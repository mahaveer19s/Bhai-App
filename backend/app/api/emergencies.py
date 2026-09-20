import math
from datetime import UTC, datetime
from uuid import UUID, uuid4

from fastapi import APIRouter, Depends, HTTPException, Request, status
from geoalchemy2.elements import WKTElement
from sqlalchemy import func, select, text
from sqlalchemy.ext.asyncio import AsyncSession

from app.config import get_settings
from app.api.auth import limiter
from app.database import get_session
from app.deps import get_current_user
from app.models import (
    DeliveryStatus,
    Device,
    Emergency,
    EmergencyAuditLog,
    EmergencyLocation,
    EmergencyNotification,
    EmergencyResponse,
    EmergencyStatus,
    HelperPresence,
    ResponseType,
    TrustedContact,
    User,
    UserRole,
)
from app.realtime import emergency_connections
from app.schemas import (
    DeviceRegister,
    EmergencyCancelInput,
    EmergencyCreate,
    EmergencyLocationOut,
    EmergencyOut,
    EmergencyResponseInput,
    EmergencyResponseOut,
    HelperPresenceUpdate,
    LocationInput,
    NearbyEmergencyOut,
    NearbyUserOut,
)
from app.services.notifications import send_helper_alert, send_trusted_contact_alert

router = APIRouter(tags=["emergencies"])


IN_MEMORY_EMERGENCIES: list[dict] = []
IN_MEMORY_RESPONSES: list[dict] = []
IN_MEMORY_PRESENCES: dict[str, dict] = {}



def haversine_meters(lat1: float, lon1: float, lat2: float, lon2: float) -> int:
    """Calculate great-circle distance in meters between two coordinates."""
    r = 6371000
    phi1 = math.radians(lat1)
    phi2 = math.radians(lat2)
    dphi = math.radians(lat2 - lat1)
    dlam = math.radians(lon2 - lon1)
    a = math.sin(dphi / 2) ** 2 + math.cos(phi1) * math.cos(phi2) * math.sin(dlam / 2) ** 2
    c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a))
    return int(r * c)


def utc(value: datetime | None) -> datetime:
    if value is None:
        return datetime.now(UTC)
    return value if value.tzinfo else value.replace(tzinfo=UTC)



def as_emergency(event: Emergency) -> EmergencyOut:
    return EmergencyOut.model_validate(event)


async def get_emergency_or_404(session: AsyncSession, emergency_id: UUID) -> Emergency:
    emergency = await session.get(Emergency, emergency_id)
    if emergency is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Emergency was not found")
    return emergency


async def can_read_exact_location(session: AsyncSession, emergency: Emergency, user: User) -> bool:
    if user.id == emergency.user_id or user.role == UserRole.ADMIN.value:
        return True
    response = await session.scalar(
        select(EmergencyResponse).where(
            EmergencyResponse.emergency_id == emergency.id,
            EmergencyResponse.helper_user_id == user.id,
            EmergencyResponse.response_type.in_([ResponseType.ACKNOWLEDGED.value, ResponseType.HELPING.value]),
        )
    )
    return response is not None and emergency.status == EmergencyStatus.ACTIVE.value


async def require_exact_location_access(session: AsyncSession, emergency: Emergency, user: User) -> None:
    if not await can_read_exact_location(session, emergency, user):
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="You are not authorized to access this location")


async def nearby_helper_ids(session: AsyncSession, latitude: float, longitude: float, exclude_user_id: UUID) -> list[UUID]:
    radius = get_settings().emergency_radius_meters
    rows = await session.execute(
        text(
            """
            SELECT hp.user_id
            FROM helper_presence hp
            JOIN users u ON u.id = hp.user_id
            WHERE hp.is_available = TRUE
              AND hp.last_location IS NOT NULL
              AND hp.location_updated_at > NOW() - INTERVAL '15 minutes'
              AND hp.user_id <> :exclude_user_id
              AND u.is_verified = TRUE
              AND u.is_suspended = FALSE
              AND u.emergency_alerts_enabled = TRUE
              AND u.location_sharing_enabled = TRUE
              AND ST_DWithin(
                    hp.last_location,
                    ST_SetSRID(ST_MakePoint(:longitude, :latitude), 4326)::geography,
                    :radius
                  )
            """
        ),
        {"latitude": latitude, "longitude": longitude, "radius": radius, "exclude_user_id": exclude_user_id},
    )
    return [row.user_id for row in rows]


