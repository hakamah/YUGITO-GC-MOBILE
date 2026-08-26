from __future__ import annotations

import json
from pathlib import Path

from parity_harness import make_engine

ROOT = Path(__file__).resolve().parents[2]
FIXTURE = ROOT / "tools" / "parity" / "fixtures" / "pc_expected_p19.json"


def slot(engine, player: int, card_id: str) -> int:
    return next(i for i, c in enumerate(engine.player(player).field) if c is not None and c.definition.id == card_id)


def scenario_chidori_survival_gauntlet():
    result = {}
    for target_id in ["onoki", "danzo", "orochimaru", "hidan", "kakuzu", "kankuro", "mu"]:
        e = make_engine(["sasuke"], [], ["sasuke", "tenten", "ino"], [target_id, "shino", "karin"], seed=90)
        ss = slot(e, 1, "sasuke"); ts = slot(e, 2, target_id)
        victim = e.player(2).field[ts]
        victim.current_hp = 300
        ok, msg = e.use_special(1, ss, ts); assert ok, msg
        assert e._find_instance(victim) is None
        result[target_id] = {
            "dead": True,
            "survival_used": bool(victim.survival_used),
            "hearts_left": int(victim.kakuzu_revivals_left),
            "karasu_used": bool(victim.kankuro_decoy_used),
            "mu_division_used": bool(victim.mu_division_used),
        }

    # Chiyo meurt quand même sous Chidori, mais son effet DE MORT peut soigner un allié.
    c = make_engine(["sasuke"], [], ["sasuke", "tenten", "ino"], ["chiyo", "sakura", "karin"], seed=91)
    ss = slot(c, 1, "sasuke"); cs = slot(c, 2, "chiyo")
    chiyo = c.player(2).field[cs]
    sakura = next(x for x in c.player(2).field if x and x.definition.id == "sakura")
    sakura.current_hp = 1; chiyo.current_hp = 300
    ok, msg = c.use_special(1, ss, cs); assert ok, msg
    assert c._find_instance(chiyo) is None and chiyo.chiyo_passive_used
    assert int(sakura.current_hp or 0) == c.max_hp(sakura)

    # Chiyo/Kabuto/Doton ne sauvent pas une AUTRE cible contre l'absolu.
    a = make_engine(["sasuke"], ["chiyo", "kabuto", "kurotsuchi"], ["sasuke", "tenten", "ino"], ["sakura", "chiyo", "kabuto"], seed=92)
    # Kurotsuchi est forcée en terrain à la place de Kabuto pour le test Doton, puis on vérifie séparément Kabuto.
    ss = slot(a, 1, "sasuke"); ts = slot(a, 2, "sakura")
    target = a.player(2).field[ts]; target.current_hp = 300
    chiyo_guard = next(x for x in a.player(2).field if x and x.definition.id == "chiyo")
    kabuto_guard = next(x for x in a.player(2).field if x and x.definition.id == "kabuto")
    ok, msg = a.use_special(1, ss, ts); assert ok, msg
    assert a._find_instance(target) is None
    assert not chiyo_guard.chiyo_passive_used and not kabuto_guard.kabuto_reanimation_armed

    # Clone Gengetsu reste une exception : sa destruction restaure Gengetsu au lieu d'un K.O.
    g = make_engine(["sasuke"], ["gengetsu"], ["sasuke", "tenten", "ino"], ["gengetsu", "shino", "karin"], seed=93)
    gs = slot(g, 2, "gengetsu"); gen = g.player(2).field[gs]
    gen.current_hp = 777; gen.shield = 222
    while g.active_player != 2: g.end_turn()
    ok, msg = g.use_special(2, gs, None); assert ok, msg
    gen.current_hp = 300
    while g.active_player != 1: g.end_turn()
    g.special_attack_used = False
    ss = slot(g, 1, "sasuke")
    ok, msg = g.use_special(1, ss, gs); assert ok, msg
    assert g._find_instance(gen) is not None and not gen.gengetsu_clone_active
    assert int(gen.current_hp or 0) == 777 and gen.shield == 222

    return {
        "name": "chidori_survival_gauntlet",
        "personal_survivals_bypassed": result,
        "chiyo_death_heal_still_fires": True,
        "external_chiyo_kabuto_bypassed": True,
        "gengetsu_clone_restores": True,
    }


