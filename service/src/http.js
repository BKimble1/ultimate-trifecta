// HTTP helpers: JSON responses, typed errors, bounded body parsing.

export class ApiError extends Error {
  constructor(status, code, message, extra = {}) {
    super(message || code);
    this.status = status;
    this.code = code;
    this.extra = extra;
  }
}

export function json(data, status = 200, headers = {}) {
  return new Response(JSON.stringify(data), {
    status,
    headers: { 'content-type': 'application/json; charset=utf-8', 'cache-control': 'no-store', ...headers },
  });
}

export function errorResponse(e) {
  if (e instanceof ApiError) {
    return json({ ok: false, error: e.code, message: e.message, ...e.extra }, e.status);
  }
  return json({ ok: false, error: 'internal', message: 'Something went wrong. Please try again.' }, 500);
}

const MAX_BODY = 16 * 1024;

export async function readJson(req) {
  const len = Number(req.headers.get('content-length') || '0');
  if (len > MAX_BODY) throw new ApiError(413, 'too_large', 'Request too large.');
  const text = await req.text();
  if (text.length > MAX_BODY) throw new ApiError(413, 'too_large', 'Request too large.');
  if (!text) return {};
  try {
    const v = JSON.parse(text);
    if (v === null || typeof v !== 'object' || Array.isArray(v)) throw new Error('not an object');
    return v;
  } catch {
    throw new ApiError(400, 'bad_json', 'Request body must be a JSON object.');
  }
}

export function str(v, name, { min = 0, max = 256, optional = false } = {}) {
  if (v === undefined || v === null) {
    if (optional) return null;
    throw new ApiError(400, 'bad_request', `Missing ${name}.`);
  }
  if (typeof v !== 'string') throw new ApiError(400, 'bad_request', `${name} must be a string.`);
  if (v.length < min || v.length > max) throw new ApiError(400, 'bad_request', `${name} has the wrong length.`);
  return v;
}

export function int(v, name, { min = -(2 ** 53), max = 2 ** 53, optional = false } = {}) {
  if (v === undefined || v === null) {
    if (optional) return null;
    throw new ApiError(400, 'bad_request', `Missing ${name}.`);
  }
  if (typeof v !== 'number' || !Number.isFinite(v) || !Number.isInteger(v) || v < min || v > max) {
    throw new ApiError(400, 'bad_request', `${name} must be a whole number in range.`);
  }
  return v;
}
