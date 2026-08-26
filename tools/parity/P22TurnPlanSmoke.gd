extends SceneTree

const BattleScript = preload("res://scripts/Main.gd")

func _fail(message: String) -> void:
    push_error("[P22 SMOKE FAIL] " + message)
    quit(1)

func _require(condition: bool, message: String) -> void:
    if not condition:
        _fail(message)

func _initialize() -> void:
    print("YUGITO 09 / P22 — Classic turn plan smoke")
    var battle = BattleScript.new()
    _require(battle.has_method("_on_hiraishin_pressed"), "Hiraishin handler absent")
    _require(battle.has_method("_cancel_planned_action"), "annulation A1/A2 absente")
    _require(battle.has_method("_cancel_planned_free"), "annulation Hiraishin absente")
    _require(battle.has_method("_on_direct_attack_pressed"), "attaque directe explicite absente")
    _require(battle.has_method("_finish_direct_attack"), "résolution attaque directe absente")
    print("[OK] handlers du plan Classic présents")
    print("ALL P22 GODOT TURN PLAN SMOKES PASSED")
    quit(0)
