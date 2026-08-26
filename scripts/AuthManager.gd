extends Node

signal busy_changed(is_busy: bool)
signal auth_flow_started(verification_url: String, expires_in: int)
signal auth_progress(message: String)
signal pseudo_required(account: Dictionary)
signal authenticated(account: Dictionary)
signal auth_failed(message: String)
signal session_changed(is_connected: bool)
signal server_health_changed(ok: bool, data: Dictionary)

const BASE_URL: String = "https://yugito-auth-server.onrender.com"
const SESSION_PATH: String = "user://yugito_auth_session.bin"
const CLIENT_VERSION: String = "YUGITO-Godot/2.0-p47"
const REQUEST_TIMEOUT_SECONDS: float = 45.0

var session_token: String = ""
var pending_session_token: String = ""
var pending_account: Dictionary = {}
var last_verification_url: String = ""

var _device_code: String = ""
var _device_expires_at: int = 0
var _poll_interval: float = 2.0
var _poll_timer: Timer
var _poll_in_flight: bool = false
var _busy: bool = false
var _recovery_hint: Dictionary = {}
var _session_account_cache: Dictionary = {}

func _ready() -> void:
    process_mode = Node.PROCESS_MODE_ALWAYS
    _poll_timer = Timer.new()
    _poll_timer.one_shot = false
    _poll_timer.wait_time = 2.0
    _poll_timer.process_callback = Timer.TIMER_PROCESS_IDLE
    _poll_timer.timeout.connect(_poll_device_status)
    add_child(_poll_timer)

    _load_session()
    if not session_token.is_empty():
        validate_saved_session()
    else:
        check_health()

func is_busy() -> bool:
    return _busy

func is_session_available() -> bool:
    return not session_token.is_empty()

func current_account() -> Dictionary:
    return _session_account_cache.duplicate(true)

func begin_google_login() -> void:
    if _busy:
        return
    _recovery_hint = IdentityManager.profile().duplicate(true)
    pending_session_token = ""
    pending_account.clear()
    _device_code = ""
    last_verification_url = ""
    _device_expires_at = 0
    _poll_timer.stop()

    _set_busy(true)
    IdentityManager.begin_auth("Connexion au serveur de comptes YUGITO…")
    auth_progress.emit("Préparation de la connexion Google…")
    _request_json(
        "device_start",
        HTTPClient.METHOD_POST,
        "/api/device/start",
        {"platform": _platform_name()}
    )

func reopen_google_page() -> void:
    if last_verification_url.is_empty():
        return
    OS.shell_open(last_verification_url)

func cancel_google_login() -> void:
    _poll_timer.stop()
    _poll_in_flight = false
    _device_code = ""
    _device_expires_at = 0
    pending_session_token = ""
    pending_account.clear()
    _set_busy(false)
    IdentityManager.mark_server_unavailable("Connexion Google annulée")
    auth_progress.emit("Connexion Google annulée.")

func claim_pseudo(value: String) -> void:
    if pending_session_token.is_empty():
        _fail("La session Google n'est plus disponible. Relance la connexion.")
        return
    var validated: Dictionary = IdentityManager.validate_pseudo(value)
    if not bool(validated.get("ok", false)):
        auth_failed.emit(str(validated.get("message", "Pseudo invalide.")))
        return

    var clean: String = str(validated.get("clean", "")).strip_edges()
    var body: Dictionary = {"pseudo": clean}

    # Le serveur 1.4.10 accepte un recovery non-secret pour retrouver le dernier
    # account_id connu après une ancienne base Render éphémère.
    var old_pseudo: String = str(_recovery_hint.get("pseudo", "")).strip_edges()
    var old_aid: String = str(_recovery_hint.get("account_id", "")).strip_edges()
    var old_email: String = str(_recovery_hint.get("email", "")).strip_edges()
    if (
        not old_pseudo.is_empty()
        and not old_aid.is_empty()
        and not old_email.is_empty()
        and _normalize_pseudo(old_pseudo) == _normalize_pseudo(clean)
    ):
        body["recovery"] = {
            "pseudo": old_pseudo,
            "account_id": old_aid,
            "email": old_email,
        }

    _set_busy(true)
    IdentityManager.begin_auth("Enregistrement du pseudo YUGITO…")
    auth_progress.emit("Enregistrement de %s…" % clean)
    _request_json(
        "claim_pseudo",
        HTTPClient.METHOD_POST,
        "/api/account/claim-pseudo",
        body,
        pending_session_token
    )

