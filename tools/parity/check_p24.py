from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]

def ok(c,m):
    if not c: raise AssertionError(m)
    print('[OK]',m)

def main():
    modal=(ROOT/'scripts/ReplacementModal.gd').read_text()
    main=(ROOT/'scripts/Main.gd').read_text()
    pc=(ROOT/'legacy_reference/app_PC_latest.py').read_text()
    print('YUGITO 09 / Prototype 24 — replacement timeout parity gate\n')
    ok('const REPLACEMENT_TIMEOUT_SECONDS := 30.0' in modal,'remplacement = 30 secondes exactes')
    ok('_timeout_remaining = maxf(0.0, _timeout_remaining - delta)' in modal,'chrono remplacement décrémenté en temps réel')
    ok('timeout_choice.emit(best_index)' in modal,'expiration déclenche un choix automatique')
    ok('stars > best_stars' in modal and 'total > best_total' in modal and 'name > best_name' in modal,'auto-choix = étoiles puis somme stats puis nom, comme PC')
    ok('replacement_modal.timeout_choice.connect(_on_replacement_timeout_choice)' in main,'timeout relié au contrôleur de combat')
    ok('mode not in ["death", "temari"]' in main,'timeout limité aux remplacements obligatoires')
    ok(main.count('candidates,\n        true') >= 1 and 'candidates,\n            true' in main,'K.O. et Grande Rafale arment le chrono')
    ok('30 secondes écoulées : %s entre automatiquement sur le terrain.' in main,'feedback timeout explicite')
    ok('max(\n                offer.options,' in pc and 'c.stars, c.max_hp + c.taijutsu + c.ninjutsu + c.genjutsu, c.name' in pc,'référence PC confirme la règle de choix automatique')
    ok('BUILD 24 • REPLACEMENT TIMEOUT LOCK' in main,'HUD identifié P24')
    ok('Prototype 24 Replacement Timeout Lock' in (ROOT/'project.godot').read_text(),'project.godot identifié P24')
    print('\nALL P24 PARITY GATES PASSED')
if __name__=='__main__': main()
