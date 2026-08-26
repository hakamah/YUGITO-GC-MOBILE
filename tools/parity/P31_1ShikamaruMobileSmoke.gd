extends SceneTree

const CardActor = preload("res://scripts/CardActor.gd")
const BattleScript = preload("res://scripts/Main.gd")

func _require(condition: bool, message: String) -> void:
    if not condition:
        push_error("[P31.1 SHIKAMARU FAIL] " + message)
        quit(1)

func _card(card_id: String, uid: int, seed: int, team: String):
    var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/cards.json"))
    for item: Variant in parsed:
        if item is Dictionary and str((item as Dictionary).get("id", "")) == card_id:
            var actor = CardActor.new()
            actor.setup_logic_only((item as Dictionary).duplicate(true), seed, team)
            actor.battle_uid = uid
            return actor
    return null

func _initialize() -> void:
    var battle = BattleScript.new()
    root.add_child(battle)
    battle.battle_log_label = Label.new()
    var shika = _card("shikamaru", 10, 0, "ally")
    var free = _card("sakura", 20, 0, "enemy")
    var a = _card("shino", 21, 1, "enemy")
    var b = _card("karin", 22, 2, "enemy")
    battle.card_actors.append_array([shika, free, a, b])
    battle.resolving_delayed_action = true
    var linked: int = battle._apply_shikamaru_shadows(shika, free)
    _require(linked == 2, "A2 ne lie pas les deux autres cibles")
    _require(int(a.status_tags.get("shadow_turns",0)) == 3, "Ombres A2 absentes")
    _require(not a.can_act() and not b.can_act(), "Ombres ne bloquent pas l'action")
    _require(int(free.status_tags.get("shadow_turns",0)) == 0, "cible libre touchée")
    print("ALL P31.1 SHIKAMARU MOBILE SMOKES PASSED")
    quit(0)
