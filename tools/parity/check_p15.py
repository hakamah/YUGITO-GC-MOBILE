from __future__ import annotations

import hashlib
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
LEGACY = ROOT / "legacy_reference"
sys.path.insert(0, str(ROOT))

from legacy_reference import cards as pc_cards  # noqa: E402
from legacy_reference import game_engine as pc_engine  # noqa: E402


def sha256(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as fh:
        for chunk in iter(lambda: fh.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


def ok(name: str, detail: str = "") -> None:
    suffix = f" — {detail}" if detail else ""
    print(f"[OK] {name}{suffix}")


def require(cond: bool, name: str, detail: str = "") -> None:
    if not cond:
        suffix = f" — {detail}" if detail else ""
        raise AssertionError(f"[FAIL] {name}{suffix}")
    ok(name, detail)


def load_pc_cards():
    definitions = pc_cards.load_cards(LEGACY / "core_set_PC_1.8.21.json")
    return definitions, {c.id: c for c in definitions}


def legal_deck(by_id: dict, required: list[str]) -> list:
    ids = []
    for cid in required:
        if cid not in ids:
            ids.append(cid)
    # Remplissage privilégiant les 3★ pour rester très loin de la limite 32,5★.
    pool = sorted(by_id.values(), key=lambda c: (c.stars, c.name.casefold()))
    for card in pool:
        if len(ids) >= 8:
            break
        if card.id in ids:
            continue
        trial = [by_id[x] for x in ids + [card.id]]
        if pc_engine.GameEngine.deck_respects_star_limit(trial):
            ids.append(card.id)
    deck = [by_id[x] for x in ids]
    require(len(deck) == 8, "deck PC de test construit", str(ids))
    require(pc_engine.GameEngine.deck_respects_star_limit(deck), "deck PC de test légal")
    return deck


def make_engine(req1: list[str], req2: list[str], starters1: list[str], starters2: list[str], seed: int = 1):
    _, by_id = load_pc_cards()
    deck1 = legal_deck(by_id, req1 + starters1)
    deck2 = legal_deck(by_id, req2 + starters2)
    return pc_engine.GameEngine(
        deck1=deck1,
        deck2=deck2,
        starters1=[by_id[x] for x in starters1],
        starters2=[by_id[x] for x in starters2],
        starting_player=1,
        seed=seed,
    )


def test_data_parity() -> None:
    godot = ROOT / "data" / "cards.json"
    pc = LEGACY / "core_set_PC_1.8.21.json"
    require(godot.exists() and pc.exists(), "fichiers cartes présents")
    require(sha256(godot) == sha256(pc), "70 données cartes Godot = PC", sha256(godot))
    require(len(json.loads(godot.read_text(encoding="utf-8"))) == 70, "roster = 70 cartes")


def test_state_schema_static() -> None:
    text = (ROOT / "scripts" / "CardActor.gd").read_text(encoding="utf-8")
    exp = text[text.index("func export_state"):text.index("func import_state")]
    imp = text[text.index("func import_state"):text.index("func _process")]
    fields = [
        "definition_max_hp", "base_max_hp", "max_hp", "taijutsu", "ninjutsu", "genjutsu", "element_name",
        "hp", "shield", "special_used", "special_cooldown", "disabled_turns",
        "kankuro_decoy_used", "kankuro_defense_active", "reactive_entry_guard",
        "synergy_bonus_pct", "status_tags", "stat_buffs", "timed_modifiers",
    ]
    for field in fields:
        require(f'"{field}"' in exp, f"export réserve : {field}")
        require(f'"{field}"' in imp, f"import réserve : {field}")
    require('"state_schema": 2' in exp, "schéma d'état versionné")
    require("setup_logic_only" in text, "acteur logique virtuel disponible")
    synergy = text[text.index("func set_synergy_bonus"):text.index("func synergy_label")]
    require("definition_max_hp" in synergy and 'gengetsu_clone_active' in synergy,
            "synergie PV : base imprimée + exception clone Gengetsu")


def test_a2_static() -> None:
    text = (ROOT / "scripts" / "Main.gd").read_text(encoding="utf-8")
    cancel = text[text.index("func _cancel_plans_for_actor"):text.index("func _descriptor_has_actor")]
    require("delayed_action2 = {}" not in cancel and "ai_delayed_action2 = {}" not in cancel,
            "A2 validée survit au départ source/cible")
    source = text[text.index("func _resolve_descriptor_source"):text.index("func _resolve_descriptor_target")]
    require("actor.card_id == source_id" in source, "A2 retrouve sa source par identité")
    target = text[text.index("func _resolve_descriptor_target"):text.index("func _finish_descriptor_safe")]
    require("actor.card_id == target_id" in target, "A2 cible d'abord l'identité")
    require('reactive_entry_cycle' in target, "suivi de slot limité au Switch A2 réactif")
    require("planned_from_virtual_entry" in text and "_planning_virtual_for_clicked_actor" in text,
            "A1 Switch -> A2 du Ninja entrant planifiable")
    require('"delayed":true' in text, "étape A2 explicitement marquée delayed")
    require("func _try_scheduled_switch_on_death" in text and "SWITCH A2 D'URGENCE" in text,
            "Switch A2 programmé remplace le tirage lors d'un K.O.")


def test_damage_order_static() -> None:
    text = (ROOT / "scripts" / "Main.gd").read_text(encoding="utf-8")
    body = text[text.index("func _apply_attack_damage"):text.index("func _apply_player_overflow")]
    idx_reduce = body.index("if not absolute and not mifune_trancheur and not self_cost:")
    idx_floor = body.index("if counts_as_attack and zero_fallback and amount == 0")
    idx_kimi = body.index('if target.card_id == "kimimaro"')
    idx_shield = body.index("var absorbed: int = 0")
    require(idx_reduce < idx_floor < idx_kimi < idx_shield,
            "ordre dégâts : réductions -> anti-zéro -> Kimimaro -> bouclier")
    require("_is_actor_untargetable(target) and not absolute" in body,
            "inciblabilité vérifiée avant Trancheur")
    pre_mifune = body[:body.index("var mifune_trancheur")]
    require('source.card_id == "mifune"' not in pre_mifune.split("_is_actor_untargetable(target)", 1)[0],
            "Mifune ne contourne plus l'inciblabilité")
    require("if mifune_trancheur:" in body and "kurenai_hidden_shield" in body,
            "Mifune conserve conversion/destruction des boucliers")


def test_haku_static() -> None:
    text = (ROOT / "scripts" / "Main.gd").read_text(encoding="utf-8")
    spawn = text[text.index("func _spawn_replacement_card"):text.index("func _retire_actor")]
    require('if card_id == "haku":' in spawn and 'if card_id == "haku" and reactive' not in spawn,
            "Haku armé à toute entrée depuis réserve")
    damage = text[text.index("func _apply_attack_damage"):text.index("func _apply_player_overflow")]
    require("resolving_delayed_action and bool(target.status_tags.get(\"haku_entry_guard\"" in damage,
            "Haku ne teste sa parade que sur attaque programmée A2")


def test_rng_static() -> None:
    main = (ROOT / "scripts" / "Main.gd").read_text(encoding="utf-8")
    rng = (ROOT / "scripts" / "ParityRNG.gd").read_text(encoding="utf-8")
    require("battle_rng.configure(GameSession.parity_rng_enabled, GameSession.parity_seed)" in main,
            "RNG déterministe branché au combat")
    require(not re.search(r"(?<!battle_rng\.)\brandf\(\)", main), "aucun randf global dans Main")
    require("1664525" in rng and "1013904223" in rng, "LCG portable défini")


def test_pc_reference_behaviour() -> None:
    _, by_id = load_pc_cards()

    # 1) Haku : tout switch l'arme.
    e = make_engine(["haku"], [], ["tenten", "ino", "kiba"], ["sakura", "shino", "karin"], seed=7)
    ok_switch, msg = e.switch_card(1, "tenten", "haku", reactive=False)
    require(ok_switch, "PC : Switch A1 vers Haku", msg)
    haku = next(c for c in e.player(1).field if c and c.definition.id == "haku")
    require(haku.haku_entry_guard is True, "PC : Haku arme Miroirs après Switch A1")

    # 2) Une vraie instance conserve ses états quand elle passe en réserve.
    ino = next(c for c in e.player(1).field if c and c.definition.id == "ino")
    ino.current_hp = 777
    ino.shield = 321
    ino.permanent_buffs["genjutsu"] = 123
    original_identity = id(ino)
    ok_out, _ = e.switch_card(1, "ino", "tenten", reactive=False)
    require(ok_out, "PC : sortie d'Ino en réserve")
    ok_in, _ = e.switch_card(1, "tenten", "ino", reactive=False)
    require(ok_in, "PC : retour d'Ino")
    ino_back = next(c for c in e.player(1).field if c and c.definition.id == "ino")
    require(id(ino_back) == original_identity, "PC : même CardInstance après réserve")
    require((ino_back.current_hp, ino_back.shield, ino_back.permanent_buffs["genjutsu"]) == (777, 321, 123),
            "PC : PV/bouclier/buff persistent")

    # 3) Mifune respecte l'inciblabilité d'Obito.
    e2 = make_engine(["mifune"], ["obito"], ["mifune", "tenten", "ino"], ["obito", "sakura", "shino"], seed=3)
    mifune = next(c for c in e2.player(1).field if c and c.definition.id == "mifune")
    obito_slot = next(i for i, c in enumerate(e2.player(2).field) if c and c.definition.id == "obito")
    hp_damage, killed, immune = e2._deal_damage(2, obito_slot, 900, attacker=mifune, style="taijutsu", is_attack=True)
    require((hp_damage, killed, immune) == (0, False, True), "PC : Mifune ne traverse pas Obito intangible")

    # 4) Anti-zéro après réduction : 100 - 200 Nagato => fallback 200 ici (bonus capé à 100).
    e3 = make_engine([], ["nagato"], ["tenten", "ino", "kiba"], ["nagato", "sakura", "shino"], seed=4)
    attacker = next(c for c in e3.player(1).field if c and c.definition.id == "tenten")
    nagato_slot = next(i for i, c in enumerate(e3.player(2).field) if c and c.definition.id == "nagato")
    hp_damage, killed, immune = e3._deal_damage(2, nagato_slot, 100, attacker=attacker, style="ninjutsu", is_attack=True)
    require(hp_damage == 200 and not killed and not immune, "PC : fallback anti-zéro après réduction", f"hp_damage={hp_damage}")

    # 5) Si le sortant d'un Switch A2 meurt avant le déclenchement normal,
    # l'entrant programmé prend immédiatement la case et aucun tirage n'est proposé.
    e4 = make_engine(["haku"], [], ["tenten", "ino", "kiba"], ["sakura", "shino", "karin"], seed=9)
    e4.delayed_actions[1] = {"kind": "switch", "outgoing_id": "tenten", "incoming_id": "haku"}
    tenten_slot = next(i for i, c in enumerate(e4.player(1).field) if c and c.definition.id == "tenten")
    killer = next(c for c in e4.player(2).field if c is not None)
    hp_damage, killed, immune = e4._deal_damage(1, tenten_slot, 99999, attacker=killer, style="taijutsu", is_attack=True)
    require(killed and not immune, "PC : K.O. du sortant A2")
    replacement = e4.player(1).field[tenten_slot]
    require(replacement is not None and replacement.definition.id == "haku", "PC : Switch A2 d'urgence remplace le tirage")
    require(e4.delayed_actions[1] is None, "PC : Switch A2 d'urgence consommé")
    require(any(c.id == "tenten" for c in e4.player(1).graveyard), "PC : sortant envoyé au cimetière")


def test_reference_snapshot_integrity() -> None:
    a = LEGACY / "game_engine.py"
    b = LEGACY / "game_engine_PC_1.8.21.py"
    require(a.exists() and b.exists(), "snapshots moteur PC présents")
    require(sha256(a) == sha256(b), "game_engine.py = snapshot PC 1.8.21", sha256(a))


def main() -> int:
    print("YUGITO 09 / Prototype 15 — parity gate\n")
    tests = [
        test_data_parity,
        test_reference_snapshot_integrity,
        test_state_schema_static,
        test_a2_static,
        test_damage_order_static,
        test_haku_static,
        test_rng_static,
        test_pc_reference_behaviour,
    ]
    for test in tests:
        print(f"\n== {test.__name__} ==")
        test()
    print("\nALL PARITY GATES PASSED")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