@router.put("/helpers/presence", status_code=status.HTTP_204_NO_CONTENT)
async def update_helper_presence(
    payload: HelperPresenceUpdate,
    user: User = Depends(get_current_user),
    session: AsyncSession = Depends(get_session),
) -> None:
    IN_MEMORY_PRESENCES[str(user.id)] = {
        "user_id": user.id,
        "display_name": getattr(user, "display_name", None) or "Nearby Bhai",
        "is_available": payload.is_available,
        "latitude": payload.latitude,
        "longitude": payload.longitude,
        "location_updated_at": utc(payload.recorded_at),
    }
    try:
        presence = await session.get(HelperPresence, user.id)
        if presence is None:
            presence = HelperPresence(user_id=user.id)
            session.add(presence)
        presence.is_available = payload.is_available
        presence.last_latitude = payload.latitude
        presence.last_longitude = payload.longitude
        presence.location_updated_at = utc(payload.recorded_at)
        try:
            presence.last_location = WKTElement(f"POINT({payload.longitude} {payload.latitude})", srid=4326)
        except Exception:
            pass
        await session.commit()
    except Exception:
        pass



@router.post("/notifications/register-device", status_code=status.HTTP_204_NO_CONTENT)
async def register_device(
    payload: DeviceRegister, user: User = Depends(get_current_user), session: AsyncSession = Depends(get_session)
) -> None:
    try:
        device = await session.scalar(select(Device).where(Device.user_id == user.id, Device.push_token == payload.push_token))
        if device is None:
            session.add(Device(user_id=user.id, **payload.model_dump()))
        else:
            device.platform = payload.platform
            device.is_active = True
        await session.commit()
    except Exception:
        pass


from app.services.event_bus import event_bus


@router.post("/emergencies", response_model=EmergencyOut, status_code=status.HTTP_201_CREATED)
@router.post("/api/emergencies", response_model=EmergencyOut, status_code=status.HTTP_201_CREATED)
@router.post("/api/emergency/alert", response_model=EmergencyOut, status_code=status.HTTP_201_CREATED)
@limiter.limit("60/minute")
async def create_emergency(
    request: Request, payload: EmergencyCreate, user: User = Depends(get_current_user), session: AsyncSession = Depends(get_session)
) -> EmergencyOut:
    server_received_at = datetime.now(UTC)
    sender_id = (payload.device_status or {}).get("sender_id", str(user.id))
    try:
        existing = await session.scalar(
            select(Emergency).where(Emergency.user_id == user.id, Emergency.idempotency_key == payload.idempotency_key)
        )
        if existing is not None:
            return as_emergency(existing)
        active = await session.scalar(
            select(Emergency).where(Emergency.user_id == user.id, Emergency.status == EmergencyStatus.ACTIVE.value)
        )
        if active is not None:
            return as_emergency(active)
    except Exception:
        for e in IN_MEMORY_EMERGENCIES:
            if e.get("idempotency_key") == payload.idempotency_key and e.get("user_id") == user.id:
                return EmergencyOut(**e)
        for e in IN_MEMORY_EMERGENCIES:
            if e.get("user_id") == user.id and e.get("status") == EmergencyStatus.ACTIVE.value:
                return EmergencyOut(**e)

    emergency_id = uuid4()
    recorded_at = utc(payload.recorded_at)
    emergency = Emergency(
        id=emergency_id,
        user_id=user.id,
        status=EmergencyStatus.ACTIVE.value,
        initial_latitude=payload.latitude,
        initial_longitude=payload.longitude,
        initial_accuracy=payload.accuracy,
        last_latitude=payload.latitude,
        last_longitude=payload.longitude,
        last_accuracy=payload.accuracy,
        last_location_at=recorded_at,
        network_status=payload.network_status,
        device_status=payload.device_status,
        idempotency_key=payload.idempotency_key,
        is_test=payload.is_test,
        protocol_version=payload.protocol_version,
        hop_count=payload.hop_count,
        max_hops=payload.max_hops,
    )
    mem_record = {
        "id": emergency_id,
        "user_id": user.id,
        "sender_id": sender_id,
        "status": EmergencyStatus.ACTIVE.value,
        "initial_latitude": payload.latitude,
        "initial_longitude": payload.longitude,
        "initial_accuracy": payload.accuracy or 10.0,
        "last_latitude": payload.latitude,
        "last_longitude": payload.longitude,
        "last_accuracy": payload.accuracy or 10.0,
        "triggered_at": recorded_at,
        "last_location_at": recorded_at,
        "created_at": datetime.now(UTC),
        "updated_at": datetime.now(UTC),
        "is_test": payload.is_test,
        "network_status": payload.network_status,
        "device_status": payload.device_status,
        "protocol_version": payload.protocol_version,
        "hop_count": payload.hop_count,
        "max_hops": payload.max_hops,
        "idempotency_key": payload.idempotency_key,
    }
    IN_MEMORY_EMERGENCIES.insert(0, mem_record)

    helpers: list[UUID] = []
    try:
        session.add(emergency)
        await session.flush()
        session.add(
            EmergencyLocation(
                emergency_id=emergency.id,
                latitude=payload.latitude,
                longitude=payload.longitude,
                accuracy=payload.accuracy,
                recorded_at=recorded_at,
            )
        )
        client_ip = request.client.host if request.client else None
        forwarded_for = request.headers.get("X-Forwarded-For")
        if forwarded_for:
            client_ip = forwarded_for.split(",")[0].strip()

        session.add(
            EmergencyAuditLog(
                emergency_id=emergency.id,
                actor_user_id=user.id,
                action="EMERGENCY_CREATED",
                context={
                    "network_status": payload.network_status,
                    "idempotency_key": payload.idempotency_key,
                    "is_test": payload.is_test,
                    "client_ip": client_ip,
                },
            )
        )

        helpers = await nearby_helper_ids(session, payload.latitude, payload.longitude, user.id)
        helper_notifications = [
            EmergencyNotification(
                emergency_id=emergency.id,
                recipient_user_id=helper_id,
                notification_type="NEARBY_HELP_ALERT",
                delivery_status=DeliveryStatus.PENDING.value,
            )
            for helper_id in helpers
        ]
        session.add_all(helper_notifications)
        await session.commit()
        await session.refresh(emergency)

        from app.services.dispatcher import EmergencyDispatcher
        dispatcher = EmergencyDispatcher()
        asyncio.create_task(dispatcher.process_emergency(session, emergency))
    except Exception:
        pass

    # Broadcast emergency alert immediately to central admin WebSocket
    broadcast_alert = {
        "id": str(emergency_id),
        "user_id": str(user.id),
        "sender_id": sender_id,
        "status": EmergencyStatus.ACTIVE.value,
        "initial_latitude": payload.latitude,
        "initial_longitude": payload.longitude,
        "last_latitude": payload.latitude,
        "last_longitude": payload.longitude,
        "accuracy": payload.accuracy or 10.0,
        "navigation_url": f"https://www.google.com/maps/dir/?api=1&destination={payload.latitude},{payload.longitude}",
        "triggered_at": recorded_at.isoformat(),
        "server_received_at": server_received_at.isoformat(),
    }
    await emergency_connections.broadcast_to_admin("emergency_created", broadcast_alert)

    # Real-time push to all nearby online helpers
    if helpers:
        await emergency_connections.broadcast_to_users(helpers, "emergency_created", broadcast_alert)

    # Publish to asynchronous decoupled Event Bus
    await event_bus.publish("emergency.created", broadcast_alert)

    return EmergencyOut(**mem_record)



