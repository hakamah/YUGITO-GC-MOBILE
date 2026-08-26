from pathlib import Path
import sys
ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT/'tools'/'parity'))
from parity_harness import make_engine

def ok(c,m):
    if not c: raise AssertionError(m)
    print('[OK]',m)

def slot(e,p,cid):
    return next(i for i,c in enumerate(e.player(p).field) if c and c.definition.id==cid)

def pc_tracker_runtime():
    e=make_engine(['neji'],['kankuro'],['neji','tenten','ino'],['sakura','shino','karin'],seed=125)
    tracked=e.player(2).deck[-1].id
    ns=slot(e,1,'neji'); target=e.player(2).field[0]
    action={'kind':'special','actor_id':'neji','target_id':target.definition.id,'target_slot':0,'tracker_id':tracked}
    good,msg=e.execute_action_descriptor(1,action)
    assert good,msg
    assert e.forced_reserve_choice[2]==tracked,(tracked,e.forced_reserve_choice)
    # Le prochain switch doit être remplacé par la carte traquée et consommer le verrou.
    outgoing=e.player(2).field[1].definition.id
    other=next(c.id for c in e.player(2).deck if c.id!=tracked)
    good,msg=e.switch_card(2,outgoing,other)
    assert good,msg
    assert any(c and c.definition.id==tracked for c in e.player(2).field)
    assert e.forced_reserve_choice[2] is None
    return tracked

def main():
    main=(ROOT/'scripts/Main.gd').read_text()
    modal=(ROOT/'scripts/ReplacementModal.gd').read_text()
    pc=(ROOT/'legacy_reference/game_engine.py').read_text()
    app=(ROOT/'legacy_reference/app_PC_latest.py').read_text()
    print('YUGITO 09 / Prototype 25 — Byakugan tracker parity gate\n')
    # P24 preserved functionally (metadata intentionally advanced)
    ok('const REPLACEMENT_TIMEOUT_SECONDS := 30.0' in modal,'P24 conservé : remplacement 30 s')
    ok('timeout_choice.emit(best_index)' in modal,'P24 conservé : auto-choix timeout')
    ok('mode not in ["death", "temari"]' in main,'P24 conservé : timeout limité aux remplacements obligatoires')
    # Exact PC planning semantics
    ok('special_id in {"neji", "hinata"}' in app and '"mode":"tracker"' in app,'PC : Neji/Hinata ouvrent le sélecteur tracker après la cible')
    ok('action["tracker_id"] = chosen.id' in app,'PC : choix tracker mémorisé dans le descripteur')
    ok('special_id in {"ao", "neji", "hinata"}' in pc,'PC : Ao/Neji/Hinata partagent le verrou de réserve')
    ok('if current_is_special and current_special_id in ["neji", "hinata"]:' in main,'Godot : Neji/Hinata ouvrent un vrai choix tracker')
    ok('"mode":"byakugan_tracker_plan"' in main,'Godot : contexte privé Byakugan dédié')
    ok('tracker_reserve: Array[String] = enemy_reserve.duplicate()' in main,'Godot : toute la réserve ennemie est proposée')
    ok('_store_planned_action(actor, target_actor, action_id, {"tracker_id":chosen_id})' in main,'Godot : tracker_id choisi est stocké avec la cible offensive')
    ok('_arm_best_tracker(source.team_name)' not in main,'Godot : ancien choix automatique Neji/Hinata supprimé')
    ok('func _arm_tracker_from_descriptor' in main,'Godot : verrou tracker centralisé par descripteur')
    ok('if cid in ["neji", "hinata"]:' in main and '_arm_tracker_from_descriptor(source, descriptor, cid)' in main,'Godot : tracker armé avant impact Neji/Hinata')
    ok('forced_reserve_choice[target_team] = tracked_id' in main,'Godot : prochaine entrée forcée par ID exact')
    ok('if str(forced_reserve_choice.get(old_team, "")) == new_id:' in main,'Godot : consommation uniquement quand la carte forcée entre')
    ok('tracker_actor.status_tags.erase("byakugan_tracker_target")' in main,'Godot : badge tracker nettoyé après consommation')
    tracked=pc_tracker_runtime()
    ok(bool(tracked),'PC runtime : tracker explicite force le prochain Switch puis se consomme')
    ok('BUILD 25 • BYAKUGAN TRACKER LOCK' in main,'HUD identifié P25')
    ok('Prototype 25 Byakugan Tracker Lock' in (ROOT/'project.godot').read_text(),'project.godot identifié P25')
    ok((ROOT/'tools/parity/P25ByakuganTrackerSmoke.gd').exists(),'Smoke Godot P25 livré')
    print('\nALL P25 PARITY GATES PASSED')
if __name__=='__main__': main()
