#!/usr/bin/env bash
# Builds the UTShare GDExtension (native/ut_share) into game/addons/ut_share/bin/.
#   Linux:  libut_share.linux.<arch>.so   (stub: share() returns false; used by tests)
#   macOS:  libut_share.macos.dylib       (stub) and, with Xcode, UTShare.xcframework
#           (iOS device arm64 + simulator arm64/x86_64 dynamic frameworks)
# gdextension_interface.h is dumped from the pinned Godot binary so the binding
# always matches the engine that runs it.
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT=$(pwd)
SRC=native/ut_share/src
OUT=game/addons/ut_share/bin
BUILD=native/ut_share/build
MIN_IOS=17.0
mkdir -p "$OUT" "$BUILD/include"

if [ ! -s "$BUILD/include/gdextension_interface.h" ]; then
  if [ -n "${GODOT_BIN:-}" ]; then GODOT="$GODOT_BIN"
  elif [ -s tools/.cache/godot/BIN ]; then GODOT=$(cat tools/.cache/godot/BIN)
  else GODOT="$ROOT/tools/gd.sh"; fi
  (cd "$BUILD/include" && "$GODOT" --headless --dump-gdextension-interface >/dev/null 2>&1 || true)
  test -s "$BUILD/include/gdextension_interface.h" || { echo "could not dump gdextension_interface.h with $GODOT" >&2; exit 1; }
fi
INC=(-I "$BUILD/include" -I "$SRC")
CFLAGS=(-std=c11 -O2 -Wall -Wextra -fvisibility=hidden)
[ "$(uname -s)" = Linux ] && CFLAGS+=(-Werror)  # verified warning-free with gcc

case "$(uname -s)" in
  Linux)
    ARCH=$(uname -m); [ "$ARCH" = aarch64 ] && ARCH=arm64
    ${CC:-cc} "${CFLAGS[@]}" "${INC[@]}" -fPIC -shared -o "$OUT/libut_share.linux.$ARCH.so" \
      "$SRC/ut_share.c" "$SRC/ut_share_stub.c"
    echo "built $OUT/libut_share.linux.$ARCH.so"
    ;;
  Darwin)
    clang "${CFLAGS[@]}" "${INC[@]}" -arch arm64 -arch x86_64 -mmacosx-version-min=11.0 -dynamiclib \
      -install_name @rpath/libut_share.macos.dylib -o "$OUT/libut_share.macos.dylib" \
      "$SRC/ut_share.c" "$SRC/ut_share_stub.c"
    echo "built $OUT/libut_share.macos.dylib"
    if ! xcrun --sdk iphoneos --show-sdk-path >/dev/null 2>&1; then
      echo "no iOS SDK: skipping UTShare.xcframework"; exit 0
    fi
    framework() {  # $1 = sdk, $2 = platform name for Info.plist, rest = clang -target values
      local sdk=$1 plat=$2; shift 2
      local dir="$BUILD/$sdk/UTShare.framework"
      rm -rf "$dir" && mkdir -p "$dir"
      local slices=()
      for target in "$@"; do
        xcrun --sdk "$sdk" clang "${CFLAGS[@]}" "${INC[@]}" -target "$target" -fobjc-arc -dynamiclib \
          -install_name @rpath/UTShare.framework/UTShare -framework UIKit -framework CoreGraphics -framework Foundation \
          -o "$BUILD/$sdk/UTShare-$target" "$SRC/ut_share.c" "$SRC/ut_share_ios.m"
        slices+=("$BUILD/$sdk/UTShare-$target")
      done
      lipo -create "${slices[@]}" -output "$dir/UTShare"
      cat > "$dir/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleDevelopmentRegion</key><string>en</string>
  <key>CFBundleExecutable</key><string>UTShare</string>
  <key>CFBundleIdentifier</key><string>com.idlery.ultimatetrifecta.utshare</string>
  <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
  <key>CFBundleName</key><string>UTShare</string>
  <key>CFBundlePackageType</key><string>FMWK</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>CFBundleSupportedPlatforms</key><array><string>$plat</string></array>
  <key>MinimumOSVersion</key><string>$MIN_IOS</string>
</dict></plist>
PLIST
      plutil -lint "$dir/Info.plist" >/dev/null
    }
    framework iphoneos iPhoneOS "arm64-apple-ios$MIN_IOS"
    framework iphonesimulator iPhoneSimulator "arm64-apple-ios$MIN_IOS-simulator" "x86_64-apple-ios$MIN_IOS-simulator"
    rm -rf "$OUT/UTShare.xcframework"
    xcodebuild -create-xcframework \
      -framework "$BUILD/iphoneos/UTShare.framework" \
      -framework "$BUILD/iphonesimulator/UTShare.framework" \
      -output "$OUT/UTShare.xcframework" >/dev/null
    lipo -info "$OUT/UTShare.xcframework"/*/UTShare.framework/UTShare
    nm -gU "$OUT/UTShare.xcframework/ios-arm64/UTShare.framework/UTShare" | grep ut_share_init
    echo "built $OUT/UTShare.xcframework"
    ;;
  *) echo "unsupported host $(uname -s)"; exit 2;;
esac
