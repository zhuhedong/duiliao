"""Schemas for the crypto handshake endpoints."""
from __future__ import annotations

from pydantic import BaseModel, Field


class PublicKeyResponse(BaseModel):
    keyId: str = Field(..., description="Identifier of the current server RSA key")
    algorithm: str = Field("RSA-OAEP-256", description="Key-wrap algorithm")
    publicKey: str = Field(..., description="Base64 SPKI (DER) RSA public key")


class HandshakeRequest(BaseModel):
    encryptedKey: str = Field(
        ..., description="Base64 RSA-OAEP(SHA-256) wrapped AES-256 session key"
    )


class HandshakeResponse(BaseModel):
    sessionId: str = Field(..., description="Opaque id referencing the AES session key")
    expiresIn: int = Field(..., description="Seconds until the session key expires")


class EncryptedEnvelope(BaseModel):
    """Shape of an AES-GCM encrypted request/response body."""

    iv: str = Field(..., description="Base64 12-byte GCM nonce")
    ciphertext: str = Field(..., description="Base64 (ciphertext || 16-byte GCM tag)")
