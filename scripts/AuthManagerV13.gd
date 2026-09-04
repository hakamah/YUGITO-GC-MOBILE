extends "res://scripts/AuthManager.gd"

# YUGITO GC V13 — TRUE Android Credential Manager diagnostic branch.
# Inherits the production AuthManager so economy/session/profile APIs remain intact.
# Only the interactive Google login path is replaced.

const CM_REQUEST_TIMEOUT_SECONDS: float = 18.0
const CM_WAIT_TIMEOUT_SECONDS: float = 120.0
const CM_EXPECTED_PACKAGE: String = "com.hakamah.yugitogc"
const CM_EXPECTED_RELEASE_SHA1: String = "49:31:D4:C5:AE:80:E9:BC:D5:81:1D:88:8E:BF:31:BF:92:45:98:08"
const GOOGLE_DIAG_INTERNAL_PATH: String = "user://google_diag_log.txt"
const GOOGLE_DIAG_RELATIVE_PATH: String = "Documents/log Google diag/"

var _cm_bridge = null
var _cm_generation: int = 0
var _cm_active: bool = false

var _diag_active: bool = false
var _diag_seq: int = 0
var _diag_internal_file = null
var _diag_external_resolver = null
var _diag_external_uri = null
var _diag_external_ready: bool = false
var _diag_external_first_write: bool = true
var _diag_external_error: String = ""

func begin_google_login() -> void:
    _diag_begin_new_click()
    _diag_log("UI: AuthManagerV13.begin_google_login() reçu")
    if _busy:
        _diag_log("AUTH: ABORT busy=true")
        return

    _cm_generation += 1
    var generation := _cm_generation
    _cm_active = true

    _recovery_hint = IdentityManager.profile().duplicate(true)
    pending_session_token = ""
    pending_account.clear()
    _device_code = ""
    last_verification_url = ""
    _device_expires_at = 0
    _poll_timer.stop()
    _poll_in_flight = false

    _set_busy(true)
    IdentityManager.begin_auth("Ouverture de Google natif…")
    auth_progress.emit("Préparation de Credential Manager…")
    _diag_log("AUTH: V13 TRUE CREDENTIAL MANAGER • browser=false • AccountManager=false")
    call_deferred("_cm_begin_async", generation)

func reopen_google_page() -> void:
    _diag_log("AUTH: reopen_google_page -> relance Credential Manager natif")
    if not _busy:
        begin_google_login()

func cancel_google_login() -> void:
    _diag_log("AUTH: cancel_google_login")
    _cm_generation += 1
    _cm_active = false
    if _cm_bridge != null:
        _cm_bridge.cancel()
        JavaClassWrapper.get_exception()
        _cm_bridge.reset()
        JavaClassWrapper.get_exception()
    _cm_bridge = null
    _poll_timer.stop()
    _poll_in_flight = false
    _device_code = ""
    _device_expires_at = 0
    pending_session_token = ""
    pending_account.clear()
    _set_busy(false)
    IdentityManager.mark_server_unavailable("Connexion Google annulée")
    auth_progress.emit("Connexion Google annulée.")

