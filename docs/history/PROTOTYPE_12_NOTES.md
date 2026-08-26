# YUGITO 2.0 — GODOT PROTOTYPE 12 SHIFUMI / DRAFT / IA

## UI / menus
- Textes des cartes de modes remplacés par des zones RichText bornées : plus de débordement horizontal hors des cadres.
- Fiche Collection réorganisée : illustration plus compacte, blocs PASSIF et SPÉCIALE séparés et bornés.
- Cartes de modes plus premium : numéro, statut, bloc description, bouton dédié.

## Flux Solo Classic porté depuis YUGITO PC
1. Shifumi n°1 : détermine le premier joueur du draft.
2. Draft de 16 choix / 8 Ninjas chacun.
3. Séquence exacte PC : W, L, L, W, W, L, L, W, W, L, L, W, W, L, L, W.
4. Déblocage progressif : 3★, 3.5★, 4★, 4.5★, puis 5★ ; un palier débloqué reste disponible.
5. Limites : 32,5★ ; 3★ illimité ; 3,5★×4 ; 4★×3 ; 4,5★×2 ; 5★×1.
6. Les cartes choisies sortent du pool commun.
7. Choix privé des 3 Ninjas de départ.
8. Shifumi n°2 : détermine qui joue le premier tour.
9. Le deck et les starters sont transmis au combat via GameSession.

## IA
- IA de draft : reprend le score PC (PV + meilleure stat + somme des stats) et ajoute diversité de rôles/éléments et valeur tactique.
- IA combat : A1 + A2 réactive, switch de survie, spéciales, remplacement et Hiraishin gratuit de Minato.
- Scoring amélioré : dégâts Classic réels, priorité K.O., surplus potentiel, menace de la cible, avantage élémentaire et utilité des contrôles.
- A2 IA part à la prochaine validation du joueur, avant son A1 ; A2 joueur part à la validation IA, avant son A1.

## Limites encore en migration
- Tous les 70 passifs/spéciales ne sont pas encore portés intégralement en GDScript.
- Les pauses exactes du moteur PC lors d'un K.O. au milieu d'une chaîne A2/A1 nécessitent encore un ordonnanceur d'actions entièrement séquentiel.
- Réseau/auth/ELO/multijoueur restent à reconnecter.
