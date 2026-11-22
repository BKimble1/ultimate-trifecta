#!/usr/bin/env bash
# Deploys the game service (both deployments) and, optionally, the website
# from GitHub Actions (.github/workflows/service.yml), with nothing but a
# Cloudflare API token (repository secret CLOUDFLARE_API_TOKEN).
#
# First run: creates the two D1 databases, the Workers and the Pages project,
# generates every service secret ON THE RUNNER, uploads it straight to
# Cloudflare (the only place it is kept) and prints the admission PUBLIC key
# for game/config/service.cfg.  Later runs: applies new migrations and
# redeploys; secrets already in Cloudflare are left alone (they never leave
# it, so they are never regenerated: APP_ACCOUNT_TOKEN_KEY must not change
# once purchases exist).  The admin token is not shown anywhere: set a new one
# whenever you need it with `npx wrangler secret put ADMIN_TOKEN`.
#
#   WEBSITE=true   also publish website/ to Cloudflare Pages
#   SUPPORT_EMAIL / SUPPORT_URL / PRIVACY_URL   (optional) public links
set -euo pipefail
cd "$(dirname "$0")/.."
: "${CLOUDFLARE_API_TOKEN:?Add the repository secret CLOUDFLARE_API_TOKEN (docs/OWNER_SETUP_GUIDE.md section C)}"
export WRANGLER_SEND_METRICS=false
W=(npx --yes wrangler@4.156.0)
API=https://api.cloudflare.com/client/v4
cf() { curl -sS -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" -H "Content-Type: application/json" "$@"; }
SUMMARY=${GITHUB_STEP_SUMMARY:-/dev/stdout}

# --- the account and its workers.dev subdomain
if [ -z "${CLOUDFLARE_ACCOUNT_ID:-}" ]; then
  CLOUDFLARE_ACCOUNT_ID=$(cf "$API/accounts?per_page=5" | jq -r '.result[0].id // empty')
  [ -n "$CLOUDFLARE_ACCOUNT_ID" ] || { echo "::error::The token can't see any account (it needs Account Settings: Read)"; cf "$API/accounts" | jq -c '.errors'; exit 1; }
  export CLOUDFLARE_ACCOUNT_ID
fi
SUB=$(cf "$API/accounts/$CLOUDFLARE_ACCOUNT_ID/workers/subdomain" | jq -r '.result.subdomain // empty')
if [ -z "$SUB" ]; then
  # an account that never used Workers has no workers.dev name yet
  for want in ultimate-trifecta "ultimate-trifecta-$(date +%s | tail -c 5)"; do
    SUB=$(cf -X PUT "$API/accounts/$CLOUDFLARE_ACCOUNT_ID/workers/subdomain" -d "{\"subdomain\":\"$want\"}" | jq -r '.result.subdomain // empty')
    [ -n "$SUB" ] && break
  done
  [ -n "$SUB" ] || { echo "::error::Could not register a workers.dev subdomain"; exit 1; }
fi
echo "workers.dev subdomain: $SUB"

# --- the website
SITE=""
if [ "${WEBSITE:-false}" = true ]; then
  echo "::group::Website"
  cf "$API/accounts/$CLOUDFLARE_ACCOUNT_ID/pages/projects/ultimate-trifecta" | jq -e '.success' >/dev/null \
    || "${W[@]}" pages project create ultimate-trifecta --production-branch main
  "${W[@]}" pages deploy ../website --project-name ultimate-trifecta --branch main --commit-dirty=true
  SITE=$(cf "$API/accounts/$CLOUDFLARE_ACCOUNT_ID/pages/projects/ultimate-trifecta" | jq -r '.result.subdomain // empty')
  # the game's Privacy and Support links default to the website's pages
  [ -n "$SITE" ] && SUPPORT_URL=${SUPPORT_URL:-https://$SITE/support/} && PRIVACY_URL=${PRIVACY_URL:-https://$SITE/privacy/}
  echo "::endgroup::"
fi

# --- the two databases (their ids are not secret)
db_id() { "${W[@]}" d1 list --json 2>/dev/null | jq -r --arg n "$1" '.[] | select(.name == $n) | .uuid' | head -1; }
for name in trifecta trifecta-production; do
  [ -n "$(db_id $name)" ] || "${W[@]}" d1 create "$name" >/dev/null
done
SANDBOX_DB=$(db_id trifecta)
PROD_DB=$(db_id trifecta-production)
[ -n "$SANDBOX_DB" ] && [ -n "$PROD_DB" ] || { echo "::error::D1 databases missing (the token needs D1: Edit)"; exit 1; }
sed -i "s/REPLACE_WITH_D1_DATABASE_ID/$SANDBOX_DB/; s/REPLACE_WITH_PRODUCTION_D1_DATABASE_ID/$PROD_DB/" wrangler.toml
grep -q "$SANDBOX_DB" wrangler.toml && grep -q "$PROD_DB" wrangler.toml || {
  echo "::error::wrangler.toml names other database ids than this account's ($SANDBOX_DB, $PROD_DB)"; exit 1; }
# public links (empty: the game hides them)
for v in SUPPORT_EMAIL SUPPORT_URL PRIVACY_URL; do
  [ -n "${!v:-}" ] && sed -i "s|^$v = \"\"|$v = \"${!v}\"|" wrangler.toml
done

node tools/sync_catalogue.mjs --check
npm test

# --- secrets already on each deployment
has_secrets() {   # $1: env args ("" or "--env production"), $2: worker name
  # a worker that isn't there yet has none; one that is must answer (never
  # regenerate a secret because a listing failed: APP_ACCOUNT_TOKEN_KEY must
  # not change)
  if ! cf "$API/accounts/$CLOUDFLARE_ACCOUNT_ID/workers/scripts/$2/settings" | jq -e '.success' >/dev/null; then
    return 0
  fi
  local out
  # shellcheck disable=SC2086
  out=$("${W[@]}" secret list $1 --format json) || { echo "::error::Could not list the secrets of $2" >&2; exit 1; }
  jq -r '.[].name' <<<"$out"
}
NEED="SESSION_KEY ADMIN_TOKEN ADMISSION_PRIVATE_KEY APP_ACCOUNT_TOKEN_KEY FRIEND_HASH_KEY"
S_HAVE=$(has_secrets "" trifecta-service)
P_HAVE=$(has_secrets "--env production" trifecta-service-production)
missing() { for s in $NEED; do grep -qx "$s" <<<"$1" || echo "$s"; done; }
S_MISS=$(missing "$S_HAVE")
P_MISS=$(missing "$P_HAVE")
FIRST=false
if [ -n "$S_MISS" ] || [ -n "$P_MISS" ]; then
  # the admission key pair and APP_ACCOUNT_TOKEN_KEY are shared by both
  # deployments; a secret can't be read back, so both must be set together
  for s in ADMISSION_PRIVATE_KEY APP_ACCOUNT_TOKEN_KEY; do
    if printf '%s\n%s\n' "$S_HAVE" "$P_HAVE" | grep -qx "$s" && { grep -qx "$s" <<<"$S_MISS" || grep -qx "$s" <<<"$P_MISS"; }; then
      echo "::error::$s is set on one deployment only; it must be the same on both. Set it by hand (wrangler secret put) on the other."
      exit 1
    fi
  done
  FIRST=true
  scripts/gen_keys.sh >/dev/null
fi

file_for() {
  case $1 in
    SESSION_KEY) echo .secrets/session_key ;;
    ADMIN_TOKEN) echo .secrets/admin_token ;;
    ADMISSION_PRIVATE_KEY) echo .secrets/admission_private.pem ;;
    APP_ACCOUNT_TOKEN_KEY) echo .secrets/app_account_token_key ;;
    FRIEND_HASH_KEY) echo .secrets/friend_hash_key ;;
  esac
}

