"""A reference encrypted-transport client, used by the tests.

Every ``/api/v1`` route except the two handshake endpoints goes through
``EncryptionMiddleware``, which rejects an unsigned request with
``401 no_session`` before any handler runs. Tests therefore need a client that
speaks the real protocol.

This is deliberately written as a literal, dependency-light implementation of
the wire format rather than reusing the server's helpers, so it doubles as the
executable specification for the Dart port:

* RSA-OAEP with SHA-256 (MGF1-SHA-256, **no label**) to wrap a 32-byte AES key.
* AES-256-GCM with a 12-byte random IV; the 16-byte tag is **appended** to the
  ciphertext, and both IV and ciphertext are **standard** (not URL-safe) base64.
* Signature over ``sessionId\\ntimestamp\\nnonce\\nsha256hex(body)`` where
  ``body`` is the **encrypted** request bytes, LF-separated, no trailing newline,
  HMAC-SHA-256 as lowercase hex.
* An absent body hashes as the SHA-256 of the empty string.
"""
from __future__ import annotations

import base64
import hashlib
import hmac
import json
import secrets
import time
from typing import Any

from Crypto.Cipher import AES, PKCS1_OAEP
from Crypto.Hash import SHA256
from Crypto.PublicKey import RSA

IV_LEN = 12
TAG_LEN = 16
EMPTY_SHA256 = "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"


def b64e(data: bytes) -> str:
    return base64.b64encode(data).decode("ascii")


def b64d(data: str) -> bytes:
    return base64.b64decode(data)


def sha256_hex(data: bytes) -> str:
    return hashlib.sha256(data or b"").hexdigest()


def hmac_sha256_hex(secret: str, message: str) -> str:
    return hmac.new(secret.encode("utf-8"), message.encode("utf-8"), hashlib.sha256).hexdigest()


def canonical_string(session_id: str, timestamp: str, nonce: str, body: bytes) -> str:
    return "\n".join([session_id, timestamp, nonce, sha256_hex(body)])


def aes_encrypt(key: bytes, plaintext: bytes) -> dict[str, str]:
    iv = secrets.token_bytes(IV_LEN)
    cipher = AES.new(key, AES.MODE_GCM, nonce=iv, mac_len=TAG_LEN)
    ct, tag = cipher.encrypt_and_digest(plaintext)
    return {"iv": b64e(iv), "ciphertext": b64e(ct + tag)}


def aes_decrypt(key: bytes, iv_b64: str, ciphertext_b64: str) -> bytes:
    iv = b64d(iv_b64)
    blob = b64d(ciphertext_b64)
    ct, tag = blob[:-TAG_LEN], blob[-TAG_LEN:]
    cipher = AES.new(key, AES.MODE_GCM, nonce=iv, mac_len=TAG_LEN)
    return cipher.decrypt_and_verify(ct, tag)


def wrap_aes_key(public_key_spki_b64: str, raw_key: bytes) -> str:
    """RSA-OAEP(SHA-256) wrap. No label — the server's PKCS1_OAEP uses none."""
    key = RSA.import_key(b64d(public_key_spki_b64))
    return b64e(PKCS1_OAEP.new(key, hashAlgo=SHA256).encrypt(raw_key))


class ApiError(Exception):
    def __init__(self, status_code: int, code: str | None, message: str, payload: Any = None):
        super().__init__(f"{status_code} {code or ''}: {message}")
        self.status_code = status_code
        self.code = code
        self.message = message
        self.payload = payload


def extract_code(payload: Any) -> str | None:
    """Read the error code from both shapes the backend produces.

    Middleware errors are plaintext with ``code`` at the top level; handler
    errors are encrypted with ``code`` nested inside ``detail``. Reading only one
    of the two is the bug the web client has.
    """
    if not isinstance(payload, dict):
        return None
    if isinstance(payload.get("code"), str):
        return payload["code"]
    detail = payload.get("detail")
    if isinstance(detail, dict) and isinstance(detail.get("code"), str):
        return detail["code"]
    return None


def extract_message(payload: Any, fallback: str) -> str:
    if isinstance(payload, str):
        return payload
    if isinstance(payload, dict):
        detail = payload.get("detail")
        if isinstance(detail, str):
            return detail
        if isinstance(detail, dict):
            msg = detail.get("message")
            if isinstance(msg, str):
                return msg
        if isinstance(payload.get("message"), str):
            return payload["message"]
    return fallback


