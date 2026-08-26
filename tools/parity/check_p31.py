from pathlib import Path
import sys
root=Path(__file__).resolve().parents[2]
main=(root/'scripts/Main.gd').read_text(encoding='utf-8')
card=(root/'scripts/CardActor.gd').read_text(encoding='utf-8')
proj=(root/'project.godot').read_text(encoding='utf-8')
pc=(root/'legacy_reference/game_engine.py').read_text(encoding='utf-8')
checks=[]
def ok(label, cond):
    checks.append((label, bool(cond)))

# 197 Hashirama
ok('197 Hashirama AOE -100 au début du tour', 'CROISSANCE LUXURIANTE' in main and '_deal_fixed_status_damage(enemy, 100' in main)
ok('197 Hashirama soin 200 seulement si dégâts spéciale', 'if cid == "hashirama" and dealt > 0' in main and 'source.heal(200)' in main)
# 198 Madara
ok('198 Madara immunité spéciale Genjutsu', 'target.card_id == "madara" and special_style_used == "genjutsu"' in main)
ok('198 Madara immunité contrôles incapacitants', 'if card_id == "madara":\n        return true' in card)
ok('198 Madara Susanoo +500 + bouclier 300', '"madara": {"style":"ninjutsu", "bonus":500}' in main and 'elif cid == "madara"' in main and 'source.add_shield(300)' in main)
# 199 Nagato
ok('199 Nagato réduction 200 NIN/GEN', 'target.card_id == "nagato" and style in ["ninjutsu", "genjutsu"]' in main and 'amount = maxi(0, amount - 200)' in main)
ok('199 Nagato bloque Taijutsu après Shinra', 'elif cid == "nagato" and dealt > 0' in main and 'blocked_taijutsu_turns' in main)
# 200 Obito
ok('200 Obito commence intangible', 'if card_id == "obito": status_tags["obito_intangible"] = true' in card)
ok('200 Obito alternance fin de tour adverse', '"obito": actor.status_tags["obito_intangible"] = not bool(actor.status_tags.get("obito_intangible", true))' in main)
ok('200 Obito Kamui détruit boucliers avant impact', 'Kamui offensif détruit réellement les DEUX couches' in main and 'actual_target.shield = 0' in main and 'actual_target.status_tags.erase("kurenai_hidden_shield")' in main)
# 201 Itachi
ok('201 Itachi Tsukuyomi après vrais dégâts HP', 'target.card_id == "itachi" and hp_damage > 0' in main)
ok('201 Itachi immunités Bee/Madara', 'attacker.card_id not in ["killer_bee","madara"]' in main)
ok('201 Itachi Counter-Switch', 'COUNTER-SWITCH — Tsukuyomi' in main)
ok('201 Itachi Katon AOE 350 autres cibles', 'if splash != actual_target' in main and '_apply_attack_damage(source, splash, 350' in main)
# 202 Jiraiya
ok('202 Jiraiya +10 aux 3 arts par tour complet terrain', 'jiraiya_turns_completed' in main and 'actor.stat_buffs["taijutsu"]' in main and '+ 10' in main)
ok('202 Jiraiya Mode ermite permanent', 'source.status_tags["sage_mode"] = true' in main and '+ 200' in main)
# 203 Killer Bee
ok('203 Killer Bee ne perd pas son tour hors scellement', 'if card_id == "killer_bee":\n        return true' in card and 'sealed_turns' in card)
ok('203 Killer Bee spéciale non bloquée', 'special_block_turns' in card and 'card_id != "killer_bee"' in card)
ok('203 Killer Bee bouclier si dégâts >=400', 'elif cid == "killer_bee" and int(result.get("hp_damage", 0)) >= 400' in main and 'source.add_shield(100)' in main)
# 204 Gai
ok('204 Gai seuils 75/50/25 +250 cumulatif', 'var thresholds: Array[int] = [75,50,25]' in main and '+ 250' in main)
ok('204 Gai Hirudora recul non létal', 'source.set_hp(maxi(1, source.hp - 150))' in main)
ok('204 Gai seuil re-évalué après recul Hirudora', 'source.set_hp(maxi(1, source.hp - 150))\n        _apply_threshold_passives(source)' in main)
# 205 Minato
ok('205 Minato Hiraishin gratuit', 'MINATO — GRATUIT' in main and '_ai_minato_free_descriptor' in main)
ok('205 Minato ignore passifs défensifs toutes attaques', 'source != null and source.card_id == "minato"' in main and 'bypass_passives' in main)
ok('205 Minato Rasengan +300 et bouclier KO', '"minato": {"style":"ninjutsu", "bonus":300, "bypass":true}' in main and 'elif cid == "minato" and bool(result.get("killed", false))' in main)
# 206 Naruto
ok('206 Naruto +350 TAI/NIN sous 50%', 'card_id == "naruto" and hp * 2 < max_hp' in card and 'value += 350' in card)
ok('206 Naruto illustration sous 50%', 'naruto_passif_field.png' in card)
ok('206 Naruto Rasengan -100 NIN durée exacte', 'elif cid == "naruto" and dealt > 0' in main and 'add_timed_modifier("ninjutsu", -100, 1, "naruto_rasengan")' in main)
# reference + metadata
ok('snapshot PC contient mêmes règles bloc 197-206', all(x in pc for x in ['Croissance luxuriante','Mode ermite','Maito Gai ouvre une porte','Kamui offensif','Mangekyô éternel']))
ok('P31 metadata', 'Prototype 31 Character Audit I' in proj and 'PROTOTYPE 31 CHARACTER AUDIT I' in main)

failed=[l for l,v in checks if not v]
for l,v in checks: print(('[OK] ' if v else '[FAIL] ')+l)
print(f'\n{len(checks)-len(failed)}/{len(checks)} checks passed')
if failed:
    print('FAILED:', ', '.join(failed)); sys.exit(1)
print('ALL P31 CHARACTER AUDIT I GATES PASSED')
