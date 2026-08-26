from __future__ import annotations

import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
PARITY = ROOT / "tools" / "parity"
sys.path.insert(0, str(ROOT))
sys.path.insert(0, str(PARITY))

import check_p16 as p16
from parity_harness_p17 import all_scenarios


def ok(name: str, detail: str = "") -> None:
    suffix = f" — {detail}" if detail else ""
    print(f"[OK] {name}{suffix}")


def require(cond: bool, name: str, detail: str = "") -> None:
    if not cond:
        suffix = f" — {detail}" if detail else ""
        raise AssertionError(f"[FAIL] {name}{suffix}")
    ok(name, detail)


def test_fixed_damage_semantics_static() -> None:
    text = (ROOT / "scripts" / "Main.gd").read_text(encoding="utf-8")
    body = text[text.index("func _apply_attack_damage"):text.index("func _apply_player_overflow")]
    require("if counts_as_attack and _is_actor_untargetable(target)" in body,
            "dégâts fixes/DOT ne sont pas bloqués par l'inciblabilité")
    require('bool(target.status_tags.get("special_protection"' not in body,
            "Kurenai n'annule plus les AOE/DOT dans le pipeline de dégâts")
    special = text[text.index("func _finish_special_descriptor"):text.index("func _execute_planned_switch")]
    require('bool(protected_body.status_tags.get("special_protection", false))' in special,
            "Kurenai annule uniquement une spéciale explicitement ciblée")
    require('protected_body.status_tags.erase("special_protection")' in special,
            "protection Kurenai consommée à l'annulation ciblée")


def test_gengetsu_karin_jinton_static() -> None:
    text = (ROOT / "scripts" / "Main.gd").read_text(encoding="utf-8")
    require('_apply_attack_damage(actor, clone_enemy, 1300, "status", true, false, false, false, false, false, false)' in text,
            "Gengetsu : explosion = dégâts fixes normaux, pas attaque absolue")
    special = text[text.index("func _finish_special_descriptor"):text.index("func _execute_planned_switch")]
    karin = special[special.index('if cid == "karin":'):special.index('if cid == "haku":')]
    require('_apply_attack_damage(source, source, 1000, "status", true, false, false, false, false, false, false, true, true)' in karin,
            "Karin : coût propre traverse bouclier/Doton mais conserve les survivances")
    jinton = special[special.index('if cid in ["mu","onoki"]:'):special.index('if cid == "omoi":')]
    require("var jinton_execute: bool" in jinton and "if jinton_execute:" in jinton,
            "Jinton : branche exécution séparée")
    require('target.hp, "status", true, false, false, false, false, false, false, true, true' in jinton,
            "Jinton exécution : PV directs, sans bouclier/Doton")
    require('1000, "status", true, false, false, false, false, false, false' in jinton,
            "Jinton non-exécution : 1000 fixes normaux")


def test_true_special_guarding_static() -> None:
    text = (ROOT / "scripts" / "Main.gd").read_text(encoding="utf-8")
    special = text[text.index("func _finish_special_descriptor"):text.index("func _execute_planned_switch")]
    for marker, actor in [
        ("actual_a3", "A 3e Raikage"),
        ("actual_omoi", "Omoi"),
        ("actual_karui", "Karui"),
        ("actual_chojuro", "Chôjûrô"),
        ("actual_jugo", "Jûgo"),
    ]:
        require(f"var {marker}: YugitoCardActor = _guard_target(target, source)" in special,
                f"Choji peut intercepter la spéciale de {actor}")
    a3 = special[special.index('if cid == "a3_raikage":'):special.index('if cid == "asuma":')]
    require('false, false, true, true, false, true, true, true, false' in a3,
            "A 3e : 50 % PV = vraie attaque, ignore bouclier sans bypass absolu")
    karui = special[special.index('if cid == "karui":'):special.index('if cid == "hanzo":')]
    require('false, false, true, true, true, true, true' in karui,
            "Karui : inesquivable mais conserve défenses/inciblabilité")


