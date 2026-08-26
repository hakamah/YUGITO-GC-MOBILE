from __future__ import annotations

import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
PARITY = ROOT / "tools" / "parity"
sys.path.insert(0, str(ROOT))
sys.path.insert(0, str(PARITY))

import check_p18 as p18
from parity_harness_p19 import all_scenarios


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


def test_legacy_p18_gate() -> None:
    for fn in [
        p18.test_legacy_p17_gate,
        p18.test_control_immunities_static,
        p18.test_chidori_mifune_static,
        p18.test_temari_persistence_static,
        p18.test_start_turn_order_static,
        p18.test_p18_fixture_runtime,
        p18.test_no_direct_hp_bypass,
    ]:
        fn()


def test_serialized_ko_queue_static() -> None:
    main = (ROOT / "scripts" / "Main.gd").read_text(encoding="utf-8")
    require("var pending_death_replacement_uids: Array[int] = []" in main,
            "P19 : file de K.O. stockée par UID stable")
    require("var death_replacement_dispatch_scheduled: bool = false" in main,
            "P19 : un seul dispatcher de remplacement peut être armé")

    after = block(main, "func _after_damage_resolution", "func _play_special_sound")
    require("_cleanup_context_links_for_departure(target)" in after,
            "K.O. définitif : liens terrain nettoyés avant remplacement")
    require("_queue_death_replacement(target)" in after,
            "K.O. définitif : remplacement sérialisé")
    require("_replace_defeated_actor.bind(target)" not in after,
            "suppression des timers concurrents actor->remplacement")

    queue = block(main, "func _schedule_death_replacement_dispatch", "func _replace_defeated_actor")
    require("pending_death_replacement_uids.has(uid)" in queue and
            "pending_death_replacement_uids.append(uid)" in queue,
            "une même mort n'entre qu'une fois dans la file")
    require("var actor: YugitoCardActor = _resolve_actor_uid(uid)" in queue,
            "dispatcher résout l'UID au dernier moment, sans référence freed")
    require("pending_death_replacement_uids.pop_front()" in queue,
            "ordre FIFO des K.O./remplacements")

    resume = block(main, "func _resume_resolution_after_replacement", "func _schedule_descriptor")
    require("if not pending_death_replacement_uids.is_empty():" in resume and
            "_schedule_death_replacement_dispatch(0.02)" in resume,
            "A2/A1 ne reprend qu'après tous les remplacements de la chaîne")


def test_temari_tracker_bombs_static() -> None:
    main = (ROOT / "scripts" / "Main.gd").read_text(encoding="utf-8")
    force = block(main, "func _force_return_to_reserve", "func _shares_family")
    require(force.index("_explode_tobi_bombs") < force.index("actor.export_state()"),
            "Temari : bombes Tobi explosent avant l'entrée en réserve")
    require('var forced_id: String = str(forced_reserve_choice.get(actor.team_name, ""))' in force,
            "Temari : tracker Ao/Neji/Hinata lu avant l'offre")
    require("candidates = [forced_id]" in force,
            "Temari : tracker force l'unique remplaçant légal")
    choose = block(main, "func _on_replacement_choice_pressed", "func _manual_reserve_exchange")
    require('if mode == "temari":' in choose and "_replace_actor(actor, chosen_id, false)" in choose,
            "Temari : instance soufflée reste une vraie réserve, pas un K.O.")


def test_chidori_mifune_survival_static() -> None:
    main = (ROOT / "scripts" / "Main.gd").read_text(encoding="utf-8")
    damage = block(main, "func _apply_attack_damage", "func _apply_player_overflow")
    clone_idx = damage.index('status_tags.get("gengetsu_clone_active",false)')
    survival_idx = damage.index("# Protection Doton")
    require(clone_idx < survival_idx,
            "Chidori : clone Gengetsu restauré avant matrice de survies")
    require("and not absolute and not self_cost" in damage,
            "Chidori absolu traverse Doton")
    require("if hp_damage >= hp_before and hp_before > 0 and not absolute:" in damage,
            "Chidori absolu traverse survies personnelles/Chiyo/Kabuto")
    require('target.card_id == "onoki"' in damage and "not mifune_trancheur" in damage,
            "Mifune ignore uniquement l'esquive létale Ônoki")
    require('target.card_id == "danzo"' in damage and 'target.card_id == "orochimaru"' in damage and
            'target.card_id == "hidan"' in damage and 'target.card_id == "kakuzu"' in damage and
            'target.card_id == "kankuro"' in damage and 'target.card_id == "mu"' in damage,
            "Mifune conserve les autres survies personnelles")
    after = block(main, "func _after_damage_resolution", "func _play_special_sound")
    require('if target.card_id == "chiyo"' in after,
            "Chidori peut tuer Chiyo mais son passif de mort reste déclenchable")


