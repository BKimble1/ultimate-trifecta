// Random identifiers and party room codes.

const B32 = 'abcdefghijkmnpqrstuvwxyz23456789';

export function randomId(prefix, n = 20) {
  const bytes = new Uint8Array(n);
  crypto.getRandomValues(bytes);
  let s = '';
  for (const b of bytes) s += B32[b % B32.length];
  return `${prefix}_${s}`;
}

// Room codes: 6 characters from an alphabet with no look-alikes
// (no 0/O, 1/I/L, 5/S, 8/B, 2/Z, U/V): easy to read aloud and type.
export const CODE_ALPHABET = 'ACDEFGHJKMNPQRTWXY34679';
export const CODE_LEN = 6;

export function newRoomCode() {
  const bytes = new Uint8Array(CODE_LEN);
  crypto.getRandomValues(bytes);
  let s = '';
  for (const b of bytes) s += CODE_ALPHABET[b % CODE_ALPHABET.length];
  return s;
}

// Normalise what a player typed into a room code.  Only case, spaces and
// dashes are forgiven; anything else is an explicit error (never silently
// stripped or truncated).  Returns {ok, code} or {ok:false, error, message}.
export function normalizeCode(input) {
  if (typeof input !== 'string') return { ok: false, error: 'code_format', message: 'Enter the 6-character party code.' };
  const s = input.toUpperCase().replace(/[\s-]/g, '');
  if (s.length === 0) return { ok: false, error: 'code_format', message: 'Enter the 6-character party code.' };
  if (s.length !== CODE_LEN) {
    return { ok: false, error: 'code_format', message: `Party codes have ${CODE_LEN} characters (that one has ${s.length}).` };
  }
  for (const ch of s) {
    if (!CODE_ALPHABET.includes(ch)) {
      return { ok: false, error: 'code_format', message: `"${ch}" isn't used in party codes. Check the code and try again.` };
    }
  }
  return { ok: true, code: s };
}
