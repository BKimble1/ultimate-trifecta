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
[ -d game/addons/GodotApplePluginsGameCenter ] || tools/fetch_deps.sh
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
fi
rm -rf build/ios && mkdir -p build/ios
"$GODOT" --headless --path game --import >/dev/null 2>&1 || true
"$GODOT" --headless --path game --export-release "iOS" ../build/ios/UltimateTrifecta.xcodeproj 2>&1 | tee build/ios/export.log
test -d build/ios/UltimateTrifecta.xcodeproj
echo "Exported Xcode project: build/ios/UltimateTrifecta.xcodeproj (version $VERSION build $BUILD)"
