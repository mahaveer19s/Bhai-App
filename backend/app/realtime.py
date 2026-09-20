import asyncio
from collections import defaultdict
from typing import Any
from uuid import UUID

from fastapi import WebSocket


class EmergencyConnectionManager:
    def __init__(self) -> None:
        self._connections: dict[UUID, set[WebSocket]] = defaultdict(set)
        self._user_connections: dict[UUID, set[WebSocket]] = defaultdict(set)
        self._admin_connections: set[WebSocket] = set()

    async def connect(self, emergency_id: UUID, socket: WebSocket) -> None:
        await socket.accept()
        self._connections[emergency_id].add(socket)

    def disconnect(self, emergency_id: UUID, socket: WebSocket) -> None:
        self._connections[emergency_id].discard(socket)
        if not self._connections[emergency_id]:
            self._connections.pop(emergency_id, None)

    async def connect_user(self, user_id: UUID, socket: WebSocket) -> None:
        await socket.accept()
        self._user_connections[user_id].add(socket)

    def disconnect_user(self, user_id: UUID, socket: WebSocket) -> None:
        self._user_connections[user_id].discard(socket)
        if not self._user_connections[user_id]:
            self._user_connections.pop(user_id, None)

    async def connect_admin(self, socket: WebSocket) -> None:
        await socket.accept()
        self._admin_connections.add(socket)

    def disconnect_admin(self, socket: WebSocket) -> None:
        self._admin_connections.discard(socket)

    async def broadcast_to_user(self, user_id: UUID, event: str, data: dict[str, Any]) -> None:
        message = {"event": event, "data": data}
        stale: list[WebSocket] = []
        for socket in list(self._user_connections.get(user_id, set())):
            try:
                await socket.send_json(message)
            except Exception:
                stale.append(socket)
        for socket in stale:
            self.disconnect_user(user_id, socket)

    async def broadcast_to_users(self, user_ids: list[UUID], event: str, data: dict[str, Any]) -> None:
        await asyncio.gather(*(self.broadcast_to_user(uid, event, data) for uid in user_ids), return_exceptions=True)

    async def broadcast_to_admin(self, event: str, data: dict[str, Any]) -> None:
        message = {"event": event, "data": data}
        stale: list[WebSocket] = []
        for socket in list(self._admin_connections):
            try:
                await socket.send_json(message)
            except Exception:
                stale.append(socket)
        for socket in stale:
            self.disconnect_admin(socket)

    async def broadcast(self, emergency_id: UUID, event: str, data: dict[str, Any]) -> None:
        message = {"event": event, "data": data}
        stale: list[WebSocket] = []
        for socket in list(self._connections.get(emergency_id, set())):
            try:
                await socket.send_json(message)
            except Exception:
                stale.append(socket)
        for socket in stale:
            self.disconnect(emergency_id, socket)

    async def close_event(self, emergency_id: UUID) -> None:
        sockets = list(self._connections.pop(emergency_id, set()))
        await asyncio.gather(*(socket.close(code=1000) for socket in sockets), return_exceptions=True)


emergency_connections = EmergencyConnectionManager()


class ChatConnectionManager:
    def __init__(self) -> None:
        self._connections: dict[UUID, set[WebSocket]] = defaultdict(set)
        self._user_connections: dict[UUID, set[WebSocket]] = defaultdict(set)

    async def connect(self, conversation_id: UUID, socket: WebSocket) -> None:
        await socket.accept()
        self._connections[conversation_id].add(socket)

    def disconnect(self, conversation_id: UUID, socket: WebSocket) -> None:
        self._connections[conversation_id].discard(socket)
        if not self._connections[conversation_id]:
            self._connections.pop(conversation_id, None)

    async def connect_user(self, user_id: UUID, socket: WebSocket) -> None:
        await socket.accept()
        self._user_connections[user_id].add(socket)

    def disconnect_user(self, user_id: UUID, socket: WebSocket) -> None:
        self._user_connections[user_id].discard(socket)
        if not self._user_connections[user_id]:
            self._user_connections.pop(user_id, None)

    async def broadcast(self, conversation_id: UUID, event: str, data: dict[str, Any]) -> None:
        message = {"event": event, "data": data}
        stale: list[WebSocket] = []
        for socket in list(self._connections.get(conversation_id, set())):
            try:
                await socket.send_json(message)
            except Exception:
                stale.append(socket)
        for socket in stale:
            self.disconnect(conversation_id, socket)

    async def send_to_user(self, user_id: UUID, event: str, data: dict[str, Any]) -> None:
        message = {"event": event, "data": data}
        stale: list[WebSocket] = []
        for socket in list(self._user_connections.get(user_id, set())):
            try:
                await socket.send_json(message)
            except Exception:
                stale.append(socket)
        for socket in stale:
            self.disconnect_user(user_id, socket)


chat_connections = ChatConnectionManager()


