extends Node
# Smoke P24 à lancer avec Godot 4.x : vérifie les symboles du modal de remplacement.
func _ready() -> void:
    var modal := YugitoReplacementModal.new()
    assert(modal.has_method("show_choices"))
    assert(modal.has_method("_best_timeout_choice_index"))
    assert(modal.has_signal("timeout_choice"))
    print("P24 replacement timeout smoke: OK")
    get_tree().quit()
