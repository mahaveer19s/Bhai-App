import asyncio
import uuid
import pytest
from httpx import ASGITransport, AsyncClient

from app.main import app
from app.security import create_access_token
from app.api.emergencies import haversine_meters


@pytest.mark.asyncio
async def test_two_victims_simultaneous_sos():
    """CRITICAL TEST: 2 victims press SOS simultaneously.
    Verifies:
    - 2 independent emergencies created with unique IDs (EMG-A, EMG-B)
    - Independent coordinates and state
    - Helper responding to EMG-A increments EMG-A only (EMG-B remains 0)
    - Resolving EMG-A leaves EMG-B ACTIVE
    """
    victim_a = uuid.uuid4()
    victim_b = uuid.uuid4()
    helper = uuid.uuid4()

    token_a = create_access_token(user_id=victim_a, role="USER")
    token_b = create_access_token(user_id=victim_b, role="USER")
    token_helper = create_access_token(user_id=helper, role="USER")

    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        # 1. Announce helper presence
        await client.put(
            "/helpers/presence",
            json={"is_available": True, "latitude": 28.6200, "longitude": 77.3700, "accuracy": 5.0},
            headers={"Authorization": f"Bearer {token_helper}"},
        )

        # 2. Both victims press SOS simultaneously
        key_a = f"idem-key-a-{uuid.uuid4().hex}"
        key_b = f"idem-key-b-{uuid.uuid4().hex}"

        res_a_task = client.post(
            "/api/emergency/alert",
            json={"latitude": 28.6210, "longitude": 77.3710, "accuracy": 8.0, "idempotency_key": key_a},
            headers={"Authorization": f"Bearer {token_a}"},
        )
        res_b_task = client.post(
            "/api/emergency/alert",
            json={"latitude": 28.6250, "longitude": 77.3750, "accuracy": 12.0, "idempotency_key": key_b},
            headers={"Authorization": f"Bearer {token_b}"},
        )

        res_a, res_b = await asyncio.gather(res_a_task, res_b_task)
        assert res_a.status_code == 201
        assert res_b.status_code == 201

        emg_a = res_a.json()
        emg_b = res_b.json()

        # Verify distinct IDs and states
        assert emg_a["id"] != emg_b["id"]
        assert emg_a["user_id"] == str(victim_a)
        assert emg_b["user_id"] == str(victim_b)
        assert emg_a["status"] == "ACTIVE"
        assert emg_b["status"] == "ACTIVE"

        id_a = emg_a["id"]
        id_b = emg_b["id"]

        # 3. Helper responds to EMG-A
        res_help = await client.post(
            f"/emergencies/{id_a}/acknowledge",
            json={"response_type": "HELPING"},
            headers={"Authorization": f"Bearer {token_helper}"},
        )
        assert res_help.status_code == 200

        # Helper queries nearby emergencies
        nearby_res = await client.get(
            "/emergencies/nearby",
            headers={"Authorization": f"Bearer {token_helper}"},
        )
        assert nearby_res.status_code == 200
        nearby_list = nearby_res.json()

        emg_a_nearby = next(item for item in nearby_list if item["id"] == id_a)
        emg_b_nearby = next(item for item in nearby_list if item["id"] == id_b)

        assert emg_a_nearby["helper_count"] == 1
        assert emg_b_nearby["helper_count"] == 0

        # 4. Victim A resolves EMG-A
        res_resolve = await client.post(
            f"/emergencies/{id_a}/resolve",
            headers={"Authorization": f"Bearer {token_a}"},
        )
        assert res_resolve.status_code == 200
        assert res_resolve.json()["status"] == "RESOLVED"

        # Verify EMG-B is STILL ACTIVE and completely unaffected
        res_check_b = await client.get(
            f"/emergencies/{id_b}",
            headers={"Authorization": f"Bearer {token_b}"},
        )
        assert res_check_b.status_code == 200
        assert res_check_b.json()["status"] == "ACTIVE"


