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
var owned_cards: Dictionary = {}
var server_weekly_rotation: Dictionary = {}

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

func is_base_unlocked(stars: float) -> bool:
    return stars <= 3.0

func is_permanently_owned(card_id: String, stars: float) -> bool:
    if is_base_unlocked(stars):
        return true
    return bool(owned_cards.get(card_id,false))

func set_server_weekly_rotation(payload: Dictionary) -> bool:
    if not _validate_server_weekly_rotation(payload):
        return false
    server_weekly_rotation = payload.duplicate(true)
    _save()
    return true

func clear_server_weekly_rotation() -> void:
    server_weekly_rotation.clear()
    _save()

func weekly_rotation_source() -> String:
    return "SERVER" if _server_rotation_is_usable() else "INDISPONIBLE"

func weekly_rotation_week_key() -> String:
    if not _server_rotation_is_usable():
        return ""
    return str(server_weekly_rotation.get("week_key",""))

func weekly_rotation_count() -> int:
    if not _server_rotation_is_usable():
        return 0
    var counts: Dictionary = server_weekly_rotation.get("counts",{}) as Dictionary
    return (
        int(counts.get("3.5",0))
        + int(counts.get("4.0",0))
        + int(counts.get("4.5",0))
        + int(counts.get("5.0",0))
    )

func weekly_free_ids(catalog: Array[Dictionary]) -> Array[String]:
    if not _server_rotation_is_usable():
        return []

    var counts: Dictionary = server_weekly_rotation.get("counts",{}) as Dictionary
    var seeds: Dictionary = server_weekly_rotation.get("seeds",{}) as Dictionary
    var rarities: Array[String] = ["3.5","4.0","4.5","5.0"]
    var result: Array[String] = []

    for rarity_key: String in rarities:
        var rarity: float = float(rarity_key)
        var count: int = maxi(0,int(counts.get(rarity_key,0)))
        var seed: String = str(seeds.get(rarity_key,""))
        if count <= 0 or seed.is_empty():
            continue

        var pool: Array[String] = []
        for data: Dictionary in catalog:
            if not is_equal_approx(float(data.get("stars",0.0)),rarity):
                continue
            var cid: String = str(data.get("id",""))
            if not cid.is_empty():
                pool.append(cid)

        pool.sort_custom(func(a: String,b: String) -> bool:
            return _weekly_card_rank(seed,a) < _weekly_card_rank(seed,b)
        )

        for i: int in range(mini(count,pool.size())):
            if not result.has(pool[i]):
                result.append(pool[i])

    return result

func is_weekly_free(card_id: String, catalog: Array[Dictionary]) -> bool:
    return weekly_free_ids(catalog).has(card_id)

func _weekly_card_rank(seed: String, card_id: String) -> String:
    var ctx := HashingContext.new()
    ctx.start(HashingContext.HASH_SHA256)
    ctx.update(("%s|%s|YUGITO-WEEKLY-V1" % [seed,card_id]).to_utf8_buffer())
    return ctx.finish().hex_encode()

func _server_rotation_is_usable() -> bool:
    if server_weekly_rotation.is_empty():
        return false
    if not _validate_server_weekly_rotation(server_weekly_rotation):
        return false
    var expires_at: int = int(server_weekly_rotation.get("next_rotation_unix",0))
    if expires_at <= 0:
        return false
    # Petite tolérance réseau, mais jamais une nouvelle rotation locale.
    return int(Time.get_unix_time_from_system()) < expires_at + 6 * 60 * 60

func _validate_server_weekly_rotation(payload: Dictionary) -> bool:
    if not bool(payload.get("ok",false)):
        return false
    if int(payload.get("version",0)) != 1:
        return false
    if str(payload.get("week_key","")).is_empty():
        return false
    if int(payload.get("next_rotation_unix",0)) <= 0:
        return false

    var counts: Dictionary = payload.get("counts",{}) as Dictionary
    var seeds: Dictionary = payload.get("seeds",{}) as Dictionary
    var expected: Dictionary = {
        "3.5":8,
        "4.0":6,
        "4.5":4,
        "5.0":4,
    }
    for rarity_key: String in expected.keys():
        if int(counts.get(rarity_key,-1)) != int(expected[rarity_key]):
            return false
        if str(seeds.get(rarity_key,"")).length() < 16:
            return false
    return true

func is_currently_owned(card_id: String, stars: float, catalog: Array[Dictionary]) -> bool:
    return is_permanently_owned(card_id,stars) or is_weekly_free(card_id,catalog)

func card_ownership_status(card_id: String, stars: float, catalog: Array[Dictionary]) -> String:
    if is_base_unlocked(stars):
        return "base"
    if bool(owned_cards.get(card_id,false)):
        return "permanent"
    if is_weekly_free(card_id,catalog):
        return "weekly"
    return "missing"

func card_ownership_label(card_id: String, stars: float, catalog: Array[Dictionary]) -> String:
    match card_ownership_status(card_id,stars,catalog):
        "base":
            return "DÉBLOQUÉE DE BASE"
        "permanent":
            return "POSSÉDÉE DÉFINITIVEMENT"
        "weekly":
            return "GRATUITE CETTE SEMAINE"
        _:
            return "NON POSSÉDÉE"

func purchase_card(card_id: String, stars: float, price: int) -> Dictionary:
    if is_permanently_owned(card_id,stars):
        return {"ok":false,"message":"Carte déjà possédée définitivement.","balance":yt_balance}
    if price <= 0:
        owned_cards[card_id] = true
        _save()
        return {"ok":true,"message":"Carte obtenue définitivement.","balance":yt_balance}
    if yt_balance < price:
        return {"ok":false,"message":"YT insuffisants.","balance":yt_balance}
    yt_balance -= price
    owned_cards[card_id] = true
    balance_changed.emit(yt_balance)
    _save()
    return {"ok":true,"message":"Achat réussi • -%d YT" % price,"balance":yt_balance}

func owned_card_ids() -> Array[String]:
    var result: Array[String] = []
    for key: Variant in owned_cards.keys():
        if bool(owned_cards[key]):
            result.append(str(key))
    result.sort()
    return result

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
        "settlements_seen":settlements_seen,
        "owned_cards":owned_cards,
        "server_weekly_rotation":server_weekly_rotation
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
    owned_cards = data.get("owned_cards",{}) as Dictionary
    server_weekly_rotation = data.get("server_weekly_rotation",{}) as Dictionary