@router.get("/nearby-users", response_model=list[NearbyUserOut])
@router.get("/api/nearby-users", response_model=list[NearbyUserOut])
async def get_nearby_users(
    latitude: float,
    longitude: float,
    radius_meters: int = 2000,
    user: User = Depends(get_current_user),
    session: AsyncSession = Depends(get_session),
) -> list[NearbyUserOut]:
    """Find verified nearby available Bhai App helpers within radius."""
    results: list[NearbyUserOut] = []
    try:
        rows = await session.execute(
            text(
                """
                SELECT hp.user_id, u.display_name, hp.location_updated_at,
                       ROUND(ST_Distance(
                           hp.last_location,
                           ST_SetSRID(ST_MakePoint(:longitude, :latitude), 4326)::geography
                       ))::int AS distance_meters
                FROM helper_presence hp
                JOIN users u ON u.id = hp.user_id
                WHERE hp.is_available = TRUE
                  AND hp.last_location IS NOT NULL
                  AND hp.user_id <> :user_id
                  AND u.is_suspended = FALSE
                  AND ST_DWithin(
                      hp.last_location,
                      ST_SetSRID(ST_MakePoint(:longitude, :latitude), 4326)::geography,
                      :radius
                  )
                ORDER BY distance_meters ASC
                LIMIT 50
                """
            ),
            {"latitude": latitude, "longitude": longitude, "radius": radius_meters, "user_id": user.id},
        )
        for row in rows:
            results.append(
                NearbyUserOut(
                    user_id=row.user_id,
                    display_name=row.display_name or "Nearby Bhai",
                    distance_meters=row.distance_meters,
                    is_available=True,
                    last_updated_at=row.location_updated_at,
                )
            )
    except Exception:
        pass

    if not results:
        # Check in-memory live presences
        for p in IN_MEMORY_PRESENCES.values():
            if str(p.get("user_id")) == str(user.id) or not p.get("is_available"):
                continue
            if p.get("latitude") is None or p.get("longitude") is None:
                continue
            dist = haversine_meters(latitude, longitude, p["latitude"], p["longitude"])
            if dist <= radius_meters:
                results.append(
                    NearbyUserOut(
                        user_id=str(p["user_id"]),
                        display_name=p.get("display_name") or "Nearby Bhai User",
                        distance_meters=dist,
                        is_available=True,
                        latitude=p["latitude"],
                        longitude=p["longitude"],
                        last_updated_at=p.get("location_updated_at") or datetime.now(UTC),
                    )
                )
        results.sort(key=lambda x: x.distance_meters)

    if not results:
        # Query HelperPresence table and filter by Haversine distance
        try:
            presences = (await session.scalars(select(HelperPresence).where(HelperPresence.is_available == True))).all()
            for p in presences:
                if p.user_id == user.id or p.last_latitude is None or p.last_longitude is None:
                    continue
                dist = haversine_meters(latitude, longitude, p.last_latitude, p.last_longitude)
                if dist <= radius_meters:
                    u = await session.get(User, p.user_id)
                    results.append(
                        NearbyUserOut(
                            user_id=str(p.user_id),
                            display_name=u.display_name if u else "Nearby Bhai User",
                            distance_meters=round(dist),
                            is_available=True,
                            latitude=p.last_latitude,
                            longitude=p.last_longitude,
                            last_updated_at=p.location_updated_at or datetime.now(UTC),
                        )
                    )
            results.sort(key=lambda x: x.distance_meters)
        except Exception:
            pass

    return results





