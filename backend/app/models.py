import enum
from datetime import datetime
from uuid import UUID, uuid4

from geoalchemy2 import Geography
from sqlalchemy import Boolean, DateTime, Float, ForeignKey, Index, Integer, JSON, String, Text, UniqueConstraint, func
from sqlalchemy.dialects.postgresql import UUID as PGUUID
from sqlalchemy.orm import Mapped, mapped_column

from app.database import Base


class UserRole(str, enum.Enum):
    USER = "USER"
    ADMIN = "ADMIN"


class EmergencyStatus(str, enum.Enum):
    CREATED = "CREATED"
    ACTIVE = "ACTIVE"
    ACKNOWLEDGED = "ACKNOWLEDGED"
    RESOLVED = "RESOLVED"
    ENDED = "ENDED"
    EXPIRED = "EXPIRED"
    CANCELLED = "CANCELLED"


class LiveLocationSessionStatus(str, enum.Enum):
    ACTIVE = "ACTIVE"
    STOPPED = "STOPPED"
    EXPIRED = "EXPIRED"


class ResponseType(str, enum.Enum):
    ACKNOWLEDGED = "ACKNOWLEDGED"
    COMING = "COMING"
    HELPING = "HELPING"
    REACHED = "REACHED"
    CANNOT_HELP = "CANNOT_HELP"


class ConversationStatus(str, enum.Enum):
    ACTIVE = "ACTIVE"
    CLOSED = "CLOSED"
    READ_ONLY = "READ_ONLY"


class MessageTransport(str, enum.Enum):
    INTERNET = "INTERNET"
    BLUETOOTH = "BLUETOOTH"


class MessageDeliveryStatus(str, enum.Enum):
    SENDING = "SENDING"
    SENT = "SENT"
    DELIVERED = "DELIVERED"
    READ = "READ"
    FAILED = "FAILED"


class DeliveryStatus(str, enum.Enum):
    PENDING = "PENDING"
    SENT = "SENT"
    FAILED = "FAILED"
    PENDING_CONFIGURATION = "PENDING_CONFIGURATION"


class Timestamped:
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now(), nullable=False)
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), onupdate=func.now(), nullable=False
    )


class User(Timestamped, Base):
    __tablename__ = "users"

    id: Mapped[UUID] = mapped_column(PGUUID(as_uuid=True), primary_key=True, default=uuid4)
    phone: Mapped[str] = mapped_column(String(32), unique=True, index=True, nullable=False)
    display_name: Mapped[str | None] = mapped_column(String(120))
    role: Mapped[str] = mapped_column(String(20), default=UserRole.USER.value, nullable=False)
    is_verified: Mapped[bool] = mapped_column(Boolean, default=False, nullable=False)
    emergency_alerts_enabled: Mapped[bool] = mapped_column(Boolean, default=False, nullable=False)
    location_sharing_enabled: Mapped[bool] = mapped_column(Boolean, default=False, nullable=False)
    is_suspended: Mapped[bool] = mapped_column(Boolean, default=False, nullable=False)


class OtpChallenge(Base):
    __tablename__ = "otp_challenges"

    id: Mapped[UUID] = mapped_column(PGUUID(as_uuid=True), primary_key=True, default=uuid4)
    phone: Mapped[str] = mapped_column(String(32), index=True, nullable=False)
    code_hash: Mapped[str] = mapped_column(String(128), nullable=False)
    expires_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)
    consumed_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    attempts: Mapped[int] = mapped_column(Integer, default=0, nullable=False)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now(), nullable=False)


class TrustedContact(Timestamped, Base):
    __tablename__ = "trusted_contacts"

    id: Mapped[UUID] = mapped_column(PGUUID(as_uuid=True), primary_key=True, default=uuid4)
    user_id: Mapped[UUID] = mapped_column(PGUUID(as_uuid=True), ForeignKey("users.id", ondelete="CASCADE"), index=True)
    name: Mapped[str] = mapped_column(String(120), nullable=False)
    phone: Mapped[str] = mapped_column(String(32), nullable=False)
    relationship: Mapped[str | None] = mapped_column(String(80))
    is_active: Mapped[bool] = mapped_column(Boolean, default=True, nullable=False)


class Region(Base):
    __tablename__ = "regions"

    id: Mapped[UUID] = mapped_column(PGUUID(as_uuid=True), primary_key=True, default=uuid4)
    name: Mapped[str] = mapped_column(String(120), nullable=False)
    code: Mapped[str] = mapped_column(String(32), unique=True, nullable=False)
    boundary: Mapped[object | None] = mapped_column(Geography(geometry_type="POLYGON", srid=4326), nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now(), nullable=False)


