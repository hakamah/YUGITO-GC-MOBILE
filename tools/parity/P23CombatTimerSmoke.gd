extends SceneTree

# Smoke manuel/headless P23. Il vérifie la présence des points d'entrée du vrai
# chrono de combat sans déclencher artificiellement toute une résolution de duel.
func _init() -> void:
    var packed: PackedScene = load("res://Battle.tscn")
    assert(packed != null)
    var battle = packed.instantiate()
    root.add_child(battle)
    await process_frame
    assert(battle.has_method("_reset_phase_timer"))
    assert(battle.has_method("_tick_phase_timer"))
    assert(battle.has_method("_on_phase_timer_expired"))
    assert(battle.has_method("_commit_player_plan"))
    battle._reset_phase_timer()
    assert(absf(float(battle.phase_timer_seconds) - 30.0) < 0.001)
    assert(bool(battle.phase_timer_running))
    battle.phase_timer_seconds = 29.4
    battle._refresh_phase_timer_label()
    assert(battle.phase_timer_label.text == "30 s")
    battle._stop_phase_timer()
    assert(not bool(battle.phase_timer_running))
    print("P23CombatTimerSmoke OK")
    quit(0)
