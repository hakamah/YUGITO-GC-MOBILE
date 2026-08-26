from __future__ import annotations

import json
import sys
from dataclasses import asdict, is_dataclass
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parents[2]
LEGACY = ROOT / "legacy_reference"
sys.path.insert(0, str(ROOT))

from legacy_reference import cards as pc_cards  # noqa: E402
from legacy_reference import game_engine as pc_engine  # noqa: E402


class PortableRNG:
    """Même LCG 32 bits que scripts/ParityRNG.gd.

    Fournit seulement l'API random.Random réellement utilisée par game_engine.py :
    random(), choice(), sample(), shuffle().
    """

    def __init__(self, seed: int = 1):
        self.state = int(seed) & 0xFFFFFFFF
        if self.state == 0:
            self.state = 0x6D2B79F5

    def _next_u32(self) -> int:
        self.state = (1664525 * self.state + 1013904223) & 0xFFFFFFFF
        return self.state

    def random(self) -> float:
        return self._next_u32() / 4294967296.0

    def _rand_index(self, n: int) -> int:
        if n <= 1:
            return 0
        return self._next_u32() % n

    def choice(self, seq):
        if not seq:
            raise IndexError("choice from empty sequence")
        return seq[self._rand_index(len(seq))]

    def shuffle(self, seq) -> None:
        for i in range(len(seq) - 1, 0, -1):
            j = self._rand_index(i + 1)
            seq[i], seq[j] = seq[j], seq[i]

    def sample(self, population, k: int):
        pool = list(population)
        if k < 0 or k > len(pool):
            raise ValueError("sample larger than population")
        out = []
        for _ in range(k):
            j = self._rand_index(len(pool))
            out.append(pool.pop(j))
        return out


def load_cards():
    defs = pc_cards.load_cards(LEGACY / "core_set_PC_1.8.21.json")
    return defs, {c.id: c for c in defs}


def legal_deck(by_id: dict[str, Any], required: list[str]) -> list[Any]:
    ids: list[str] = []
    for cid in required:
        if cid in by_id and cid not in ids:
            ids.append(cid)
    for card in sorted(by_id.values(), key=lambda c: (c.stars, c.name.casefold())):
        if len(ids) >= 8:
            break
        if card.id in ids:
            continue
        trial = [by_id[x] for x in ids + [card.id]]
        if pc_engine.GameEngine.deck_respects_star_limit(trial):
            ids.append(card.id)
    deck = [by_id[x] for x in ids]
    if len(deck) != 8 or not pc_engine.GameEngine.deck_respects_star_limit(deck):
        raise AssertionError(f"Impossible de construire un deck légal: {ids}")
    return deck


def make_engine(
    req1: list[str], req2: list[str], starters1: list[str], starters2: list[str], *, seed: int = 1
):
    _, by_id = load_cards()
    deck1 = legal_deck(by_id, req1 + starters1)
    deck2 = legal_deck(by_id, req2 + starters2)
    e = pc_engine.GameEngine(
        deck1=deck1,
        deck2=deck2,
        starters1=[by_id[x] for x in starters1],
        starters2=[by_id[x] for x in starters2],
        starting_player=1,
        seed=seed,
    )
    # Le runner PC et le runner Godot partagent désormais EXACTEMENT la même
    # suite pseudo-aléatoire en mode QA.
    e.random = PortableRNG(seed)
    return e


def _card_state(engine: pc_engine.GameEngine, card) -> dict[str, Any] | None:
    if card is None:
        return None
    body = engine._effect_carrier(card)
    state: dict[str, Any] = {
        "id": card.definition.id,
        "body_id": body.definition.id,
        "hp": int(body.current_hp or 0),
        "max_hp": int(engine.max_hp(body)),
        "shield": int(body.shield or 0),
        "disabled": int(body.disabled_turns or 0),
        "special_used": bool(card.special_used),
        "special_cd": int(getattr(card, "ino_special_cooldown", 0) if card.definition.id == "ino" else 0),
        "synergy": round(float(getattr(body, "synergy_bonus_pct", 0.0) or 0.0), 4),
        "buffs": dict(getattr(body, "permanent_buffs", {}) or {}),
        "blocked": dict(getattr(body, "blocked_styles", {}) or {}),
        "reactive_counter": bool(getattr(card, "switch_counter_armed", False)),
    }
    if card.definition.id == "ino":
        target = card.ino_possession_target
        state["ino_target"] = target.definition.id if engine._is_alive_instance(target) else None
        state["ino_turns"] = int(card.ino_possession_turns_left or 0)
    if card.ino_possessed_by is not None and engine._is_alive_instance(card.ino_possessed_by):
        state["possessed_by"] = card.ino_possessed_by.definition.id
    for name in [
        "shino_poisoned", "hanzo_poisoned", "haku_ice_prison_turns", "sealed_turns",
        "torune_contact_poison", "torune_micro_poison", "anko_poison_turns",
    ]:
        value = getattr(body, name, None)
        if value:
            state[name] = value
    return state


