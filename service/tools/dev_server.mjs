#!/usr/bin/env node
// DEVELOPMENT ONLY - never deployed.  Serves the real service code
// (src/app.js handle()) over local HTTP with an in-memory database
// (node:sqlite, the same D1 shim the tests use), so desktop evidence runs
// can exercise sign-in, names, rooms/admission, typed-chat approval and
// reports end to end.  It is NOT the deployed service and proves nothing
// about a deployment.
//
// Game Center can't sign identities on Linux, so this server holds a
// test-only "Game Center" key (a self-signed certificate made per run with
// openssl, as in test/helpers.mjs) and offers GET /dev/identity?player=ID,
// which returns an identity body signed with it.  The service verifies that
// signature exactly as it would Apple's (its key download is pointed at the
// test certificate).  Nothing here exists in src/worker.js.
//
//   node tools/dev_server.mjs PORT OUT_DIR
// writes OUT_DIR/admission_public.pem and OUT_DIR/admin_token.txt, and
// serves http://127.0.0.1:PORT until killed.
import { createServer } from 'node:http';
import { writeFileSync, mkdirSync } from 'node:fs';
import { join } from 'node:path';
import { generateKeyPairSync } from 'node:crypto';
import { makeEnv, gcBody } from '../test/helpers.mjs';
import { handle } from '../src/app.js';

const port = Number(process.argv[2] || 8787);
const out = process.argv[3] || '.';
mkdirSync(out, { recursive: true });
const ctx = makeEnv({ ENVIRONMENT: 'development', SUPPORT_EMAIL: '', SUPPORT_URL: '' });
ctx.env.__now = () => Date.now() + 60 * 1000;   // (the test certificate is valid from "now")
ctx.clock.t = Date.now() + 60 * 1000;
writeFileSync(join(out, 'admission_public.pem'), ctx.admPub.export({ type: 'spki', format: 'pem' }));
writeFileSync(join(out, 'admin_token.txt'), ctx.env.ADMIN_TOKEN);
void generateKeyPairSync;

createServer(async (req, res) => {
  const url = new URL(req.url, `http://127.0.0.1:${port}`);
  const chunks = [];
  for await (const c of req) chunks.push(c);
  const body = Buffer.concat(chunks);
  try {
    if (url.pathname === '/dev/identity') {
      ctx.clock.t = Date.now() + 60 * 1000;
      const b = gcBody(ctx, String(url.searchParams.get('player') || 'T:dev'));
      res.writeHead(200, { 'content-type': 'application/json' });
      res.end(JSON.stringify({ ok: true, ...b }));
      return;
    }
    const headers = {};
    for (const [k, v] of Object.entries(req.headers)) if (typeof v === 'string') headers[k] = v;
    const r = await handle(new Request(url.toString(), { method: req.method, headers,
      body: ['GET', 'HEAD'].includes(req.method) ? undefined : body }), ctx.env);
    const text = await r.text();
    res.writeHead(r.status, { 'content-type': 'application/json' });
    res.end(text);
    console.log(`${req.method} ${url.pathname} -> ${r.status}`);
  } catch (e) {
    res.writeHead(500, { 'content-type': 'application/json' });
    res.end(JSON.stringify({ ok: false, error: 'internal', message: String(e) }));
  }
}).listen(port, '127.0.0.1', () => console.log(`dev service (NOT deployed) on http://127.0.0.1:${port}`));
