#!/usr/bin/env python3
"""App Store Connect API helper for the Ultimate Trifecta TestFlight lane.

Auth: an App Store Connect API key (Team key, App Manager or Admin role):
  ASC_KEY_ID, ASC_ISSUER_ID, and ASC_KEY_PATH (path to AuthKey_XXXX.p8)

Commands:
  app            -> print the app record for BUNDLE_ID (exit 3 if missing)
  next-build     -> print max(existing CFBundleVersion for MARKETING_VERSION)+1
  builds         -> list recent builds with processing state
  wait VERSION BUILD [timeout_s] -> poll until the build is VALID (or fails)
  internal BUILD_ID -> add the build to every existing internal beta group
  beta BUILD_ID  -> print the build's TestFlight states (internal/external)
  ensure-bundle  -> register BUNDLE_ID with Game Center if missing (Xcode
                    automatic signing can also do this)
Never prints the key. Requires: pip install pyjwt cryptography requests
"""
import json, os, sys, time

import jwt
import requests

API = "https://api.appstoreconnect.apple.com/v1"
BUNDLE_ID = os.environ.get("BUNDLE_ID", "com.idlery.ultimatetrifecta")


def token():
    key = open(os.environ["ASC_KEY_PATH"]).read()
    now = int(time.time())
    return jwt.encode({"iss": os.environ["ASC_ISSUER_ID"], "iat": now, "exp": now + 1100, "aud": "appstoreconnect-v1"},
                      key, algorithm="ES256", headers={"kid": os.environ["ASC_KEY_ID"], "typ": "JWT"})


def call(method, path, **kw):
    r = requests.request(method, API + path if path.startswith("/") else path,
                         headers={"Authorization": "Bearer " + token(), "Content-Type": "application/json"}, timeout=60, **kw)
    if r.status_code >= 400:
        sys.stderr.write(f"ASC {method} {path} -> {r.status_code}: {r.text[:800]}\n")
    return r


def app():
    r = call("GET", "/apps", params={"filter[bundleId]": BUNDLE_ID, "fields[apps]": "name,bundleId,sku,primaryLocale"})
    data = r.json().get("data", []) if r.ok else []
    return data[0] if data else None


def builds(app_id, limit=20):
    r = call("GET", "/builds", params={"filter[app]": app_id, "sort": "-uploadedDate", "limit": limit,
                                       "include": "preReleaseVersion",
                                       "fields[builds]": "version,processingState,uploadedDate,expired,usesNonExemptEncryption,buildAudienceType",
                                       "fields[preReleaseVersions]": "version"})
    if not r.ok:
        return []
    out = []
    pre = {i["id"]: i["attributes"]["version"] for i in r.json().get("included", []) if i["type"] == "preReleaseVersions"}
    for b in r.json().get("data", []):
        a = b["attributes"]
        rel = b.get("relationships", {}).get("preReleaseVersion", {}).get("data") or {}
        out.append({"id": b["id"], "build": a.get("version"), "marketing": pre.get(rel.get("id"), "?"),
                    "state": a.get("processingState"), "uploaded": a.get("uploadedDate"), "audience": a.get("buildAudienceType"),
                    "encryption": a.get("usesNonExemptEncryption")})
    return out


def main():
    cmd = sys.argv[1] if len(sys.argv) > 1 else "app"
    if cmd == "ensure-bundle":
        r = call("GET", "/bundleIds", params={"filter[identifier]": BUNDLE_ID})
        if r.ok and r.json().get("data"):
            print("bundle id exists:", r.json()["data"][0]["id"])
            return 0
        body = {"data": {"type": "bundleIds", "attributes": {"identifier": BUNDLE_ID, "name": "Ultimate Trifecta", "platform": "IOS"}}}
        r = call("POST", "/bundleIds", data=json.dumps(body))
        if not r.ok:
            return 1
        bid = r.json()["data"]["id"]
        cap = {"data": {"type": "bundleIdCapabilities", "attributes": {"capabilityType": "GAME_CENTER"},
                        "relationships": {"bundleId": {"data": {"type": "bundleIds", "id": bid}}}}}
        call("POST", "/bundleIdCapabilities", data=json.dumps(cap))
        print("registered bundle id", bid)
        return 0
    a = app()
    if cmd == "app":
        if not a:
            print(f"NO_APP_RECORD for {BUNDLE_ID}: create it in App Store Connect (My Apps > + > New App).")
            return 3
        print(json.dumps({"id": a["id"], **a["attributes"]}))
        return 0
    if not a:
        print(f"NO_APP_RECORD for {BUNDLE_ID}")
        return 3
    if cmd == "builds":
        print(json.dumps(builds(a["id"]), indent=2))
        return 0
    if cmd == "next-build":
        marketing = os.environ.get("MARKETING_VERSION", "1.0")
        nums = [int(b["build"]) for b in builds(a["id"], 50) if str(b["build"]).isdigit()]
        print(max(nums + [0]) + 1)
        return 0
    if cmd == "wait":
        ver, bn = sys.argv[2], sys.argv[3]
        limit = int(sys.argv[4]) if len(sys.argv) > 4 else 1800
        t0 = time.time()
        last = None
        while time.time() - t0 < limit:
            for b in builds(a["id"]):
                if str(b["build"]) == str(bn) and b["marketing"] in (ver, "?"):
                    if b["state"] != last:
                        print(json.dumps(b))
                        last = b["state"]
                    if b["state"] in ("VALID", "FAILED", "INVALID"):
                        return 0 if b["state"] == "VALID" else 4
            time.sleep(30)
        print(f"STILL_PROCESSING after {limit}s (last state: {last})")
        return 5
    if cmd == "internal":
        build_id = sys.argv[2]
        r = call("GET", "/betaGroups", params={"filter[app]": a["id"], "filter[isInternalGroup]": "true"})
        groups = r.json().get("data", []) if r.ok else []
        for g in groups:
            name = g["attributes"].get("name")
            if g["attributes"].get("hasAccessToAllBuilds"):
                print("internal group %r gets every build automatically" % name)
                continue
            rr = call("POST", f"/betaGroups/{g['id']}/relationships/builds", data=json.dumps({"data": [{"type": "builds", "id": build_id}]}))
            print(("added to internal group %r" if rr.ok else "could not add to internal group %r (HTTP %d)") % ((name,) if rr.ok else (name, rr.status_code)))
        if not groups:
            print("No internal beta group yet: in App Store Connect > TestFlight > Internal Testing, create a group with your account.")
        return 0
    if cmd == "beta":
        # TestFlight availability as App Store Connect reports it
        r = call("GET", f"/builds/{sys.argv[2]}/buildBetaDetail")
        if not r.ok:
            return 1
        a = r.json()["data"]["attributes"]
        print(json.dumps({"internalBuildState": a.get("internalBuildState"), "externalBuildState": a.get("externalBuildState"),
                          "autoNotifyEnabled": a.get("autoNotifyEnabled")}))
        return 0
    print(__doc__)
    return 2


if __name__ == "__main__":
    sys.exit(main())
