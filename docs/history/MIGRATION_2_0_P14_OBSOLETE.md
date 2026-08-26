# YUGITO 2.0 — Godot migration

## Prototype 02 — Cinematic UI
Cette itération conserve les données et la référence gameplay du prototype 01,
mais remplace la direction visuelle temporaire par une proposition beaucoup plus
moderne : verre sombre, profondeur, cartes GPU redessinées, hover physique et
mise en scène de l'arène.

## Ce qui est volontairement encore fictif
- Action 1 / Action 2 ne déclenchent pas encore `game_engine.py`.
- Les réserves/cimetières sont visuels.
- Le timer est statique.
- Réseau/auth/social/ELO ne sont pas encore branchés à Godot.

## Source de vérité conservée
- `data/cards.json` : 70 cartes.
- `legacy_reference/game_engine.py` : règles historiques.
- `legacy_reference/cards.py` : définitions historiques.

## Étape suivante recommandée
Valider la DA et la sensation de mouvement. Ensuite créer un modèle de combat
Godot testable avec PV réels, sélection de cible et A1/A2, puis comparer ses
résultats à l'ancien moteur Python avant migration complète.
