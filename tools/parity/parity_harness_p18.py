from __future__ import annotations

import json
from pathlib import Path

from parity_harness import make_engine

ROOT = Path(__file__).resolve().parents[2]
FIXTURE = ROOT / "tools" / "parity" / "fixtures" / "pc_expected_p18.json"


def slot(engine, player: int, card_id: str) -> int:
    return next(i for i, c in enumerate(engine.player(player).field) if c is not None and c.definition.id == card_id)


def scenario_chidori_absolute_matrix():
    # 1) Bouclier visible détruit, bouclier caché Kurenai seulement ignoré/persistant.
    e = make_engine(["sasuke"], [], ["sasuke", "tenten", "ino"], ["sakura", "shino", "karin"], seed=60)
    ss = slot(e, 1, "sasuke")
    target = e.player(2).field[0]
    target.current_hp = 5000
    target.shield = 333
    target.kurenai_hidden_shield = 444
    before = int(target.current_hp or 0)
    ok, msg = e.use_special(1, ss, 0); assert ok, msg
    assert target.shield == 0
    assert target.kurenai_hidden_shield == 444
    assert before - int(target.current_hp or 0) == 1965

    # 2) Chidori traverse l'esquive létale Ônoki et toutes les survivances/assistances.
    cases = {}
    for target_id, enemy_starters in [
        ("onoki", ["onoki", "shino", "karin"]),
        ("danzo", ["danzo", "chiyo", "kabuto"]),
        ("obito", ["obito", "shino", "karin"]),
    ]:
        x = make_engine(["sasuke"], [], ["sasuke", "tenten", "ino"], enemy_starters, seed=61)
        sslot = slot(x, 1, "sasuke")
        tslot = slot(x, 2, target_id)
        victim = x.player(2).field[tslot]
        victim.current_hp = 500
        victim.shield = 333
        victim.kurenai_hidden_shield = 444
        if target_id == "obito":
            victim.obito_intangible = True
        ok, msg = x.use_special(1, sslot, tslot); assert ok, msg
        assert x._find_instance(victim) is None
        assert target_id in [c.id for c in x.player(2).graveyard]
        if target_id == "onoki":
            assert not victim.survival_used
        if target_id == "danzo":
            chiyo = next(c for c in x.player(2).field if c and c.definition.id == "chiyo")
            kabuto = next(c for c in x.player(2).field if c and c.definition.id == "kabuto")
            assert not victim.survival_used and not chiyo.chiyo_passive_used and not kabuto.kabuto_reanimation_armed
        cases[target_id] = {
            "dead": True,
            "visible_shield": victim.shield,
            "hidden_shield": victim.kurenai_hidden_shield,
        }
    return {
        "name": "chidori_absolute_matrix",
        "survivor_case_hp_damage": 1965,
        "visible_shield_destroyed": True,
        "hidden_shield_preserved": 444,
        "absolute_cases": cases,
    }


def scenario_mifune_defense_matrix():
    # La liste PC des profils défensifs décide +750 au lieu de +500.
    damage = {}
    for target_id in [
        "tenten", "sasuke", "sasori", "onoki", "danzo", "orochimaru",
        "hidan", "kakuzu", "choji", "kimimaro", "kurotsuchi",
    ]:
        e = make_engine(["mifune"], [], ["mifune", "tenten", "ino"], [target_id, "shino", "karin"], seed=62)
        ms = slot(e, 1, "mifune")
        ts = slot(e, 2, target_id)
        target = e.player(2).field[ts]
        target.current_hp = 9999
        before = int(target.current_hp or 0)
        ok, msg = e.use_special(1, ms, ts); assert ok, msg
        damage[target_id] = before - int(target.current_hp or 0)
    # Ônoki : Trancheur ignore bien son esquive létale.
    o = make_engine(["mifune"], [], ["mifune", "tenten", "ino"], ["onoki", "shino", "karin"], seed=63)
    ms = slot(o, 1, "mifune"); os = slot(o, 2, "onoki")
    onoki = o.player(2).field[os]; onoki.current_hp = 1
    ok, msg = o.use_special(1, ms, os); assert ok, msg
    assert o._find_instance(onoki) is None and not onoki.survival_used
    return {"name": "mifune_defense_matrix", "damage": damage, "onoki_dodge_ignored": True}


