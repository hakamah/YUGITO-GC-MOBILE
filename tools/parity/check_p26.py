from pathlib import Path
import sys
ROOT=Path(__file__).resolve().parents[2]
main=(ROOT/'scripts/Main.gd').read_text(encoding='utf-8')
card=(ROOT/'scripts/CardActor.gd').read_text(encoding='utf-8')
app=(ROOT/'scripts/AppShell.gd').read_text(encoding='utf-8')
proj=(ROOT/'project.godot').read_text(encoding='utf-8')

def ok(cond,msg):
    if not cond:
        print('[FAIL]',msg); raise SystemExit(1)
    print('[OK]',msg)

print('YUGITO 09 / Prototype 26 R2 — field-lock + persistent-state gate\n')
ok('byakugan_tracker_target' in main, 'P25 conservé : tracker Byakugan explicite')
ok('forced_reserve_choice' in main, 'P25 conservé : réserve forcée centralisée')
ok('PHASE_TIMER_LIMIT: float = 30.0' in main, 'P23/P24 conservés : timers 30 s')

# Règle utilisateur : les états personnels restent dans l'instance de réserve.
exp=card[card.index('func export_state'):card.index('func import_state')]
for tok,label in [
    ('"shield": shield','bouclier persistant'),
    ('"disabled_turns": disabled_turns','STUN persistant'),
    ('"status_tags": status_tags.duplicate(true)','poisons/verrous/tags persistants'),
    ('"stat_buffs": stat_buffs.duplicate(true)','buffs/debuffs persistants'),
    ('"timed_modifiers": timed_modifiers.duplicate(true)','modificateurs temporisés persistants'),
]: ok(tok in exp,label)

# Verrous de terrain volontaires.
lock=main[main.index('func _field_departure_lock_reason'):main.index('func _can_leave_field_voluntarily')]
for tok,label in [
    ('"rooted_turns"','Enraciné bloque le Switch'),
    ('"shadow_turns"','Ombres de Shikamaru bloquent le Switch'),
    ('"kisame_prisoned_by_uid"','Prison aqueuse bloque le Switch'),
    ('"sealed_turns"','Scellement de Kushina bloque le Switch'),
    ('"doom_turns"','Jashin bloque le Switch'),
]: ok(tok in lock,label)

sw=main[main.index('func _execute_planned_switch'):main.index('func _build_status_link_layer')]
ok('_field_departure_lock_reason(outgoing)' in sw, 'Switch A1/A2 revalidé au moment de sa résolution')
open_sw=main[main.index('func _open_tactical_switch_choice'):main.index('func _close_replacement_overlay')]
ok('_field_departure_lock_reason(actor)' in open_sw, 'Switch manuel refusé avant ouverture de la réserve')
ok('_can_leave_field_voluntarily(weakest)' in main, 'IA ne tente pas de Switch illégal')
ok('_can_leave_field_voluntarily(selected_actor)' in main, 'bouton Réserve désactivé sur cible verrouillée')

# Temari : exception explicite, conserve les liens reçus avant export.
tem=main[main.index('func _force_return_to_reserve'):main.index('func _best_reserve_id')]
ok('_cleanup_context_links_for_departure(actor, true)' in tem, 'Temari utilise l’exception preserve_target_links')
ok(tem.index('_cleanup_context_links_for_departure(actor, true)') < tem.index('actor.export_state()'), 'Temari sauvegarde ensuite l’instance complète')

cl=main[main.index('func _cleanup_context_links_for_departure'):main.index('func _replace_actor')]
ok('if not preserve_target_links:' in cl, 'nettoyage cible conditionnel, pas automatique')
ok('actor.status_tags.erase("shadow_source_uid")' in cl, 'branche de nettoyage Ombres disponible hors exception')
ok('actor.status_tags.erase("kisame_prisoned_by_uid")' in cl, 'branche de nettoyage Prison disponible hors exception')
ok('actor.status_tags.erase("doom_source_uid")' in cl, 'branche de nettoyage Jashin disponible hors exception')
ok('actor.status_tags.erase("sealed_turns")' not in cl, 'Scellement Kushina jamais effacé par simple sortie')

# UI 145-152 audit
ok('if rows.size() > 5:' in card and '+%d AUTRES EFFETS' in card, '145/146 : badges dynamiques + compteur +N')
ok('enemy_field_effect_label' in main and 'ally_field_effect_label' in main, '147 : couche dédiée aux états de terrain')
ok('MAKIBISHI • 7% PV MAX À CHAQUE ENTRÉE' in main, '148 : indicateur permanent Makibishi')
ok('source.status_tags["makibishi_active"]' not in main, '148 : Makibishi n’est plus attaché à Tenten')
ok('elif untargetable:' in card and '0.46' in card, '149 : inciblabilité transparente')
ok('disabled_turns > 0' in card and '_status_art_tint' in card, '150 : voile STUN présent')
ok('shield_frame' in card and 'BOUCLIER CACHÉ' in card, '151 : boucliers visibles/cachés séparés')
ok('SPÉ T %d/%d' in card, '152 : cooldown T x/y présent')

ok('PROTOTYPE 26 LINK FIELD STATUS LOCK' in main and 'PROTOTYPE 26 LINK FIELD STATUS LOCK' in app, 'HUD/menu identifiés P26')
ok('Prototype 26 Link Field Status Lock' in proj, 'project.godot identifié P26')
print('\nALL P26 R2 GATES PASSED')
