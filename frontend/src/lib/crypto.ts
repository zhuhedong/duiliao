/**
 * Browser-side crypto primitives (Web Crypto API) that mirror the backend.
 *
 * These are framework-agnostic and rely only on `crypto.subtle`, so the same
 * code runs unchanged inside a Capacitor / native WebView when the project
 * grows into an app.
 */

const enc = new TextEncoder();

/**
 * TS 5.7's DOM lib types `Uint8Array` as `Uint8Array<ArrayBufferLike>`, which
 * Web Crypto's `BufferSource` parameters (expecting `ArrayBuffer`-backed views)
 * reject. Our arrays are always real `ArrayBuffer`-backed at runtime, so this
 * narrows the type at the crypto.subtle boundary.
 */
function buf(u: Uint8Array): BufferSource {
  return u as unknown as BufferSource;
}

export function bytesToBase64(bytes: ArrayBuffer | Uint8Array): string {
  const arr = bytes instanceof Uint8Array ? bytes : new Uint8Array(bytes);
  let bin = "";
  for (let i = 0; i < arr.length; i++) bin += String.fromCharCode(arr[i]);
  return btoa(bin);
}

export function base64ToBytes(b64: string): Uint8Array {
  const bin = atob(b64);
  const out = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) out[i] = bin.charCodeAt(i);
  return out;
}

function toHex(buffer: ArrayBuffer): string {
  const arr = new Uint8Array(buffer);
  let hex = "";
  for (let i = 0; i < arr.length; i++) hex += arr[i].toString(16).padStart(2, "0");
  return hex;
}

/** Import the server's base64 SPKI RSA public key for OAEP-SHA256 wrapping. */
export async function importRsaPublicKey(spkiBase64: string): Promise<CryptoKey> {
  const der = base64ToBytes(spkiBase64);
  return crypto.subtle.importKey(
    "spki",
    buf(der),
    { name: "RSA-OAEP", hash: "SHA-256" },
    false,
    ["encrypt"],
  );
}

export interface AesSession {
  key: CryptoKey;
  rawKey: Uint8Array;
}

/** Generate a fresh AES-256-GCM session key and its raw bytes. */
export async function generateAesSession(): Promise<AesSession> {
  const key = await crypto.subtle.generateKey(
    { name: "AES-GCM", length: 256 },
    true,
    ["encrypt", "decrypt"],
  );
  const rawKey = new Uint8Array(await crypto.subtle.exportKey("raw", key));
  return { key, rawKey };
}

/** RSA-OAEP wrap the raw AES key -> base64, ready for the handshake. */
export async function wrapAesKey(rsaPublicKey: CryptoKey, rawKey: Uint8Array): Promise<string> {
  const wrapped = await crypto.subtle.encrypt({ name: "RSA-OAEP" }, rsaPublicKey, buf(rawKey));
  return bytesToBase64(wrapped);
}

export interface Envelope {
  iv: string;
  ciphertext: string;
}

/** AES-256-GCM encrypt -> {iv, ciphertext(=ct||tag)} (Web Crypto appends tag). */
export async function aesEncrypt(key: CryptoKey, plaintext: Uint8Array): Promise<Envelope> {
  const iv = crypto.getRandomValues(new Uint8Array(12));
  const ct = await crypto.subtle.encrypt({ name: "AES-GCM", iv: buf(iv) }, key, buf(plaintext));
  return { iv: bytesToBase64(iv), ciphertext: bytesToBase64(ct) };
}

export async function aesDecrypt(key: CryptoKey, env: Envelope): Promise<Uint8Array> {
  const iv = base64ToBytes(env.iv);
  const ct = base64ToBytes(env.ciphertext);
  const pt = await crypto.subtle.decrypt({ name: "AES-GCM", iv: buf(iv) }, key, buf(ct));
  return new Uint8Array(pt);
}

export async function sha256Hex(data: Uint8Array): Promise<string> {
  const digest = await crypto.subtle.digest("SHA-256", buf(data));
  return toHex(digest);
}

export async function hmacSha256Hex(secret: string, message: string): Promise<string> {
  const key = await crypto.subtle.importKey(
    "raw",
    buf(enc.encode(secret)),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const sig = await crypto.subtle.sign("HMAC", key, buf(enc.encode(message)));
  return toHex(sig);
}

export function randomNonceHex(bytes = 16): string {
  const arr = crypto.getRandomValues(new Uint8Array(bytes));
  let hex = "";
  for (let i = 0; i < arr.length; i++) hex += arr[i].toString(16).padStart(2, "0");
  return hex;
}
