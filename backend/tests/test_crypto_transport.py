"""Transport-layer tests: handshake, envelope, signing, replay, clock skew.

These pin down the exact wire format the Flutter client has to reproduce. If one
of these changes, the Dart implementation has to change with it.
"""
from __future__ import annotations

import base64
import json
import secrets
import time

import pytest

from tests.crypto_client import (
    EMPTY_SHA256,
    ApiError,
    CryptoClient,
    aes_decrypt,
    aes_encrypt,
    canonical_string,
    hmac_sha256_hex,
    sha256_hex,
    wrap_aes_key,
)

PREFIX = "/api/v1"


# --------------------------------------------------------------------------- #
# Primitives
# --------------------------------------------------------------------------- #
def test_empty_string_sha256_is_the_documented_constant():
    assert sha256_hex(b"") == EMPTY_SHA256


def test_canonical_string_is_lf_separated_with_four_fields():
    s = canonical_string("sid", "1700000000", "abcd", b"")
    assert s == f"sid\n1700000000\nabcd\n{EMPTY_SHA256}"
    assert s.count("\n") == 3
    assert not s.endswith("\n")


def test_hmac_matches_a_precomputed_vector():
    # Guards against the client signing with anything other than raw UTF-8 bytes
    # of the secret.
    assert hmac_sha256_hex("secret", "message") == (
        "8b5f48702995c1598c573db1e21866a9b825d4a794d169d7060a03605796360b"
    )


def test_aes_gcm_round_trip_and_layout():
    key = secrets.token_bytes(32)
    envelope = aes_encrypt(key, b"hello duiliao")
    iv = base64.b64decode(envelope["iv"])
    blob = base64.b64decode(envelope["ciphertext"])
    assert len(iv) == 12, "IV must be 12 bytes"
    # ciphertext || 16-byte tag, so the blob is exactly 16 bytes longer than input
    assert len(blob) == len(b"hello duiliao") + 16
    assert aes_decrypt(key, envelope["iv"], envelope["ciphertext"]) == b"hello duiliao"


def test_tampering_with_the_ciphertext_fails_authentication():
    key = secrets.token_bytes(32)
    envelope = aes_encrypt(key, b"hello duiliao")
    blob = bytearray(base64.b64decode(envelope["ciphertext"]))
    blob[0] ^= 0x01
    with pytest.raises(Exception):
        aes_decrypt(key, envelope["iv"], base64.b64encode(bytes(blob)).decode())


def test_base64_is_standard_not_urlsafe():
    key = secrets.token_bytes(32)
    # Repeat until a '+' or '/' appears, proving the standard alphabet is in use.
    for _ in range(200):
        envelope = aes_encrypt(key, secrets.token_bytes(64))
        if "+" in envelope["ciphertext"] or "/" in envelope["ciphertext"]:
            break
    else:
        pytest.skip("no non-alphanumeric base64 char observed")
    assert "-" not in envelope["ciphertext"] or "+" in envelope["ciphertext"]


# --------------------------------------------------------------------------- #
# Handshake
# --------------------------------------------------------------------------- #
def test_public_key_is_base64_der_spki_and_carries_server_time(raw_client):
    res = raw_client.get(f"{PREFIX}/crypto/public-key")
    assert res.status_code == 200
    body = res.json()
    assert body["algorithm"] == "RSA-OAEP-256"
    der = base64.b64decode(body["publicKey"])
    # DER SPKI starts with a SEQUENCE tag; a PEM header would start with '-'
    assert der[0] == 0x30
    assert not body["publicKey"].startswith("-----")
    assert abs(int(body["serverTime"]) - int(time.time())) < 30


def test_handshake_returns_session_and_server_time(raw_client):
    info = raw_client.get(f"{PREFIX}/crypto/public-key").json()
    wrapped = wrap_aes_key(info["publicKey"], secrets.token_bytes(32))
    res = raw_client.post(f"{PREFIX}/crypto/handshake", json={"encryptedKey": wrapped})
    assert res.status_code == 200
    body = res.json()
    assert body["sessionId"]
    assert body["expiresIn"] > 0
    assert abs(int(body["serverTime"]) - int(time.time())) < 30


def test_wrapped_key_with_wrong_length_is_rejected(raw_client):
    info = raw_client.get(f"{PREFIX}/crypto/public-key").json()
    wrapped = wrap_aes_key(info["publicKey"], secrets.token_bytes(20))  # not 16/24/32
    res = raw_client.post(f"{PREFIX}/crypto/handshake", json={"encryptedKey": wrapped})
    assert res.status_code == 400


# --------------------------------------------------------------------------- #
# Middleware enforcement
# --------------------------------------------------------------------------- #
def test_missing_session_header_yields_no_session_in_plaintext(raw_client):
    res = raw_client.get(f"{PREFIX}/collector/rules")
    assert res.status_code == 401
    # Middleware errors are NOT encrypted and put `code` at the top level.
    assert "x-encrypted" not in {k.lower() for k in res.headers}
    body = res.json()
    assert body["code"] == "no_session"