def scenario_mifune_survival_gauntlet():
    expected_alive = {
        "onoki": False, "danzo": True, "orochimaru": True, "hidan": True,
        "kakuzu": True, "kankuro": True, "mu": True, "chiyo": False,
    }
    out = {}
    for target_id, should_live in expected_alive.items():
        starters = [target_id, "shino", "karin"] if target_id != "chiyo" else ["chiyo", "sakura", "karin"]
        e = make_engine(["mifune"], [], ["mifune", "tenten", "ino"], starters, seed=94)
        ms = slot(e, 1, "mifune"); ts = slot(e, 2, target_id)
        victim = e.player(2).field[ts]; victim.current_hp = 1
        ok, msg = e.use_special(1, ms, ts); assert ok, msg
        alive = e._find_instance(victim) is not None
        assert alive == should_live, (target_id, alive, msg)
        out[target_id] = {"alive": alive, "hp": int(victim.current_hp or 0)}

    # Doton reste une survie et sauve contre Mifune.
    d = make_engine(["mifune"], ["kurotsuchi"], ["mifune", "tenten", "ino"], ["sakura", "kurotsuchi", "karin"], seed=95)
    ms = slot(d, 1, "mifune"); ss = slot(d, 2, "sakura")
    sakura = d.player(2).field[ss]; sakura.current_hp = 1
    ok, msg = d.use_special(1, ms, ss); assert ok, msg
    assert d._find_instance(sakura) is not None and sakura.kurotsuchi_guard_used

    # Chiyo et Kabuto sont de vraies survies : Mifune ne les traverse pas.
    rescues = {}
    for rescuer_id in ["chiyo", "kabuto"]:
        x = make_engine(["mifune"], [rescuer_id], ["mifune", "tenten", "ino"], ["sakura", rescuer_id, "karin"], seed=951 if rescuer_id == "chiyo" else 952)
        ms = slot(x, 1, "mifune"); ss = slot(x, 2, "sakura")
        target = x.player(2).field[ss]; target.current_hp = 1
        ok, msg = x.use_special(1, ms, ss); assert ok, msg
        assert x._find_instance(target) is not None and int(target.current_hp or 0) == x.max_hp(target)
        rescues[rescuer_id] = True

    # Inciblabilité reste une vraie limite de Trancheur.
    u = make_engine(["mifune"], ["obito"], ["mifune", "tenten", "ino"], ["obito", "shino", "karin"], seed=96)
    ms = slot(u, 1, "mifune"); os = slot(u, 2, "obito")
    obito = u.player(2).field[os]
    assert obito.obito_intangible
    hp_before = int(obito.current_hp or 0)
    ok, msg = u.use_special(1, ms, os); assert ok, msg
    assert int(obito.current_hp or 0) == hp_before

    return {"name": "mifune_survival_gauntlet", "matrix": out, "doton_saves": True, "chiyo_kabuto_save": rescues, "untargetable_blocks": True}


