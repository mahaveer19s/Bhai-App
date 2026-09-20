import hashlib
import hmac
import secrets
from datetime import UTC, datetime, timedelta
from uuid import UUID

from jose import JWTError, jwt

from app.config import get_settings

ALGORITHM = "HS256"
ACCESS_TOKEN_MINUTES = 60 * 24 * 30


def create_otp() -> str:
    settings = get_settings()
    if settings.environment.lower() != "production" and settings.dev_otp_code:
        return settings.dev_otp_code
    return f"{secrets.randbelow(1_000_000):06d}"


def hash_otp(phone: str, code: str) -> str:
    secret = get_settings().otp_hmac_secret.encode()
    return hmac.new(secret, f"{phone}:{code}".encode(), hashlib.sha256).hexdigest()


def verify_otp(phone: str, code: str, expected_hash: str) -> bool:
    return hmac.compare_digest(hash_otp(phone, code), expected_hash)


def create_access_token(user_id: UUID, role: str) -> str:
    expires_at = datetime.now(UTC) + timedelta(minutes=ACCESS_TOKEN_MINUTES)
    return jwt.encode({"sub": str(user_id), "role": role, "exp": expires_at}, get_settings().jwt_secret, algorithm=ALGORITHM)


def read_access_token(token: str) -> tuple[UUID, str]:
    try:
        payload = jwt.decode(token, get_settings().jwt_secret, algorithms=[ALGORITHM])
        return UUID(payload["sub"]), str(payload.get("role", "USER"))
    except (JWTError, KeyError, ValueError) as exc:
        raise ValueError("Invalid or expired access token") from exc


import ipaddress
from fastapi import Request


def get_observed_client_ip(request: Request) -> dict[str, str | int | bool] | None:
    """Securely resolve the real server-observed client IP address.

    Security Controls:
    1. Direct Socket Check: Reads peer connection address (request.client.host).
    2. Trusted Proxy Guard: Only evaluates X-Forwarded-For or X-Real-IP if the peer
       connection originates from a verified, explicitly configured trusted reverse proxy.
    3. RFC 1918 / Private IP Classification: Differentiates private/loopback/carrier-grade NAT
       from globally routable public IPs.
    4. Offline/Missing Guard: Returns None when no connection is present without fabricating dummy IPs.
    """
    if not request.client or not request.client.host:
        return None

    settings = get_settings()
    peer_ip_str = request.client.host.strip()
    trusted_list = settings.trusted_proxies_list

    resolved_ip_str = peer_ip_str

    # Only process proxy headers if the direct socket connection is from a trusted proxy
    if peer_ip_str in trusted_list:
        forwarded_for = request.headers.get("X-Forwarded-For")
        real_ip = request.headers.get("X-Real-IP")
        if forwarded_for:
            candidate = forwarded_for.split(",")[0].strip()
            if candidate:
                resolved_ip_str = candidate
        elif real_ip:
            resolved_ip_str = real_ip.strip()

    try:
        ip_obj = ipaddress.ip_address(resolved_ip_str)
        return {
            "ip": str(ip_obj),
            "version": ip_obj.version,
            "is_private": ip_obj.is_private,
            "is_loopback": ip_obj.is_loopback,
            "is_global": ip_obj.is_global,
            "scope": "PRIVATE" if (ip_obj.is_private or ip_obj.is_loopback) else "GLOBAL",
        }
    except ValueError:
        return None

