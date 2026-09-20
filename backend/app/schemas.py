from datetime import datetime
from typing import Any
from uuid import UUID, uuid4

from pydantic import BaseModel, ConfigDict, Field


class APIModel(BaseModel):
    model_config = ConfigDict(from_attributes=True)


class AuthRequest(BaseModel):
    phone: str = Field(min_length=7, max_length=32, pattern=r"^\+?[0-9][0-9\- ]+$")
    display_name: str | None = Field(default=None, min_length=1, max_length=120)


class VerifyOtpRequest(BaseModel):
    phone: str = Field(min_length=7, max_length=32)
    code: str = Field(min_length=6, max_length=6, pattern=r"^[0-9]{6}$")


class UserOut(APIModel):
    id: UUID
    phone: str
    display_name: str | None
    role: str
    is_verified: bool
    emergency_alerts_enabled: bool
    location_sharing_enabled: bool


class SafetyPreferencesUpdate(BaseModel):
    emergency_alerts_enabled: bool | None = None
    location_sharing_enabled: bool | None = None


class TokenOut(BaseModel):
    access_token: str
    token_type: str = "bearer"
    user: UserOut


class LocationInput(BaseModel):
    latitude: float = Field(ge=-90, le=90)
    longitude: float = Field(ge=-180, le=180)
    accuracy: float | None = Field(default=None, ge=0, le=100_000)
    recorded_at: datetime | None = None


class EmergencyCreate(LocationInput):
    idempotency_key: str = Field(min_length=8, max_length=96)
    network_status: str | None = Field(default=None, max_length=40)
    device_status: dict[str, Any] = Field(default_factory=dict)
    is_test: bool = False
    protocol_version: int = 1
    hop_count: int = 0
    max_hops: int = 3


class EmergencyCancelInput(BaseModel):
    reason: str | None = Field(default=None, max_length=120)


class RelayMessageCreate(BaseModel):
    emergency_id: UUID
    message_id: str = Field(min_length=8, max_length=96)
    received_via: str = Field(default="BLE", pattern=r"^(BLE|INTERNET|CELLULAR)$")
    hop_count: int = Field(default=1, ge=1, le=10)
    raw_packet: dict[str, Any] = Field(default_factory=dict)


class RelayMessageOut(APIModel):
    id: UUID
    emergency_id: UUID
    message_id: str
    relayed_by_user_id: UUID | None
    received_via: str
    hop_count: int
    created_at: datetime


class EmergencyLocationOut(LocationInput):
    id: UUID
    emergency_id: UUID
    recorded_at: datetime


class EmergencyOut(APIModel):
    id: UUID
    user_id: UUID
    status: str
    triggered_at: datetime
    ended_at: datetime | None = None
    cancelled_at: datetime | None = None
    cancellation_reason: str | None = None
    initial_latitude: float
    initial_longitude: float
    initial_accuracy: float | None = None
    last_latitude: float
    last_longitude: float
    last_accuracy: float | None = None
    last_location_at: datetime
    network_status: str | None = None
    is_test: bool = False
    protocol_version: int = 1
    hop_count: int = 0
    max_hops: int = 3
    region_id: UUID | None = None
    helper_count: int = 0
    alerted_count: int = 0


class NearbyEmergencyOut(BaseModel):
    id: UUID
    status: str = "ACTIVE"
    triggered_at: datetime
    distance_meters: int
    sender_id: str | None = None
    helper_count: int = 0


class EmergencyResponseInput(BaseModel):
    response_type: str = Field(pattern=r"^(ACKNOWLEDGED|COMING|GOING_TO_HELP|HELPING|REACHED|CANNOT_HELP)$")
    notes: str | None = None
    latitude: float | None = None
    longitude: float | None = None


class EmergencyResponseOut(APIModel):
    id: UUID = Field(default_factory=uuid4)
    emergency_id: UUID
    helper_user_id: UUID
    response_type: str
    responded_at: datetime
    reached_at: datetime | None = None
    last_latitude: float | None = None
    last_longitude: float | None = None


