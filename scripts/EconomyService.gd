extends Node

signal state_updated(state: Dictionary)
signal purchase_completed(card_id: String, result: Dictionary)
signal request_failed(kind: String, message: String)

const BASE_URL: String = "https://yugito-auth-server.onrender.com"
const CACHE_PATH: String = "user://yugito_economy_cache_v1.json"
const REQUEST_TIMEOUT_SECONDS: float = 45.0

var state: Dictionary = {}
var catalog_by_id: Dictionary = {}
var busy_state: bool = false
var busy_purchase: bool = false

func _ready() -> void:
    _load_cache()

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

func refresh_state(include_catalog: bool = true) -> void:
    # La rotation publique est indépendante de la session et sert aussi de
    # garde-fou si l'état authentifié tarde à revenir.
    refresh_weekly_rotation()
    if busy_state:
        return
    if not has_auth_session():
        request_failed.emit("state","Compte YUGITO non connecté.")
        return
    busy_state = true
    var suffix: String = "?catalog=1" if include_catalog else "?catalog=0"
    _request_json("state",HTTPClient.METHOD_GET,"/api/economy/state" + suffix,{},AuthManager.session_token)

func refresh_weekly_rotation() -> void:
    _request_json("weekly",HTTPClient.METHOD_GET,"/api/collection/weekly",{},"")

func purchase_card(card_id: String) -> void:
    if busy_purchase:
        return
    if not has_auth_session():
        request_failed.emit("purchase","Compte YUGITO non connecté.")
        return
    var clean_id: String = card_id.strip_edges()
    if clean_id.is_empty():
        request_failed.emit("purchase","Carte invalide.")
        return
    busy_purchase = true
    _request_json(
        "purchase:" + clean_id,
        HTTPClient.METHOD_POST,
        "/api/economy/purchase",
        {"card_id":clean_id},
        AuthManager.session_token
    )

func _request_json(kind: String, method: int, path: String, payload: Dictionary, bearer: String) -> void:
    var request := HTTPRequest.new()
    request.timeout = REQUEST_TIMEOUT_SECONDS
    request.use_threads = true
    request.process_mode = Node.PROCESS_MODE_ALWAYS
    add_child(request)
    request.request_completed.connect(_on_request_completed.bind(kind,request))

    var headers := PackedStringArray([
        "Accept: application/json",
        "User-Agent: YUGITO-GC-Mobile/P67"
    ])
    var body: String = ""
    if method == HTTPClient.METHOD_POST:
        headers.append("Content-Type: application/json")
        body = JSON.stringify(payload)
    if not bearer.is_empty():
        headers.append("Authorization: Bearer " + bearer)

    var err: Error = request.request(BASE_URL + path,headers,method,body)
    if err != OK:
        if is_instance_valid(request):
            request.queue_free()
        _finish_error(kind,"Impossible de démarrer la requête réseau (%s)." % error_string(err))

func _on_request_completed(
    result: int,
    response_code: int,
    _headers: PackedStringArray,
    body: PackedByteArray,
    kind: String,
    request: HTTPRequest
) -> void:
    if is_instance_valid(request):
        request.queue_free()

    if result != HTTPRequest.RESULT_SUCCESS:
        _finish_error(kind,"Serveur économie YUGITO injoignable.")
        return

    var raw_text: String = body.get_string_from_utf8()
    var parsed: Variant = JSON.parse_string(raw_text) if not raw_text.is_empty() else {}
    var data: Dictionary = parsed as Dictionary if parsed is Dictionary else {}

    if response_code < 200 or response_code >= 300:
        _finish_error(kind,str(data.get("error","Erreur économie YUGITO (HTTP %d)." % response_code)))
        return

    if kind == "weekly":
        _apply_weekly(data)
        return

    if kind == "state":
        busy_state = false
        _apply_state(data)
        return

    if kind.begins_with("purchase:"):
        busy_purchase = false
        var card_id: String = kind.trim_prefix("purchase:")
        var returned_state: Dictionary = data.get("state",{}) as Dictionary
        if not returned_state.is_empty():
            _apply_state(returned_state,false)
        purchase_completed.emit(card_id,data)
        return

func _finish_error(kind: String, message: String) -> void:
    if kind == "state":
        busy_state = false
    elif kind.begins_with("purchase:"):
        busy_purchase = false
        kind = "purchase"
    # Une panne de la route publique weekly ne doit pas masquer un état économie
    # authentifié déjà valide/caché.
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

    var available: Array[String] = []
    for cid: String in _string_array(new_state.get("base_card_ids",[]) as Array):
        if not available.has(cid):
            available.append(cid)
    for cid: String in _string_array(new_state.get("owned_card_ids",[]) as Array):
        if not available.has(cid):
            available.append(cid)
    for cid: String in ids:
        if not available.has(cid):
            available.append(cid)
    new_state["available_card_ids"] = available
    state = new_state
    _save_cache()
    state_updated.emit(state.duplicate(true))

func _apply_state(data: Dictionary, emit_signal: bool = true) -> void:
    if not bool(data.get("ok",false)):
        return

    var new_state: Dictionary = state.duplicate(true)
    for key: Variant in data.keys():
        new_state[key] = data[key]
    state = new_state

    if data.get("catalog",[]) is Array:
        catalog_by_id.clear()
        var catalog: Array = data.get("catalog",[]) as Array
        for raw: Variant in catalog:
            if raw is Dictionary:
                var row: Dictionary = raw as Dictionary
                var cid: String = str(row.get("id",""))
                if not cid.is_empty():
                    catalog_by_id[cid] = row.duplicate(true)

    _save_cache()
    if emit_signal:
        state_updated.emit(state.duplicate(true))

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