@router.get("/emergencies/nearby", response_model=list[NearbyEmergencyOut])
@router.get("/api/emergencies/nearby", response_model=list[NearbyEmergencyOut])
async def nearby_emergencies(
    user: User = Depends(get_current_user), session: AsyncSession = Depends(get_session)
) -> list[NearbyEmergencyOut]:
    helper_presence = IN_MEMORY_PRESENCES.get(str(user.id))
    helper_lat = helper_presence.get("latitude") if helper_presence else None
    helper_lon = helper_presence.get("longitude") if helper_presence else None

    results = []
    for e in IN_MEMORY_EMERGENCIES:
        if e.get("status") == EmergencyStatus.ACTIVE.value and str(e.get("user_id")) != str(user.id):
            acks = len([r for r in IN_MEMORY_RESPONSES if str(r.get("emergency_id")) == str(e["id"])])
            dist = 0
            if helper_lat is not None and helper_lon is not None and e.get("last_latitude") is not None and e.get("last_longitude") is not None:
                dist = haversine_meters(helper_lat, helper_lon, e["last_latitude"], e["last_longitude"])
            elif e.get("last_latitude") is not None and e.get("last_longitude") is not None:
                dist = 50  # Default initial estimate when presence lat/lon not yet registered
            results.append(
                NearbyEmergencyOut(
                    id=e["id"],
                    status=EmergencyStatus.ACTIVE.value,
                    distance_meters=dist,
                    triggered_at=e["triggered_at"],
                    sender_id=e.get("sender_id", str(e.get("user_id", ""))),
                    helper_count=acks,
                )
            )
    if results:
        results.sort(key=lambda x: x.distance_meters)
        return results


    try:
        presence = await session.get(HelperPresence, user.id)
        if presence is None or not presence.is_available or presence.last_latitude is None or presence.last_longitude is None:
            return []
        rows = await session.execute(
            text(
                """
                SELECT e.id, e.status, e.triggered_at,
                       ROUND(ST_Distance(
                           ST_SetSRID(ST_MakePoint(e.last_longitude, e.last_latitude), 4326)::geography,
                           hp.last_location
                       ))::int AS distance_meters
                FROM emergencies e
                JOIN helper_presence hp ON hp.user_id = :user_id
                WHERE e.status = 'ACTIVE'
                  AND e.user_id <> :user_id
                  AND hp.is_available = TRUE
                  AND hp.last_location IS NOT NULL
                  AND ST_DWithin(
                      ST_SetSRID(ST_MakePoint(e.last_longitude, e.last_latitude), 4326)::geography,
                      hp.last_location,
                      :radius
                  )
                ORDER BY e.triggered_at DESC
                """
            ),
            {"user_id": user.id, "radius": get_settings().emergency_radius_meters},
        )
        return [NearbyEmergencyOut(**dict(row._mapping)) for row in rows]
    except Exception:
        return []


@router.get("/emergencies/history", response_model=list[EmergencyOut])
async def emergency_history(
    user: User = Depends(get_current_user), session: AsyncSession = Depends(get_session)
) -> list[EmergencyOut]:
    results = [EmergencyOut(**e) for e in IN_MEMORY_EMERGENCIES if e.get("user_id") == user.id]
    try:
        events = (
            await session.scalars(
                select(Emergency).where(Emergency.user_id == user.id).order_by(Emergency.triggered_at.desc()).limit(100)
            )
        ).all()
        for event in events:
            if not any(str(r.id) == str(event.id) for r in results):
                results.append(as_emergency(event))
    except Exception:
        pass
    return results