def scenario_shield_stack_order():
    e = make_engine([], [], ["sakura", "shino", "karin"], ["kurenai", "tenten", "ino"], seed=97)
    ks = slot(e, 2, "kurenai"); k = e.player(2).field[ks]
    k.current_hp = 1500; k.shield = 300; k.kurenai_hidden_shield = 600
    hp0 = int(k.current_hp or 0)
    dealt, killed = e._deal_fixed_damage(2, ks, 700, source=e.player(1).field[0], label="P19 shield", allow_guard=False)
    assert not killed and dealt == 0 and k.shield == 0 and k.kurenai_hidden_shield == 200 and int(k.current_hp or 0) == hp0
    dealt, killed = e._deal_fixed_damage(2, ks, 400, source=e.player(1).field[0], label="P19 shield2", allow_guard=False)
    assert not killed and dealt == 200 and k.kurenai_hidden_shield == 0 and hp0 - int(k.current_hp or 0) == 200

    # Mifune détruit les DEUX boucliers et convertit exactement la moitié de leur stock en dégâts additionnels.
    def mifune_damage(vis: int, hid: int) -> int:
        x = make_engine(["mifune"], [], ["mifune", "tenten", "ino"], ["kurenai", "shino", "karin"], seed=98)
        ms = slot(x, 1, "mifune"); ks = slot(x, 2, "kurenai")
        target = x.player(2).field[ks]; target.current_hp = 9999; target.shield = vis; target.kurenai_hidden_shield = hid
        before = int(target.current_hp or 0)
        ok, msg = x.use_special(1, ms, ks); assert ok, msg
        assert target.shield == 0 and target.kurenai_hidden_shield == 0
        return before - int(target.current_hp or 0)
    no_shield = mifune_damage(0, 0)
    stacked = mifune_damage(300, 600)
    assert stacked - no_shield == 450
    return {"name": "shield_stack_order", "fixed_visible_then_hidden": True, "hp_after_two_hits": hp0 - 200, "mifune_extra_from_900_shield": 450}


def scenario_temari_links_and_tracker():
    e = make_engine(["temari"], ["hidan", "kisame"], ["temari", "ino", "shino"], ["tenten", "hidan", "kisame"], seed=99)
    ts = slot(e, 1, "temari"); vs = slot(e, 2, "tenten")
    victim = e.player(2).field[vs]
    hidan = next(c for c in e.player(2).field if c and c.definition.id == "hidan")
    kisame = next(c for c in e.player(2).field if c and c.definition.id == "kisame")
    victim.current_hp = 4000
    victim.doom_source = hidan; victim.doom_turns = 5
    victim.prisoned_by = kisame
    forced = e.player(2).deck[0].id
    e.set_forced_reserve_choice(2, forced)
    ok, msg = e.use_special(1, ts, vs); assert ok, msg
    assert e.reserve_instances[2].get("tenten") is victim
    assert victim.doom_source is hidan and victim.doom_turns == 5 and victim.prisoned_by is kisame
    assert e.pending_replacement is not None
    options = [c.id for c in e.pending_replacement.options]
    assert options == [forced], (forced, options)
    ok, msg = e.choose_replacement(2, forced); assert ok, msg
    assert e.forced_reserve_choice[2] is None
    return {"name": "temari_links_and_tracker", "target_links_persist_in_reserve": True, "forced_option": forced, "tracker_consumed": True}


def scenario_source_death_cleanup_without_reserve():
    # Les liens de terrain doivent disparaître même si la source morte n'a AUCUN remplaçant.
    e = make_engine([], [], ["hidan", "kisame", "tenten"], ["sakura", "shino", "karin"], seed=100)
    e.player(1).deck.clear()
    hidan = next(c for c in e.player(1).field if c and c.definition.id == "hidan")
    kisame = next(c for c in e.player(1).field if c and c.definition.id == "kisame")
    victim1 = e.player(2).field[0]; victim2 = e.player(2).field[1]
    victim1.doom_source = hidan; victim1.doom_turns = 5
    victim2.prisoned_by = kisame
    # Consomme leurs survies pour forcer une vraie mort par dégâts fixes sans source.
    hidan.survival_used = True; hidan.current_hp = 1
    kisame.current_hp = 1
    hs = slot(e, 1, "hidan"); ks = slot(e, 1, "kisame")
    e._deal_fixed_damage(1, hs, 10, source=None, label="P19 DOT", allow_guard=False)
    assert victim1.doom_source is None and victim1.doom_turns == 0
    e._deal_fixed_damage(1, ks, 10, source=None, label="P19 DOT", allow_guard=False)
    assert victim2.prisoned_by is None
    return {"name": "source_death_cleanup_without_reserve", "jashin_cleared": True, "kisame_prison_cleared": True}


