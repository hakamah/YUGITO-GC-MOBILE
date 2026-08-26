extends SceneTree

const CardActor = preload("res://scripts/CardActor.gd")
const BattleScript = preload("res://scripts/Main.gd")

func _fail(message: String) -> void:
    push_error("[P19 SMOKE FAIL] " + message)
    quit(1)

func _require(condition: bool, message: String) -> void:
    if not condition:
        _fail(message)

func _card_by_id(card_id: String) -> Dictionary:
    var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/cards.json"))
    if not (parsed is Array):
        return {}
    for item: Variant in parsed:
        if item is Dictionary and str((item as Dictionary).get("id", "")) == card_id:
            return (item as Dictionary).duplicate(true)
    return {}

func _actor(card_id: String, uid: int, seed: int, team: String):
    var data: Dictionary = _card_by_id(card_id)
    _require(not data.is_empty(), "Carte absente : " + card_id)
    var actor = CardActor.new()
    actor.setup_logic_only(data, seed, team)
    actor.battle_uid = uid
    return actor

func _initialize() -> void:
    print("YUGITO 09 / P19 — KO + survival headless smoke")

    var battle = BattleScript.new()
    battle.battle_log_label = Label.new()

    # Mort définitive d'une source : les liens terrain sont retirés immédiatement.
    var hidan = _actor("hidan", 1, 0, "ally")
    var kisame = _actor("kisame", 2, 1, "ally")
    var victim_jashin = _actor("tenten", 3, 0, "enemy")
    var victim_prison = _actor("shino", 4, 1, "enemy")
    victim_jashin.status_tags["doom_source_uid"] = hidan.battle_uid
    victim_jashin.status_tags["doom_source_team"] = "ally"
    victim_jashin.status_tags["doom_turns"] = 5
    victim_prison.status_tags["kisame_prisoned_by_uid"] = kisame.battle_uid
    battle.card_actors.append_array([hidan, kisame, victim_jashin, victim_prison])
    battle._cleanup_context_links_for_departure(hidan)
    _require(not victim_jashin.status_tags.has("doom_source_uid") and not victim_jashin.status_tags.has("doom_turns"),
        "Jashin reste actif après disparition définitive de Hidan")
    battle._cleanup_context_links_for_departure(kisame)
    _require(not victim_prison.status_tags.has("kisame_prisoned_by_uid"),
        "Prison aqueuse reste active après disparition définitive de Kisame")
    print("[OK] nettoyage immédiat Jashin / Prison aqueuse")

    # Chidori absolu traverse Izanagi ; Mifune conserve Izanagi.
    var sasuke = _actor("sasuke", 10, 0, "ally")
    var danzo_abs = _actor("danzo", 11, 0, "enemy")
    danzo_abs.hp = 1
    battle.card_actors.append(sasuke)
    battle.card_actors.append(danzo_abs)
    var chidori: Dictionary = battle._apply_attack_damage(sasuke, danzo_abs, 500, "ninjutsu", true, true, false, true, true, false, true)
    _require(bool(chidori.get("killed", false)) and not bool(danzo_abs.status_tags.get("survival_used", false)),
        "Chidori ne traverse pas Izanagi")

    var mifune = _actor("mifune", 12, 1, "ally")
    var danzo_mifune = _actor("danzo", 13, 1, "enemy")
    danzo_mifune.hp = 1
    battle.card_actors.append(mifune)
    battle.card_actors.append(danzo_mifune)
    var trancheur: Dictionary = battle._apply_attack_damage(mifune, danzo_mifune, 500, "taijutsu", true, false, false, true, true, false, true)
    _require(not bool(trancheur.get("killed", false)) and bool(danzo_mifune.status_tags.get("survival_used", false)) and danzo_mifune.hp == 1,
        "Mifune traverse à tort Izanagi")
    print("[OK] Chidori absolu / Mifune survies")

    # Boucliers empilés de Kurenai : Mifune convertit 50 % puis détruit les deux.
    var kurenai = _actor("kurenai", 14, 2, "enemy")
    kurenai.shield = 300
    kurenai.status_tags["kurenai_hidden_shield"] = 600
    var before: int = kurenai.hp
    battle.card_actors.append(kurenai)
    var shield_hit: Dictionary = battle._apply_attack_damage(mifune, kurenai, 500, "taijutsu", true, false, false, true, true, false, true)
    _require(kurenai.shield == 0 and not kurenai.status_tags.has("kurenai_hidden_shield"),
        "Mifune ne détruit pas les deux boucliers")
    _require(before - kurenai.hp == 950 and int(shield_hit.get("hp_damage", 0)) == 950,
        "Conversion 50 % des 900 boucliers incorrecte")
    print("[OK] boucliers empilés Mifune")

    # Surplus + survie : Danzo garde 1 PV mais le joueur prend le surplus ;
    # Ônoki annule l'impact létal et donc le surplus.
    battle.enemy_player_hp = 4000
    var danzo_over = _actor("danzo", 20, 0, "enemy")
    danzo_over.hp = 100
    battle.card_actors.append(danzo_over)
    var over_hit: Dictionary = battle._apply_attack_damage(sasuke, danzo_over, 1000, "taijutsu", false, false, true, false, false, false, true)
    _require(not bool(over_hit.get("killed", false)) and danzo_over.hp == 1 and int(over_hit.get("overflow", 0)) == 900,
        "Danzo ne conserve pas le surplus après Izanagi")
    _require(battle.enemy_player_hp == 3100, "Le surplus Danzo n'atteint pas les PV joueur")

    battle.enemy_player_hp = 4000
    var onoki_over = _actor("onoki", 21, 1, "enemy")
    onoki_over.hp = 100
    battle.card_actors.append(onoki_over)
    var onoki_hit: Dictionary = battle._apply_attack_damage(sasuke, onoki_over, 1000, "taijutsu", false, false, true, false, false, false, true)
    _require(bool(onoki_hit.get("immune", false)) and int(onoki_hit.get("overflow", 0)) == 0 and battle.enemy_player_hp == 4000,
        "Ônoki génère à tort un surplus après son esquive létale")
    print("[OK] surplus joueur + survies")

    print("ALL P19 GODOT KO SMOKES PASSED")
    quit(0)
