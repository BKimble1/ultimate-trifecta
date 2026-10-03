#!/usr/bin/env bash
# Exports the Godot project as an Xcode project into build/ios/.
# Env: APPLE_TEAM_ID (required for signed builds; a placeholder is used for
#      unsigned CI builds), BUILD_NUMBER (CFBundleVersion), MARKETING_VERSION.
set -euo pipefail
cd "$(dirname "$0")/.."
GODOT="${GODOT_BIN:-$(cat tools/.cache/godot/BIN)}"
TEAM="${APPLE_TEAM_ID:-TEAMID0000}"
BUILD="${BUILD_NUMBER:-1}"
VERSION="${MARKETING_VERSION:-1.4}"
{ [ -d game/addons/GodotApplePluginsGameCenter ] && [ -d game/addons/GodotApplePluginsStoreKit ]; } || tools/fetch_deps.sh
# stamp identity into a temporary copy of the preset (the committed file keeps placeholders)
cp game/export_presets.cfg build_export_presets.bak
trap 'mv build_export_presets.bak game/export_presets.cfg' EXIT
sed -i.tmp -e "s/^application\/app_store_team_id=.*/application\/app_store_team_id=\"$TEAM\"/" \
  -e "s/^application\/version=.*/application\/version=\"$BUILD\"/" \
  -e "s/^application\/short_version=.*/application\/short_version=\"$VERSION\"/" game/export_presets.cfg
rm -f game/export_presets.cfg.tmp
# Signed builds use Xcode automatic signing. With an empty identity Godot
# writes "Apple Distribution" into the Release configuration, and Xcode
# refuses a manually chosen identity under automatic signing ("conflicting
# provisioning settings"). Archive with the development identity; the App
# Store Connect export re-signs for distribution.
if [ -n "${APPLE_TEAM_ID:-}" ]; then
  sed -i.tmp -e 's/^application\/code_sign_identity_release=.*/application\/code_sign_identity_release="Apple Development"/' \
    -e 's/^application\/code_sign_identity_debug=.*/application\/code_sign_identity_debug="Apple Development"/' game/export_presets.cfg
  rm -f game/export_presets.cfg.tmp
fi
# With the game service configured, the app collects a user ID (Game Center
# team player ID, verified server-side), the player name, the runner's look
# (gameplay content) and reports (other user content), linked to the player,
# for app functionality only, never tracking. Declare exactly that in the
# privacy manifest; without the service nothing is collected and nothing is
# declared.
SERVICE_URL=$(sed -n 's/^url *= *"\(.*\)"/\1/p' game/config/service.cfg 2>/dev/null | head -1)
if [ -n "$SERVICE_URL" ]; then
  PRIV=""
  for d in user_id name gameplay_content other_user_content; do
    PRIV+="privacy/collected_data/$d/collected=true\nprivacy/collected_data/$d/linked_to_user=true\nprivacy/collected_data/$d/used_for_tracking=false\nprivacy/collected_data/$d/collection_purposes=2\n"
  done
  python3 - "$PRIV" <<'PY'
import sys
p = "game/export_presets.cfg"
s = open(p).read()
anchor = "privacy/tracking_domains=PackedStringArray()\n"
assert anchor in s
s = s.replace(anchor, anchor + sys.argv[1].replace("\\n", "\n"), 1)
open(p, "w").write(s)
PY
  echo "Privacy manifest: declaring service data (user ID, name, gameplay content, reports) for app functionality"
  # V6: the service keeps purchases (App Store transaction IDs and what they
  # delivered, never payment details) to deliver them once and restore them
  python3 - <<'PY2'
p = "game/export_presets.cfg"
s = open(p).read()
anchor = "privacy/tracking_domains=PackedStringArray()\n"
add = "".join("privacy/collected_data/purchase_history/%s\n" % kv for kv in ["collected=true", "linked_to_user=true", "used_for_tracking=false", "collection_purposes=2"])
s = s.replace(anchor, anchor + add, 1)
open(p, "w").write(s)
PY2
  echo "Privacy manifest: declaring purchase history (App Store purchases, app functionality)"
