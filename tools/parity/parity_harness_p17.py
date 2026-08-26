from __future__ import annotations

import json
from pathlib import Path

from parity_harness import make_engine

ROOT = Path(__file__).resolve().parents[2]
FIXTURE = ROOT / "tools" / "parity" / "fixtures" / "pc_expected_p17.json"


def cid(card):
    return None if card is None else card.definition.id


def scenario_shikamaru_break():
    e = make_engine(["shikamaru"], [], ["shikamaru", "tenten", "ino"], ["sakura", "shino", "karin"], seed=31)
    ss = next(i for i,c in enumerate(e.player(1).field) if c and c.definition.id == "shikamaru")
    sh = e.player(1).field[ss]
    ok, msg = e.use_special(1, ss, 0)
    assert ok, msg
    initial = [len(c.shadow_stuns) for c in e.player(2).field]
    assert initial == [0, 1, 1], initial
    assert sh.shikamaru_special_cooldown == 4
    sh.shield = 100
    dealt, killed = e._deal_fixed_damage(1, ss, 50, source=None, label="QA shield", allow_guard=False)
    assert dealt == 0 and not killed
    after_shield = [len(c.shadow_stuns) for c in e.player(2).field]
    assert after_shield == initial
    dealt, killed = e._deal_fixed_damage(1, ss, 120, source=None, label="QA hp", allow_guard=False)
    assert dealt == 70 and not killed
    after_hp = [len(c.shadow_stuns) for c in e.player(2).field]
    assert after_hp == [0, 0, 0]
    return {
        "name": "shikamaru_break",
        "cooldown": sh.shikamaru_special_cooldown,
        "initial_shadow_links": initial,
        "after_shield_only": after_shield,
        "after_real_hp_damage": after_hp,
    }


def scenario_rescue_chain():
    e = make_engine([], ["chiyo", "kabuto"], ["sakura", "shino", "karin"], ["tenten", "chiyo", "kabuto"], seed=32)
    ts = next(i for i,c in enumerate(e.player(2).field) if c and c.definition.id == "tenten")
    target = e.player(2).field[ts]
    attacker = e.player(1).field[0]
    chiyo = next(c for c in e.player(2).field if c and c.definition.id == "chiyo")
    kabuto = next(c for c in e.player(2).field if c and c.definition.id == "kabuto")
    checkpoints = []
    for n in range(1, 4):
        hp = int(target.current_hp or 0)
        e._deal_damage(2, ts, hp + 500, attacker=attacker, style="ninjutsu", is_attack=True, allow_guard=False)
        checkpoints.append({
            "hit": n,
            "field": cid(e.player(2).field[ts]),
            "target_hp": int(target.current_hp or 0),
            "chiyo_used": bool(chiyo.chiyo_passive_used),
            "kabuto_used": bool(kabuto.kabuto_reanimation_armed),
            "graveyard": [c.id for c in e.player(2).graveyard],
            "pending_replacement": e.pending_replacement is not None,
        })
    assert checkpoints[0]["field"] == "tenten" and checkpoints[0]["chiyo_used"] and not checkpoints[0]["kabuto_used"]
    assert checkpoints[1]["field"] == "tenten" and checkpoints[1]["kabuto_used"]
    assert checkpoints[2]["field"] is None and "tenten" in checkpoints[2]["graveyard"] and checkpoints[2]["pending_replacement"]
    return {"name": "rescue_chain_chiyo_kabuto", "checkpoints": checkpoints}


