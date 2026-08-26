# YUGITO 2.0 — GODOT PROTOTYPE 15 — ENGINE LOCKSTEP

Première passe de **Projet YUGITO 09 Godot** suivant la feuille de route de parité Classic.

## Bloc P0 traité

- A2 validée conservée jusqu'à la prochaine validation adverse, même si sa source/cible quitte ensuite le terrain.
- Résolution différée par identité stable de Ninja, puis suivi de case uniquement après un vrai Switch A2 réactif.
- Planification **A1 Switch → A2 avec le Ninja entrant** via acteur logique virtuel, sans créer de Node visuel fantôme.
- Switch A2 déjà programmé utilisé comme **remplacement d'urgence** si son Ninja sortant tombe K.O. avant le déclenchement normal.
- Persistance terrain ↔ réserve passée en schéma explicite v2 : PV, PV max imprimés/instance, arts, élément, boucliers, cooldowns, STUN, passifs consommés, tags, buffs et modificateurs temporaires.
- Correction du calcul de synergie : le pourcentage de PV porte uniquement sur les PV imprimés, pas sur les +PV Rin/Jûgo/Karui ; le clone Gengetsu reste à 4800 PV.
- Haku arme Miroirs de glace à chaque vraie entrée depuis la réserve, mais ne teste la parade que sur la première attaque A2 programmée.
- Mifune respecte de nouveau l'inciblabilité ; Trancheur continue d'ignorer les réductions et de convertir/détruire les boucliers.
- Fallback anti-zéro déplacé après les réductions défensives et avant Kimimaro/boucliers, comme le moteur PC.
- RNG combat centralisé avec mode QA déterministe optionnel (`GameSession.enable_parity_rng(seed)`).

## Banc de parité ajouté

- `tools/parity/check_p15.py` : gate Python contre le snapshot Classic embarqué + invariants statiques Godot.
- `tools/parity/ParitySmoke.gd` : smoke headless Godot pour RNG, sérialisation, synergie Rin et clone Gengetsu.
- `tools/parity/README_FR.txt` : commandes de lancement.

Le mode RNG déterministe est désactivé en jeu normal.

## Validation effectuée dans l'environnement de génération

`python tools/parity/check_p15.py` : **ALL PARITY GATES PASSED**.

Le binaire Godot 4.7.x n'est pas installé dans l'environnement de génération ; le smoke `ParitySmoke.gd` est donc livré mais n'a pas pu être exécuté ici. Il doit être lancé avec Godot headless avant de déclarer P15 runtime-validé.

## Suite de la feuille de route

1. Étendre le runner PC ↔ Godot aux scénarios A2 → Switch → Counter-Switch → K.O. → remplacement → A1.
2. Tester les 70 cartes une par une, avec seed imposée pour les mécaniques RNG.
3. Puis seulement : badges/FX d'états, IA, services réseau/auth/boutique/social.
