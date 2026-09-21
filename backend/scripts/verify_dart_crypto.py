#!/usr/bin/env python3
"""Verify Dart-produced crypto output with the server's own primitives.

The Dart unit tests decrypt Python's output. This script checks the other
direction — that the backend can unwrap and decrypt what the Flutter client
produces — which is the direction every outbound request depends on.

Usage:
    cd duiliao_app && dart run tool/emit_crypto_output.dart > /tmp/dart_out.json
    cd backend && .venv/bin/python scripts/verify_dart_crypto.py \
        ../duiliao_app/assets/fixtures/crypto_vectors.json /tmp/dart_out.json

Exits non-zero on the first mismatch.
"""
from __future__ import annotations

import base64
import hashlib
import hmac
import json
import sys
from pathlib import Path

from Crypto.Cipher import AES, PKCS1_OAEP
from Crypto.Hash import SHA256
from Crypto.PublicKey import RSA

TAG_LEN = 16


def b64d(value: str) -> bytes:
    return base64.b64decode(value)


def aes_decrypt(key: bytes, iv_b64: str, ciphertext_b64: str) -> bytes:
    """Byte-for-byte the server's app/core/crypto.py:aes_decrypt."""
    iv = b64d(iv_b64)
    blob = b64d(ciphertext_b64)
    if len(blob) < TAG_LEN:
        raise ValueError("ciphertext too short")
    ct, tag = blob[:-TAG_LEN], blob[-TAG_LEN:]
    cipher = AES.new(key, AES.MODE_GCM, nonce=iv, mac_len=TAG_LEN)
    return cipher.decrypt_and_verify(ct, tag)


def main() -> int:
    if len(sys.argv) < 3:
        print(__doc__)
        return 2
    fixtures = json.loads(Path(sys.argv[1]).read_text("utf-8"))
    dart = json.loads(Path(sys.argv[2]).read_text("utf-8"))

    checks = 0
    print(f"Dart crypto library: {dart['library']}")

    # 1. Unwrap the AES key Dart wrapped with our public key. This is the check
    #    that RSA-OAEP params line up (SHA-256 digest, MGF1-SHA-256, no label).
    private_key = RSA.import_key(fixtures["rsa"]["private_key_pem"])
    unwrapped = PKCS1_OAEP.new(private_key, hashAlgo=SHA256).decrypt(
        b64d(dart["wrapped_aes_key_b64"])
    )
    expected_key = b64d(dart["expected_aes_key_b64"])
    assert unwrapped == expected_key, "unwrapped AES key does not match"
    assert len(unwrapped) == 32, f"expected a 32-byte key, got {len(unwrapped)}"
    print("  [ok] RSA-OAEP unwrap recovered the exact 32-byte AES key")
    checks += 1

    # 2. Decrypt every payload Dart encrypted under that key.
    for case in dart["encrypted"]:
        plain = aes_decrypt(unwrapped, case["iv"], case["ciphertext"])
        expected = case["expected_plaintext"]
        assert plain.decode("utf-8") == expected, (
            f"decrypted text differs: {plain[:60]!r} != {expected[:60]!r}"
        )
        assert len(b64d(case["iv"])) == 12, "iv must be 12 bytes"
        checks += 1
    print(f"  [ok] AES-GCM decrypted {len(dart['encrypted'])} Dart payloads "
          "(incl. empty, non-ASCII and 5000 bytes)")

    # 3. Recompute Dart's signatures with the server's HMAC.
    secret = fixtures["signing_secret"]
    for case in dart["signatures"]:
        body = b64d(case["body_b64"])
        canonical = "\n".join(
            [
                case["session_id"],
                case["timestamp"],
                case["nonce"],
                hashlib.sha256(body or b"").hexdigest(),
            ]
        )
        expected = hmac.new(
            secret.encode("utf-8"), canonical.encode("utf-8"), hashlib.sha256
        ).hexdigest()
        assert hmac.compare_digest(expected, case["signature"]), (
            f"signature mismatch for body of {len(body)} bytes"
        )
        checks += 1
    print(f"  [ok] {len(dart['signatures'])} request signatures verified "
          "(empty body and encrypted body)")

    assert dart["sha256_empty"] == hashlib.sha256(b"").hexdigest()
    checks += 1
    print("  [ok] empty-body SHA-256 matches")

    print(f"\nAll {checks} cross-language checks passed.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
