import uuid
import pytest
from httpx import ASGITransport, AsyncClient

from app.main import app
from app.security import create_access_token


@pytest.mark.asyncio
async def test_nearby_users_geospatial_discovery():
    user_token = create_access_token(user_id=uuid.uuid4(), role="USER")
    helper_id = uuid.uuid4()
    helper_token = create_access_token(user_id=helper_id, role="USER")
    transport = ASGITransport(app=app)
    headers = {"Authorization": f"Bearer {user_token}"}
    helper_headers = {"Authorization": f"Bearer {helper_token}"}

    async with AsyncClient(transport=transport, base_url="http://test") as client:
        # Register an active helper presence 90m away
        await client.put(
            "/helpers/presence",
            json={
                "is_available": True,
                "latitude": 28.6280,
                "longitude": 77.3730,
            },
            headers=helper_headers,
        )

        # Query nearby users within 2000 meters
        res = await client.get(
            "/api/nearby-users?latitude=28.6273&longitude=77.3725&radius_meters=2000",
            headers=headers,
        )
        assert res.status_code == 200
        helpers = res.json()
        assert isinstance(helpers, list)
        assert len(helpers) > 0


        for h in helpers:
            assert "user_id" in h
            assert "distance_meters" in h
            assert h["distance_meters"] <= 2000
            assert h["is_available"] is True

        # Check sorted ascending by distance
        distances = [h["distance_meters"] for h in helpers]
        assert distances == sorted(distances)

        # Query with very tight radius (e.g. 10 meters) -> outside users excluded
        res_tight = await client.get(
            "/api/nearby-users?latitude=28.6273&longitude=77.3725&radius_meters=10",
            headers=headers,
        )
        assert res_tight.status_code == 200
        helpers_tight = res_tight.json()
        assert len(helpers_tight) <= len(helpers)
        for h in helpers_tight:
            assert h["distance_meters"] <= 10
