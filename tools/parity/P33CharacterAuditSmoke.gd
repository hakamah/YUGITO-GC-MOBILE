extends Node
# Smoke P33 : points critiques du bloc 217→226 + hotfix Ino/liens.
func _ready() -> void:
    var battle = get_tree().get_first_node_in_group("battle")
    if battle == null:
        print("P33 smoke: battle absent (scene non chargee)")
        return
    print("P33 smoke ready: character audit III")
