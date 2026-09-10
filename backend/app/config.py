from functools import lru_cache

from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", extra="ignore")

    environment: str = "development"
    database_url: str
    jwt_secret: str
    otp_hmac_secret: str
    cors_origins: str = "http://localhost:3000,http://localhost:8080"
    emergency_radius_meters: int = 2000
    emergency_number: str = "112"
    location_retention_days: int = 90
    dev_otp_code: str | None = None
    firebase_credentials_path: str | None = None
    twilio_account_sid: str | None = None
    twilio_auth_token: str | None = None
    twilio_from_number: str | None = None

    admin_username: str = "admin"
    admin_password: str = "bhaisecureadmin2026"
    apk_version: str = "1.2.0"
    apk_size_mb: str = "47.5 MB"
    apk_download_url: str | None = None
    apk_file_path: str = "../bhai_app.apk"
    live_location_interval_seconds: int = 5
    session_expiry_minutes: int = 60

    @property
    def async_database_url(self) -> str:
        url = self.database_url.strip()
        if url.startswith("postgres://"):
            return url.replace("postgres://", "postgresql+asyncpg://", 1)
        if url.startswith("postgresql://") and not url.startswith("postgresql+"):
            return url.replace("postgresql://", "postgresql+asyncpg://", 1)
        return url

    @property
    def origins(self) -> list[str]:
        return [origin.strip() for origin in self.cors_origins.split(",") if origin.strip()]



@lru_cache
def get_settings() -> Settings:
    return Settings()
