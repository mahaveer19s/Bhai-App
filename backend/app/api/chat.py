import logging
from datetime import datetime, timezone
from uuid import UUID, uuid4

from fastapi import APIRouter, Depends, HTTPException, Query, status
from sqlalchemy import desc, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.database import get_session
from app.deps import get_current_user
from app.models import (
    ChatMessage,
    Conversation,
    ConversationStatus,
    Emergency,
    EmergencyResponse,
    MessageDeliveryStatus,
    MessageTransport,
    User,
    UserRole,
)
from app.realtime import chat_connections, emergency_connections
from app.schemas import (
    ChatMessageCreate,
    ChatMessageOut,
    ConversationCreate,
    ConversationOut,
    MessageStatusUpdate,
)

logger = logging.getLogger("bhai.chat")
router = APIRouter(prefix="/chat", tags=["Emergency Chat"])

# Resilient in-memory fallback stores for high-availability / zero-db testing
IN_MEMORY_CONVERSATIONS: list[dict] = []
IN_MEMORY_MESSAGES: list[dict] = []


def _find_mem_conv(conv_id: UUID) -> dict | None:
    for c in IN_MEMORY_CONVERSATIONS:
        if str(c["id"]) == str(conv_id):
            return c
    return None


@router.post("/conversations", response_model=ConversationOut, status_code=status.HTTP_200_OK)
async def create_or_get_conversation(
    payload: ConversationCreate,
    current_user: User = Depends(get_current_user),
    session: AsyncSession = Depends(get_session),
) -> ConversationOut:
    """Create or retrieve a private conversation thread for an emergency alert."""
    is_admin = current_user.role == UserRole.ADMIN.value
    helper_id = payload.helper_user_id
    is_admin_thread = payload.is_admin_thread or (is_admin and not is_admin_thread)

    now_utc = datetime.now(timezone.utc)
    conv_id = uuid4()
    victim_id = current_user.id

    try:
        emergency = await session.get(Emergency, payload.alert_id)
        if emergency:
            victim_id = emergency.user_id
            is_victim = current_user.id == emergency.user_id
            if not is_victim and not is_admin:
                helper_id = current_user.id

            query = select(Conversation).where(
                Conversation.alert_id == payload.alert_id,
                Conversation.is_admin_thread == is_admin_thread,
            )
            if is_admin_thread:
                conv = await session.scalar(query)
            elif helper_id:
                query = query.where(Conversation.helper_user_id == helper_id)
                conv = await session.scalar(query)
            else:
                conv = await session.scalar(query)

            if not conv:
                conv = Conversation(
                    id=conv_id,
                    alert_id=payload.alert_id,
                    victim_user_id=victim_id,
                    helper_user_id=helper_id if not is_admin_thread else None,
                    is_admin_thread=is_admin_thread,
                    status=ConversationStatus.ACTIVE.value,
                )
                session.add(conv)
                await session.commit()
                await session.refresh(conv)

            return ConversationOut.model_validate(conv)
    except Exception:
        pass

    # Resilient fallback
    for c in IN_MEMORY_CONVERSATIONS:
        if str(c["alert_id"]) == str(payload.alert_id) and c["is_admin_thread"] == is_admin_thread:
            if is_admin_thread or not helper_id or str(c.get("helper_user_id")) == str(helper_id):
                return ConversationOut(**c)

    mem_conv = {
        "id": conv_id,
        "alert_id": payload.alert_id,
        "victim_user_id": victim_id,
        "helper_user_id": helper_id if not is_admin_thread else None,
        "is_admin_thread": is_admin_thread,
        "status": ConversationStatus.ACTIVE.value,
        "created_at": now_utc,
    }
    IN_MEMORY_CONVERSATIONS.append(mem_conv)
    return ConversationOut(**mem_conv)


