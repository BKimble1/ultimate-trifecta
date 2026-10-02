// Minimal DER reader for X.509 certificates: extracts the
// SubjectPublicKeyInfo (for WebCrypto importKey 'spki') and the validity
// window.  Enough for Apple's Game Center identity-verification certificates.

function readTLV(buf, off) {
  const tag = buf[off];
  let len = buf[off + 1];
  let hdr = 2;
  if (len & 0x80) {
    const n = len & 0x7f;
    if (n < 1 || n > 4) throw new Error('bad DER length');
    len = 0;
    for (let i = 0; i < n; i++) len = (len * 256) + buf[off + 2 + i];
    hdr = 2 + n;
  }
  const start = off + hdr;
  const end = start + len;
  if (end > buf.length) throw new Error('DER overrun');
  return { tag, start, end, hdr, off };
}

function children(buf, tlv) {
  const out = [];
  let o = tlv.start;
  while (o < tlv.end) {
    const c = readTLV(buf, o);
    out.push(c);
    o = c.end;
  }
  return out;
}

function parseTime(buf, tlv) {
  const s = new TextDecoder().decode(buf.subarray(tlv.start, tlv.end));
  // UTCTime YYMMDDHHMMSSZ or GeneralizedTime YYYYMMDDHHMMSSZ
  let y, rest;
  if (tlv.tag === 0x17) {
    y = Number(s.slice(0, 2));
    y += y < 50 ? 2000 : 1900;
    rest = s.slice(2);
  } else {
    y = Number(s.slice(0, 4));
    rest = s.slice(4);
  }
  const mo = Number(rest.slice(0, 2)) - 1;
  const d = Number(rest.slice(2, 4));
  const h = Number(rest.slice(4, 6));
  const mi = Number(rest.slice(6, 8));
  const se = Number(rest.slice(8, 10));
  return Date.UTC(y, mo, d, h, mi, se);
}

export function parseCertificate(der) {
  const buf = der instanceof Uint8Array ? der : new Uint8Array(der);
  const cert = readTLV(buf, 0);
  if (cert.tag !== 0x30) throw new Error('not a certificate');
  const [tbs] = children(buf, cert);
  let parts = children(buf, tbs);
  if (parts[0].tag === 0xa0) parts = parts.slice(1);   // explicit version
  // serial, signature alg, issuer, validity, subject, spki
  const validity = children(buf, parts[3]);
  const spki = parts[5];
  return {
    notBefore: parseTime(buf, validity[0]),
    notAfter: parseTime(buf, validity[1]),
    spki: buf.slice(spki.off, spki.end),
  };
}

export function pemToDer(pem) {
  const b64 = pem.replace(/-----[^-]+-----/g, '').replace(/\s+/g, '');
  return Uint8Array.from(atob(b64), (c) => c.charCodeAt(0));
}
