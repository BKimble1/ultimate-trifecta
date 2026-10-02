// Cloudflare Worker entry.  Bindings (wrangler.toml): DB (D1).  Vars:
// ENVIRONMENT, BUNDLE_ID, GC_KEY_HOSTS, SUPPORT_EMAIL, SUPPORT_URL,
// PRIVACY_URL, MIN_CLIENT_BUILD, ADMISSION_KEY_ID.  Secrets (wrangler secret
// put): SESSION_KEY, ADMISSION_PRIVATE_KEY, ADMIN_TOKEN.
import { handle, sweep } from './app.js';

export default {
  async fetch(req, env) {
    return handle(req, env);
  },
  async scheduled(_event, env, ctx) {
    ctx.waitUntil(sweep(env));
  },
};
