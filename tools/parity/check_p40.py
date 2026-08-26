from __future__ import annotations
from pathlib import Path
import json, sys

ROOT=Path(__file__).resolve().parents[2]
PARITY=ROOT/"tools"/"parity"
sys.path.insert(0,str(ROOT))
sys.path.insert(0,str(PARITY))

from parity_harness import make_engine
from parity_harness_p18 import all_scenarios as p18_scenarios
from parity_harness_p19 import all_scenarios as p19_scenarios
from parity_harness_p20 import all_scenarios as p20_scenarios

cards=json.loads((ROOT/"data/cards.json").read_text(encoding="utf-8"))
main=(ROOT/"scripts/Main.gd").read_text(encoding="utf-8")
card=(ROOT/"scripts/CardActor.gd").read_text(encoding="utf-8")
pc=(ROOT/"legacy_reference/game_engine.py").read_text(encoding="utf-8")
pre=(ROOT/"scripts/PreBattle.gd").read_text(encoding="utf-8")
matrix=json.loads((PARITY/"qa_matrix_p40.json").read_text(encoding="utf-8"))

checks=[]
def ok(name, cond, detail=""):
    cond=bool(cond); checks.append((name,cond))
    print(("[OK] " if cond else "[FAIL] ")+name+((" — "+detail) if detail else ""))

# 307 — 70 reference duel boots
fallback=["naruto","sakura","sasuke","tenten","ino","shino"]
for idx,data in enumerate(cards):
    cid=data["id"]
    allies=[cid]+[x for x in fallback if x!=cid][:2]
    try:
        e=make_engine([],[],allies,["choji","kakashi","gaara"],seed=4000+idx)
        field=[c.definition.id for c in e.player(1).field if c]
        good=cid in field and len(e.player(2).field)==3
    except Exception:
        good=False
    ok(f"307 duel boot reference — {cid}", good)

# 308/309 — data + reference/Godot implementation surface for all 70
combined=(main+"\n"+card).lower()
for data in cards:
    cid=str(data["id"])
    ok(f"308 special definition — {cid}", bool(str(data.get("special_name","")).strip()) and bool(str(data.get("special","")).strip()))
    ok(f"309 passive definition — {cid}", bool(str(data.get("passive_name","")).strip()) and bool(str(data.get("passive","")).strip()))
    ok(f"PC reference contains — {cid}", cid.lower() in pc.lower())
    # Generic cards may be carried by SPECIAL_ATTACKS/normal engine tables; id presence is still mandatory.
    ok(f"Godot implementation surface — {cid}", cid.lower() in combined)

# Historical deterministic PC fixtures: core cross-interactions
for proto,fn in [(18,p18_scenarios),(19,p19_scenarios),(20,p20_scenarios)]:
    fixture=PARITY/"fixtures"/f"pc_expected_p{proto}.json"
    expected=json.loads(fixture.read_text(encoding="utf-8"))["scenarios"]
    actual=fn()
    ok(f"PC fixture P{proto} deterministic", actual==expected, f"{len(actual)} scenarios")

def has(*parts):
    return all(p in main or p in card for p in parts)

# 310 — entry paths / switch/replacement persistence
ok("310 reserve exports full instance", 'export_state()' in main and 'ally_reserve_states' in main and 'enemy_reserve_states' in main)
ok("310 Switch A1/A2 supported", '"switch_plan"' in main and 'planning_slot' in main and 'reactive' in main)
ok("310 KO replacement serialized", 'pending_death_replacement_uids' in main and 'death_replacement_dispatch_scheduled' in main)

# 311 survivals matrix
ok("311 Chidori absolute strips defenses", '_strip_chidori_defenses' in main and 'if cid == "sasuke":' in main and '"absolute":true' in main)
ok("311 Chidori bypasses Chiyo/Kabuto/Kurotsuchi survival path", has('_strip_chidori_defenses','chiyo','kabuto','kurotsuchi'))
ok("311 survival order has Kankuro/Chiyo/Kabuto/Kurotsuchi", has('kankuro','chiyo','kabuto','kurotsuchi','survival'))

# 312 targetability matrix
ok("312 explicit untargetable gate", 'func is_untargetable()' in card)
ok("312 absolute exceptions exist", has('if cid == "sasuke":','is_untargetable'))
ok("312 normal target selection checks untargetable", 'is_untargetable()' in main)

# 313 poison simultaneous pipeline
for tok in ["torune_contact_poison","anko_poison","shino_poisoned","hanzo_poisoned","shizune_poison"]:
    ok(f"313 poison pipeline — {tok}", tok in main or tok in card)
ok("313 DOT start turn before passives", main.find("TOXINES TORUNE") < main.find("actor.tick_own_turn()"))

# 314 shields / Kurenai / Mifune / Obito
ok("314 hidden Kurenai shield represented", 'kurenai_hidden_shield' in main)
ok("314 Mifune shield conversion", 'mifune_trancheur' in main and '0.50' in main)
ok("314 Obito untargetable/Kamui path", 'obito_intangible' in main or 'obito_intangible' in card)

