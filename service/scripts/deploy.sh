#!/usr/bin/env bash
# Deploys the service to the owner's Cloudflare account.  Requires the owner's
# own credentials (wrangler login, or CLOUDFLARE_API_TOKEN in the environment)
# and a D1 database id in wrangler.toml.  It creates no paid resources: Workers
# and D1 have free tiers, and this script only uses what is already there.
#   service/scripts/gen_keys.sh      # once
#   service/scripts/deploy.sh        # every release
#   DEPLOY_ENV=production service/scripts/deploy.sh   # V6: the App Store build's deployment
set -euo pipefail
cd "$(dirname "$0")/.."
command -v npx >/dev/null || { echo "Node.js (npx) is required"; exit 1; }
ENV_ARGS=()
DB=trifecta
if [ "${DEPLOY_ENV:-}" = production ]; then
  ENV_ARGS=(--env production)
  DB=trifecta-production
  grep -q "REPLACE_WITH_PRODUCTION_D1_DATABASE_ID" wrangler.toml && { echo "Set [env.production] database_id first: npx wrangler d1 create trifecta-production"; exit 1; }
elif grep -q "REPLACE_WITH_D1_DATABASE_ID" wrangler.toml; then
  echo "Set database_id in wrangler.toml first: npx wrangler d1 create trifecta"; exit 1
fi
node tools/sync_catalogue.mjs --check   # the Worker's catalogue copy matches the game
for f in session_key admin_token admission_private.pem; do
  [ -f ".secrets/$f" ] || { echo "Missing .secrets/$f: run scripts/gen_keys.sh"; exit 1; }
done
npm test
npx wrangler d1 migrations apply "$DB" --remote ${ENV_ARGS[@]+"${ENV_ARGS[@]}"}
npx wrangler secret put SESSION_KEY ${ENV_ARGS[@]+"${ENV_ARGS[@]}"} < .secrets/session_key
npx wrangler secret put ADMIN_TOKEN ${ENV_ARGS[@]+"${ENV_ARGS[@]}"} < .secrets/admin_token
npx wrangler secret put ADMISSION_PRIVATE_KEY ${ENV_ARGS[@]+"${ENV_ARGS[@]}"} < .secrets/admission_private.pem
# V6, optional: an App Store Connect In-App Purchase key lets the service ask
# Apple's App Store Server API about each transaction (docs/COMMERCE_SETUP.md)
if [ -f .secrets/asc_iap_key.p8 ] && [ -f .secrets/asc_iap_key_id ] && [ -f .secrets/asc_iap_issuer_id ]; then
  npx wrangler secret put ASC_IAP_PRIVATE_KEY ${ENV_ARGS[@]+"${ENV_ARGS[@]}"} < .secrets/asc_iap_key.p8
  npx wrangler secret put ASC_IAP_KEY_ID ${ENV_ARGS[@]+"${ENV_ARGS[@]}"} < .secrets/asc_iap_key_id
  npx wrangler secret put ASC_IAP_ISSUER_ID ${ENV_ARGS[@]+"${ENV_ARGS[@]}"} < .secrets/asc_iap_issuer_id
fi
npx wrangler deploy ${ENV_ARGS[@]+"${ENV_ARGS[@]}"}
echo "Deployed.  Check: curl -s https://<your-worker>.workers.dev/v1/health"
