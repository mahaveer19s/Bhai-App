import pytest
from httpx import ASGITransport, AsyncClient
from uuid import uuid4

from app.main import app
from app.security import create_access_token


@pytest.mark.asyncio
async def test_chat_conversation_and_message_lifecycle():
    victim_id = uuid4()
    helper_id = uuid4()
    alert_id = uuid4()

    victim_token = create_access_token(victim_id, "USER")
    helper_token = create_access_token(helper_id, "USER")

    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        # 1. Victim creates emergency
        alert_resp = await client.post(
            "/emergencies",
            headers={"Authorization": f"Bearer {victim_token}"},
            json={
                "idempotency_key": f"test-chat-alert-{uuid4()}",
                "latitude": 28.6139,
                "longitude": 77.2090,
                "accuracy": 5.0,
            },
        )
        assert alert_resp.status_code == 201
        created_alert_id = alert_resp.json()["id"]

        # 2. Helper acknowledges/responds
        resp_ack = await client.post(
            f"/emergencies/{created_alert_id}/respond",
            headers={"Authorization": f"Bearer {helper_token}"},
            json={"response_type": "COMING", "latitude": 28.6145, "longitude": 77.2095},
        )
        assert resp_ack.status_code == 200
        assert resp_ack.json()["response_type"] == "COMING"

        # 3. Create or get conversation thread
        conv_resp = await client.post(
            "/chat/conversations",
            headers={"Authorization": f"Bearer {victim_token}"},
            json={"alert_id": created_alert_id, "helper_user_id": str(helper_id)},
        )
        assert conv_resp.status_code == 200
        conv_data = conv_resp.json()
        conversation_id = conv_data["id"]
        assert conv_data["alert_id"] == created_alert_id

        # 4. Victim sends message
        client_msg_id_1 = f"msg-{uuid4()}"
        send_resp_1 = await client.post(
            f"/chat/conversations/{conversation_id}/messages",
            headers={"Authorization": f"Bearer {victim_token}"},
            json={
                "client_message_id": client_msg_id_1,
                "message": "Where are you?",
                "transport": "INTERNET",
            },
        )
        assert send_resp_1.status_code == 201
        msg_1 = send_resp_1.json()
        assert msg_1["message"] == "Where are you?"
        assert msg_1["delivery_status"] == "SENT"

        # 5. Idempotent check: Resending same client_message_id returns identical record without duplicates
        dup_send = await client.post(
            f"/chat/conversations/{conversation_id}/messages",
            headers={"Authorization": f"Bearer {victim_token}"},
            json={
                "client_message_id": client_msg_id_1,
                "message": "Where are you?",
                "transport": "INTERNET",
            },
        )
        assert dup_send.status_code == 201
        assert dup_send.json()["id"] == msg_1["id"]

        # 6. Helper sends reply
        client_msg_id_2 = f"msg-{uuid4()}"
        send_resp_2 = await client.post(
            f"/chat/conversations/{conversation_id}/messages",
            headers={"Authorization": f"Bearer {helper_token}"},
            json={
                "client_message_id": client_msg_id_2,
                "message": "I am 300m away, approaching north gate.",
                "transport": "INTERNET",
            },
        )
        assert send_resp_2.status_code == 201

        # 7. Helper marks message 1 as READ
        status_resp = await client.post(
            f"/chat/messages/{msg_1['id']}/status",
            headers={"Authorization": f"Bearer {helper_token}"},
            json={"delivery_status": "READ"},
        )
        assert status_resp.status_code == 200
        assert status_resp.json()["delivery_status"] == "READ"

        # 8. List messages in order
        list_resp = await client.get(
            f"/chat/conversations/{conversation_id}/messages",
            headers={"Authorization": f"Bearer {victim_token}"},
        )
        assert list_resp.status_code == 200
        messages = list_resp.json()
        assert len(messages) == 2
        assert messages[0]["message"] == "Where are you?"
        assert messages[1]["message"] == "I am 300m away, approaching north gate."


@pytest.mark.asyncio
async def test_unauthorized_user_cannot_access_private_chat():
    victim_id = uuid4()
    stranger_id = uuid4()
    alert_id = uuid4()

    victim_token = create_access_token(victim_id, "USER")
    stranger_token = create_access_token(stranger_id, "USER")

    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        # Create emergency
        alert_resp = await client.post(
            "/emergencies",
            headers={"Authorization": f"Bearer {victim_token}"},
            json={
                "idempotency_key": f"test-private-alert-{uuid4()}",
                "latitude": 12.9716,
                "longitude": 77.5946,
            },
        )
        alert_id = alert_resp.json()["id"]

        # Create conversation
        conv_resp = await client.post(
            "/chat/conversations",
            headers={"Authorization": f"Bearer {victim_token}"},
            json={"alert_id": alert_id},
        )
        conv_id = conv_resp.json()["id"]

        # Stranger attempts to read messages
        read_attempt = await client.get(
            f"/chat/conversations/{conv_id}/messages",
            headers={"Authorization": f"Bearer {stranger_token}"},
        )
        assert read_attempt.status_code == 403
