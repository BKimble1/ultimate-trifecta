// Display-name rules and moderation.  The service is the only authority that
// approves a name; the game runs the same character rules locally just to
// give instant feedback while typing.
//
// Pipeline: NFKC + whitespace normalise -> character rules (3-16 of letters,
// digits, single internal spaces, underscores; at least two letters) ->
// skeleton (lowercase, look-alike digits mapped, separators removed, repeats
// collapsed) -> blocklists (slurs, sexual content, profanity, threats, staff
// or bot impersonation, URLs/contact handles) with an allowlist of harmless
// words that contain blocked strings -> reserved names -> a free
// discriminator (#0001-#9999) for duplicates.
import * as T from './terms.js';

export const MIN_LEN = 3;
export const MAX_LEN = 16;

const dec = (arr) => arr.map((s) => atob(s));

// look-alike characters (digits read as letters); '1' and '0' each try two readings
const LEET = { '0': 'o', '1': 'i', '3': 'e', '4': 'a', '5': 's', '6': 'g', '7': 't', '8': 'b', '9': 'g', '2': 'z' };
const LEET_ALT = { '1': 'l', '0': 'o', '6': 'b' };

function collapse(s) {
  return s.replace(/(.)\1+/g, '$1');
}

// Spelling variants of a name for substring matching: leet digits read as
// letters (two readings for 1/0/6), separators removed; each as raw and with
// repeated letters collapsed ("fuuuck" -> "fuck").
export function variants(name) {
  const base = name.toLowerCase().replace(/[\s_]/g, '');
  const maps = [
    (c) => LEET[c] ?? c,
    (c) => LEET_ALT[c] ?? LEET[c] ?? c,
  ];
  const out = [];
  for (const f of maps) {
    const raw = [...base].map(f).join('');
    for (const r of [raw, raw.replace(/rn/g, 'm').replace(/vv/g, 'w')]) out.push({ raw: r, col: collapse(r) });
  }
  const seen = new Set();
  return out.filter((v) => (seen.has(v.raw) ? false : seen.add(v.raw)));
}

export function skeletons(name) {
  return [...new Set(variants(name).map((v) => v.col))];
}

// Whole words, two ways: split on spaces/underscores, digit runs and
// lower->Upper changes ("Player42", "BigBoss"), and split only on
// spaces/underscores with digits read as letters ("m0d", "B0t").
export function tokens(name) {
  const camel = name
    .replace(/([a-z])([A-Z])/g, '$1 $2')
    .replace(/([A-Za-z])([0-9])/g, '$1 $2')
    .replace(/([0-9])([A-Za-z])/g, '$1 $2')
    .split(/[\s_]+/)
    .map((t) => t.toLowerCase())
    .filter((t) => /[a-z]/.test(t));
  const leet = name.replace(/([a-z])([A-Z])/g, '$1 $2').split(/[\s_]+/)
    .flatMap((t) => [[...t.toLowerCase()].map((ch) => LEET[ch] ?? ch).join(''), [...t.toLowerCase()].map((ch) => LEET_ALT[ch] ?? LEET[ch] ?? ch).join('')])
    .filter(Boolean);
  return [...new Set([...camel, ...leet])];
}

function list(words, tok) {
  return { sub: words.map(collapse), raw: words, tok };
}
const LISTS = {
  slur: list(dec(T.SLURS), dec(T.SLUR_TOKENS)),
  sexual: list(dec(T.SEXUAL), dec(T.SEXUAL_TOKENS)),
  profanity: list(dec(T.PROFANITY), []),
  threat: list(T.THREATS, T.THREAT_TOKENS),
  impersonation: list(T.STAFF, T.STAFF_TOKENS),
  contact: list(T.CONTACT, T.CONTACT_TOKENS),
};
const ALLOW_PAIRS = [...T.ALLOW].sort((x, y) => y.length - x.length).map((w) => ({ raw: w, col: collapse(w) }));

export const BUILTIN_RESERVED = ['player', 'runner', 'night watch', 'nightwatch', 'anonymous', 'unknown', 'guest', 'host',
  'you', 'me', 'everyone', 'nobody', 'null', 'undefined', 'test', 'claude'];

