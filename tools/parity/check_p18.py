from __future__ import annotations

import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
PARITY = ROOT / "tools" / "parity"
sys.path.insert(0, str(ROOT))
sys.path.insert(0, str(PARITY))

import check_p17 as p17
from parity_harness_p18 import all_scenarios


def ok(name: str, detail: str = "") -> None:
    print(f"[OK] {name}" + (f" — {detail}" if detail else ""))


def require(cond: bool, name: str, detail: str = "") -> None:
    if not cond:
        raise AssertionError(f"[FAIL] {name}" + (f" — {detail}" if detail else ""))
    ok(name, detail)


def block(text: str, start: str, end: str) -> str:
    i = text.index(start)
    j = text.index(end, i)
    return text[i:j]


def test_legacy_p17_gate() -> None:
    for fn in [
        p17.test_reference_and_legacy_gates,
        p17.test_fixed_damage_semantics_static,
        p17.test_gengetsu_karin_jinton_static,
        p17.test_true_special_guarding_static,
        p17.test_mei_centering_static,
        p17.test_links_shadows_copy_static,
        p17.test_survival_order_static,
        p17.test_tobi_zetsu_static,
        p17.test_shield_destruction_static,
        p17.test_konohamaru_counter_static,
        p17.test_p17_fixture_and_pc_runtime,
    ]:
        fn()


def test_control_immunities_static() -> None:
    card = (ROOT / "scripts" / "CardActor.gd").read_text(encoding="utf-8")
    can = block(card, "func can_act() -> bool:", "func can_use_style(style: String) -> bool:")
    require(can.index('if card_id == "madara":') < can.index('if int(status_tags.get("sealed_turns", 0)) > 0') < can.index('if card_id == "killer_bee":') < can.index('if disabled_turns > 0:'),
            "ordre contrôles : Madara > scellement > Killer Bee > STUN")
    special = block(card, "func special_available() -> bool:", "func consume_special() -> void:")
    require("if not can_act():" in special, "disponibilité spéciale réutilise les immunités d'action")

    main = (ROOT / "scripts" / "Main.gd").read_text(encoding="utf-8")
    sai = block(main, 'if cid == "sai":', 'if cid == "kurenai":')
    require('if target.card_id in ["killer_bee", "madara"]:' in sai,
            "Sai : Bee/Madara résistent à la prison")


def test_chidori_mifune_static() -> None:
    main = (ROOT / "scripts" / "Main.gd").read_text(encoding="utf-8")
    strip = block(main, "func _strip_chidori_defenses", "func _actor_effective_stat")
    require("target.shield = 0" in strip, "Chidori détruit le bouclier visible")
    require('erase("kurenai_hidden_shield")' not in strip,
            "Chidori ignore mais ne détruit pas le bouclier caché Kurenai")

    special = block(main, "func _finish_special_descriptor", "func _execute_planned_switch")
    mifune = block(special, 'if cid == "mifune":', "# Spéciales d'attaque")
    expected = '["nagato","sasuke","gaara","a_raikage","sasori","suigetsu","kurenai","kankuro","chiyo","tobirama","onoki","danzo","orochimaru","hidan","kakuzu","haku","shisui","konohamaru","choji"]'
    require(expected in mifune, "Mifune : liste défensive identique PC")
    damage = block(main, "func _apply_attack_damage", "func _apply_player_overflow")
    require('target.card_id == "onoki"' in damage and "and not mifune_trancheur" in damage,
            "Mifune : Trancheur ignore l'esquive létale Ônoki")


def test_temari_persistence_static() -> None:
    main = (ROOT / "scripts" / "Main.gd").read_text(encoding="utf-8")
    force = block(main, "func _force_return_to_reserve", "func _shares_family")
    require("state_store[actor.card_id] = actor.export_state()" in force,
            "Temari : sauvegarde l'instance complète en réserve")
    require("var had_other_reserve: bool = not reserve.is_empty()" in force and
            "if not had_other_reserve:" in force,
            "Temari : offre calculée avant de réajouter la carte soufflée")
    require('"mode": "temari"' in force and '"candidates": candidates' in force,
            "Temari : remplacement dédié suspend la résolution")
    choices = block(main, "func _on_replacement_choice_pressed", "func _manual_reserve_exchange")
    require('if mode == "temari":' in choices,
            "Temari : choix de remplacement distinct d'un K.O.")
    require("_replace_actor(actor, chosen_id, false)" in choices,
            "Temari : remplaçant = Switch/réserve, pas nouvelle instance de mort")


