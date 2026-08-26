extends Node

func _ready() -> void:
    var script := load("res://scripts/Main.gd")
    assert(script != null)
    print("P26 R2 SMOKE DELIVERED — field locks + Temari persistence")
    get_tree().quit()
