import logging
from datetime import UTC, datetime
from uuid import UUID, uuid4

from fastapi import APIRouter, Depends, HTTPException, Request, status
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.auth import limiter
from app.database import get_session
from app.deps import get_admin_user, get_current_user
from app.models import (
    Emergency,
    EmergencyAuditLog,
    LiveLocationSession,
    LiveLocationSessionStatus,
    LiveLocationUpdate,
    User,
    UserRole,
)
from app.realtime import emergency_connections
from app.schemas import (
    LiveLocationSessionOut,
    LiveLocationStartInput,
    LiveLocationStopInput,
    LiveLocationUpdateInput,
    LiveLocationUpdateOut,
)

logger = logging.getLogger("bhai.live_location")

router = APIRouter(tags=["live-location"])

# Thread-safe in-memory session stores keyed independently by session_id
# User A -> Session A -> Stream A; User B -> Session B -> Stream B
IN_MEMORY_LIVE_SESSIONS: dict[str, dict] = {}
IN_MEMORY_LIVE_UPDATES: dict[str, list[dict]] = {}


def generate_navigation_url(lat: float, lon: float) -> str:
    """Universal Google Maps directions URL format with dynamic coordinates."""
    return f"https://www.google.com/maps/dir/?api=1&destination={lat},{lon}"


def session_to_out(data: dict) -> LiveLocationSessionOut:
    lat = data.get("last_latitude", data.get("initial_latitude", 0.0))
    lon = data.get("last_longitude", data.get("initial_longitude", 0.0))
    return LiveLocationSessionOut(
        id=data["id"],
        user_id=data["user_id"],
        emergency_id=data.get("emergency_id"),
        status=data["status"],
        initial_latitude=data["initial_latitude"],
        initial_longitude=data["initial_longitude"],
        initial_accuracy=data.get("initial_accuracy"),
        last_latitude=lat,
        last_longitude=lon,
        last_accuracy=data.get("last_accuracy"),
        started_at=data["started_at"],
        last_updated_at=data["last_updated_at"],
        ended_at=data.get("ended_at"),
        navigation_url=generate_navigation_url(lat, lon),
    )


@router.post(
    "/live-location/start",
    response_model=LiveLocationSessionOut,
    status_code=status.HTTP_201_CREATED,
)
@router.post(
    "/api/live-location/start",
    response_model=LiveLocationSessionOut,
    status_code=status.HTTP_201_CREATED,
)
@limiter.limit("30/minute")
async def start_live_location(
    request: Request,
    payload: LiveLocationStartInput,
    user: User = Depends(get_current_user),
    session: AsyncSession = Depends(get_session),
) -> LiveLocationSessionOut:
    """Create an independent live-location session for the authenticated user."""
    session_id = uuid4()
    now = datetime.now(UTC)

    session_data = {
        "id": session_id,
        "user_id": user.id,
        "emergency_id": payload.emergency_id,
        "status": LiveLocationSessionStatus.ACTIVE.value,
        "initial_latitude": payload.latitude,
        "initial_longitude": payload.longitude,
        "initial_accuracy": payload.accuracy or 10.0,
        "last_latitude": payload.latitude,
        "last_longitude": payload.longitude,
        "last_accuracy": payload.accuracy or 10.0,
        "started_at": now,
        "last_updated_at": now,
        "ended_at": None,
    }
    IN_MEMORY_LIVE_SESSIONS[str(session_id)] = session_data
    IN_MEMORY_LIVE_UPDATES[str(session_id)] = [
        {
            "id": uuid4(),
            "session_id": session_id,
            "user_id": user.id,
            "latitude": payload.latitude,
            "longitude": payload.longitude,
            "accuracy": payload.accuracy or 10.0,
            "recorded_at": now,
        }
    ]

    try:
        db_session = LiveLocationSession(
            id=session_id,
            user_id=user.id,
            emergency_id=payload.emergency_id,
            status=LiveLocationSessionStatus.ACTIVE.value,
            initial_latitude=payload.latitude,
            initial_longitude=payload.longitude,
            initial_accuracy=payload.accuracy,
            last_latitude=payload.latitude,
            last_longitude=payload.longitude,
            last_accuracy=payload.accuracy,
            started_at=now,
            last_updated_at=now,
        )
        session.add(db_session)
        session.add(
            LiveLocationUpdate(
                id=uuid4(),
                session_id=session_id,
                user_id=user.id,
                latitude=payload.latitude,
                longitude=payload.longitude,
                accuracy=payload.accuracy,
                recorded_at=now,
            )
        )
        await session.commit()
    except Exception as exc:
        logger.debug("Database write skipped in fallback mode: %s", exc)

    broadcast_payload = {
        "event": "live_location_started",
        "session_id": str(session_id),
        "user_id": str(user.id),
        "emergency_id": str(payload.emergency_id) if payload.emergency_id else None,
        "latitude": payload.latitude,
        "longitude": payload.longitude,
        "accuracy": payload.accuracy or 10.0,
        "navigation_url": generate_navigation_url(payload.latitude, payload.longitude),
        "started_at": now.isoformat(),
    }
    if payload.emergency_id:
        await emergency_connections.broadcast(payload.emergency_id, "live_location_started", broadcast_payload)
    await emergency_connections.broadcast_to_admin("live_location_started", broadcast_payload)

    return session_to_out(session_data)


