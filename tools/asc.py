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
                    and its What to Test text
  whats-new BUILD_ID FILE [LOCALE] -> set the build's TestFlight "What to
                    Test" text (en-US by default) from FILE (max 4000 chars)
  ensure-bundle  -> register BUNDLE_ID with Game Center if missing (Xcode
                    automatic signing can also do this)
  iap-plan       -> (no credentials needed) the in-app purchases the game
                    expects, from game/config/catalogue.json
  iap-list       -> read only: the app's existing in-app purchases, matched
                    against the plan (missing / present / unexpected)
  iap-create --yes -> create the MISSING planned products (type, reference
                    name, product ID, family sharing off, review note) with
                    their en-US display name and description.  It never sets
                    a price, never uploads a review screenshot, never submits
                    anything for review and never changes existing products:
                    the account holder chooses prices in App Store Connect
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
                                       "fields[builds]": "version,processingState,uploadedDate,expired,usesNonExemptEncryption,buildAudienceType,preReleaseVersion",
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


# ---------------------------------------------------------------- in-app purchases (V6)
CATALOGUE = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "game", "config", "catalogue.json")
IAP_TEXT = {
    # en-US display name / description (App Store limits: 30 / 45 characters)
    "coin_pack": ("{n} Coins", "{n} Coins for the Shop. Cosmetic only."),
    "com.idlery.ultimatetrifecta.skin.moonlight_runner": ("Moonlight Runner", "A permanent outfit. Cosmetic only."),
    "com.idlery.ultimatetrifecta.skin.starry_sleeper": ("Starry Sleeper", "A permanent outfit. Cosmetic only."),
}
REVIEW_NOTE = ("Ultimate Trifecta is a cosmetic-only party game. {what} Open Shop (top bar) to see it; "
               "it is delivered by the game's service after StoreKit 2 verification. No gameplay advantage.")


def iap_plan():
    cat = json.load(open(CATALOGUE))
    out = []
    for pid, p in sorted(cat["products"].items()):
        if p["kind"] == "coin_pack":
            n = "{:,}".format(p["coins"])
            name, desc = (t.format(n=n) for t in IAP_TEXT["coin_pack"])
            what = "This consumable adds %s Coins to the player's wallet." % n
        else:
            name, desc = IAP_TEXT[pid]
            what = "This non-consumable unlocks the %s outfit permanently (restorable)." % name
        assert len(name) <= 30 and len(desc) <= 45, pid
        out.append({"productId": pid, "inAppPurchaseType": p["apple_type"], "name": p["reference_name"], "displayName": name,
                    "description": desc, "reviewNote": REVIEW_NOTE.format(what=what)})
    return out


def iap_existing(app_id):
    out, url = [], f"/apps/{app_id}/inAppPurchasesV2"
    params = {"limit": 200, "fields[inAppPurchases]": "name,productId,inAppPurchaseType,state,familySharable"}
    while url:
        r = call("GET", url, params=params)
        if not r.ok:
            return None
        js = r.json()
        out += [{"id": d["id"], **d["attributes"]} for d in js.get("data", [])]
        url = js.get("links", {}).get("next")
        params = None
    return out


def main():
    cmd = sys.argv[1] if len(sys.argv) > 1 else "app"
    if cmd == "iap-plan":
        print(json.dumps(iap_plan(), indent=2))
        return 0
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
        out = {"internalBuildState": a.get("internalBuildState"), "externalBuildState": a.get("externalBuildState"),
               "autoNotifyEnabled": a.get("autoNotifyEnabled")}
        rl = call("GET", f"/builds/{sys.argv[2]}/betaBuildLocalizations")
        if rl.ok:
            out["whatToTest"] = {l["attributes"].get("locale"): (l["attributes"].get("whatsNew") or "")[:80]
                                 for l in rl.json().get("data", [])}
        print(json.dumps(out))
        return 0
    if cmd in ("iap-list", "iap-create"):
        have = iap_existing(a["id"])
        if have is None:
            print("could not read in-app purchases (the API key needs App Manager or Admin)")
            return 1
        plan = iap_plan()
        by_pid = {h["productId"]: h for h in have}
        missing = [p for p in plan if p["productId"] not in by_pid]
        for p in plan:
            h = by_pid.get(p["productId"])
            print("%-52s %-15s %s" % (p["productId"], p["inAppPurchaseType"], ("present, state " + str(h.get("state"))) if h else "MISSING"))
            if h and h.get("inAppPurchaseType") != p["inAppPurchaseType"]:
                print("   ! type mismatch: App Store Connect has %s" % h.get("inAppPurchaseType"))
        planned = {p["productId"] for p in plan}
        for h in have:
            if h["productId"] not in planned:
                print("%-52s %-15s unexpected (not in the catalogue)" % (h["productId"], h.get("inAppPurchaseType")))
        if cmd == "iap-list" or not missing:
            return 0
        if "--yes" not in sys.argv:
            print("%d missing; run again with --yes to create them (no prices, no submission)" % len(missing))
            return 0
        for p in missing:
            body = {"data": {"type": "inAppPurchases", "attributes": {"name": p["name"], "productId": p["productId"],
                    "inAppPurchaseType": p["inAppPurchaseType"], "reviewNote": p["reviewNote"], "familySharable": False},
                    "relationships": {"app": {"data": {"type": "apps", "id": a["id"]}}}}}
            r = call("POST", "https://api.appstoreconnect.apple.com/v2/inAppPurchases", data=json.dumps(body))
            if not r.ok:
                print("could not create %s (HTTP %d)" % (p["productId"], r.status_code))
                return 1
            iid = r.json()["data"]["id"]
            loc = {"data": {"type": "inAppPurchaseLocalizations", "attributes": {"locale": "en-US", "name": p["displayName"],
                   "description": p["description"]}, "relationships": {"inAppPurchaseV2": {"data": {"type": "inAppPurchases", "id": iid}}}}}
            rl = call("POST", "/inAppPurchaseLocalizations", data=json.dumps(loc))
            print("created %s (%s)%s" % (p["productId"], iid, "" if rl.ok else ", localization FAILED (HTTP %d)" % rl.status_code))
        print("Next (account holder, in App Store Connect): set each product's price, add its review screenshot.")
        return 0
    if cmd == "whats-new":
        build_id, path = sys.argv[2], sys.argv[3]
        locale = sys.argv[4] if len(sys.argv) > 4 else "en-US"
        text = open(path, encoding="utf-8").read().strip()
        if len(text) > 4000:
            print(f"What to Test text is {len(text)} characters; App Store Connect allows 4000")
            return 1
        rl = call("GET", f"/builds/{build_id}/betaBuildLocalizations")
        have = [l for l in (rl.json().get("data", []) if rl.ok else []) if l["attributes"].get("locale") == locale]
        if have:
            body = {"data": {"type": "betaBuildLocalizations", "id": have[0]["id"], "attributes": {"whatsNew": text}}}
            r = call("PATCH", f"/betaBuildLocalizations/{have[0]['id']}", data=json.dumps(body))
        else:
            body = {"data": {"type": "betaBuildLocalizations", "attributes": {"locale": locale, "whatsNew": text},
                             "relationships": {"build": {"data": {"type": "builds", "id": build_id}}}}}
            r = call("POST", "/betaBuildLocalizations", data=json.dumps(body))
        print(("What to Test set (%s, %d characters)" % (locale, len(text))) if r.ok else ("could not set What to Test (HTTP %d)" % r.status_code))
        return 0 if r.ok else 1
    print(__doc__)
    return 2


if __name__ == "__main__":
    sys.exit(main())
