extends SceneTree

const CardActor = preload("res://scripts/CardActor.gd")
const BattleScript = preload("res://scripts/Main.gd")

func _fail(message: String) -> void:
    push_error("[P20 SMOKE FAIL] " + message)
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
    print("YUGITO 09 / P20 — Classic visual & gameplay smoke")
    var battle = BattleScript.new()
    battle.battle_log_label = Label.new()

    # Choji : la fonction de cible visuelle doit retourner le même garde que le calcul.
    var attacker = _actor("sakura", 1, 0, "ally")
    var victim = _actor("tenten", 2, 0, "enemy")
    var choji = _actor("choji", 3, 1, "enemy")
    battle.card_actors.append_array([attacker, victim, choji])
    var d := {"kind":"attack", "action_id":"taijutsu"}
    _require(battle._descriptor_visual_target(d, attacker, victim) == choji,
        "Choji n'est pas la cible visuelle effective")
    print("[OK] Choji : redirection logique/visuelle commune")

    # Shikamaru : Ombres = vrai verrou indépendant, décrémentable et lié à la source.
    var shikamaru = _actor("shikamaru", 10, 2, "ally")
    var shadowed = _actor("shino", 11, 2, "enemy")
    shadowed.status_tags["shadow_source_uid"] = shikamaru.battle_uid
    shadowed.status_tags["shadow_turns"] = 3
    shadowed.status_tags["shadow_turns_skip_tick"] = true
    _require(not shadowed.can_act(), "Ombres de Shikamaru ne bloquent pas l'action")
    shadowed.tick_own_turn()
    _require(int(shadowed.status_tags.get("shadow_turns",0)) == 3, "premier tick Ombres incorrect")
    shadowed.tick_own_turn()
    _require(int(shadowed.status_tags.get("shadow_turns",0)) == 2, "décompte Ombres incorrect")
    print("[OK] Shikamaru : verrou/durée Ombres")

    # Gengetsu : le clone est une vraie identité de jeu 4800 / 0 / 0 / 0.
    var gengetsu = _actor("gengetsu", 20, 0, "ally")
    gengetsu.status_tags["gengetsu_clone_active"] = true
    gengetsu.status_tags["gengetsu_clone_turns"] = 2
    gengetsu.max_hp = 4800
    gengetsu.hp = 4800
    _require(gengetsu.effective_stat("taijutsu") == 0 and gengetsu.effective_stat("ninjutsu") == 0 and gengetsu.effective_stat("genjutsu") == 0,
        "clone Gengetsu n'est pas à 0/0/0")
    _require(not gengetsu.special_available(), "clone Gengetsu peut lancer une spéciale")
    print("[OK] Gengetsu : état clone jouable/ciblable, arts 0")

    # Ino : le vrai corps possédé est inciblable et garde son instance.
    var ino = _actor("ino", 30, 0, "ally")
    var body = _actor("karui", 31, 0, "enemy")
    ino.status_tags["ino_target_uid"] = body.battle_uid
    ino.status_tags["ino_target"] = body.card_id
    body.status_tags["possessed_by_uid"] = ino.battle_uid
    battle.card_actors.append_array([ino, body])
    _require(body.is_untargetable(), "corps contrôlé par Ino n'est pas inciblable")
    _require(battle._ino_controlled_body(ino) == body, "lien vivant Ino→corps perdu")
    print("[OK] Ino : lien vivant / corps inciblable")

    print("ALL P20 GODOT CLASSIC VISUAL SMOKES PASSED")
    quit(0)
