#!/usr/bin/env bash
# Generates the service secrets into service/.secrets/ (git-ignored) and prints
# the admission PUBLIC key that goes into the game (game/config/service.cfg).
# Nothing is uploaded; deploy.sh reads these files.
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .secrets && chmod 700 .secrets
[ -f .secrets/session_key ] || openssl rand -base64 48 | tr -d '\n' > .secrets/session_key
[ -f .secrets/admin_token ] || openssl rand -hex 32 | tr -d '\n' > .secrets/admin_token
if [ ! -f .secrets/admission_private.pem ]; then
  openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:2048 -out .secrets/admission_private.pem 2>/dev/null
fi
openssl pkey -in .secrets/admission_private.pem -pubout -out .secrets/admission_public.pem
chmod 600 .secrets/*
echo "Secrets are in service/.secrets/ (keep them out of git and chat)."
echo "Admission public key for game/config/service.cfg:"
cat .secrets/admission_public.pem
