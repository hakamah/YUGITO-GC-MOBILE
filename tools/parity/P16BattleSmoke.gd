extends SceneTree

const CardActor = preload("res://scripts/CardActor.gd")
const BattleScript = preload("res://scripts/Main.gd")

func _fail(message: String) -> void:
    push_error("[P16 SMOKE FAIL] " + message)
    quit(1)

func _require(condition: bool, message: String) -> void:
    if not condition:
        _fail(message)

func _card_by_id(card_id: String) -> Dictionary:
    var raw: String = FileAccess.get_file_as_string("res://data/cards.json")
    var parsed: Variant = JSON.parse_string(raw)
    if not (parsed is Array):
        return {}
    for item: Variant in parsed:
        if item is Dictionary and str((item as Dictionary).get("id", "")) == card_id:
            return (item as Dictionary).duplicate(true)
    return {}

func _actor(card_id: String, uid: int, slot_seed: int, team: String):
    var data: Dictionary = _card_by_id(card_id)
    _require(not data.is_empty(), "Carte absente : " + card_id)
    var actor = CardActor.new()
    actor.setup_logic_only(data, slot_seed, team)
    actor.battle_uid = uid
    return actor

func _initialize() -> void:
    print("YUGITO 09 / P16 — Battle + Ino headless smoke")

    var battle = BattleScript.new()
    battle.battle_log_label = Label.new()
    battle.turn_counter = 10

    # --------------------------------------------------------------
    # A2 : identité d'abord ; case uniquement après vrai Switch A2.
    # --------------------------------------------------------------
    var kiba = _actor("kiba", 1, 0, "enemy")
    var tenten = _actor("tenten", 2, 1, "ally")
    battle.card_actors.append(kiba)
    battle.card_actors.append(tenten)
    var delayed := {
        "action_id": "taijutsu",
        "source_uid": kiba.battle_uid,
        "source_id": kiba.card_id,
        "source_team": kiba.team_name,
        "target_uid": tenten.battle_uid,
        "target_id": tenten.card_id,
        "target_slot": tenten.seed_index_value() % 3,
        "delayed": true,
    }
    _require(battle._resolve_descriptor_target(delayed, "enemy") == tenten, "A2 ne retrouve pas sa cible originale")

    battle.card_actors.erase(tenten)
    var sasuke = _actor("sasuke", 3, 1, "ally")
    battle.card_actors.append(sasuke)
    _require(battle._resolve_descriptor_target(delayed, "enemy") == null, "A2 suit à tort un remplacement ordinaire")
    sasuke.status_tags["reactive_entry_cycle"] = battle.turn_counter
    sasuke.reactive_entry_guard = true
    _require(battle._resolve_descriptor_target(delayed, "enemy") == sasuke, "A2 ne suit pas la case après Switch A2 réactif")
    var counter: Dictionary = battle._apply_attack_damage(kiba, sasuke, 500, "taijutsu", false, false, true, false, false, true)
    _require(bool(counter.get("immune", false)), "Counter-Switch Sasuke n'annule pas l'attaque")
    _require(not sasuke.reactive_entry_guard, "Counter-Switch n'est pas consommé")
    print("[OK] A2 identité -> Switch réactif -> Counter-Switch")

    # --------------------------------------------------------------
    # Ino : le vrai CardActor ennemi porte l'état pendant Transfert.
    # --------------------------------------------------------------
    var ino = _actor("ino", 10, 0, "ally")
    var body = _actor("tenten", 11, 0, "enemy")
    body.hp = 777
    body.shield = 222
    body.stat_buffs["taijutsu"] = 125
    body.status_tags["shino_poisoned"] = true
    battle.card_actors.append(ino)
    battle.card_actors.append(body)

    # Exécute la VRAIE branche spéciale avec une seed dont le premier tirage
    # vaut 0.236... : réussite déterministe.
    battle.battle_rng.configure(true, 1)
    battle._finish_special_descriptor(ino, body, "SMOKE INO", {})

    _require(battle._ino_controlled_body(ino) == body, "Lien Ino -> corps invalide")
    _require(battle._effect_actor(ino) == body, "Ino n'utilise pas le vrai corps")
    _require(battle._is_actor_untargetable(ino), "Ino doit être inciblable pendant Transfert")
    _require(battle._is_actor_untargetable(body), "Corps contrôlé doit être inciblable")
    _require(not battle._actor_can_act(body), "Le propriétaire du corps peut encore agir")
    _require(not battle._actor_special_available(ino), "Ino peut relancer Transfert pendant possession")

    var tai_before: int = battle._actor_effective_stat(ino, "taijutsu")
    body.stat_buffs["taijutsu"] = int(body.stat_buffs.get("taijutsu", 0)) + 77
    var tai_after: int = battle._actor_effective_stat(ino, "taijutsu")
    _require(tai_after - tai_before == 77, "Les stats d'Ino sont une copie figée au lieu d'un lien vivant")

    body.apply_disable(2, "p16_smoke")
    _require(not battle._actor_can_act(ino), "Le STUN du corps contrôlé ne bloque pas Ino")

    # Le tour d'activation ne consomme pas la durée.
    var possession_turns: int = int(ino.status_tags.get("ino_turns", 0))
    _require(possession_turns > 0, "Durée Ino non armée")
    battle._tick_ino_possessions_at_end("ally")
    _require(int(ino.status_tags.get("ino_turns", 0)) == possession_turns, "Le tour d'activation consomme le Transfert")
    for remaining: int in range(possession_turns - 1, -1, -1):
        battle.turn_counter += 1
        battle._tick_ino_possessions_at_end("ally")
        if remaining > 0:
            _require(int(ino.status_tags.get("ino_turns", 0)) == remaining, "Durée Ino incorrecte")
    _require(not ino.status_tags.has("ino_target_uid"), "Lien Ino non nettoyé à la fin")
    _require(not body.status_tags.has("possessed_by_uid"), "Lien corps non nettoyé à la restitution")
    _require(body.hp == 777 and body.shield == 222, "La restitution réinitialise PV/bouclier")
    _require(bool(body.status_tags.get("shino_poisoned", false)), "La restitution supprime le poison")
    _require(int(body.stat_buffs.get("taijutsu", 0)) == 202, "La restitution perd les buffs reçus pendant possession")
    print("[OK] Ino live body -> état dynamique -> restitution intacte")

    # Vraie branche d'échec : seed 1000 -> 0.6236... >= 0.5.
    var fail_battle = BattleScript.new()
    fail_battle.battle_log_label = Label.new()
    fail_battle.turn_counter = 20
    fail_battle.battle_rng.configure(true, 1000)
    var fail_ino = _actor("ino", 30, 0, "ally")
    var fail_body = _actor("tenten", 31, 0, "enemy")
    fail_battle.card_actors.append(fail_ino)
    fail_battle.card_actors.append(fail_body)
    fail_battle._finish_special_descriptor(fail_ino, fail_body, "SMOKE INO FAIL", {})
    _require(not fail_ino.status_tags.has("ino_target_uid"), "Échec Ino crée quand même une possession")
    _require(fail_ino.disabled_turns == 3, "Échec Ino n'arme pas exactement 3 tours STUN côté Godot")
    _require(fail_ino.special_cooldown == 3, "Échec Ino n'arme pas la recharge 3 tours")
    print("[OK] Ino échec déterministe -> STUN 3 tours + cooldown 3")

    # Cooldown Ino : 3 -> 2 au premier tour suivant, sans tour fantôme.
    var ino_cd = _actor("ino", 20, 2, "ally")
    ino_cd.consume_special()
    _require(ino_cd.special_cooldown == 3 and not ino_cd.status_tags.has("cooldown_skip_tick"), "Cooldown Ino mal armé")
    ino_cd.tick_own_turn()
    _require(ino_cd.special_cooldown == 2, "Cooldown Ino ne descend pas au tour suivant")
    ino_cd.tick_own_turn()
    _require(ino_cd.special_cooldown == 1, "Cooldown Ino T 3/3 incorrect")
    ino_cd.tick_own_turn()
    _require(ino_cd.special_cooldown == 0 and ino_cd.special_available(), "Transfert ne revient pas au 3e tour suivant")
    print("[OK] cooldown Ino = retour au 3e tour suivant")

    print("ALL P16 GODOT BATTLE SMOKES PASSED")
    quit(0)
