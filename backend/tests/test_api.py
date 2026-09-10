import uuid
from datetime import datetime, UTC
import pytest
from pydantic import ValidationError

from app.security import (
    create_otp,
    hash_otp,
    verify_otp,
    create_access_token,
    read_access_token,
)
from app.schemas import (
    AuthRequest,
    VerifyOtpRequest,
    EmergencyCreate,
    EmergencyCancelInput,
    RelayMessageCreate,
)
from app.models import Emergency, EmergencyStatus, DeliveryStatus


def test_security_otp_generation():
    otp = create_otp()
    assert len(otp) == 6
    assert otp.isdigit()


def test_security_otp_verification():
    phone = "+919876543210"
    otp = "123456"
    expected_hash = hash_otp(phone, otp)

    assert verify_otp(phone, otp, expected_hash) is True
    assert verify_otp(phone, "654321", expected_hash) is False
    assert verify_otp("+919999999999", otp, expected_hash) is False


def test_security_jwt_token_lifecycle():
    user_id = uuid.uuid4()
    role = "ADMIN"

    token = create_access_token(user_id=user_id, role=role)
    assert isinstance(token, str)
    assert len(token) > 20

    extracted_id, extracted_role = read_access_token(token)
    assert extracted_id == user_id
    assert extracted_role == role


def test_security_jwt_invalid_token():
    with pytest.raises(ValueError, match="Invalid or expired access token"):
        read_access_token("invalid.token.payload")


def test_auth_request_schema():
    valid = AuthRequest(phone="+919876543210", display_name="Aarav Sharma")
    assert valid.phone == "+919876543210"
    assert valid.display_name == "Aarav Sharma"

    # Reject invalid phone characters
    with pytest.raises(ValidationError):
        AuthRequest(phone="not-a-phone-number!")


def test_verify_otp_request_schema():
    valid = VerifyOtpRequest(phone="+919876543210", code="123456")
    assert valid.code == "123456"

    # Reject non-6-digit code
    with pytest.raises(ValidationError):
        VerifyOtpRequest(phone="+919876543210", code="12345")

    with pytest.raises(ValidationError):
        VerifyOtpRequest(phone="+919876543210", code="abcdef")


def test_emergency_create_schema_validation():
    emergency_data = {
        "latitude": 28.6273,
        "longitude": 77.3725,
        "accuracy": 12.5,
        "idempotency_key": "idem-key-9988776655",
        "is_test": False,
        "protocol_version": 1,
        "hop_count": 0,
        "max_hops": 3,
    }
    emergency = EmergencyCreate(**emergency_data)
    assert emergency.latitude == 28.6273
    assert emergency.longitude == 77.3725
    assert emergency.max_hops == 3

    # Reject out-of-bounds latitude
    invalid_data = dict(emergency_data, latitude=120.0)
    with pytest.raises(ValidationError):
        EmergencyCreate(**invalid_data)

    # Reject too short idempotency key
    invalid_data2 = dict(emergency_data, idempotency_key="short")
    with pytest.raises(ValidationError):
        EmergencyCreate(**invalid_data2)


def test_emergency_cancel_schema():
    cancel_input = EmergencyCancelInput(reason="False alarm - testing emergency flow")
    assert cancel_input.reason == "False alarm - testing emergency flow"


def test_relay_message_create_schema():
    emergency_id = uuid.uuid4()
    relay = RelayMessageCreate(
        emergency_id=emergency_id,
        message_id="relay-msg-uuid-123456",
        received_via="BLE",
        hop_count=2,
        raw_packet={"test": "data"},
    )
    assert relay.emergency_id == emergency_id
    assert relay.received_via == "BLE"
    assert relay.hop_count == 2

    # Invalid received_via protocol
    with pytest.raises(ValidationError):
        RelayMessageCreate(
            emergency_id=emergency_id,
            message_id="relay-msg-uuid-123456",
            received_via="SATELLITE",
            hop_count=1,
        )


@pytest.mark.asyncio
async def test_police_dispatcher_safe_test_mode():
    from app.services.dispatcher import PoliceDispatcher

    dispatcher = PoliceDispatcher()
    test_emergency = Emergency(
        id=uuid.uuid4(),
        user_id=uuid.uuid4(),
        status=EmergencyStatus.ACTIVE.value,
        initial_latitude=28.6273,
        initial_longitude=77.3725,
        is_test=True,  # Safe test mode
    )

    # In test mode, dispatch must skip police alert dispatch without needing database session
    await dispatcher.dispatch(None, test_emergency)


@pytest.mark.asyncio
async def test_health_endpoint():
    from httpx import ASGITransport, AsyncClient
    from app.main import app

    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        response = await client.get("/health")
        assert response.status_code == 200
        assert response.json() == {"status": "ok"}


@pytest.mark.asyncio
async def test_openapi_spec():
    from httpx import ASGITransport, AsyncClient
    from app.main import app

    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        response = await client.get("/openapi.json")
        assert response.status_code == 200
        data = response.json()
        assert data["info"]["title"] == "BHAI Emergency API"
        assert "/health" in data["paths"]
        assert "/auth/login" in data["paths"]
        assert "/auth/verify" in data["paths"]
        assert "/emergencies/{emergency_id}/cancel" in data["paths"]
