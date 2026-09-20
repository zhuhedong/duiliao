"""Application-layer transport encryption.

Scheme (hybrid, works identically for web + native app clients):

  1. Client fetches the server RSA public key           GET  /crypto/public-key
  2. Client generates a random AES-256 key, encrypts it
     with the server RSA public key (RSA-OAEP-SHA256)
     and registers it                                    POST /crypto/handshake
     -> server returns an opaque `sessionId`
  3. Every subsequent API call carries `X-Session-Id`.
     Request bodies are AES-256-GCM encrypted; responses
     are AES-256-GCM encrypted with the same session key.

AES-GCM provides confidentiality + integrity of the payload. A separate HMAC
signature + timestamp + nonce (see security.py) protects against tampering of
the envelope/metadata and against replay.

Wire format for AES-GCM (interoperable with browser Web Crypto API):
  ciphertext field = base64( ciphertext_bytes || 16-byte GCM tag )

Implemented with `pycryptodome` (no OpenSSL/Rust build dependency).

NOTE: the session-key store here is in-memory and therefore single-process.
For horizontally-scaled production deployments back it with Redis.
"""
from __future__ import annotations

import base64
import secrets
import time
from dataclasses import dataclass
from threading import Lock
from typing import Dict, Optional

from Crypto.Cipher import AES, PKCS1_OAEP
from Crypto.Hash import SHA256
from Crypto.PublicKey import RSA

from app.core.config import settings

_TAG_LEN = 16  # AES-GCM authentication tag length (bytes)
_IV_LEN = 12   # 96-bit nonce, recommended for GCM


def b64e(data: bytes) -> str:
    return base64.b64encode(data).decode("ascii")


def b64d(data: str) -> bytes:
    return base64.b64decode(data)


class RSAKeyManager:
    """Holds the server RSA keypair used for AES key exchange."""

    def __init__(self) -> None:
        if settings.RSA_PRIVATE_KEY_PEM.strip():
            self._key = RSA.import_key(settings.RSA_PRIVATE_KEY_PEM)
        else:
            self._key = RSA.generate(settings.RSA_KEY_SIZE)
            if not settings.is_production:
                pem = self._key.export_key(format="PEM").decode()
                print(
                    "[crypto] No RSA_PRIVATE_KEY_PEM set; generated an ephemeral "
                    "dev keypair. Pin it in backend/.env to keep it stable across "
                    "restarts:\nRSA_PRIVATE_KEY_PEM=\"" + pem.strip() + "\""
                )
        self._decryptor = PKCS1_OAEP.new(self._key, hashAlgo=SHA256)
        self.key_id = secrets.token_hex(8)

    @property
    def public_key_spki_b64(self) -> str:
        """Public key as base64-encoded DER (SubjectPublicKeyInfo / SPKI).

        This is exactly what `crypto.subtle.importKey('spki', ...)` expects on
        the web / native-app side.
        """
        der = self._key.publickey().export_key(format="DER")
        return b64e(der)

    def decrypt_aes_key(self, encrypted_key_b64: str) -> bytes:
        """Decrypt an AES key that was wrapped with the server public key."""
        return self._decryptor.decrypt(b64d(encrypted_key_b64))


@dataclass
class SessionKey:
    key: bytes
    created_at: float
    expires_at: float


class SessionKeyStore:
    """In-memory TTL store mapping sessionId -> AES key."""

    def __init__(self, ttl_seconds: int) -> None:
        self._ttl = ttl_seconds
        self._store: Dict[str, SessionKey] = {}
        self._lock = Lock()

    def create(self, aes_key: bytes) -> tuple[str, int]:
        if len(aes_key) not in (16, 24, 32):
            raise ValueError("AES key must be 128/192/256-bit")
        session_id = secrets.token_urlsafe(32)
        now = time.time()
        with self._lock:
            self._store[session_id] = SessionKey(
                key=aes_key, created_at=now, expires_at=now + self._ttl
            )
        return session_id, self._ttl

    def get(self, session_id: str) -> Optional[bytes]:
        now = time.time()
        with self._lock:
            entry = self._store.get(session_id)
            if entry is None:
                return None
            if entry.expires_at < now:
                self._store.pop(session_id, None)
                return None
            return entry.key

    def revoke(self, session_id: str) -> None:
        with self._lock:
            self._store.pop(session_id, None)

    def purge_expired(self) -> None:
        now = time.time()
        with self._lock:
            for k in [k for k, v in self._store.items() if v.expires_at < now]:
                self._store.pop(k, None)


# --- AES-GCM payload helpers (Web Crypto compatible) -------------------------

def aes_encrypt(key: bytes, plaintext: bytes) -> dict:
    """Encrypt plaintext -> {iv, ciphertext} where ciphertext = ct||tag."""
    iv = secrets.token_bytes(_IV_LEN)
    cipher = AES.new(key, AES.MODE_GCM, nonce=iv, mac_len=_TAG_LEN)
    ct, tag = cipher.encrypt_and_digest(plaintext)
    return {"iv": b64e(iv), "ciphertext": b64e(ct + tag)}


def aes_decrypt(key: bytes, iv_b64: str, ciphertext_b64: str) -> bytes:
    """Decrypt {iv, ciphertext} where ciphertext = ct||tag (Web Crypto style)."""
    iv = b64d(iv_b64)
    blob = b64d(ciphertext_b64)
    if len(blob) < _TAG_LEN:
        raise ValueError("ciphertext too short")
    ct, tag = blob[:-_TAG_LEN], blob[-_TAG_LEN:]
    cipher = AES.new(key, AES.MODE_GCM, nonce=iv, mac_len=_TAG_LEN)
    return cipher.decrypt_and_verify(ct, tag)


# Singletons wired at import time.
rsa_manager = RSAKeyManager()
session_store = SessionKeyStore(settings.SESSION_KEY_TTL_SECONDS)