@router.post(
    "/live-location/update",
    response_model=LiveLocationUpdateOut,
    status_code=status.HTTP_200_OK,
)
@router.post(
    "/api/live-location/update",
    response_model=LiveLocationUpdateOut,
    status_code=status.HTTP_200_OK,
)
@limiter.limit("120/minute")
async def update_live_location(
    request: Request,
    payload: LiveLocationUpdateInput,
    user: User = Depends(get_current_user),
    session: AsyncSession = Depends(get_session),
) -> LiveLocationUpdateOut:
    """Record a 5-second location update. Validates session ownership and is non-blocking."""
    session_id_str = str(payload.session_id)
    now = payload.timestamp if payload.timestamp else datetime.now(UTC)
    now_utc = now if now.tzinfo else now.replace(tzinfo=UTC)

    # In-memory lookup and ownership check
    mem_session = IN_MEMORY_LIVE_SESSIONS.get(session_id_str)
    if mem_session:
        if mem_session["user_id"] != user.id and user.role != UserRole.ADMIN.value:
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="You do not own this live-location session",
            )
        if mem_session["status"] != LiveLocationSessionStatus.ACTIVE.value:
            raise HTTPException(
                status_code=status.HTTP_409_CONFLICT,
                detail="This live-location session is no longer active",
            )
        mem_session["last_latitude"] = payload.latitude
        mem_session["last_longitude"] = payload.longitude
        mem_session["last_accuracy"] = payload.accuracy or 10.0
        mem_session["last_updated_at"] = now_utc

    update_id = uuid4()
    update_data = {
        "id": update_id,
        "session_id": payload.session_id,
        "user_id": user.id,
        "latitude": payload.latitude,
        "longitude": payload.longitude,
        "accuracy": payload.accuracy or 10.0,
        "recorded_at": now_utc,
    }

    if session_id_str in IN_MEMORY_LIVE_UPDATES:
        updates = IN_MEMORY_LIVE_UPDATES[session_id_str]
        updates.append(update_data)
        # Keep maximum 100 historical breadcrumbs in memory per session
        if len(updates) > 100:
            del updates[0]
    else:
        IN_MEMORY_LIVE_UPDATES[session_id_str] = [update_data]

    # Database synchronization
    try:
        db_session = await session.get(LiveLocationSession, payload.session_id)
        if db_session:
            if db_session.user_id != user.id and user.role != UserRole.ADMIN.value:
                raise HTTPException(
                    status_code=status.HTTP_403_FORBIDDEN,
                    detail="You do not own this live-location session",
                )
            if db_session.status != LiveLocationSessionStatus.ACTIVE.value:
                raise HTTPException(
                    status_code=status.HTTP_409_CONFLICT,
                    detail="This live-location session is no longer active",
                )
            db_session.last_latitude = payload.latitude
            db_session.last_longitude = payload.longitude
            db_session.last_accuracy = payload.accuracy
            db_session.last_updated_at = now_utc

            session.add(
                LiveLocationUpdate(
                    id=update_id,
                    session_id=payload.session_id,
                    user_id=user.id,
                    latitude=payload.latitude,
                    longitude=payload.longitude,
                    accuracy=payload.accuracy,
                    recorded_at=now_utc,
                )
            )
            await session.commit()
    except HTTPException:
        raise
    except Exception as exc:
        logger.debug("Database update skipped in fallback mode: %s", exc)

    # Realtime broadcast to admin and emergency channels
    broadcast_payload = {
        "session_id": session_id_str,
        "user_id": str(user.id),
        "latitude": payload.latitude,
        "longitude": payload.longitude,
        "accuracy": payload.accuracy or 10.0,
        "navigation_url": generate_navigation_url(payload.latitude, payload.longitude),
        "timestamp": now_utc.isoformat(),
    }
    emergency_id = mem_session.get("emergency_id") if mem_session else None
    if emergency_id:
        await emergency_connections.broadcast(emergency_id, "live_location_updated", broadcast_payload)
    await emergency_connections.broadcast_to_admin("live_location_updated", broadcast_payload)

    return LiveLocationUpdateOut(**update_data)


