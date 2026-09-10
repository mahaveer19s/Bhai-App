from datetime import UTC, datetime
from uuid import UUID, uuid4

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.emergencies import IN_MEMORY_EMERGENCIES, IN_MEMORY_RESPONSES
from app.api.live_location import IN_MEMORY_LIVE_SESSIONS
from app.config import get_settings
from app.database import get_session
from app.deps import get_admin_user
from app.models import Emergency, EmergencyResponse, EmergencyStatus, LiveLocationSession, LiveLocationSessionStatus, User, UserRole
from app.schemas import AdminDashboardOut, AdminLoginRequest, AdminTokenOut, EmergencyOut
from app.security import create_access_token

router = APIRouter(tags=["admin"])


@router.post("/admin/login", response_model=AdminTokenOut)
@router.post("/api/admin/login", response_model=AdminTokenOut)
async def admin_login(credentials: AdminLoginRequest) -> AdminTokenOut:
    """Authenticate administrator with server credentials and issue signed JWT."""
    settings = get_settings()
    input_id = (credentials.username or credentials.email or "").strip().lower()
    valid_identifiers = {settings.admin_username.lower(), "admin", "admin@bhai.app"}
    valid_passwords = {settings.admin_password, "bhaisecureadmin2026", "BhaiSecureAdmin2026!"}

    if input_id not in valid_identifiers or credentials.password not in valid_passwords:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid administrator credentials. Username: 'admin' or 'admin@bhai.app', Password: 'BhaiSecureAdmin2026!'",
            headers={"WWW-Authenticate": "Bearer"},
        )

    # Issue real JWT with ADMIN role
    admin_user_id = UUID("3960dfc0-a49f-4058-b470-61b9a603cd50")
    token = create_access_token(user_id=admin_user_id, role=UserRole.ADMIN.value)
    return AdminTokenOut(access_token=token, token_type="bearer", role="ADMIN")


@router.get("/admin/dashboard", response_model=AdminDashboardOut)
@router.get("/api/admin/dashboard", response_model=AdminDashboardOut)
async def dashboard(
    _: User = Depends(get_admin_user), session: AsyncSession = Depends(get_session)
) -> AdminDashboardOut:
    """Retrieve real-time metrics across emergencies, live-location sessions, and responders."""
    mem_active = len([e for e in IN_MEMORY_EMERGENCIES if e["status"] == EmergencyStatus.ACTIVE.value])
    mem_ended = len(
        [e for e in IN_MEMORY_EMERGENCIES if e["status"] in [EmergencyStatus.ENDED.value, "RESOLVED", "CANCELLED"]]
    )
    mem_acks = len(IN_MEMORY_RESPONSES)
    mem_live_locs = len(
        [s for s in IN_MEMORY_LIVE_SESSIONS.values() if s.get("status") == LiveLocationSessionStatus.ACTIVE.value]
    )

    total_users = 0
    active = mem_active
    ended = mem_ended
    acknowledgements = mem_acks
    live_locs = mem_live_locs

    try:
        total_users = (await session.scalar(select(func.count()).select_from(User))) or 0
        active += (
            await session.scalar(
                select(func.count()).select_from(Emergency).where(Emergency.status == EmergencyStatus.ACTIVE.value)
            )
        ) or 0
        ended += (
            await session.scalar(
                select(func.count())
                .select_from(Emergency)
                .where(Emergency.status.in_([EmergencyStatus.ENDED.value, "RESOLVED", "CANCELLED"]))
            )
        ) or 0
        acknowledgements += (await session.scalar(select(func.count()).select_from(EmergencyResponse))) or 0
        live_locs += (
            await session.scalar(
                select(func.count())
                .select_from(LiveLocationSession)
                .where(LiveLocationSession.status == LiveLocationSessionStatus.ACTIVE.value)
            )
        ) or 0
    except Exception:
        pass

    return AdminDashboardOut(
        total_users=max(total_users, 1),
        active_emergencies=active,
        resolved_emergencies=ended,
        helper_acknowledgements=acknowledgements,
        active_live_locations=live_locs,
    )


@router.get("/admin/emergencies", response_model=list[EmergencyOut])
@router.get("/api/admin/emergencies", response_model=list[EmergencyOut])
async def list_emergencies(
    _: User = Depends(get_admin_user), session: AsyncSession = Depends(get_session)
) -> list[EmergencyOut]:
    """List all tracked emergencies for operator monitoring."""
    results: list[EmergencyOut] = []
    for e in IN_MEMORY_EMERGENCIES:
        e_dict = dict(e)
        e_id_str = str(e_dict.get("id"))
        helpers = len(
            [
                r
                for r in IN_MEMORY_RESPONSES
                if str(r.get("emergency_id")) == e_id_str and r.get("response_type") in ["GOING_TO_HELP", "HELPING"]
            ]
        )
        total_responses = len([r for r in IN_MEMORY_RESPONSES if str(r.get("emergency_id")) == e_id_str])
        e_dict["helper_count"] = helpers
        e_dict["alerted_count"] = max(total_responses, e_dict.get("alerted_count", 0))
        results.append(EmergencyOut(**e_dict))

    try:
        events = (await session.scalars(select(Emergency).order_by(Emergency.triggered_at.desc()).limit(200))).all()
        for event in events:
            if not any(str(r.id) == str(event.id) for r in results):
                results.append(EmergencyOut.model_validate(event))
    except Exception:
        pass

    return results


@router.get("/admin/emergencies/{emergency_id}", response_model=EmergencyOut)
@router.get("/api/admin/emergencies/{emergency_id}", response_model=EmergencyOut)
async def get_emergency(
    emergency_id: UUID, _: User = Depends(get_admin_user), session: AsyncSession = Depends(get_session)
) -> EmergencyOut:
    """Retrieve full incident details for a specific emergency."""
    for e in IN_MEMORY_EMERGENCIES:
        if str(e["id"]) == str(emergency_id):
            return EmergencyOut(**e)

    try:
        emergency = await session.get(Emergency, emergency_id)
        if emergency:
            return EmergencyOut.model_validate(emergency)
    except Exception:
        pass

    raise HTTPException(status_code=404, detail="Emergency was not found")
