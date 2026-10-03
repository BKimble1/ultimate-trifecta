#!/usr/bin/env python3
"""Writes native/storekit/UltimateTrifecta.storekit (Xcode's local StoreKit
testing configuration) from game/config/catalogue.json.

For local testing in Xcode only (Scheme > Run > Options > StoreKit
Configuration): Xcode-signed transactions are never accepted by the game
service (it trusts only Apple's App Store certificate chain), so this file
can't grant anything outside a local test.  The prices below are local test
values required by the file format, not the App Store price: the game always
shows StoreKit's localized price, set by the account holder in App Store
Connect.  The tool is deterministic (stable IDs), so re-running it changes
nothing unless the catalogue did.
"""
import json, os, uuid

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
CAT = json.load(open(os.path.join(ROOT, "game", "config", "catalogue.json")))
NS = uuid.UUID("6f1d3b1e-7c1a-4a9e-9a55-1d6c2b7e0f42")
TEST_PRICE = {"CONSUMABLE": "0.99", "NON_CONSUMABLE": "1.99"}

products = []
for pid, p in sorted(CAT["products"].items()):
    if p["kind"] == "coin_pack":
        name = "{:,} Coins".format(p["coins"])
        desc = "{:,} Coins for the Shop. Cosmetic only.".format(p["coins"])
    else:
        name = p["reference_name"].replace("Skin ", "")
        desc = "A permanent outfit. Cosmetic only."
    products.append({
        "displayPrice": TEST_PRICE[p["apple_type"]],
        "familyShareable": False,
        "internalID": str(uuid.uuid5(NS, pid)).upper()[:8],
        "localizations": [{"description": desc, "displayName": name, "locale": "en_US"}],
        "productID": pid,
        "referenceName": p["reference_name"] + " (local test)",
        "type": "Consumable" if p["apple_type"] == "CONSUMABLE" else "NonConsumable",
    })
out = {
    "identifier": str(uuid.uuid5(NS, "config")).upper(),
    "nonRenewingSubscriptions": [],
    "products": products,
    "settings": {"_applicationInternalID": "6818346960", "_developerTeamID": "", "_failTransactionsEnabled": False,
                 "_locale": "en_US", "_storefront": "USA", "_storeKitErrors": []},
    "subscriptionGroups": [],
    "version": {"major": 4, "minor": 0},
}
path = os.path.join(ROOT, "native", "storekit", "UltimateTrifecta.storekit")
with open(path, "w") as f:
    json.dump(out, f, indent=2)
    f.write("\n")
print("wrote", os.path.relpath(path, ROOT), "with", len(products), "products")
