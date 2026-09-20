import asyncio
from collections import defaultdict
from typing import Any
from uuid import UUID

from fastapi import WebSocket


class EmergencyConnectionManager:
    def __init__(self) -> None:
        self._connections: dict[str, set[WebSocket]] = defaultdict(set)
        self._user_connections: dict[str, set[WebSocket]] = defaultdict(set)
        self._admin_connections: set[WebSocket] = set()

    async def connect(self, emergency_id: Any, socket: WebSocket) -> None:
        await socket.accept()
        self._connections[str(emergency_id)].add(socket)

    def disconnect(self, emergency_id: Any, socket: WebSocket) -> None:
        eid = str(emergency_id)
        self._connections[eid].discard(socket)
        if not self._connections[eid]:
            self._connections.pop(eid, None)

    async def connect_user(self, user_id: Any, socket: WebSocket) -> None:
        await socket.accept()
        self._user_connections[str(user_id)].add(socket)

    def disconnect_user(self, user_id: Any, socket: WebSocket) -> None:
        uid = str(user_id)
        self._user_connections[uid].discard(socket)
        if not self._user_connections[uid]:
            self._user_connections.pop(uid, None)

    async def connect_admin(self, socket: WebSocket) -> None:
        await socket.accept()
        self._admin_connections.add(socket)

    def disconnect_admin(self, socket: WebSocket) -> None:
        self._admin_connections.discard(socket)

    async def broadcast_to_user(self, user_id: Any, event: str, data: dict[str, Any]) -> None:
        message = {"event": event, "data": data}
        stale: list[WebSocket] = []
        uid = str(user_id)
        for socket in list(self._user_connections.get(uid, set())):
            try:
                await socket.send_json(message)
            except Exception:
                stale.append(socket)
        for socket in stale:
            self.disconnect_user(uid, socket)

    async def broadcast_to_users(self, user_ids: list[Any], event: str, data: dict[str, Any]) -> None:
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

    async def broadcast(self, emergency_id: Any, event: str, data: dict[str, Any]) -> None:
        message = {"event": event, "data": data}
        stale: list[WebSocket] = []
        eid = str(emergency_id)
        for socket in list(self._connections.get(eid, set())):
            try:
                await socket.send_json(message)
            except Exception:
                stale.append(socket)
        for socket in stale:
            self.disconnect(eid, socket)

    async def close_event(self, emergency_id: Any) -> None:
        eid = str(emergency_id)
        sockets = list(self._connections.pop(eid, set()))
        await asyncio.gather(*(socket.close(code=1000) for socket in sockets), return_exceptions=True)


emergency_connections = EmergencyConnectionManager()


class ChatConnectionManager:
    def __init__(self) -> None:
        self._connections: dict[str, set[WebSocket]] = defaultdict(set)
        self._user_connections: dict[str, set[WebSocket]] = defaultdict(set)

    async def connect(self, conversation_id: Any, socket: WebSocket) -> None:
        await socket.accept()
        self._connections[str(conversation_id)].add(socket)

    def disconnect(self, conversation_id: Any, socket: WebSocket) -> None:
        cid = str(conversation_id)
        self._connections[cid].discard(socket)
        if not self._connections[cid]:
            self._connections.pop(cid, None)

    async def connect_user(self, user_id: Any, socket: WebSocket) -> None:
        await socket.accept()
        self._user_connections[str(user_id)].add(socket)

    def disconnect_user(self, user_id: Any, socket: WebSocket) -> None:
        uid = str(user_id)
        self._user_connections[uid].discard(socket)
        if not self._user_connections[uid]:
            self._user_connections.pop(uid, None)

    async def broadcast(self, conversation_id: Any, event: str, data: dict[str, Any]) -> None:
        message = {"event": event, "data": data}
        stale: list[WebSocket] = []
        cid = str(conversation_id)
        for socket in list(self._connections.get(cid, set())):
            try:
                await socket.send_json(message)
            except Exception:
                stale.append(socket)
        for socket in stale:
            self.disconnect(cid, socket)

    async def send_to_user(self, user_id: Any, event: str, data: dict[str, Any]) -> None:
        message = {"event": event, "data": data}
        stale: list[WebSocket] = []
        uid = str(user_id)
        for socket in list(self._user_connections.get(uid, set())):
            try:
                await socket.send_json(message)
            except Exception:
                stale.append(socket)
        for socket in stale:
            self.disconnect_user(uid, socket)


chat_connections = ChatConnectionManager()
