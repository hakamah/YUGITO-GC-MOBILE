extends Node

signal balance_changed(new_balance: int)
signal settlement_done(result: Dictionary)

const SAVE_PATH := "user://yugito_rewards_v1.json"

const SOLO_WIN_YT := 10
const SOLO_LOSS_YT := 0
const MULTI_WIN_YT := 30
const MULTI_LOSS_YT := 10

# Une défaite doit être une vraie partie jouée pour donner les 10 YT.
const MIN_CLEAN_SECONDS := 90
const MIN_CLEAN_TURNS := 4

# Anti-farm même adversaire : fenêtre glissante de 6 h.
# 1-3 matchs : 100 %, 4e : 50 %, 5e : 25 %, 6e+ : 0 %.
const REPEAT_WINDOW_SECONDS := 21600

# 3 parties multijoueur propres font redescendre un niveau d'abandon.
const CLEAN_MATCHES_TO_REDUCE_PENALTY := 3
const MAX_ABANDON_TIER := 8

var yt_balance: int = 0
var abandon_tier: int = 0
var clean_matches_since_abandon: int = 0
var opponent_history: Dictionary = {}
var settlements_seen: Dictionary = {}

func _ready() -> void:
    _load()

func balance() -> int:
    return yt_balance

func penalty_tier() -> int:
    return abandon_tier

func penalty_weight() -> int:
    if abandon_tier <= 0:
        return 0
    return 1 << mini(abandon_tier - 1, 20)

func clean_progress() -> int:
    return clean_matches_since_abandon

func settle_solo(victory: bool, match_id: String = "") -> Dictionary:
    var unique_id: String = _normalized_match_id(match_id, "solo")
    if _already_settled(unique_id):
        return {"ok":false,"duplicate":true,"yt":0,"message":"Récompense déjà attribuée."}

    var reward: int = SOLO_WIN_YT if victory else SOLO_LOSS_YT
    _mark_settled(unique_id)
    _add_yt(reward)

    var result: Dictionary = {
        "ok":true,
        "mode":"solo",
        "victory":victory,
        "yt":reward,
        "elo_delta":0,
        "balance":yt_balance,
        "message":"+%d YT" % reward if reward > 0 else "0 YT"
    }
    _save()
    settlement_done.emit(result)
    return result

func settle_multiplayer(
    mode: String,
    victory: bool,
    opponent_key: String,
    clean_completed: bool,
    abandoned: bool,
    duration_seconds: float,
    turns: int,
    player_elo: int,
    opponent_elo: int,
    player_stars: float,
    opponent_stars: float,
    match_id: String = ""
) -> Dictionary:
    var normalized_mode: String = "ranked" if mode == "ranked" else "classic"
    var unique_id: String = _normalized_match_id(match_id, normalized_mode)
    if _already_settled(unique_id):
        return {"ok":false,"duplicate":true,"yt":0,"elo_delta":0,"message":"Match déjà réglé."}

    _mark_settled(unique_id)

    var valid_clean_loss: bool = (
        clean_completed
        and not abandoned
        and duration_seconds >= float(MIN_CLEAN_SECONDS)
        and turns >= MIN_CLEAN_TURNS
    )

    var base_reward: int = MULTI_WIN_YT if victory else MULTI_LOSS_YT

    # Un abandon/déconnexion fautive donne toujours 0 YT au perdant.
    if not victory and (abandoned or not valid_clean_loss):
        base_reward = 0

    # Une victoire peut être payée même si l'autre joueur abandonne :
    # on ne punit pas le gagnant pour le ragequit adverse.
    var repeat_multiplier: float = _repeat_multiplier(opponent_key)
    var final_reward: int = int(round(float(base_reward) * repeat_multiplier))

    var elo_delta: int = 0
    if normalized_mode == "ranked":
        elo_delta = calculate_ranked_delta(
            victory,
            player_elo,
            opponent_elo,
            player_stars,
            opponent_stars
        )

    if abandoned and not victory:
        _record_abandon()
    elif clean_completed:
        _record_clean_match()

    if clean_completed or victory:
        _record_opponent_match(opponent_key)

    _add_yt(final_reward)

    var result: Dictionary = {
        "ok":true,
        "mode":normalized_mode,
        "victory":victory,
        "yt":final_reward,
        "yt_base":base_reward,
        "repeat_multiplier":repeat_multiplier,
        "elo_delta":elo_delta,
        "abandon_tier":abandon_tier,
        "abandon_weight":penalty_weight(),
        "clean_progress":clean_matches_since_abandon,
        "balance":yt_balance,
        "loss_reward_valid":valid_clean_loss,
        "message":_settlement_message(final_reward, elo_delta, normalized_mode, repeat_multiplier, abandoned)
    }
    _save()
    settlement_done.emit(result)
    return result