func _cm_begin_async(generation: int) -> void:
    _diag_log("CM/START: generation=" + str(generation))
    if OS.get_name() != "Android":
        _cm_fail("Credential Manager est disponible uniquement sur Android.")
        return

    # device_code = nonce Google one-shot. The server also returns the Web OAuth client ID.
    _diag_log("SERVER: POST /api/device/start")
    var start: Dictionary = await _cm_http_json(
        HTTPClient.METHOD_POST,
        BASE_URL + "/api/device/start",
        {"platform":"android_cm_v13"}
    )
    if not _cm_is_current(generation):
        return
    _diag_log("SERVER: device/start http=" + str(start.get("_http_code", 0)) + " ok=" + str(start.get("ok", false)))
    if not bool(start.get("ok", false)):
        _cm_fail(str(start.get("error", "Le serveur YUGITO ne répond pas.")))
        return

    var device_code := str(start.get("device_code", "")).strip_edges()
    var web_client_id := str(start.get("google_client_id", "")).strip_edges()
    _diag_log("CM/CONFIG: device_code_present=" + str(not device_code.is_empty()) + " len=" + str(device_code.length()) + " • value NOT logged")
    _diag_log("CM/CONFIG: web_client_id_present=" + str(not web_client_id.is_empty()) + " len=" + str(web_client_id.length()) + " • value NOT logged")
    if device_code.is_empty() or web_client_id.is_empty():
        _cm_fail("Configuration Google incomplète côté serveur YUGITO.")
        return

    JavaClassWrapper.get_exception()
    _cm_bridge = JavaClassWrapper.wrap("com.hakamah.yugitogc.auth.YugitoCredentialBridge")
    var java_err = JavaClassWrapper.get_exception()
    _diag_log("CM/INIT: bridge null=" + str(_cm_bridge == null) + " exception=" + str(java_err))
    if _cm_bridge == null or java_err != null:
        _cm_fail("Le module Android Credential Manager n'est pas présent dans cette APK.")
        return

    var bridge_version = _cm_bridge.getBridgeVersion()
    java_err = JavaClassWrapper.get_exception()
    _diag_log("CM/INIT: bridge_version=" + str(bridge_version) + " exception=" + str(java_err))

    var runtime = Engine.get_singleton("AndroidRuntime")
    java_err = JavaClassWrapper.get_exception()
    var activity = null
    if runtime != null and java_err == null:
        activity = runtime.getActivity()
        java_err = JavaClassWrapper.get_exception()
    _diag_log("CM/INIT: activity null=" + str(activity == null) + " exception=" + str(java_err))
    if activity == null or java_err != null:
        _cm_fail("Impossible d'obtenir l'activité Android YUGITO.")
        return

    var runtime_package = str(_cm_bridge.getPackageName(activity))
    JavaClassWrapper.get_exception()
    var runtime_sha1 = str(_cm_bridge.getSigningSha1(activity))
    JavaClassWrapper.get_exception()
    _diag_log("CM/CONFIG: runtime_package=" + runtime_package)
    _diag_log("CM/CONFIG: runtime_signing_sha1=" + runtime_sha1)
    _diag_log("CM/CONFIG: release_identity_match=" + str(runtime_package == CM_EXPECTED_PACKAGE and runtime_sha1 == CM_EXPECTED_RELEASE_SHA1))
    if runtime_package != CM_EXPECTED_PACKAGE:
        _cm_fail("Package Android inattendu pour Google OAuth.")
        return

    _cm_bridge.reset()
    java_err = JavaClassWrapper.get_exception()
    _diag_log("CM/FLOW: bridge.reset exception=" + str(java_err))

    auth_progress.emit("Ouverture de la fenêtre Google native…")
    _diag_log("CM/UI: request GetGoogleIdOption • filterByAuthorizedAccounts=false • autoSelect=false")
    _diag_log("CM/UI: YUGITO should remain visible behind the system Google sheet")
    var started = _cm_bridge.start(activity, web_client_id, device_code)
    java_err = JavaClassWrapper.get_exception()
    _diag_log("CM/FLOW: bridge.start returned=" + str(started) + " exception=" + str(java_err))
    if java_err != null or not bool(started):
        var ec := ""
        var em := ""
        if java_err == null:
            ec = str(_cm_bridge.getErrorCode())
            JavaClassWrapper.get_exception()
            em = str(_cm_bridge.getErrorMessage())
            JavaClassWrapper.get_exception()
        _diag_log("CM/ERROR: start refused code=" + ec + " detail=" + em.left(240))
        _cm_fail("Impossible de lancer Credential Manager.")
        return

    var wait_started := Time.get_ticks_msec()
    var last_state := -1
    var last_stage := ""
    var last_flow := ""
    while _cm_is_current(generation):
        var state := int(_cm_bridge.getState())
        java_err = JavaClassWrapper.get_exception()
        if java_err != null:
            _diag_log("CM/ERROR: getState exception=" + str(java_err))
            _cm_fail("Erreur Android pendant la connexion Google.")
            return
        var stage := str(_cm_bridge.getStage())
        JavaClassWrapper.get_exception()
        var flow := str(_cm_bridge.getFlow())
        JavaClassWrapper.get_exception()
        if state != last_state or stage != last_stage or flow != last_flow:
            _diag_log("CM/STATE: state=" + str(state) + " flow=" + flow + " stage=" + stage)
            last_state = state
            last_stage = stage
            last_flow = flow
            if stage == "native_sheet_requested":
                auth_progress.emit("Choisis ton compte dans la fenêtre Google native…")
            elif stage == "no_credential_fallback_to_explicit_google":
                auth_progress.emit("Ouverture du panneau Se connecter avec Google…")
                _diag_log("CM/FALLBACK: GetSignInWithGoogleOption • still native • browser=false")

        if state == 2:
            break
        if state == 3:
            _diag_log("CM/RESULT: user_cancelled")
            _cm_finish_cancelled()
            return
        if state == 4:
            var code := str(_cm_bridge.getErrorCode())
            JavaClassWrapper.get_exception()
            var detail := str(_cm_bridge.getErrorMessage())
            JavaClassWrapper.get_exception()
            _diag_log("CM/ERROR: code=" + code + " detail=" + detail.left(260))
            var friendly := "Connexion Google native impossible."
            if code == "provider_configuration":
                friendly = "Credential Manager est présent mais Google refuse la configuration OAuth Android. Vérifie package + SHA-1 et le Web Client ID."
            elif code == "unsupported":
                friendly = "Credential Manager n'est pas pris en charge par les services Google de cet appareil."
            elif code == "no_credential":
                friendly = "Aucun compte Google utilisable n'a été trouvé."
            _cm_fail(friendly)
            return

        if Time.get_ticks_msec() - wait_started > int(CM_WAIT_TIMEOUT_SECONDS * 1000.0):
            _diag_log("CM/ERROR: native wait timeout")
            _cm_bridge.cancel()
            JavaClassWrapper.get_exception()
            _cm_fail("La fenêtre Google n'a pas répondu.")
            return
        await get_tree().create_timer(0.10).timeout

    if not _cm_is_current(generation):
        return

    var id_token := str(_cm_bridge.takeIdToken())
    java_err = JavaClassWrapper.get_exception()
    _diag_log("CM/RESULT: success token_present=" + str(not id_token.is_empty()) + " len=" + str(id_token.length()) + " • TOKEN/EMAIL CONTENT NOT LOGGED")
    if java_err != null or id_token.is_empty():
        _cm_fail("Google n'a pas fourni de jeton d'identité.")
        return

    _diag_log("SERVER: POST /api/device/google-token auth_mode=credential_manager • token NOT logged")
    var exchange: Dictionary = await _cm_http_json(
        HTTPClient.METHOD_POST,
        BASE_URL + "/api/device/google-token",
        {"device_code":device_code, "id_token":id_token, "auth_mode":"credential_manager"}
    )
    id_token = ""
    if not _cm_is_current(generation):
        return
    _diag_log("SERVER: google-token http=" + str(exchange.get("_http_code", 0)) + " ok=" + str(exchange.get("ok", false)) + " status=" + str(exchange.get("status", "")))
    if not bool(exchange.get("ok", false)):
        _cm_fail(str(exchange.get("error", "Le serveur YUGITO a refusé l'identité Google.")))
        return

    var status: Dictionary = await _cm_http_json(
        HTTPClient.METHOD_GET,
        BASE_URL + "/api/device/status?device_code=" + device_code.uri_encode(),
        {}
    )
    if not _cm_is_current(generation):
        return
    _diag_log("SERVER: device/status http=" + str(status.get("_http_code", 0)) + " ok=" + str(status.get("ok", false)) + " status=" + str(status.get("status", "")))
    if not bool(status.get("ok", false)) or str(status.get("status", "")) != "authenticated":
        _cm_fail("Google a validé le compte mais la session YUGITO n'a pas été finalisée.")
        return

    var session := str(status.get("session_token", "")).strip_edges()
    var account: Dictionary = status.get("account", {}) as Dictionary if status.get("account", {}) is Dictionary else {}
    if session.is_empty() or account.is_empty():
        _cm_fail("Le serveur n'a pas renvoyé la session YUGITO attendue.")
        return

    _cm_cleanup_bridge()
    _cm_active = false
    _device_code = ""

    if str(account.get("pseudo", "")).strip_edges().is_empty():
        pending_session_token = session
        pending_account = account.duplicate(true)
        IdentityManager.require_pseudo(account)
        pseudo_required.emit(account)
        auth_progress.emit("Google connecté • choisis maintenant ton pseudo YUGITO.")
        _set_busy(false)
        _diag_log("AUTH: Google native success • pseudo_required=true")
        return

    _diag_log("AUTH: SUCCESS • Credential Manager -> Google ID token -> YUGITO session")
    _complete_auth(session, account)

