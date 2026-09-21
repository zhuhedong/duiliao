"""Key-exchange endpoints. These are intentionally unencrypted (bootstrap)."""
from __future__ import annotations

import time

from fastapi import APIRouter, HTTPException, status

from app.core.crypto import rsa_manager, session_store
from app.schemas.crypto import (
    HandshakeRequest,
    HandshakeResponse,
    PublicKeyResponse,
)

router = APIRouter(prefix="/crypto", tags=["crypto"])


@router.get("/public-key", response_model=PublicKeyResponse)
def get_public_key() -> PublicKeyResponse:
    """Return the server RSA public key used to wrap AES session keys."""
    return PublicKeyResponse(
        keyId=rsa_manager.key_id,
        algorithm="RSA-OAEP-256",
        publicKey=rsa_manager.public_key_spki_b64,
        serverTime=int(time.time()),
    )


@router.post("/handshake", response_model=HandshakeResponse)
def handshake(payload: HandshakeRequest) -> HandshakeResponse:
    """Register a client-generated AES key and return an opaque session id."""
    try:
        aes_key = rsa_manager.decrypt_aes_key(payload.encryptedKey)
    except Exception:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Could not decrypt session key",
        )
    try:
        session_id, ttl = session_store.create(aes_key)
    except ValueError:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Invalid AES key length",
        )
    # serverTime lets the client correct for local clock skew before signing;
    # without it every request from a skewed device fails with bad_timestamp.
    return HandshakeResponse(
        sessionId=session_id, expiresIn=ttl, serverTime=int(time.time())
    )