def scenario_links_cleanup():
    # Kisame prison source identity.
    e = make_engine(["kisame"], [], ["kisame", "tenten", "ino"], ["sakura", "shino", "karin"], seed=33)
    ks = next(i for i,c in enumerate(e.player(1).field) if c and c.definition.id == "kisame")
    ok, msg = e.use_special(1, ks, 0); assert ok, msg
    kisame = e.player(1).field[ks]; prisoner = e.player(2).field[0]
    assert prisoner.prisoned_by is kisame
    e._deal_damage(1, ks, 99999, attacker=e.player(2).field[0], style="taijutsu", is_attack=True,
                   absolute_bypass=True, suppress_survival=True, allow_guard=False)
    assert prisoner.prisoned_by is None

    # Hidan Jashin source identity.
    h = make_engine(["hidan"], [], ["hidan", "tenten", "ino"], ["sakura", "shino", "karin"], seed=34)
    hs = next(i for i,c in enumerate(h.player(1).field) if c and c.definition.id == "hidan")
    ok, msg = h.use_special(1, hs, 0); assert ok, msg
    hidan = h.player(1).field[hs]; doomed = h.player(2).field[0]
    assert doomed.doom_source is hidan and doomed.doom_turns == 5
    h._deal_damage(1, hs, 99999, attacker=h.player(2).field[0], style="taijutsu", is_attack=True,
                   absolute_bypass=True, suppress_survival=True, allow_guard=False)
    assert doomed.doom_source is None and doomed.doom_turns == 0
    return {"name": "source_link_cleanup", "kisame_prison_cleared": True, "hidan_jashin_cleared": True}


def scenario_kakashi_copy():
    e = make_engine(["naruto"], ["kakashi"], ["naruto", "tenten", "ino"], ["kakashi", "sakura", "shino"], seed=35)
    ns = next(i for i,c in enumerate(e.player(1).field) if c and c.definition.id == "naruto")
    ks = next(i for i,c in enumerate(e.player(2).field) if c and c.definition.id == "kakashi")
    ok, msg = e.use_special(1, ns, ks); assert ok, msg
    kakashi = e.player(2).field[ks]
    assert kakashi.copied_special_id == "naruto" and not kakashi.copied_special_used
    while e.active_player != 2:
        e.end_turn()
    e.special_attack_used = False
    assert e.special_available(kakashi, copied=True)
    ok, msg = e.use_special(2, ks, ns, copied=True); assert ok, msg
    assert kakashi.copied_special_used and not kakashi.special_used
    return {
        "name": "kakashi_copy_resource",
        "copied_special": kakashi.copied_special_id,
        "copy_used": kakashi.copied_special_used,
        "raikiri_still_unused": not kakashi.special_used,
    }


def scenario_gengetsu_fixed_explosion():
    e = make_engine(["gengetsu"], [], ["gengetsu", "tenten", "ino"], ["tenten", "shino", "karin"], seed=36)
    gs = next(i for i,c in enumerate(e.player(1).field) if c and c.definition.id == "gengetsu")
    g = e.player(1).field[gs]
    g.current_hp = 1111; g.shield = 222
    for c in e.player(2).field: c.shield = 1000
    before = [int(c.current_hp or 0) for c in e.player(2).field]
    player_hp_before = e.player(2).hp
    ok, msg = e.use_special(1, gs, None); assert ok, msg
    assert int(g.current_hp or 0) == 4800 and g.shield == 0 and g.gengetsu_clone_turns_left == 2
    e._tick_gengetsu_clone(1, gs, g)
    e._tick_gengetsu_clone(1, gs, g)
    losses = [before[i] - int(c.current_hp or 0) for i,c in enumerate(e.player(2).field)]
    assert losses == [300, 300, 300], losses
    assert [c.shield for c in e.player(2).field] == [0, 0, 0]
    assert int(g.current_hp or 0) == 1111 and g.shield == 222 and g.gengetsu_special_cooldown == 4
    assert e.player(2).hp == player_hp_before
    return {"name":"gengetsu_fixed_explosion", "enemy_hp_losses":losses, "restored_hp":1111, "restored_shield":222, "cooldown":4, "player_overflow":0}