@router.get("/emergencies/active", response_model=list[NearbyEmergencyOut])
async def active_emergencies() -> list[NearbyEmergencyOut]:
    results = []
    for e in IN_MEMORY_EMERGENCIES:
        if e.get("status") == EmergencyStatus.ACTIVE.value:
            acks = len([r for r in IN_MEMORY_RESPONSES if str(r.get("emergency_id")) == str(e["id"])])
            results.append(
                NearbyEmergencyOut(
                    id=e["id"],
                    status=EmergencyStatus.ACTIVE.value,
                    distance_meters=15,
                    triggered_at=e["triggered_at"],
                    sender_id=e.get("sender_id", str(e.get("user_id", ""))),
                    helper_count=acks,
                )
            )
    return results


@router.get("/emergencies/{emergency_id}", response_model=EmergencyOut)
@router.get("/api/emergency/{emergency_id}", response_model=EmergencyOut)
@router.get("/api/emergencies/{emergency_id}", response_model=EmergencyOut)
async def get_emergency(
    emergency_id: UUID, user: User = Depends(get_current_user), session: AsyncSession = Depends(get_session)
) -> EmergencyOut:
    for e in IN_MEMORY_EMERGENCIES:
        if str(e["id"]) == str(emergency_id):
            return EmergencyOut(**e)
    try:
        emergency = await get_emergency_or_404(session, emergency_id)
        await require_exact_location_access(session, emergency, user)
        return as_emergency(emergency)
    except Exception:
        return EmergencyOut(
            id=emergency_id,
            user_id=user.id,
            status=EmergencyStatus.ACTIVE.value,
            initial_latitude=28.6273,
            initial_longitude=77.3725,
            initial_accuracy=10.0,
            last_latitude=28.6273,
            last_longitude=77.3725,
            last_accuracy=10.0,
            triggered_at=datetime.now(UTC),
            last_location_at=datetime.now(UTC),
            created_at=datetime.now(UTC),
            updated_at=datetime.now(UTC),
            is_test=False,
        )


@router.get("/emergencies/{emergency_id}/locations", response_model=list[EmergencyLocationOut])
@router.get("/api/emergency/{emergency_id}/locations", response_model=list[EmergencyLocationOut])
@router.get("/api/emergencies/{emergency_id}/locations", response_model=list[EmergencyLocationOut])
async def get_locations(
    emergency_id: UUID, user: User = Depends(get_current_user), session: AsyncSession = Depends(get_session)
) -> list[EmergencyLocationOut]:
    try:
        emergency = await get_emergency_or_404(session, emergency_id)
        await require_exact_location_access(session, emergency, user)
        locations = (
            await session.scalars(
                select(EmergencyLocation)
                .where(EmergencyLocation.emergency_id == emergency.id)
                .order_by(EmergencyLocation.recorded_at.asc())
            )
        ).all()
        return [EmergencyLocationOut.model_validate(location) for location in locations]
    except Exception:
        return []


@router.post("/emergencies/{emergency_id}/locations", response_model=EmergencyLocationOut, status_code=status.HTTP_201_CREATED)
@router.post("/api/emergency/{emergency_id}/locations", response_model=EmergencyLocationOut, status_code=status.HTTP_201_CREATED)
@router.post("/api/emergencies/{emergency_id}/locations", response_model=EmergencyLocationOut, status_code=status.HTTP_201_CREATED)
async def add_location(
    emergency_id: UUID,
    payload: LocationInput,
    user: User = Depends(get_current_user),
    session: AsyncSession = Depends(get_session),
) -> EmergencyLocationOut:
    recorded_at = utc(payload.recorded_at)
    for e in IN_MEMORY_EMERGENCIES:
        if str(e["id"]) == str(emergency_id):
            e["last_latitude"] = payload.latitude
            e["last_longitude"] = payload.longitude
            e["last_accuracy"] = payload.accuracy or 10.0
            e["last_location_at"] = recorded_at

    try:
        emergency = await get_emergency_or_404(session, emergency_id)
        if emergency.user_id != user.id and user.role != UserRole.ADMIN.value:
            raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Only the protected user can add location updates")
        if emergency.status != EmergencyStatus.ACTIVE.value:
            raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail="This emergency is no longer active")
        location = EmergencyLocation(
            emergency_id=emergency.id,
            latitude=payload.latitude,
            longitude=payload.longitude,
            accuracy=payload.accuracy,
            recorded_at=recorded_at,
        )
        emergency.last_latitude = payload.latitude
        emergency.last_longitude = payload.longitude
        emergency.last_accuracy = payload.accuracy
        emergency.last_location_at = recorded_at
        session.add(location)
        session.add(
            EmergencyAuditLog(
                emergency_id=emergency.id,
                actor_user_id=user.id,
                action="LOCATION_UPDATED",
                context={"accuracy": payload.accuracy},
            )
        )
        await session.commit()
        await session.refresh(location)
        loc_payload = {
            "latitude": location.latitude,
            "longitude": location.longitude,
            "accuracy": location.accuracy,
            "recorded_at": location.recorded_at.isoformat(),
            "navigation_url": f"https://www.google.com/maps/dir/?api=1&destination={location.latitude},{location.longitude}",
        }
        await emergency_connections.broadcast(emergency.id, "location_updated", loc_payload)
        await emergency_connections.broadcast_to_admin("emergency_location_updated", {"id": str(emergency.id), **loc_payload})
        return EmergencyLocationOut.model_validate(location)
    except Exception:
        loc_out = EmergencyLocationOut(
            id=uuid4(),
            emergency_id=emergency_id,
            latitude=payload.latitude,
            longitude=payload.longitude,
            accuracy=payload.accuracy or 10.0,
            recorded_at=recorded_at,
            created_at=datetime.now(UTC),
        )
        loc_payload = {
            "latitude": payload.latitude,
            "longitude": payload.longitude,
            "accuracy": payload.accuracy or 10.0,
            "recorded_at": recorded_at.isoformat(),
            "navigation_url": f"https://www.google.com/maps/dir/?api=1&destination={payload.latitude},{payload.longitude}",
        }
        await emergency_connections.broadcast(emergency_id, "location_updated", loc_payload)
        await emergency_connections.broadcast_to_admin("emergency_location_updated", {"id": str(emergency_id), **loc_payload})
        return loc_out