def scenario_control_immunity_bee_madara():
    out = {}
    for attacker_id in ["sai", "shizune", "kushina"]:
        out[attacker_id] = {}
        for target_id in ["killer_bee", "madara"]:
            e = make_engine([attacker_id], [], [attacker_id, "tenten", "ino"], [target_id, "shino", "karin"], seed=64)
            a = slot(e, 1, attacker_id); t = slot(e, 2, target_id)
            target = e.player(2).field[t]
            ok, msg = e.use_special(1, a, t); assert ok, msg
            out[attacker_id][target_id] = {
                "disabled_turns": int(target.disabled_turns or 0),
                "sealed_turns": int(getattr(target, "sealed_turns", 0) or 0),
                "is_disabled": bool(e.is_disabled(target)),
            }
    assert out["sai"]["killer_bee"]["disabled_turns"] == 0
    assert out["sai"]["madara"]["disabled_turns"] == 0
    assert out["shizune"]["killer_bee"]["disabled_turns"] == 2 and not out["shizune"]["killer_bee"]["is_disabled"]
    assert out["shizune"]["madara"]["disabled_turns"] == 0 and not out["shizune"]["madara"]["is_disabled"]
    assert out["kushina"]["killer_bee"]["sealed_turns"] == 5 and out["kushina"]["killer_bee"]["is_disabled"]
    assert out["kushina"]["madara"]["sealed_turns"] == 0 and not out["kushina"]["madara"]["is_disabled"]
    return {"name": "control_immunity_bee_madara", "matrix": out}


def scenario_poison_stack_pipeline():
    e = make_engine([], [], ["sakura", "shino", "karin"], ["tenten", "ino", "kiba"], seed=65)
    target = e.player(1).field[0]
    target.current_hp = 1400
    target.shield = 250
    target.torune_contact_poison = 50
    target.torune_micro_poison = 100
    target.anko_poison_turns = 4
    target.shino_poisoned = True
    target.hanzo_poisoned = True
    target.shizune_poisoned = True
    target.haku_ice_prison_turns = 3
    e.start_turn(1)
    assert int(target.current_hp or 0) == 1093
    assert target.shield == 0
    assert target.anko_poison_turns == 3
    # Prison de glace décrémente à la fin du tour, pas lors du tic du début.
    assert target.haku_ice_prison_turns == 3
    return {
        "name": "poison_stack_pipeline",
        "hp_after_start": 1093,
        "shield_after_start": 0,
        "anko_turns_after_tick": 3,
        "haku_turns_after_tick": 3,
    }


def scenario_temari_reserve_state():
    e = make_engine(["temari"], [], ["temari", "ino", "shino"], ["tenten", "sakura", "karin"], seed=73)
    ts = slot(e, 1, "temari")
    vs = slot(e, 2, "tenten")
    victim = e.player(2).field[vs]
    victim.current_hp = 777
    victim.shield = 333
    victim.shino_poisoned = True
    victim.permanent_buffs["taijutsu"] = 125
    victim.special_used = True
    reserve_before = [c.id for c in e.player(2).deck]
    ok, msg = e.use_special(1, ts, vs); assert ok, msg
    assert e.player(2).field[vs] is None
    assert e.reserve_instances[2].get("tenten") is victim
    assert e.pending_replacement is not None
    offered = [c.id for c in e.pending_replacement.options]
    assert "tenten" not in offered, (reserve_before, offered)
    # Les dégâts de la rafale passent d'abord : le bouclier est consommé et la
    # vraie instance, avec ses états personnels restants, rejoint la réserve.
    assert int(victim.current_hp or 0) == 717
    assert victim.shield == 0 and victim.shino_poisoned and victim.permanent_buffs["taijutsu"] == 125 and victim.special_used
    chosen = offered[0]
    ok, msg = e.choose_replacement(2, chosen); assert ok, msg
    assert e.player(2).field[vs] is not None and e.player(2).field[vs].definition.id == chosen
    assert e.reserve_instances[2].get("tenten") is victim
    return {
        "name": "temari_reserve_state",
        "offered": offered,
        "blown_not_immediate_option": True,
        "victim_hp_in_reserve": 717,
        "victim_states_persist": True,
        "replacement": chosen,
    }



