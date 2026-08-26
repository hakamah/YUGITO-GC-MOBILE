from pathlib import Path
import sys
ROOT=Path(__file__).resolve().parents[2]
main=(ROOT/'scripts/Main.gd').read_text(encoding='utf-8')
app=(ROOT/'scripts/AppShell.gd').read_text(encoding='utf-8')
checks=[]
def ck(name, cond):
    checks.append((name,bool(cond)))
    print(('[OK] ' if cond else '[FAIL] ')+name)

# End duel
ck('P44+ solo completion lineage','PROTOTYPE 44 SOLO COMPLETION' in main or 'PROTOTYPE 45 GLOBAL AUDIO' in main or 'PROTOTYPE 46 IDENTITY PROFILE' in main or 'PROTOTYPE 47 GOOGLE AUTH' in main or 'PROTOTYPE 47M LANDSCAPE' in main)
ck('duel end overlay exists','func _show_duel_end_overlay' in main and 'DUEL TERMINÉ' in main)
ck('victory and defeat titles','"VICTOIRE" if victory else "DÉFAITE"' in main)
ck('victory hook opens overlay','_show_duel_end_overlay(victory,result_text)' in main)
ck('end overlay shows turn/player HP/cemetery','TOUR %d' in main and 'PLAYER_HP_MAX' in main and 'CIMETIÈRE' in main)
ck('end overlay replay button','"REJOUER"' in main and 'replay_requested.emit()' in main)
ck('end overlay menu button','return_to_menu_requested.emit()' in main)
ck('result SFX retained','assets/audio/result/victory.mp3' in main and 'assets/audio/result/defeat.mp3' in main)

# Replay/menu wiring
ck('AppShell replay signal connection','battle_instance.connect("replay_requested"' in app)
ck('AppShell menu signal connection','battle_instance.connect("return_to_menu_requested"' in app)
ck('replay recreates battle without clearing session','func _replay_current_battle' in app and 'call_deferred("_spawn_battle_instance")' in app)
replay_block=app[app.find('func _replay_current_battle'):app.find('func _return_from_battle')]
ck('replay keeps GameSession', 'GameSession.clear()' not in replay_block)

# Real journal
ck('journal history array','var battle_journal: Array[String]' in main)
ck('journal writes routed through helper',main.count('_battle_log_set(') > 100 and main.count('_battle_log_append(') > 5)
ck('journal capped','battle_journal.size() > 300' in main)
ck('journal overlay exists','func _build_journal_overlay' in main and 'JOURNAL DU DUEL' in main)
ck('journal button in HUD','journal_button.pressed.connect(_open_battle_journal)' in main)
ck('end screen can open journal','journal_btn.pressed.connect(_open_battle_journal)' in main)
ck('journal newest-first','range(battle_journal.size() - 1, -1, -1)' in main)

# Inspection
ck('inspection overlay exists','func _build_inspection_overlay' in main and 'FICHE NINJA' in main)
ck('inspection HUD button','inspect_button.pressed.connect(_open_selected_inspection)' in main)
ck('inspection usable for selected actor','func _populate_inspection(actor: YugitoCardActor)' in main)
ck('inspection shows passive','PASSIF — %s' in main and 'data.get("passive"' in main)
ck('inspection shows special','SPÉCIALE — %s' in main and 'data.get("special"' in main)
ck('inspection shows effective stats','_actor_effective_stat(actor,"taijutsu")' in main)
ck('inspection shows statuses','ÉTATS ACTIFS' in main and 'actor.status_tags.keys()' in main)
ck('inspection button disabled without selection','inspect_button.disabled = true' in main)
ck('inspection enabled with selection','inspect_button.disabled = false' in main)

# Interaction safety
ck('new overlays block selection','_solo_overlay_active()' in main and 'or _solo_overlay_active()' in main)
ck('journal above end overlay','journal_overlay.z_index = 28000' in main and 'duel_end_overlay.z_index = 26000' in main)
ck('inspection above end overlay','inspection_overlay.z_index = 27000' in main)

fails=[n for n,v in checks if not v]
print(f'\nP44 SOLO COMPLETION: {len(checks)-len(fails)}/{len(checks)}')
if fails:
    print('FAILED:',*fails,sep='\n- ')
    sys.exit(1)
