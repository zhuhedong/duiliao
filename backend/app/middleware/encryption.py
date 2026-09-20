"""Transparent end-to-end payload encryption (pure ASGI middleware).

For every request under the API prefix (except the handshake/health/docs
endpoints) this middleware:

  1. Requires an `X-Session-Id` header that maps to a live AES session key.
  2. Verifies anti-replay metadata: `X-Timestamp` (fresh), `X-Nonce` (unused),
     and `X-Signature` (HMAC over the raw encrypted body).
  3. Decrypts the request body ({iv, ciphertext}) and hands plaintext JSON to
     the route handler.
  4. Encrypts the handler's JSON response with the same session key and returns
     an {iv, ciphertext} envelope, tagged with `X-Encrypted: 1`.

Handlers therefore deal only with plaintext and never know encryption happened.
Endpoints that must stay in the clear (so a client can bootstrap) are exempt.
"""
from __future__ import annotations

import json

from starlette.types import ASGIApp, Message, Receive, Scope, Send

from app.core.config import settings
from app.core.crypto import aes_decrypt, aes_encrypt, session_store
from app.core.security import (
    nonce_cache,
    timestamp_within_window,
    verify_signature,
)

_PREFIX = settings.API_V1_PREFIX


def _exempt(path: str) -> bool:
    exact = {
        f"{_PREFIX}/crypto/public-key",
        f"{_PREFIX}/crypto/handshake",
        f"{_PREFIX}/health",
        "/health",
        "/",
        "/openapi.json",
        "/docs",
        "/redoc",
        "/docs/oauth2-redirect",
        "/favicon.ico",
        f"{_PREFIX}/ai/analyze-stream",
    }
    if path in exact:
        return True
    # Only guard the versioned API surface; everything else passes through.
    if not path.startswith(_PREFIX):
        return True
    return False


async def _send_json(send: Send, status: int, payload: dict) -> None:
    body = json.dumps(payload).encode("utf-8")
    await send(
        {
            "type": "http.response.start",
            "status": status,
            "headers": [
                (b"content-type", b"application/json"),
                (b"content-length", str(len(body)).encode()),
            ],
        }
    )
    await send({"type": "http.response.body", "body": body, "more_body": False})


class EncryptionMiddleware:
    def __init__(self, app: ASGIApp) -> None:
        self.app = app

    async def __call__(self, scope: Scope, receive: Receive, send: Send) -> None:
        if scope["type"] != "http":
            await self.app(scope, receive, send)
            return

        method = scope.get("method", "GET")
        path = scope.get("path", "")

        if method == "OPTIONS" or _exempt(path):
            await self.app(scope, receive, send)
            return

        headers = {k.decode().lower(): v.decode() for k, v in scope.get("headers", [])}
        session_id = headers.get("x-session-id", "")
        aes_key = session_store.get(session_id) if session_id else None
        if aes_key is None:
            await _send_json(
                send, 401, {"detail": "Missing or expired encryption session", "code": "no_session"}
            )
            return

        # --- Buffer the raw (encrypted) request body ---
        raw = b""
        more = True
        MAX_BODY_SIZE = getattr(settings, "MAX_UPLOAD_SIZE_MB", 100) * 1024 * 1024
        while more:
            message = await receive()
            raw += message.get("body", b"")
            if len(raw) > MAX_BODY_SIZE:
                await _send_json(send, 413, {"detail": "Payload Too Large", "code": "payload_too_large"})
                return
            more = message.get("more_body", False)

        # --- Anti-replay / integrity checks ---
        if settings.ENFORCE_REQUEST_SIGNATURE:
            ts = headers.get("x-timestamp", "")
            nonce = headers.get("x-nonce", "")
            signature = headers.get("x-signature", "")
            if not timestamp_within_window(ts):
                await _send_json(send, 401, {"detail": "Stale or invalid timestamp", "code": "bad_timestamp"})
                return
            if not verify_signature(signature, session_id, ts, nonce, raw):
                await _send_json(send, 401, {"detail": "Invalid request signature", "code": "bad_signature"})
                return
            if not nonce_cache.check_and_store(nonce):
                await _send_json(send, 401, {"detail": "Replay detected", "code": "replay"})
                return

        # --- Decrypt request body (if any) ---
        plaintext = b""
        if raw:
            try:
                envelope = json.loads(raw)
                plaintext = aes_decrypt(aes_key, envelope["iv"], envelope["ciphertext"])
            except Exception:
                await _send_json(send, 400, {"detail": "Malformed encrypted payload", "code": "bad_payload"})
                return

        async def receive_plaintext() -> Message:
            return {"type": "http.request", "body": plaintext, "more_body": False}

        # --- Capture + encrypt the response ---
        state: dict = {"status": 200, "headers": [], "chunks": [], "is_stream": False}

        async def send_encrypting(message: Message) -> None:
            if message["type"] == "http.response.start":
                for k, v in message.get("headers", []):
                    if k.lower() == b"content-type" and b"text/event-stream" in v.lower():
                        state["is_stream"] = True
                        break
                if state["is_stream"]:
                    await send(message)
                    return
                state["status"] = message["status"]
                state["headers"] = message.get("headers", [])
                return  # defer until body is fully collected
            if message["type"] == "http.response.body":
                if state["is_stream"]:
                    await send(message)
                    return
                state["chunks"].append(message.get("body", b""))
                if message.get("more_body", False):
                    return
                full = b"".join(state["chunks"])
                envelope = aes_encrypt(aes_key, full)
                out = json.dumps(envelope).encode("utf-8")

                # Rebuild headers: force JSON, fix length, mark as encrypted.
                new_headers = [
                    (k, v)
                    for (k, v) in state["headers"]
                    if k.lower() not in (b"content-length", b"content-type", b"content-encoding")
                ]
                new_headers.append((b"content-type", b"application/json"))
                new_headers.append((b"content-length", str(len(out)).encode()))
                new_headers.append((b"x-encrypted", b"1"))

                await send({"type": "http.response.start", "status": state["status"], "headers": new_headers})
                await send({"type": "http.response.body", "body": out, "more_body": False})

        await self.app(scope, receive_plaintext, send_encrypting)