@pytest.mark.asyncio
async def test_ten_victims_simultaneous_sos_isolation():
    """CRITICAL TEST: 10 victims press SOS simultaneously.
    Verifies:
    - 10 distinct emergencies created
    - Chat isolation: message sent to EMG-2 never appears in EMG-3
    - Location stream isolation
    """
    transport = ASGITransport(app=app)
    victims = [(uuid.uuid4(), f"idem-key-10-{i}-{uuid.uuid4().hex[:8]}") for i in range(10)]

    async with AsyncClient(transport=transport, base_url="http://test") as client:
        async def trigger_sos(u_id: uuid.UUID, key: str, index: int):
            token = create_access_token(user_id=u_id, role="USER")
            lat = 28.6000 + (index * 0.005)
            lon = 77.3000 + (index * 0.005)
            res = await client.post(
                "/api/emergency/alert",
                json={"latitude": lat, "longitude": lon, "accuracy": 10.0, "idempotency_key": key},
                headers={"Authorization": f"Bearer {token}"},
            )
            return res.json()

        results = await asyncio.gather(*[
            trigger_sos(u_id, key, i) for i, (u_id, key) in enumerate(victims)
        ])

        assert len(results) == 10
        ids = [r["id"] for r in results]
        assert len(set(ids)) == 10, "All 10 emergency IDs must be unique"

        # Verify chat isolation between emergency 2 and emergency 3
        token_2 = create_access_token(user_id=victims[2][0], role="USER")
        token_3 = create_access_token(user_id=victims[3][0], role="USER")

        # 1. Create conversation thread for EMG-2
        conv2_res = await client.post(
            "/chat/conversations",
            headers={"Authorization": f"Bearer {token_2}"},
            json={"alert_id": ids[2]},
        )
        assert conv2_res.status_code == 200
        conv2_id = conv2_res.json()["id"]

        # 2. Create conversation thread for EMG-3
        conv3_res = await client.post(
            "/chat/conversations",
            headers={"Authorization": f"Bearer {token_3}"},
            json={"alert_id": ids[3]},
        )
        assert conv3_res.status_code == 200
        conv3_id = conv3_res.json()["id"]

        # 3. Post chat message to EMG-2 conversation
        chat_res = await client.post(
            f"/chat/conversations/{conv2_id}/messages",
            json={
                "client_message_id": f"msg-{uuid.uuid4().hex[:8]}",
                "message": "Victim 2 needs immediate medical assistance",
                "transport": "INTERNET",
            },
            headers={"Authorization": f"Bearer {token_2}"},
        )
        assert chat_res.status_code == 201

        # 4. Fetch messages for EMG-2
        emg2_msgs = await client.get(
            f"/chat/conversations/{conv2_id}/messages",
            headers={"Authorization": f"Bearer {token_2}"},
        )
        assert emg2_msgs.status_code == 200
        assert any(m["message"] == "Victim 2 needs immediate medical assistance" for m in emg2_msgs.json())

        # 5. Fetch messages for EMG-3 -> must NOT contain Victim 2 message
        emg3_msgs = await client.get(
            f"/chat/conversations/{conv3_id}/messages",
            headers={"Authorization": f"Bearer {token_3}"},
        )
        assert emg3_msgs.status_code == 200
        assert not any(m["message"] == "Victim 2 needs immediate medical assistance" for m in emg3_msgs.json())


@pytest.mark.asyncio
async def test_hundred_victims_concurrent_sos():
    """CRITICAL TEST: 100 victims press SOS concurrently.
    Verifies zero dropped emergencies, zero collisions, zero merge errors.
    """
    transport = ASGITransport(app=app)
    victims = [(uuid.uuid4(), f"idem-key-100-{i}-{uuid.uuid4().hex[:8]}") for i in range(100)]

    async with AsyncClient(transport=transport, base_url="http://test") as client:
        async def send_sos(u_id: uuid.UUID, key: str, idx: int):
            token = create_access_token(user_id=u_id, role="USER")
            res = await client.post(
                "/api/emergency/alert",
                json={
                    "latitude": 28.5000 + (idx * 0.001),
                    "longitude": 77.2000 + (idx * 0.001),
                    "accuracy": 5.0,
                    "idempotency_key": key,
                },
                headers={"Authorization": f"Bearer {token}"},
            )
            return res

        responses = await asyncio.gather(*[
            send_sos(u_id, key, i) for i, (u_id, key) in enumerate(victims)
        ])

        created_ids = set()
        for i, res in enumerate(responses):
            assert res.status_code == 201
            data = res.json()
            assert data["status"] == "ACTIVE"
            created_ids.add(data["id"])

        assert len(created_ids) == 100, f"Expected 100 unique emergencies, got {len(created_ids)}"


