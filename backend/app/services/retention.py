from datetime import UTC, datetime, timedelta

from sqlalchemy import delete, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.config import get_settings
from app.models import Emergency, EmergencyLocation, EmergencyStatus


async def purge_expired_location_history(session: AsyncSession) -> int:
    """Remove only ended-emergency locations after the configured retention window."""
    cutoff = datetime.now(UTC) - timedelta(days=get_settings().location_retention_days)
    ended_events = select(Emergency.id).where(
        Emergency.status == EmergencyStatus.ENDED.value,
        Emergency.ended_at.is_not(None),
        Emergency.ended_at < cutoff,
    )
    result = await session.execute(
        delete(EmergencyLocation).where(
            EmergencyLocation.emergency_id.in_(ended_events), EmergencyLocation.recorded_at < cutoff
        )
    )
    await session.commit()
    return result.rowcount or 0
