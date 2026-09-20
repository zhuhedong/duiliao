// Verifies the browser Web Crypto path interoperates with the backend.
// Uses Node's global `crypto.subtle` (same API surface as the browser) and the
// same steps as src/lib/api.ts. Run backend first, then:
//   node scripts/webcrypto_e2e.mjs
import fs from "node:fs";

const BASE = "http://127.0.0.1:8000/api/v1";
const SECRET = (fs.readFileSync(new URL("../.env.local", import.meta.url), "utf8")
  .match(/^VITE_APP_SIGNING_SECRET=(.*)$/m) || [])[1].trim();

const enc = new TextEncoder();
const dec = new TextDecoder();
const b64e = (b) => Buffer.from(b).toString("base64");
const b64d = (s) => new Uint8Array(Buffer.from(s, "base64"));
const hex = (b) => Buffer.from(b).toString("hex");

async function sha256Hex(bytes) {
  return hex(await crypto.subtle.digest("SHA-256", bytes));
}
async function hmacHex(secret, msg) {
  const k = await crypto.subtle.importKey("raw", enc.encode(secret), { name: "HMAC", hash: "SHA-256" }, false, ["sign"]);
  return hex(await crypto.subtle.sign("HMAC", k, enc.encode(msg)));
}

let session = null;

async function handshake() {
  const pk = await (await fetch(`${BASE}/crypto/public-key`)).json();
  const rsa = await crypto.subtle.importKey("spki", b64d(pk.publicKey), { name: "RSA-OAEP", hash: "SHA-256" }, false, ["encrypt"]);
  const aes = await crypto.subtle.generateKey({ name: "AES-GCM", length: 256 }, true, ["encrypt", "decrypt"]);
  const raw = new Uint8Array(await crypto.subtle.exportKey("raw", aes));
  const wrapped = await crypto.subtle.encrypt({ name: "RSA-OAEP" }, rsa, raw);
  const res = await fetch(`${BASE}/crypto/handshake`, {
    method: "POST", headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ encryptedKey: b64e(wrapped) }),
  });
  const { sessionId } = await res.json();
  session = { id: sessionId, aes };
  console.log("  handshake OK", sessionId.slice(0, 12) + "...");
}

async function call(method, path, body, token) {
  let raw = new Uint8Array(0);
  const headers = {};
  if (body !== undefined) {
    const iv = crypto.getRandomValues(new Uint8Array(12));
    const ct = await crypto.subtle.encrypt({ name: "AES-GCM", iv }, session.aes, enc.encode(JSON.stringify(body)));
    raw = enc.encode(JSON.stringify({ iv: b64e(iv), ciphertext: b64e(new Uint8Array(ct)) }));
    headers["Content-Type"] = "application/json";
  }
  const ts = Math.floor(Date.now() / 1000).toString();
  const nonce = hex(crypto.getRandomValues(new Uint8Array(16)));
  const sig = await hmacHex(SECRET, [session.id, ts, nonce, await sha256Hex(raw)].join("\n"));
  Object.assign(headers, { "X-Session-Id": session.id, "X-Timestamp": ts, "X-Nonce": nonce, "X-Signature": sig });
  if (token) headers["Authorization"] = `Bearer ${token}`;
  const res = await fetch(`${BASE}${path}`, { method, headers, body: body !== undefined ? raw : undefined });
  const text = await res.text();
  let data = null;
  if (text) {
    if (res.headers.get("x-encrypted") === "1") {
      const env = JSON.parse(text);
      const pt = await crypto.subtle.decrypt({ name: "AES-GCM", iv: b64d(env.iv) }, session.aes, b64d(env.ciphertext));
      data = JSON.parse(dec.decode(pt));
    } else {
      try { data = JSON.parse(text); } catch { data = text; }
    }
  }
  return { status: res.status, data };
}

async function main() {
  if (!SECRET) throw new Error("could not read VITE_APP_SIGNING_SECRET from .env.local");
  console.log("1) handshake (WebCrypto RSA-OAEP + AES-GCM)");
  await handshake();

  const email = `web_${hex(crypto.getRandomValues(new Uint8Array(4)))}@example.com`;
  console.log("2) encrypted register");
  const reg = await call("POST", "/auth/register", { email, password: "hunter2abc", display_name: "WebCrypto", source: "web" });
  if (reg.status !== 201) throw new Error("register failed: " + JSON.stringify(reg));
  console.log("   registered", email);

  console.log("3) encrypted GET /auth/me");
  const me = await call("GET", "/auth/me", undefined, reg.data.access_token);
  if (me.status !== 200 || me.data.email !== email) throw new Error("me failed: " + JSON.stringify(me));
  console.log("   me OK ->", me.data.email);

  console.log("\nWEBCRYPTO <-> BACKEND INTEROP OK ✅");
}

main().catch((e) => { console.error("FAILED:", e); process.exit(1); });