func _cm_is_current(generation: int) -> bool:
    return _cm_active and _busy and generation == _cm_generation

func _cm_finish_cancelled() -> void:
    _cm_cleanup_bridge()
    _cm_active = false
    _set_busy(false)
    IdentityManager.mark_server_unavailable("Connexion Google annulée")
    auth_progress.emit("Connexion Google annulée.")

func _cm_fail(message: String) -> void:
    _diag_log("AUTH/FAIL: " + message)
    _cm_cleanup_bridge()
    _cm_active = false
    _poll_timer.stop()
    _poll_in_flight = false
    _set_busy(false)
    IdentityManager.set_auth_error(message)
    auth_failed.emit(message)

func _cm_cleanup_bridge() -> void:
    if _cm_bridge != null:
        _cm_bridge.reset()
        JavaClassWrapper.get_exception()
    _cm_bridge = null

func _cm_http_json(method: int, url: String, payload: Dictionary) -> Dictionary:
    var started_ms := Time.get_ticks_msec()
    var req := HTTPRequest.new()
    req.timeout = CM_REQUEST_TIMEOUT_SECONDS
    req.use_threads = true
    req.process_mode = Node.PROCESS_MODE_ALWAYS
    add_child(req)

    var state: Dictionary = {"done":false, "result":-1, "http":0, "body":PackedByteArray()}
    req.request_completed.connect(func(result_code, response_code, _headers, raw_body):
        state["done"] = true
        state["result"] = int(result_code)
        state["http"] = int(response_code)
        state["body"] = raw_body
    , CONNECT_ONE_SHOT)

    var headers := PackedStringArray(["Accept: application/json", "User-Agent: YUGITO-Godot/2.1.5-CM-V13"])
    var body := ""
    if method != HTTPClient.METHOD_GET:
        headers.append("Content-Type: application/json")
        body = JSON.stringify(payload)

    var start_err := req.request(url, headers, method, body)
    if start_err != OK:
        req.queue_free()
        return {"ok":false, "error":"Impossible de démarrer la requête YUGITO.", "_http_code":0}

    while not bool(state.get("done", false)):
        if Time.get_ticks_msec() - started_ms > int(CM_REQUEST_TIMEOUT_SECONDS * 1000.0):
            req.cancel_request()
            req.queue_free()
            _diag_log("HTTP: timeout url=" + url.replace(BASE_URL, "<BASE>"))
            return {"ok":false, "error":"Le serveur YUGITO ne répond pas assez vite.", "_http_code":0}
        await get_tree().create_timer(0.05).timeout

    var result_code := int(state.get("result", -1))
    var http_code := int(state.get("http", 0))
    var raw: PackedByteArray = state.get("body", PackedByteArray())
    req.queue_free()

    var parsed = JSON.parse_string(raw.get_string_from_utf8())
    var out: Dictionary = parsed as Dictionary if parsed is Dictionary else {}
    out["_http_code"] = http_code
    out["_request_result"] = result_code
    if result_code != HTTPRequest.RESULT_SUCCESS or http_code < 200 or http_code >= 300:
        out["ok"] = false
        if not out.has("error"):
            out["error"] = "Erreur réseau YUGITO (HTTP %d)." % http_code
    return out

