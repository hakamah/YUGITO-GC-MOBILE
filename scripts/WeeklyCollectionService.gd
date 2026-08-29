extends Node

signal rotation_updated(payload: Dictionary)
signal rotation_failed(message: String)

const WEEKLY_URL := "https://yugito-auth-server.onrender.com/api/collection/weekly"
const REFRESH_COOLDOWN_MS := 60 * 1000

var rewards: Node = null
var request: HTTPRequest = null
var busy: bool = false
var last_refresh_ms: int = -1000000
var last_message: String = "Rotation hebdomadaire non chargée."

func _ready() -> void:
    request = HTTPRequest.new()
    request.name = "WeeklyCollectionHTTPRequest"
    add_child(request)
    request.request_completed.connect(_on_request_completed)

func configure(reward_manager: Node) -> void:
    rewards = reward_manager

func refresh(force: bool = false) -> void:
    if request == null or busy:
        return
    var now_ms: int = Time.get_ticks_msec()
    if not force and now_ms - last_refresh_ms < REFRESH_COOLDOWN_MS:
        return
    last_refresh_ms = now_ms
    busy = true
    last_message = "Synchronisation des cartes gratuites…"

    var headers := PackedStringArray([
        "Accept: application/json",
        "User-Agent: YUGITO-GC-Mobile/P65"
    ])
    var err: Error = request.request(WEEKLY_URL,headers,HTTPClient.METHOD_GET)
    if err != OK:
        busy = false
        last_message = "Impossible de joindre la rotation YUGITO."
        rotation_failed.emit(last_message)

func _on_request_completed(
    result: int,
    response_code: int,
    _headers: PackedStringArray,
    body: PackedByteArray
) -> void:
    busy = false

    if result != HTTPRequest.RESULT_SUCCESS or response_code != 200:
        last_message = "Rotation serveur indisponible (HTTP %d)." % response_code
        rotation_failed.emit(last_message)
        return

    var parsed: Variant = JSON.parse_string(body.get_string_from_utf8())
    if typeof(parsed) != TYPE_DICTIONARY:
        last_message = "Réponse rotation invalide."
        rotation_failed.emit(last_message)
        return

    var payload: Dictionary = parsed as Dictionary
    if rewards == null or not rewards.has_method("set_server_weekly_rotation"):
        last_message = "RewardManager incompatible avec la rotation serveur."
        rotation_failed.emit(last_message)
        return

    var accepted: bool = bool(rewards.call("set_server_weekly_rotation",payload))
    if not accepted:
        last_message = "Rotation serveur refusée par validation locale."
        rotation_failed.emit(last_message)
        return

    last_message = "Rotation serveur synchronisée • semaine %s" % str(payload.get("week_key",""))
    rotation_updated.emit(payload)

func status_text() -> String:
    return last_message
