from datetime import UTC, datetime, timedelta

from fastapi import APIRouter, Depends, HTTPException, Request, status
from slowapi import Limiter
from slowapi.util import get_remote_address
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.config import get_settings
from app.database import get_session
from app.deps import get_current_user
from app.models import OtpChallenge, User
from app.schemas import AuthRequest, SafetyPreferencesUpdate, TokenOut, UserOut, VerifyOtpRequest
from app.security import create_access_token, create_otp, hash_otp, verify_otp
from app.services.notifications import send_otp

router = APIRouter(prefix="/auth", tags=["auth"])
limiter = Limiter(key_func=get_remote_address)


def normalize_phone(phone: str) -> str:
    return phone.replace(" ", "").replace("-", "")


async def issue_challenge(session: AsyncSession, phone: str) -> None:
    code = create_otp()
    delivered = await send_otp(phone, code)
    if get_settings().environment.lower() == "production" and not delivered:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Verification messaging is temporarily unavailable. Please try again later.",
        )
    session.add(
        OtpChallenge(
            phone=phone,
            code_hash=hash_otp(phone, code),
            expires_at=datetime.now(UTC) + timedelta(minutes=10),
        )
    )
    await session.commit()


@router.post("/register", status_code=status.HTTP_202_ACCEPTED)
@limiter.limit("5/minute")
async def register(request: Request, payload: AuthRequest, session: AsyncSession = Depends(get_session)) -> dict[str, str]:
    phone = normalize_phone(payload.phone)
    user = await session.scalar(select(User).where(User.phone == phone))
    if user is None:
        user = User(phone=phone, display_name=payload.display_name)
        session.add(user)
        await session.flush()
    elif payload.display_name and not user.display_name:
        user.display_name = payload.display_name
    await issue_challenge(session, phone)
    return {"detail": "If this number can receive messages, a verification code has been sent."}


@router.post("/login", status_code=status.HTTP_202_ACCEPTED)
@limiter.limit("5/minute")
async def login(request: Request, payload: AuthRequest, session: AsyncSession = Depends(get_session)) -> dict[str, str]:
    phone = normalize_phone(payload.phone)
    user = await session.scalar(select(User).where(User.phone == phone))
    if user is None:
        # Deliberately return the same response to reduce phone-number enumeration.
        return {"detail": "If this number can receive messages, a verification code has been sent."}
    await issue_challenge(session, phone)
    return {"detail": "If this number can receive messages, a verification code has been sent."}


@router.post("/verify", response_model=TokenOut)
@limiter.limit("10/minute")
async def verify(request: Request, payload: VerifyOtpRequest, session: AsyncSession = Depends(get_session)) -> TokenOut:
    phone = normalize_phone(payload.phone)
    challenge = await session.scalar(
        select(OtpChallenge)
        .where(OtpChallenge.phone == phone, OtpChallenge.consumed_at.is_(None))
        .order_by(OtpChallenge.created_at.desc())
    )
    now = datetime.now(UTC)
    if challenge is None or challenge.expires_at < now or challenge.attempts >= 5:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Verification code is invalid or expired")
    challenge.attempts += 1
    if not verify_otp(phone, payload.code, challenge.code_hash):
        await session.commit()
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Verification code is invalid or expired")

    user = await session.scalar(select(User).where(User.phone == phone))
    if user is None or user.is_suspended:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Account is unavailable")
    challenge.consumed_at = now
    user.is_verified = True
    await session.commit()
    return TokenOut(access_token=create_access_token(user.id, user.role), user=UserOut.model_validate(user))


@router.get("/me", response_model=UserOut)
async def me(user: User = Depends(get_current_user)) -> UserOut:
    return UserOut.model_validate(user)


@router.patch("/preferences", response_model=UserOut)
async def update_preferences(
    payload: SafetyPreferencesUpdate,
    user: User = Depends(get_current_user),
    session: AsyncSession = Depends(get_session),
) -> UserOut:
    for field, value in payload.model_dump(exclude_unset=True).items():
        setattr(user, field, value)
    await session.commit()
    await session.refresh(user)
    return UserOut.model_validate(user)
