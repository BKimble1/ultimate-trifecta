// Typed party chat: the message policy.  The service is the only authority
// that approves a typed message (POST /v1/chat/check signs the approved
// text); the game runs the same rules (game/src/core/chat_rules.gd) to give
// instant feedback and as a receiver-side defence, never as approval.
//
// Pipeline (decision = first failing step):
//   normalise   NFKC, zero-width / bidi / soft-hyphen characters removed,
//               tabs and newlines are spaces, runs of spaces collapsed, trimmed
//   empty       nothing left
//   length      at most CHAT_MAX characters
//   characters  printable ASCII, Latin-1 and Latin Extended-A letters, and
//               typographic quotes / ellipsis only (no emoji, no other
//               scripts: their look-alike letters can spell anything)
//   markup      < > [ ] { } \ ` (no markup reaches a label, ever)
//   spam        a character repeated more than 6 times, or the same word
//               more than 4 times in a row
//   contact     links (scheme, www, name.tld, "dot com"), e-mail addresses,
//               @handles, phone numbers (7+ digits), contact apps and "add
//               me"-style phrases
//   words       every word (and every word with its separators removed, and
//               runs of single letters joined) against the shared slur /
//               sexual / profanity / threat lists, with leetspeak and
//               repeated letters handled and harmless ALLOW words cut out
//               first; threat phrases ("kill you") over 2-3 word windows
import * as T from './terms.js';
import { substringCategory, squeeze2 } from './names.js';

export const CHAT_MAX = 100;

const dec = (arr) => arr.map((s) => atob(s));
const LEET = { '0': 'o', '1': 'i', '3': 'e', '4': 'a', '5': 's', '6': 'g', '7': 't', '8': 'b', '9': 'g', '2': 'z', '@': 'a', $: 's', '!': 'i' };
const LEET_ALT = { '1': 'l', '0': 'o', '6': 'b', '!': 'l' };

function collapse(s) {
  return s.replace(/(.)\1+/g, '$1');
}

const dl = (words) => {
  const col = words.filter((w) => collapse(w) === w ? w.length >= 3 : collapse(w).length >= 4).map(collapse);
  return { col, raw: words.filter((w) => w.length >= 3) };
};
// chat checks the abuse lists only (staff words and "contact" substrings
// are fine in a sentence; links and handles have their own patterns)
const SUBLISTS = {
  slur: dl(dec(T.SLURS)),
  sexual: dl(dec(T.SEXUAL)),
  profanity: dl(dec(T.PROFANITY)),
  threat: dl(T.THREATS),
};
const TOK = {
  slur: dec(T.SLUR_TOKENS),
  sexual: dec(T.SEXUAL_TOKENS),
  profanity: [],
  threat: T.THREAT_TOKENS,
};
const EXACT = {
  slur: dec(T.SLURS),
  sexual: dec(T.SEXUAL),
  profanity: dec(T.PROFANITY),
  threat: T.THREATS,
};
const CATS = ['slur', 'sexual', 'profanity', 'threat'];

// contact apps / services (substring of a word skeleton) and whole-word
// contact tokens.  "gg", "io", "com" are not chat tokens ("gg" is good game):
// real links are caught by the link patterns instead.
export const CONTACT_WORDS = ['discord', 'snapchat', 'instagram', 'tiktok', 'telegram', 'whatsapp', 'twitter', 'youtube',
  'twitch', 'paypal', 'venmo', 'cashapp', 'gmail', 'yahoo', 'hotmail', 'icloud', 'onlyfans'];
export const CONTACT_TOKENS = ['dm', 'dms', 'snap', 'insta', 'ig', 'fb', 'kik', 'email', 'tel', 'ttv', 'yt', 'whatsapp', 'wa'];
export const CONTACT_PHRASES = ['addme', 'dmme', 'textme', 'callme', 'followme', 'messageme', 'pmme', 'snapme', 'mynumber', 'myinsta', 'mysnap'];
const TLDS = 'com|net|org|gg|io|me|co|tv|ly|app|xyz|ru|uk|us|de|fr|info|biz|link|site|online|club|live|to|cc|fun|gay|sex|xxx';
const LINK_RES = [
  /https?\s*:\s*\/\//i,
  /\bwww\s*\./i,
  new RegExp(`[a-z0-9-]{2,}\\s*(\\.|\\(dot\\)|\\[dot\\]|\\sdot\\s)\\s*(${TLDS})\\b`, 'i'),
  /[a-z0-9._%+-]+\s*@\s*[a-z0-9-]+\s*\.\s*[a-z]{2,}/i,
  /(^|\s)@[a-z0-9_.]{3,}/i,
];

