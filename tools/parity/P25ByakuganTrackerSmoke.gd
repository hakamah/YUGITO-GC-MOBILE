extends SceneTree

func _initialize() -> void:
    var main_source := FileAccess.get_file_as_string("res://scripts/Main.gd")
    var required := [
        "byakugan_tracker_plan",
        "_arm_tracker_from_descriptor",
        "tracker_id",
        "byakugan_tracker_target",
        "forced_reserve_choice"
    ]
    for token in required:
        if not main_source.contains(token):
            push_error("P25 smoke missing: %s" % token)
            quit(1)
            return
    print("P25 BYAKUGAN TRACKER SMOKE OK")
    quit(0)
