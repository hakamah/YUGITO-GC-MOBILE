from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
pre=(ROOT/'scripts/PreBattle.gd').read_text(encoding='utf-8')
card=(ROOT/'scripts/CardActor.gd').read_text(encoding='utf-8')
app=(ROOT/'scripts/AppShell.gd').read_text(encoding='utf-8')
main=(ROOT/'scripts/Main.gd').read_text(encoding='utf-8')
proj=(ROOT/'project.godot').read_text(encoding='utf-8')
checks={
'30s prebattle timer':'PREBATTLE_TIMER_SECONDS: float = 30.0' in pre,
'RPS timeout':'context == "rps"' in pre and '_choose_rps(choices[randi() % choices.size()])' in pre,
'RPS delayed reveal':'RPS_REVEAL_DELAY' in pre and '_draw_rps_wait' in pre and '_finish_rps_reveal' in pre,
'RPS tween fluidity':'_animate_result_panel' in pre and 'Tween.TRANS_CUBIC' in pre,
'draft timer':'context == "draft"' in pre and '_timer_badge(stage_root,Rect2(1218,92,96,48),"draft")' in pre,
'draft autopick':'_ai_card_score(d, ally_draft)' in pre,
'left history':'TES CHOIX' in pre and '_draw_pick_history("ally"' in pre,
'right history':'CHOIX ADVERSAIRE' in pre and '_draw_pick_history("enemy"' in pre,
'AI pick reveal':'L\'ADVERSAIRE CHOISIT' in pre and '_commit_ai_reveal' in pre,
'pick reason':'_draft_lock_reason' in pre and 'DÉPASSERAIT 32,5★' in pre and 'QUOTA %.1f★ ATTEINT' in pre,
'preview confirm split':'APERÇU / CONFIRMATION' in pre and 'CONFIRMER' in pre,
'unlock stays available':'Une rareté débloquée reste disponible jusqu\'à la fin.' in pre,
'starter timer':'context == "lineup"' in pre and '_timer_badge(stage_root,Rect2(1434,20,90,52),"lineup")' in pre,
'starter autopick':'ally_starters = _ai_choose_starters(ally_draft)' in pre,
'starter slots':'TES 3 TITULAIRES' in pre and 'EMPLACEMENT %d' in pre,
'enemy starters hidden':'3 NINJAS SÉLECTIONNÉS' in pre and 'CACHÉ' in pre,
'Isobu artwork':'return "rin_isobu"' in card and (ROOT/'assets/cards/rin_isobu_field.png').exists(),
'P30 metadata':'PROTOTYPE 30 PREBATTLE DRAFT UX OVERHAUL' in app and 'PROTOTYPE 30 PREBATTLE DRAFT UX OVERHAUL' in main and 'Prototype 30 Prebattle Draft UX Overhaul' in proj,
}
failed=[k for k,v in checks.items() if not v]
for k,v in checks.items(): print(('[OK] ' if v else '[FAIL] ')+k)
if failed: raise SystemExit('FAILED: '+', '.join(failed))
print('ALL P30 PREBATTLE / DRAFT UX GATES PASSED')