@router.post(
    "/live-location/stop",
    response_model=LiveLocationSessionOut,
    status_code=status.HTTP_200_OK,
)
@router.post(
    "/api/live-location/stop",
    response_model=LiveLocationSessionOut,
    status_code=status.HTTP_200_OK,
)
async def stop_live_location(
    payload: LiveLocationStopInput,
    user: User = Depends(get_current_user),
    session: AsyncSession = Depends(get_session),
) -> LiveLocationSessionOut:
    """Explicitly terminate an active live-location session."""
    session_id_str = str(payload.session_id)
    now = datetime.now(UTC)

    mem_session = IN_MEMORY_LIVE_SESSIONS.get(session_id_str)
    if mem_session:
        if mem_session["user_id"] != user.id and user.role != UserRole.ADMIN.value:
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="You do not own this live-location session",
            )
        mem_session["status"] = LiveLocationSessionStatus.STOPPED.value
        mem_session["ended_at"] = now
        session_out = session_to_out(mem_session)
    else:
        session_out = None

    try:
        db_session = await session.get(LiveLocationSession, payload.session_id)
        if db_session:
            if db_session.user_id != user.id and user.role != UserRole.ADMIN.value:
                raise HTTPException(
                    status_code=status.HTTP_403_FORBIDDEN,
                    detail="You do not own this live-location session",
                )
            db_session.status = LiveLocationSessionStatus.STOPPED.value
            db_session.ended_at = now
            await session.commit()
            lat = db_session.last_latitude
            lon = db_session.last_longitude
            session_out = LiveLocationSessionOut(
                id=db_session.id,
                user_id=db_session.user_id,
                emergency_id=db_session.emergency_id,
                status=db_session.status,
                initial_latitude=db_session.initial_latitude,
                initial_longitude=db_session.initial_longitude,
                initial_accuracy=db_session.initial_accuracy,
                last_latitude=lat,
                last_longitude=lon,
                last_accuracy=db_session.last_accuracy,
                started_at=db_session.started_at,
                last_updated_at=db_session.last_updated_at,
                ended_at=now,
                navigation_url=generate_navigation_url(lat, lon),
            )
    except HTTPException:
        raise
    except Exception as exc:
        logger.debug("Database session close skipped in fallback mode: %s", exc)

    if session_out is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Live-location session was not found",
        )

    broadcast_payload = {
        "session_id": session_id_str,
        "user_id": str(user.id),
        "status": "STOPPED",
        "ended_at": now.isoformat(),
    }
    if mem_session and mem_session.get("emergency_id"):
        await emergency_connections.broadcast(mem_session["emergency_id"], "live_location_stopped", broadcast_payload)
    await emergency_connections.broadcast_to_admin("live_location_stopped", broadcast_payload)

    return session_out


