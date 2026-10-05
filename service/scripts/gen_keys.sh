#!/usr/bin/env bash
# Generates the service secrets into service/.secrets/ (git-ignored) and prints
# the admission PUBLIC key that goes into the game (game/config/service.cfg).
# Nothing is uploaded; deploy.sh reads these files.
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .secrets && chmod 700 .secrets
[ -f .secrets/session_key ] || openssl rand -base64 48 | tr -d '\n' > .secrets/session_key
[ -f .secrets/admin_token ] || openssl rand -hex 32 | tr -d '\n' > .secrets/admin_token
# FINAL_RELEASE_SWEEP: derives each player's StoreKit appAccountToken.  ONE
# value for BOTH deployments (deploy.sh uploads this same file to sandbox and
# production): never regenerate it once purchases exist.
[ -f .secrets/app_account_token_key ] || openssl rand -base64 48 | tr -d '\n' > .secrets/app_account_token_key
# Friends: the key for the keyed hashes of friend IDs (src/friends.js).  Keep
# it stable: a new key makes every stored friend set unreadable until each
# game syncs again (it does on its next launch or Friends visit).
[ -f .secrets/friend_hash_key ] || openssl rand -base64 48 | tr -d '\n' > .secrets/friend_hash_key
if [ ! -f .secrets/admission_private.pem ]; then
  openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:2048 -out .secrets/admission_private.pem 2>/dev/null
fi
openssl pkey -in .secrets/admission_private.pem -pubout -out .secrets/admission_public.pem
chmod 600 .secrets/*
echo "Secrets are in service/.secrets/ (keep them out of git and chat)."
echo "Admission public key for game/config/service.cfg:"
cat .secrets/admission_public.pem
