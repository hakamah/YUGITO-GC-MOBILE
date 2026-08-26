from __future__ import annotations

import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
PARITY = ROOT / "tools" / "parity"
sys.path.insert(0, str(ROOT))
sys.path.insert(0, str(PARITY))

import check_p21 as p21


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


def test_legacy_p21_without_metadata() -> None:
    for fn in [
        p21.test_legacy_p20_without_obsolete_status_layout,
        p21.test_p21_fixture_runtime,
        p21.test_shikamaru_a2_godot_static,
        p21.test_tobi_secret_ui_static,
        p21.test_classic_band_layout_static,
        p21.test_p21_smoke_delivered,
    ]:
        fn()


def test_three_slot_classic_plan_static() -> None:
    main = (ROOT / "scripts" / "Main.gd").read_text(encoding="utf-8")
    require('"MINATO — GRATUIT"' in main and 'timeline_free_button' in main,
            "HUD : vraie case gratuite Minato distincte")
    require('timeline_free_button.pressed.connect(_on_hiraishin_pressed)' in main,
            "HUD : clic case gratuite arme Hiraishin")
    hira = block(main, 'func _on_hiraishin_pressed()', 'func _announce_zetsu_switch_a2')
    require('_find_live_card("ally", "minato")' in hira and 'selected_actor = minato' in hira,
            "Hiraishin : clic sélectionne automatiquement Minato comme Classic")
    validate = block(main, 'func _on_validate_plan_pressed()', 'func _finish_player_validation_cycle')
    i_a2 = validate.index('steps.append({"descriptor":ai_delayed_action2.duplicate(true)')
    i_free = validate.index('steps.append({"descriptor":free_action_plan.duplicate(true)')
    i_a1 = validate.index('steps.append({"descriptor":action1_plan.duplicate(true)')
    require(i_a2 < i_free < i_a1, "ordre validation = A2 adverse -> Hiraishin -> A1")


def test_independent_cancellation_static() -> None:
    main = (ROOT / "scripts" / "Main.gd").read_text(encoding="utf-8")
    require('_mini_cancel_button(Rect2(1540, 198, 32, 28), _cancel_planned_action.bind(1))' in main,
            "HUD : annulation A1 indépendante")
    require('_mini_cancel_button(Rect2(1540, 256, 32, 28), _cancel_planned_action.bind(2))' in main,
            "HUD : annulation A2 indépendante")
    require('_mini_cancel_button(Rect2(1540, 145, 32, 28), _cancel_planned_free)' in main,
            "HUD : annulation Hiraishin indépendante")
    cancel = block(main, 'func _cancel_planned_action', 'func _on_hiraishin_pressed')
    require('removed_was_switch' in cancel and 'planned_from_virtual_entry' in cancel,
            "A1 Switch annulée nettoie uniquement l'A2 virtuelle dépendante")
    require('planning_slot = 2 if not action1_plan.is_empty() else 1' in cancel,
            "annulation A2 restaure le bon slot de préparation")


def test_direct_attack_explicit_static() -> None:
    main = (ROOT / "scripts" / "Main.gd").read_text(encoding="utf-8")
    action = block(main, 'func _on_action_button_pressed', 'func _store_planned_action')
    require('if action_id in ["taijutsu", "ninjutsu", "genjutsu"] and _living_cards("enemy").is_empty()' not in action,
            "choisir un art ne programme plus implicitement l'attaque directe")
    require('direct_attack_button = _action_button' in main and '"ATTAQUE DIRECTE"' in main,
            "HUD : bouton ATTAQUE DIRECTE explicite")
    direct = block(main, 'func _on_direct_attack_pressed', 'func _cancel_planned_free')
    require('normal_action not in ["taijutsu", "ninjutsu", "genjutsu"]' in direct,
            "attaque directe exige un art normal sélectionné")
    require('not _living_cards("enemy").is_empty()' in direct,
            "attaque directe exige les 3 slots ennemis vides")
    require('_store_planned_action(selected_actor, null, current_action)' in direct,
            "attaque directe reste un vrai descripteur A1/A2/Hiraishin")
    require('maxi(100, _actor_effective_stat(source, action_id) / 2)' in main,
            "dégâts directs Classic = max(100, stat/2)")


def test_copy_kept_independent() -> None:
    main = (ROOT / "scripts" / "Main.gd").read_text(encoding="utf-8")
    require('copy_action_button = _action_button(Rect2(1318, 598, 262, 28)' in main,
            "COPIE Kakashi a sa propre ligne et ne partage plus Hiraishin")
    require('copy_action_button.pressed.connect(_on_action_button_pressed.bind("copy_special"))' in main,
            "COPIE Kakashi reste réellement jouable")
    require('free_action_button = timeline_free_button' in main,
            "ancienne zone Hiraishin partagée supprimée")


def test_metadata_p22() -> None:
    main = (ROOT / "scripts" / "Main.gd").read_text(encoding="utf-8")
    app = (ROOT / "scripts" / "AppShell.gd").read_text(encoding="utf-8")
    project = (ROOT / "project.godot").read_text(encoding="utf-8")
    require("PROTOTYPE 22" in main and "BUILD 22" in main, "Battle identifié P22")
    require("BUILD 22" in app and "PROTOTYPE 22" in app, "menu identifié P22")
    require("Prototype 22" in project, "project.godot identifié P22")


def test_p22_smoke_delivered() -> None:
    smoke = ROOT / "tools" / "parity" / "P22TurnPlanSmoke.gd"
    require(smoke.exists(), "Smoke Godot P22 livré")
    text = smoke.read_text(encoding="utf-8")
    for token in ["_on_hiraishin_pressed", "_cancel_planned_action", "_on_direct_attack_pressed"]:
        require(token in text, "Smoke P22 couvre " + token)


def main() -> int:
    print("YUGITO 09 / Prototype 22 — Classic turn plan lock\n")
    for test in [
        test_legacy_p21_without_metadata,
        test_three_slot_classic_plan_static,
        test_independent_cancellation_static,
        test_direct_attack_explicit_static,
        test_copy_kept_independent,
        test_metadata_p22,
        test_p22_smoke_delivered,
    ]:
        print(f"\n== {test.__name__} ==")
        test()
    print("\nALL P22 PARITY GATES PASSED")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
