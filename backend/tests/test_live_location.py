import uuid
from datetime import UTC, datetime
import pytest
from httpx import ASGITransport, AsyncClient

from app.main import app
from app.security import create_access_token


@pytest.fixture
def user_a_token():
    user_id = uuid.uuid4()
    return user_id, create_access_token(user_id=user_id, role="USER")


@pytest.fixture
def user_b_token():
    user_id = uuid.uuid4()
    return user_id, create_access_token(user_id=user_id, role="USER")


@pytest.fixture
def admin_token():
    admin_id = uuid.uuid4()
    return admin_id, create_access_token(user_id=admin_id, role="ADMIN")


@pytest.mark.asyncio
async def test_live_location_lifecycle(user_a_token):
    user_id, token = user_a_token
    transport = ASGITransport(app=app)
    headers = {"Authorization": f"Bearer {token}"}

    async with AsyncClient(transport=transport, base_url="http://test") as client:
        # 1. Start live location session
        start_payload = {
            "latitude": 28.6273,
            "longitude": 77.3725,
            "accuracy": 8.0,
        }
        res_start = await client.post("/api/live-location/start", json=start_payload, headers=headers)
        assert res_start.status_code == 201
        session_data = res_start.json()
        session_id = session_data["id"]
        assert session_data["status"] == "ACTIVE"
        assert session_data["user_id"] == str(user_id)
        assert session_data["initial_latitude"] == 28.6273
        assert "maps/dir" in session_data["navigation_url"]
        assert "28.6273,77.3725" in session_data["navigation_url"]

        # 2. Update location (5s update)
        update_payload = {
            "session_id": session_id,
            "latitude": 28.6280,
            "longitude": 77.3732,
            "accuracy": 5.5,
        }
        res_update = await client.post("/api/live-location/update", json=update_payload, headers=headers)
        assert res_update.status_code == 200
        update_data = res_update.json()
        assert update_data["latitude"] == 28.6280
        assert update_data["longitude"] == 77.3732

        # 3. Retrieve session details
        res_get = await client.get(f"/api/live-location/{session_id}", headers=headers)
        assert res_get.status_code == 200
        get_data = res_get.json()
        assert get_data["last_latitude"] == 28.6280
        assert "28.628,77.3732" in get_data["navigation_url"]

        # 4. Stop session
        stop_payload = {"session_id": session_id}
        res_stop = await client.post("/api/live-location/stop", json=stop_payload, headers=headers)
        assert res_stop.status_code == 200
        stop_data = res_stop.json()
        assert stop_data["status"] == "STOPPED"
        assert stop_data["ended_at"] is not None

        # 5. Subsequent updates rejected
        res_update_after = await client.post("/api/live-location/update", json=update_payload, headers=headers)
        assert res_update_after.status_code == 409


@pytest.mark.asyncio
async def test_live_location_ownership_isolation(user_a_token, user_b_token):
    user_a_id, token_a = user_a_token
    user_b_id, token_b = user_b_token
    transport = ASGITransport(app=app)

    async with AsyncClient(transport=transport, base_url="http://test") as client:
        # User A starts session
        res_start = await client.post(
            "/api/live-location/start",
            json={"latitude": 28.5000, "longitude": 77.2000, "accuracy": 10.0},
            headers={"Authorization": f"Bearer {token_a}"},
        )
        assert res_start.status_code == 201
        session_a_id = res_start.json()["id"]

        # User B attempts to post location updates to User A's session -> must be forbidden 403
        res_malicious_update = await client.post(
            "/api/live-location/update",
            json={"session_id": session_a_id, "latitude": 28.9999, "longitude": 77.9999},
            headers={"Authorization": f"Bearer {token_b}"},
        )
        assert res_malicious_update.status_code == 403

        # User B attempts to read User A's session -> must be forbidden 403
        res_unauthorized_read = await client.get(
            f"/api/live-location/{session_a_id}",
            headers={"Authorization": f"Bearer {token_b}"},
        )
        assert res_unauthorized_read.status_code == 403

        # User B attempts to stop User A's session -> must be forbidden 403
        res_unauthorized_stop = await client.post(
            "/api/live-location/stop",
            json={"session_id": session_a_id},
            headers={"Authorization": f"Bearer {token_b}"},
        )
        assert res_unauthorized_stop.status_code == 403
