extends SceneTree

const CardActor = preload("res://scripts/CardActor.gd")
const BattleScript = preload("res://scripts/Main.gd")

func _fail(message: String) -> void:
    push_error("[P21 SMOKE FAIL] " + message)
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

func _has_bomb_row(actor) -> bool:
    for row: Dictionary in actor.status_lines():
        if str(row.get("text", "")).begins_with("BOMBE"):
            return true
    return false

func _initialize() -> void:
    print("YUGITO 09 / P21 — A2 + secret status smoke")

    # Shikamaru : A1 et A2 appellent le même helper. On l'exécute explicitement
    # dans le contexte A2 pour vérifier cible libre + deux liens 3T.
    var battle = BattleScript.new()
    battle.battle_log_label = Label.new()
    battle.resolving_delayed_action = true
    var shika = _actor("shikamaru", 10, 0, "ally")
    var free = _actor("sakura", 20, 0, "enemy")
    var a = _actor("shino", 21, 1, "enemy")
    var b = _actor("karin", 22, 2, "enemy")
    battle.card_actors.append_array([shika, free, a, b])
    var linked: int = battle._apply_shikamaru_shadows(shika, free)
    _require(linked == 2, "Shikamaru A2 ne lie pas exactement les deux autres Ninjas")
    _require(int(free.status_tags.get("shadow_turns", 0)) == 0, "la cible libre reçoit les Ombres")
    _require(int(a.status_tags.get("shadow_turns", 0)) == 3 and int(b.status_tags.get("shadow_turns", 0)) == 3,
        "les Ombres A2 ne durent pas 3T")
    _require(not a.can_act() and not b.can_act(), "les Ombres A2 n'empêchent pas réellement d'agir")
    print("[OK] Shikamaru : helper commun A1/A2 + cible libre + 3T")

    # Tobi ennemi : ses bombes sur NOS cartes sont secrètes.
    var ally_victim = _actor("gengetsu", 30, 0, "ally")
    ally_victim.status_tags["tobi_bombs_enemy"] = 2
    ally_victim.status_tags["tobi_bombs"] = 2
    _require(ally_victim._visible_tobi_bomb_count() == 0, "bombes du Tobi ennemi révélées au joueur")
    _require(not _has_bomb_row(ally_victim), "badge BOMBE ennemi visible")

    # Nos propres bombes restent visibles sur les cartes adverses.
    var enemy_victim = _actor("shisui", 31, 0, "enemy")
    enemy_victim.status_tags["tobi_bombs_ally"] = 3
    enemy_victim.status_tags["tobi_bombs"] = 3
    _require(enemy_victim._visible_tobi_bomb_count() == 3, "nos propres bombes ne sont plus visibles")
    _require(_has_bomb_row(enemy_victim), "badge de nos bombes absent")
    print("[OK] Tobi : secret asymétrique des bombes")

    # Même secret pour la prédiction armée du Tobi adverse.
    var enemy_tobi = _actor("tobi", 40, 0, "enemy")
    enemy_tobi.status_tags["tobi_prediction_armed"] = true
    _require(not enemy_tobi._visible_tobi_prediction_armed(), "prédiction du Tobi ennemi révélée")
    var ally_tobi = _actor("tobi", 41, 0, "ally")
    ally_tobi.status_tags["tobi_prediction_armed"] = true
    _require(ally_tobi._visible_tobi_prediction_armed(), "notre prédiction Tobi masquée")
    print("[OK] Tobi : prédiction ennemie secrète")

    print("ALL P21 GODOT A2/SECRET STATUS SMOKES PASSED")
    quit(0)
