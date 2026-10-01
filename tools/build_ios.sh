#!/usr/bin/env bash
# Builds the exported Xcode project (macOS + Xcode 26 required).
#   tools/build_ios.sh sim            -> simulator .app (no signing)
#   tools/build_ios.sh device         -> unsigned device archive (compile proof)
#   tools/build_ios.sh signed         -> signed App Store archive + .ipa export
# Signed builds need: APPLE_TEAM_ID, ASC_KEY_ID, ASC_ISSUER_ID, ASC_KEY_PATH (AuthKey .p8)
set -euo pipefail
cd "$(dirname "$0")/.."
MODE="${1:-sim}"
PROJ=build/ios/UltimateTrifecta.xcodeproj
SCHEME=$(xcodebuild -list -project "$PROJ" -json | python3 -c 'import json,sys; print(json.load(sys.stdin)["project"]["schemes"][0])')
echo "scheme: $SCHEME"
case "$MODE" in
  sim)
    # Godot 4.7.2's official iOS templates ship an x86_64-only simulator slice,
    # so the simulator build targets x86_64 (runs under Rosetta on Apple silicon).
    xcodebuild -project "$PROJ" -scheme "$SCHEME" -configuration Release -sdk iphonesimulator \
      -destination 'generic/platform=iOS Simulator' -derivedDataPath build/ios/dd-sim \
      ARCHS=x86_64 EXCLUDED_ARCHS=arm64 ONLY_ACTIVE_ARCH=NO CODE_SIGNING_ALLOWED=NO build | tail -n 40
    find build/ios/dd-sim -name '*.app' -maxdepth 6 | head -1
    ;;
  device)
    xcodebuild -project "$PROJ" -scheme "$SCHEME" -configuration Release -sdk iphoneos \
      -destination 'generic/platform=iOS' -archivePath build/ios/UltimateTrifecta-unsigned.xcarchive \
      CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" archive | tail -n 40
    ;;
  signed)
    : "${APPLE_TEAM_ID:?}" "${ASC_KEY_ID:?}" "${ASC_ISSUER_ID:?}" "${ASC_KEY_PATH:?}"
    AUTH=(-allowProvisioningUpdates -authenticationKeyPath "$ASC_KEY_PATH" -authenticationKeyID "$ASC_KEY_ID" -authenticationKeyIssuerID "$ASC_ISSUER_ID")
    xcodebuild -project "$PROJ" -scheme "$SCHEME" -configuration Release -sdk iphoneos \
      -destination 'generic/platform=iOS' -archivePath build/ios/UltimateTrifecta.xcarchive \
      DEVELOPMENT_TEAM="$APPLE_TEAM_ID" CODE_SIGN_STYLE=Automatic "${AUTH[@]}" archive | tail -n 60
    cat > build/ios/ExportOptions.plist <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>method</key><string>app-store-connect</string>
  <key>destination</key><string>${EXPORT_DESTINATION:-export}</string>
  <key>teamID</key><string>${APPLE_TEAM_ID}</string>
  <key>signingStyle</key><string>automatic</string>
  <key>uploadSymbols</key><true/>
  <key>manageAppVersionAndBuildNumber</key><false/>
  <key>testFlightInternalTestingOnly</key><${INTERNAL_ONLY:-true}/>
</dict></plist>
PLIST
    xcodebuild -exportArchive -archivePath build/ios/UltimateTrifecta.xcarchive \
      -exportOptionsPlist build/ios/ExportOptions.plist -exportPath build/ios/export "${AUTH[@]}" | tail -n 40
    ls -la build/ios/export || true
    ;;
  *) echo "unknown mode $MODE"; exit 2;;
esac
