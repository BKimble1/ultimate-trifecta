#!/usr/bin/env bash
# Deploys the service to the owner's Cloudflare account.  Requires the owner's
# own credentials (wrangler login, or CLOUDFLARE_API_TOKEN in the environment)
# and a D1 database id in wrangler.toml.  It creates no paid resources: Workers
# and D1 have free tiers, and this script only uses what is already there.
#   service/scripts/gen_keys.sh      # once
#   service/scripts/deploy.sh        # every release
set -euo pipefail
cd "$(dirname "$0")/.."
command -v npx >/dev/null || { echo "Node.js (npx) is required"; exit 1; }
if grep -q "REPLACE_WITH_D1_DATABASE_ID" wrangler.toml; then
  echo "Set database_id in wrangler.toml first: npx wrangler d1 create trifecta"; exit 1
fi
for f in session_key admin_token admission_private.pem; do
  [ -f ".secrets/$f" ] || { echo "Missing .secrets/$f: run scripts/gen_keys.sh"; exit 1; }
done
npm test
npx wrangler d1 migrations apply trifecta --remote
npx wrangler secret put SESSION_KEY < .secrets/session_key
npx wrangler secret put ADMIN_TOKEN < .secrets/admin_token
npx wrangler secret put ADMISSION_PRIVATE_KEY < .secrets/admission_private.pem
npx wrangler deploy
echo "Deployed.  Check: curl -s https://<your-worker>.workers.dev/v1/health"
