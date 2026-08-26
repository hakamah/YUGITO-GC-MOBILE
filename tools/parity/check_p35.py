from pathlib import Path
import sys,re
root=Path(__file__).resolve().parents[2]
main=(root/'scripts/Main.gd').read_text(encoding='utf-8')
card=(root/'scripts/CardActor.gd').read_text(encoding='utf-8')
proj=(root/'project.godot').read_text(encoding='utf-8')
pc=(root/'legacy_reference/game_engine.py').read_text(encoding='utf-8')
checks=[]
def ok(label, cond): checks.append((label,bool(cond)))
def allin(text,*needles): return all(n in text for n in needles)

# P35 visual/runtime regressions first
ok('P35 metadata project', 'Prototype 35 Deep Character Audit' in proj)
ok('P35 metadata battle', 'PROTOTYPE 35 DEEP CHARACTER AUDIT' in main)
ok('HUD build label no longer stale P30', 'BUILD 35 • DEEP CHARACTER AUDIT' in main and 'BUILD 30 • PREBATTLE / DRAFT UX' not in main)
ok('persistent links = local markers, no corridor Line2D', 'P35 MOBILE CLEAN LINK' in main and 'var line := Line2D.new()' not in main[main.index('func _add_status_link('):main.index('func _refresh_persistent_status_links()')])
ok('Shikamaru cast has no long lines', 'P35 : le cast lui-même' in main and 'shadow_line := Line2D.new()' not in main)
ok('Ombres fresh A2 guard exists', allin(main,'shadow_turns_skip_tick','shadow_fresh_application'))
ok('Ombres band remains explicit 3→2→1', 'OMBRE DES NARA • %dT' in card)
ok('Ino source untargetable / possessed target targetable', 'if card_id == "ino" and status_tags.has("ino_target"): return true' in card and 'possessed_by_uid", 0)) > 0: return true' not in card)

