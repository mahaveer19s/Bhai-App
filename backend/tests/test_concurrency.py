import asyncio
import uuid
import pytest
from httpx import ASGITransport, AsyncClient

from app.main import app
from app.security import create_access_token


@pytest.mark.asyncio
async def test_concurrent_emergency_alerts_multiple_users():
    """Simulate multiple users (User A, User B, User C) triggering emergencies concurrently.
    Verifies that requests are non-blocking, sessions do not overwrite each other,
    and each alert has its own independent state.
    """
    users = [
        (uuid.uuid4(), f"idem-key-user-{i}-{uuid.uuid4().hex[:8]}")
        for i in range(5)
    ]
    transport = ASGITransport(app=app)

    async with AsyncClient(transport=transport, base_url="http://test") as client:
        async def trigger_emergency(user_id: uuid.UUID, key: str, index: int):
            token = create_access_token(user_id=user_id, role="USER")
            payload = {
                "latitude": 28.6000 + (index * 0.01),
                "longitude": 77.3000 + (index * 0.01),
                "accuracy": 10.0,
                "idempotency_key": key,
                "device_status": {"sender_id": f"device-{index}"},
            }
            res = await client.post(
                "/api/emergency/alert",
                json=payload,
                headers={"Authorization": f"Bearer {token}"},
            )
            return res

        # Run 5 users concurrently at the exact same instant
        tasks = [
            trigger_emergency(user_id, key, i)
            for i, (user_id, key) in enumerate(users)
        ]
        responses = await asyncio.gather(*tasks)

        alert_ids = set()
        for i, res in enumerate(responses):
            assert res.status_code == 201, f"User {i} failed: {res.text}"
            data = res.json()
            assert data["user_id"] == str(users[i][0])
            assert data["status"] == "ACTIVE"
            alert_ids.add(data["id"])

        # Verify all 5 alerts have distinct unique identifiers
        assert len(alert_ids) == 5


@pytest.mark.asyncio
async def test_concurrent_live_location_streams_independent():
    """Simulate multiple users concurrently streaming 5-second live location updates.
    Verifies that one user's updates do not block or overwrite another user's stream.
    """
    transport = ASGITransport(app=app)
    users = [uuid.uuid4() for _ in range(4)]

    async with AsyncClient(transport=transport, base_url="http://test") as client:
        # Step 1: Start sessions concurrently
        async def start_stream(u_id: uuid.UUID, idx: int):
            token = create_access_token(user_id=u_id, role="USER")
            res = await client.post(
                "/api/live-location/start",
                json={"latitude": 28.5 + idx * 0.05, "longitude": 77.2 + idx * 0.05, "accuracy": 8.0},
                headers={"Authorization": f"Bearer {token}"},
            )
            return u_id, token, res.json()["id"]

        session_tuples = await asyncio.gather(*[start_stream(u, i) for i, u in enumerate(users)])
        session_ids = [s[2] for s in session_tuples]
        assert len(set(session_ids)) == 4

        # Step 2: Concurrently post location updates
        async def update_stream(u_id: uuid.UUID, token: str, s_id: str, idx: int):
            res = await client.post(
                "/api/live-location/update",
                json={
                    "session_id": s_id,
                    "latitude": 28.5 + idx * 0.05 + 0.001,
                    "longitude": 77.2 + idx * 0.05 + 0.001,
                    "accuracy": 6.0,
                },
                headers={"Authorization": f"Bearer {token}"},
            )
            return res

        update_responses = await asyncio.gather(*[
            update_stream(u_id, token, s_id, i)
            for i, (u_id, token, s_id) in enumerate(session_tuples)
        ])

        for res in update_responses:
            assert res.status_code == 200

        # Step 3: Verify each session independently retains its own updated coordinates
        for i, (u_id, token, s_id) in enumerate(session_tuples):
            check_res = await client.get(
                f"/api/live-location/{s_id}",
                headers={"Authorization": f"Bearer {token}"},
            )
            assert check_res.status_code == 200
            data = check_res.json()
            expected_lat = round(28.5 + i * 0.05 + 0.001, 4)
            assert round(data["last_latitude"], 4) == expected_lat


@pytest.mark.asyncio
async def test_user_idempotency_prevents_duplicate_emergencies():
    """Verify that rapid repeated clicks by the same user with the same idempotency key
    safely return the identical emergency without creating duplicate incidents.
    """
    user_id = uuid.uuid4()
    token = create_access_token(user_id=user_id, role="USER")
    transport = ASGITransport(app=app)
    shared_key = f"idem-rapid-click-{uuid.uuid4().hex[:12]}"

    async with AsyncClient(transport=transport, base_url="http://test") as client:
        payload = {
            "latitude": 28.6273,
            "longitude": 77.3725,
            "accuracy": 10.0,
            "idempotency_key": shared_key,
        }
        # Send 3 rapid clicks concurrently with the exact same idempotency key
        tasks = [
            client.post(
                "/api/emergency/alert",
                json=payload,
                headers={"Authorization": f"Bearer {token}"},
            )
            for _ in range(3)
        ]
        responses = await asyncio.gather(*tasks)

        ids = [res.json()["id"] for res in responses]
        assert len(set(ids)) == 1, "Expected all rapid clicks to resolve to the same emergency ID"