func validate_saved_session() -> void:
    if session_token.is_empty():
        IdentityManager.disconnect_session_keep_profile()
        session_changed.emit(false)
        return
    _set_busy(true)
    IdentityManager.begin_auth("Vérification de la session YUGITO…")
    auth_progress.emit("Vérification de la session enregistrée…")
    _request_json(
        "session_me",
        HTTPClient.METHOD_GET,
        "/api/account/me",
        {},
        session_token
    )

func logout() -> void:
    var old_token: String = session_token
    _poll_timer.stop()
    _device_code = ""
    pending_session_token = ""
    pending_account.clear()
    session_token = ""
    _session_account_cache.clear()
    _clear_session_file()
    IdentityManager.disconnect_session_keep_profile()
    session_changed.emit(false)

    if not old_token.is_empty():
        _request_json(
            "logout",
            HTTPClient.METHOD_POST,
            "/api/logout",
            {},
            old_token
        )

func sync_ranked_profile() -> void:
    if session_token.is_empty():
        return
    var profile: Dictionary = IdentityManager.server_profile_payload()
    _request_json(
        "sync_elo",
        HTTPClient.METHOD_POST,
        "/api/account/sync-elo",
        {
            "elo": int(profile.get("elo", IdentityManager.DEFAULT_ELO)),
            "profile": profile,
        },
        session_token
    )

func check_health() -> void:
    _request_json("health", HTTPClient.METHOD_GET, "/health")

func _platform_name() -> String:
    var os_name: String = OS.get_name().to_lower()
    if os_name == "android":
        return "android-godot"
    if os_name == "windows":
        return "windows"
    if os_name == "macos":
        return "macos-godot"
    return os_name + "-godot"

func _request_json(
    kind: String,
    method: int,
    path: String,
    payload: Dictionary = {},
    bearer: String = ""
) -> void:
    var request := HTTPRequest.new()
    request.timeout = REQUEST_TIMEOUT_SECONDS
    request.use_threads = true
    request.process_mode = Node.PROCESS_MODE_ALWAYS
    add_child(request)
    request.request_completed.connect(_on_request_completed.bind(kind, request))

    var headers: PackedStringArray = PackedStringArray([
        "Accept: application/json",
        "User-Agent: " + CLIENT_VERSION,
    ])
    var body: String = ""
    if method == HTTPClient.METHOD_POST:
        headers.append("Content-Type: application/json")
        body = JSON.stringify(payload)
    if not bearer.is_empty():
        headers.append("Authorization: Bearer " + bearer)

    var err: Error = request.request(BASE_URL + path, headers, method, body)
    if err != OK:
        request.queue_free()
        _handle_transport_error(kind, "Impossible de démarrer la requête réseau (%s)." % error_string(err))

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

    if kind == "device_status":
        _poll_in_flight = false

    if result != HTTPRequest.RESULT_SUCCESS:
        _handle_transport_error(kind, "Serveur YUGITO injoignable.")
        return

    var text: String = body.get_string_from_utf8()
    var parsed: Variant = JSON.parse_string(text) if not text.is_empty() else {}
    var data: Dictionary = parsed as Dictionary if parsed is Dictionary else {}

    if response_code < 200 or response_code >= 300:
        _handle_http_error(kind, response_code, data)
        return

    match kind:
        "health":
            server_health_changed.emit(bool(data.get("ok", false)), data)
        "device_start":
            _handle_device_start(data)
        "device_status":
            _handle_device_status(data)
        "session_me":
            _handle_session_me(data)
        "claim_pseudo":
            _handle_claim_pseudo(data)
        "sync_elo":
            _handle_sync_elo(data)
        "logout":
            pass

func _handle_device_start(data: Dictionary) -> void:
    var code: String = str(data.get("device_code", "")).strip_edges()
    var url: String = str(data.get("verification_url", "")).strip_edges()
    var expires_in: int = maxi(60, int(data.get("expires_in", 600)))
    var interval: float = maxf(1.0, float(data.get("interval", 2.0)))
    if code.is_empty() or url.is_empty():
        _fail("Le serveur n'a pas renvoyé le lien Google attendu.")
        return

    _device_code = code
    last_verification_url = url
    _device_expires_at = int(Time.get_unix_time_from_system()) + expires_in
    _poll_interval = interval
    _poll_timer.wait_time = interval
    _poll_timer.start()

    IdentityManager.begin_auth("Google ouvert • en attente de validation…")
    auth_flow_started.emit(url, expires_in)
    auth_progress.emit("Valide ton compte Google puis reviens dans YUGITO.")
    OS.shell_open(url)
    _set_busy(false)