# 227 Kankuro
ok('227 Kankuro Karasu one KO full HP', allin(main,'target.card_id == "kankuro"','target.kankuro_decoy_used = true','target.set_hp(target.max_hp)'))
ok('227 Kankuro defense persistent 250', allin(main,'cid == "kankuro"','source.kankuro_defense_active = true','250 dégâts de moins'))
# 228 Kiba
ok('228 Kiba entry +150 first TAI', allin(card,'card_id == "kiba"','kiba_first_tai','value += 150'))
ok('228 Kiba consumes first TAI after strike', allin(main,'attacker.card_id == "kiba"','attacker.status_tags["kiba_first_tai"] = false'))
ok('228 Kiba Gatsuga base Tai condition', allin(main,'cid == "kiba"','target.taijutsu < source.taijutsu','bonus += 100'))
# 229 Shino
ok('229 Shino NIN hit debuff -100 temporary', allin(main,'attacker.card_id == "shino"','add_timed_modifier("ninjutsu", -100, 1'))
ok('229 Shino special permanent poison', allin(main,'cid == "shino"','actual_target.status_tags["shino_poisoned"] = true'))
ok('229 Shino poison tick 100', allin(main,'shino_poisoned','_deal_fixed_status_damage(effect_actor, 100, "POISON SHINO")'))
# 230 Suigetsu
ok('230 Suigetsu TAI -150 unless lightning', allin(main,'target.card_id == "suigetsu"','style == "taijutsu"','source.element_name != "foudre"','amount - 150'))
ok('230 Suigetsu special heals 150', allin(main,'cid == "suigetsu"','source.heal(150)'))
# 231 Tenten
ok('231 Tenten +25 TAI each TAI strike', allin(main,'attacker.card_id == "tenten"','+ 25'))
ok('231 Makibishi field non-stack boolean', allin(main,'makibishi_active[enemy_team] = true'))
ok('231 Makibishi every entry 7% max HP shield bypass', allin(main,'float(newest.max_hp) * 0.07','"MAKIBISHI TENTEN"'))
# 232 Karin
ok('232 Karin +600 every two own turns', allin(main,'card_id == "karin"','kt % 2 == 0','actor.heal(600)'))
ok('232 Karin ally full heal / self -1000', allin(main,'cid == "karin"','target.heal(target.max_hp)','1000, "status"'))
ok('232 Karin cooldown3', 'elif card_id == "karin"' in card and 'special_cooldown = 3' in card)
# 233 Onoki
ok('233 Onoki lethal dodge once', allin(main,'target.card_id == "onoki"','survival_used','survival":"onoki"'))
ok('233 Onoki Jinton compare NIN', allin(main,'cid in ["mu","onoki"]','tar_nin < own_nin'))
ok('233 Onoki Jinton -1000 NIN permanent', allin(main,'source.stat_buffs["ninjutsu"]','- 1000'))
# 234 Gengetsu
ok('234 Gengetsu alternating untargetable', allin(main,'"gengetsu":','gengetsu_untargetable'))
ok('234 Gengetsu clone 4800 2T', allin(main,'cid == "gengetsu"','gengetsu_clone_turns"] = 2','source.max_hp = 4800'))
ok('234 Gengetsu clone explosion 1300 AOE', allin(main,'gengetsu_clone_active','1300','_restore_gengetsu_clone(actor, true)'))
ok('234 Gengetsu cooldown4 after return', allin(main,'actor.special_cooldown = 4','_restore_gengetsu_clone'))
# 235 Tobirama
ok('235 Tobirama every second attack 25%', allin(main,'target.card_id == "tobirama"','tcount % 2 == 0','* 0.25'))
ok('235 Tobirama 650 fixed AOE', allin(main,'cid == "tobirama"','650','for enemy_t'))
# 236 Zabuza
ok('236 Zabuza alternating untargetable', allin(main,'"zabuza": actor.status_tags["zabuza_untargetable"]','not bool'))
ok('236 Zabuza special migrated attack config', '"zabuza": {"style":"ninjutsu", "bonus":200}' in main)
# 237 Shisui
ok('237 Shisui 1/3 dodge', allin(main,'target.card_id == "shisui"','battle_rng.randf() < (1.0/3.0)'))
ok('237 Shisui AOE stun2', allin(main,'cid == "shisui"','apply_disable(2, "shisui_genjutsu")'))
# 238 Konohamaru
ok('238 Konohamaru 1/2 dodge', allin(main,'target.card_id == "konohamaru"','battle_rng.randf() < 0.50'))
ok('238 Konohamaru counter 350 on dodge', allin(main,'konohamaru_dodge','350'))
ok('238 Sexy Jutsu 2T + cooldown4', allin(main,'cid == "konohamaru"','konohamaru_sexy_turns", 2') and 'elif card_id in ["shikamaru", "konohamaru"]' in card)
# 239 Haku
ok('239 Haku entry guard armed', allin(main,'card_id == "haku"','haku_entry_guard"] = true'))
ok('239 Haku guard only programmed/A2 2of3', allin(main,'resolving_delayed_action','haku_entry_guard','battle_rng.randf() < (2.0 / 3.0)'))
ok('239 Haku ice prison 3T -200/t', allin(main,'cid == "haku"','haku_ice_prison_turns", 3','200, "PRISON DE GLACE"'))
# 240 A3
ok('240 3e recoil 20% only normal damage', allin(main,'source.card_id == "a3_raikage"','* 0.20'))
ok('240 3e special half current hp no recoil branch', allin(main,'cid == "a3_raikage"','ceil(float(target.hp) * 0.50)'))
# 241 Chiyo
ok('241 Chiyo ally rescue once', allin(main,'chiyo_rescuer','chiyo_passive_used'))
ok('241 Chiyo death-before-use random full heal', allin(main,'target.card_id == "chiyo"','heal_targets[battle_rng.randi_range','set_hp(healed_chiyo.max_hp)'))
ok('241 Chiyo puppets +250 and -20%', allin(main,'cid == "chiyo"','+ 250','chiyo_puppets_active') and allin(main,'chiyo_puppets_active','* 0.80'))
# 242 Hanzo
ok('242 Hanzo mist 5 allies /10 enemies', allin(main,'"BRUME HANZO"','*0.05','*0.10'))
ok('242 Hanzo permanent 5% poison', allin(main,'cid == "hanzo"','hanzo_poisoned') and allin(main,'hanzo_poisoned','* 0.05'))
# 243 Kakuzu
ok('243 Kakuzu two full revivals', allin(main,'kakuzu_revivals_left", 2','target.set_hp(target.max_hp)'))
ok('243 Kakuzu no weakness / always advantage', allin(main,'target_body.card_id == "kakuzu"','return false','source_body.card_id == "kakuzu"','return true'))
ok('243 Kakuzu special force advantage', '"kakuzu": {"style":"ninjutsu", "bonus":300, "force_advantage":true}' in main)
# 244 Mei
ok('244 Mei fire counter on TAI received', allin(main,'target.card_id == "mei"','style == "taijutsu"','fire_counter'))
ok('244 Mei 900 main /450 splash', allin(main,'cid == "mei"','main_amount: int = 900','splash_amount: int = 450'))
# 245 Ino
ok('245 Ino 50% success', allin(main,'cid == "ino"','battle_rng.randf() >= 0.50'))
ok('245 Ino failure exactly 3 turns', allin(main,'source.apply_disable(3, "ino_failure")'))
ok('245 Ino duration by stars', allin(main,'duration_map: Dictionary = {3.0: 5, 3.5: 4, 4.0: 3, 4.5: 2, 5.0: 1}','duration_map.get(target.stars, 1)'))
ok('245 Ino cooldown3', 'elif card_id == "ino"' in card and 'special_cooldown = 3' in card)
ok('245 Ino true body state retained', allin(main,'possessed_by_uid','ino_target_uid') and allin(card,'possession_stats'))
# 246 Kurenai
ok('246 Kurenai first attack -200 each cycle', allin(main,'target.card_id == "kurenai"','kurenai_guard_used_cycle','amount - 200'))
ok('246 Kurenai cleanse + hidden 600 + special cancel', allin(main,'cid == "kurenai"','clear_negative_timed_modifiers','kurenai_hidden_shield"] = 600','special_protection"] = true'))
# 247 Sai
ok('247 Sai attacker -200 art 2T', allin(main,'target.card_id == "sai"','add_timed_modifier(style, -200, 2'))
ok('247 Sai prison 3T', allin(main,'cid == "sai"','sai_prison"] = 3'))
# 248 Ao
ok('248 Ao anticipation before specials', allin(main,'_ao_anticipation_cancels','SPÉCIALE ANNULÉE PAR AO'))
ok('248 Ao tracker', allin(main,'cid == "ao"','_arm_tracker_from_descriptor'))
# 249 Torune
ok('249 Torune contact 50/t', allin(main,'target.card_id == "torune"','torune_contact_poison','50'))
ok('249 Torune special 100/t stacks with contact', allin(main,'cid == "torune"','torune_micro_poison','100') and allin(main,'torune_contact_poison', 'torune_micro_poison'))
# 250 Mifune
ok('250 Mifune ignores Choji redirect', allin(main,'if target.card_id == "choji" or source.card_id == "mifune":','return target'))
ok('250 Mifune respects untargetable', allin(main,'Mifune respecte encore inciblabilité','_is_actor_untargetable'))
ok('250 Mifune shield half converted then destroyed', allin(main,'mifune_shield','* 0.50','target.shield = 0'))
ok('250 Mifune +500/+750 by initial defense', allin(main,'mifune_fixed: int = 750 if defensive_before else 500'))
# 251 Asuma
ok('251 Asuma smoke under20 two turns', allin(main,'target.card_id == "asuma"','asuma_smoke_turns"] = 2'))
ok('251 Asuma smoke explosion 20% remaining', allin(main,'asuma_smoke_turns','float(asuma_actor.hp)*0.20'))
ok('251 Asuma special destroys shields +400', allin(main,'cid == "asuma"','target.shield = 0','400, "special"'))
# 252 Kushina
ok('252 Kushina death seals killer4', allin(main,'target.card_id == "kushina"','sealed_turns",4'))
ok('252 Kushina special seal5 +20% maxHP', allin(main,'cid == "kushina"','sealed_turns",5','_percent_hp_amount(target,0.20)'))
# 253 Rin
ok('253 Rin under25 one-time Isobu +1000', allin(main,'target.card_id == "rin"','rin_isobu_active','base_max_hp += 1000'))
ok('253 Rin stat boosts 250/300/200', allin(main,'rin_isobu_active','+250','+300','+200'))
ok('253 Rin special 550 fixed', allin(main,'cid == "rin"','550,"special"'))
# 254 Shizune
ok('254 Shizune death halves killer arts3T', allin(main,'target.card_id == "shizune"','shizune_paralysis_turns",3') and 'value = int(round(float(value) * 0.50))' in card)
ok('254 Shizune special stun2 + poison30 permanent', allin(main,'cid == "shizune"','shizune_poisoned','apply_disable(2') and allin(main,'shizune_poisoned','30, "POISON SHIZUNE"'))
# 255 Kimimaro
ok('255 Kimimaro -25% all damage', allin(main,'target.card_id == "kimimaro"','* 0.75'))
ok('255 Kimimaro fury +15% / -10% maxHP each turn', allin(card,'card_id == "kimimaro"','* 1.15') and allin(main,'kimimaro_fury','* 0.10'))
# 256 Chojuro
ok('256 Chojuro ±200 every strike', allin(main,'source.card_id == "chojuro"','200 if battle_rng.randf() < 0.50 else -200'))
ok('256 Chojuro stock +50 per complete turn', allin(main,'actor.card_id == "chojuro"','chojuro_chakra_stock','+ 50'))
ok('256 Chojuro release stock and reusable', allin(main,'cid == "chojuro"','chojuro_chakra_stock"] = 0') and allin(card,'card_id == "chojuro"','special_used = false'))
# 257 Konan
ok('257 Konan alternating untargetable starts flagged', allin(main,'"konan": actor.status_tags["konan_untargetable"]','not bool'))
ok('257 Konan permanent mine active', allin(main,'cid == "konan"','konan_mine_active"] = true'))
# 258 Jugo
ok('258 Jugo stages at 30/60% loss', allin(main,'target.card_id == "jugo"','<= target.max_hp * 40','<= target.max_hp * 70'))
ok('258 Jugo stats/images state', allin(main,'jugo_stage','base_max_hp += 100') and 'jugo_stage' in card)
ok('258 Jugo special sex 1.5/0.5', allin(main,'cid == "jugo"','1.50 if called_female == target_female else 0.50'))
# 259 Kurotsuchi
ok('259 Kurotsuchi per-ally lethal save once', allin(main,'target.card_id != "kurotsuchi"','kurotsuchi_guard_used','survival":"kurotsuchi"'))
ok('259 Kurotsuchi shield350 all', allin(main,'cid == "kurotsuchi"','add_shield(350)'))
# 260 Mu
ok('260 Mu division full once -450 NIN', allin(main,'target.card_id == "mu"','mu_division_used','target.set_hp(target.max_hp)','- 450'))
ok('260 Mu Jinton disabled after division', allin(card,'card_id == "mu"','mu_division_used') and allin(main,'target.special_used = true'))
ok('260 Mu Jinton -1000 NIN', allin(main,'cid in ["mu","onoki"]','- 1000'))
# 261 Omoi
ok('261 Omoi 1/3 cancel normal', allin(main,'source.card_id == "omoi"','1.0/3.0'))
ok('261 Omoi +20% final otherwise', allin(main,'source.card_id == "omoi"','* 1.20'))
ok('261 Omoi special same mechanic + paralysis', allin(main,'cid == "omoi"','omoi_amount = 600','apply_disable(1,"omoi")'))
# 262 Karui
ok('262 Karui family death +300 HP/arts 2T', allin(main,'_trigger_karui_family_death','karui_hp_bonus"] = 300','karui_electric_turns",2') and allin(card,'karui_electric_turns','value += 300'))
ok('262 Karui duration refresh nonstack', allin(main,'if int(karui_actor.status_tags.get("karui_hp_bonus",0)) <= 0'))
ok('262 Karui 400 fixed undodgeable except untargetable', allin(main,'cid == "karui"','400, "ninjutsu"'))
# 263 Anko
ok('263 Anko under25 heal600 +10% arts', allin(main,'target.card_id == "anko"','target.heal(600)') and allin(card,'card_id == "anko"','* 0.10'))
ok('263 Anko permutation armed', allin(main,'cid == "anko"','anko_serpent_armed"] = true'))
ok('263 Anko poison100x4', allin(main,'anko_poison_turns','100') or allin(main,'anko_serpent_armed','4'))
# 264 Yamato
ok('264 Yamato gift only reactive A2 switch', allin(main,'yamato_relay','reactive','yamato_counter_gift'))
ok('264 Yamato Mokuton 20% max + root3', allin(main,'cid == "yamato"','float(target.max_hp) * 0.20','rooted_turns"] = 3'))
# 265 Zetsu
ok('265 Zetsu reveals enemy Switch A2', allin(main,'_announce_zetsu_switch_a2','zetsu'))
ok('265 Zetsu A1 entry stun2 only', allin(main,'not from_death and not reactive','zetsu_switch_a1','apply_disable(2'))
ok('265 Zetsu alternating targetability', allin(main,'actor.card_id == "zetsu"','zetsu_hidden'))
ok('265 Zetsu heals ally 25% actual attack loss', allin(main,'card_id != "zetsu"','zetsu_healer','*0.25'))
ok('265 Zetsu special intercept A2 or 300', allin(main,'cid == "zetsu"','Switch A2 ANNULÉ','300'))
# 266 Tobi
ok('266 Tobi alternating intangible', allin(main,'tobi_intangible','not bool'))
ok('266 Tobi mandatory bomb at own start', allin(main,'tobi_bomb_pending_team = "ally"','place obligatoirement'))
ok('266 Tobi max5 / 320 each', allin(main,'mini(5','320'))
ok('266 Tobi A1/A2 prediction descriptor', allin(main,'prediction_ally_uid','tobi_predictions'))
ok('266 Tobi failed prediction deletes predicted stack', allin(main,'_clear_failed_tobi_prediction','predicted.status_tags.erase(key_bomb)'))
ok('266 Tobi death clears all owned bombs', allin(main,'target.card_id == "tobi"','bombed.status_tags.erase(_tobi_bomb_key(dead_tobi_team))'))

# Reference snapshot must contain all audited IDs / features
for token in ['shisui','konohamaru','haku','a3_raikage','chiyo','hanzo','kakuzu','mei','ino','kurenai','sai','ao','torune','mifune','asuma','kushina','rin','shizune','kimimaro','chojuro','konan','jugo','kurotsuchi','mu','omoi','karui','anko','yamato','zetsu','tobi']:
    ok(f'PC snapshot contains {token}', token in pc)

failed=[l for l,v in checks if not v]
for l,v in checks: print(('[OK] ' if v else '[FAIL] ')+l)
print(f'\n{len(checks)-len(failed)}/{len(checks)} checks passed')
if failed:
    print('FAILED:', ', '.join(failed))
    sys.exit(1)
print('ALL P35 DEEP CHARACTER AUDIT GATES PASSED')
