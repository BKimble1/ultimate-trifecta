#!/usr/bin/env bash
# Exports the Godot project as an Xcode project into build/ios/.
# Env: APPLE_TEAM_ID (required for signed builds; a placeholder is used for
#      unsigned CI builds), BUILD_NUMBER (CFBundleVersion), MARKETING_VERSION.
set -euo pipefail
cd "$(dirname "$0")/.."
GODOT="${GODOT_BIN:-$(cat tools/.cache/godot/BIN)}"
TEAM="${APPLE_TEAM_ID:-TEAMID0000}"
BUILD="${BUILD_NUMBER:-1}"
VERSION="${MARKETING_VERSION:-1.0}"
[ -d game/addons/GodotApplePluginsGameCenter ] || tools/fetch_deps.sh
# stamp identity into a temporary copy of the preset (the committed file keeps placeholders)
cp game/export_presets.cfg build_export_presets.bak
trap 'mv build_export_presets.bak game/export_presets.cfg' EXIT
sed -i.tmp -e "s/^application\/app_store_team_id=.*/application\/app_store_team_id=\"$TEAM\"/" \
  -e "s/^application\/version=.*/application\/version=\"$BUILD\"/" \
  -e "s/^application\/short_version=.*/application\/short_version=\"$VERSION\"/" game/export_presets.cfg
rm -f game/export_presets.cfg.tmp
rm -rf build/ios && mkdir -p build/ios
"$GODOT" --headless --path game --import >/dev/null 2>&1 || true
"$GODOT" --headless --path game --export-release "iOS" ../build/ios/UltimateTrifecta.xcodeproj 2>&1 | tee build/ios/export.log
test -d build/ios/UltimateTrifecta.xcodeproj
echo "Exported Xcode project: build/ios/UltimateTrifecta.xcodeproj (version $VERSION build $BUILD)"