class ControlRoom(Base):
    __tablename__ = "control_rooms"

    id: Mapped[UUID] = mapped_column(PGUUID(as_uuid=True), primary_key=True, default=uuid4)
    region_id: Mapped[UUID | None] = mapped_column(PGUUID(as_uuid=True), ForeignKey("regions.id", ondelete="SET NULL"))
    name: Mapped[str] = mapped_column(String(120), nullable=False)
    email: Mapped[str | None] = mapped_column(String(120))
    phone: Mapped[str | None] = mapped_column(String(32))
    webhook_url: Mapped[str | None] = mapped_column(Text)
    is_active: Mapped[bool] = mapped_column(Boolean, default=True, nullable=False)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now(), nullable=False)


class PoliceContact(Base):
    __tablename__ = "police_contacts"

    id: Mapped[UUID] = mapped_column(PGUUID(as_uuid=True), primary_key=True, default=uuid4)
    region_id: Mapped[UUID | None] = mapped_column(PGUUID(as_uuid=True), ForeignKey("regions.id", ondelete="SET NULL"))
    name: Mapped[str] = mapped_column(String(120), nullable=False)
    contact_type: Mapped[str] = mapped_column(String(20), default="SMS", nullable=False)
    endpoint: Mapped[str] = mapped_column(Text, nullable=False)
    is_active: Mapped[bool] = mapped_column(Boolean, default=True, nullable=False)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now(), nullable=False)


class Emergency(Timestamped, Base):
    __tablename__ = "emergencies"
    __table_args__ = (UniqueConstraint("user_id", "idempotency_key", name="uq_emergency_user_idempotency"),)

    id: Mapped[UUID] = mapped_column(PGUUID(as_uuid=True), primary_key=True, default=uuid4)
    user_id: Mapped[UUID] = mapped_column(PGUUID(as_uuid=True), ForeignKey("users.id"), index=True, nullable=False)
    status: Mapped[str] = mapped_column(String(20), default=EmergencyStatus.ACTIVE.value, index=True, nullable=False)
    triggered_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now(), nullable=False)
    ended_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    cancelled_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    cancellation_reason: Mapped[str | None] = mapped_column(String(120))
    initial_latitude: Mapped[float] = mapped_column(Float, nullable=False)
    initial_longitude: Mapped[float] = mapped_column(Float, nullable=False)
    initial_accuracy: Mapped[float | None] = mapped_column(Float)
    last_latitude: Mapped[float] = mapped_column(Float, nullable=False)
    last_longitude: Mapped[float] = mapped_column(Float, nullable=False)
    last_accuracy: Mapped[float | None] = mapped_column(Float)
    last_location_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)
    network_status: Mapped[str | None] = mapped_column(String(40))
    device_status: Mapped[dict] = mapped_column(JSON, default=dict, nullable=False)
    idempotency_key: Mapped[str] = mapped_column(String(96), nullable=False)
    is_test: Mapped[bool] = mapped_column(Boolean, default=False, nullable=False)
    protocol_version: Mapped[int] = mapped_column(Integer, default=1, nullable=False)
    hop_count: Mapped[int] = mapped_column(Integer, default=0, nullable=False)
    max_hops: Mapped[int] = mapped_column(Integer, default=3, nullable=False)
    region_id: Mapped[UUID | None] = mapped_column(PGUUID(as_uuid=True), ForeignKey("regions.id", ondelete="SET NULL"))


class RelayMessage(Base):
    __tablename__ = "relay_messages"
    __table_args__ = (UniqueConstraint("emergency_id", "message_id", name="uq_relay_message_id"),)

    id: Mapped[UUID] = mapped_column(PGUUID(as_uuid=True), primary_key=True, default=uuid4)
    emergency_id: Mapped[UUID] = mapped_column(PGUUID(as_uuid=True), ForeignKey("emergencies.id", ondelete="CASCADE"), nullable=False)
    message_id: Mapped[str] = mapped_column(String(96), nullable=False)
    relayed_by_user_id: Mapped[UUID | None] = mapped_column(PGUUID(as_uuid=True), ForeignKey("users.id", ondelete="SET NULL"))
    received_via: Mapped[str] = mapped_column(String(20), default="BLE", nullable=False)
    hop_count: Mapped[int] = mapped_column(Integer, default=1, nullable=False)
    raw_packet: Mapped[dict] = mapped_column(JSON, default=dict, nullable=False)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now(), nullable=False)