func _poll_device_status() -> void:
    if _device_code.is_empty() or _poll_in_flight:
        return
    if int(Time.get_unix_time_from_system()) >= _device_expires_at:
        _poll_timer.stop()
        _fail("La connexion Google a expiré. Relance-la depuis YUGITO.")
        return

    _poll_in_flight = true
    var query: String = "/api/device/status?device_code=" + _device_code.uri_encode()
    _request_json("device_status", HTTPClient.METHOD_GET, query)

func _handle_device_status(data: Dictionary) -> void:
    var status: String = str(data.get("status", ""))
    if status == "pending":
        auth_progress.emit("En attente de Google…")
        return
    if status != "authenticated":
        return

    _poll_timer.stop()
    _device_code = ""

    var token: String = str(data.get("session_token", "")).strip_edges()
    var account: Dictionary = data.get("account", {}) as Dictionary if data.get("account", {}) is Dictionary else {}
    if token.is_empty() or account.is_empty():
        _fail("Le serveur a validé Google mais n'a pas renvoyé de session YUGITO.")
        return

    var account_pseudo: String = str(account.get("pseudo", "")).strip_edges()
    if account_pseudo.is_empty():
        pending_session_token = token
        pending_account = account.duplicate(true)
        IdentityManager.require_pseudo(account)
        pseudo_required.emit(account)
        auth_progress.emit("Google connecté • choisis maintenant ton pseudo YUGITO.")
        _set_busy(false)
        return

    _complete_auth(token, account)

func _handle_session_me(data: Dictionary) -> void:
    var account: Dictionary = data.get("account", {}) as Dictionary if data.get("account", {}) is Dictionary else {}
    if account.is_empty():
        _invalidate_local_session("Session YUGITO invalide.")
        return
    _apply_account_preserving_profile(account)
    _session_account_cache = account.duplicate(true)
    _save_session()
    _set_busy(false)
    authenticated.emit(account)
    session_changed.emit(true)
    auth_progress.emit("Session YUGITO restaurée.")

func _handle_claim_pseudo(data: Dictionary) -> void:
    var token: String = str(data.get("session_token", pending_session_token)).strip_edges()
    var account: Dictionary = data.get("account", {}) as Dictionary if data.get("account", {}) is Dictionary else {}
    if token.is_empty() or account.is_empty():
        _fail("Le serveur n'a pas confirmé le nouveau pseudo.")
        return
    pending_session_token = ""
    pending_account.clear()
    _complete_auth(token, account)

func _handle_sync_elo(data: Dictionary) -> void:
    var new_token: String = str(data.get("session_token", session_token)).strip_edges()
    var account: Dictionary = data.get("account", {}) as Dictionary if data.get("account", {}) is Dictionary else {}
    if not new_token.is_empty():
        session_token = new_token
    if not account.is_empty():
        _apply_account_preserving_profile(account)
        _session_account_cache = account.duplicate(true)
    if not session_token.is_empty():
        _save_session()

func _complete_auth(token: String, account: Dictionary) -> void:
    session_token = token
    pending_session_token = ""
    pending_account.clear()
    _session_account_cache = account.duplicate(true)
    _apply_account_preserving_profile(account)
    _recovery_hint.clear()
    _save_session()
    _set_busy(false)
    authenticated.emit(account)
    session_changed.emit(true)
    auth_progress.emit("Compte Google YUGITO connecté.")

func _apply_account_preserving_profile(account: Dictionary) -> void:
    var previous: Dictionary = IdentityManager.profile()
    var incoming_id: String = str(account.get("account_id", "")).strip_edges()
    var previous_id: String = str(previous.get("account_id", "")).strip_edges()
    var recovery_id: String = str(_recovery_hint.get("account_id", "")).strip_edges()

    var source_profile: Dictionary = {}
    if not incoming_id.is_empty() and incoming_id == previous_id:
        source_profile = previous
    elif not incoming_id.is_empty() and incoming_id == recovery_id:
        source_profile = _recovery_hint

    var ranked_profile: Dictionary = {}
    if not source_profile.is_empty():
        ranked_profile = {
            "elo": int(account.get("elo", source_profile.get("elo", IdentityManager.DEFAULT_ELO))),
            "ranked_matches": int(source_profile.get("ranked_matches", 0)),
            "wins": int(source_profile.get("wins", 0)),
            "losses": int(source_profile.get("losses", 0)),
            "best_elo": int(source_profile.get("best_elo", account.get("elo", IdentityManager.DEFAULT_ELO))),
        }
    IdentityManager.apply_server_account(account, ranked_profile)

