from __future__ import annotations

import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
PARITY = ROOT / "tools" / "parity"
sys.path.insert(0, str(ROOT))
sys.path.insert(0, str(PARITY))

import check_p19 as p19
from parity_harness_p20 import all_scenarios


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


def test_legacy_p19_gate() -> None:
    for fn in [
        p19.test_legacy_p18_gate,
        p19.test_serialized_ko_queue_static,
        p19.test_temari_tracker_bombs_static,
        p19.test_chidori_mifune_survival_static,
        p19.test_shield_stack_static,
        p19.test_overflow_survival_static,
        p19.test_p19_fixture_runtime,
        p19.test_empty_reserve_static,
        p19.test_p19_smoke_delivered,
    ]:
        fn()


def test_p20_fixture_runtime() -> None:
    fixture = ROOT / "tools" / "parity" / "fixtures" / "pc_expected_p20.json"
    require(fixture.exists(), "fixture PC P20 présente")
    expected = json.loads(fixture.read_text(encoding="utf-8"))
    scenarios = all_scenarios()
    require(expected.get("prototype") == 20, "fixture identifiée Prototype 20")
    require(scenarios == expected.get("scenarios"), "fixture P20 déterministe bit-à-bit")
    names = [x["name"] for x in scenarios]
    require(names == [
        "choji_effective_visual_target",
        "shikamaru_three_turn_links",
        "gengetsu_clone_play_state",
    ], "couverture comportementale P20", str(names))


def test_choji_visual_redirect_static() -> None:
    main = (ROOT / "scripts" / "Main.gd").read_text(encoding="utf-8")
    target_fn = block(main, "func _descriptor_visual_target", "func _launch_descriptor")
    require('return _guard_target(requested, source)' in target_fn,
            "Choji : cible visuelle calculée avec la même garde que le moteur")
    require('sid in ["a3_raikage", "chojuro", "jugo", "omoi", "karui", "mei"]' in target_fn,
            "Choji : spéciales dédiées interceptables couvertes")
    require('sid in ["mifune", "sasuke"]' in target_fn,
            "Choji : exceptions Classic Mifune/Chidori conservées")
    launch = block(main, "func _launch_descriptor", "func _resolve_actor_uid")
    require("var visual_target: YugitoCardActor = _descriptor_visual_target" in launch,
            "animation résout la cible effective avant de tracer")
    require("_spawn_interception_fx(target, visual_target)" in launch,
            "feedback Expansion Akimichi visible")
    require("_spawn_projectile_fx(source.global_position, visual_target.global_position" in launch,
            "trait d'attaque redirigé vers Choji")
    require("_spawn_descriptor_impact.bind(visual_uid" in launch,
            "impact visuel suit lui aussi la cible effective")
    projectile = block(main, "func _spawn_projectile_fx", "func _spawn_impact_fx")
    require("PathFollow2D.new()" in projectile and '"progress_ratio", 1.0' in projectile,
            "animation Classic : projectile mobile le long de la courbe")
    require("_quadratic_points" in projectile and "Line2D.new()" in projectile,
            "animation Classic : courbe + glow")


