from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.database import get_session
from app.deps import get_current_user
from app.models import TrustedContact, User
from app.schemas import TrustedContactCreate, TrustedContactOut, TrustedContactUpdate

router = APIRouter(prefix="/trusted-contacts", tags=["trusted contacts"])


@router.get("", response_model=list[TrustedContactOut])
async def list_contacts(user: User = Depends(get_current_user), session: AsyncSession = Depends(get_session)) -> list[TrustedContactOut]:
    contacts = (await session.scalars(select(TrustedContact).where(TrustedContact.user_id == user.id))).all()
    return [TrustedContactOut.model_validate(contact) for contact in contacts]


@router.post("", response_model=TrustedContactOut, status_code=status.HTTP_201_CREATED)
async def create_contact(
    payload: TrustedContactCreate, user: User = Depends(get_current_user), session: AsyncSession = Depends(get_session)
) -> TrustedContactOut:
    contact = TrustedContact(user_id=user.id, **payload.model_dump())
    session.add(contact)
    await session.commit()
    await session.refresh(contact)
    return TrustedContactOut.model_validate(contact)


@router.put("/{contact_id}", response_model=TrustedContactOut)
async def update_contact(
    contact_id: UUID,
    payload: TrustedContactUpdate,
    user: User = Depends(get_current_user),
    session: AsyncSession = Depends(get_session),
) -> TrustedContactOut:
    contact = await session.get(TrustedContact, contact_id)
    if contact is None or contact.user_id != user.id:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Trusted contact was not found")
    for field, value in payload.model_dump(exclude_unset=True).items():
        setattr(contact, field, value)
    await session.commit()
    await session.refresh(contact)
    return TrustedContactOut.model_validate(contact)


@router.delete("/{contact_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_contact(
    contact_id: UUID, user: User = Depends(get_current_user), session: AsyncSession = Depends(get_session)
) -> None:
    contact = await session.get(TrustedContact, contact_id)
    if contact is None or contact.user_id != user.id:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Trusted contact was not found")
    await session.delete(contact)
    await session.commit()
