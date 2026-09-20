"""User-facing schemas."""
from __future__ import annotations

from datetime import datetime

from pydantic import BaseModel, ConfigDict, EmailStr, Field, field_validator

from app.models.user import RegistrationSource, UserRole, UserStatus


class UserPublic(BaseModel):
    """Safe user representation returned to clients (no secrets)."""

    model_config = ConfigDict(from_attributes=True)

    id: str
    username: str | None = None
    email: EmailStr | None = None
    email_verified: bool
    phone: str | None = None
    phone_verified: bool
    display_name: str | None = None
    avatar_url: str | None = None
    locale: str
    timezone: str
    status: UserStatus
    role: UserRole
    registration_source: RegistrationSource
    mfa_enabled: bool
    last_login_at: datetime | None = None
    created_at: datetime


class UserUpdate(BaseModel):
    display_name: str | None = Field(None, max_length=120)
    avatar_url: str | None = Field(None, max_length=512)
    locale: str | None = Field(None, max_length=16)
    timezone: str | None = Field(None, max_length=48)


class PasswordChange(BaseModel):
    current_password: str = Field(..., min_length=1, max_length=128)
    new_password: str = Field(..., min_length=8, max_length=128)

    @field_validator("new_password")
    @classmethod
    def _password_strength(cls, v: str) -> str:
        if not any(c.isalpha() for c in v) or not any(c.isdigit() for c in v):
            raise ValueError("password must contain both letters and numbers")
        return v
