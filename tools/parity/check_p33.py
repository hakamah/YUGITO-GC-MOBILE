from pathlib import Path
import sys
root=Path(__file__).resolve().parents[2]
main=(root/'scripts/Main.gd').read_text(encoding='utf-8')
card=(root/'scripts/CardActor.gd').read_text(encoding='utf-8')
proj=(root/'project.godot').read_text(encoding='utf-8')
pc=(root/'legacy_reference/game_engine.py').read_text(encoding='utf-8')
checks=[]
def ok(label, cond): checks.append((label,bool(cond)))
# visual + Ino hotfix
ok('liens routés hors illustrations', 'Corridor horizontal dans l\'espace vide entre les deux rangées' in main and 'PackedVector2Array([a, Vector2(a.x, corridor_y), Vector2(b.x, corridor_y), b])' in main)
ok('liens sans gros glow', 'glow.width = width + 5.0' not in main)
ok('Ino source reste inciblable', 'actor.card_id == "ino" and _ino_controlled_body(actor) != null' in main)
ok('corps adverse possédé redevient ciblable', 'if _ino_possessor(actor) != null:\n        return false' in main and 'possessed_by_uid", 0)) > 0: return true' not in card)
ok('voile blanc déplacé sur Ino active', 'if ino_active:\n        _status_texture_overlay("res://assets/cards/ino_white_overlay_field.png"' in card)
# 217 Hidan
ok('217 Hidan survit une fois à 200 PV', 'target.card_id == "hidan"' in main and 'target.set_hp(mini(target.max_hp, 200))' in main)
ok('217 Jashin 5T lié UID Hidan', 'target.status_tags["doom_turns"] = 5' in main and 'doom_source_uid' in main and 'source_actor.card_id == "hidan"' in main)
# 218 Kabuto
ok('218 Kabuto sauve un autre allié une fois', 'target.card_id != "kabuto"' in main and 'kabuto_reanimation_used' in main)
ok('218 Kabuto remet full HP', 'target.set_hp(target.max_hp)' in main)
ok('218 Scalpel bypass absolu', '"kabuto": {"style":"taijutsu", "bonus":300, "bypass":true, "absolute":true}' in main)
# 219 Neji
ok('219 Neji premier contact unique', 'neji_passive_used' in main and 'add_timed_modifier("ninjutsu", -loss, 2' in main)
ok('219 Neji bloque spéciale', 'special_block_turns' in main and 'cid == "neji"' in main)
ok('219 Neji tracker réserve', 'cid in ["neji", "hinata"]' in main and 'tracker_id' in main)
# 220 Rock Lee
ok('220 Lee deux premières TAI +150', 'rock_lee_boosts_left' in card and 'value += 150' in card and 'attacker.status_tags["rock_lee_boosts_left"]' in main)
ok('220 Lee tenue +300 TAI permanent allié', 'target.stat_buffs["taijutsu"]' in main and '+ 300' in main and 'cid == "rock_lee"' in main)
# 221 Sakura
ok('221 Sakura soin propre 25%', 'target.card_id == "sakura"' in main and 'float(hp_damage) * 0.25' in main)
ok('221 Sakura diffuse 10% quand elle est touchée', 'float(hp_damage) * 0.10' in main)
ok('221 Sakura aura 25% sur autres alliés', 'ally.card_id == "sakura"' in main and 'target.heal(maxi(1, int(round(float(hp_damage) * 0.25))))' in main)
ok('221 Sakura KO spécial heal 200', 'cid == "sakura" and bool(result.get("killed", false))' in main and 'source.heal(200)' in main)
# 222 Sasori
ok('222 Sasori riposte Tai max une fois/cycle', 'sasori_counter_used_cycle' in main and 'target.card_id == "sasori" and style == "taijutsu"' in main)
ok('222 Sasori -100 TAI permanent +50 fixe', 'attacker.stat_buffs["taijutsu"]' in main and '- 100' in main and '_deal_fixed_status_damage(attacker,50,"POISON MARIONNETTE SASORI")' in main)
ok('222 Sasori spéciale delayed 100', 'cid == "sasori" and dealt > 0' in main and 'delayed_damage' in main)
# 223 Shikamaru
ok('223 Shikamaru +150 GEN cible plus étoilée', 'card_id == "shikamaru" and style == "genjutsu" and defender_stars > stars' in card and 'value += 150' in card)
ok('223 Shikamaru cible libre + autres Ombres 3T', '_apply_shikamaru_shadows(source, target)' in main and 'maxi(3' in main)
ok('223 Shikamaru cooldown4 + rupture HP', 'special_cooldown = 4' in main and 'target.card_id == "shikamaru" and hp_damage > 0' in main)
# 224 Temari
ok('224 Temari +100 NIN sans avantage', 'source.card_id == "temari" and style == "ninjutsu" and not advantage' in main and 'situational_bonus += 100' in main)
ok('224 Temari AOE +250 + expulsion réserve', 'cid == "temari"' in main and '_force_return_to_reserve(selected_after)' in main)
# 225 Choji
ok('225 Choji interception permanente', '_guard_target' in main and 'ally.card_id == "choji"' in main)
ok('225 Choji pilule +500 TAI 3T', 'add_timed_modifier("taijutsu", 500, 3, "choji_pill")' in main)
# 226 Hinata
ok('226 Hinata riposte 100 et -35% art 2T', 'target.card_id == "hinata" and not immune' in main and 'float(attacker.effective_stat(style)) * 0.35' in main and 'add_timed_modifier(style, -loss_h, 2' in main)
ok('226 Hinata spéciale bouclier + tracker', 'cid == "hinata"' in main and 'source.add_shield(150)' in main and 'tracker_id' in main)
ok('snapshot PC couvre bloc 217-226', all(x in pc for x in ['Rituel de Jashin','Réincarnation','Possession des ombres','Grande rafale','Pilule de combat','32 Points du Hakke']))
ok('P33 metadata', 'Prototype 33 Character Audit III' in proj and 'PROTOTYPE 33 CHARACTER AUDIT III' in main)
failed=[l for l,v in checks if not v]
for l,v in checks: print(('[OK] ' if v else '[FAIL] ')+l)
print(f'\n{len(checks)-len(failed)}/{len(checks)} checks passed')
if failed:
 print('FAILED:', ', '.join(failed)); sys.exit(1)
print('ALL P33 CHARACTER AUDIT III GATES PASSED')
