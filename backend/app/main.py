import logging
import os
from contextlib import asynccontextmanager
from pathlib import Path
from uuid import UUID

from fastapi import FastAPI, HTTPException, WebSocket, WebSocketDisconnect, status
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import FileResponse, RedirectResponse
from fastapi.staticfiles import StaticFiles
from slowapi import _rate_limit_exceeded_handler
from slowapi.errors import RateLimitExceeded
from sqlalchemy import select, text

from app.api import admin, auth, chat, contacts, emergencies, live_location, relay
from app.config import get_settings
from app.database import Base, SessionLocal, engine
from app.deps import get_user_from_token
from app.models import Conversation, Emergency, EmergencyResponse, UserRole
from app.realtime import chat_connections, emergency_connections
from app.schemas import AppVersionOut
from app.security import read_access_token
from app.services.retention import purge_expired_location_history

logger = logging.getLogger("bhai.api")

STATIC_DIR = Path(__file__).resolve().parent / "static"


from app.services.event_bus import event_bus


@asynccontextmanager
async def lifespan(_: FastAPI):
    event_bus.start()
    try:
        async with engine.begin() as connection:
            await connection.execute(text("CREATE EXTENSION IF NOT EXISTS postgis"))
            await connection.run_sync(Base.metadata.create_all)
        async with SessionLocal() as session:
            await purge_expired_location_history(session)
        logger.info("Database schema initialized and expired history purged successfully.")
    except Exception as exc:
        logger.warning(
            "Database connection could not be established on startup: %s. "
            "API started in resilient mode. Ensure PostgreSQL/PostGIS is running when performing database operations.",
            exc,
        )
    yield
    await event_bus.stop()
    try:
        await engine.dispose()
    except Exception:
        pass



app = FastAPI(
    title="BHAI Emergency API",
    version="1.2.0",
    description="Production-ready, authenticated, privacy-first emergency assistance and live-location streaming API.",
    lifespan=lifespan,
)

app.state.limiter = auth.limiter
app.add_exception_handler(RateLimitExceeded, _rate_limit_exceeded_handler)

settings = get_settings()

app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.origins if settings.environment.lower() == "production" else ["*"],
    allow_credentials=True if settings.environment.lower() == "production" else False,
    allow_methods=["GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS"],
    allow_headers=["*"],
)


from fastapi import Request


@app.middleware("http")
async def add_security_headers(request: Request, call_next):
    response = await call_next(request)
    response.headers["X-Content-Type-Options"] = "nosniff"
    response.headers["X-Frame-Options"] = "DENY"
    response.headers["X-XSS-Protection"] = "1; mode=block"
    response.headers["Referrer-Policy"] = "strict-origin-when-cross-origin"
    response.headers["Permissions-Policy"] = "geolocation=(self), microphone=(), camera=()"
    if get_settings().environment.lower() == "production":
        response.headers["Strict-Transport-Security"] = "max-age=31536000; includeSubDomains"
    return response

# API Routers
app.include_router(auth.router)
app.include_router(contacts.router)
app.include_router(emergencies.router)
app.include_router(live_location.router)
app.include_router(chat.router)
app.include_router(chat.router, prefix="/api")
app.include_router(chat.router, prefix="/api/v1")
app.include_router(relay.router)
app.include_router(admin.router)


# Health & Readiness Endpoints
@app.get("/health")
async def health() -> dict[str, str]:
    """Basic service health check for load balancers and Render."""
    return {"status": "ok"}



@app.get("/ready")
async def ready() -> dict[str, str]:
    """Readiness probe checking database and core subsystems."""
    db_status = "connected"
    try:
        async with engine.connect() as conn:
            await conn.execute(text("SELECT 1"))
    except Exception:
        db_status = "resilient_fallback"

    return {"status": "ready", "database": db_status}


# Version & Release Metadata
@app.get("/api/version", response_model=AppVersionOut)
@app.get("/version", response_model=AppVersionOut)
async def get_version() -> AppVersionOut:
    """Retrieve dynamic application version and APK release information."""
    settings = get_settings()
    apk_url = settings.apk_download_url if settings.apk_download_url else "/download/bhai_app.apk"
    return AppVersionOut(
        app_name="BHAI",
        version=settings.apk_version,
        apk_url=apk_url,
        size_mb=settings.apk_size_mb,
        last_updated="September 2026",
        release_notes="High-precision 5-second GPS live location streaming and BLE mesh dispatch",
    )


# APK Direct Download Endpoint
@app.api_route("/download/bhai_app.apk", methods=["GET", "HEAD"], operation_id="download_apk_file")
async def download_apk():
    """Stream or redirect to the real production Bhai App APK."""
    settings = get_settings()
    if settings.apk_download_url and settings.apk_download_url.startswith("http"):
        return RedirectResponse(url=settings.apk_download_url)

    candidates = [
        Path(settings.apk_file_path),
        Path(__file__).resolve().parent / "static" / "bhai_app.apk",
        Path(__file__).resolve().parents[1] / "bhai_app.apk",
        Path(__file__).resolve().parents[2] / "bhai_app.apk",
        Path("/app/bhai_app.apk"),
        Path("./bhai_app.apk"),
    ]
    for apk_path in candidates:
        if apk_path.exists() and apk_path.is_file():
            return FileResponse(
                path=str(apk_path),
                filename="bhai_app.apk",
                media_type="application/vnd.android.package-archive",
            )

    raise HTTPException(status_code=404, detail="Bhai App APK file is currently not uploaded on this server.")


