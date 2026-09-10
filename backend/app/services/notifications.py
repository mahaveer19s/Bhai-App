from datetime import UTC, datetime
from functools import lru_cache
from pathlib import Path

from firebase_admin import credentials, get_app, initialize_app, messaging
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession
from twilio.rest import Client as TwilioClient

from app.config import get_settings
from app.models import DeliveryStatus, Device, EmergencyNotification


@lru_cache
def _firebase_ready() -> bool:
    credentials_path = get_settings().firebase_credentials_path
    if not credentials_path or not Path(credentials_path).is_file():
        return False
    try:
        try:
            get_app()
        except ValueError:
            initialize_app(credentials.Certificate(credentials_path))
        return True
    except Exception:
        return False


async def send_helper_alert(session: AsyncSession, notification: EmergencyNotification) -> None:
    """Send a generic alert; intentionally never includes the protected user's coordinates."""
    if notification.recipient_user_id is None:
        notification.delivery_status = DeliveryStatus.FAILED.value
        return

    devices = (
        await session.scalars(
            select(Device).where(Device.user_id == notification.recipient_user_id, Device.is_active.is_(True))
        )
    ).all()
    if not devices or not _firebase_ready():
        notification.delivery_status = DeliveryStatus.PENDING_CONFIGURATION.value
        return

    try:
        for device in devices:
            message = messaging.Message(
                notification=messaging.Notification(
                    title="BHAI HELP ALERT",
                    body="Someone nearby has requested emergency assistance. Open BHAI to respond.",
                ),
                data={"emergency_id": str(notification.emergency_id), "kind": "nearby_emergency"},
                token=device.push_token,
                android=messaging.AndroidConfig(priority="high"),
                apns=messaging.APNSConfig(headers={"apns-priority": "10"}),
            )
            notification.provider_message_id = messaging.send(message)
        notification.delivery_status = DeliveryStatus.SENT.value
        notification.sent_at = datetime.now(UTC)
    except Exception:
        # Keep the provider error out of the public API; an operator can inspect the audit/notification record.
        notification.delivery_status = DeliveryStatus.FAILED.value


async def send_trusted_contact_alert(
    session: AsyncSession, notification: EmergencyNotification, phone: str, message_body: str
) -> None:
    settings = get_settings()
    if not all([settings.twilio_account_sid, settings.twilio_auth_token, settings.twilio_from_number]):
        notification.delivery_status = DeliveryStatus.PENDING_CONFIGURATION.value
        return
    try:
        client = TwilioClient(settings.twilio_account_sid, settings.twilio_auth_token)
        result = client.messages.create(body=message_body, from_=settings.twilio_from_number, to=phone)
        notification.provider_message_id = result.sid
        notification.delivery_status = DeliveryStatus.SENT.value
        notification.sent_at = datetime.now(UTC)
    except Exception:
        notification.delivery_status = DeliveryStatus.FAILED.value


async def send_otp(phone: str, code: str) -> bool:
    """Deliver a one-time verification code through the configured SMS provider."""
    settings = get_settings()
    if not all([settings.twilio_account_sid, settings.twilio_auth_token, settings.twilio_from_number]):
        return False
    try:
        client = TwilioClient(settings.twilio_account_sid, settings.twilio_auth_token)
        client.messages.create(
            body=f"Your BHAI verification code is {code}. It expires in 10 minutes. Do not share this code.",
            from_=settings.twilio_from_number,
            to=phone,
        )
        return True
    except Exception:
        return False