def scenario_three_ko_replacement_queue():
    e = make_engine(["gengetsu"], [], ["gengetsu", "tenten", "ino"], ["sakura", "shino", "karin"], seed=101)
    gs = slot(e, 1, "gengetsu"); g = e.player(1).field[gs]
    for c in e.player(2).field:
        c.current_hp = 100
    ok, msg = e.use_special(1, gs, None); assert ok, msg
    e._tick_gengetsu_clone(1, gs, g); e._tick_gengetsu_clone(1, gs, g)
    assert [c.id for c in e.player(2).graveyard] == ["sakura", "shino", "karin"]
    assert e.pending_replacement is not None and len(e._replacement_queue) == 2
    offers = []
    while e.pending_replacement is not None:
        offer = e.pending_replacement
        choice = offer.options[0].id
        offers.append({"slot": offer.slot, "options": [c.id for c in offer.options], "choice": choice})
        ok, msg = e.choose_replacement(2, choice); assert ok, msg
    assert len(offers) == 3 and all(c is not None for c in e.player(2).field)
    return {"name": "three_ko_replacement_queue", "graveyard": ["sakura", "shino", "karin"], "offers": offers, "serialized": True}


def scenario_dot_death_passives():
    # Kushina/Shizune sans source : aucun debuff de meurtrier. Chiyo : dernier soin part quand même.
    out = {}
    for cid in ["kushina", "shizune"]:
        e = make_engine([], [], [cid, "tenten", "ino"], ["sakura", "shino", "karin"], seed=102)
        v = e.player(1).field[slot(e, 1, cid)]; v.current_hp = 1
        e._deal_fixed_damage(1, slot(e, 1, cid), 10, source=None, label="P19 DOT", allow_guard=False)
        assert e._find_instance(v) is None
        out[cid] = "dead_without_killer_debuff"

    c = make_engine([], [], ["chiyo", "kiba", "ino"], ["tenten", "shino", "karin"], seed=103)
    ch = c.player(1).field[slot(c, 1, "chiyo")]; ally = c.player(1).field[slot(c, 1, "kiba")]
    ch.current_hp = 1; ally.current_hp = 1
    c._deal_fixed_damage(1, slot(c, 1, "chiyo"), 10, source=None, label="P19 DOT", allow_guard=False)
    assert c._find_instance(ch) is None and ch.chiyo_passive_used and int(ally.current_hp or 0) == c.max_hp(ally)
    return {"name": "dot_death_passives", "kushina": out["kushina"], "shizune": out["shizune"], "chiyo_death_heal": True}



