from datetime import UTC, datetime
from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.database import get_session
from app.deps import get_current_user
from app.models import Emergency, EmergencyAuditLog, RelayMessage, User
from app.schemas import RelayMessageCreate, RelayMessageOut

router = APIRouter(prefix="/relay", tags=["relay"])


@router.post("/messages", response_model=RelayMessageOut, status_code=status.HTTP_201_CREATED)
async def upload_relay_message(
    payload: RelayMessageCreate,
    user: User = Depends(get_current_user),
    session: AsyncSession = Depends(get_session),
) -> RelayMessageOut:
    """Stores a store-and-forward relay packet uploaded by an intermediate device (Phone B/C).
    Deduplicates based on (emergency_id, message_id).
    """
    emergency = await session.get(Emergency, payload.emergency_id)
    if emergency is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Referenced emergency was not found")

    existing = await session.scalar(
        select(RelayMessage).where(
            RelayMessage.emergency_id == payload.emergency_id,
            RelayMessage.message_id == payload.message_id,
        )
    )
    if existing is not None:
        return RelayMessageOut.model_validate(existing)

    relay = RelayMessage(
        emergency_id=payload.emergency_id,
        message_id=payload.message_id,
        relayed_by_user_id=user.id,
        received_via=payload.received_via,
        hop_count=payload.hop_count,
        raw_packet=payload.raw_packet,
    )
    session.add(relay)

    # Log audit event for store-and-forward telemetry
    session.add(
        EmergencyAuditLog(
            emergency_id=emergency.id,
            actor_user_id=user.id,
            action="BLE_RELAY_RECEIVED",
            context={
                "message_id": payload.message_id,
                "received_via": payload.received_via,
                "hop_count": payload.hop_count,
            },
        )
    )
    await session.commit()
    await session.refresh(relay)
    return RelayMessageOut.model_validate(relay)
