from __future__ import annotations

import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
PARITY = ROOT / "tools" / "parity"
sys.path.insert(0, str(ROOT))
sys.path.insert(0, str(PARITY))

import check_p22 as p22


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


def test_legacy_p22_without_relocated_validation_or_metadata() -> None:
    p22.test_legacy_p21_without_metadata()
    p22.test_independent_cancellation_static()
    p22.test_direct_attack_explicit_static()
    p22.test_copy_kept_independent()
    p22.test_p22_smoke_delivered()

    main = (ROOT / "scripts" / "Main.gd").read_text(encoding="utf-8")
    require('"MINATO — GRATUIT"' in main and 'timeline_free_button' in main,
            "P22 conservé : vraie case gratuite Minato distincte")
    hira = block(main, 'func _on_hiraishin_pressed()', 'func _announce_zetsu_switch_a2')
    require('_find_live_card("ally", "minato")' in hira and 'selected_actor = minato' in hira,
            "P22 conservé : Hiraishin sélectionne automatiquement Minato")
    commit = block(main, 'func _commit_player_plan', 'func _finish_player_validation_cycle')
    i_a2 = commit.index('steps.append({"descriptor":ai_delayed_action2.duplicate(true)')
    i_free = commit.index('steps.append({"descriptor":free_action_plan.duplicate(true)')
    i_a1 = commit.index('steps.append({"descriptor":action1_plan.duplicate(true)')
    require(i_a2 < i_free < i_a1, "P22 conservé : ordre A2 adverse -> Hiraishin -> A1")


def test_real_30s_timer_static() -> None:
    main = (ROOT / "scripts" / "Main.gd").read_text(encoding="utf-8")
    require('const PHASE_TIMER_LIMIT: float = 30.0' in main,
            "chrono combat = 30 secondes exactes")
    require('phase_timer_seconds = maxf(0.0, phase_timer_seconds - delta)' in main,
            "chrono décrémenté en temps réel")
    require('_tick_phase_timer(delta)' in block(main, 'func _process', 'func _load_card_data'),
            "chrono relié à la boucle de rendu")
    require('phase_timer_label.text = "%02d s" % shown' in main,
            "HUD affiche le vrai temps restant")
    require('Vector2(800.0 - phase_timer_root.size.x * 0.5, 450.0 - phase_timer_root.size.y * 0.5)' in main,
            "chrono apparaît depuis le centre de l'écran")
    require('tween.tween_property(phase_timer_root, "position", target, 0.58)' in main,
            "animation Classic centre -> position haute en 0,58 s")


def test_timer_authority_and_reset_static() -> None:
    main = (ROOT / "scripts" / "Main.gd").read_text(encoding="utf-8")
    should = block(main, 'func _phase_timer_should_run', 'func _reset_phase_timer')
    for token in ['current_turn_team == "ally"', 'not resolving_action', 'not ai_thinking', 'not _replacement_overlay_active()']:
        require(token in should, "chrono suspendu hors décision humaine — " + token)
    start = block(main, 'func _start_team_turn', 'func _end_team_turn')
    require('if team_name == "ally":\n        _reset_phase_timer()' in start,
            "chaque nouveau tour joueur réinitialise le chrono")
    require('else:\n        _stop_phase_timer()' in start,
            "tour IA coupe le chrono humain")
    commit = block(main, 'func _commit_player_plan', 'func _finish_player_validation_cycle')
    require('_stop_phase_timer()' in commit,
            "validation manuelle stoppe le chrono avant résolution")


def test_timeout_exact_classic_semantics() -> None:
    main = (ROOT / "scripts" / "Main.gd").read_text(encoding="utf-8")
    expired = block(main, 'func _on_phase_timer_expired', 'func _refresh_turn_labels')
    require('_commit_player_plan(true)' in expired,
            "timeout valide automatiquement le plan / passe le tour")
    commit = block(main, 'func _commit_player_plan', 'func _finish_player_validation_cycle')
    require('allow_empty: bool = false' in commit,
            "validation automatique possède une voie explicite autorisant un plan vide")
    require('and not allow_empty' in commit,
            "validation manuelle conserve l'interdiction du plan vide")
    require('if not ai_delayed_action2.is_empty():' in commit,
            "timeout ne saute pas une A2 adverse déjà armée")
    require('delayed_action2 = action2_plan.duplicate(true) if not action2_plan.is_empty() else {}' in commit,
            "timeout conserve une A2 joueur déjà préparée")


def test_metadata_p23() -> None:
    main = (ROOT / "scripts" / "Main.gd").read_text(encoding="utf-8")
    app = (ROOT / "scripts" / "AppShell.gd").read_text(encoding="utf-8")
    project = (ROOT / "project.godot").read_text(encoding="utf-8")
    require("PROTOTYPE 23" in main and "BUILD 23" in main, "Battle identifié P23")
    require("BUILD 23" in app and "PROTOTYPE 23" in app, "menu identifié P23")
    require("Prototype 23" in project, "project.godot identifié P23")


def test_p23_smoke_delivered() -> None:
    smoke = ROOT / "tools" / "parity" / "P23CombatTimerSmoke.gd"
    require(smoke.exists(), "Smoke Godot P23 livré")
    text = smoke.read_text(encoding="utf-8")
    for token in ["_reset_phase_timer", "_tick_phase_timer", "_on_phase_timer_expired", "_commit_player_plan"]:
        require(token in text, "Smoke P23 couvre " + token)


def main() -> int:
    print("YUGITO 09 / Prototype 23 — Combat timer / timeout lock\n")
    for test in [
        test_legacy_p22_without_relocated_validation_or_metadata,
        test_real_30s_timer_static,
        test_timer_authority_and_reset_static,
        test_timeout_exact_classic_semantics,
        test_metadata_p23,
        test_p23_smoke_delivered,
    ]:
        print(f"\n== {test.__name__} ==")
        test()
    print("\nALL P23 PARITY GATES PASSED")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