const MESSAGES = {
  length: `Names are ${MIN_LEN}-${MAX_LEN} characters.`,
  characters: 'Use letters, numbers, spaces and underscores.',
  spacing: 'Use single spaces between words (no spaces at the start or end).',
  letters: 'Include at least two letters.',
  slur: "That name isn't allowed. Please pick something kind.",
  sexual: "That name isn't allowed. Please keep it friendly for everyone.",
  profanity: "That name isn't allowed. Please keep it friendly for everyone.",
  threat: "That name isn't allowed. Please keep it friendly for everyone.",
  impersonation: "Names can't look like staff, the game or a bot.",
  contact: "Names can't include links, handles or contact details.",
  reserved: 'That name is reserved. Try another.',
  digits: "Names can't include long numbers (like phone numbers).",
};

export function normalizeName(raw) {
  if (typeof raw !== 'string') return '';
  return raw.normalize('NFKC').replace(/[​-‍﻿]/g, '').trim().replace(/\s+/g, ' ');
}

// Character-level rules (shared with the client). Returns null or an error key.
export function shapeError(name) {
  if (name.length < MIN_LEN || name.length > MAX_LEN) return 'length';
  if (!/^[A-Za-z0-9 _]+$/.test(name)) return 'characters';
  if (/ {2,}/.test(name) || name !== name.trim()) return 'spacing';
  if ((name.match(/[A-Za-z]/g) || []).length < 2) return 'letters';
  if ((name.match(/[0-9]/g) || []).length >= 6) return 'digits';
  return null;
}

// Full moderation decision.  reserved: extra reserved normalised names (DB).
export function moderate(raw, reserved = []) {
  const name = normalizeName(raw);
  const shape = shapeError(name);
  if (shape) return { ok: false, error: 'name_' + shape, reason: shape, message: MESSAGES[shape], name };
  const toks = tokens(name);
  for (const [cat, l] of Object.entries(LISTS)) {
    if (toks.some((t) => l.tok.includes(t) || l.tok.includes(collapse(t)))) {
      return { ok: false, error: 'name_rejected', reason: cat, message: MESSAGES[cat], name };
    }
  }
  for (const v of variants(name)) {
    // harmless words are cut out first, but only when they are really spelled
    // that way (so a collapsed slur can't hide behind a place name)
    let s = v.col;
    let r = v.raw;
    for (const w of ALLOW_PAIRS) {
      if (v.raw.includes(w.raw)) {
        s = s.split(w.col).join('|');
        r = r.split(w.raw).join('|');
      }
    }
    for (const [cat, l] of Object.entries(LISTS)) {
      if (l.sub.some((term) => term.length >= 3 && s.includes(term)) || l.raw.some((term) => term.length >= 3 && r.includes(term))) {
        return { ok: false, error: 'name_rejected', reason: cat, message: MESSAGES[cat], name };
      }
    }
  }
  const norm = name.toLowerCase();
  const sk0 = skeletons(name)[0];
  void sk0;
  const res = [...BUILTIN_RESERVED, ...reserved];
  if (res.includes(norm) || res.map((r) => collapse(r.replace(/[\s_]/g, ''))).some((r) => skeletons(name).includes(r))) {
    return { ok: false, error: 'name_reserved', reason: 'reserved', message: MESSAGES.reserved, name };
  }
  return { ok: true, name, norm };
}

const ADJ = ['Sleepy', 'Cozy', 'Fuzzy', 'Snug', 'Dreamy', 'Comfy', 'Drowsy', 'Moonlit', 'Splashy', 'Bouncy', 'Quiet', 'Sneaky',
  'Speedy', 'Wobbly', 'Snoozy', 'Twinkly'];
const ANIMALS = ['Otter', 'Panda', 'Koala', 'Gecko', 'Puffin', 'Newt', 'Walrus', 'Moose', 'Frog', 'Duck', 'Badger', 'Fox',
  'Owl', 'Lamb', 'Seal', 'Hedgehog'];

export function suggestions(seedText = '', n = 3, reserved = []) {
  let h = 2166136261;
  for (const c of String(seedText)) h = Math.imul(h ^ c.charCodeAt(0), 16777619) >>> 0;
  const out = [];
  let i = 0;
  while (out.length < n && i < 64) {
    h = Math.imul(h ^ (i + 7), 16777619) >>> 0;
    const s = `${ADJ[h % ADJ.length]} ${ANIMALS[(h >>> 8) % ANIMALS.length]} ${10 + ((h >>> 16) % 90)}`;
    if (s.length <= MAX_LEN && moderate(s, reserved).ok && !out.includes(s)) out.push(s);
    i++;
  }
  return out;
}