func calculate_ranked_delta(
    victory: bool,
    player_elo: int,
    opponent_elo: int,
    player_stars: float,
    opponent_stars: float
) -> int:
    var expected: float = 1.0 / (1.0 + pow(10.0, float(opponent_elo - player_elo) / 400.0))
    var raw: float

    if victory:
        raw = 40.0 * (1.0 - expected)
        # Bonus si on gagne avec un deck moins étoilé ; malus si plus lourd.
        raw += (opponent_stars - player_stars) * 2.5
    else:
        raw = 40.0 * expected
        # La perte suit la même logique miroir.
        raw += (player_stars - opponent_stars) * 2.5

    var delta: int = clampi(int(round(raw)), 1, 60)
    return delta if victory else -delta

func register_abandon_without_settlement() -> void:
    _record_abandon()
    _save()

func _record_abandon() -> void:
    abandon_tier = mini(MAX_ABANDON_TIER, abandon_tier + 1)
    clean_matches_since_abandon = 0

func _record_clean_match() -> void:
    if abandon_tier <= 0:
        clean_matches_since_abandon = 0
        return
    clean_matches_since_abandon += 1
    if clean_matches_since_abandon >= CLEAN_MATCHES_TO_REDUCE_PENALTY:
        abandon_tier = maxi(0, abandon_tier - 1)
        clean_matches_since_abandon = 0

func _repeat_multiplier(opponent_key: String) -> float:
    var key: String = opponent_key.strip_edges().to_lower()
    if key.is_empty():
        return 1.0

    var now: int = int(Time.get_unix_time_from_system())
    var history: Array = opponent_history.get(key,[]) as Array
    var recent_count: int = 0
    for raw: Variant in history:
        if now - int(raw) <= REPEAT_WINDOW_SECONDS:
            recent_count += 1

    if recent_count <= 2:
        return 1.0
    if recent_count == 3:
        return 0.50
    if recent_count == 4:
        return 0.25
    return 0.0

func _record_opponent_match(opponent_key: String) -> void:
    var key: String = opponent_key.strip_edges().to_lower()
    if key.is_empty():
        return
    var now: int = int(Time.get_unix_time_from_system())
    var history: Array = opponent_history.get(key,[]) as Array
    var cleaned: Array = []
    for raw: Variant in history:
        if now - int(raw) <= REPEAT_WINDOW_SECONDS:
            cleaned.append(int(raw))
    cleaned.append(now)
    opponent_history[key] = cleaned

func _settlement_message(yt: int, elo_delta: int, mode: String, multiplier: float, abandoned: bool) -> String:
    var parts: Array[String] = []
    parts.append("+%d YT" % yt if yt > 0 else "0 YT")
    if mode == "ranked":
        parts.append(("%+d ELO" % elo_delta))
    if abandoned:
        parts.append("abandon")
    elif multiplier < 1.0:
        parts.append("anti-farm ×%.2f" % multiplier)
    return " • ".join(parts)

func _add_yt(amount: int) -> void:
    if amount <= 0:
        return
    yt_balance = maxi(0,yt_balance + amount)
    balance_changed.emit(yt_balance)

func _normalized_match_id(match_id: String, mode: String) -> String:
    var clean: String = match_id.strip_edges()
    if not clean.is_empty():
        return clean
    return "%s-%d-%s" % [mode,int(Time.get_unix_time_from_system()),_random_hex(6)]

func _already_settled(match_id: String) -> bool:
    return bool(settlements_seen.get(match_id,false))

func _mark_settled(match_id: String) -> void:
    settlements_seen[match_id] = true
    # Garde une taille bornée.
    if settlements_seen.size() > 500:
        var keys: Array = settlements_seen.keys()
        for i: int in range(mini(100,keys.size())):
            settlements_seen.erase(keys[i])

func _random_hex(bytes_count: int) -> String:
    return Crypto.new().generate_random_bytes(bytes_count).hex_encode()

func _save() -> void:
    var payload: Dictionary = {
        "version":1,
        "yt_balance":yt_balance,
        "abandon_tier":abandon_tier,
        "clean_matches_since_abandon":clean_matches_since_abandon,
        "opponent_history":opponent_history,
        "settlements_seen":settlements_seen
    }
    var file: FileAccess = FileAccess.open(SAVE_PATH,FileAccess.WRITE)
    if file != null:
        file.store_string(JSON.stringify(payload))

func _load() -> void:
    if not FileAccess.file_exists(SAVE_PATH):
        return
    var file: FileAccess = FileAccess.open(SAVE_PATH,FileAccess.READ)
    if file == null:
        return
    var parsed: Variant = JSON.parse_string(file.get_as_text())
    if typeof(parsed) != TYPE_DICTIONARY:
        return
    var data: Dictionary = parsed as Dictionary
    yt_balance = maxi(0,int(data.get("yt_balance",0)))
    abandon_tier = clampi(int(data.get("abandon_tier",0)),0,MAX_ABANDON_TIER)
    clean_matches_since_abandon = clampi(int(data.get("clean_matches_since_abandon",0)),0,CLEAN_MATCHES_TO_REDUCE_PENALTY-1)
    opponent_history = data.get("opponent_history",{}) as Dictionary
    settlements_seen = data.get("settlements_seen",{}) as Dictionary