@router.get(
    "/live-location/{session_id}",
    response_model=LiveLocationSessionOut,
)
@router.get(
    "/api/live-location/{session_id}",
    response_model=LiveLocationSessionOut,
)
async def get_live_location(
    session_id: UUID,
    user: User = Depends(get_current_user),
    session: AsyncSession = Depends(get_session),
) -> LiveLocationSessionOut:
    """Retrieve details for a specific live-location session."""
    session_id_str = str(session_id)
    mem = IN_MEMORY_LIVE_SESSIONS.get(session_id_str)
    if mem:
        if mem["user_id"] != user.id and user.role != UserRole.ADMIN.value:
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="You are not authorized to view this location session",
            )
        return session_to_out(mem)

    try:
        db_session = await session.get(LiveLocationSession, session_id)
        if db_session:
            if db_session.user_id != user.id and user.role != UserRole.ADMIN.value:
                raise HTTPException(
                    status_code=status.HTTP_403_FORBIDDEN,
                    detail="You are not authorized to view this location session",
                )
            lat = db_session.last_latitude
            lon = db_session.last_longitude
            return LiveLocationSessionOut(
                id=db_session.id,
                user_id=db_session.user_id,
                emergency_id=db_session.emergency_id,
                status=db_session.status,
                initial_latitude=db_session.initial_latitude,
                initial_longitude=db_session.initial_longitude,
                initial_accuracy=db_session.initial_accuracy,
                last_latitude=lat,
                last_longitude=lon,
                last_accuracy=db_session.last_accuracy,
                started_at=db_session.started_at,
                last_updated_at=db_session.last_updated_at,
                ended_at=db_session.ended_at,
                navigation_url=generate_navigation_url(lat, lon),
            )
    except HTTPException:
        raise
    except Exception:
        pass

    raise HTTPException(
        status_code=status.HTTP_404_NOT_FOUND,
        detail="Live-location session was not found",
    )


@router.get(
    "/admin/live-locations",
    response_model=list[LiveLocationSessionOut],
)
@router.get(
    "/api/admin/live-locations",
    response_model=list[LiveLocationSessionOut],
)
async def list_admin_live_locations(
    _: User = Depends(get_admin_user),
    session: AsyncSession = Depends(get_session),
) -> list[LiveLocationSessionOut]:
    """Admin endpoint to monitor all active live-location sessions with navigation URLs."""
    results: list[LiveLocationSessionOut] = []

    # Collect from memory
    for mem in IN_MEMORY_LIVE_SESSIONS.values():
        if mem.get("status") == LiveLocationSessionStatus.ACTIVE.value:
            results.append(session_to_out(mem))

    # Collect from DB
    try:
        active_sessions = (
            await session.scalars(
                select(LiveLocationSession)
                .where(LiveLocationSession.status == LiveLocationSessionStatus.ACTIVE.value)
                .order_by(LiveLocationSession.last_updated_at.desc())
                .limit(100)
            )
        ).all()
        for s in active_sessions:
            if not any(str(r.id) == str(s.id) for r in results):
                lat = s.last_latitude
                lon = s.last_longitude
                results.append(
                    LiveLocationSessionOut(
                        id=s.id,
                        user_id=s.user_id,
                        emergency_id=s.emergency_id,
                        status=s.status,
                        initial_latitude=s.initial_latitude,
                        initial_longitude=s.initial_longitude,
                        initial_accuracy=s.initial_accuracy,
                        last_latitude=lat,
                        last_longitude=lon,
                        last_accuracy=s.last_accuracy,
                        started_at=s.started_at,
                        last_updated_at=s.last_updated_at,
                        ended_at=s.ended_at,
                        navigation_url=generate_navigation_url(lat, lon),
                    )
                )
    except Exception:
        pass

    return results
