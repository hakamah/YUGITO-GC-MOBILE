extends Node

signal profile_changed(profile: Dictionary)
signal auth_state_changed(state: String, message: String)

const PROFILE_CACHE_PATH: String = "user://yugito_profile_cache.json"
const DEFAULT_ELO: int = 100

const AUTH_GOOGLE_REQUIRED: String = "google_required"
const AUTH_CONNECTING: String = "connecting"
const AUTH_PSEUDO_REQUIRED: String = "pseudo_required"
const AUTH_CONNECTED: String = "connected"
const AUTH_OFFLINE_CACHE: String = "offline_cache"
const AUTH_ERROR: String = "error"

var account_id: String = ""
var pseudo: String = ""
var email: String = ""

var elo: int = DEFAULT_ELO
var ranked_matches: int = 0
var wins: int = 0
var losses: int = 0
var best_elo: int = DEFAULT_ELO

var auth_state: String = AUTH_GOOGLE_REQUIRED
var auth_message: String = "Connexion Google requise"
var last_sync_unix: int = 0
var profile_source: String = "none"

func _ready() -> void:
    _load_profile_cache()

func display_name() -> String:
    var clean: String = pseudo.strip_edges()
    return clean if not clean.is_empty() else "Joueur"

func is_connected() -> bool:
    return auth_state == AUTH_CONNECTED and not account_id.is_empty() and not pseudo.is_empty()

func has_cached_identity() -> bool:
    return not account_id.is_empty() or not pseudo.is_empty()

func winrate() -> float:
    if ranked_matches <= 0:
        return 0.0
    return (float(wins) * 100.0) / float(ranked_matches)

func profile() -> Dictionary:
    return {
        "account_id": account_id,
        "pseudo": pseudo,
        "email": email,
        "elo": elo,
        "ranked_matches": ranked_matches,
        "wins": wins,
        "losses": losses,
        "best_elo": best_elo,
        "winrate": winrate(),
        "auth_state": auth_state,
        "auth_message": auth_message,
        "connected": is_connected(),
        "last_sync_unix": last_sync_unix,
        "profile_source": profile_source,
    }

func public_identity_payload() -> Dictionary:
    return {
        "account_id":account_id,
        "pseudo":display_name(),
        "elo":elo,
        "connected":is_connected(),
    }

func server_profile_payload() -> Dictionary:
    # Aucun secret/session token n'est stocké ici. Cette structure est prête
    # pour la synchronisation P47/P48.
    return {
        "elo": elo,
        "ranked_matches": ranked_matches,
        "wins": wins,
        "losses": losses,
        "best_elo": best_elo,
        "winrate": winrate(),
    }

func apply_server_account(account: Dictionary, ranked_profile: Dictionary = {}) -> void:
    var incoming_id: String = str(account.get("account_id","")).strip_edges()
    var same_account: bool = not incoming_id.is_empty() and incoming_id == account_id

    if not same_account and ranked_profile.is_empty():
        ranked_matches = 0
        wins = 0
        losses = 0
        best_elo = DEFAULT_ELO

    account_id = incoming_id if not incoming_id.is_empty() else account_id
    pseudo = str(account.get("pseudo",pseudo)).strip_edges()
    email = str(account.get("email",email)).strip_edges()

    elo = _normalize_elo(int(account.get("elo",ranked_profile.get("elo",elo))))
    ranked_matches = maxi(0,int(ranked_profile.get("ranked_matches",ranked_matches)))
    wins = maxi(0,int(ranked_profile.get("wins",wins)))
    losses = maxi(0,int(ranked_profile.get("losses",losses)))
    if ranked_matches < wins + losses:
        ranked_matches = wins + losses
    best_elo = maxi(elo,_normalize_elo(int(ranked_profile.get("best_elo",best_elo))))

    auth_state = AUTH_CONNECTED
    auth_message = "Compte Google YUGITO connecté"
    last_sync_unix = int(Time.get_unix_time_from_system())
    profile_source = "server"
    _save_profile_cache()
    _emit_all()

func apply_ranked_profile(ranked_profile: Dictionary) -> void:
    elo = _normalize_elo(int(ranked_profile.get("elo",elo)))
    ranked_matches = maxi(0,int(ranked_profile.get("ranked_matches",ranked_matches)))
    wins = maxi(0,int(ranked_profile.get("wins",wins)))
    losses = maxi(0,int(ranked_profile.get("losses",losses)))
    if ranked_matches < wins + losses:
        ranked_matches = wins + losses
    best_elo = maxi(elo,_normalize_elo(int(ranked_profile.get("best_elo",best_elo))))
    last_sync_unix = int(Time.get_unix_time_from_system())
    if is_connected():
        profile_source = "server"
    _save_profile_cache()
    profile_changed.emit(profile())

func register_ranked_result(victory: bool, new_elo: int) -> void:
    ranked_matches += 1
    if victory:
        wins += 1
    else:
        losses += 1
    elo = _normalize_elo(new_elo)
    best_elo = maxi(best_elo,elo)
    _save_profile_cache()
    profile_changed.emit(profile())

func begin_auth(message: String = "Connexion au serveur de comptes YUGITO…") -> void:
    auth_state = AUTH_CONNECTING
    auth_message = message
    auth_state_changed.emit(auth_state,auth_message)
    profile_changed.emit(profile())