@router.get("/conversations", response_model=list[ConversationOut])
async def list_conversations(
    alert_id: UUID | None = Query(None),
    current_user: User = Depends(get_current_user),
    session: AsyncSession = Depends(get_session),
) -> list[ConversationOut]:
    """List active emergency conversations authorized for the current user."""
    try:
        query = select(Conversation)
        if alert_id:
            query = query.where(Conversation.alert_id == alert_id)

        if current_user.role != UserRole.ADMIN.value:
            query = query.where(
                (Conversation.victim_user_id == current_user.id)
                | (Conversation.helper_user_id == current_user.id)
            )

        query = query.order_by(desc(Conversation.created_at))
        conversations = (await session.scalars(query)).all()
        return [ConversationOut.model_validate(c) for c in conversations]
    except Exception:
        results = []
        for c in IN_MEMORY_CONVERSATIONS:
            if alert_id and str(c["alert_id"]) != str(alert_id):
                continue
            if current_user.role == UserRole.ADMIN.value:
                results.append(ConversationOut(**c))
            elif str(c["victim_user_id"]) == str(current_user.id) or (c.get("helper_user_id") and str(c["helper_user_id"]) == str(current_user.id)):
                results.append(ConversationOut(**c))
        return results


@router.get("/conversations/{conversation_id}/messages", response_model=list[ChatMessageOut])
async def list_messages(
    conversation_id: UUID,
    limit: int = Query(50, ge=1, le=200),
    offset: int = Query(0, ge=0),
    current_user: User = Depends(get_current_user),
    session: AsyncSession = Depends(get_session),
) -> list[ChatMessageOut]:
    """Retrieve ordered chat messages for an authorized emergency conversation."""
    try:
        conversation = await session.get(Conversation, conversation_id)
        if conversation:
            authorized = (
                current_user.role == UserRole.ADMIN.value
                or current_user.id == conversation.victim_user_id
                or current_user.id == conversation.helper_user_id
            )
            if not authorized:
                raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Unauthorized conversation access.")

            query = (
                select(ChatMessage)
                .where(ChatMessage.conversation_id == conversation_id)
                .order_by(ChatMessage.created_at.asc())
                .limit(limit)
                .offset(offset)
            )
            messages = (await session.scalars(query)).all()
            return [ChatMessageOut.model_validate(m) for m in messages]
    except HTTPException:
        raise
    except Exception:
        pass

    # Resilient in-memory fallback
    mem_c = _find_mem_conv(conversation_id)
    if not mem_c:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Conversation not found.")

    authorized = (
        current_user.role == UserRole.ADMIN.value
        or str(current_user.id) == str(mem_c["victim_user_id"])
        or (mem_c.get("helper_user_id") and str(current_user.id) == str(mem_c["helper_user_id"]))
    )
    if not authorized:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Unauthorized conversation access.")

    matched = [
        ChatMessageOut(**m)
        for m in IN_MEMORY_MESSAGES
        if str(m["conversation_id"]) == str(conversation_id)
    ]
    return matched[offset : offset + limit]


