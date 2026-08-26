extends SceneTree

const CardActor = preload("res://scripts/CardActor.gd")
const BattleScript = preload("res://scripts/Main.gd")

func _fail(message: String) -> void:
    push_error("[P18 SMOKE FAIL] " + message)
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
    print("YUGITO 09 / P18 — control + start-turn headless smoke")

    var bee = _actor("killer_bee", 1, 0, "ally")
    bee.apply_disable(3, "smoke")
    _require(bee.can_act(), "Killer Bee perd son tour sous STUN")
    bee.status_tags["sealed_turns"] = 5
    _require(not bee.can_act(), "Le Scellement Kushina ne bloque pas Killer Bee")

    var madara = _actor("madara", 2, 1, "ally")
    madara.apply_disable(3, "smoke")
    madara.status_tags["sealed_turns"] = 5
    madara.status_tags["sai_prison"] = 3
    _require(madara.can_act(), "Madara n'ignore pas les contrôles incapacitants")
    print("[OK] Killer Bee / Madara contrôles")

    var battle = BattleScript.new()
    battle.battle_log_label = Label.new()
    var sai = _actor("sai", 3, 0, "enemy")
    var bee2 = _actor("killer_bee", 4, 1, "ally")
    battle.card_actors.append(sai)
    battle.card_actors.append(bee2)
    battle._finish_special_descriptor(sai, bee2, "SMOKE SAI", {})
    _require(bee2.disabled_turns == 0 and int(bee2.status_tags.get("sai_prison",0)) == 0,
        "Sai emprisonne encore Killer Bee")
    print("[OK] Sai -> Killer Bee immunité")

    var turn_battle = BattleScript.new()
    turn_battle.battle_log_label = Label.new()
    var tsunade = _actor("tsunade", 10, 0, "ally")
    var enemy = _actor("tenten", 11, 0, "enemy")
    tsunade.hp = 700
    turn_battle.card_actors.append(tsunade)
    turn_battle.card_actors.append(enemy)
    turn_battle._start_team_turn("ally")
    _require(tsunade.hp == 900, "Tsunade ne soigne pas +200 sous 50 %")
    print("[OK] Tsunade début de tour")

    print("ALL P18 GODOT CONTROL SMOKES PASSED")
    quit(0)
