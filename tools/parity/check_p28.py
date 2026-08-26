from pathlib import Path
R=Path(__file__).resolve().parents[2]
c=(R/'scripts/CardActor.gd').read_text()
m=(R/'scripts/Main.gd').read_text()
a=R/'assets/cards'
checks={
'173 Naruto dynamique':'naruto_passif_field.png' in c and (a/'naruto_passif_field.png').exists(),
'174 Jiraiya ermite':'jiraiya_sage_field.png' in c and (a/'jiraiya_sage_field.png').exists() and 'status_tags["sage_mode"] = true' in m,
'175 Gai 3 stades':all((a/f'gai_stade{i}_field.png').exists() for i in (1,2,3)) and 'gai_gate_count' in m,
'176 Gengetsu clone':'gengetsu_clone' in c and (a/'gengetsu_clone_field.png').exists(),
'177 Jugo 2 stades':all((a/f'jugo_stade{i}_field.png').exists() for i in (1,2)) and 'jugo_stage' in m,
'178 Rin Isobu identité':'visual_name = "Rin • Isobu"' in c and 'rin_isobu_active' in m,
'179 Sexy Jutsu':'konohamaru_sexy' in c and (a/'konohamaru_sexy_field.png').exists(),
'P28 metadata':'PROTOTYPE 28 TRANSFORMATION LOCK' in m,
}
for k,v in checks.items(): print(('[OK] ' if v else '[FAIL] ')+k)
if not all(checks.values()): raise SystemExit(1)
print('ALL P28 TRANSFORMATION GATES PASSED')
