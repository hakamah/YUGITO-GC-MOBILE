YUGITO 2.0 GODOT — PROTOTYPE 20 CLASSIC VISUAL / GAMEPLAY PARITY
================================================================

Projet YUGITO 09 — verrouillage progressif du moteur PC Classic/Tkinter -> Godot.
P20 ajoute une passe « jeu des 7 différences » : la représentation visuelle doit suivre
la même cible, le même état et la même identité que le moteur de combat.

Démarrage : ouvrir project.godot avec Godot 4.7.2 stable.
Scène principale : Main.tscn (AppShell -> Battle.tscn).

Validation parité :
  python tools/parity/check_gd_structure.py
  python tools/parity/parity_harness_p20.py
  python tools/parity/check_p20.py

Le master gate P20 réexécute les invariants fonctionnels P15 -> P19 avant les nouveaux
contrôles Choji / Shikamaru / Gengetsu / Ino / FX d'état / images dynamiques / ratios.

Smokes Godot disponibles :
  godot --headless --path . --script res://tools/parity/ParitySmoke.gd
  godot --headless --path . --script res://tools/parity/P16BattleSmoke.gd
  godot --headless --path . --script res://tools/parity/P18ControlSmoke.gd
  godot --headless --path . --script res://tools/parity/P19KOSmoke.gd
  godot --headless --path . --script res://tools/parity/P20ClassicVisualSmoke.gd

Voir PROTOTYPE_20_NOTES.md, docs/DEV_7_DIFFERENCES_P20.md et
`docs/PROJET_YUGITO_09_ROADMAP_REFERENCE.md`.