def snapshot(engine: pc_engine.GameEngine, label: str) -> dict[str, Any]:
    data: dict[str, Any] = {
        "label": label,
        "turn": int(engine.turn),
        "active_player": int(engine.active_player),
        "winner": engine.winner,
        "player_hp": {"1": int(engine.player(1).hp), "2": int(engine.player(2).hp)},
        "field": {},
        "reserve": {},
        "graveyard": {},
        "delayed": {},
        "pending_replacement": None,
    }
    for pnum in (1, 2):
        data["field"][str(pnum)] = [_card_state(engine, c) for c in engine.player(pnum).field]
        data["reserve"][str(pnum)] = sorted(c.id for c in engine.player(pnum).deck)
        data["graveyard"][str(pnum)] = [c.id for c in engine.player(pnum).graveyard]
        data["delayed"][str(pnum)] = engine.delayed_actions.get(pnum)
    if engine.pending_replacement is not None:
        offer = engine.pending_replacement
        data["pending_replacement"] = {
            "player": offer.player_number,
            "slot": offer.slot,
            "options": [c.id for c in offer.options],
        }
    return data


def scenario_a2_torture(seed: int = 17) -> dict[str, Any]:
    e = make_engine(
        ["sasuke"], ["kiba"],
        ["tenten", "ino", "shino"], ["kiba", "sakura", "karin"],
        seed=seed,
    )
    trace = [snapshot(e, "initial")]

    # J1 arme un Switch A2 Tenten -> Sasuke.
    tenten_slot = next(i for i, c in enumerate(e.player(1).field) if c and c.definition.id == "tenten")
    e.set_delayed_action(1, {
        "kind": "switch",
        "outgoing_id": "tenten",
        "incoming_id": "sasuke",
        "outgoing_name": "Tenten",
        "incoming_name": "Sasuke",
    })
    trace.append(snapshot(e, "a2_switch_armed"))

    # J2 valide : A2 adverse part AVANT son A1.
    e.end_turn()  # J2 devient actif.
    kiba_slot = next(i for i, c in enumerate(e.player(2).field) if c and c.definition.id == "kiba")
    attack_desc = {
        "kind": "normal", "actor_id": "kiba", "actor_name": "Kiba", "style": "taijutsu",
        "target_id": "tenten", "target_slot": tenten_slot, "minato_free": False,
    }
    assert e.resolve_reactive_a2_before_actions(2), "Le Switch A2 PC devait réussir"
    trace.append(snapshot(e, "a2_reactive_switch_resolved"))

    # L'A1 déjà pointée sur Tenten suit la case uniquement parce qu'un vrai Switch
    # A2 réactif vient de modifier cette case. Sasuke annule cette première attaque.
    ok, msg = e.execute_action_descriptor(2, attack_desc)
    assert ok, msg
    sasuke = e.player(1).field[tenten_slot]
    assert sasuke is not None and sasuke.definition.id == "sasuke"
    assert int(sasuke.current_hp or 0) == e.max_hp(sasuke), "Counter-Switch Sasuke n'a pas annulé l'attaque"
    assert not sasuke.switch_counter_armed, "Counter-Switch devait être consommé"
    trace.append(snapshot(e, "counter_switch_consumed"))

    # K.O. forcé pour stresser l'ordre cimetière -> offre -> remplacement.
    killer = next(c for c in e.player(2).field if c is not None and c.definition.id == "sakura")
    hp_before = int(sasuke.current_hp or 0)
    dealt, killed, immune = e._deal_damage(
        1, tenten_slot, hp_before + 150, attacker=killer, style="ninjutsu", is_attack=True,
        absolute_bypass=True, suppress_survival=True,
    )
    assert killed and not immune and dealt == hp_before
    assert any(c.id == "sasuke" for c in e.player(1).graveyard)
    assert e.pending_replacement is not None
    trace.append(snapshot(e, "ko_waiting_replacement"))

    chosen = e.pending_replacement.options[0].id
    ok, msg = e.choose_replacement(1, chosen)
    assert ok, msg
    replacement = e.player(1).field[tenten_slot]
    assert replacement is not None and replacement.definition.id == chosen
    trace.append(snapshot(e, "replacement_done"))

    return {"name": "a2_torture", "seed": seed, "chosen_replacement": chosen, "trace": trace}


