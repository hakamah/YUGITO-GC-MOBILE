from __future__ import annotations

import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
PARITY = ROOT / "tools" / "parity"
sys.path.insert(0, str(ROOT))
sys.path.insert(0, str(PARITY))

import check_p20 as p20
from parity_harness_p21 import all_scenarios


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


def test_legacy_p20_without_obsolete_status_layout() -> None:
    # Le layout des bandeaux P20 est précisément ce que P21 remplace ; on garde
    # tous les verrous comportementaux/visuels P19-P20 qui restent pertinents.
    for fn in [
        p20.test_legacy_p19_gate,
        p20.test_p20_fixture_runtime,
        p20.test_choji_visual_redirect_static,
        p20.test_gengetsu_visual_identity_static,
        p20.test_dynamic_images_static,
        p20.test_card_proportions_everywhere_static,
    ]:
        fn()


def test_p21_fixture_runtime() -> None:
    fixture = ROOT / "tools" / "parity" / "fixtures" / "pc_expected_p21.json"
    require(fixture.exists(), "fixture PC P21 présente")
    expected = json.loads(fixture.read_text(encoding="utf-8"))
    scenarios = all_scenarios()
    require(expected.get("prototype") == 21, "fixture identifiée Prototype 21")
    require(scenarios == expected.get("scenarios"), "fixture P21 déterministe bit-à-bit")
    require([x["name"] for x in scenarios] == [
        "shikamaru_delayed_a2",
        "tobi_secret_bomb_reference",
    ], "couverture P21 A2 + secret")
    shika = scenarios[0]
    require(shika["shadow_turns"] == [0,3,3] and shika["cooldown"] == 4 and shika["a2_consumed"],
            "PC : Shikamaru A2 = cible libre + deux Ombres 3T + CD4")
    secret = scenarios[1]
    require(secret["target_hidden"] and secret["count_hidden"] and secret["actual_stack"] == 1,
            "PC : bombe Tobi réellement posée mais cible/nombre secrets")


def test_shikamaru_a2_godot_static() -> None:
    main = (ROOT / "scripts" / "Main.gd").read_text(encoding="utf-8")
    require('steps.append({"descriptor":delayed_action2.duplicate(true), "label":"A2 RÉACTION", "delayed":true})' in main,
            "A2 joueur résolue dans la file avec flag delayed")
    require('resolving_delayed_action = bool(step.get("delayed", false))' in main,
            "contexte A2 conservé jusqu'à la résolution")
    special = block(main, 'func _finish_special_descriptor', 'func _restore_gengetsu_clone')
    require('cid not in ["tobi", "shikamaru"]' in special,
            "Shikamaru : la cible LIBRE ne déclenche plus la prédiction Tobi")
    require('var linked_count: int = _apply_shikamaru_shadows(source, target)' in special,
            "Shikamaru A1/A2 passent par le même helper")
    helper = block(main, 'func _apply_shikamaru_shadows', 'func _spawn_shikamaru_cast_fx')
    require('enemy.battle_uid == free_uid' in helper,
            "Shikamaru : cible sélectionnée explicitement laissée libre")
    require('body.card_id in ["killer_bee", "madara"]' in helper,
            "Shikamaru : immunités Bee/Madara conservées")
    require('body.status_tags["shadow_turns"] = maxi(3' in helper and
            'body.status_tags["shadow_source_uid"] = source.battle_uid' in helper,
            "Shikamaru : vrais liens 3T vers la source")
    require('var shadow_phase: String = "A2 RÉACTION" if resolving_delayed_action else phase_label' in special,
            "journal distingue explicitement la résolution Shikamaru A2")


