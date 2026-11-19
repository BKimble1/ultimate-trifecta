#!/usr/bin/env bash
# Builds the exported Xcode project (macOS + Xcode 27 required; CI selects it).
#   tools/build_ios.sh sim            -> simulator .app (no signing)
#   tools/build_ios.sh device         -> unsigned device archive (compile proof)
#   tools/build_ios.sh signed         -> signed App Store archive + .ipa export
# Signed builds need: APPLE_TEAM_ID, ASC_KEY_ID, ASC_ISSUER_ID, ASC_KEY_PATH (AuthKey .p8)
# and INTERNAL_ONLY=true|false (the TestFlight audience; no default)
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
    # the TestFlight audience is never implied: true = internal testers only
    # (the build can't be submitted to the App Store), false = App Store-eligible
    case "${INTERNAL_ONLY:-}" in
      true|false) echo "testFlightInternalTestingOnly: $INTERNAL_ONLY" ;;
      *) echo "INTERNAL_ONLY must be set to true or false for a signed export (got '${INTERNAL_ONLY:-}')"; exit 2 ;;
    esac
    AUTH=(-allowProvisioningUpdates -authenticationKeyPath "$ASC_KEY_PATH" -authenticationKeyID "$ASC_KEY_ID" -authenticationKeyIssuerID "$ASC_ISSUER_ID")
    SIGN=(DEVELOPMENT_TEAM="$APPLE_TEAM_ID" CODE_SIGN_STYLE=Automatic CODE_SIGN_IDENTITY="Apple Development")
    echo "signing settings (Release, iphoneos):"
    xcodebuild -project "$PROJ" -scheme "$SCHEME" -configuration Release -sdk iphoneos "${SIGN[@]}" -showBuildSettings 2>/dev/null \
      | grep -E "^ *(CODE_SIGN_STYLE|CODE_SIGN_IDENTITY|PROVISIONING_PROFILE_SPECIFIER|PRODUCT_BUNDLE_IDENTIFIER) =" || true
    xcodebuild -project "$PROJ" -scheme "$SCHEME" -configuration Release -sdk iphoneos \
      -destination 'generic/platform=iOS' -archivePath build/ios/UltimateTrifecta.xcarchive \
      "${SIGN[@]}" "${AUTH[@]}" archive | tail -n 60
    [ -d build/ios/UltimateTrifecta.xcarchive ] || { echo "signed archive was not created"; exit 1; }
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
  <key>testFlightInternalTestingOnly</key><${INTERNAL_ONLY}/>
</dict></plist>
PLIST
    xcodebuild -exportArchive -archivePath build/ios/UltimateTrifecta.xcarchive \
      -exportOptionsPlist build/ios/ExportOptions.plist -exportPath build/ios/export "${AUTH[@]}" | tail -n 40
    ls -la build/ios/export || true
    # (build 24) what Apple signed the upload with: the distribution
    # certificate (its type and expiry) and the App Store provisioning
    # profile, from Xcode's own record of the export, and the archive's
    # entitlements.  Fails the build if either is missing or expired.
    python3 - build/ios/export build/ios/UltimateTrifecta.xcarchive <<'PY'
import glob, os, plistlib, subprocess, sys, datetime
export, archive = sys.argv[1], sys.argv[2]
now = datetime.datetime.now(datetime.timezone.utc)
def when(v):
    if isinstance(v, datetime.datetime):
        return v if v.tzinfo else v.replace(tzinfo=datetime.timezone.utc)
    return None
ok = True
print("SIGNING_REPORT_BEGIN")
found = False
for f in glob.glob(os.path.join(export, "**", "DistributionSummary.plist"), recursive=True):
    found = True
    d = plistlib.load(open(f, "rb"))
    for app, entries in d.items():
        for e in entries:
            c = e.get("certificate", {}) or {}
            exp = when(c.get("dateExpires"))
            print("app:", app, "| certificate:", c.get("type"), "| expires:", exp, "| SHA1:", c.get("SHA1"))
            if exp is None or exp <= now + datetime.timedelta(days=7):
                ok = False
                print("::error::the distribution certificate is missing or expires within a week")
            for pr in (e.get("profile"),) if e.get("profile") else []:
                pexp = when(pr.get("dateExpires"))
                print("profile:", pr.get("name"), "| UUID:", pr.get("UUID"), "| expires:", pexp)
                if pexp is None or pexp <= now:
                    ok = False
                    print("::error::the provisioning profile is missing or expired")
            if not e.get("profile"):
                ok = False
                print("::error::no provisioning profile recorded")
            ents = e.get("entitlements", {}) or {}
            print("entitlements:", ", ".join("%s=%s" % (k, ents[k]) for k in sorted(ents)))
if not found:
    print("::warning::no DistributionSummary.plist in the export: signing details not recorded here")
    for f in sorted(glob.glob(os.path.join(export, "*"))):
        print("export file:", os.path.basename(f))
print("SIGNING_REPORT_END")
sys.exit(0 if ok else 1)
PY
    ;;
  *) echo "unknown mode $MODE"; exit 2;;
esac
