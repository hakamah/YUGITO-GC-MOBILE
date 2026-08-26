extends Node

const SynergyDB = preload("res://scripts/SynergyDB.gd")

func _ready() -> void:
    assert(is_equal_approx(SynergyDB.bonus_for("naruto", ["naruto","sasuke","sakura"]), 0.20))
    assert(is_equal_approx(SynergyDB.bonus_for("naruto", ["naruto","sasuke"]), 0.125))
    assert(is_equal_approx(SynergyDB.bonus_for("kisame", ["kisame","itachi"]), 0.15))
    assert(is_equal_approx(SynergyDB.bonus_for("zetsu", ["zetsu","deidara"]), 0.15))
    assert(is_equal_approx(SynergyDB.bonus_for("deidara", ["zetsu","deidara"]), 0.15))
    print("P36 SYNERGY SMOKE PASSED")
    get_tree().quit()
