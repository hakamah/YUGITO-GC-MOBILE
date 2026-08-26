YUGITO 09 — BANC DE PARITÉ P20
================================

Objectif : verrouiller progressivement la référence Classic/Tkinter dans Godot,
puis vérifier que le gameplay et sa représentation visuelle racontent la même chose.

Commandes principales :
  python tools/parity/check_gd_structure.py
  python tools/parity/parity_harness_p20.py
  python tools/parity/check_p20.py

Le master gate P20 réexécute les invariants fonctionnels des passes P15 à P19,
puis contrôle la fixture Classic P20 et les invariants visuels/structurels de :
  - Choji : cible effective = cible de l'animation et de l'impact ;
  - Shikamaru : cible choisie libre, ombres sur les autres, liens 3T ;
  - Gengetsu : vraie identité de clone, 4800/0-0-0/2T puis restauration ;
  - Ino : corps vivant + identité visuelle + voile/fantôme ;
  - états : bannières/voiles/cadres beaucoup plus lisibles ;
  - transformations : artworks dynamiques disponibles + Rin/Isobu en marqueur ;
  - cartes hors combat : même ratio externe que la carte de combat Godot.

Fixtures :
  tools/parity/fixtures/pc_expected_p16.json
  tools/parity/fixtures/pc_expected_p17.json
  tools/parity/fixtures/pc_expected_p18.json
  tools/parity/fixtures/pc_expected_p19.json
  tools/parity/fixtures/pc_expected_p20.json

Smokes Godot :
  tools/parity/P16BattleSmoke.gd
  tools/parity/P18ControlSmoke.gd
  tools/parity/P19KOSmoke.gd
  tools/parity/P20ClassicVisualSmoke.gd

Les smokes Godot exigent un exécutable Godot 4.7.x. Le mode RNG déterministe QA
n'est jamais activé en partie normale.