class ConversationCreate(BaseModel):
    alert_id: str
    helper_user_id: str | None = None
    is_admin_thread: bool = False


class ConversationOut(APIModel):
    id: str
    alert_id: str
    victim_user_id: str
    helper_user_id: str | None = None
    is_admin_thread: bool
    status: str
    created_at: datetime
    last_message: str | None = None
    last_message_at: datetime | None = None


class ChatMessageCreate(BaseModel):
    client_message_id: str = Field(min_length=3, max_length=96)
    message: str = Field(min_length=1, max_length=2000)
    transport: str = Field(default="INTERNET")
    receiver_id: str | None = None
    sender_id: str | None = None


class ChatMessageOut(APIModel):
    id: str
    conversation_id: str
    client_message_id: str
    sender_id: str
    receiver_id: str | None = None
    message: str
    transport: str
    delivery_status: str
    created_at: datetime
    delivered_at: datetime | None = None
    read_at: datetime | None = None


class MessageStatusUpdate(BaseModel):
    delivery_status: str = Field(pattern=r"^(DELIVERED|READ|FAILED)$")


class DeviceRegister(BaseModel):
    push_token: str = Field(min_length=20, max_length=4096)
    platform: str = Field(pattern=r"^(android|ios)$")


class TrustedContactCreate(BaseModel):
    name: str = Field(min_length=1, max_length=120)
    phone: str = Field(min_length=7, max_length=32)
    relationship: str | None = Field(default=None, max_length=80)


class TrustedContactUpdate(BaseModel):
    name: str | None = Field(default=None, min_length=1, max_length=120)
    phone: str | None = Field(default=None, min_length=7, max_length=32)
    relationship: str | None = Field(default=None, max_length=80)
    is_active: bool | None = None


class TrustedContactOut(APIModel):
    id: UUID
    user_id: UUID
    name: str
    phone: str
    relationship: str | None
    is_active: bool


class HelperPresenceUpdate(LocationInput):
    is_available: bool


class AdminDashboardOut(BaseModel):
    total_users: int
    active_emergencies: int
    resolved_emergencies: int
    helper_acknowledgements: int
    active_live_locations: int = 0


class LiveLocationStartInput(BaseModel):
    emergency_id: UUID | None = None
    latitude: float = Field(ge=-90, le=90)
    longitude: float = Field(ge=-180, le=180)
    accuracy: float | None = Field(default=None, ge=0, le=100_000)


class LiveLocationUpdateInput(BaseModel):
    session_id: UUID
    latitude: float = Field(ge=-90, le=90)
    longitude: float = Field(ge=-180, le=180)
    accuracy: float | None = Field(default=None, ge=0, le=100_000)
    timestamp: datetime | None = None


class LiveLocationStopInput(BaseModel):
    session_id: UUID


class LiveLocationUpdateOut(APIModel):
    id: UUID
    session_id: UUID
    user_id: UUID
    latitude: float
    longitude: float
    accuracy: float | None = None
    recorded_at: datetime


class LiveLocationSessionOut(APIModel):
    id: UUID
    user_id: UUID
    emergency_id: UUID | None = None
    status: str
    initial_latitude: float
    initial_longitude: float
    initial_accuracy: float | None = None
    last_latitude: float
    last_longitude: float
    last_accuracy: float | None = None
    started_at: datetime
    last_updated_at: datetime
    ended_at: datetime | None = None
    navigation_url: str | None = None


class NearbyUserOut(BaseModel):
    user_id: UUID
    display_name: str | None = "Bhai Helper"
    distance_meters: int
    is_available: bool = True
    last_updated_at: datetime | None = None


class AdminLoginRequest(BaseModel):
    username: str | None = None
    email: str | None = None
    password: str


class AdminTokenOut(BaseModel):
    access_token: str
    token_type: str = "bearer"
    role: str = "ADMIN"


class AppVersionOut(BaseModel):
    app_name: str = "Bhai App"
    version: str
    apk_url: str
    size_mb: str
    last_updated: str
    release_notes: str | None = "High-accuracy live location and BLE store-and-forward mesh"


