"""Authentication request/response schemas."""
from __future__ import annotations

from pydantic import BaseModel, EmailStr, Field, field_validator, model_validator

from app.core.config import settings
from app.models.user import RegistrationSource
from app.schemas.user import UserPublic


class DeviceInfo(BaseModel):
    """Optional client/device metadata attached to a session."""

    deviceId: str | None = Field(None, max_length=128)
    deviceName: str | None = Field(None, max_length=128)
    platform: str | None = Field(None, max_length=16)  # web | ios | android
    appVersion: str | None = Field(None, max_length=32)


class RegisterRequest(BaseModel):
    email: EmailStr | None = None
    phone: str | None = Field(None, max_length=20)
    username: str | None = Field(None, min_length=3, max_length=64)
    password: str = Field(..., min_length=settings.PASSWORD_MIN_LENGTH, max_length=128)
    display_name: str | None = Field(None, max_length=120)
    source: RegistrationSource = RegistrationSource.WEB
    device: DeviceInfo | None = None

    @model_validator(mode="after")
    def _require_identity(self):
        if not self.email and not self.phone:
            raise ValueError("either email or phone is required")
        return self

    @field_validator("password")
    @classmethod
    def _password_strength(cls, v: str) -> str:
        if not any(c.isalpha() for c in v) or not any(c.isdigit() for c in v):
            raise ValueError("password must contain both letters and numbers")
        return v


class BootstrapRequest(BaseModel):
    """Create the very first admin account (first-run only, loopback only)."""

    email: EmailStr | None = None
    phone: str | None = Field(None, max_length=20)
    username: str | None = Field(None, min_length=3, max_length=64)
    password: str = Field(..., min_length=settings.PASSWORD_MIN_LENGTH, max_length=128)
    display_name: str | None = Field(None, max_length=120)
    device: DeviceInfo | None = None

    @model_validator(mode="after")
    def _require_identity(self):
        if not (self.email or self.phone or self.username):
            raise ValueError("email, phone, or username is required")
        return self

    @field_validator("password")
    @classmethod
    def _password_strength(cls, v: str) -> str:
        if not any(c.isalpha() for c in v) or not any(c.isdigit() for c in v):
            raise ValueError("password must contain both letters and numbers")
        return v


class BootstrapStatus(BaseModel):
    available: bool
    reason: str | None = None


class LoginRequest(BaseModel):
    identifier: str = Field(..., description="email, phone, or username")
    password: str = Field(..., min_length=1, max_length=128)
    device: DeviceInfo | None = None


class TokenResponse(BaseModel):
    access_token: str
    refresh_token: str
    token_type: str = "bearer"
    expires_in: int  # access-token lifetime in seconds
    user: UserPublic


class RefreshRequest(BaseModel):
    refresh_token: str


class AccessTokenResponse(BaseModel):
    access_token: str
    refresh_token: str
    token_type: str = "bearer"
    expires_in: int


class LogoutRequest(BaseModel):
    refresh_token: str | None = None
    all_devices: bool = False