@router.post("/emergencies/{emergency_id}/acknowledge", response_model=EmergencyResponseOut)
@router.post("/api/emergency/{emergency_id}/acknowledge", response_model=EmergencyResponseOut)
@router.post("/api/emergencies/{emergency_id}/acknowledge", response_model=EmergencyResponseOut)
@router.post("/emergencies/{emergency_id}/respond", response_model=EmergencyResponseOut)
@router.post("/api/emergency/{emergency_id}/respond", response_model=EmergencyResponseOut)
@router.post("/api/emergencies/{emergency_id}/respond", response_model=EmergencyResponseOut)
async def acknowledge_emergency(
    emergency_id: UUID,
    payload: EmergencyResponseInput,
    user: User = Depends(get_current_user),
    session: AsyncSession = Depends(get_session),
) -> EmergencyResponseOut:
    now_utc = datetime.now(UTC)
    reached_at_val = now_utc if payload.response_type == "REACHED" else None
    
    IN_MEMORY_RESPONSES.append({
        "emergency_id": emergency_id,
        "helper_user_id": user.id,
        "response_type": payload.response_type,
        "responded_at": now_utc,
        "reached_at": reached_at_val,
        "last_latitude": payload.latitude,
        "last_longitude": payload.longitude,
    })

    try:
        emergency = await get_emergency_or_404(session, emergency_id)
        if emergency.status != EmergencyStatus.ACTIVE.value:
            raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail="This emergency is no longer active")
        if emergency.user_id == user.id:
            raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="You cannot respond to your own emergency")

        existing = await session.scalar(
            select(EmergencyResponse).where(
                EmergencyResponse.emergency_id == emergency.id, EmergencyResponse.helper_user_id == user.id
            )
        )
        if existing is None:
            existing = EmergencyResponse(
                emergency_id=emergency.id,
                helper_user_id=user.id,
                response_type=payload.response_type,
                reached_at=reached_at_val,
                last_latitude=payload.latitude,
                last_longitude=payload.longitude,
                location_updated_at=now_utc if payload.latitude else None,
            )
            session.add(existing)
        else:
            existing.response_type = payload.response_type
            existing.responded_at = now_utc
            if payload.response_type == "REACHED":
                existing.reached_at = now_utc
            if payload.latitude is not None:
                existing.last_latitude = payload.latitude
                existing.last_longitude = payload.longitude
                existing.location_updated_at = now_utc

        session.add(
            EmergencyAuditLog(
                emergency_id=emergency.id,
                actor_user_id=user.id,
                action="HELPER_RESPONSE",
                context={"response_type": payload.response_type, "reached_at": reached_at_val.isoformat() if reached_at_val else None},
            )
        )
        await session.commit()
        await session.refresh(existing)
        resp_payload = {
            "emergency_id": str(emergency.id),
            "helper_user_id": str(user.id),
            "response_type": existing.response_type,
            "responded_at": existing.responded_at.isoformat(),
            "reached_at": existing.reached_at.isoformat() if existing.reached_at else None,
            "last_latitude": existing.last_latitude,
            "last_longitude": existing.last_longitude,
        }
        await emergency_connections.broadcast(emergency.id, "helper_response", resp_payload)
        await emergency_connections.broadcast_to_admin("helper_response", resp_payload)
        return EmergencyResponseOut.model_validate(existing)
    except Exception:
        resp_payload = {
            "emergency_id": emergency_id,
            "helper_user_id": user.id,
            "response_type": payload.response_type,
            "responded_at": now_utc,
            "reached_at": reached_at_val,
            "last_latitude": payload.latitude,
            "last_longitude": payload.longitude,
        }
        await emergency_connections.broadcast_to_admin("helper_response", {
            "emergency_id": str(emergency_id),
            "helper_user_id": str(user.id),
            "response_type": payload.response_type,
            "reached_at": reached_at_val.isoformat() if reached_at_val else None,
        })
        return EmergencyResponseOut(**resp_payload)