def scenario_start_turn_order_gengetsu():
    # PC : les poisons sont résolus AVANT le countdown du clone. Un clone qui
    # meurt du poison revient à Gengetsu sans jamais exploser.
    e = make_engine(["gengetsu"], [], ["gengetsu", "tenten", "ino"], ["sakura", "shino", "karin"], seed=76)
    gs = slot(e, 1, "gengetsu")
    g = e.player(1).field[gs]
    ok, msg = e.use_special(1, gs, None); assert ok, msg
    g.current_hp = 50
    g.shino_poisoned = True
    g.gengetsu_clone_turns_left = 1
    for enemy in e.player(2).field:
        enemy.current_hp = 3000
    before = [int(c.current_hp or 0) for c in e.player(2).field]
    e.start_turn(1)
    after = [int(c.current_hp or 0) for c in e.player(2).field]
    assert not g.gengetsu_clone_active
    assert after == before
    # Le poison détruit le clone AVANT la phase de recharge du même début de
    # tour : le cooldown 4 créé par le retour est donc immédiatement tické 4->3.
    assert int(g.gengetsu_special_cooldown or 0) == 3
    e.start_turn(1)
    assert int(g.gengetsu_special_cooldown or 0) == 2
    return {
        "name": "start_turn_order_gengetsu",
        "poison_prevents_explosion": True,
        "enemy_hp_unchanged": after,
        "cooldown_after_same_start_tick": 3,
        "cooldown_next_own_start": 2,
    }


def scenario_tsunade_start_heal():
    e = make_engine([], [], ["tsunade", "tenten", "ino"], ["sakura", "shino", "karin"], seed=77)
    t = e.player(1).field[slot(e, 1, "tsunade")]
    t.current_hp = 700
    before = int(t.current_hp or 0)
    e.start_turn(1)
    healed = int(t.current_hp or 0) - before
    assert healed == 200
    return {"name": "tsunade_start_heal", "healed": healed, "hp_after": int(t.current_hp or 0)}


def scenario_tobi_after_start_effects():
    # Tobi est une extension qui s'exécute APRES GameEngine.start_turn(). S'il
    # meurt d'un poison de début de tour, aucune bombe ne doit être demandée.
    e = make_engine([], [], ["tobi", "tenten", "ino"], ["sakura", "shino", "karin"], seed=78)
    t = e.player(1).field[slot(e, 1, "tobi")]
    t.current_hp = 50
    t.shino_poisoned = True
    # make_engine a déjà appelé le premier start_turn lors du lancement.
    e.tobi_bomb_choice_required[1] = False
    e.start_turn(1)
    assert e._find_instance(t) is None
    assert not bool(e.tobi_bomb_choice_required.get(1, False))
    return {"name": "tobi_after_start_effects", "tobi_dead": True, "bomb_choice_required": False}

def all_scenarios():
    return [
        scenario_chidori_absolute_matrix(),
        scenario_mifune_defense_matrix(),
        scenario_control_immunity_bee_madara(),
        scenario_poison_stack_pipeline(),
        scenario_temari_reserve_state(),
        scenario_start_turn_order_gengetsu(),
        scenario_tsunade_start_heal(),
        scenario_tobi_after_start_effects(),
    ]


def main():
    scenarios = all_scenarios()
    FIXTURE.parent.mkdir(parents=True, exist_ok=True)
    FIXTURE.write_text(json.dumps({"prototype": 18, "scenarios": scenarios}, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(FIXTURE)
    for s in scenarios:
        print(f"[OK] {s['name']}")


if __name__ == "__main__":
    main()