def scenario_kurenai_target_only():
    e = make_engine(["kurenai"], ["haku"], ["kurenai", "sakura", "shino"], ["haku", "tenten", "ino"], seed=37)
    ks = next(i for i,c in enumerate(e.player(1).field) if c and c.definition.id == "kurenai")
    ss = next(i for i,c in enumerate(e.player(1).field) if c and c.definition.id == "sakura")
    hs = next(i for i,c in enumerate(e.player(2).field) if c and c.definition.id == "haku")
    ok, msg = e.use_special(1, ks, ss); assert ok, msg
    sakura = e.player(1).field[ss]
    assert sakura.kurenai_special_protection and sakura.kurenai_hidden_shield == 600
    dealt, killed = e._deal_fixed_damage(1, ss, 100, source=e.player(2).field[hs], label="QA AOE", allow_guard=False)
    assert dealt == 0 and not killed and sakura.kurenai_special_protection and sakura.kurenai_hidden_shield == 500
    while e.active_player != 2: e.end_turn()
    e.special_attack_used = False
    ok, msg = e.use_special(2, hs, ss); assert ok, msg
    assert not sakura.kurenai_special_protection and sakura.disabled_turns == 0 and sakura.haku_ice_prison_turns == 0
    return {"name":"kurenai_target_only", "protection_survives_aoe":True, "hidden_shield_after_100":500, "targeted_special_cancelled":True}


def scenario_fixed_ignores_untargetable():
    e = make_engine([], ["obito"], ["sakura", "shino", "karin"], ["obito", "tenten", "ino"], seed=38)
    os = next(i for i,c in enumerate(e.player(2).field) if c and c.definition.id == "obito")
    obito = e.player(2).field[os]
    assert obito.obito_intangible
    obito.shield = 300; hp = int(obito.current_hp or 0)
    dealt, killed = e._deal_fixed_damage(2, os, 500, source=e.player(1).field[0], label="QA fixed", allow_guard=False)
    assert dealt == 200 and not killed and obito.shield == 0 and hp - int(obito.current_hp or 0) == 200
    return {"name":"fixed_ignores_untargetable", "shield_absorbed":300, "hp_damage":200}


def scenario_karin_self_cost():
    e = make_engine(["karin", "kurotsuchi"], [], ["karin", "kurotsuchi", "sakura"], ["tenten", "ino", "shino"], seed=39)
    ks = next(i for i,c in enumerate(e.player(1).field) if c and c.definition.id == "karin")
    ss = next(i for i,c in enumerate(e.player(1).field) if c and c.definition.id == "sakura")
    karin = e.player(1).field[ks]; sakura = e.player(1).field[ss]
    karin.current_hp = 800; karin.shield = 900; sakura.current_hp = 1
    ok, msg = e.use_special(1, ks, ss); assert ok, msg
    assert e._find_instance(karin) is None and karin.shield == 900 and not karin.kurotsuchi_guard_used
    assert any(c.id == "karin" for c in e.player(1).graveyard)
    assert int(sakura.current_hp or 0) == e.max_hp(sakura)
    return {"name":"karin_self_cost", "karin_dead":True, "shield_untouched":900, "doton_not_spent":True, "ally_full_heal":True}


def scenario_jinton_execute():
    e = make_engine(["mu"], ["chiyo", "kurotsuchi"], ["mu", "tenten", "ino"], ["sakura", "chiyo", "kurotsuchi"], seed=40)
    ms = next(i for i,c in enumerate(e.player(1).field) if c and c.definition.id == "mu")
    ss = next(i for i,c in enumerate(e.player(2).field) if c and c.definition.id == "sakura")
    target = e.player(2).field[ss]; target.shield = 999
    chiyo = next(c for c in e.player(2).field if c and c.definition.id == "chiyo")
    assert e.effective_stat(e.player(1).field[ms], "ninjutsu", target) > e.effective_stat(target, "ninjutsu", e.player(1).field[ms])
    ok, msg = e.use_special(1, ms, ss); assert ok, msg
    assert int(target.current_hp or 0) == e.max_hp(target) and target.shield == 999
    assert chiyo.chiyo_passive_used and not target.kurotsuchi_guard_used
    assert e.player(1).field[ms].permanent_buffs["ninjutsu"] == -1000
    return {"name":"jinton_execute", "chiyo_rescued":True, "doton_not_spent":True, "shield_bypassed":True, "mu_nin_penalty":-1000}