export const MESSAGES = {
  empty: 'Type a message first.',
  length: `Messages are up to ${CHAT_MAX} characters.`,
  characters: 'Use plain letters, numbers and punctuation.',
  markup: 'Use plain letters, numbers and punctuation.',
  spam: 'That looks like spam. Try a shorter message.',
  contact: "Chat can't include links, handles or contact details.",
  slur: "That message isn't allowed. Please keep chat kind.",
  sexual: "That message isn't allowed. Please keep chat friendly for everyone.",
  profanity: "That message isn't allowed. Please keep chat friendly for everyone.",
  threat: "That message isn't allowed. Please keep chat friendly for everyone.",
};

// Latin letters with accents -> plain letters (for the word checks only;
// the approved text keeps its accents).
const FOLD = (() => {
  const m = {};
  const add = (chars, to) => { for (const c of chars) m[c] = to; };
  add('ÀÁÂÃÄÅàáâãäåĀāĂăĄą', 'a'); add('ÇçĆćĈĉĊċČč', 'c'); add('ĎďĐđÐ', 'd'); add('ÈÉÊËèéêëĒēĔĕĖėĘęĚě', 'e');
  add('ĜĝĞğĠġĢģ', 'g'); add('ĤĥĦħ', 'h'); add('ÌÍÎÏìíîïĨĩĪīĬĭĮįİı', 'i'); add('Ĵĵ', 'j'); add('Ķķĸ', 'k');
  add('ĹĺĻļĽľĿŀŁł', 'l'); add('ÑñŃńŅņŇňŉŊŋ', 'n'); add('ÒÓÔÕÖØòóôõöøŌōŎŏŐő', 'o'); add('ŔŕŖŗŘř', 'r');
  add('ŚśŜŝŞşŠšſß', 's'); add('ŢţŤťŦŧ', 't'); add('ÙÚÛÜùúûüŨũŪūŬŭŮůŰűŲų', 'u'); add('Ŵŵ', 'w'); add('ÝýÿŶŷŸ', 'y');
  add('ŹźŻżŽž', 'z'); add('Ææ', 'ae'); add('Œœ', 'oe'); add('Þþ', 'th'); add('Ĳĳ', 'ij');
  return m;
})();

export function fold(s) {
  let o = '';
  for (const c of s) o += FOLD[c] ?? c;
  return o;
}

const ZW = /[\u00AD\u180E\u200B-\u200F\u202A-\u202E\u2060-\u2064\u2066-\u2069\uFEFF]/g;

export function normalizeChat(raw) {
  if (typeof raw !== 'string') return '';
  return raw.normalize('NFKC').replace(ZW, '').replace(/[\t\n\r\v\f\u0085\u2028\u2029]/g, ' ').replace(/ {2,}/g, ' ').trim();
}

function allowedChar(cp) {
  if (cp >= 0x20 && cp <= 0x7e) return true;
  if (cp >= 0xc0 && cp <= 0x17f && cp !== 0xd7 && cp !== 0xf7) return true;
  return [0x2018, 0x2019, 0x201c, 0x201d, 0x2026].includes(cp);
}

// Word variants for matching: leet readings (two for 1/0/6/!), and each as
// spelled and with repeated letters collapsed ("fuuuck" -> "fuck").
function wordVariants(w) {
  const out = new Set();
  for (const f of [(c) => LEET[c] ?? c, (c) => LEET_ALT[c] ?? LEET[c] ?? c]) {
    const raw = [...w].map(f).join('');
    for (const r of [raw, raw.replace(/rn/g, 'm').replace(/vv/g, 'w')]) out.add(r);
  }
  return [...out];
}

