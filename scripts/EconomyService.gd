extends Node

signal state_updated(state: Dictionary)
signal purchase_completed(card_id: String, result: Dictionary)
signal request_failed(kind: String, message: String)

const CACHE_PATH: String = "user://yugito_economy_cache_v2.json"

var state: Dictionary = {}
var catalog_by_id: Dictionary = {}
var busy_state: bool = false
var busy_purchase: bool = false

func _ready() -> void:
    _load_cache()
    _connect_auth_transport()

func _connect_auth_transport() -> void:
    if AuthManager == null:
        return
    if AuthManager.has_signal("economy_state_received") and not AuthManager.is_connected("economy_state_received",Callable(self,"_on_auth_economy_state")):
        AuthManager.connect("economy_state_received",Callable(self,"_on_auth_economy_state"))
    if AuthManager.has_signal("weekly_collection_received") and not AuthManager.is_connected("weekly_collection_received",Callable(self,"_on_auth_weekly")):
        AuthManager.connect("weekly_collection_received",Callable(self,"_on_auth_weekly"))
    if AuthManager.has_signal("economy_purchase_received") and not AuthManager.is_connected("economy_purchase_received",Callable(self,"_on_auth_purchase")):
        AuthManager.connect("economy_purchase_received",Callable(self,"_on_auth_purchase"))
    if AuthManager.has_signal("economy_request_failed") and not AuthManager.is_connected("economy_request_failed",Callable(self,"_on_auth_economy_failed")):
        AuthManager.connect("economy_request_failed",Callable(self,"_on_auth_economy_failed"))

func has_auth_session() -> bool:
    return AuthManager != null and AuthManager.is_session_available()

func yt_balance() -> int:
    return int(state.get("yt_balance",0))

func free_card_ids() -> Array[String]:
    return _string_array(state.get("free_card_ids",[]) as Array)

func owned_card_ids() -> Array[String]:
    return _string_array(state.get("owned_card_ids",[]) as Array)

func base_card_ids() -> Array[String]:
    return _string_array(state.get("base_card_ids",[]) as Array)

func available_card_ids() -> Array[String]:
    return _string_array(state.get("available_card_ids",[]) as Array)

func rotation() -> Dictionary:
    return (state.get("rotation",{}) as Dictionary).duplicate(true)

func card_price(card_id: String, fallback: int = 0) -> int:
    var row: Dictionary = catalog_by_id.get(card_id,{}) as Dictionary
    return int(row.get("price_yt",fallback))

func card_purchasable(card_id: String) -> bool:
    var row: Dictionary = catalog_by_id.get(card_id,{}) as Dictionary
    return bool(row.get("purchasable",true))

func ownership_status(card_id: String, stars: float) -> String:
    if stars <= 3.0 or base_card_ids().has(card_id):
        return "base"
    if owned_card_ids().has(card_id):
        return "permanent"
    if free_card_ids().has(card_id):
        return "weekly"
    return "missing"

func ownership_label(card_id: String, stars: float) -> String:
    match ownership_status(card_id,stars):
        "base":
            return "DÉBLOQUÉE DE BASE"
        "permanent":
            return "POSSÉDÉE DÉFINITIVEMENT"
        "weekly":
            return "GRATUITE CETTE SEMAINE"
        _:
            return "NON POSSÉDÉE"

func refresh_state(_include_catalog: bool = true) -> void:
    _connect_auth_transport()
    # Toujours demander la rotation publique en parallèle.
    AuthManager.refresh_weekly_collection()
    if not has_auth_session():
        request_failed.emit("state","Compte YUGITO non connecté.")
        return
    if busy_state:
        return
    busy_state = true
    AuthManager.refresh_economy_state()

func refresh_weekly_rotation() -> void:
    _connect_auth_transport()
    AuthManager.refresh_weekly_collection()

func purchase_card(card_id: String) -> void:
    _connect_auth_transport()
    if not has_auth_session():
        request_failed.emit("purchase","Compte YUGITO non connecté.")
        return
    if busy_purchase:
        return
    busy_purchase = true
    AuthManager.purchase_economy_card(card_id)