def scenario_guarded_specials():
    results = {}
    for card_id, seed in [("karui", 41), ("chojuro", 42), ("jugo", 43), ("a3_raikage", 44), ("omoi", 1000)]:
        e = make_engine([card_id], ["choji"], [card_id, "tenten", "ino"], ["tenten", "choji", "shino"], seed=seed)
        cs = next(i for i,c in enumerate(e.player(1).field) if c and c.definition.id == card_id)
        ts = next(i for i,c in enumerate(e.player(2).field) if c and c.definition.id == "tenten")
        choji = next(c for c in e.player(2).field if c and c.definition.id == "choji")
        target = e.player(2).field[ts]
        cb, tb = int(choji.current_hp or 0), int(target.current_hp or 0)
        ok, msg = e.use_special(1, cs, ts); assert ok, msg
        target_loss = tb - int(target.current_hp or 0); choji_loss = cb - int(choji.current_hp or 0)
        assert target_loss == 0 and choji_loss > 0, (card_id, target_loss, choji_loss, msg)
        results[card_id] = {"target_loss":target_loss, "choji_loss":choji_loss}
    return {"name":"choji_guards_true_special_attacks", "results":results}


def scenario_mei_guard_centering():
    e = make_engine(["mei"], ["choji"], ["mei", "tenten", "ino"], ["tenten", "choji", "shino"], seed=45)
    ms = next(i for i,c in enumerate(e.player(1).field) if c and c.definition.id == "mei")
    ts = next(i for i,c in enumerate(e.player(2).field) if c and c.definition.id == "tenten")
    target = e.player(2).field[ts]
    choji = next(c for c in e.player(2).field if c and c.definition.id == "choji")
    tb, cb = int(target.current_hp or 0), int(choji.current_hp or 0)
    ok, msg = e.use_special(1, ms, ts); assert ok, msg
    assert tb - int(target.current_hp or 0) == 0
    assert cb - int(choji.current_hp or 0) == 1350
    return {"name":"mei_guard_centering", "original_target_loss":0, "choji_loss":1350, "main_plus_adjacent_splash":True}



def scenario_tobi_bomb_switch():
    e = make_engine(["tobi"], [], ["tobi", "tenten", "ino"], ["tenten", "shino", "karin"], seed=46)
    tobi = next(c for c in e.player(1).field if c and c.definition.id == "tobi")
    assert bool(getattr(tobi, "tobi_intangible", False))
    assert e.tobi_bomb_choice_required[1]
    victim = e.player(2).field[0]
    victim.shield = 100
    hp_before = int(victim.current_hp or 0)
    ok, msg = e.place_tobi_bomb(1, 0); assert ok, msg
    assert victim.tobi_bombs == 1
    incoming = e.player(2).deck[0].id
    ok, msg = e.switch_card(2, victim.definition.id, incoming, reactive=False); assert ok, msg
    assert victim.tobi_bombs == 0 and victim.shield == 0
    assert hp_before - int(victim.current_hp or 0) == 220
    assert victim.definition.id in e.reserve_instances[2]
    return {"name":"tobi_bomb_switch", "bomb_damage":320, "shield_absorbed":100, "hp_damage":220, "bombs_cleared":True, "switch_completed":True}


def scenario_zetsu_switch_a1_only():
    out = {}
    for reactive in (False, True):
        e = make_engine(["zetsu"], [], ["zetsu", "tenten", "ino"], ["tenten", "shino", "karin"], seed=47)
        incoming = e.player(2).deck[0].id
        ok, msg = e.switch_card(2, "tenten", incoming, reactive=reactive); assert ok, msg
        entered = e.player(2).field[0]
        out["a2" if reactive else "a1"] = int(entered.disabled_turns or 0)
    assert out == {"a1":2, "a2":0}, out
    return {"name":"zetsu_switch_a1_only", "a1_stun_turns":2, "a2_stun_turns":0}


