class_name StoreKitAdapter
extends StoreAdapter
## StoreKit 2 on iOS through the pinned GodotApplePlugins StoreKit module
## (tools/fetch_deps.sh: the same sha256-checked release as Game Center;
## MIT).  Its StoreKitManager listens to Transaction.updates, replays
## Transaction.unfinished at start(), emits only verified transactions on
## `transaction_updated` (unverified ones separately) and never finishes a
## transaction itself: we finish it after the service has durably delivered.
##
## Classes are reached by name (ClassDB), so this script also parses where
## the module isn't installed; it is only used on iOS.

var mgr: Object
var _products: Dictionary = {}     # product_id -> StoreProduct


func _init() -> void:
	if not ClassDB.class_exists("StoreKitManager") or OS.get_name() != "iOS":
		return
	mgr = ClassDB.instantiate("StoreKitManager")
	if mgr == null:
		return
	mgr.connect("products_request_completed", _on_products)
	mgr.connect("purchase_completed", _on_purchase)
	mgr.connect("transaction_updated", _on_transaction)
	mgr.connect("unverified_transaction_updated", _on_unverified)
	mgr.connect("restore_completed", _on_restore)


func available() -> bool:
	return mgr != null


func adapter_name() -> String:
	return "storekit2" if mgr != null else "none"


func start() -> void:
	if mgr:
		mgr.call("start")


func request_products(ids: PackedStringArray) -> void:
	if mgr == null:
		super(ids)
		return
	mgr.call("request_products", ids)


func purchase(product_id: String, app_account_token: String) -> void:
	var p: Object = _products.get(product_id)
	if mgr == null or p == null:
		purchase_result.emit.call_deferred({}, Status.INVALID_PRODUCT, "This item isn't available right now.")
		return
	# the purchase is bound to the player's game account (appAccountToken, a
	# UUID the service issued); the service checks it before delivering Coins
	var opts := Array([], TYPE_OBJECT, &"StoreProductPurchaseOption", null)
	if app_account_token != "":
		var o: Object = ClassDB.class_call_static(&"StoreProductPurchaseOption", &"app_account_token", app_account_token)
		if o != null:
			opts.append(o)
	mgr.call("purchase_with_options", p, opts)


func restore() -> void:
	if mgr:
		mgr.call("restore_purchases")
	else:
		super()


func fetch_entitlements() -> void:
	if mgr:
		mgr.call("fetch_current_entitlements")


func fetch_unfinished() -> void:
	if mgr:
		mgr.call("fetch_unfinished_transactions")


func finish(tx: Dictionary) -> void:
	var h: Variant = tx.get("handle")
	if h is Object and is_instance_valid(h):
		(h as Object).call("finish")


static func to_dict(t: Object) -> Dictionary:
	if t == null:
		return {}
	return {
		"transaction_id": str(t.get("transaction_id")), "original_id": str(t.get("original_id")),
		"product_id": String(t.get("product_id")), "jws": String(t.get("jws_representation")),
		"purchase_date": float(t.get("purchase_date")), "revocation_date": float(t.get("revocation_date")),
		"ownership_type": String(t.get("ownership_type")), "handle": t,
	}


func _on_products(products: Array, status: int) -> void:
	var out: Array = []
	for p in products:
		if p == null:
			continue
		var o := p as Object
		var pid := String(o.get("product_id"))
		_products[pid] = o
		out.append({"product_id": pid, "display_name": String(o.get("display_name")),
			"display_price": String(o.get("display_price")), "description": String(o.get("description_value")),
			"price": float(o.get("price")) if o.get("price") != null else 0.0})
	products_loaded.emit(out, status == Status.OK)


func _on_purchase(t: Object, status: int, message: String) -> void:
	purchase_result.emit(to_dict(t), status, message)


func _on_transaction(t: Object) -> void:
	if t != null:
		transaction.emit(to_dict(t))


func _on_unverified(t: Object, code: int) -> void:
	unverified.emit(to_dict(t), code)


func _on_restore(status: int, message: String) -> void:
	restore_done.emit(status == Status.OK, message)