class CryptoClient:
    """Wraps a ``TestClient`` with the encrypted-transport envelope."""

    def __init__(self, client, signing_secret: str, prefix: str = "/api/v1", app_id: str = "test"):
        self._client = client
        self._secret = signing_secret
        self._prefix = prefix
        self._app_id = app_id
        self.session_id: str | None = None
        self.aes_key: bytes | None = None
        self.server_time: int | None = None
        self.clock_offset: int = 0
        # Simulates a wrong device clock, in seconds. Calibration against
        # serverTime should cancel it out.
        self.time_skew: int = 0
        self.handshake_count = 0
        self.access_token: str | None = None

    def _device_now(self) -> int:
        """The clock as this 'device' sees it, before calibration."""
        return int(time.time()) + self.time_skew

    # -- handshake ---------------------------------------------------------- #
    def handshake(self) -> None:
        res = self._client.get(f"{self._prefix}/crypto/public-key")
        res.raise_for_status()
        info = res.json()
        self.server_time = info.get("serverTime")
        raw_key = secrets.token_bytes(32)
        wrapped = wrap_aes_key(info["publicKey"], raw_key)
        res = self._client.post(f"{self._prefix}/crypto/handshake", json={"encryptedKey": wrapped})
        res.raise_for_status()
        body = res.json()
        self.session_id = body["sessionId"]
        self.aes_key = raw_key
        if body.get("serverTime"):
            # Sign with the server's clock, not the device's.
            self.clock_offset = int(body["serverTime"]) - self._device_now()
        self.handshake_count += 1

    def ensure_session(self) -> None:
        if self.session_id is None or self.aes_key is None:
            self.handshake()

    def reset_session(self) -> None:
        self.session_id = None
        self.aes_key = None

    # -- requests ----------------------------------------------------------- #
    def _sign(self, raw_body: bytes) -> dict[str, str]:
        assert self.session_id is not None
        timestamp = str(self._device_now() + self.clock_offset)
        nonce = secrets.token_bytes(16).hex()
        signature = hmac_sha256_hex(
            self._secret, canonical_string(self.session_id, timestamp, nonce, raw_body)
        )
        return {
            "X-Session-Id": self.session_id,
            "X-Timestamp": timestamp,
            "X-Nonce": nonce,
            "X-Signature": signature,
            "X-App-Id": self._app_id,
        }

    def request(
        self,
        method: str,
        path: str,
        body: Any = None,
        *,
        params: dict[str, Any] | None = None,
        auth: bool = True,
        _retry: bool = False,
    ) -> Any:
        self.ensure_session()
        assert self.aes_key is not None

        raw_body = b""
        headers: dict[str, str] = {}
        if body is not None:
            envelope = aes_encrypt(self.aes_key, json.dumps(body).encode("utf-8"))
            raw_body = json.dumps(envelope).encode("utf-8")
            headers["Content-Type"] = "application/json"
        headers.update(self._sign(raw_body))
        if auth and self.access_token:
            headers["Authorization"] = f"Bearer {self.access_token}"

        res = self._client.request(
            method,
            f"{self._prefix}{path}",
            content=raw_body if body is not None else None,
            headers=headers,
            params=params,
        )
        payload = self._decode(res)

        if res.status_code >= 400:
            code = extract_code(payload)
            # A backend restart drops the in-memory session store, so every
            # client sees no_session until it re-handshakes. Retry once.
            if res.status_code == 401 and code == "no_session" and not _retry:
                self.reset_session()
                return self.request(
                    method, path, body, params=params, auth=auth, _retry=True
                )
            raise ApiError(
                res.status_code, code, extract_message(payload, res.reason_phrase or ""), payload
            )
        return payload

    def _decode(self, res) -> Any:
        text = res.text
        if not text:
            return None
        if res.headers.get("x-encrypted") == "1" and self.aes_key is not None:
            envelope = json.loads(text)
            plain = aes_decrypt(self.aes_key, envelope["iv"], envelope["ciphertext"])
            text = plain.decode("utf-8")
        try:
            return json.loads(text)
        except json.JSONDecodeError:
            return text

    # -- convenience -------------------------------------------------------- #
    def get(self, path: str, **kw) -> Any:
        return self.request("GET", path, None, **kw)

    def post(self, path: str, body: Any = None, **kw) -> Any:
        return self.request("POST", path, body if body is not None else {}, **kw)

    def put(self, path: str, body: Any = None, **kw) -> Any:
        return self.request("PUT", path, body if body is not None else {}, **kw)

    def delete(self, path: str, **kw) -> Any:
        return self.request("DELETE", path, None, **kw)

    def login(self, identifier: str, password: str, device: dict | None = None) -> Any:
        payload: dict[str, Any] = {"identifier": identifier, "password": password}
        if device:
            payload["device"] = device
        result = self.request("POST", "/auth/login", payload, auth=False)
        self.access_token = result["access_token"]
        return result
