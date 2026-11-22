#!/usr/bin/env bash
# End-to-end test of party codes over the service relay, on this machine:
#
#   1. the real service (service/src/worker.js: Worker + RelayRoom Durable
#      Object + local D1) under `wrangler dev --local`, with secrets made for
#      this run only;
#   2. two Godot processes, a host and a guest, each signed in as its own
#      player, going through the game's own party code path (App ->
#      Cloud rooms/admission -> RelayTransport -> NetSession).
#
# Game Center can't sign identities here, so the two players are written into
# the local D1 (profile + verified identity, as sign-in would leave them) and
# their session tokens are minted with this run's SESSION_KEY by the service's
# own issueSession(); the Worker verifies them exactly as any other.  Nothing
# in the service is bypassed or changed for this.
#
#   tools/relay_e2e.sh            (PORT=8799 by default; KEEP=1 keeps the work dir)
#
# Needs: node 22+, openssl, npx (downloads wrangler@4.156.0 once), the pinned
# Godot (tools/fetch_godot.sh).  Exits 0 when both sides passed.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(dirname "$HERE")"
SVC="$ROOT/service"
PORT="${PORT:-8799}"
W=(npx --yes wrangler@4.156.0)
export WRANGLER_SEND_METRICS=false CI=1
WORK="$(mktemp -d "${TMPDIR:-/tmp}/relay-e2e.XXXXXX")"
STATE="$WORK/state"
WPID=""
cleanup() {
  # wrangler runs workerd as a child: stop the whole process group
  [ -n "$WPID" ] && { kill -- "-$WPID" 2>/dev/null || kill "$WPID" 2>/dev/null; wait "$WPID" 2>/dev/null; } || true
  [ "${KEEP:-0}" = 1 ] && echo "work dir kept: $WORK" || rm -rf "$WORK"
}
trap cleanup EXIT
echo "== work dir $WORK"

# --- this run's secrets (never committed, gone with the work dir)
openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:2048 -out "$WORK/adm.pem" 2>/dev/null
openssl pkey -in "$WORK/adm.pem" -pubout -out "$WORK/admission_public.pem"
SESSION_KEY="e2e-$(openssl rand -hex 24)"
{
  echo "SESSION_KEY=\"$SESSION_KEY\""
  echo "ADMIN_TOKEN=\"e2e-admin-$(openssl rand -hex 16)\""
  echo "APP_ACCOUNT_TOKEN_KEY=\"e2e-$(openssl rand -hex 24)\""
  printf 'ADMISSION_PRIVATE_KEY="%s"\n' "$(awk 'BEGIN{ORS="\\n"} {print}' "$WORK/adm.pem")"
} > "$WORK/dev.vars"

# --- the local database
cd "$SVC"
echo "== migrations (local D1)"
"${W[@]}" d1 migrations apply trifecta --local --persist-to "$STATE" >"$WORK/migrate.log" 2>&1 || { cat "$WORK/migrate.log"; exit 1; }
NOW=$(node -e 'console.log(Date.now())')
"${W[@]}" d1 execute trifecta --local --persist-to "$STATE" --command "
  INSERT INTO profiles (id, created_at, updated_at, display_name, name_norm, discriminator, status)
    VALUES ('p_e2ehost', $NOW, $NOW, 'Host Otter', 'host otter', 1111, 'active'),
           ('p_e2eguest', $NOW, $NOW, 'Guest Otter', 'guest otter', 2222, 'active');
  INSERT INTO identities (provider, subject, environment, profile_id, created_at, last_seen)
    VALUES ('gamecenter', 'G:e2e-host', 'sandbox', 'p_e2ehost', $NOW, $NOW),
           ('gamecenter', 'G:e2e-guest', 'sandbox', 'p_e2eguest', $NOW, $NOW);" >"$WORK/seed.log" 2>&1 || { cat "$WORK/seed.log"; exit 1; }

# --- the two players' sessions (the service's own token code, this run's key)
SESSION_KEY="$SESSION_KEY" OUT="$WORK" node --input-type=module -e '
import { issueSession } from "./src/tokens.js";
import { writeFileSync } from "node:fs";
const env = { SESSION_KEY: process.env.SESSION_KEY, ENVIRONMENT: "sandbox", BUNDLE_ID: "com.idlery.ultimatetrifecta" };
for (const [role, pid, player, name, disc] of [["host", "p_e2ehost", "G:e2e-host", "Host Otter", "1111"], ["guest", "p_e2eguest", "G:e2e-guest", "Guest Otter", "2222"]]) {
  const { token, payload } = await issueSession(env, pid, Date.now());
  writeFileSync(`${process.env.OUT}/${role}.json`, JSON.stringify({ token, expires_at: payload.exp * 1000, player,
    host_name: "Host Otter", guest_name: "Guest Otter",
    profile: { profile_id: pid, display_name: name, discriminator: disc, needs_name: false, status: "active" } }));
}'

# --- the service
echo "== wrangler dev --local on 127.0.0.1:$PORT"
if curl -s -o /dev/null "http://127.0.0.1:$PORT/" 2>/dev/null; then
  echo "port $PORT is already in use (another wrangler dev?): set PORT=..." >&2
  exit 1
fi
setsid "${W[@]}" dev --local --ip 127.0.0.1 --port "$PORT" --persist-to "$STATE" --env-file "$WORK/dev.vars" \
  --show-interactive-dev-session=false >"$WORK/wrangler.log" 2>&1 &
WPID=$!
for _ in $(seq 1 90); do
  curl -sf "http://127.0.0.1:$PORT/v1/health" >/dev/null 2>&1 && break
  kill -0 "$WPID" 2>/dev/null || { cat "$WORK/wrangler.log"; exit 1; }
  sleep 1
done
curl -sf "http://127.0.0.1:$PORT/v1/config" | node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{const c=JSON.parse(s);console.log("   /v1/config environment="+c.environment+" features="+c.features.join(","))})'

# --- host and guest (separate user data: XDG_DATA_HOME)
cd "$ROOT"
"$HERE/gd.sh" --headless --path "$ROOT/game" --import >/dev/null 2>&1 || true
run_side() {
  XDG_DATA_HOME="$WORK/data_$1" "$HERE/gd.sh" --headless --path "$ROOT/game" -s res://tests/relay_e2e.gd -- \
    --no-app --no-gamecenter "--service-url=http://127.0.0.1:$PORT" "--relay-e2e=$1" "--e2e-dir=$WORK" >"$WORK/$1.log" 2>&1
}
echo "== host and guest"
run_side host & HPID=$!
run_side guest & GPID=$!
HS=0; GS=0
wait "$HPID" || HS=$?
wait "$GPID" || GS=$?
echo "--- host";  grep '^E2E' "$WORK/host.log" || tail -30 "$WORK/host.log"
echo "--- guest"; grep '^E2E' "$WORK/guest.log" || tail -30 "$WORK/guest.log"
echo "--- service (relay and rooms)"
grep -E '/v1/(relay|rooms)' "$WORK/wrangler.log" | sed -E 's/token=[^ &]+/token=…/' | head -40 || true
if [ "$HS" = 0 ] && [ "$GS" = 0 ]; then
  echo "RELAY E2E: PASS"
else
  echo "RELAY E2E: FAIL (host exit $HS, guest exit $GS)"
  KEEP=1
  exit 1
fi