def test_shield_stack_static() -> None:
    main = (ROOT / "scripts" / "Main.gd").read_text(encoding="utf-8")
    damage = block(main, "func _apply_attack_damage", "func _apply_player_overflow")
    shield_phase = block(damage, "var absorbed: int = 0", "# Multi-clonage Tobirama")
    visible = shield_phase.index("target.shield > 0 and amount > 0")
    hidden = shield_phase.index('status_tags.get("kurenai_hidden_shield", 0)')
    require(visible < hidden, "ordre boucliers : visible puis caché Kurenai")
    mifune = block(damage, "if mifune_trancheur:", "var hp_before: int = target.hp")
    require("mifune_shield: int = target.shield + int(target.status_tags.get(\"kurenai_hidden_shield\", 0))" in mifune,
            "Mifune additionne les deux stocks de bouclier")
    require("amount += int(round(float(mifune_shield) * 0.50))" in mifune and
            "target.shield = 0" in mifune and 'target.status_tags.erase("kurenai_hidden_shield")' in mifune,
            "Mifune convertit 50 % puis détruit visible+caché")



def test_overflow_survival_static() -> None:
    main = (ROOT / "scripts" / "Main.gd").read_text(encoding="utf-8")
    damage = block(main, "func _apply_attack_damage", "func _apply_player_overflow")
    require('var overflow: int = maxi(0, amount - hp_before) if allow_overflow else 0' in damage,
            "surplus calculé sur le dégât de vraie attaque avant survie personnelle")
    doton = damage.index('# Protection Doton')
    onoki = damage.index('target.card_id == "onoki"')
    danzo = damage.index('target.card_id == "danzo"')
    require(doton < danzo and onoki < danzo,
            "Doton/Ônoki annulent avant les survies qui conservent le surplus")
    for cid in ["danzo", "hidan", "kakuzu", "kankuro"]:
        pos = damage.index(f'target.card_id == "{cid}"')
        tail = damage[pos:pos+1800]
        require('_apply_player_overflow(target.team_name, overflow)' in tail,
                f"{cid} : survie conserve le surplus joueur")

def test_p19_fixture_runtime() -> None:
    fixture = ROOT / "tools" / "parity" / "fixtures" / "pc_expected_p19.json"
    require(fixture.exists(), "fixture PC P19 présente")
    expected = json.loads(fixture.read_text(encoding="utf-8"))
    scenarios = all_scenarios()
    names = [x["name"] for x in scenarios]
    fixture_scenarios = expected.get("scenarios", [])
    require(expected.get("prototype") == 19, "fixture identifiée Prototype 19")
    require(len(scenarios) == 9, "P19 : 9 nouveaux scénarios PC ciblés")
    require(names == [x.get("name") for x in fixture_scenarios], "fixture P19 = scénarios rejoués", str(names))
    require(scenarios == fixture_scenarios, "fixture P19 déterministe bit-à-bit")
    required = {
        "chidori_survival_gauntlet", "mifune_survival_gauntlet", "shield_stack_order",
        "temari_links_and_tracker", "source_death_cleanup_without_reserve",
        "three_ko_replacement_queue", "dot_death_passives", "overflow_with_survival",
        "ko_empty_reserve",
    }
    require(set(names) == required, "couverture P19 attendue")



def test_empty_reserve_static() -> None:
    main = (ROOT / "scripts" / "Main.gd").read_text(encoding="utf-8")
    replace = block(main, "func _replace_defeated_actor", "func _ai_choose_replacement_candidate")
    require("if reserve.is_empty():" in replace and "_retire_actor(actor)" in replace,
            "K.O. sans réserve : slot libéré sans fenêtre de remplacement")
    require("_check_victory_state()" in replace and "_resume_resolution_after_replacement()" in replace,
            "K.O. sans réserve : victoire vérifiée puis résolution reprise")


def test_p19_smoke_delivered() -> None:
    smoke = ROOT / "tools" / "parity" / "P19KOSmoke.gd"
    require(smoke.exists(), "Smoke Godot P19 livré")
    text = smoke.read_text(encoding="utf-8")
    require("nettoyage immédiat Jashin / Prison aqueuse" in text and "surplus joueur + survies" in text,
            "Smoke P19 couvre liens, survies, boucliers et surplus")


def test_metadata_p19() -> None:
    main = (ROOT / "scripts" / "Main.gd").read_text(encoding="utf-8")
    app = (ROOT / "scripts" / "AppShell.gd").read_text(encoding="utf-8")
    project = (ROOT / "project.godot").read_text(encoding="utf-8")
    require("PROTOTYPE 19" in main, "Battle identifié P19")
    require("BUILD 19" in main and "BUILD 19" in app, "HUD/menu identifiés BUILD 19")
    require("Prototype 19" in project, "project.godot identifié P19")


def main() -> int:
    print("YUGITO 09 / Prototype 19 — KO, survival & replacement queue parity gate\n")
    tests = [
        test_legacy_p18_gate,
        test_serialized_ko_queue_static,
        test_temari_tracker_bombs_static,
        test_chidori_mifune_survival_static,
        test_shield_stack_static,
        test_overflow_survival_static,
        test_p19_fixture_runtime,
        test_empty_reserve_static,
        test_p19_smoke_delivered,
        test_metadata_p19,
    ]
    for test in tests:
        print(f"\n== {test.__name__} ==")
        test()
    print("\nALL P19 PARITY GATES PASSED")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