// The category a single word falls in, or null: whole-word lists first,
// then the substring lists (shared with names) on each spelling.
export function wordCategory(word) {
  if (!word) return null;
  const hasLetter = /[a-z]/.test(word);
  const vs = hasLetter ? wordVariants(word) : [word];
  for (const v of vs) {
    for (const cat of CATS) {
      for (const f of [v, collapse(v), squeeze2(v)]) {
        if (TOK[cat].includes(f) || EXACT[cat].includes(f)) return cat;
      }
    }
  }
  for (const v of vs) {
    const cat = substringCategory(v, SUBLISTS);
    if (cat) return cat;
  }
  return null;
}

function contactWord(word) {
  if (CONTACT_TOKENS.includes(word)) return true;
  const vs = /[a-z]/.test(word) ? wordVariants(word) : [word];
  return vs.some((v) => CONTACT_WORDS.some((c) => v.includes(c) || collapse(v).includes(collapse(c))));
}

// Decision for one typed message: {ok, text} or {ok:false, reason, message}.
export function checkChat(raw) {
  const no = (reason) => ({ ok: false, reason, message: MESSAGES[reason] });
  if (typeof raw !== 'string') return no('empty');
  for (const c of raw) {
    const cp = c.codePointAt(0);
    if ((cp < 0x20 && !'\t\n\r'.includes(c)) || (cp >= 0x7f && cp <= 0x9f)) return no('characters');
  }
  const text = normalizeChat(raw);
  if (text.length === 0) return no('empty');
  if ([...text].length > CHAT_MAX) return no('length');
  for (const c of text) if (!allowedChar(c.codePointAt(0))) return no('characters');
  if (/[<>[\]{}\\`]/.test(text)) return no('markup');
  if (/(.)\1{6,}/u.test(text)) return no('spam');
  const lower = fold(text.toLowerCase());
  const plainWords = lower.split(/[^a-z0-9]+/).filter(Boolean);
  for (let i = 0, run = 1; i + 1 < plainWords.length; i++) {
    run = plainWords[i] === plainWords[i + 1] ? run + 1 : 1;
    if (run > 4) return no('spam');
  }
  if (LINK_RES.some((re) => re.test(lower))) return no('contact');
  // phone numbers: 7+ digits with only separators between them
  if (/\d(?:[\s().+-]*\d){6,}/.test(lower)) return no('contact');
  // chunks: whitespace-separated; each is checked as its words and with its
  // separators removed ("f.u.c.k", "sh-it", "f*ck")
  const chunks = lower.split(' ').filter(Boolean);
  const words = [];
  for (const ch of chunks) {
    // "!" ends a sentence; inside a word it is a letter ("sh!t")
    const c2 = ch.replace(/!+$/, '').replace(/!+(?=[^a-z0-9@$!])/g, '');
    const joined = c2.replace(/[^a-z0-9@$!]/g, '');
    const parts = c2.split(/[^a-z0-9@$!]+/).filter(Boolean);
    for (const p of parts) words.push(p);
    for (const w of new Set([joined, ...parts])) {
      if (contactWord(w)) return no('contact');
      const cat = wordCategory(w);
      if (cat) return no(cat);
    }
  }
  // runs of single letters, joined ("f u c k")
  let run = '';
  for (const w of [...words, '']) {
    if (w.length === 1) {
      run += w;
      continue;
    }
    if (run.length >= 3) {
      const cat = wordCategory(run);
      if (cat) return no(cat);
      if (contactWord(run)) return no('contact');
    }
    run = '';
  }
  // phrases over 2-3 word windows ("kill you", "add me", "kill your self")
  for (let i = 0; i < words.length; i++) {
    for (const n of [2, 3]) {
      if (i + n > words.length) continue;
      const j = words.slice(i, i + n).join('');
      const jv = wordVariants(j).map(collapse);
      if (T.THREATS.some((t) => j === t || jv.includes(collapse(t)))) return no('threat');
      if (CONTACT_PHRASES.some((t) => j === t || jv.includes(collapse(t)))) return no('contact');
    }
  }
  return { ok: true, text };
}
