import uuid
import pytest
from httpx import ASGITransport, AsyncClient

from app.config import get_settings
from app.main import app
from app.security import create_access_token


@pytest.mark.asyncio
async def test_admin_endpoints_reject_unauthenticated():
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        # Without token
        res_dash = await client.get("/api/admin/dashboard")
        assert res_dash.status_code == 401

        res_em = await client.get("/api/admin/emergencies")
        assert res_em.status_code == 401

        res_loc = await client.get("/api/admin/live-locations")
        assert res_loc.status_code == 401


@pytest.mark.asyncio
async def test_admin_endpoints_reject_normal_user():
    transport = ASGITransport(app=app)
    user_token = create_access_token(user_id=uuid.uuid4(), role="USER")
    headers = {"Authorization": f"Bearer {user_token}"}

    async with AsyncClient(transport=transport, base_url="http://test") as client:
        res_dash = await client.get("/api/admin/dashboard", headers=headers)
        assert res_dash.status_code == 403

        res_em = await client.get("/api/admin/emergencies", headers=headers)
        assert res_em.status_code == 403

        res_loc = await client.get("/api/admin/live-locations", headers=headers)
        assert res_loc.status_code == 403


@pytest.mark.asyncio
async def test_admin_login_lifecycle_and_access():
    transport = ASGITransport(app=app)
    settings = get_settings()

    async with AsyncClient(transport=transport, base_url="http://test") as client:
        # 1. Invalid login fails
        res_fail = await client.post(
            "/api/admin/login",
            json={"username": settings.admin_username, "password": "wrong_password"},
        )
        assert res_fail.status_code == 401

        # 2. Valid login succeeds with username and default password
        res_ok = await client.post(
            "/api/admin/login",
            json={"username": "admin", "password": "BhaiSecureAdmin2026!"},
        )
        assert res_ok.status_code == 200
        data = res_ok.json()
        assert "access_token" in data
        assert data["role"] == "ADMIN"
        admin_token = data["access_token"]

        # Also verify with email and lowercase password
        res_email = await client.post(
            "/api/admin/login",
            json={"email": "admin@bhai.app", "password": "bhaisecureadmin2026"},
        )
        assert res_email.status_code == 200

        # 3. Access admin endpoints with token
        headers = {"Authorization": f"Bearer {admin_token}"}
        res_dash = await client.get("/api/admin/dashboard", headers=headers)
        assert res_dash.status_code == 200
        dash_data = res_dash.json()
        assert "active_emergencies" in dash_data
        assert "active_live_locations" in dash_data

        res_em = await client.get("/api/admin/emergencies", headers=headers)
        assert res_em.status_code == 200
        assert isinstance(res_em.json(), list)

        res_loc = await client.get("/api/admin/live-locations", headers=headers)
        assert res_loc.status_code == 200
        assert isinstance(res_loc.json(), list)