func _diag_begin_new_click() -> void:
    _diag_close_writers()
    _diag_active = true
    _diag_seq = 0
    _diag_external_error = ""
    _diag_internal_file = FileAccess.open(GOOGLE_DIAG_INTERNAL_PATH, FileAccess.WRITE)
    _diag_try_open_documents_writer()
    _diag_log("============================================================")
    _diag_log("YUGITO GC • GOOGLE DIAG V13 • TRUE CREDENTIAL MANAGER • NO BROWSER • NO ACCOUNTMANAGER • NO TOKEN/EMAIL LOGGED")
    _diag_log("Time: " + Time.get_datetime_string_from_system(false, true))
    _diag_log("OS: " + OS.get_name() + " • version=" + OS.get_version() + " • model=" + OS.get_model_name())
    _diag_log("Godot: " + str(Engine.get_version_info().get("string", Engine.get_version_info())))
    _diag_log("Documents writer ready=" + str(_diag_external_ready))
    if not _diag_external_error.is_empty():
        _diag_log("Documents writer error=" + _diag_external_error)
    _diag_log("============================================================")

func _diag_close_writers() -> void:
    _diag_external_resolver = null
    _diag_external_uri = null
    _diag_external_ready = false
    _diag_external_first_write = true
    if _diag_internal_file != null:
        _diag_internal_file.flush()
        _diag_internal_file.close()
    _diag_internal_file = null

