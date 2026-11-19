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
    python3 - build/ios/export <<'PY'
import glob, os, plistlib, subprocess, sys, datetime, tempfile, zipfile
export = sys.argv[1]
now = datetime.datetime.now(datetime.timezone.utc)
# the expiring legacy "iOS Distribution" certificate (2026-11-26): never the signer
RETIRED = {"7E525A3A505D780FCCE6C7D8ADE21E4A"}
def x509(der):
    out = subprocess.run(["openssl", "x509", "-inform", "DER", "-noout", "-subject", "-enddate", "-serial"],
                         input=der, capture_output=True).stdout.decode()
    f = dict(l.split("=", 1) for l in out.splitlines() if "=" in l)
    end = datetime.datetime.strptime(f.get("notAfter", "").replace(" GMT", ""), "%b %d %H:%M:%S %Y").replace(tzinfo=datetime.timezone.utc) if f.get("notAfter") else None
    return f.get("subject", "").strip(), end, f.get("serial", "").strip().upper()
ok = True
print("SIGNING_REPORT_BEGIN")
# Xcode's record of the export (also written when it uploads directly)
for f in glob.glob(os.path.join(export, "DistributionSummary.plist")):
    d = plistlib.load(open(f, "rb"))
    for app, entries in d.items():
        for e in entries:
            c = e.get("certificate") or {}
            pr = e.get("profile") or {}
            print("export:", app, "| certificate:", c.get("type"), "| SHA1:", c.get("SHA1"), "| expires:", c.get("dateExpires"))
            print("export: profile", pr.get("name"), "| UUID:", pr.get("UUID"), "| expires:", pr.get("dateExpires"))
            if "Distribution" not in str(c.get("type")) or "Store" not in str(pr.get("name")):
                ok = False
                print("::error::not signed for App Store distribution")
            ents = e.get("entitlements") or {}
            print("entitlements:", ", ".join("%s=%s" % (k, ents[k]) for k in sorted(ents)))
# the signed .ipa (a signing check exports one): the certificate that really
# signed the app, and the App Store profile embedded in it
for ipa in glob.glob(os.path.join(export, "*.ipa")):
    tmp = tempfile.mkdtemp()
    zipfile.ZipFile(ipa).extractall(tmp)
    app = glob.glob(os.path.join(tmp, "Payload", "*.app"))[0]
    subprocess.run(["codesign", "-d", "--extract-certificates=" + os.path.join(tmp, "signer"), app], capture_output=True)
    leaf = os.path.join(tmp, "signer0")
    if not os.path.exists(leaf):
        ok = False
        print("::error::could not read the app's signing certificate")
    else:
        subj, end, serial = x509(open(leaf, "rb").read())
        print("signed by:", subj, "| serial:", serial, "| expires:", end)
        if "Distribution" not in subj or end is None or end <= now + datetime.timedelta(days=30) or serial in RETIRED:
            ok = False
            print("::error::the signing certificate is not a current distribution certificate")
    prov = os.path.join(app, "embedded.mobileprovision")
    if not os.path.exists(prov):
        ok = False
        print("::error::the signed app has no embedded provisioning profile")
        continue
    p = plistlib.loads(subprocess.run(["security", "cms", "-D", "-i", prov], capture_output=True).stdout)
    pexp = p.get("ExpirationDate")
    pexp = pexp.replace(tzinfo=datetime.timezone.utc) if isinstance(pexp, datetime.datetime) and pexp.tzinfo is None else pexp
    store = not p.get("ProvisionedDevices") and not p.get("ProvisionsAllDevices")
    print("embedded profile:", p.get("Name"), "|", "App Store" if store else "NOT App Store", "| expires:", pexp,
          "| get-task-allow:", (p.get("Entitlements") or {}).get("get-task-allow"))
    if not store or not isinstance(pexp, datetime.datetime) or pexp <= now + datetime.timedelta(days=30):
        ok = False
        print("::error::the embedded profile is not a current App Store profile")
    for der in p.get("DeveloperCertificates", []):
        subj, end, serial = x509(der)
        import re
        cn = re.search(r"CN ?= ?([^,/]+)", subj)
        print("profile lists:", cn.group(1).strip() if cn else subj, "| serial:", serial, "| expires:", end)
print("SIGNING_REPORT_END")
sys.exit(0 if ok else 1)
PY
    ;;
  *) echo "unknown mode $MODE"; exit 2;;
esac
