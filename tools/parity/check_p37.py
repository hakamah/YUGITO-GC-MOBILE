from pathlib import Path
import sys
ROOT=Path(__file__).resolve().parents[2]
app=(ROOT/'scripts/AppShell.gd').read_text(encoding='utf-8')
checks=[]
def ck(n,c):
 checks.append((n,bool(c))); print(('[OK] ' if c else '[FAIL] ')+n)
ck('286 full guide replaces summary','Manuel de combat YUGITO' in app and '_classic_guide_bbcode' in app)
ck('287 element wheel','FEU[/b][/color] →' in app and '×1,10 puis +150' in app)
ck('288 A1/A2 visual example','A1 / A2 — EXEMPLE' in app and 'CASE A1' in app and 'CASE A2' in app)
ck('288 A2 resolves on opponent validation','avant ses actions' in app)
ck('289 Hiraishin free','HIRAISHIN GRATUIT — MINATO' in app and 'troisième action indépendante' in app)
ck('289 Hiraishin order','A2 adverse → Hiraishin gratuit → A1 immédiate' in app)
ck('290 Switch A1/A2','SWITCH A1 / SWITCH A2' in app and 'Switch A1' in app and 'Switch A2' in app)
ck('290 field locks documented','Jashin, Prison aqueuse, Scellement Kushina et Ombres des Nara' in app)
ck('291 defenses states','DÉFENSES & ÉTATS' in app and 'Inciblable' in app and 'Esquive' in app and 'Bouclier' in app and 'Réduction' in app and 'Survie' in app)
ck('292 cooldowns','COOLDOWNS' in app and 'ne réinitialise pas gratuitement' in app)
ck("293 synergies","Famille complète de 3 : +20 %" in app and "Deux membres d'une famille : +12,5 %" in app)
ck('293 no stacking','le meilleur bonus applicable' in app and 'ratio de PV' in app)
ck('294 damage categories','DÉGÂTS FIXES / VRAIE ATTAQUE / SURPLUS' in app)
ck("294 overflow player HP","l'excédent frappe les [b]PV joueur[/b]" in app)
ck('guide chapter navigation','func _guide_jump' in app and 'CHAPITRES' in app)
ck('P37 metadata','PROTOTYPE 37 COMPLETE CLASSIC GUIDE' in app)
fails=[n for n,v in checks if not v]
print(f'\nP37: {len(checks)-len(fails)}/{len(checks)}')
if fails:
 print(*fails,sep='\nFAIL: '); sys.exit(1)
