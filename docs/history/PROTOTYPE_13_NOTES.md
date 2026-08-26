# YUGITO 2.0 — GODOT PROTOTYPE 13 — CARTES / SYNERGIES / STABILITÉ

## UX
- Son de clic/sélection dans les menus, Shifumi, Draft, sélection des starters et remplacement.
- Draft et starters affichés sous forme de vraies cartes YUGITO (nom/PV, illustration, rareté, élément, TAI/NIN/GEN, passif, spéciale).
- Cliquer une carte ouvre une fiche complète avec description du passif, de la spéciale et des synergies.
- Sélection renforcée (bordure or + badge ✓ CHOISI).
- Accueil remanié : suppression du panneau « bases déjà migrées », raccourcis utiles et Ninja à la une.

## STABILITÉ
- Correction du crash `Trying to cast a freed object` : les actions A1/A2/timers utilisent désormais battle_uid + slots stables, jamais une référence Node libérable.
- Une cible remplacée peut être résolue par son slot ; une source morte/retirée fait perdre proprement l'action.

## SYNERGIES
- Familles et duos repris du moteur PC YUGITO(4).
- 3 membres d'une même famille : +20 % ALL STATS.
- 2 membres d'une famille : +12,5 %.
- Duo explicite : +15 %.
- Zetsu + Akatsuki : +15 %.
- Non cumulatif : le meilleur bonus seulement.
- Bonus appliqué réellement sur le terrain et retiré en réserve en conservant le pourcentage de PV.

## COMBAT
- Table des spéciales d'attaque standard élargie à partir du moteur PC (Hashirama, Madara, Nagato, Obito, Itachi, Killer Bee, Gai, Minato, Naruto, Sasuke, A, Hiruzen, Kakashi, Kabuto, Tsunade, Deidara, Neji, Sakura, Sasori, Hinata, Kiba, Shino, Suigetsu, Zabuza, Kakuzu, Mifune).
- Plusieurs effets post-spéciale synchronisés : soins/boucliers, blocages, Katon d'Itachi, poison Shino, dégâts retardés Sasori, etc.
- Réductions défensives ajoutées : Nagato, A 4e, Suigetsu, Kimimaro.
- Survies ajoutées : Ônoki, Danzo, Orochimaru, Hidan, Kakuzu, Mû.

Le moteur PC reste embarqué dans legacy_reference comme source de vérité pour les cartes encore en cours de portage exact.
