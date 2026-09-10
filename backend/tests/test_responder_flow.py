import pytest
from httpx import ASGITransport, AsyncClient
from uuid import uuid4

from app.main import app
from app.security import create_access_token


@pytest.mark.asyncio
async def test_responder_lifecycle_coming_to_reached():
    victim_id = uuid4()
    helper_id = uuid4()

    victim_token = create_access_token(victim_id, "USER")
    helper_token = create_access_token(helper_id, "USER")

    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        # 1. Victim creates emergency
        alert_resp = await client.post(
            "/emergencies",
            headers={"Authorization": f"Bearer {victim_token}"},
            json={
                "idempotency_key": f"test-resp-alert-{uuid4()}",
                "latitude": 19.0760,
                "longitude": 72.8777,
                "accuracy": 8.0,
            },
        )
        assert alert_resp.status_code == 201
        alert_id = alert_resp.json()["id"]

        # 2. Helper marks COMING ("I'M COMING")
        coming_resp = await client.post(
            f"/emergencies/{alert_id}/respond",
            headers={"Authorization": f"Bearer {helper_token}"},
            json={
                "response_type": "COMING",
                "latitude": 19.0780,
                "longitude": 72.8790,
            },
        )
        assert coming_resp.status_code == 200
        coming_data = coming_resp.json()
        assert coming_data["response_type"] == "COMING"
        assert coming_data["reached_at"] is None

        # 3. Helper arrives at scene and marks REACHED ("REACHED")
        reached_resp = await client.post(
            f"/emergencies/{alert_id}/respond",
            headers={"Authorization": f"Bearer {helper_token}"},
            json={
                "response_type": "REACHED",
                "latitude": 19.0761,
                "longitude": 72.8778,
            },
        )
        assert reached_resp.status_code == 200
        reached_data = reached_resp.json()
        assert reached_data["response_type"] == "REACHED"
        assert reached_data["reached_at"] is not None

        # 4. Victim resolves emergency
        resolve_resp = await client.post(
            f"/emergencies/{alert_id}/cancel",
            headers={"Authorization": f"Bearer {victim_token}"},
            json={"reason": "Helper reached and situation is safe"},
        )
        assert resolve_resp.status_code == 200
        assert resolve_resp.json()["status"] == "CANCELLED"