fi
rm -rf build/ios && mkdir -p build/ios
"$GODOT" --headless --path game --import >/dev/null 2>&1 || true
# V6: SHADER_BAKE=1 on macOS bakes the game's Metal shaders into the export
# (Godot's shader baker), so a phone doesn't compile them from source the
# first time each material is drawn.  The baker needs the editor running the
# target's renderer (Mobile on Metal) - it can't bake in --headless mode or
# for Metal on Linux - so this export runs with a real rendering device.  If
# that export fails, the ordinary headless export (no baked shaders) is used.
BAKED=0
BAKE_RC=""
if [ "${SHADER_BAKE:-0}" = 1 ] && [ "$(uname -s)" = Darwin ]; then
  sed -i.tmp -e 's/^shader_baker\/enabled=.*/shader_baker\/enabled=true/' game/export_presets.cfg
  rm -f game/export_presets.cfg.tmp
  BAKE_RC=0
  python3 -c 'import subprocess,sys; sys.exit(subprocess.run(sys.argv[1:], timeout=1200).returncode)' \
      "$GODOT" --path game --rendering-method mobile --rendering-driver metal --export-release "iOS" ../build/ios/UltimateTrifecta.xcodeproj \
      > build/ios/export.log 2>&1 || BAKE_RC=$?
  sed -i.tmp -e 's/^shader_baker\/enabled=.*/shader_baker\/enabled=false/' game/export_presets.cfg
  rm -f game/export_presets.cfg.tmp
  # Judged by what it produced, not only the exit code: on the CI runner the
  # editor has crashed while quitting after a finished export (run #63).
  # Kept when the project and its game data exist and the data carries
  # baked shaders; the simulator run below then plays exactly this build.
  BPCK=$(find build/ios -maxdepth 1 -name '*.pck' | head -1)
  BN=$( { [ -n "$BPCK" ] && strings -n 8 "$BPCK" 2>/dev/null | grep -c "shader_cache" ; } || true)
  echo "shader-baking export: exit code $BAKE_RC · game data ${BPCK:-missing} · shader_cache entries ${BN:-0}"
  grep -iE "shader|bake|export|error|crash|signal" build/ios/export.log | grep -v "already has constant\|bind_integer_constant" | head -40 || true
  if [ -d build/ios/UltimateTrifecta.xcodeproj ] && [ -n "$BPCK" ] && [ "${BN:-0}" -gt 0 ]; then
    BAKED=1
  else
    echo "shader-baking export unusable; falling back to the headless export without baked shaders"
    tail -40 build/ios/export.log || true
    rm -rf build/ios/UltimateTrifecta* build/ios/*.pck && mkdir -p build/ios
  fi
fi
if [ "$BAKED" = 0 ]; then
  "$GODOT" --headless --path game --export-release "iOS" ../build/ios/UltimateTrifecta.xcodeproj 2>&1 | tee build/ios/export.log
fi
test -d build/ios/UltimateTrifecta.xcodeproj
# what actually went into the game data (evidence, not an assumption)
PCK=$(find build/ios -maxdepth 1 -name '*.pck' | head -1)
N=$( { strings -n 8 "$PCK" 2>/dev/null | grep -c "shader_cache" ; } || true)
{ echo "shader baker requested: ${SHADER_BAKE:-0} · baking export used: $BAKED (its exit code: ${BAKE_RC:-n/a}) · shader_cache entries in the game data: ${N:-0}"
  grep -i "shader baker" build/ios/export.log | head -5 || true; } | tee build/ios/shader_bake.txt
echo "Exported Xcode project: build/ios/UltimateTrifecta.xcodeproj (version $VERSION build $BUILD)"