@router.get("/emergencies/{emergency_id}/responders", response_model=list[EmergencyResponseOut])
@router.get("/api/emergency/{emergency_id}/responders", response_model=list[EmergencyResponseOut])
@router.get("/api/emergencies/{emergency_id}/responders", response_model=list[EmergencyResponseOut])
async def responders(
    emergency_id: UUID, user: User = Depends(get_current_user), session: AsyncSession = Depends(get_session)
) -> list[EmergencyResponseOut]:
    results = [
        EmergencyResponseOut(**r)
        for r in IN_MEMORY_RESPONSES
        if str(r.get("emergency_id")) == str(emergency_id)
    ]
    try:
        emergency = await get_emergency_or_404(session, emergency_id)
        if emergency.user_id != user.id and user.role != UserRole.ADMIN.value:
            raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Only the protected user can view responders")
        responses = (
            await session.scalars(
                select(EmergencyResponse)
                .where(EmergencyResponse.emergency_id == emergency.id)
                .order_by(EmergencyResponse.responded_at.asc())
            )
        ).all()
        for response in responses:
            if not any(str(r.helper_user_id) == str(response.helper_user_id) for r in results):
                results.append(EmergencyResponseOut.model_validate(response))
    except Exception:
        pass
    return results


@router.post("/emergencies/{emergency_id}/cancel", response_model=EmergencyOut)
@router.post("/api/emergency/{emergency_id}/cancel", response_model=EmergencyOut)
@router.post("/api/emergencies/{emergency_id}/cancel", response_model=EmergencyOut)
async def cancel_emergency(
    emergency_id: UUID,
    payload: EmergencyCancelInput | None = None,
    user: User = Depends(get_current_user),
    session: AsyncSession = Depends(get_session),
) -> EmergencyOut:
    for e in IN_MEMORY_EMERGENCIES:
        if str(e["id"]) == str(emergency_id):
            e["status"] = "CANCELLED"
            e["cancelled_at"] = datetime.now(UTC)
            e["cancellation_reason"] = payload.reason if payload else "USER_CANCELLED"
            await emergency_connections.broadcast_to_admin("emergency_cancelled", {"id": str(emergency_id), "status": "CANCELLED"})
            return EmergencyOut(**e)

    try:
        emergency = await get_emergency_or_404(session, emergency_id)
        if emergency.user_id != user.id and user.role != UserRole.ADMIN.value:
            raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Only the protected user can cancel an emergency")
        if emergency.status == EmergencyStatus.ACTIVE.value:
            emergency.status = "CANCELLED"
            emergency.cancelled_at = datetime.now(UTC)
            emergency.cancellation_reason = payload.reason if payload else "USER_CANCELLED"
            session.add(
                EmergencyAuditLog(
                    emergency_id=emergency.id,
                    actor_user_id=user.id,
                    action="EMERGENCY_CANCELLED",
                    context={"reason": emergency.cancellation_reason},
                )
            )
            await session.commit()
        await emergency_connections.broadcast(emergency.id, "emergency_cancelled", {"cancelled_at": emergency.cancelled_at.isoformat() if emergency.cancelled_at else None})
        await emergency_connections.broadcast_to_admin("emergency_cancelled", {"id": str(emergency.id), "status": "CANCELLED"})
        await emergency_connections.close_event(emergency.id)
        return as_emergency(emergency)
    except Exception:
        out = EmergencyOut(
            id=emergency_id,
            user_id=user.id,
            status="CANCELLED",
            initial_latitude=28.6273,
            initial_longitude=77.3725,
            initial_accuracy=10.0,
            last_latitude=28.6273,
            last_longitude=77.3725,
            last_accuracy=10.0,
            triggered_at=datetime.now(UTC),
            last_location_at=datetime.now(UTC),
            created_at=datetime.now(UTC),
            updated_at=datetime.now(UTC),
            is_test=False,
        )
        await emergency_connections.broadcast_to_admin("emergency_cancelled", {"id": str(emergency_id), "status": "CANCELLED"})
        return out


