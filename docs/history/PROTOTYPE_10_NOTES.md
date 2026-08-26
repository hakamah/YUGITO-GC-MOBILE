# YUGITO 2.0 — GODOT PROTOTYPE 10 PC RULES SYNC

Cette build marque le passage du prototype inspiré de YUGITO à une migration guidée par la build PC `YUGITO(4)`.

## Inclus

- 70 cartes et 70 illustrations terrain de la build PC auditée.
- PV joueur 4000/4000 séparés des PV Ninja.
- Formule de dégâts Classic, avantage élémentaire, plancher anti-zéro, surplus vers les PV joueur.
- K.O., cimetière et remplacement.
- Remplacement humain dans une vraie fenêtre modale plein écran Godot (`CanvasLayer`) avec jusqu'à 3 choix aléatoires.
- Switch tactique et conservation d'état de réserve.
- Base A1/A2 conservée et rapprochée du comportement PC.
- Première couche de plusieurs passifs/défenses/counter-switchs.
- Sources PC de référence incluses dans `legacy_reference/` pour poursuivre la parité exacte.

## Encore incomplet

- Ordonnanceur Joueur ↔ IA exact de l'A2 réactive.
- Hiraishin gratuit de Minato dans le HUD.
- Port exact de tous les passifs/spéciales et synergies des 70 cartes.
- IA complète, menus, deck builder, draft/lineup, réseau, auth/social/ELO.

Voir `PC_COMBAT_RULES_AUDIT.md` et `CARD_PARITY_MATRIX.md` pour l'état détaillé de la migration.
