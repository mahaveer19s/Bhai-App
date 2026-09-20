import asyncio
import logging
from collections import defaultdict
from dataclasses import dataclass, field
from datetime import UTC, datetime
from typing import Any, Callable, Coroutine
from uuid import UUID, uuid4

logger = logging.getLogger("bhai.event_bus")


@dataclass
class BhaiEvent:
    event_id: str = field(default_factory=lambda: str(uuid4()))
    topic: str = ""
    payload: dict[str, Any] = field(default_factory=dict)
    timestamp: datetime = field(default_factory=lambda: datetime.now(UTC))
    source: str = "bhai-backend"
    version: int = 1


class AsyncEventBus:
    """
    Lightweight, ultra-fast asynchronous event bus for decoupled incident and communication handling.
    Processes events concurrently without blocking HTTP request execution cycles.
    """

    def __init__(self, max_queue_size: int = 10000) -> None:
        self._queue: asyncio.Queue[BhaiEvent] = asyncio.Queue(maxsize=max_queue_size)
        self._handlers: dict[str, list[Callable[[BhaiEvent], Coroutine[Any, Any, None]]]] = defaultdict(list)
        self._worker_task: asyncio.Task | None = None
        self._running: bool = False

    def subscribe(self, topic: str, handler: Callable[[BhaiEvent], Coroutine[Any, Any, None]]) -> None:
        """Register an async subscriber for a given event topic."""
        self._handlers[topic].append(handler)

    async def publish(self, topic: str, payload: dict[str, Any], source: str = "api") -> BhaiEvent:
        """
        Publish an event to the queue asynchronously.
        Guarantees non-blocking fast response to caller.
        """
        event = BhaiEvent(topic=topic, payload=payload, source=source)
        try:
            self._queue.put_nowait(event)
        except asyncio.QueueFull:
            logger.warning("Event bus queue full! Spawning direct background dispatch for topic: %s", topic)
            asyncio.create_task(self._dispatch_event(event))
        return event

    async def _dispatch_event(self, event: BhaiEvent) -> None:
        """Route event to matching topic handlers and wildcard '*' handlers."""
        handlers = list(self._handlers.get(event.topic, [])) + list(self._handlers.get("*", []))
        if not handlers:
            return

        for handler in handlers:
            try:
                await handler(event)
            except Exception as exc:
                logger.error("Error executing handler %s for event %s: %s", handler.__name__, event.topic, exc)

    async def _worker_loop(self) -> None:
        """Continuous background worker draining event queue."""
        while self._running:
            try:
                event = await self._queue.get()
                await self._dispatch_event(event)
                self._queue.task_done()
            except asyncio.CancelledError:
                break
            except Exception as exc:
                logger.error("Event loop error: %s", exc)

    def start(self) -> None:
        if not self._running:
            self._running = True
            self._worker_task = asyncio.create_task(self._worker_loop())
            logger.info("Bhai AsyncEventBus started successfully.")

    async def stop(self) -> None:
        self._running = False
        if self._worker_task:
            self._worker_task.cancel()
            try:
                await self._worker_task
            except asyncio.CancelledError:
                pass
        logger.info("Bhai AsyncEventBus stopped.")


# Global Event Bus Singleton
event_bus = AsyncEventBus()