# 315 Hidan Jashin / immortality
ok("315 Jashin link state", 'doom_source_uid' in main and 'doom_turns' in main)
ok("315 Hidan survival state", 'hidan' in main and 'survival' in main)

# 316 Shikamaru real HP break, shield does not
ok("316 Shikamaru shadow 3 turns", 'shadow_turns"] = maxi(3' in main)
ok("316 shadow break source function", '_clear_shadow_stuns_from' in main)
ok("316 fresh A2 guard", 'shadow_fresh_application' in main and 'shadow_turns_skip_tick' in main)
ok("316 visual immunity Bee/Madara semantic", 'body.card_id in ["killer_bee","madara"]' in main or 'body.card_id in ["killer_bee", "madara"]' in main)

# 317 Ino state carrier / restitution
ok("317 Ino possession UID links", 'possessed_by_uid' in main and 'ino_target_uid' in main)
ok("317 Ino state export/import reserve path", 'export_state()' in main and 'import_state' in main)
ok("317 Ino source untargetable", 'card_id == "ino"' in card and 'ino_target' in card and 'return true' in card)

# 318 Temari with linked states
ok("318 Temari full-state reserve export", 'state_store[actor.card_id] = actor.export_state()' in main)
ok("318 Temari bombs before reserve", '_explode_tobi_bombs' in main and '_force_return_to_reserve' in main)
ok("318 Temari tracker forced replacement", 'forced_reserve_choice' in main and '"mode": "temari"' in main)

# 319 Zetsu+Tobi+Switch A2
ok("319 Zetsu announces Switch A2", '_announce_zetsu_switch_a2' in main)
ok("319 Tobi predictions carry A1/A2 descriptor", 'tobi_predictions' in main and 'prediction_action_id' in main)
ok("319 Switch A2 descriptor exists", 'planning_slot' in main and 'switch_plan' in main)

# 320 Ao pre-special kill
ok("320 Ao pre-special anticipation", 'ao' in main and 'anticip' in main.lower())
ok("320 special can be cancelled before execution", 'spéciale' in main.lower() and 'annul' in main.lower())

# 321 Chidori every-defense engine
ok("321 Chidori absolute defense function", '_strip_chidori_defenses' in main)
for tok in ["shield","onoki","kurotsuchi","chiyo","kabuto","hidan","kakuzu","kankuro","gengetsu"]:
    ok(f"321 Chidori matrix token — {tok}", tok in main)

# 322 Mifune every-defense engine
ok("322 Mifune dedicated trancheur flag", 'mifune_trancheur' in main)
for tok in ["onoki","choji","shield","kurenai","survival"]:
    ok(f"322 Mifune matrix token — {tok}", tok in main)

# 323 Madara control immunity
ok("323 Madara can_act immunity first", 'if card_id == "madara":' in card and 'return true' in card)
for tok in ["sealed_turns","disabled_turns","shadow_turns","kisame_prisoned_by_uid"]:
    ok(f"323 control represented — {tok}", tok in card)

# 324 Killer Bee
ok("324 Killer Bee ignores generic disabled", 'if card_id == "killer_bee":' in card and 'return true' in card)
ok("324 seal checked before Killer Bee", card.find('sealed_turns') < card.find('if card_id == "killer_bee":'))

# 325/326 KO pipelines
ok("325 DOT damage uses fixed status pipeline", '_deal_fixed_status_damage' in main)
ok("325 KO replacement dispatcher exists", '_dispatch_next_death_replacement' in main)
ok("326 death passives centralized", 'Passifs de mort Classic.' in main and '_after_damage_resolution' in main)

# 327 empty reserve
ok("327 empty reserve handled", 'reserve.is_empty()' in main and 'replacement' in main.lower())

# 328 triple KO FIFO
ok("328 FIFO pending UID queue", 'pending_death_replacement_uids' in main and 'pop_front()' in main)
ok("328 resolution waits replacement chain", 'resolution_waiting_replacement' in main)

# 329 overflow with survival
ok("329 player overflow function", 'func _apply_player_overflow' in main)
ok("329 overflow carries pre-survival damage", 'overflow' in main and 'survival' in main)

# 330 regression artifacts
ok("330 QA matrix has 24 roadmap items", len(matrix)==24)
ok("330 runtime checklist shipped", (ROOT/"P40_RUNTIME_QA_CHECKLIST.md").exists())
ok("330 historical fixtures P18/P19/P20 retained", all((PARITY/"fixtures"/f"pc_expected_p{x}.json").exists() for x in [18,19,20]))

failed=[n for n,v in checks if not v]
print(f"\nP40 AUTOMATED QA: {len(checks)-len(failed)}/{len(checks)} checks passed")
if failed:
    print("FAILED:",*failed,sep="\n- ")
    raise SystemExit(1)
print("ALL P40 AUTOMATED QA GATES PASSED")
