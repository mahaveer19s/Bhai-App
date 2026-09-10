from uuid import UUID

from fastapi import Depends, HTTPException, status
from fastapi.security import OAuth2PasswordBearer
from sqlalchemy.ext.asyncio import AsyncSession

from app.database import get_session
from app.models import User, UserRole
from app.security import read_access_token

DEMO_USER_ID = UUID("782a860c-8cc6-4041-9161-51b808e27c6a")
DEMO_ADMIN_ID = UUID("3960dfc0-a49f-4058-b470-61b9a603cd50")

oauth2_scheme = OAuth2PasswordBearer(tokenUrl="/auth/login", auto_error=False)


async def get_current_user(
    token: str | None = Depends(oauth2_scheme), session: AsyncSession = Depends(get_session)
) -> User:
    if not token:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Authentication credentials were not provided",
            headers={"WWW-Authenticate": "Bearer"},
        )

    try:
        user_id, role = read_access_token(token)
    except ValueError:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid or expired access token",
            headers={"WWW-Authenticate": "Bearer"},
        )

    user = None
    try:
        user = await session.get(User, user_id)
    except Exception:
        pass

    if user is None:
        user = User(
            id=user_id,
            phone="+919999999999",
            display_name="Authenticated User",
            role=role if role in [UserRole.ADMIN.value, UserRole.USER.value] else UserRole.USER.value,
            is_verified=True,
            emergency_alerts_enabled=True,
            location_sharing_enabled=True,
            is_suspended=False,
        )

    if user.is_suspended:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="User account is suspended")

    return user


async def get_admin_user(
    token: str | None = Depends(oauth2_scheme), session: AsyncSession = Depends(get_session)
) -> User:
    if not token:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Admin authentication credentials required",
            headers={"WWW-Authenticate": "Bearer"},
        )

    try:
        user_id, role = read_access_token(token)
    except ValueError:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid or expired access token",
            headers={"WWW-Authenticate": "Bearer"},
        )

    if role != UserRole.ADMIN.value:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Administrator access required",
        )

    user = None
    try:
        user = await session.get(User, user_id)
    except Exception:
        pass

    if user is None:
        user = User(
            id=user_id,
            phone="+919999999999",
            display_name="Admin Operator",
            role=UserRole.ADMIN.value,
            is_verified=True,
            emergency_alerts_enabled=True,
            location_sharing_enabled=True,
            is_suspended=False,
        )

    if user.is_suspended:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Admin account is suspended")

    return user


async def get_user_from_token(token: str, session: AsyncSession) -> User | None:
    try:
        user_id, _ = read_access_token(token)
    except ValueError:
        return None
    try:
        user = await session.get(User, user_id)
        if user and user.is_suspended:
            return None
        return user
    except Exception:
        return None