def test_shikamaru_visual_and_logic_static() -> None:
    main = (ROOT / "scripts" / "Main.gd").read_text(encoding="utf-8")
    card = (ROOT / "scripts" / "CardActor.gd").read_text(encoding="utf-8")
    launch = block(main, "func _launch_descriptor", "func _resolve_actor_uid")
    require('source.card_id == "shikamaru"' in launch and "_spawn_shikamaru_cast_fx" in launch,
            "Shikamaru : animation dédiée au lieu d'un projectile vers la cible libre")
    fx = block(main, "func _spawn_shikamaru_cast_fx", "func _spawn_interception_fx")
    require("candidate.battle_uid == free_uid" in fx,
            "Shikamaru : aucune ombre visuelle vers la cible laissée libre")
    require('body.card_id in ["killer_bee", "madara"]' in fx,
            "Shikamaru : immunités Bee/Madara également respectées visuellement")
    require('free_label.text = "CIBLE LIBRE"' in fx,
            "Shikamaru : cible libre explicitement lisible")
    special = main[main.index('if cid == "shikamaru":'):main.index('if cid == "ino":', main.index('if cid == "shikamaru":'))]
    require('body.status_tags["shadow_turns"] = maxi(3' in special and
            'body.status_tags["shadow_source_uid"] = source.battle_uid' in special,
            "Shikamaru : vrais liens source + durée 3T")
    require('for key in ["rooted_turns", "sai_prison", "shadow_turns", "zetsu_switch_stun"]' in card,
            "Shikamaru : durée Ombres décrémentée aux tours du Ninja lié")
    require('if int(status_tags.get("shadow_turns", 0)) > 0:' in card,
            "Shikamaru : Ombres empêchent réellement d'agir")
    require('target.card_id == "shikamaru" and hp_damage > 0' in main,
            "Shikamaru : rupture uniquement sur vrais dégâts HP")
    require('"OMBRE DES NARA • %dT"' in card,
            "Shikamaru : bandeau noir Classic visible")
    links = block(main, "func _refresh_persistent_status_links", "func _spawn_descriptor_impact")
    require('"OMBRES"' in links and "shadow_source_uid" in links,
            "Shikamaru : lien visuel persistant source→cible")


def test_gengetsu_visual_identity_static() -> None:
    main = (ROOT / "scripts" / "Main.gd").read_text(encoding="utf-8")
    card = (ROOT / "scripts" / "CardActor.gd").read_text(encoding="utf-8")
    require('return "gengetsu_clone"' in card,
            "Gengetsu : illustration clone réellement sélectionnée")
    require('visual_name = "Clone de Gengetsu"' in card and
            "visual_tai = 0" in card and "visual_nin = 0" in card and "visual_gen = 0" in card,
            "Gengetsu : identité/statistiques clone 4800/0/0/0 visibles")
    activate = main[main.index('if cid == "gengetsu":'):main.index('if cid == "tobirama":', main.index('if cid == "gengetsu":'))]
    require('source.max_hp = 4800' in activate and 'source.hp = 4800' in activate and
            "source.refresh_dynamic_identity()" in activate and "source.refresh_status_visuals()" in activate,
            "Gengetsu : activation clone rafraîchit immédiatement la carte")
    restore = block(main, "func _restore_gengetsu_clone", "func _force_return_to_reserve")
    require("actor.refresh_dynamic_identity()" in restore and "actor.refresh_status_visuals()" in restore,
            "Gengetsu : retour à l'original immédiatement visible")
    require('"CLONE EXPLOSIF • EXPLOSION %dT"' in card,
            "Gengetsu : compte à rebours d'explosion en gros bandeau")
    panel = block(main, "func _refresh_selection_panel", "func _refresh_action_buttons")
    require('visual_title = "Clone de Gengetsu"' in panel,
            "Gengetsu : panneau latéral affiche aussi le clone")


def test_status_fx_classic_static() -> None:
    card = (ROOT / "scripts" / "CardActor.gd").read_text(encoding="utf-8")
    require("_status_art_tint" in card,
            "états : voiles pleine illustration présents")
    for text in ["KAMUI • INCIBLABLE", "BRUME • INCIBLABLE", "PALOURDE • INCIBLABLE",
                 "STUN • %dT", "SCELLÉ • %dT", "PRISON DE GLACE • %dT", "PRISON AQUEUSE",
                 "ENRACINÉ • %dT", "JASHIN • %dT", "SEXY JUTSU • %dT"]:
        require(text in card, f"état très visible : {text}")
    require('ino_white_overlay_field.png' in card and 'ino_ghost_field.png' in card,
            "Ino : corps possédé blanc + fantôme comme Tkinter")
    require('"COUNTER-SWITCH"' in card and '"DÉF. MARIONNETTE"' in card and
            '"JINTON OFF"' in card and '"HIRAMEKAREI +%d"' in card,
            "états spéciaux déjà traités renforcés visuellement")
    require('"♥ ×%d"' in card and '"PRÉDICTION ARMÉE"' in card,
            "Kakuzu/Tobi : indicateurs dédiés visibles")
    require('range(mini(5, bombs))' in card,
            "Tobi : bombes visibles individuellement jusqu'à ×5")
    require('"+%d AUTRES EFFETS"' in card,
            "combos lourds : compteur +N au-delà des badges principaux")