def test_mei_centering_static() -> None:
    text = (ROOT / "scripts" / "Main.gd").read_text(encoding="utf-8")
    special = text[text.index("func _finish_special_descriptor"):text.index("func _execute_planned_switch")]
    mei = special[special.index('if cid == "mei":'):special.index('if cid == "temari":')]
    require("var center_slot: int = target.seed_index_value() % 3" in mei,
            "Mei : zone centrée sur le slot initial")
    require("var main_mei: YugitoCardActor = _guard_target(target, source)" in mei,
            "Mei : impact principal interceptable par Choji")
    require("for side_slot: int in [center_slot - 1, center_slot + 1]" in mei,
            "Mei : splashs calculés autour de la cible initiale")


def test_links_shadows_copy_static() -> None:
    main = (ROOT / "scripts" / "Main.gd").read_text(encoding="utf-8")
    card = (ROOT / "scripts" / "CardActor.gd").read_text(encoding="utf-8")
    require("shadow_source_uid" in main and "shadow_turns" in card,
            "Shikamaru : liens d'ombres séparés du STUN générique")
    require("func _clear_shadow_stuns_from" in main and 'if target.card_id == "shikamaru" and hp_damage > 0' in main,
            "Shikamaru : rupture liée aux vrais dégâts HP")
    require("kisame_prisoned_by_uid" in main,
            "Kisame : Prison aqueuse liée à l'UID source")
    require("doom_source_uid" in main,
            "Hidan : Jashin lié à l'UID source")
    require("copy_action_button" in main and '"copy_special"' in main,
            "Kakashi : action COPIE distincte dans le HUD")
    require("copied_special_used" in main and "_actor_copied_special_available" in main,
            "Kakashi : ressource de copie indépendante de Raikiri")


def test_survival_order_static() -> None:
    text = (ROOT / "scripts" / "Main.gd").read_text(encoding="utf-8")
    body = text[text.index("func _apply_attack_damage"):text.index("func _apply_player_overflow")]
    idx_kuro = body.index("# Protection Doton")
    idx_survival = body.index("# Survies Classic")
    idx_chiyo = body.index("chiyo_passive_used")
    idx_kabuto = body.index("kabuto_reanimation_used")
    require(idx_kuro < idx_survival < idx_chiyo < idx_kabuto,
            "ordre létal : Doton -> survies propres -> Chiyo -> Kabuto")


def test_tobi_zetsu_static() -> None:
    main = (ROOT / "scripts" / "Main.gd").read_text(encoding="utf-8")
    require('mini(5, int(target.status_tags.get(key_bomb,0)) + 1)' in main,
            "Tobi : bombes plafonnées à 5 par cible")
    require('var amount: int = stacks * 320' in main,
            "Tobi : chaque bombe = 320 dégâts fixes")
    switch = main[main.index("func _execute_planned_switch"):main.index("func _spawn_projectile_fx")]
    require('_explode_tobi_bombs(_opponent_team(outgoing.team_name), outgoing' in switch,
            "Tobi : bombes explosent avant le Switch")
    require('if target.card_id == "tobi":' in main and 'bombed.status_tags.erase(_tobi_bomb_key(dead_tobi_team))' in main,
            "Tobi : mort définitive nettoie toutes ses bombes")
    require('func _trigger_tobi_prediction' in main and '_trigger_tobi_prediction(source, requested_target)' in main and '_trigger_tobi_prediction(source, target)' in main,
            "Tobi : prédiction vérifiée sur attaques normales et spéciales, A1/A2 via même résolveur")
    require('func _clear_failed_tobi_prediction' in main and 'predicted.status_tags.erase(key_bomb)' in main,
            "Tobi : prédiction ratée supprime la pile prédite")
    require('func _announce_zetsu_switch_a2' in main and '_announce_zetsu_switch_a2("enemy", delayed_action2)' in main and '_announce_zetsu_switch_a2("ally", ai_delayed_action2)' in main,
            "Zetsu : Switch A2 adverse révélé aux deux camps")
    spawn = main[main.index("func _spawn_replacement_card"):main.index("func _retire_actor") ]
    require('if not from_death and not reactive and _find_live_card(_opponent_team(team_name),"zetsu") != null:' in spawn,
            "Zetsu : STUN 2T uniquement sur Switch A1")