def scenario_shield_destruction_semantics():
    # Asuma détruit bouclier visible + bouclier caché Kurenai avant ses 400 fixes.
    a = make_engine(["asuma"], [], ["asuma", "tenten", "ino"], ["tenten", "shino", "karin"], seed=48)
    ass = next(i for i,c in enumerate(a.player(1).field) if c and c.definition.id == "asuma")
    target = a.player(2).field[0]
    target.shield = 250
    target.kurenai_hidden_shield = 350
    hp_before = int(target.current_hp or 0)
    ok, msg = a.use_special(1, ass, 0); assert ok, msg
    assert target.shield == 0 and target.kurenai_hidden_shield == 0
    assert hp_before - int(target.current_hp or 0) == 400

    # Obito détruit les boucliers de la cible EFFECTIVE après garde Choji.
    o = make_engine(["obito"], ["choji"], ["obito", "tenten", "ino"], ["tenten", "choji", "shino"], seed=49)
    obs = next(i for i,c in enumerate(o.player(1).field) if c and c.definition.id == "obito")
    tslot = next(i for i,c in enumerate(o.player(2).field) if c and c.definition.id == "tenten")
    selected = o.player(2).field[tslot]
    choji = next(c for c in o.player(2).field if c and c.definition.id == "choji")
    selected.shield = 444
    selected.kurenai_hidden_shield = 111
    choji.shield = 333
    choji.kurenai_hidden_shield = 222
    selected_hp = int(selected.current_hp or 0)
    choji_hp = int(choji.current_hp or 0)
    ok, msg = o.use_special(1, obs, tslot); assert ok, msg
    assert selected.shield == 444 and selected.kurenai_hidden_shield == 111
    assert int(selected.current_hp or 0) == selected_hp
    assert choji.shield == 0 and choji.kurenai_hidden_shield == 0
    assert int(choji.current_hp or 0) < choji_hp

    # Kabuto ignore le bouclier sans le détruire physiquement.
    k = make_engine(["kabuto"], [], ["kabuto", "tenten", "ino"], ["sakura", "shino", "karin"], seed=50)
    kslot = next(i for i,c in enumerate(k.player(1).field) if c and c.definition.id == "kabuto")
    victim = k.player(2).field[0]
    victim.current_hp = 5000
    victim.shield = 777
    victim.kurenai_hidden_shield = 333
    vb = int(victim.current_hp or 0)
    ok, msg = k.use_special(1, kslot, 0); assert ok, msg
    assert int(victim.current_hp or 0) < vb
    assert victim.shield == 777 and victim.kurenai_hidden_shield == 333
    return {
        "name":"shield_destruction_semantics",
        "asuma_both_layers_destroyed":True,
        "asuma_hp_damage":400,
        "obito_effective_target_is_choji":True,
        "obito_selected_target_shields_preserved":[444,111],
        "kabuto_shields_preserved_while_bypassed":[777,333],
    }


def scenario_konohamaru_fixed_counter():
    e = make_engine([], ["konohamaru"], ["tenten", "shino", "karin"], ["konohamaru", "sakura", "ino"], seed=1)
    ks = next(i for i,c in enumerate(e.player(2).field) if c and c.definition.id == "konohamaru")
    attacker = e.player(1).field[0]
    attacker.shield = 200
    hp_before = int(attacker.current_hp or 0)
    outcome = e._perform_attack(1, 0, "taijutsu", ks)
    assert outcome.immune
    assert attacker.shield == 0
    assert hp_before - int(attacker.current_hp or 0) == 150
    return {
        "name":"konohamaru_fixed_counter",
        "attack_dodged":True,
        "counter_fixed_damage":350,
        "shield_absorbed":200,
        "hp_damage":150,
    }

def all_scenarios():
    return [
        scenario_shikamaru_break(),
        scenario_rescue_chain(),
        scenario_links_cleanup(),
        scenario_kakashi_copy(),
        scenario_gengetsu_fixed_explosion(),
        scenario_kurenai_target_only(),
        scenario_fixed_ignores_untargetable(),
        scenario_karin_self_cost(),
        scenario_jinton_execute(),
        scenario_guarded_specials(),
        scenario_mei_guard_centering(),
        scenario_tobi_bomb_switch(),
        scenario_zetsu_switch_a1_only(),
        scenario_shield_destruction_semantics(),
        scenario_konohamaru_fixed_counter(),
    ]


def main():
    scenarios = all_scenarios()
    FIXTURE.parent.mkdir(parents=True, exist_ok=True)
    FIXTURE.write_text(json.dumps({"prototype":17, "scenarios":scenarios}, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(FIXTURE)
    for s in scenarios:
        print(f"[OK] {s['name']}")


if __name__ == "__main__":
    main()
