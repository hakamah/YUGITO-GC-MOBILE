from pathlib import Path

ROOT=Path(__file__).resolve().parents[2]
main=(ROOT/'scripts/Main.gd').read_text(encoding='utf-8')
card=(ROOT/'scripts/CardActor.gd').read_text(encoding='utf-8')
proj=(ROOT/'project.godot').read_text(encoding='utf-8')
checks=[]
def check(name, cond):
    checks.append((name,bool(cond)))
    print(('[OK] ' if cond else '[FAIL] ')+name)

check('Shikamaru A1/A2 utilisent le même helper', 'var linked_count: int = _apply_shikamaru_shadows(source, target)' in main)
check('A2 est explicitement reconnue comme réaction', '"A2 RÉACTION" if resolving_delayed_action else phase_label' in main)
check('cible choisie reste libre', 'enemy.battle_uid == free_uid' in main)
check('Ombres posées exactement 3T minimum', 'body.status_tags["shadow_turns"] = maxi(3' in main)
check('Ombres bloquent réellement can_act', 'if int(status_tags.get("shadow_turns", 0)) > 0:' in card and 'return false' in card)
check('bandeau OMBRE DES NARA existe', 'OMBRE DES NARA • %dT' in card)
check('cache overlay invalidable explicitement', 'func force_refresh_status_visuals()' in card and '_last_status_visual_signature = ""' in card)
check('application Ombres force le rendu', 'body.force_refresh_status_visuals()' in main)
check('resync mobile différé après Ombres', 'func _schedule_shikamaru_mobile_visual_sync' in main and 'create_timer(0.08)' in main)
check('resync mobile rebâtit les liens', 'func _refresh_shikamaru_mobile_visuals' in main and '_refresh_persistent_status_links()' in main)
check('branche spéciale demande resync après consommation', main.count('_schedule_shikamaru_mobile_visual_sync(source.battle_uid)') >= 2)
check('immunités Bee/Madara préservées', 'body.card_id in ["killer_bee", "madara"]' in main)
check('rupture si Shikamaru prend vrais dégâts HP', 'if target.card_id == "shikamaru" and hp_damage > 0:' in main)
check('verrou Switch Ombres conservé', 'return "OMBRES DE SHIKAMARU"' in main)
check('metadata P31.1', 'Prototype 31.1 Shikamaru Mobile Lock' in proj)

ok=sum(v for _,v in checks)
print(f'\n{ok}/{len(checks)} checks passed')
raise SystemExit(0 if ok==len(checks) else 1)
