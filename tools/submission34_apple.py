#!/usr/bin/env python3
"""Read-only App Store submission evidence. No mutation endpoints."""
import json, sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parent))
import asc

out = Path("audit34")
out.mkdir(exist_ok=True)
def get(path, **params):
    r = asc.call("GET", path, params=params or None)
    return r.json() if r.ok else {"http_status": r.status_code}
def attrs(obj):
    return (obj.get("data") or {}).get("attributes") or {}
app = asc.app()
if not app:
    raise SystemExit("App record unavailable")
aid = app["id"]
report = {"app_id": aid, "builds": asc.builds(aid, 5)}
detail = get(f"/apps/{aid}", **{"fields[apps]":"contentRightsDeclaration,subscriptionStatusUrl,subscriptionStatusUrlForSandbox"})
report["app"] = attrs(detail)
report["eula"] = get(f"/apps/{aid}/endUserLicenseAgreement")
report["versions"] = []
versions = get(f"/apps/{aid}/appStoreVersions", **{"filter[platform]":"IOS","limit":5})
for v in versions.get("data", []):
    if v["attributes"].get("versionString") != "2.2": continue
    vid = v["id"]
    vr = {"id":vid, "attributes":v["attributes"]}
    vr["build"] = get(f"/appStoreVersions/{vid}/build")
    vr["iap_relationship"] = get(f"/appStoreVersions/{vid}/relationships/inAppPurchases")
    review = get(f"/appStoreVersions/{vid}/appStoreReviewDetail")
    ra = attrs(review)
    vr["review"] = {"notes":ra.get("notes"), "demoAccountRequired":ra.get("demoAccountRequired"),
                    "contact_complete":all(ra.get(k) for k in ["contactFirstName","contactLastName","contactEmail","contactPhone"])}
    vr["localizations"] = []
    for loc in get(f"/appStoreVersions/{vid}/appStoreVersionLocalizations").get("data", []):
        la = dict(loc["attributes"])
        la["id"] = loc["id"]
        la["screenshot_sets"] = []
        for ss in get(f"/appStoreVersionLocalizations/{loc['id']}/appScreenshotSets").get("data",[]):
            sd = {"id":ss["id"], "attributes":ss["attributes"], "shots":[]}
            for shot in get(f"/appScreenshotSets/{ss['id']}/appScreenshots").get("data", []):
                sa = shot["attributes"]
                sd["shots"].append({k:sa.get(k) for k in ["fileName","fileSize","sourceFileChecksum","assetDeliveryState"]})
                sd["shots"][-1]["image_size"] = {k:(sa.get("imageAsset") or {}).get(k) for k in ["width","height"]}
            la["screenshot_sets"].append(sd)
        vr["localizations"].append(la)
    report["versions"].append(vr)
gc = get(f"/apps/{aid}/gameCenterDetail")
report["game_center"] = gc
if gc.get("data"):
    did = gc["data"]["id"]
    report["leaderboards"] = get(f"/gameCenterDetails/{did}/gameCenterLeaderboards", limit=200)
    report["leaderboard_versions"] = []
    for board in report["leaderboards"].get("data", []):
        report["leaderboard_versions"].append({"id":board["id"],"versions":get(f"/gameCenterLeaderboards/{board['id']}/versions")})
report["review_submissions"] = get("/reviewSubmissions", **{"filter[app]":aid,"limit":20})
report["review_items"] = []
for sub in report["review_submissions"].get("data", []):
    report["review_items"].append({"id":sub["id"],"items":get(f"/reviewSubmissions/{sub['id']}/items", limit=200, include="inAppPurchaseVersion,gameCenterLeaderboardVersion,appStoreVersion", **{"fields[reviewSubmissionItems]":"state,inAppPurchaseVersion,gameCenterLeaderboardVersion,appStoreVersion"})})
report["iap_records"] = asc.iap_existing(aid)
(out/"listing-detail.json").write_text(json.dumps(report, indent=2)+"\n")
print("Read-only listing detail saved. Review contact values and credentials excluded.")
