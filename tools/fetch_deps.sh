#!/usr/bin/env bash
# Fetches pinned third-party binaries (not committed) into game/addons/.
# GodotApplePlugins (MIT) — Game Center bindings used for iOS rooms/invites, and
# (V6) its StoreKit 2 module for the Shop's App Store purchases.  One pinned,
# sha256-checked release provides both.
set -euo pipefail
cd "$(dirname "$0")/.."
GAP_BUILD="${GAP_BUILD:-bfade13ff8b6027ede438bac637b5bf93057d404}"
GAP_SHA256="${GAP_SHA256:-2ba567042f58624b200c09eab70ac475b3dfd752466793ed8068df55688bfd3f}"
CACHE=tools/.cache
mkdir -p "$CACHE"
ZIP="$CACHE/GodotApplePlugins-addons-$GAP_BUILD.zip"
if [ ! -f "$ZIP" ]; then
  curl -fsSL --retry 3 -o "$ZIP" "https://github.com/migueldeicaza/GodotApplePlugins/releases/download/build-$GAP_BUILD/GodotApplePlugins-addons-$GAP_BUILD.zip"
fi
echo "$GAP_SHA256  $ZIP" | shasum -a 256 -c -
rm -rf "$CACHE/gap" && mkdir -p "$CACHE/gap"
unzip -q "$ZIP" -d "$CACHE/gap"
mkdir -p game/addons
for d in GodotApplePluginsGameCenter GodotApplePluginsStoreKit GodotApplePluginsRuntime; do
  rm -rf "game/addons/$d"
  cp -R "$CACHE/gap/dist/addons/$d" "game/addons/$d"
done
echo "GodotApplePlugins $GAP_BUILD installed into game/addons/"