deploy_one() {   # $1: label, $2: database name, $3: env args, $4: missing secrets
  echo "::group::$1"
  # shellcheck disable=SC2086
  "${W[@]}" d1 migrations apply "$2" --remote $3
  # shellcheck disable=SC2086
  "${W[@]}" deploy $3
  for s in $4; do
    # shellcheck disable=SC2086
    "${W[@]}" secret put "$s" $3 < "$(file_for "$s")"
  done
  echo "::endgroup::"
}
deploy_one "Sandbox (TestFlight, App Review)" trifecta "" "$S_MISS"
deploy_one "Production (App Store)" trifecta-production "--env production" "$P_MISS"

S_URL="https://trifecta-service.$SUB.workers.dev"
P_URL="https://trifecta-service-production.$SUB.workers.dev"

# --- check
sleep 10
check() { curl -sS --max-time 20 "$1/v1/config" | jq -c '{environment, apple_environment, features}' 2>/dev/null || echo "(no answer yet)"; }
# (also in the log, so a run's answer can be read without the summary page)
echo "CHECK sandbox $(check "$S_URL")"
echo "CHECK production $(check "$P_URL")"
{
  echo "## Game service deployed"
  echo
  echo "| | URL | /v1/config |"
  echo "|---|---|---|"
  echo "| Sandbox (TestFlight) | $S_URL | \`$(check "$S_URL")\` |"
  echo "| Production (App Store) | $P_URL | \`$(check "$P_URL")\` |"
  [ -n "$SITE" ] && echo "| Website | https://$SITE | |"
  echo
  echo "D1 databases: trifecta \`$SANDBOX_DB\`, trifecta-production \`$PROD_DB\` (not secret: these go in service/wrangler.toml)."
  echo
  echo "App Store Server Notifications (Version 2): Production \`$P_URL/v1/appstore/notifications\`, Sandbox \`$S_URL/v1/appstore/notifications\`."
  if [ "$FIRST" = true ]; then
    echo
    echo "Secrets were generated on this runner and uploaded to Cloudflare only (missing were: sandbox \`$(echo $S_MISS)\`, production \`$(echo $P_MISS)\`)."
  fi
} >> "$SUMMARY"
# the admission PUBLIC key (public: it goes in the game) for service.cfg
if [ -f .secrets/admission_public.pem ]; then
  echo "ADMISSION_PUBLIC_KEY_BEGIN"
  awk 'BEGIN{ORS="\\n"} {print}' .secrets/admission_public.pem; echo
  echo "ADMISSION_PUBLIC_KEY_END"
fi
echo "SERVICE_URLS sandbox=$S_URL production=$P_URL site=${SITE:+https://$SITE}"
echo "D1_IDS sandbox=$SANDBOX_DB production=$PROD_DB"
rm -rf .secrets
