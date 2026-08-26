from __future__ import annotations

import json
from pathlib import Path

from parity_harness import make_engine

ROOT = Path(__file__).resolve().parents[2]
FIXTURE = ROOT / "tools" / "parity" / "fixtures" / "pc_expected_p21.json"


def _shadow_turns(card) -> int:
    if not card.shadow_stuns:
        return 0
    st = card.shadow_stuns[0]
    return int(st.get("turns", st.get("turns_left", 0)))


def scenario_shikamaru_delayed_a2():
    """Référence PC : la spéciale de Shikamaru doit être identique en A2."""
    e = make_engine(
        ["shikamaru"], [],
        ["shikamaru", "tenten", "ino"],
        ["sakura", "shino", "karin"],
        seed=211,
    )
    sh_slot = next(i for i,c in enumerate(e.player(1).field) if c and c.definition.id == "shikamaru")
    sh = e.player(1).field[sh_slot]
    free_slot = 0
    free = e.player(2).field[free_slot]
    action = {
        "kind":"special",
        "actor_id":"shikamaru",
        "actor_name":sh.definition.name,
        "special_name":sh.definition.special_name,
        "target_id":free.definition.id,
        "target_slot":free_slot,
    }
    e.set_delayed_action(1, action)
    before = bool(e.delayed_actions[1])
    ok = e.resolve_reactive_a2_before_actions(2)
    turns = [_shadow_turns(c) for c in e.player(2).field]
    assert before and ok
    assert e.delayed_actions[1] is None
    assert turns == [0,3,3], turns
    assert sh.shikamaru_special_cooldown == 4
    assert all(e.is_disabled(c) for i,c in enumerate(e.player(2).field) if i != free_slot)
    return {
        "name":"shikamaru_delayed_a2",
        "a2_consumed": e.delayed_actions[1] is None,
        "free_slot":free_slot,
        "shadow_turns":turns,
        "cooldown":sh.shikamaru_special_cooldown,
        "resolved_before_enemy_actions":ok,
    }


def scenario_tobi_secret_bomb_reference():
    """Le PC ne révèle dans son log ni cible ni nombre à l'adversaire."""
    e = make_engine(["tobi"], [], ["tobi","sakura","ino"], ["shino","karin","tenten"], seed=212)
    # Le helper 1.7.7 impose normalement le choix au début du tour ; pour isoler
    # la règle de secret, on arme explicitement ce choix puis on pose une bombe.
    e.tobi_bomb_choice_required[1] = True
    target_slot = 1
    target = e.player(2).field[target_slot]
    target_name = target.definition.name
    ok, msg = e.place_tobi_bomb(1, target_slot)
    assert ok, msg
    last = e.log[-1]
    assert last == "Tobi place secrètement une bombe sur le terrain ennemi.", last
    assert target_name not in last
    assert "1/5" not in last and "×1" not in last
    return {
        "name":"tobi_secret_bomb_reference",
        "generic_log":last,
        "target_hidden":target_name not in last,
        "count_hidden":"1/5" not in last,
        "actual_stack":int(getattr(target,"tobi_bombs",0) or 0),
    }


def all_scenarios():
    return [
        scenario_shikamaru_delayed_a2(),
        scenario_tobi_secret_bomb_reference(),
    ]


def main():
    payload = {"prototype":21, "scenarios":all_scenarios()}
    FIXTURE.parent.mkdir(parents=True, exist_ok=True)
    FIXTURE.write_text(json.dumps(payload, ensure_ascii=False, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(json.dumps(payload, ensure_ascii=False, indent=2, sort_keys=True))
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