def scenario_ino(seed: int = 1) -> dict[str, Any]:
    # seed=1 -> premier LCG = 0.236... donc Transfert réussi (< 0.5).
    e = make_engine(
        ["ino"], ["tenten"],
        ["ino", "kiba", "shino"], ["tenten", "sakura", "karin"],
        seed=seed,
    )
    trace = [snapshot(e, "initial")]
    ino_slot = next(i for i, c in enumerate(e.player(1).field) if c and c.definition.id == "ino")
    tenten_slot = next(i for i, c in enumerate(e.player(2).field) if c and c.definition.id == "tenten")
    ino = e.player(1).field[ino_slot]
    body = e.player(2).field[tenten_slot]
    assert ino is not None and body is not None

    # Donne au corps contrôlé un état riche AVANT possession.
    body.current_hp = 777
    body.shield = 222
    body.permanent_buffs["taijutsu"] = 125
    body.shino_poisoned = True
    original_identity = id(body)
    trace.append(snapshot(e, "body_preloaded"))

    ok, msg = e.use_special(1, ino_slot, tenten_slot)
    assert ok, msg
    assert ino.ino_possession_target is body and body.ino_possessed_by is ino
    assert e._is_untargetable(ino) and e._is_untargetable(body)
    assert not e.special_available(ino)
    assert e.effective_stat(ino, "taijutsu") == e.effective_stat(body, "taijutsu")
    trace.append(snapshot(e, "possession_started"))

    # Tout nouvel état reçu appartient AU CORPS, et Ino le lit immédiatement.
    body.permanent_buffs["taijutsu"] += 77
    body.shield += 111
    body.disabled_turns = 2
    assert e.is_disabled(ino), "Le STUN du corps doit bloquer Ino"
    body.disabled_turns = 0
    dynamic_tai = e.effective_stat(body, "taijutsu")
    assert e.effective_stat(ino, "taijutsu") == dynamic_tai
    trace.append(snapshot(e, "body_mutated_during_possession"))

    # Le tour d'activation ne consomme pas la durée. Puis chaque fin de tour J1
    # retire exactement 1 charge jusqu'à restitution du MÊME objet.
    initial_turns = int(ino.ino_possession_turns_left)
    e.end_turn()  # fin J1 activation -> J2
    assert ino.ino_possession_turns_left == initial_turns
    for _ in range(initial_turns):
        e.end_turn()  # fin J2 -> J1
        e.end_turn()  # fin J1 -> J2 : décrémente
    assert ino.ino_possession_target is None
    assert body.ino_possessed_by is None
    assert id(body) == original_identity
    assert int(body.current_hp or 0) <= 777  # poison peut avoir tické, mais l'état n'est pas reset.
    # Le poison de Shino peut légitimement consommer le bouclier pendant ces tours ;
    # l'invariant de parité est qu'aucun reset/recréation du corps ne se produit.
    assert body.shield >= 0
    assert body.permanent_buffs["taijutsu"] == 202
    assert body.shino_poisoned is True
    trace.append(snapshot(e, "possession_ended_state_preserved"))

    return {"name": "ino_live_body", "seed": seed, "trace": trace}


def scenario_ino_failure(seed: int = 1000) -> dict[str, Any]:
    # seed=1000 -> premier LCG = 0.6236... donc Transfert échoue (>= 0.5).
    e = make_engine(
        ["ino"], ["tenten"],
        ["ino", "kiba", "shino"], ["tenten", "sakura", "karin"],
        seed=seed,
    )
    trace = [snapshot(e, "initial")]
    ino_slot = next(i for i, c in enumerate(e.player(1).field) if c and c.definition.id == "ino")
    tenten_slot = next(i for i, c in enumerate(e.player(2).field) if c and c.definition.id == "tenten")
    ino = e.player(1).field[ino_slot]
    assert ino is not None

    ok, msg = e.use_special(1, ino_slot, tenten_slot)
    assert ok, msg
    assert ino.ino_possession_target is None
    assert ino.disabled_turns == 4, "PC arme 4 avant la décrémentation de fin du tour courant"
    assert ino.ino_special_cooldown == 3
    trace.append(snapshot(e, "transfer_failed_armed"))

    # Fin du tour d'échec : 4 -> 3. Ino manquera ensuite exactement trois tours.
    e.end_turn()
    assert ino.disabled_turns == 3
    trace.append(snapshot(e, "failure_current_turn_closed"))

    for missed in range(1, 4):
        e.end_turn()  # J2 -> J1
        assert e.is_disabled(ino), f"Ino devrait être STUN au tour manqué {missed}"
        e.end_turn()  # J1 -> J2, décrémente en fin de tour
        trace.append(snapshot(e, f"failure_missed_turn_{missed}"))

    assert ino.disabled_turns == 0 and not e.is_disabled(ino)
    assert ino.ino_special_cooldown == 0, "La recharge doit aussi être terminée au 3e tour suivant"
    return {"name": "ino_failure_3_turn_stun", "seed": seed, "trace": trace}


def build_all() -> dict[str, Any]:
    return {
        "schema": 1,
        "rng": "LCG32 1664525/1013904223",
        "scenarios": [scenario_a2_torture(), scenario_ino(), scenario_ino_failure()],
    }


def main() -> int:
    out = build_all()
    target = ROOT / "tools" / "parity" / "fixtures" / "pc_expected_p16.json"
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(json.dumps(out, ensure_ascii=False, indent=2), encoding="utf-8")
    print(target)
    for scenario in out["scenarios"]:
        print(f"[OK] {scenario['name']} — {len(scenario['trace'])} checkpoints — seed {scenario['seed']}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
