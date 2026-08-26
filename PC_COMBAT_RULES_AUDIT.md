# Audit du combat PC — YUGITO(4) → migration Godot Prototype 10

## Sources auditées

- `legacy_reference/game_engine_PC_1.8.21.py` : moteur de duel fourni dans YUGITO(4).
- `legacy_reference/app_PC_latest.py` : flux UI/écrans du client PC fourni.
- `legacy_reference/core_set_PC_1.8.21.json` : 70 cartes, stats, passifs et spéciales.
- Le paquet fourni contient un `VERSION` racine 1.8.21 et un shell `app/VERSION` 1.9.0 GPU ; cet audit traite le contenu fourni comme source de vérité fonctionnelle.

## Règles structurelles confirmées

- Chaque joueur possède **4000 PV joueur** indépendants des PV de ses Ninjas.
- Un deck contient **8 Ninjas uniques** : 3 sur le terrain, 5 en réserve cachée. Le moteur maintient jusqu’à 3 Ninjas sur le terrain tant qu’il en reste assez.
- Le plan contient **Action 1 immédiate** et **Action 2 réactive**. A2 se déclenche à la **prochaine validation adverse**, avant Hiraishin et l’Action 1 adverse. Elle est consommée même si elle est devenue illégale.
- Un switch est une vraie action planifiée A1/A2. Un switch A2 est réactif et peut changer la cible physique d’une attaque déjà préparée sur le slot.
- Les cartes sortant volontairement en réserve conservent leur **instance** : PV, boucliers, cooldowns, buffs/debuffs et états personnels persistants.
- Après K.O., le moteur tire **jusqu’à 3 cartes aléatoires** de la réserve. Le joueur choisit exactement une. Les non choisies restent en réserve. Le remplaçant prend le **même slot**.
- L’écran PC de remplacement est une **phase plein écran dédiée** (`current_screen = "replacement"`), pas un simple texte superposé au duel.
- Les phases interactives importantes utilisent un timer de 30 s ; le remplacement peut être auto-résolu au timeout.
- Une attaque directe n’est autorisée que si le terrain adverse est vide. Dégâts = `max(100, stat_offensive / 2)` sur les PV joueur.
- Une attaque normale compare le même art : `attaque - défense`. Si la différence est positive : minimum 100. L’avantage élémentaire applique ×1,10 puis +150.
- Si une attaque valide tomberait à 0, le moteur applique le plancher anti-zéro : 100 + un pourcentage des PV max de la cible selon les étoiles de l’attaquant (bonus plafonné à 100).
- Le **surplus d’une vraie attaque** traverse un Ninja K.O. et frappe les PV joueur. Les dégâts fixes/passifs/poisons n’ont pas de surplus joueur.
- Ordre défensif important : interceptions/gardes, immunités/esquives, réductions, boucliers, survies, PV, surplus, K.O./remplacement.
- Minato dispose d’une vraie case **Hiraishin gratuite** séparée de A1/A2.
- Contre-switch : Itachi/Sasuke/Kakashi peuvent annuler la première attaque reçue après une entrée réactive ; Yamato peut transmettre ce counter au remplaçant.
- Choji intercepte automatiquement les attaques destinées aux autres alliés. Kankuro réduit de 250 les dégâts subis par ses autres alliés lorsque sa Défense marionnettiste est active.
- Shikamaru libère immédiatement toutes ses ombres s’il subit le moindre dégât de PV.
- Ino conserve les états du vrai corps contrôlé ; son Transfert a 50 % de réussite, une durée dépendant des étoiles, et 3 tours de recharge.
- Le moteur possède beaucoup d’autres subtilités contextuelles : trackers Byakugan, Makibishi, liens Jashin/prison, poisons, survies multiples, copies de Kakashi, transformations, inciblabilités, buffs familiaux, etc. Le fichier Python PC est gardé dans le projet pour le portage exact.

## Ce qui est désormais synchronisé dans le Prototype 10

- 70 définitions de cartes et **70 illustrations terrain** copiées depuis la build PC.
- PV joueur 4000/4000 séparés des PV cartes.
- Formule de dégâts normale Classic, avantage élémentaire et plancher anti-zéro.
- Attaque directe, surplus d’attaque, boucliers, K.O., cimetière.
- Remplacement humain dans un **vrai CanvasLayer modal plein écran**, avec 3 propositions aléatoires maximum et blocage du duel derrière.
- Switch tactique planifié, conservation/restauration de l’état de réserve, retour au même slot.
- Première couche de counter-switch Sasuke/Kakashi/Itachi + relais Yamato.
- Première couche de Choji, Kankuro, Gaara, Kurenai, Sakura, Sai, Naruto, Shikamaru, Ino, Yamato, Jiraiya, Asuma et quelques spéciales offensives.
- Sons historiques disponibles lorsqu’un asset correspondant existe.

## Parité encore à porter exactement

- Ordonnanceur complet **Joueur ↔ IA** afin que A2 parte réellement à la validation adverse (le Prototype 10 garde encore un cycle de validation simplifié).
- Case Hiraishin gratuite de Minato dans le HUD Godot.
- Les 70 passifs/spéciales, synergies de familles, copies, trackers, poisons, transformations et effets de terrain au niveau exact du moteur Python.
- IA complète, timers par phase, draft/lineup, deck builder, menus, profils, réseau, auth Google, ELO/social/multijoueur.
- Migration des FX/sons dédiés restants et des écrans secondaires.