func _diag_try_open_documents_writer() -> void:
    _diag_external_ready = false
    if OS.get_name() != "Android":
        _diag_external_error = "Not Android"
        return
    JavaClassWrapper.get_exception()
    var runtime = Engine.get_singleton("AndroidRuntime")
    if runtime == null:
        _diag_external_error = "AndroidRuntime unavailable"
        return
    var activity = runtime.getActivity()
    var err = JavaClassWrapper.get_exception()
    if err != null or activity == null:
        _diag_external_error = "getActivity failed: " + str(err)
        return
    var ContentValues = JavaClassWrapper.wrap("android.content.ContentValues")
    var MediaStoreFiles = JavaClassWrapper.wrap("android.provider.MediaStore$Files")
    err = JavaClassWrapper.get_exception()
    if ContentValues == null or MediaStoreFiles == null or err != null:
        _diag_external_error = "MediaStore wrappers failed: " + str(err)
        return
    var values = ContentValues.ContentValues()
    err = JavaClassWrapper.get_exception()
    if values == null or err != null:
        _diag_external_error = "ContentValues failed: " + str(err)
        return
    values.put("_display_name", "log.txt")
    JavaClassWrapper.get_exception()
    values.put("mime_type", "text/plain")
    JavaClassWrapper.get_exception()
    values.put("relative_path", GOOGLE_DIAG_RELATIVE_PATH)
    JavaClassWrapper.get_exception()
    var collection = MediaStoreFiles.getContentUri("external")
    err = JavaClassWrapper.get_exception()
    var resolver = activity.getContentResolver()
    err = JavaClassWrapper.get_exception()
    if collection == null or resolver == null or err != null:
        _diag_external_error = "MediaStore resolver failed: " + str(err)
        return
    var uri = resolver.insert(collection, values)
    err = JavaClassWrapper.get_exception()
    if uri == null or err != null:
        _diag_external_error = "MediaStore insert failed: " + str(err)
        return
    _diag_external_uri = uri
    _diag_external_resolver = resolver
    _diag_external_ready = true
    _diag_external_first_write = true

func _diag_log(message: String) -> void:
    if not _diag_active:
        return
    _diag_seq += 1
    var line := "%03d | %s | %s\n" % [_diag_seq, Time.get_time_string_from_system(), message]
    if _diag_internal_file != null:
        _diag_internal_file.store_string(line)
        _diag_internal_file.flush()
    if _diag_external_ready and _diag_external_resolver != null and _diag_external_uri != null:
        var mode := "w" if _diag_external_first_write else "wa"
        var stream = _diag_external_resolver.openOutputStream(_diag_external_uri, mode)
        var err = JavaClassWrapper.get_exception()
        if stream == null or err != null:
            _diag_external_ready = false
            return
        var bytes := line.to_utf8_buffer()
        stream.write(bytes, 0, bytes.size())
        err = JavaClassWrapper.get_exception()
        stream.flush()
        JavaClassWrapper.get_exception()
        stream.close()
        JavaClassWrapper.get_exception()
        if err == null:
            _diag_external_first_write = false
        else:
            _diag_external_ready = false
