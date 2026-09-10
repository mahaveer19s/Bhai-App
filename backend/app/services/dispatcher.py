import logging
from uuid import UUID

from sqlalchemy import select, text
from sqlalchemy.ext.asyncio import AsyncSession

from app.models import (
    ControlRoom,
    DeliveryStatus,
    Emergency,
    EmergencyNotification,
    PoliceContact,
    TrustedContact,
)
from app.services.notifications import send_helper_alert, send_trusted_contact_alert

logger = logging.getLogger(__name__)


class DispatchAdapter:
    async def dispatch(self, session: AsyncSession, emergency: Emergency) -> None:
        raise NotImplementedError


class FamilyDispatcher(DispatchAdapter):
    async def dispatch(self, session: AsyncSession, emergency: Emergency) -> None:
        contacts = (
            await session.scalars(
                select(TrustedContact).where(TrustedContact.user_id == emergency.user_id, TrustedContact.is_active.is_(True))
            )
        ).all()

        location_url = (
            f"https://www.openstreetmap.org/?mlat={emergency.initial_latitude}&mlon={emergency.initial_longitude}"
            f"#map=16/{emergency.initial_latitude}/{emergency.initial_longitude}"
        )
        for contact in contacts:
            notification = EmergencyNotification(
                emergency_id=emergency.id,
                trusted_contact_id=contact.id,
                notification_type="TRUSTED_CONTACT_SMS",
                delivery_status=DeliveryStatus.PENDING.value,
            )
            session.add(notification)
            await session.flush()

            if emergency.is_test:
                message = f"BHAI TEST ALERT: This is a test emergency request from a trusted contact. No action needed."
            else:
                message = f"BHAI Emergency Alert: a trusted contact requested immediate help. Location: {location_url}"
            
            await send_trusted_contact_alert(session, notification, contact.phone, message)


class PoliceDispatcher(DispatchAdapter):
    async def dispatch(self, session: AsyncSession, emergency: Emergency) -> None:
        if emergency.is_test:
            logger.info("Test emergency %s skipping official police dispatch", emergency.id)
            return

        if emergency.region_id is not None:
            contacts = (
                await session.scalars(
                    select(PoliceContact).where(
                        PoliceContact.region_id == emergency.region_id, PoliceContact.is_active.is_(True)
                    )
                )
            ).all()

            for contact in contacts:
                notification = EmergencyNotification(
                    emergency_id=emergency.id,
                    notification_type=f"POLICE_{contact.contact_type}",
                    delivery_status=DeliveryStatus.SENT.value,
                )
                session.add(notification)
                logger.info("Dispatched emergency %s to police contact %s (%s)", emergency.id, contact.name, contact.endpoint)


class ControlRoomDispatcher(DispatchAdapter):
    async def dispatch(self, session: AsyncSession, emergency: Emergency) -> None:
        # Find regional control room or fallback
        query = select(ControlRoom).where(ControlRoom.is_active.is_(True))
        if emergency.region_id is not None:
            query = query.where(ControlRoom.region_id == emergency.region_id)
        
        control_rooms = (await session.scalars(query)).all()
        for cr in control_rooms:
            notification = EmergencyNotification(
                emergency_id=emergency.id,
                notification_type="CONTROL_ROOM_ALERT",
                delivery_status=DeliveryStatus.SENT.value,
            )
            session.add(notification)
            logger.info("Dispatched emergency %s to control room %s", emergency.id, cr.name)


class EmergencyDispatcher:
    def __init__(self) -> None:
        self.adapters: list[DispatchAdapter] = [
            FamilyDispatcher(),
            PoliceDispatcher(),
            ControlRoomDispatcher(),
        ]

    async def process_emergency(self, session: AsyncSession, emergency: Emergency) -> None:
        # Determine geospatial region if PostGIS boundary matches
        if emergency.region_id is None:
            region_id = await self._lookup_region(session, emergency.initial_latitude, emergency.initial_longitude)
            if region_id:
                emergency.region_id = region_id

        for adapter in self.adapters:
            try:
                await adapter.dispatch(session, emergency)
            except Exception as err:
                logger.error("Error in dispatcher adapter %s: %s", adapter.__class__.__name__, err)

    async def _lookup_region(self, session: AsyncSession, latitude: float, longitude: float) -> UUID | None:
        result = await session.execute(
            text(
                """
                SELECT id FROM regions
                WHERE ST_Contains(
                    boundary::geometry,
                    ST_SetSRID(ST_MakePoint(:longitude, :latitude), 4326)
                )
                LIMIT 1
                """
            ),
            {"latitude": latitude, "longitude": longitude},
        )
        row = result.first()
        return row.id if row else None