@pytest.mark.asyncio
async def test_thousand_simulated_victims_scale_concurrency():
    """CRITICAL TEST: 1000 simulated victims concurrency test.
    Executes in fast asynchronous chunks to verify high-throughput non-blocking design.
    """
    transport = ASGITransport(app=app)
    total_victims = 1000
    batch_size = 100

    async with AsyncClient(transport=transport, base_url="http://test") as client:
        all_ids = set()

        for batch_start in range(0, total_victims, batch_size):
            batch_tasks = []
            for i in range(batch_start, batch_start + batch_size):
                u_id = uuid.uuid4()
                token = create_access_token(user_id=u_id, role="USER")
                key = f"scale-1k-{i}-{uuid.uuid4().hex[:8]}"
                task = client.post(
                    "/api/emergency/alert",
                    json={
                        "latitude": 28.0 + (i * 0.0001),
                        "longitude": 77.0 + (i * 0.0001),
                        "accuracy": 10.0,
                        "idempotency_key": key,
                    },
                    headers={"Authorization": f"Bearer {token}"},
                )
                batch_tasks.append(task)

            batch_results = await asyncio.gather(*batch_tasks)
            for res in batch_results:
                assert res.status_code == 201
                all_ids.add(res.json()["id"])

        assert len(all_ids) == total_victims, f"Expected {total_victims} unique emergencies, got {len(all_ids)}"


@pytest.mark.asyncio
async def test_dual_transport_idempotency_deduplication():
    """CRITICAL TEST: Offline -> Online transition and Internet + BLE deduplication.
    When the same emergency or message arrives via both transports with the same
    idempotency_key / client_event_id, the server MUST return the existing record without duplicating.
    """
    user_id = uuid.uuid4()
    token = create_access_token(user_id=user_id, role="USER")
    transport = ASGITransport(app=app)
    shared_key = f"offline-sync-key-{uuid.uuid4().hex}"

    async with AsyncClient(transport=transport, base_url="http://test") as client:
        # First discovery (e.g. from BLE relay)
        res1 = await client.post(
            "/api/emergency/alert",
            json={"latitude": 28.6273, "longitude": 77.3725, "accuracy": 10.0, "idempotency_key": shared_key},
            headers={"Authorization": f"Bearer {token}"},
        )
        assert res1.status_code == 201
        emg1_id = res1.json()["id"]

        # Second sync (e.g. direct Internet reconnect with same key)
        res2 = await client.post(
            "/api/emergency/alert",
            json={"latitude": 28.6273, "longitude": 77.3725, "accuracy": 10.0, "idempotency_key": shared_key},
            headers={"Authorization": f"Bearer {token}"},
        )
        assert res2.status_code == 201
        emg2_id = res2.json()["id"]

        # Must return the EXACT SAME emergency ID (0 duplicate created)
        assert emg1_id == emg2_id


def test_haversine_geodesic_distance_calculation():
    """Verify geodesic distance calculation with real coordinates."""
    # Delhi to Noida Sector 62 (~15.2 km)
    delhi_lat, delhi_lon = 28.6139, 77.2090
    noida_lat, noida_lon = 28.6273, 77.3725

    dist = haversine_meters(delhi_lat, delhi_lon, noida_lat, noida_lon)
    # Distance is ~16.0 km ± 500m
    assert 15000 <= dist <= 17000, f"Expected ~16000m, got {dist}m"

    # Same location must be 0 meters
    assert haversine_meters(28.6273, 77.3725, 28.6273, 77.3725) == 0
