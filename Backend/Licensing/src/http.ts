type Json = Record<string, unknown>;

export class RequestError extends Error {
  readonly code: string;
  readonly status: number;

  constructor(code: string, status: number) {
    super(code);
    this.name = "RequestError";
    this.code = code;
    this.status = status;
  }
}

export async function readText(request: Request, maxBytes: number): Promise<string> {
  const declaredLength = Number(request.headers.get("content-length"));
  if (declaredLength > maxBytes) throw new RequestError("body_too_large", 413);
  if (!request.body) throw new RequestError("invalid_body", 400);
  const reader = request.body.getReader();
  const chunks: Uint8Array[] = [];
  let length = 0;
  try {
    while (true) {
      const { value, done } = await reader.read();
      if (done) break;
      length += value.byteLength;
      if (length > maxBytes) {
        await reader.cancel();
        throw new RequestError("body_too_large", 413);
      }
      chunks.push(value);
    }
  } finally { reader.releaseLock(); }
  const bytes = new Uint8Array(length);
  let offset = 0;
  for (const chunk of chunks) { bytes.set(chunk, offset); offset += chunk.byteLength; }
  return new TextDecoder().decode(bytes);
}

export async function readBody(request: Request): Promise<Json> {
  if (request.headers.get("content-type")?.split(";")[0].trim().toLowerCase() !== "application/json") {
    throw new RequestError("json_required", 415);
  }
  let body: unknown;
  try { body = JSON.parse(await readText(request, 16_384)); }
  catch (error) {
    if (error instanceof RequestError) throw error;
    throw new RequestError("invalid_body", 400);
  }
  if (!body || typeof body !== "object" || Array.isArray(body)) throw new RequestError("invalid_body", 400);
  return body as Json;
}

export function requiredString(body: Json, key: string, maxLength: number): string {
  const value = body[key];
  if (typeof value !== "string" || !value.trim() || value.length > maxLength) throw new RequestError(`invalid_${key}`, 400);
  return value.trim();
}

export function checkoutReturnPage(sessionID: string | null): Response {
  if (!sessionID || !/^cs_[A-Za-z0-9_]{1,125}$/.test(sessionID)) return json({ error: "invalid_session_id" }, 400);
  const deepLink = `primarypaste://license/claim?session_id=${encodeURIComponent(sessionID)}`;
  const html = `<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Primary Paste purchase</title></head>
    <body><main><h1>Return to Primary Paste</h1><p>Open the app to confirm your payment and activate your license.</p>
    <p><a href="${deepLink}">Open Primary Paste</a></p><p>If the app does not open, install Primary Paste and open this link again.</p></main></body></html>`;
  return new Response(html, { headers: {
    "content-type": "text/html; charset=utf-8", "cache-control": "no-store", "referrer-policy": "no-referrer",
    "x-content-type-options": "nosniff", "content-security-policy": "default-src 'none'; frame-ancestors 'none'; base-uri 'none'"
  } });
}

export function json(value: Json, status = 200): Response {
  return Response.json(value, { status, headers: { "cache-control": "no-store", "x-content-type-options": "nosniff" } });
}