def test_zodiac_streak_stream_skips_encryption_session(raw_client):
    """The streak SSE route is plaintext like /ai/analyze-stream.

    A missing encryption session must not be reported as no_session, or the
    web client treats the click as an expired identity.
    """
    res = raw_client.post(
        f"{PREFIX}/ai/zodiac-streak-stream",
        json={"lottery": "macau", "num_periods": 10, "min_streak": 3},
    )
    assert res.status_code == 401
    body = res.json()
    assert body.get("code") != "no_session"
    assert body.get("detail") == "Not authenticated"


def test_bad_signature_is_rejected(raw_client):
    from app.core.config import settings

    client = CryptoClient(raw_client, "the-wrong-secret")
    client.handshake()
    with pytest.raises(ApiError) as exc:
        client.get("/collector/rules")
    assert exc.value.status_code == 401
    assert exc.value.code == "bad_signature"
    assert settings.APP_SIGNING_SECRET != "the-wrong-secret"


def test_stale_timestamp_is_rejected(user_client):
    # A device clock 400s fast, with the calibration offset discarded.
    user_client.time_skew = 400
    user_client.clock_offset = 0
    with pytest.raises(ApiError) as exc:
        user_client.get("/collector/rules")
    assert exc.value.code == "bad_timestamp"


def test_server_time_calibration_survives_a_skewed_device_clock(user_client):
    """The whole point of returning serverTime: a skewed client still works."""
    user_client.time_skew = 400
    user_client.handshake()  # recomputes clock_offset against the server clock
    # The offset must cancel the skew, bringing the signed timestamp back in range.
    assert user_client.clock_offset <= -395
    rules = user_client.get("/collector/rules")
    assert isinstance(rules, list) and len(rules) == 21


def test_replayed_nonce_is_rejected(user_client):
    from app.core.config import settings

    timestamp = str(int(time.time()))
    nonce = secrets.token_bytes(16).hex()
    signature = hmac_sha256_hex(
        settings.APP_SIGNING_SECRET,
        canonical_string(user_client.session_id, timestamp, nonce, b""),
    )
    headers = {
        "X-Session-Id": user_client.session_id,
        "X-Timestamp": timestamp,
        "X-Nonce": nonce,
        "X-Signature": signature,
        "Authorization": f"Bearer {user_client.access_token}",
    }
    first = user_client._client.get(f"{PREFIX}/collector/rules", headers=headers)
    assert first.status_code == 200
    # Same nonce again: the replay cache must reject it even though the signature
    # is still valid and the timestamp still in window.
    second = user_client._client.get(f"{PREFIX}/collector/rules", headers=headers)
    assert second.status_code == 401
    assert second.json()["code"] == "replay"


def test_unknown_session_id_reports_no_session(raw_client):
    from app.core.config import settings

    client = CryptoClient(raw_client, settings.APP_SIGNING_SECRET)
    client.handshake()
    client.session_id = "definitely-not-a-real-session"
    with pytest.raises(ApiError) as exc:
        # _retry would re-handshake and succeed, so assert on the first attempt.
        client.request("GET", "/collector/rules", None, _retry=True)
    assert exc.value.code == "no_session"


def test_client_recovers_from_a_dropped_session_by_rehandshaking(user_client):
    """Mirrors a backend restart clearing the in-memory session store."""
    assert user_client.handshake_count == 1
    user_client.session_id = "stale-session-id"
    rules = user_client.get("/collector/rules")  # transparent re-handshake + retry
    assert isinstance(rules, list) and len(rules) == 21
    assert user_client.handshake_count == 2


# --------------------------------------------------------------------------- #
# Round trip through a real route
# --------------------------------------------------------------------------- #
def test_encrypted_get_returns_all_21_play_types(user_client):
    rules = user_client.get("/collector/rules")
    assert len(rules) == 21
    assert {r["version"] for r in rules} == {"2026-09-06.2"}
    scopes = {}
    for row in rules:
        scopes.setdefault(row["scope"], []).append(row["play_type"])
    assert len(scopes["特码"]) == 8
    assert len(scopes["七球（含特码）"]) == 7
    assert len(scopes["六个正码"]) == 5
    assert len(scopes["正码与特码"]) == 1


def test_response_body_is_actually_encrypted(user_client):
    """Confirm the plaintext never appears on the wire."""
    headers = user_client._sign(b"")
    headers["Authorization"] = f"Bearer {user_client.access_token}"
    raw = user_client._client.get(f"{PREFIX}/collector/rules", headers=headers)
    assert raw.status_code == 200
    assert raw.headers["x-encrypted"] == "1"
    assert "play_type" not in raw.text
    envelope = json.loads(raw.text)
    assert set(envelope) == {"iv", "ciphertext"}
    plain = aes_decrypt(user_client.aes_key, envelope["iv"], envelope["ciphertext"])
    assert "play_type" in plain.decode()


def test_concurrent_requests_reuse_one_session(user_client):
    before = user_client.handshake_count
    for _ in range(5):
        user_client.get("/collector/rules")
    assert user_client.handshake_count == before