func _on_auth_economy_state(data: Dictionary) -> void:
    busy_state = false
    _apply_state(data)

func _on_auth_weekly(data: Dictionary) -> void:
    _apply_weekly(data)

func _on_auth_purchase(card_id: String, data: Dictionary) -> void:
    busy_purchase = false
    var returned_state: Dictionary = data.get("state",{}) as Dictionary
    if not returned_state.is_empty():
        _apply_state(returned_state,false)
    purchase_completed.emit(card_id,data)

func _on_auth_economy_failed(kind: String, message: String) -> void:
    if kind == "state":
        busy_state = false
    elif kind == "purchase":
        busy_purchase = false
    request_failed.emit(kind,message)

func _apply_weekly(data: Dictionary) -> void:
    if not bool(data.get("ok",false)):
        return
    var ids: Array[String] = _string_array(data.get("card_ids",[]) as Array)
    if ids.is_empty():
        return
    var new_state: Dictionary = state.duplicate(true)
    new_state["free_card_ids"] = ids
    new_state["rotation"] = {
        "week_key":str(data.get("week_key","")),
        "starts_at":int(data.get("starts_at",0)),
        "ends_at":int(data.get("ends_at",0)),
        "card_ids":ids,
    }
    _rebuild_available(new_state)
    state = new_state
    _save_cache()
    state_updated.emit(state.duplicate(true))

func _apply_state(data: Dictionary, emit_signal: bool = true) -> void:
    if not bool(data.get("ok",false)):
        return
    var previous_weekly: Array[String] = free_card_ids()
    var new_state: Dictionary = state.duplicate(true)
    for key: Variant in data.keys():
        new_state[key] = data[key]

    # Le serveur economy/state est normalement autoritaire. Mais si une réponse
    # transitoire ne contient pas encore free_card_ids, on conserve la rotation
    # publique déjà validée au lieu de revenir brutalement à 7 cartes.
    var incoming_free: Array[String] = _string_array(data.get("free_card_ids",[]) as Array)
    if incoming_free.is_empty() and not previous_weekly.is_empty():
        new_state["free_card_ids"] = previous_weekly

    if data.get("catalog",[]) is Array:
        catalog_by_id.clear()
        var catalog: Array = data.get("catalog",[]) as Array
        for raw: Variant in catalog:
            if raw is Dictionary:
                var row: Dictionary = raw as Dictionary
                var cid: String = str(row.get("id",""))
                if not cid.is_empty():
                    catalog_by_id[cid] = row.duplicate(true)

    _rebuild_available(new_state)
    state = new_state
    _save_cache()
    if emit_signal:
        state_updated.emit(state.duplicate(true))

func _rebuild_available(target: Dictionary) -> void:
    var available: Array[String] = []
    for source_key: String in ["base_card_ids","owned_card_ids","free_card_ids"]:
        for cid: String in _string_array(target.get(source_key,[]) as Array):
            if not available.has(cid):
                available.append(cid)
    target["available_card_ids"] = available

func _string_array(values: Array) -> Array[String]:
    var result: Array[String] = []
    for raw: Variant in values:
        var value: String = str(raw)
        if not value.is_empty():
            result.append(value)
    return result

func _save_cache() -> void:
    if state.is_empty():
        return
    var file: FileAccess = FileAccess.open(CACHE_PATH,FileAccess.WRITE)
    if file == null:
        return
    file.store_string(JSON.stringify({
        "state":state,
        "catalog_by_id":catalog_by_id,
        "saved_at":int(Time.get_unix_time_from_system())
    }))

func _load_cache() -> void:
    if not FileAccess.file_exists(CACHE_PATH):
        return
    var file: FileAccess = FileAccess.open(CACHE_PATH,FileAccess.READ)
    if file == null:
        return
    var parsed: Variant = JSON.parse_string(file.get_as_text())
    if not (parsed is Dictionary):
        return
    var data: Dictionary = parsed as Dictionary
    state = data.get("state",{}) as Dictionary
    catalog_by_id = data.get("catalog_by_id",{}) as Dictionary
