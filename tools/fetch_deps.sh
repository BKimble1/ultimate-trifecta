#!/usr/bin/env bash
# Fetches pinned third-party binaries (not committed) into game/addons/.
# GodotApplePlugins (MIT) — Game Center bindings used for iOS rooms/invites, and
# (V6) its StoreKit 2 module for the Shop's App Store purchases.  One pinned
# build provides both.
#
# 2.2: upstream deleted its "build-<sha>" releases (and their tags) after
# 2.1, so the pinned asset now answers 404.  The pinned *commit* still
# exists, so on macOS this falls back to building exactly that commit from
# source with upstream's own release recipe (.github/workflows/
# build-and-release.yml at that commit: two `make split-build` passes,
# `make split-dist`, unsigned).  The source is verified by its commit hash;
# the release zip, when it can still be downloaded or is cached, by its
# sha256 as before.  CI caches the built zip (key: the commit).
set -euo pipefail
cd "$(dirname "$0")/.."
GAP_BUILD="${GAP_BUILD:-bfade13ff8b6027ede438bac637b5bf93057d404}"
GAP_SHA256="${GAP_SHA256:-2ba567042f58624b200c09eab70ac475b3dfd752466793ed8068df55688bfd3f}"
GAP_REPO="https://github.com/migueldeicaza/GodotApplePlugins"
CACHE=tools/.cache
mkdir -p "$CACHE"
ZIP="$CACHE/GodotApplePlugins-addons-$GAP_BUILD.zip"
SRC_ZIP="$CACHE/GodotApplePlugins-addons-$GAP_BUILD-src.zip"

build_from_source() {
  local src="$CACHE/gap-src"
  rm -rf "$src"
  git init -q "$src"
  git -C "$src" remote add origin "$GAP_REPO"
  git -C "$src" fetch -q --depth 1 origin "$GAP_BUILD"
  git -C "$src" checkout -q FETCH_HEAD
  test "$(git -C "$src" rev-parse HEAD)" = "$GAP_BUILD"
  echo "Building GodotApplePlugins $GAP_BUILD from source (upstream release recipe, unsigned)"
  (
    cd "$src"
    # SwiftGodot ships a Swift macro: Xcode refuses an un-trusted macro or
    # package plugin unless told to skip the check (upstream's own Mac had
    # them trusted).  The defaults are written only on a throwaway CI runner.
    if [ -n "${CI:-}" ]; then
      defaults write com.apple.dt.Xcode IDESkipMacroFingerprintValidation -bool YES
      defaults write com.apple.dt.Xcode IDESkipPackagePluginFingerprintValidatation -bool YES
    fi
    export XCODEBUILD_SETTINGS="-skipMacroValidation -skipPackagePluginValidation CODE_SIGNING_ALLOWED=NO OTHER_LDFLAGS=-Wl,-headerpad_max_install_names"
    export XCODEBUILD_LOG_ON_ERROR=1
    make split-build DESTINATIONS="generic/platform=iOS generic/platform=iOS\ Simulator platform=macOS,arch=arm64"
    make split-build DESTINATIONS="platform=macOS,arch=x86_64"
    make split-dist
    rm -rf dist && mkdir -p dist/addons
    for a in GodotApplePluginsGameCenter GodotApplePluginsStoreKit GodotApplePluginsRuntime; do
      test -d "addons/$a"
      ditto "addons/$a" "dist/addons/$a"
    done
    ditto -c -k --sequesterRsrc --keepParent dist "$OLDPWD/$SRC_ZIP"
  )
  rm -rf "$src"
}

use=""
if [ -f "$ZIP" ] || curl -fsSL --retry 3 -o "$ZIP" "$GAP_REPO/releases/download/build-$GAP_BUILD/GodotApplePlugins-addons-$GAP_BUILD.zip"; then
  echo "$GAP_SHA256  $ZIP" | shasum -a 256 -c -
  use="$ZIP"
else
  rm -f "$ZIP"
  echo "The pinned GodotApplePlugins release asset is gone upstream (build-$GAP_BUILD)."
  if [ ! -f "$SRC_ZIP" ]; then
    if [ "$(uname -s)" != Darwin ]; then
      echo "Building it from source needs macOS with Xcode." >&2
      exit 1
    fi
    build_from_source
  else
    echo "Using the cached source build $SRC_ZIP"
  fi
  use="$SRC_ZIP"
fi
rm -rf "$CACHE/gap" && mkdir -p "$CACHE/gap"
unzip -q "$use" -d "$CACHE/gap"
mkdir -p game/addons
for d in GodotApplePluginsGameCenter GodotApplePluginsStoreKit GodotApplePluginsRuntime; do
  rm -rf "game/addons/$d"
  cp -R "$CACHE/gap/dist/addons/$d" "game/addons/$d"
done
echo "GodotApplePlugins $GAP_BUILD installed into game/addons/ (from $(basename "$use"))"
