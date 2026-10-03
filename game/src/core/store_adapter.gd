class_name StoreAdapter
extends RefCounted
## The App Store as the purchase service sees it (V6).  This base class is
## the "no store" adapter (desktop, tests without a store): nothing is
## available and nothing can be bought.  StoreKitAdapter talks to Apple's
## StoreKit 2 through the pinned GodotApplePlugins StoreKit module; the test
## adapter (src/dev/test_store_adapter.gd, never exported) simulates it.
##
## Transactions are passed around as dictionaries:
##   {transaction_id, original_id, product_id, jws, purchase_date,
##    revocation_date, ownership_type, handle}
## `handle` is the native object finish() needs.  The JWS is the signed
## transaction the service verifies; it is never logged.

signal products_loaded(products: Array, ok: bool)   # [{product_id, display_name, display_price, description}]
signal purchase_result(tx: Dictionary, status: int, message: String)
signal transaction(tx: Dictionary)                   # verified: deliver, then finish
signal unverified(tx: Dictionary, code: int)
signal restore_done(ok: bool, message: String)

## StoreKitManager.StoreKitStatus
enum Status { OK, INVALID_PRODUCT, CANCELLED, UNVERIFIED, USER_CANCELLED, PENDING, UNKNOWN }


func available() -> bool:
	return false


func adapter_name() -> String:
	return "none"


## Begin listening for transaction updates and replay unfinished ones.
func start() -> void:
	pass


func request_products(_ids: PackedStringArray) -> void:
	products_loaded.emit.call_deferred([], false)


func purchase(_product_id: String, _app_account_token: String) -> void:
	purchase_result.emit.call_deferred({}, Status.INVALID_PRODUCT, "Purchases aren't available on this device.")


func restore() -> void:
	restore_done.emit.call_deferred(false, "Purchases aren't available on this device.")


## Current non-consumable entitlements arrive through `transaction`.
func fetch_entitlements() -> void:
	pass


## Unfinished transactions arrive through `transaction`.
func fetch_unfinished() -> void:
	pass


func finish(_tx: Dictionary) -> void:
	pass