class EmergencyLocation(Base):
    __tablename__ = "emergency_locations"
    __table_args__ = (Index("ix_emergency_locations_emergency_recorded", "emergency_id", "recorded_at"),)

    id: Mapped[UUID] = mapped_column(PGUUID(as_uuid=True), primary_key=True, default=uuid4)
    emergency_id: Mapped[UUID] = mapped_column(PGUUID(as_uuid=True), ForeignKey("emergencies.id", ondelete="CASCADE"), nullable=False)
    latitude: Mapped[float] = mapped_column(Float, nullable=False)
    longitude: Mapped[float] = mapped_column(Float, nullable=False)
    accuracy: Mapped[float | None] = mapped_column(Float)
    recorded_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now(), nullable=False)


class HelperPresence(Timestamped, Base):
    __tablename__ = "helper_presence"

    user_id: Mapped[UUID] = mapped_column(PGUUID(as_uuid=True), ForeignKey("users.id", ondelete="CASCADE"), primary_key=True)
    is_available: Mapped[bool] = mapped_column(Boolean, default=False, nullable=False)
    last_location: Mapped[object | None] = mapped_column(Geography(geometry_type="POINT", srid=4326), nullable=True)
    last_latitude: Mapped[float | None] = mapped_column(Float)
    last_longitude: Mapped[float | None] = mapped_column(Float)
    location_updated_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))


class EmergencyResponse(Base):
    __tablename__ = "emergency_responses"
    __table_args__ = (UniqueConstraint("emergency_id", "helper_user_id", name="uq_emergency_response_helper"),)

    id: Mapped[UUID] = mapped_column(PGUUID(as_uuid=True), primary_key=True, default=uuid4)
    emergency_id: Mapped[UUID] = mapped_column(PGUUID(as_uuid=True), ForeignKey("emergencies.id", ondelete="CASCADE"), nullable=False)
    helper_user_id: Mapped[UUID] = mapped_column(PGUUID(as_uuid=True), ForeignKey("users.id"), nullable=False)
    response_type: Mapped[str] = mapped_column(String(20), nullable=False)
    responded_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now(), nullable=False)
    reached_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    last_latitude: Mapped[float | None] = mapped_column(Float)
    last_longitude: Mapped[float | None] = mapped_column(Float)
    location_updated_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))


class Device(Timestamped, Base):
    __tablename__ = "devices"
    __table_args__ = (UniqueConstraint("user_id", "push_token", name="uq_device_user_push_token"),)

    id: Mapped[UUID] = mapped_column(PGUUID(as_uuid=True), primary_key=True, default=uuid4)
    user_id: Mapped[UUID] = mapped_column(PGUUID(as_uuid=True), ForeignKey("users.id", ondelete="CASCADE"), index=True, nullable=False)
    push_token: Mapped[str] = mapped_column(Text, nullable=False)
    platform: Mapped[str] = mapped_column(String(20), nullable=False)
    is_active: Mapped[bool] = mapped_column(Boolean, default=True, nullable=False)


class EmergencyNotification(Base):
    __tablename__ = "emergency_notifications"

    id: Mapped[UUID] = mapped_column(PGUUID(as_uuid=True), primary_key=True, default=uuid4)
    emergency_id: Mapped[UUID] = mapped_column(PGUUID(as_uuid=True), ForeignKey("emergencies.id", ondelete="CASCADE"), nullable=False)
    recipient_user_id: Mapped[UUID | None] = mapped_column(PGUUID(as_uuid=True), ForeignKey("users.id", ondelete="SET NULL"))
    trusted_contact_id: Mapped[UUID | None] = mapped_column(PGUUID(as_uuid=True), ForeignKey("trusted_contacts.id", ondelete="SET NULL"))
    notification_type: Mapped[str] = mapped_column(String(40), nullable=False)
    delivery_status: Mapped[str] = mapped_column(String(40), default=DeliveryStatus.PENDING.value, nullable=False)
    provider_message_id: Mapped[str | None] = mapped_column(String(120))
    sent_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    opened_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now(), nullable=False)


class EmergencyAuditLog(Base):
    __tablename__ = "emergency_audit_logs"

    id: Mapped[UUID] = mapped_column(PGUUID(as_uuid=True), primary_key=True, default=uuid4)
    emergency_id: Mapped[UUID | None] = mapped_column(PGUUID(as_uuid=True), ForeignKey("emergencies.id", ondelete="SET NULL"), index=True)
    actor_user_id: Mapped[UUID | None] = mapped_column(PGUUID(as_uuid=True), ForeignKey("users.id", ondelete="SET NULL"))
    action: Mapped[str] = mapped_column(String(80), nullable=False)
    context: Mapped[dict] = mapped_column(JSON, default=dict, nullable=False)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now(), nullable=False)


