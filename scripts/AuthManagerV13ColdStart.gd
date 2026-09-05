extends "res://scripts/AuthManagerV13.gd"

# YUGITO GC • V13.2 COLD-START HARDENING
#
# Purpose:
# - keep the validated Android Credential Manager bridge untouched;
# - survive Render Free cold starts before /api/device/start answers;
# - make duplicate taps visible instead of silently returning;
# - preserve the same Google/server/session contract as V13.1.
#
# No token, e-mail, device_code or Google identity value is logged here.

const COLDSTART_FIRST_TIMEOUT_SECONDS: float = 30.0
const COLDSTART_RETRY_TIMEOUT_SECONDS: float = 75.0
const NORMAL_API_TIMEOUT_SECONDS: float = 30.0
const COLDSTART_NOTICE_AFTER_SECONDS: float = 6.0

func begin_google_login() -> void:
    # V13.1 silently returned when _busy was already true. On mobile this looked
    # exactly like a dead Google button. Keep the running flow intact and make the
    # state visible to the player + diagnostic log instead.
    if _busy:
        auth_progress.emit("Connexion Google déjà en cours…")
        if _diag_active:
            _diag_log("UI: duplicate Google tap while busy=true • active flow preserved")
        return
    super.begin_google_login()

func _cm_http_json(method: int, url: String, payload: Dictionary) -> Dictionary:
    var is_device_start := url.ends_with("/api/device/start")
    var first_timeout := COLDSTART_FIRST_TIMEOUT_SECONDS if is_device_start else NORMAL_API_TIMEOUT_SECONDS

    if is_device_start:
        _diag_log("HTTP/COLDSTART: /api/device/start attempt=1 timeout=" + str(first_timeout))
        auth_progress.emit("Connexion au serveur YUGITO…")

    var out: Dictionary = await _cm_http_json_once(method, url, payload, first_timeout, is_device_start)

    # A sleeping Render service can fail/timeout before the Python process is ready.
    # Retry only network-level failures (no HTTP response). HTTP 4xx/5xx must remain
    # visible as real server errors and are never hidden by this retry.
    if is_device_start and _busy and not bool(out.get("ok", false)) and int(out.get("_http_code", 0)) == 0:
        _diag_log("HTTP/COLDSTART: attempt=1 failed before HTTP response -> retry=1")
        auth_progress.emit("Réveil du serveur YUGITO… Google s'ouvrira automatiquement.")
        await get_tree().create_timer(1.0).timeout
        if not _busy:
            return {"ok":false, "error":"Connexion Google annulée.", "_http_code":0, "_request_result":-1}
        out = await _cm_http_json_once(method, url, payload, COLDSTART_RETRY_TIMEOUT_SECONDS, true)
        _diag_log("HTTP/COLDSTART: attempt=2 finished http=" + str(out.get("_http_code", 0)) + " ok=" + str(out.get("ok", false)) + " result=" + str(out.get("_request_result", -1)))

    return out

func _cm_http_json_once(method: int, url: String, payload: Dictionary, timeout_seconds: float, show_coldstart_notice: bool) -> Dictionary:
    var started_ms := Time.get_ticks_msec()
    var req := HTTPRequest.new()
    req.timeout = timeout_seconds
    req.use_threads = true
    req.process_mode = Node.PROCESS_MODE_ALWAYS
    add_child(req)

    var state: Dictionary = {
        "done": false,
        "result": -1,
        "http": 0,
        "body": PackedByteArray(),
    }
    req.request_completed.connect(func(result_code, response_code, _headers, raw_body):
        state["done"] = true
        state["result"] = int(result_code)
        state["http"] = int(response_code)
        state["body"] = raw_body
    , CONNECT_ONE_SHOT)

    var headers := PackedStringArray([
        "Accept: application/json",
        "User-Agent: YUGITO-Godot/2.1.5-CM-V13.2-ColdStart",
    ])
    var body := ""
    if method != HTTPClient.METHOD_GET:
        headers.append("Content-Type: application/json")
        body = JSON.stringify(payload)

    var start_err := req.request(url, headers, method, body)
    if start_err != OK:
        req.queue_free()
        _diag_log("HTTP: request start failed err=" + str(start_err) + " url=" + url.replace(BASE_URL, "<BASE>"))
        return {
            "ok": false,
            "error": "Impossible de démarrer la requête YUGITO.",
            "_http_code": 0,
            "_request_result": -1,
        }

    var slow_notice_sent := false
    var mark_30_sent := false
    var mark_60_sent := false

    while not bool(state.get("done", false)):
        if not _busy:
            req.cancel_request()
            req.queue_free()
            _diag_log("HTTP: cancelled because auth flow is no longer active")
            return {"ok":false, "error":"Connexion Google annulée.", "_http_code":0, "_request_result":-1}

        var elapsed_ms := Time.get_ticks_msec() - started_ms

        if show_coldstart_notice and not slow_notice_sent and elapsed_ms >= int(COLDSTART_NOTICE_AFTER_SECONDS * 1000.0):
            slow_notice_sent = true
            auth_progress.emit("Réveil du serveur YUGITO… Google s'ouvrira automatiquement.")
            _diag_log("HTTP: backend response slow • possible Render cold start")

        if not mark_30_sent and elapsed_ms >= 30000:
            mark_30_sent = true
            _diag_log("HTTP: still waiting after 30s url=" + url.replace(BASE_URL, "<BASE>"))

        if not mark_60_sent and elapsed_ms >= 60000:
            mark_60_sent = true
            _diag_log("HTTP: still waiting after 60s url=" + url.replace(BASE_URL, "<BASE>"))

        if elapsed_ms > int(timeout_seconds * 1000.0):
            req.cancel_request()
            req.queue_free()
            _diag_log("HTTP: timeout after=" + str(timeout_seconds) + "s url=" + url.replace(BASE_URL, "<BASE>"))
            return {
                "ok": false,
                "error": "Le serveur YUGITO ne répond pas assez vite.",
                "_http_code": 0,
                "_request_result": HTTPRequest.RESULT_TIMEOUT,
            }

        await get_tree().create_timer(0.05).timeout

    var result_code := int(state.get("result", -1))
    var http_code := int(state.get("http", 0))
    var raw: PackedByteArray = state.get("body", PackedByteArray())
    req.queue_free()

    _diag_log(
        "HTTP: completed result=" + str(result_code)
        + " http=" + str(http_code)
        + " elapsed_ms=" + str(Time.get_ticks_msec() - started_ms)
        + " url=" + url.replace(BASE_URL, "<BASE>")
    )

    if result_code != HTTPRequest.RESULT_SUCCESS:
        return {
            "ok": false,
            "error": "Serveur YUGITO injoignable.",
            "_http_code": http_code,
            "_request_result": result_code,
        }

    var parsed = JSON.parse_string(raw.get_string_from_utf8())
    var out: Dictionary = parsed as Dictionary if parsed is Dictionary else {}
    out["_http_code"] = http_code
    out["_request_result"] = result_code

    if http_code < 200 or http_code >= 300:
        out["ok"] = false
        if not out.has("error"):
            out["error"] = "Erreur réseau YUGITO (HTTP %d)." % http_code

    return out