func require_pseudo(account: Dictionary) -> void:
    account_id = str(account.get("account_id","")).strip_edges()
    email = str(account.get("email","")).strip_edges()
    pseudo = ""
    auth_state = AUTH_PSEUDO_REQUIRED
    auth_message = "Google est connecté • choisis ton pseudo YUGITO"
    profile_source = "server_pending"
    _save_profile_cache()
    _emit_all()

func require_google(message: String = "Connexion Google requise") -> void:
    auth_state = AUTH_GOOGLE_REQUIRED
    auth_message = message
    profile_source = "cache" if has_cached_identity() else "none"
    _save_profile_cache()
    _emit_all()

func set_auth_error(message: String) -> void:
    auth_state = AUTH_ERROR
    auth_message = message.strip_edges()
    auth_state_changed.emit(auth_state,auth_message)
    profile_changed.emit(profile())

func mark_server_unavailable(message: String = "Serveur YUGITO indisponible") -> void:
    if has_cached_identity():
        auth_state = AUTH_OFFLINE_CACHE
        auth_message = message + " • profil local affiché"
    else:
        auth_state = AUTH_GOOGLE_REQUIRED
        auth_message = message
    profile_changed.emit(profile())
    auth_state_changed.emit(auth_state,auth_message)

func disconnect_session_keep_profile() -> void:
    auth_state = AUTH_OFFLINE_CACHE if has_cached_identity() else AUTH_GOOGLE_REQUIRED
    auth_message = "Session déconnectée • profil local conservé" if has_cached_identity() else "Connexion Google requise"
    profile_source = "cache" if has_cached_identity() else "none"
    _save_profile_cache()
    _emit_all()

func clear_cached_identity() -> void:
    account_id = ""
    pseudo = ""
    email = ""
    elo = DEFAULT_ELO
    ranked_matches = 0
    wins = 0
    losses = 0
    best_elo = DEFAULT_ELO
    auth_state = AUTH_GOOGLE_REQUIRED
    auth_message = "Connexion Google requise"
    last_sync_unix = 0
    profile_source = "none"
    if FileAccess.file_exists(PROFILE_CACHE_PATH):
        DirAccess.remove_absolute(ProjectSettings.globalize_path(PROFILE_CACHE_PATH))
    _emit_all()

func validate_pseudo(value: String) -> Dictionary:
    var clean: String = value.strip_edges()
    if clean.length() < 3 or clean.length() > 20:
        return {"ok":false,"message":"Le pseudo doit contenir entre 3 et 20 caractères.","clean":clean}
    if clean.begins_with("-") or clean.begins_with("_") or clean.ends_with("-") or clean.ends_with("_"):
        return {"ok":false,"message":"Le pseudo ne peut pas commencer ou finir par - ou _.","clean":clean}
    var regex := RegEx.new()
    regex.compile("^[A-Za-zÀ-ÖØ-öø-ÿ0-9 _-]+$")
    if regex.search(clean) == null:
        return {"ok":false,"message":"Utilise uniquement lettres, chiffres, espaces, - et _.","clean":clean}
    if clean.begins_with(" ") or clean.ends_with(" "):
        return {"ok":false,"message":"Le pseudo ne peut pas commencer ou finir par un espace.","clean":clean}
    while clean.find("  ") >= 0:
        clean = clean.replace("  "," ")
    return {"ok":true,"message":"","clean":clean}

func _normalize_elo(value: int) -> int:
    return maxi(0,value)

func _load_profile_cache() -> void:
    if not FileAccess.file_exists(PROFILE_CACHE_PATH):
        return
    var file := FileAccess.open(PROFILE_CACHE_PATH,FileAccess.READ)
    if file == null:
        return
    var parsed: Variant = JSON.parse_string(file.get_as_text())
    if not (parsed is Dictionary):
        return
    var data: Dictionary = parsed as Dictionary

    account_id = str(data.get("account_id","")).strip_edges()
    pseudo = str(data.get("pseudo","")).strip_edges()
    email = str(data.get("email","")).strip_edges()
    elo = _normalize_elo(int(data.get("elo",DEFAULT_ELO)))
    ranked_matches = maxi(0,int(data.get("ranked_matches",0)))
    wins = maxi(0,int(data.get("wins",0)))
    losses = maxi(0,int(data.get("losses",0)))
    if ranked_matches < wins + losses:
        ranked_matches = wins + losses
    best_elo = maxi(elo,_normalize_elo(int(data.get("best_elo",elo))))
    last_sync_unix = int(data.get("last_sync_unix",0))
    profile_source = "cache"

    if has_cached_identity():
        auth_state = AUTH_OFFLINE_CACHE
        auth_message = "Profil YUGITO local chargé • connexion Google à vérifier"

func _save_profile_cache() -> void:
    var file := FileAccess.open(PROFILE_CACHE_PATH,FileAccess.WRITE)
    if file == null:
        return
    # Cache volontairement NON SECRET : aucun jeton Google/YUGITO ici.
    file.store_string(JSON.stringify({
        "account_id":account_id,
        "pseudo":pseudo,
        "email":email,
        "elo":elo,
        "ranked_matches":ranked_matches,
        "wins":wins,
        "losses":losses,
        "best_elo":best_elo,
        "last_sync_unix":last_sync_unix,
    }))

func _emit_all() -> void:
    profile_changed.emit(profile())
    auth_state_changed.emit(auth_state,auth_message)