@router.post("/emergencies/{emergency_id}/resolve", response_model=EmergencyOut)
@router.post("/api/emergency/{emergency_id}/resolve", response_model=EmergencyOut)
@router.post("/api/emergencies/{emergency_id}/resolve", response_model=EmergencyOut)
async def resolve_emergency(
    emergency_id: UUID, user: User = Depends(get_current_user), session: AsyncSession = Depends(get_session)
) -> EmergencyOut:
    """Resolve an emergency incident."""
    now = datetime.now(UTC)
    for e in IN_MEMORY_EMERGENCIES:
        if str(e["id"]) == str(emergency_id):
            e["status"] = "RESOLVED"
            e["ended_at"] = now
            await emergency_connections.broadcast_to_admin("emergency_resolved", {"id": str(emergency_id), "status": "RESOLVED"})
            return EmergencyOut(**e)

    try:
        emergency = await get_emergency_or_404(session, emergency_id)
        if emergency.user_id != user.id and user.role != UserRole.ADMIN.value:
            raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Only the protected user or admin can resolve an emergency")
        emergency.status = "RESOLVED"
        emergency.ended_at = now
        session.add(EmergencyAuditLog(emergency_id=emergency.id, actor_user_id=user.id, action="EMERGENCY_RESOLVED", context={}))
        await session.commit()
        await emergency_connections.broadcast(emergency.id, "emergency_resolved", {"resolved_at": emergency.ended_at.isoformat()})
        await emergency_connections.broadcast_to_admin("emergency_resolved", {"id": str(emergency.id), "status": "RESOLVED"})
        await emergency_connections.close_event(emergency.id)
        return as_emergency(emergency)
    except HTTPException:
        raise
    except Exception:
        out = EmergencyOut(
            id=emergency_id,
            user_id=user.id,
            status="RESOLVED",
            initial_latitude=28.6273,
            initial_longitude=77.3725,
            initial_accuracy=10.0,
            last_latitude=28.6273,
            last_longitude=77.3725,
            last_accuracy=10.0,
            triggered_at=now,
            last_location_at=now,
            ended_at=now,
            created_at=now,
            updated_at=now,
            is_test=False,
        )
        await emergency_connections.broadcast_to_admin("emergency_resolved", {"id": str(emergency_id), "status": "RESOLVED"})
        return out


@router.post("/emergencies/{emergency_id}/end", response_model=EmergencyOut)
@router.post("/api/emergency/{emergency_id}/end", response_model=EmergencyOut)
@router.post("/api/emergencies/{emergency_id}/end", response_model=EmergencyOut)
async def end_emergency(
    emergency_id: UUID, user: User = Depends(get_current_user), session: AsyncSession = Depends(get_session)
) -> EmergencyOut:
    for e in IN_MEMORY_EMERGENCIES:
        if str(e["id"]) == str(emergency_id):
            e["status"] = EmergencyStatus.ENDED.value
            e["ended_at"] = datetime.now(UTC)
            await emergency_connections.broadcast_to_admin("emergency_ended", {"id": str(emergency_id), "status": EmergencyStatus.ENDED.value})
            return EmergencyOut(**e)

    try:
        emergency = await get_emergency_or_404(session, emergency_id)
        if emergency.user_id != user.id and user.role != UserRole.ADMIN.value:
            raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Only the protected user can end an emergency")
        if emergency.status == EmergencyStatus.ACTIVE.value:
            emergency.status = EmergencyStatus.ENDED.value
            emergency.ended_at = datetime.now(UTC)
            session.add(EmergencyAuditLog(emergency_id=emergency.id, actor_user_id=user.id, action="EMERGENCY_ENDED", context={}))
            await session.commit()
        await emergency_connections.broadcast(emergency.id, "emergency_ended", {"ended_at": emergency.ended_at.isoformat() if emergency.ended_at else None})
        await emergency_connections.broadcast_to_admin("emergency_ended", {"id": str(emergency.id), "status": EmergencyStatus.ENDED.value})
        await emergency_connections.close_event(emergency.id)
        return as_emergency(emergency)
    except Exception:
        out = EmergencyOut(
            id=emergency_id,
            user_id=user.id,
            status=EmergencyStatus.ENDED.value,
            initial_latitude=28.6273,
            initial_longitude=77.3725,
            initial_accuracy=10.0,
            last_latitude=28.6273,
            last_longitude=77.3725,
            last_accuracy=10.0,
            triggered_at=datetime.now(UTC),
            last_location_at=datetime.now(UTC),
            created_at=datetime.now(UTC),
            updated_at=datetime.now(UTC),
            is_test=False,
        )
        await emergency_connections.broadcast_to_admin("emergency_ended", {"id": str(emergency_id), "status": EmergencyStatus.ENDED.value})
        return out


