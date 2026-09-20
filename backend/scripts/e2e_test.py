"""End-to-end test of the encrypted API flow (no external deps).

Mirrors exactly what the web/native client does:
  handshake -> encrypted register -> encrypted authenticated GET /me
             -> refresh -> replay-attack rejection check
Run the server first:  uvicorn app.main:app --port 8000
Then:                  python scripts/e2e_test.py
"""
from __future__ import annotations

import base64
import hashlib
import hmac
import json
import secrets
import time
import urllib.error
import urllib.request

from Crypto.Cipher import AES, PKCS1_OAEP
from Crypto.Hash import SHA256
from Crypto.PublicKey import RSA

# Load the same signing secret the server uses.
import sys, os
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from app.core.config import settings  # noqa: E402

BASE = "http://127.0.0.1:8000/api/v1"
APP_SECRET = settings.APP_SIGNING_SECRET.encode()


def b64e(b: bytes) -> str:
    return base64.b64encode(b).decode()


def b64d(s: str) -> bytes:
    return base64.b64decode(s)


def http(method: str, url: str, body: bytes | None = None, headers: dict | None = None):
    req = urllib.request.Request(url, data=body, method=method, headers=headers or {})
    try:
        with urllib.request.urlopen(req) as r:
            return r.status, dict(r.headers), r.read()
    except urllib.error.HTTPError as e:
        return e.code, dict(e.headers), e.read()


class Client:
    def __init__(self):
        self.session_id = None
        self.aes_key = None

    def handshake(self):
        _, _, raw = http("GET", f"{BASE}/crypto/public-key")
        pub = json.loads(raw)
        rsa_key = RSA.import_key(b64d(pub["publicKey"]))
        self.aes_key = secrets.token_bytes(32)
        wrapped = PKCS1_OAEP.new(rsa_key, hashAlgo=SHA256).encrypt(self.aes_key)
        body = json.dumps({"encryptedKey": b64e(wrapped)}).encode()
        st, _, raw = http("POST", f"{BASE}/crypto/handshake", body,
                          {"Content-Type": "application/json"})
        assert st == 200, (st, raw)
        self.session_id = json.loads(raw)["sessionId"]
        print(f"  handshake OK  sessionId={self.session_id[:12]}...")

    def _enc(self, plaintext: bytes) -> bytes:
        iv = secrets.token_bytes(12)
        cipher = AES.new(self.aes_key, AES.MODE_GCM, nonce=iv, mac_len=16)
        ct, tag = cipher.encrypt_and_digest(plaintext)
        return json.dumps({"iv": b64e(iv), "ciphertext": b64e(ct + tag)}).encode()

    def _dec(self, raw: bytes) -> bytes:
        env = json.loads(raw)
        iv = b64d(env["iv"]); blob = b64d(env["ciphertext"])
        ct, tag = blob[:-16], blob[-16:]
        return AES.new(self.aes_key, AES.MODE_GCM, nonce=iv, mac_len=16).decrypt_and_verify(ct, tag)

    def _headers(self, raw_body: bytes, nonce: str | None = None) -> dict:
        ts = str(int(time.time()))
        nonce = nonce or secrets.token_hex(16)
        body_hash = hashlib.sha256(raw_body or b"").hexdigest()
        msg = "\n".join([self.session_id, ts, nonce, body_hash]).encode()
        sig = hmac.new(APP_SECRET, msg, hashlib.sha256).hexdigest()
        return {
            "Content-Type": "application/json",
            "X-Session-Id": self.session_id,
            "X-Timestamp": ts,
            "X-Nonce": nonce,
            "X-Signature": sig,
        }

    def call(self, method: str, path: str, payload=None, token: str | None = None,
             nonce: str | None = None):
        raw_body = self._enc(json.dumps(payload).encode()) if payload is not None else b""
        headers = self._headers(raw_body, nonce=nonce)
        if token:
            headers["Authorization"] = f"Bearer {token}"
        st, resp_headers, raw = http(method, f"{BASE}{path}", raw_body or None, headers)
        data = None
        if raw:
            data = self._dec(raw) if resp_headers.get("x-encrypted") == "1" else raw
            try:
                data = json.loads(data)
            except Exception:
                pass
        return st, data


def main():
    c = Client()
    print("1) crypto handshake")
    c.handshake()

    email = f"user_{secrets.token_hex(4)}@example.com"
    print("2) encrypted register")
    st, data = c.call("POST", "/auth/register",
                      {"email": email, "password": "hunter2abc", "display_name": "Test",
                       "device": {"platform": "web", "deviceName": "e2e"}})
    assert st == 201, (st, data)
    access, refresh = data["access_token"], data["refresh_token"]
    print(f"   registered {email}  user.id={data['user']['id'][:8]}...")

    print("3) encrypted GET /auth/me with bearer token")
    st, me = c.call("GET", "/auth/me", token=access)
    assert st == 200 and me["email"] == email, (st, me)
    print(f"   me OK -> {me['email']} status={me['status']}")

    print("4) unauthenticated protected call is rejected")
    st, _ = c.call("GET", "/users/me")
    assert st == 401, st
    print("   401 as expected")

    print("5) refresh access token")
    st, data = c.call("POST", "/auth/refresh", {"refresh_token": refresh})
    assert st == 200 and data.get("access_token"), (st, data)
    print("   new access token issued")

    print("6) replay protection (reuse a nonce)")
    fixed_nonce = secrets.token_hex(16)
    st1, _ = c.call("GET", "/auth/me", token=access, nonce=fixed_nonce)
    st2, body2 = c.call("GET", "/auth/me", token=access, nonce=fixed_nonce)
    assert st1 == 200 and st2 == 401, (st1, st2, body2)
    print("   first OK, replayed nonce rejected (401)")

    print("7) missing session id is rejected")
    st, _, _ = http("GET", f"{BASE}/auth/me", None, {"Authorization": f"Bearer {access}"})
    assert st == 401, st
    print("   401 as expected")

    print("\nALL CHECKS PASSED ✅")


if __name__ == "__main__":
    main()
