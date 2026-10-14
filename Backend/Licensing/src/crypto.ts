const encoder = new TextEncoder();

export async function signEntitlement(payload: Record<string, unknown>, privateJWK: string): Promise<string> {
  const header = base64URL(encoder.encode(JSON.stringify({ alg: "ES256", typ: "JWT" })));
  const claims = base64URL(encoder.encode(JSON.stringify(payload)));
  const key = await crypto.subtle.importKey("jwk", JSON.parse(privateJWK), { name: "ECDSA", namedCurve: "P-256" }, false, ["sign"]);
  const signature = await crypto.subtle.sign({ name: "ECDSA", hash: "SHA-256" }, key, encoder.encode(`${header}.${claims}`));
  return `${header}.${claims}.${base64URL(new Uint8Array(signature))}`;
}

export async function sha256(value: string): Promise<string> {
  return hex(await crypto.subtle.digest("SHA-256", encoder.encode(value)));
}

export async function hmac(value: string, secret: string): Promise<string> {
  const key = await crypto.subtle.importKey("raw", encoder.encode(secret), { name: "HMAC", hash: "SHA-256" }, false, ["sign"]);
  return hex(await crypto.subtle.sign("HMAC", key, encoder.encode(value)));
}

export async function encrypt(value: string, keyMaterial: string): Promise<string> {
  const keyBytes = await crypto.subtle.digest("SHA-256", encoder.encode(keyMaterial));
  const key = await crypto.subtle.importKey("raw", keyBytes, "AES-GCM", false, ["encrypt"]);
  const nonce = crypto.getRandomValues(new Uint8Array(12));
  const ciphertext = await crypto.subtle.encrypt({ name: "AES-GCM", iv: nonce }, key, encoder.encode(value));
  return `${base64URL(nonce)}.${base64URL(new Uint8Array(ciphertext))}`;
}

export async function decrypt(value: string, keyMaterial: string): Promise<string> {
  const [nonceText, ciphertextText] = value.split(".");
  if (!nonceText || !ciphertextText) throw new Error("invalid_ciphertext");
  const keyBytes = await crypto.subtle.digest("SHA-256", encoder.encode(keyMaterial));
  const key = await crypto.subtle.importKey("raw", keyBytes, "AES-GCM", false, ["decrypt"]);
  const plaintext = await crypto.subtle.decrypt({ name: "AES-GCM", iv: fromBase64URL(nonceText) }, key, fromBase64URL(ciphertextText));
  return new TextDecoder().decode(plaintext);
}

export function makeLicenseKey(): string {
  const alphabet = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";
  const bytes = crypto.getRandomValues(new Uint8Array(20));
  const chars = Array.from(bytes, byte => alphabet[byte % alphabet.length]);
  return `PP-${chars.slice(0, 5).join("")}-${chars.slice(5, 10).join("")}-${chars.slice(10, 15).join("")}-${chars.slice(15).join("")}`;
}

export function randomToken(): string {
  return base64URL(crypto.getRandomValues(new Uint8Array(32)));
}

export function randomLetters(count: number): string {
  const alphabet = "abcdefghijklmnopqrstuvwxyz";
  return Array.from(crypto.getRandomValues(new Uint8Array(count)), byte => alphabet[byte % alphabet.length]).join("");
}

function base64URL(bytes: Uint8Array): string {
  let binary = "";
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary).replaceAll("+", "-").replaceAll("/", "_").replaceAll("=", "");
}

function fromBase64URL(value: string): Uint8Array {
  const base64 = value.replaceAll("-", "+").replaceAll("_", "/") + "=".repeat((4 - value.length % 4) % 4);
  return Uint8Array.from(atob(base64), character => character.charCodeAt(0));
}

function hex(value: ArrayBuffer): string {
  return Array.from(new Uint8Array(value), byte => byte.toString(16).padStart(2, "0")).join("");
}

export function unixNow(): number {
  return Math.floor(Date.now() / 1000);
}