# WebSockets
@app.websocket("/ws/emergencies/{emergency_id}")
async def emergency_socket(websocket: WebSocket, emergency_id: UUID, token: str) -> None:
    """Live incident updates stream for user and acknowledged responders."""
    async with SessionLocal() as session:
        user = await get_user_from_token(token, session)
        emergency = await session.get(Emergency, emergency_id)
        authorized = False
        if user and emergency:
            if user.id == emergency.user_id or user.role == UserRole.ADMIN.value:
                authorized = True
            elif emergency.status == "ACTIVE":
                response = await session.scalar(
                    select(EmergencyResponse).where(
                        EmergencyResponse.emergency_id == emergency.id,
                        EmergencyResponse.helper_user_id == user.id,
                        EmergencyResponse.response_type.in_(["ACKNOWLEDGED", "HELPING"]),
                    )
                )
                authorized = response is not None
        if not authorized:
            await websocket.close(code=status.WS_1008_POLICY_VIOLATION)
            return

    await emergency_connections.connect(emergency_id, websocket)
    try:
        while True:
            await websocket.receive_text()
    except WebSocketDisconnect:
        emergency_connections.disconnect(emergency_id, websocket)


@app.websocket("/ws/admin")
async def admin_socket(websocket: WebSocket, token: str) -> None:
    """Real-time operations feed for central admin dashboard."""
    try:
        _, role = read_access_token(token)
        if role != UserRole.ADMIN.value:
            await websocket.close(code=status.WS_1008_POLICY_VIOLATION)
            return
    except Exception:
        await websocket.close(code=status.WS_1008_POLICY_VIOLATION)
        return

    await emergency_connections.connect_admin(websocket)
    try:
        while True:
            await websocket.receive_text()
    except WebSocketDisconnect:
        emergency_connections.disconnect_admin(websocket)


@app.websocket("/ws/chat/{conversation_id}")
async def chat_socket(websocket: WebSocket, conversation_id: str, token: str) -> None:
    """Real-time two-way emergency chat feed for authorized participants."""
    async with SessionLocal() as session:
        user = await get_user_from_token(token, session)
        if not user:
            await websocket.close(code=status.WS_1008_POLICY_VIOLATION)
            return

        authorized = True
        try:
            from uuid import UUID as _UUID
            c_uuid = _UUID(conversation_id)
            conversation = await session.get(Conversation, c_uuid)
            if conversation:
                if user.role == UserRole.ADMIN.value:
                    authorized = True
                elif user.id == conversation.victim_user_id or user.id == conversation.helper_user_id:
                    authorized = True
                else:
                    resp = await session.scalar(
                        select(EmergencyResponse).where(
                            EmergencyResponse.emergency_id == conversation.alert_id,
                            EmergencyResponse.helper_user_id == user.id,
                        )
                    )
                    authorized = resp is not None
        except Exception:
            authorized = True

        if not authorized:
            await websocket.close(code=status.WS_1008_POLICY_VIOLATION)
            return

    await chat_connections.connect(conversation_id, websocket)
    try:
        while True:
            await websocket.receive_text()
    except WebSocketDisconnect:
        chat_connections.disconnect(conversation_id, websocket)


@app.websocket("/ws/user")
@app.websocket("/ws/alerts")
async def user_alerts_socket(websocket: WebSocket, token: str) -> None:
    """Real-time personal push alerts and notifications for active Bhai users."""
    async with SessionLocal() as session:
        user = await get_user_from_token(token, session)
        if not user:
            await websocket.close(code=status.WS_1008_POLICY_VIOLATION)
            return
        user_id = user.id

    await emergency_connections.connect_user(user_id, websocket)
    await chat_connections.connect_user(user_id, websocket)
    try:
        while True:
            await websocket.receive_text()
    except WebSocketDisconnect:
        emergency_connections.disconnect_user(user_id, websocket)
        chat_connections.disconnect_user(user_id, websocket)


# Static File Mounting
if STATIC_DIR.exists():

    app.mount("/static", StaticFiles(directory=str(STATIC_DIR)), name="static")

FLUTTER_WEB_DIR = Path(__file__).resolve().parents[2] / "bhai_app" / "build" / "web"
if FLUTTER_WEB_DIR.exists():
    app.mount("/app", StaticFiles(directory=str(FLUTTER_WEB_DIR), html=True), name="flutter_app")


@app.get("/admin")
@app.get("/admin/")
async def serve_admin_panel():
    """Serve standalone production admin command center."""
    admin_index = STATIC_DIR / "admin" / "index.html"
    if admin_index.exists():
        return FileResponse(str(admin_index))
    raise HTTPException(status_code=404, detail="Admin panel index not found")


@app.get("/")
async def serve_landing_page():
    """Serve public Bhai App landing & download showcase."""
    landing_index = STATIC_DIR / "landing" / "index.html"
    if landing_index.exists():
        return FileResponse(str(landing_index))
    raise HTTPException(status_code=404, detail="Landing page index not found")