def test_shield_destruction_static() -> None:
    text = (ROOT / "scripts" / "Main.gd").read_text(encoding="utf-8")
    special = text[text.index("func _finish_special_descriptor"):text.index("func _execute_planned_switch")]
    asuma = special[special.index('if cid == "asuma":'):special.index('if cid == "mifune":')]
    require('target.status_tags.erase("kurenai_hidden_shield")' in asuma,
            "Asuma : détruit bouclier visible + caché Kurenai")
    standard = special[special.index("# Spéciales d'attaque"):special.index('if cid == \"hashirama\" and dealt > 0')]
    require('if cid == "obito" and actual_target != null:' in standard and
            'actual_target.status_tags.erase("kurenai_hidden_shield")' in standard,
            "Obito : détruit les deux boucliers de la cible effective après Choji")
    require('elif cid in ["obito", "kabuto"]' not in standard,
            "Kabuto : n'efface plus physiquement le bouclier")


def test_konohamaru_counter_static() -> None:
    text = (ROOT / "scripts" / "Main.gd").read_text(encoding="utf-8")
    body = text[text.index("func _apply_attack_damage"):text.index("func _apply_player_overflow")]
    require('_deal_fixed_status_damage(source, 350, "Rasengan réflexe", target)' in body,
            "Konohamaru : riposte 350 passe par les dégâts fixes normaux")
    require('source.apply_damage(mini(350' not in body,
            "Konohamaru : aucun retrait direct de PV hors pipeline")

def test_p17_fixture_and_pc_runtime() -> None:
    fixture = ROOT / "tools" / "parity" / "fixtures" / "pc_expected_p17.json"
    require(fixture.exists(), "fixture PC P17 présente")
    expected = json.loads(fixture.read_text(encoding="utf-8"))
    scenarios = all_scenarios()
    names = [x["name"] for x in scenarios]
    fixture_names = [x.get("name") for x in expected.get("scenarios", [])]
    require(len(names) == 15, "P17 : 15 scénarios PC ciblés")
    require(names == fixture_names, "fixture P17 = scénarios rejoués", str(names))
    require(scenarios == expected.get("scenarios"), "fixture P17 déterministe bit-à-bit")
    required = {
        "shikamaru_break", "rescue_chain_chiyo_kabuto", "source_link_cleanup",
        "kakashi_copy_resource", "gengetsu_fixed_explosion", "kurenai_target_only",
        "fixed_ignores_untargetable", "karin_self_cost", "jinton_execute",
        "choji_guards_true_special_attacks", "mei_guard_centering",
        "tobi_bomb_switch", "zetsu_switch_a1_only", "shield_destruction_semantics",
        "konohamaru_fixed_counter",
    }
    require(set(names) == required, "couverture P17 attendue")


def test_reference_and_legacy_gates() -> None:
    # Ré-exécute les fonctions critiques du gate P16 dans le même processus.
    for fn in [
        p16.test_data_parity,
        p16.test_reference_snapshot_integrity,
        p16.test_state_schema_static,
        p16.test_a2_static,
        p16.test_damage_order_static,
        p16.test_haku_static,
        p16.test_rng_static,
        p16.test_p16_harness_and_ino_static,
        p16.test_p16_pc_scenarios,
    ]:
        fn()


def main() -> int:
    print("YUGITO 09 / Prototype 17 — engine parity gate\n")
    tests = [
        test_reference_and_legacy_gates,
        test_fixed_damage_semantics_static,
        test_gengetsu_karin_jinton_static,
        test_true_special_guarding_static,
        test_mei_centering_static,
        test_links_shadows_copy_static,
        test_survival_order_static,
        test_tobi_zetsu_static,
        test_shield_destruction_static,
        test_konohamaru_counter_static,
        test_p17_fixture_and_pc_runtime,
    ]
    for test in tests:
        print(f"\n== {test.__name__} ==")
        test()
    print("\nALL P17 PARITY GATES PASSED")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