def scenario_overflow_with_survival():
    # Roadmap QA : le surplus est calculé AVANT les survies personnelles classiques.
    # Danzo/Hidan/Kankuro/Kakuzu survivent, mais le joueur encaisse le surplus.
    # Ônoki et Doton annulent l'impact avant ce calcul : aucun surplus joueur.
    out = {}
    for cid in ["danzo", "hidan", "kankuro", "kakuzu"]:
        e = make_engine([], [], ["sakura", "shino", "karin"], [cid, "tenten", "ino"], seed=104)
        ts = slot(e, 2, cid)
        victim = e.player(2).field[ts]
        victim.current_hp = 100
        hp_before = e.player(2).hp
        dealt, killed, cancelled = e._deal_damage(
            2, ts, 1000, attacker=e.player(1).field[0], style="taijutsu",
            is_attack=True, label="P19 overflow survival"
        )
        assert not killed and not cancelled
        assert hp_before - e.player(2).hp == 900
        out[cid] = {
            "alive": e._find_instance(victim) is not None,
            "card_hp": int(victim.current_hp or 0),
            "player_overflow": hp_before - e.player(2).hp,
        }

    onoki = make_engine([], [], ["sakura", "shino", "karin"], ["onoki", "tenten", "ino"], seed=105)
    os = slot(onoki, 2, "onoki")
    ov = onoki.player(2).field[os]; ov.current_hp = 100
    php = onoki.player(2).hp
    dealt, killed, cancelled = onoki._deal_damage(
        2, os, 1000, attacker=onoki.player(1).field[0], style="taijutsu",
        is_attack=True, label="P19 overflow onoki"
    )
    assert not killed and cancelled and dealt == 0 and php == onoki.player(2).hp

    doton = make_engine(["kurotsuchi"], [], ["sakura", "shino", "karin"], ["sakura", "kurotsuchi", "ino"], seed=106)
    ss = slot(doton, 2, "sakura")
    sv = doton.player(2).field[ss]; sv.current_hp = 100
    php = doton.player(2).hp
    dealt, killed, cancelled = doton._deal_damage(
        2, ss, 1000, attacker=doton.player(1).field[0], style="taijutsu",
        is_attack=True, label="P19 overflow doton"
    )
    assert not killed and cancelled and dealt == 0 and php == doton.player(2).hp and sv.kurotsuchi_guard_used

    rescue_overflow = {}
    for rescuer_id in ["chiyo", "kabuto"]:
        e = make_engine([], [rescuer_id], ["sakura", "shino", "karin"], ["kiba", rescuer_id, "ino"], seed=107 if rescuer_id == "chiyo" else 108)
        ss = slot(e, 2, "kiba")
        victim = e.player(2).field[ss]; victim.current_hp = 100
        php = e.player(2).hp
        dealt, killed, cancelled = e._deal_damage(
            2, ss, 1000, attacker=e.player(1).field[0], style="taijutsu",
            is_attack=True, label="P19 overflow rescue"
        )
        assert not killed and not cancelled and int(victim.current_hp or 0) == e.max_hp(victim)
        assert php - e.player(2).hp == 900
        rescue_overflow[rescuer_id] = 900

    return {
        "name": "overflow_with_survival",
        "personal_survival_overflow": out,
        "chiyo_kabuto_overflow": rescue_overflow,
        "onoki_overflow": 0,
        "doton_overflow": 0,
    }


def scenario_ko_empty_reserve():
    # Un K.O. sans réserve laisse simplement le slot vide. Si plus aucun Ninja
    # n'existe sur le terrain, la défaite est immédiate sans fenêtre fantôme.
    e = make_engine([], [], ["sakura", "shino", "karin"], ["tenten", "ino", "kiba"], seed=109)
    e.player(2).deck.clear()
    ts = slot(e, 2, "tenten")
    victim = e.player(2).field[ts]; victim.current_hp = 1
    e._deal_fixed_damage(2, ts, 10, source=None, label="P19 no reserve", allow_guard=False)
    assert e.player(2).field[ts] is None and e.pending_replacement is None and e.winner is None

    wipe = make_engine([], [], ["sakura", "shino", "karin"], ["tenten", "ino", "kiba"], seed=110)
    wipe.player(2).deck.clear()
    for c in wipe.player(2).field:
        c.current_hp = 1
    for idx in range(3):
        if wipe.player(2).field[idx] is not None:
            wipe._deal_fixed_damage(2, idx, 10, source=None, label="P19 empty wipe", allow_guard=False)
    assert wipe.winner == 1 and wipe.pending_replacement is None and all(c is None for c in wipe.player(2).field)
    return {"name": "ko_empty_reserve", "single_hole_no_modal": True, "full_wipe_winner": 1}

def all_scenarios():
    return [
        scenario_chidori_survival_gauntlet(),
        scenario_mifune_survival_gauntlet(),
        scenario_shield_stack_order(),
        scenario_temari_links_and_tracker(),
        scenario_source_death_cleanup_without_reserve(),
        scenario_three_ko_replacement_queue(),
        scenario_dot_death_passives(),
        scenario_overflow_with_survival(),
        scenario_ko_empty_reserve(),
    ]


def main():
    scenarios = all_scenarios()
    FIXTURE.parent.mkdir(parents=True, exist_ok=True)
    FIXTURE.write_text(json.dumps({"prototype": 19, "scenarios": scenarios}, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(FIXTURE)
    for s in scenarios:
        print(f"[OK] {s['name']}")


if __name__ == "__main__":
    main()