def test_dynamic_images_static() -> None:
    card = (ROOT / "scripts" / "CardActor.gd").read_text(encoding="utf-8")
    for token in ["naruto_passif", "gai_stade%d", "jugo_stade%d", "jiraiya_sage", "konohamaru_sexy", "gengetsu_clone"]:
        require(token in card, f"illustration dynamique portée : {token}")
    for asset in [
        "naruto_passif_field.png", "gai_stade1_field.png", "gai_stade2_field.png", "gai_stade3_field.png",
        "jugo_stade1_field.png", "jugo_stade2_field.png", "jiraiya_sage_field.png",
        "konohamaru_sexy_field.png", "gengetsu_clone_field.png", "ino_ghost_field.png", "ino_white_overlay_field.png",
    ]:
        require((ROOT / "assets" / "cards" / asset).exists(), f"asset dynamique présent : {asset}")


def test_card_proportions_everywhere_static() -> None:
    menu = (ROOT / "scripts" / "MenuCard.gd").read_text(encoding="utf-8")
    app = (ROOT / "scripts" / "AppShell.gd").read_text(encoding="utf-8")
    pre = (ROOT / "scripts" / "PreBattle.gd").read_text(encoding="utf-8")
    require("const COMBAT_CARD_H_PER_W: float = 396.0 / 252.0" in menu and
            "requested_w * COMBAT_CARD_H_PER_W" in menu,
            "Draft/Collection/Deck : même ratio 252×396 que le combat")
    require("card.setup(data, Vector2(220, 0)" in app,
            "Collection utilise le ratio de combat")
    require("card.setup(data, Vector2(200, 0)" in app,
            "Deck utilise YugitoMenuCard au ratio de combat")
    require(pre.count("card.setup(data, Vector2(200, 0)") >= 2,
            "Draft + choix des 3 utilisent le ratio de combat")
    require("ScrollContainer" in pre,
            "pré-combat reste scrollable avec les cartes plus hautes")


def test_metadata_p20() -> None:
    main = (ROOT / "scripts" / "Main.gd").read_text(encoding="utf-8")
    app = (ROOT / "scripts" / "AppShell.gd").read_text(encoding="utf-8")
    project = (ROOT / "project.godot").read_text(encoding="utf-8")
    require("PROTOTYPE 20" in main and "BUILD 20" in main,
            "Battle identifié P20")
    require("BUILD 20" in app,
            "menu identifié BUILD 20")
    require("Prototype 20" in project,
            "project.godot identifié P20")


def test_p20_smoke_delivered() -> None:
    smoke = ROOT / "tools" / "parity" / "P20ClassicVisualSmoke.gd"
    require(smoke.exists(), "Smoke Godot P20 livré")
    text = smoke.read_text(encoding="utf-8")
    require("Choji" in text and "Shikamaru" in text and "Gengetsu" in text and "Ino" in text,
            "Smoke P20 couvre les quatre points visuels critiques")


def main() -> int:
    print("YUGITO 09 / Prototype 20 — Classic visual & gameplay parity gate\n")
    tests = [
        test_legacy_p19_gate,
        test_p20_fixture_runtime,
        test_choji_visual_redirect_static,
        test_shikamaru_visual_and_logic_static,
        test_gengetsu_visual_identity_static,
        test_status_fx_classic_static,
        test_dynamic_images_static,
        test_card_proportions_everywhere_static,
        test_metadata_p20,
        test_p20_smoke_delivered,
    ]
    for test in tests:
        print(f"\n== {test.__name__} ==")
        test()
    print("\nALL P20 PARITY GATES PASSED")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