def test_tobi_secret_ui_static() -> None:
    card = (ROOT / "scripts" / "CardActor.gd").read_text(encoding="utf-8")
    main = (ROOT / "scripts" / "Main.gd").read_text(encoding="utf-8")
    helper = block(card, 'func _visible_tobi_bomb_count', 'func status_lines')
    require('if team_name == "enemy"' in helper and 'status_tags.get("tobi_bombs_ally", 0)' in helper,
            "UI : seules NOS bombes sur l'ennemi sont visibles")
    require('return 0' in helper,
            "UI : bombes du Tobi ennemi sur nos cartes masquées")
    require('var bombs: int = _visible_tobi_bomb_count()' in card,
            "FX bombes utilisent le compteur filtré, pas le total secret")
    require('var visible_bombs: int = _visible_tobi_bomb_count()' in card,
            "badges bombes utilisent le compteur filtré")
    require('if _visible_tobi_prediction_armed()' in card,
            "prédiction Tobi filtrée côté UI")
    place = block(main, 'func _place_tobi_bomb', 'func _explode_tobi_bombs')
    require('if owner_team == "ally"' in place and
            'Tobi place secrètement une bombe sur votre terrain.' in place,
            "journal ennemi ne révèle plus cible/nombre de bombe")
    special_scope = block(main, 'func _finish_special_descriptor', 'func _restore_gengetsu_clone')
    tobi_special = block(special_scope, 'if cid == "tobi":', '# Techniques non offensives')
    require('if source.team_name == "ally"' in tobi_special and
            'Tobi prépare secrètement une prédiction.' in tobi_special,
            "journal ennemi ne révèle plus la prédiction exacte")


def test_classic_band_layout_static() -> None:
    card = (ROOT / "scripts" / "CardActor.gd").read_text(encoding="utf-8")
    status = block(card, 'func status_lines()', 'func refresh_status_badges()')
    # Aucun doublon des grands contrôles dans les petits badges du haut.
    for obsolete in [
        'rows.append({"text":"STUN ',
        'rows.append({"text":"OMBRES ',
        'rows.append({"text":"SCELLÉ ',
        'rows.append({"text":"PRISON GLACE ',
        'rows.append({"text":"TOBI • ',
        'rows.append({"text":"PALOURDE • INCIBLABLE',
        'rows.append({"text":"CORPS CONTRÔLÉ',
        'rows.append({"text":"CLONE EXPLOSIF',
    ]:
        require(obsolete not in status, "bandeaux Classic sans doublon badge", obsolete)
    visuals = block(card, 'func refresh_status_visuals()', 'func play_intercept_fx()')
    require('CARD_H * 0.29' in visuals and 'CARD_H * 0.30' in visuals and 'CARD_H * 0.37' in visuals and 'CARD_H * 0.38' in visuals,
            "bandeaux repositionnés aux proportions Tkinter 29/30/37/38 %")
    require('var disabled_visual: bool' in visuals and 'var control_text: String' in visuals,
            "un seul bandeau de contrôle principal")
    require('var band_y:' not in visuals and 'band_count' not in visuals,
            "ancien empilement vertical P20 supprimé")
    require('_status_overlay_label(untargetable_text, 84.0)' in visuals,
            "inciblabilité = petit label de voile, pas gros bandeau empilé")
    require('_status_band("JASHIN %dT" % doom, CARD_H - 92.0' in visuals,
            "Jashin replacé près du bas comme Tkinter")


def test_metadata_p21() -> None:
    main = (ROOT / "scripts" / "Main.gd").read_text(encoding="utf-8")
    app = (ROOT / "scripts" / "AppShell.gd").read_text(encoding="utf-8")
    project = (ROOT / "project.godot").read_text(encoding="utf-8")
    require("PROTOTYPE 21" in main and "BUILD 21" in main, "Battle identifié P21")
    require("BUILD 21" in app, "menu identifié BUILD 21")
    require("Prototype 21" in project, "project.godot identifié P21")


def test_p21_smoke_delivered() -> None:
    smoke = ROOT / "tools" / "parity" / "P21A2SecretStatusSmoke.gd"
    require(smoke.exists(), "Smoke Godot P21 livré")
    text = smoke.read_text(encoding="utf-8")
    for token in ["_apply_shikamaru_shadows", "_visible_tobi_bomb_count", "_visible_tobi_prediction_armed"]:
        require(token in text, "Smoke P21 couvre " + token)


def main() -> int:
    print("YUGITO 09 / Prototype 21 — A2 + secret status parity gate\n")
    tests = [
        test_legacy_p20_without_obsolete_status_layout,
        test_p21_fixture_runtime,
        test_shikamaru_a2_godot_static,
        test_tobi_secret_ui_static,
        test_classic_band_layout_static,
        test_metadata_p21,
        test_p21_smoke_delivered,
    ]
    for test in tests:
        print(f"\n== {test.__name__} ==")
        test()
    print("\nALL P21 PARITY GATES PASSED")
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