func _handle_http_error(kind: String, response_code: int, data: Dictionary) -> void:
    var message: String = str(data.get("error", "Erreur serveur YUGITO (HTTP %d)." % response_code))
    if kind == "device_status" and response_code == 410:
        _poll_timer.stop()
        _fail("La connexion Google a expiré. Relance-la depuis YUGITO.")
        return
    if kind == "session_me" and response_code == 401:
        _invalidate_local_session("Ta session YUGITO a expiré. Reconnecte Google.")
        return
    if kind == "claim_pseudo":
        _set_busy(false)
        IdentityManager.require_pseudo(pending_account)
        auth_failed.emit(message)
        return
    if kind == "logout":
        return
    _fail(message)

func _handle_transport_error(kind: String, message: String) -> void:
    if kind == "health":
        server_health_changed.emit(false, {"error": message})
        return
    if kind == "device_status":
        # On ne détruit pas le Device Flow à la première micro-coupure.
        auth_progress.emit("Connexion au serveur interrompue • nouvelle tentative…")
        return
    if kind == "session_me":
        _set_busy(false)
        IdentityManager.mark_server_unavailable("Serveur YUGITO indisponible")
        auth_progress.emit("Mode hors ligne • la session sera revérifiée plus tard.")
        return
    if kind == "logout":
        return
    _fail(message)

func _invalidate_local_session(message: String) -> void:
    session_token = ""
    pending_session_token = ""
    pending_account.clear()
    _session_account_cache.clear()
    _clear_session_file()
    _set_busy(false)
    IdentityManager.require_google(message)
    session_changed.emit(false)
    auth_failed.emit(message)

func _fail(message: String) -> void:
    _poll_timer.stop()
    _poll_in_flight = false
    _set_busy(false)
    IdentityManager.set_auth_error(message)
    auth_failed.emit(message)

func _set_busy(value: bool) -> void:
    if _busy == value:
        return
    _busy = value
    busy_changed.emit(_busy)

func _normalize_pseudo(value: String) -> String:
    var clean: String = value.strip_edges().to_lower()
    while clean.find("  ") >= 0:
        clean = clean.replace("  ", " ")
    return clean

func _session_password() -> String:
    var uid: String = OS.get_unique_id()
    if uid.is_empty():
        uid = OS.get_name() + "|" + ProjectSettings.globalize_path("user://")
    return "YUGITO-P47|" + uid + "|AUTH-SESSION"

func _save_session() -> void:
    if session_token.is_empty():
        _clear_session_file()
        return
    var file := FileAccess.open_encrypted_with_pass(
        SESSION_PATH,
        FileAccess.WRITE,
        _session_password()
    )
    if file == null:
        push_warning("AuthManager: impossible de sauvegarder la session chiffrée.")
        return
    file.store_string(JSON.stringify({
        "session_token": session_token,
        "account": _session_account_cache,
        "saved_at": int(Time.get_unix_time_from_system()),
    }))

func _load_session() -> void:
    if not FileAccess.file_exists(SESSION_PATH):
        return
    var file := FileAccess.open_encrypted_with_pass(
        SESSION_PATH,
        FileAccess.READ,
        _session_password()
    )
    if file == null:
        _clear_session_file()
        return
    var parsed: Variant = JSON.parse_string(file.get_as_text())
    if not (parsed is Dictionary):
        _clear_session_file()
        return
    var data: Dictionary = parsed as Dictionary
    session_token = str(data.get("session_token", "")).strip_edges()
    if data.get("account", {}) is Dictionary:
        _session_account_cache = (data.get("account", {}) as Dictionary).duplicate(true)

func _clear_session_file() -> void:
    if not FileAccess.file_exists(SESSION_PATH):
        return
    DirAccess.remove_absolute(ProjectSettings.globalize_path(SESSION_PATH))
