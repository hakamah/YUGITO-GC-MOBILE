from pathlib import Path
m=Path('scripts/Main.gd').read_text(); c=Path('scripts/CardActor.gd').read_text(); p=Path('project.godot').read_text()
checks={
'P26 persistent-state rule retained':'preserve_target_links' in m and 'rooted_turns' in m,
'153 rooted visible':'ENRACINÉ %dT' in c,
'154 ice prison visual':'GLACE %dT' in c,
'155 water prison dedicated':'PRISON AQUEUSE • KISAME' in c,
'156 Shikamaru visual link':'OMBRE DES NARA' in c,
'157 Jashin counter':'JASHIN %dT' in c,
'158 poison families distinguished':all(x in c for x in ['POISON SHINO','POISON SALAMANDRE','POISON ANKO','POISON SHIZUNE','NANO-POISON','MICROBIOSE','POISON SASORI']),
'159 Kushina seal countdown':'SCELLÉ %dT' in c,
'160 Sexy Jutsu visible':'SEXY JUTSU %dT' in c,
'161 untargetable identities':all(x in c for x in ['KAMUI','BRUME','PALOURDE','INTANGIBLE','SOUS TERRE','ORIGAMI']),
'162 counter switch badge':'COUNTER-SWITCH' in c,
'163 Yamato gift separate':'DON YAMATO • COUNTER' in c,
'164 Kankuro defense':'DÉF. MARIONNETTE' in c,
'165 Kurotsuchi consumed protection':'DOTON • PROTECTION UTILISÉE' in c,
'166 Kakuzu hearts':'♥ ×%d' in c,
'167 Mu Jinton off':'JINTON OFF' in c,
'168 Hiramekarei stock':'HIRAMEKAREI +%d' in c,
'169 Tobi bomb icons':'for i: int in range(mini(5, bombs))' in c,
'170 Tobi prediction private':'_visible_tobi_prediction_armed' in c,
'171 Ino white body':'ino_white_overlay_field.png' in c and 'ESPRIT TRANSFÉRÉ' in c,
'172 Ino identity/stats':'ino_visual_element' in c and 'ino_visual_tai' in c,
'P27 metadata':'Prototype 27 Status UI Lock' in p and 'PROTOTYPE 27 STATUS UI LOCK' in m,
}
for k,v in checks.items(): print(('[OK] ' if v else '[FAIL] ')+k)
if not all(checks.values()): raise SystemExit(1)
print('\nALL P27 STATUS UI GATES PASSED')
