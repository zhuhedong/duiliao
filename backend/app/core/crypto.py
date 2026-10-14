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

NOTE: session keys default to the app database (CRYPTO_STORE=database) so
multiple API workers share handshakes. Set CRYPTO_STORE=memory for the
legacy single-process store. An in-process dict is always used as L1 cache.
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


def normalize_pem(raw: str) -> str:
    """Accept PEM pasted into env UIs that mangle newlines.

    Handles: real newlines, literal "\\n", surrounding quotes, everything
    collapsed onto one line with spaces, or the whole PEM base64-encoded.
    """
    import base64
    import re

    s = raw.strip().strip('"').strip("'").strip()
    s = s.replace("\\r\\n", "\n").replace("\\n", "\n").replace("\r\n", "\n")
    if "-----BEGIN" not in s:
        try:
            s = base64.b64decode(re.sub(r"\s+", "", s)).decode().strip()
        except Exception:
            return raw
    m = re.match(r"^(-----BEGIN [A-Z ]+-----)(.*?)(-----END [A-Z ]+-----)$", s, re.S)
    if not m:
        return s
    body = re.sub(r"\s+", "", m.group(2))
    lines = [body[i:i + 64] for i in range(0, len(body), 64)]
    return "\n".join([m.group(1), *lines, m.group(3)]) + "\n"


class RSAKeyManager:
    """Holds the server RSA keypair used for AES key exchange."""

    def __init__(self) -> None:
        if settings.RSA_PRIVATE_KEY_PEM.strip():
            self._key = RSA.import_key(normalize_pem(settings.RSA_PRIVATE_KEY_PEM))
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
    """TTL store mapping sessionId -> AES key (DB-backed by default)."""

    def __init__(self, ttl_seconds: int) -> None:
        self._ttl = ttl_seconds
        self._store: Dict[str, SessionKey] = {}
        self._lock = Lock()
        self._ops = 0

    def create(self, aes_key: bytes) -> tuple[str, int]:
        if len(aes_key) not in (16, 24, 32):
            raise ValueError("AES key must be 128/192/256-bit")
        session_id = secrets.token_urlsafe(32)
        now = time.time()
        expires = now + self._ttl
        entry = SessionKey(key=aes_key, created_at=now, expires_at=expires)
        with self._lock:
            self._store[session_id] = entry
        if settings.crypto_store_database:
            self._db_put(session_id, aes_key, expires)
        return session_id, self._ttl

    def get(self, session_id: str) -> Optional[bytes]:
        now = time.time()
        with self._lock:
            entry = self._store.get(session_id)
            if entry is not None:
                if entry.expires_at < now:
                    self._store.pop(session_id, None)
                else:
                    return entry.key
        if settings.crypto_store_database:
            key = self._db_get(session_id, now)
            if key is not None:
                with self._lock:
                    self._store[session_id] = SessionKey(
                        key=key, created_at=now, expires_at=now + self._ttl
                    )
                return key
        return None

    def revoke(self, session_id: str) -> None:
        with self._lock:
            self._store.pop(session_id, None)
        if settings.crypto_store_database:
            self._db_delete(session_id)

    def purge_expired(self) -> None:
        now = time.time()
        with self._lock:
            for k in [k for k, v in self._store.items() if v.expires_at < now]:
                self._store.pop(k, None)
        if settings.crypto_store_database:
            self._db_purge(now)

    def _db_put(self, session_id: str, aes_key: bytes, expires: float) -> None:
        try:
            from app.db.session import SessionLocal
            from app.models.crypto_store import CryptoSession

            with SessionLocal() as db:
                row = db.get(CryptoSession, session_id)
                if row is None:
                    db.add(
                        CryptoSession(
                            session_id=session_id,
                            key_b64=b64e(aes_key),
                            expires_at=expires,
                        )
                    )
                else:
                    row.key_b64 = b64e(aes_key)
                    row.expires_at = expires
                db.commit()
        except Exception:
            # L1 memory entry still works for this process.
            pass

    def _db_get(self, session_id: str, now: float) -> Optional[bytes]:
        try:
            from app.db.session import SessionLocal
            from app.models.crypto_store import CryptoSession

            with SessionLocal() as db:
                self._ops += 1
                row = db.get(CryptoSession, session_id)
                if row is None:
                    return None
                if float(row.expires_at) < now:
                    db.delete(row)
                    db.commit()
                    return None
                return b64d(row.key_b64)
        except Exception:
            return None

    def _db_delete(self, session_id: str) -> None:
        try:
            from app.db.session import SessionLocal
            from app.models.crypto_store import CryptoSession

            with SessionLocal() as db:
                row = db.get(CryptoSession, session_id)
                if row is not None:
                    db.delete(row)
                    db.commit()
        except Exception:
            pass

    def _db_purge(self, now: float) -> None:
        try:
            from sqlalchemy import delete

            from app.db.session import SessionLocal
            from app.models.crypto_store import CryptoSession

            with SessionLocal() as db:
                db.execute(delete(CryptoSession).where(CryptoSession.expires_at < now))
                db.commit()
        except Exception:
            pass


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
