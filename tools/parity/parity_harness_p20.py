from __future__ import annotations

import json
from pathlib import Path

from parity_harness import make_engine

ROOT = Path(__file__).resolve().parents[2]
FIXTURE = ROOT / "tools" / "parity" / "fixtures" / "pc_expected_p20.json"


def cid(card):
    return None if card is None else card.definition.id


def scenario_choji_effective_visual_target():
    e = make_engine([], ["choji"], ["sakura", "shino", "karin"], ["tenten", "choji", "ino"], seed=201)
    attacker = e.player(1).field[0]
    target_slot = next(i for i,c in enumerate(e.player(2).field) if c and c.definition.id == "tenten")
    choji_slot = next(i for i,c in enumerate(e.player(2).field) if c and c.definition.id == "choji")
    target = e.player(2).field[target_slot]
    choji = e.player(2).field[choji_slot]
    target_hp = int(target.current_hp or 0)
    choji_hp = int(choji.current_hp or 0)
    e.drain_visual_events()
    outcome = e._perform_attack(1, 0, "taijutsu", target_slot)
    events = e.drain_visual_events()
    attack_events = [x for x in events if x.get("type") == "attack"]
    assert outcome.target_slot == choji_slot, (outcome.target_slot, choji_slot)
    assert int(target.current_hp or 0) == target_hp
    assert int(choji.current_hp or 0) < choji_hp
    assert attack_events and int(attack_events[-1].get("to_slot", -1)) == choji_slot, attack_events
    return {
        "name": "choji_effective_visual_target",
        "requested_slot": target_slot,
        "effective_slot": choji_slot,
        "visual_event_slot": int(attack_events[-1].get("to_slot", -1)),
        "original_target_loss": target_hp - int(target.current_hp or 0),
        "choji_loss": choji_hp - int(choji.current_hp or 0),
    }


def scenario_shikamaru_three_turn_links():
    e = make_engine(["shikamaru"], [], ["shikamaru", "tenten", "ino"], ["sakura", "shino", "karin"], seed=202)
    sh_slot = next(i for i,c in enumerate(e.player(1).field) if c and c.definition.id == "shikamaru")
    sh = e.player(1).field[sh_slot]
    free_slot = 0
    ok, msg = e.use_special(1, sh_slot, free_slot)
    assert ok, msg
    free = e.player(2).field[free_slot]
    others = [c for i,c in enumerate(e.player(2).field) if i != free_slot and c]
    assert not free.shadow_stuns
    assert all(len(c.shadow_stuns) == 1 and int(c.shadow_stuns[0].get("turns", c.shadow_stuns[0].get("turns_left", 0))) == 3 for c in others)
    assert sh.shikamaru_special_cooldown == 4
    initial = [0 if i == free_slot else int(c.shadow_stuns[0].get("turns", c.shadow_stuns[0].get("turns_left", 0))) for i,c in enumerate(e.player(2).field)]
    # Le bouclier absorbe : l'ombre reste.
    sh.shield = 100
    e._deal_fixed_damage(1, sh_slot, 60, source=None, label="P20 shield", allow_guard=False)
    after_shield = [len(c.shadow_stuns) for c in e.player(2).field]
    assert after_shield == [0,1,1]
    # Vrais dégâts HP : rupture immédiate de TOUS les liens source.
    e._deal_fixed_damage(1, sh_slot, 120, source=None, label="P20 hp", allow_guard=False)
    after_hp = [len(c.shadow_stuns) for c in e.player(2).field]
    assert after_hp == [0,0,0]
    return {
        "name":"shikamaru_three_turn_links",
        "free_slot":free_slot,
        "initial_turns":initial,
        "cooldown":sh.shikamaru_special_cooldown,
        "links_after_shield_only":after_shield,
        "links_after_real_hp_damage":after_hp,
    }


def scenario_gengetsu_clone_play_state():
    e = make_engine(["gengetsu"], [], ["gengetsu", "tenten", "ino"], ["sakura", "shino", "karin"], seed=203)
    gs = next(i for i,c in enumerate(e.player(1).field) if c and c.definition.id == "gengetsu")
    g = e.player(1).field[gs]
    g.current_hp = 1200
    g.shield = 275
    saved = {"hp":int(g.current_hp or 0), "shield":int(g.shield or 0)}
    ok, msg = e.use_special(1, gs, None)
    assert ok, msg
    assert g.gengetsu_clone_active and g.gengetsu_clone_turns_left == 2
    assert int(g.current_hp or 0) == 4800 and g.shield == 0
    assert e.effective_stat(g, "taijutsu") == 0 and e.effective_stat(g,"ninjutsu") == 0 and e.effective_stat(g,"genjutsu") == 0
    clone = {"hp":int(g.current_hp or 0), "tai":e.effective_stat(g,"taijutsu"), "nin":e.effective_stat(g,"ninjutsu"), "gen":e.effective_stat(g,"genjutsu"), "turns":g.gengetsu_clone_turns_left}
    e._tick_gengetsu_clone(1, gs, g)
    after_one = g.gengetsu_clone_turns_left
    e._tick_gengetsu_clone(1, gs, g)
    assert not g.gengetsu_clone_active
    assert int(g.current_hp or 0) == saved["hp"] and g.shield == saved["shield"] and g.gengetsu_special_cooldown == 4
    return {
        "name":"gengetsu_clone_play_state",
        "clone":clone,
        "after_one_own_turn":after_one,
        "restored_hp":int(g.current_hp or 0),
        "restored_shield":g.shield,
        "cooldown":g.gengetsu_special_cooldown,
    }


def all_scenarios():
    return [
        scenario_choji_effective_visual_target(),
        scenario_shikamaru_three_turn_links(),
        scenario_gengetsu_clone_play_state(),
    ]


def main():
    payload = {"prototype":20, "scenarios":all_scenarios()}
    FIXTURE.write_text(json.dumps(payload, ensure_ascii=False, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(json.dumps(payload, ensure_ascii=False, indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