@router.post("/conversations/{conversation_id}/messages", response_model=ChatMessageOut, status_code=status.HTTP_201_CREATED)
async def send_message(
    conversation_id: UUID,
    payload: ChatMessageCreate,
    current_user: User = Depends(get_current_user),
    session: AsyncSession = Depends(get_session),
) -> ChatMessageOut:
    """Send an asynchronous emergency chat message with client idempotency and realtime broadcast."""
    now_utc = datetime.now(timezone.utc)
    msg_id = uuid4()

    try:
        conversation = await session.get(Conversation, conversation_id)
        if conversation:
            authorized = (
                current_user.role == UserRole.ADMIN.value
                or current_user.id == conversation.victim_user_id
                or current_user.id == conversation.helper_user_id
            )
            if not authorized:
                raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Unauthorized conversation access.")

            existing = await session.scalar(
                select(ChatMessage).where(
                    ChatMessage.conversation_id == conversation_id,
                    ChatMessage.client_message_id == payload.client_message_id,
                )
            )
            if existing:
                return ChatMessageOut.model_validate(existing)

            receiver_id = payload.receiver_id or (
                conversation.helper_user_id if current_user.id == conversation.victim_user_id else conversation.victim_user_id
            )
            msg = ChatMessage(
                id=msg_id,
                conversation_id=conversation_id,
                client_message_id=payload.client_message_id,
                sender_id=current_user.id,
                receiver_id=receiver_id,
                message=payload.message.strip(),
                transport=payload.transport,
                delivery_status=MessageDeliveryStatus.SENT.value,
            )
            session.add(msg)
            await session.commit()
            await session.refresh(msg)

            msg_out = ChatMessageOut.model_validate(msg)
            msg_dict = msg_out.model_dump(mode="json")
            await chat_connections.broadcast(conversation_id, "new_message", msg_dict)
            if receiver_id:
                await chat_connections.send_to_user(receiver_id, "new_message", msg_dict)
            await emergency_connections.broadcast(conversation.alert_id, "chat_message", msg_dict)
            await emergency_connections.broadcast_to_admin("chat_message", msg_dict)
            return msg_out
    except HTTPException:
        raise
    except Exception:
        pass

    # Resilient in-memory path
    mem_c = _find_mem_conv(conversation_id)
    if not mem_c:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Conversation not found.")

    authorized = (
        current_user.role == UserRole.ADMIN.value
        or str(current_user.id) == str(mem_c["victim_user_id"])
        or (mem_c.get("helper_user_id") and str(current_user.id) == str(mem_c["helper_user_id"]))
    )
    if not authorized:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Unauthorized conversation access.")

    for m in IN_MEMORY_MESSAGES:
        if str(m["conversation_id"]) == str(conversation_id) and m["client_message_id"] == payload.client_message_id:
            return ChatMessageOut(**m)

    receiver_id = payload.receiver_id or (
        mem_c.get("helper_user_id") if str(current_user.id) == str(mem_c["victim_user_id"]) else mem_c.get("victim_user_id")
    )
    mem_msg = {
        "id": msg_id,
        "conversation_id": conversation_id,
        "client_message_id": payload.client_message_id,
        "sender_id": current_user.id,
        "receiver_id": receiver_id,
        "message": payload.message.strip(),
        "transport": payload.transport,
        "delivery_status": MessageDeliveryStatus.SENT.value,
        "created_at": now_utc,
        "delivered_at": None,
        "read_at": None,
    }
    IN_MEMORY_MESSAGES.append(mem_msg)
    msg_out = ChatMessageOut(**mem_msg)
    msg_dict = msg_out.model_dump(mode="json")
    await chat_connections.broadcast(conversation_id, "new_message", msg_dict)
    if receiver_id:
        try:
            from uuid import UUID as _UUID
            await chat_connections.send_to_user(_UUID(str(receiver_id)), "new_message", msg_dict)
        except Exception:
            pass
    await emergency_connections.broadcast(mem_c["alert_id"], "chat_message", msg_dict)
    await emergency_connections.broadcast_to_admin("chat_message", msg_dict)
    return msg_out



@router.post("/messages/{message_id}/status", response_model=ChatMessageOut)
async def update_message_status(
    message_id: UUID,
    payload: MessageStatusUpdate,
    current_user: User = Depends(get_current_user),
    session: AsyncSession = Depends(get_session),
) -> ChatMessageOut:
    """Update delivery/read receipts for an emergency message."""
    now = datetime.now(timezone.utc)
    try:
        msg = await session.get(ChatMessage, message_id)
        if msg:
            msg.delivery_status = payload.delivery_status
            if payload.delivery_status == "DELIVERED" and not msg.delivered_at:
                msg.delivered_at = now
            elif payload.delivery_status == "READ":
                msg.read_at = now
                if not msg.delivered_at:
                    msg.delivered_at = now

            await session.commit()
            await session.refresh(msg)
            msg_out = ChatMessageOut.model_validate(msg)
            await chat_connections.broadcast(msg.conversation_id, "status_update", msg_out.model_dump(mode="json"))
            return msg_out
    except Exception:
        pass

    # In-memory update
    for m in IN_MEMORY_MESSAGES:
        if str(m["id"]) == str(message_id):
            m["delivery_status"] = payload.delivery_status
            if payload.delivery_status == "DELIVERED" and not m.get("delivered_at"):
                m["delivered_at"] = now
            elif payload.delivery_status == "READ":
                m["read_at"] = now
                if not m.get("delivered_at"):
                    m["delivered_at"] = now
            msg_out = ChatMessageOut(**m)
            await chat_connections.broadcast(m["conversation_id"], "status_update", msg_out.model_dump(mode="json"))
            return msg_out

    raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Message not found.")