class LiveLocationSession(Timestamped, Base):
    __tablename__ = "live_location_sessions"

    id: Mapped[UUID] = mapped_column(PGUUID(as_uuid=True), primary_key=True, default=uuid4)
    user_id: Mapped[UUID] = mapped_column(PGUUID(as_uuid=True), ForeignKey("users.id", ondelete="CASCADE"), index=True, nullable=False)
    emergency_id: Mapped[UUID | None] = mapped_column(PGUUID(as_uuid=True), ForeignKey("emergencies.id", ondelete="SET NULL"))
    status: Mapped[str] = mapped_column(String(20), default=LiveLocationSessionStatus.ACTIVE.value, index=True, nullable=False)
    initial_latitude: Mapped[float] = mapped_column(Float, nullable=False)
    initial_longitude: Mapped[float] = mapped_column(Float, nullable=False)
    initial_accuracy: Mapped[float | None] = mapped_column(Float)
    last_latitude: Mapped[float] = mapped_column(Float, nullable=False)
    last_longitude: Mapped[float] = mapped_column(Float, nullable=False)
    last_accuracy: Mapped[float | None] = mapped_column(Float)
    started_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now(), nullable=False)
    last_updated_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now(), index=True, nullable=False)
    ended_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))


class LiveLocationUpdate(Base):
    __tablename__ = "live_location_updates"
    __table_args__ = (Index("ix_live_location_updates_session_rec", "session_id", "recorded_at"),)

    id: Mapped[UUID] = mapped_column(PGUUID(as_uuid=True), primary_key=True, default=uuid4)
    session_id: Mapped[UUID] = mapped_column(PGUUID(as_uuid=True), ForeignKey("live_location_sessions.id", ondelete="CASCADE"), nullable=False)
    user_id: Mapped[UUID] = mapped_column(PGUUID(as_uuid=True), ForeignKey("users.id", ondelete="CASCADE"), index=True, nullable=False)
    latitude: Mapped[float] = mapped_column(Float, nullable=False)
    longitude: Mapped[float] = mapped_column(Float, nullable=False)
    accuracy: Mapped[float | None] = mapped_column(Float)
    recorded_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now(), nullable=False)


class Conversation(Timestamped, Base):
    __tablename__ = "conversations"
    __table_args__ = (
        Index("ix_conversations_alert_id", "alert_id"),
        Index("ix_conversations_victim_helper", "victim_user_id", "helper_user_id"),
    )

    id: Mapped[UUID] = mapped_column(PGUUID(as_uuid=True), primary_key=True, default=uuid4)
    alert_id: Mapped[UUID] = mapped_column(PGUUID(as_uuid=True), ForeignKey("emergencies.id", ondelete="CASCADE"), nullable=False)
    victim_user_id: Mapped[UUID] = mapped_column(PGUUID(as_uuid=True), ForeignKey("users.id"), nullable=False)
    helper_user_id: Mapped[UUID | None] = mapped_column(PGUUID(as_uuid=True), ForeignKey("users.id"), nullable=True)
    is_admin_thread: Mapped[bool] = mapped_column(Boolean, default=False, nullable=False)
    status: Mapped[str] = mapped_column(String(20), default=ConversationStatus.ACTIVE.value, nullable=False)


class ChatMessage(Base):
    __tablename__ = "chat_messages"
    __table_args__ = (
        Index("ix_chat_messages_conversation_created", "conversation_id", "created_at"),
        UniqueConstraint("conversation_id", "client_message_id", name="uq_chat_message_client_id"),
    )

    id: Mapped[UUID] = mapped_column(PGUUID(as_uuid=True), primary_key=True, default=uuid4)
    conversation_id: Mapped[UUID] = mapped_column(PGUUID(as_uuid=True), ForeignKey("conversations.id", ondelete="CASCADE"), nullable=False)
    client_message_id: Mapped[str] = mapped_column(String(96), nullable=False)
    sender_id: Mapped[UUID] = mapped_column(PGUUID(as_uuid=True), ForeignKey("users.id"), nullable=False)
    receiver_id: Mapped[UUID | None] = mapped_column(PGUUID(as_uuid=True), ForeignKey("users.id"), nullable=True)
    message: Mapped[str] = mapped_column(Text, nullable=False)
    transport: Mapped[str] = mapped_column(String(20), default=MessageTransport.INTERNET.value, nullable=False)
    delivery_status: Mapped[str] = mapped_column(String(20), default=MessageDeliveryStatus.SENT.value, nullable=False)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now(), nullable=False)
    delivered_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    read_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))