def test_start_turn_order_static() -> None:
    main = (ROOT / "scripts" / "Main.gd").read_text(encoding="utf-8")
    st = block(main, "func _start_team_turn", "func _end_team_turn")
    markers = [
        "TOXINES TORUNE",
        "POISON ANKO",
        "POISON SHINO",
        "POISON SALAMANDRE",
        "BRUME HANZO",
        "PRISON DE GLACE",
        "POISON SHIZUNE",
        "FURIE KIMIMARO",
        "actor.tick_own_turn()",
        'gengetsu_clone_active',
        'actor.card_id == "tsunade"',
        "CROISSANCE LUXURIANTE",
        'tobi.status_tags["tobi_intangible"]',
    ]
    idx = [st.index(m) for m in markers]
    require(idx == sorted(idx), "ordre début de tour = Classic (DOT -> brume -> prison -> clone -> passifs -> Hashirama -> Tobi)")
    require('actor.card_id == "tsunade" and actor.hp * 2 < actor.max_hp' in st and "actor.heal(200)" in st,
            "Tsunade : +200 au début du tour sous 50 %")
    restore = block(main, "func _restore_gengetsu_clone", "func _force_return_to_reserve")
    require('actor.status_tags.erase("cooldown_skip_tick")' in restore,
            "Gengetsu : recharge sans tour fantôme après destruction/retour")


def test_p18_fixture_runtime() -> None:
    fixture = ROOT / "tools" / "parity" / "fixtures" / "pc_expected_p18.json"
    require(fixture.exists(), "fixture PC P18 présente")
    expected = json.loads(fixture.read_text(encoding="utf-8"))
    scenarios = all_scenarios()
    names = [x["name"] for x in scenarios]
    fixture_scenarios = expected.get("scenarios", [])
    require(expected.get("prototype") == 18, "fixture identifiée Prototype 18")
    require(len(scenarios) == 8, "P18 : 8 scénarios PC ciblés")
    require(names == [x.get("name") for x in fixture_scenarios], "fixture P18 = scénarios rejoués", str(names))
    require(scenarios == fixture_scenarios, "fixture P18 déterministe bit-à-bit")
    required = {
        "chidori_absolute_matrix", "mifune_defense_matrix", "control_immunity_bee_madara",
        "poison_stack_pipeline", "temari_reserve_state", "start_turn_order_gengetsu",
        "tsunade_start_heal", "tobi_after_start_effects",
    }
    require(set(names) == required, "couverture P18 attendue")


def test_no_direct_hp_bypass() -> None:
    main = (ROOT / "scripts" / "Main.gd").read_text(encoding="utf-8")
    # On autorise l'application finale du pipeline ainsi que set_hp pour les
    # mécaniques explicitement absolues/sacrifices. Les retraits arithmétiques
    # sauvages de type target.hp -= X doivent rester absents.
    bad = [line.strip() for line in main.splitlines() if ".hp -=" in line or ".hp = max" in line]
    require(not bad, "aucun nouveau retrait arithmétique direct de PV hors pipeline", str(bad))


def main() -> int:
    print("YUGITO 09 / Prototype 18 — defense, control & reserve parity gate\n")
    tests = [
        test_legacy_p17_gate,
        test_control_immunities_static,
        test_chidori_mifune_static,
        test_temari_persistence_static,
        test_start_turn_order_static,
        test_p18_fixture_runtime,
        test_no_direct_hp_bypass,
    ]
    for test in tests:
        print(f"\n== {test.__name__} ==")
        test()
    print("\nALL P18 PARITY GATES PASSED")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
