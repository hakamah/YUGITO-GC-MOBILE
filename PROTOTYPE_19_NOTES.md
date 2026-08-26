# YUGITO 2.0 Godot — Prototype 19 KO / SURVIVAL / QUEUE LOCK

## But
Poursuivre la feuille de route YUGITO 09 sur les interactions létales qui peuvent casser
l'ordonnanceur : Chidori/Mifune contre toutes les survivances, boucliers empilés,
Temari avec états persistants/tracker, K.O. multiples, réserve vide et surplus joueur.

## Corrections moteur P19
- Remplacements après plusieurs K.O. sérialisés dans une file FIFO d'UID stables.
  Une AOE qui tue 2 ou 3 Ninjas ne peut plus ouvrir plusieurs fenêtres concurrentes.
- La résolution A2/A1 reste suspendue jusqu'à consommation de toute la file de K.O.
- Nettoyage Jashin / Prison aqueuse / Transfert / Ombres déclenché dès la mort définitive,
  même si la réserve est vide et qu'aucun `_replace_actor()` ne sera exécuté.
- Temari conserve l'instance complète soufflée en réserve, fait exploser les bombes Tobi
  avant la sortie et respecte un tracker Ao/Neji/Hinata pour l'offre de remplacement.
- Matrice Chidori : les survies personnelles, Doton, Chiyo et Kabuto sont traversés ;
  le clone de Gengetsu reste l'exception qui restaure la vraie carte.
- Matrice Mifune : Ônoki est traversé, mais Danzo/Orochimaru/Hidan/Kakuzu/Kankuro/Mû,
  Doton, Chiyo et Kabuto restent des survies légales ; l'inciblabilité reste une limite.
- Boucliers Kurenai : dégâts fixes = visible puis caché ; Mifune additionne les deux,
  convertit exactement 50 % du stock en dégâts puis détruit les deux boucliers.
- Surplus joueur : Danzo/Hidan/Kankuro/Kakuzu/Chiyo/Kabuto conservent le surplus d'une
  vraie attaque ; Ônoki et Doton annulent l'impact avant calcul du surplus.
- K.O. sans réserve : l'emplacement reste vide, aucune modale fantôme ; un wipe total
  sans terrain ni réserve déclenche immédiatement la défaite.

## Harness P19
`tools/parity/parity_harness_p19.py` rejoue 9 scénarios PC déterministes :
1. chidori_survival_gauntlet
2. mifune_survival_gauntlet
3. shield_stack_order
4. temari_links_and_tracker
5. source_death_cleanup_without_reserve
6. three_ko_replacement_queue
7. dot_death_passives
8. overflow_with_survival
9. ko_empty_reserve

Fixture : `tools/parity/fixtures/pc_expected_p19.json`.
Master gate : `python tools/parity/check_p19.py` ; il réexécute également P15/P16/P17/P18.

## Smoke Godot
`tools/parity/P19KOSmoke.gd` couvre en logique headless :
- nettoyage Jashin / Prison aqueuse ;
- Chidori vs Izanagi ;
- Mifune vs Izanagi ;
- boucliers empilés Kurenai ;
- surplus avec Danzo vs annulation Ônoki.

## Note roadmap « K.O. causé par un passif de mort »
Dans le moteur PC de référence actuel, les passifs de mort présents ne causent pas de dégâts
directs : Kushina scelle, Shizune affaiblit et Chiyo soigne. Aucun scénario létal artificiel
n'a donc été inventé. Les effets de mort réellement implémentés restent couverts par le harness.

## Limite de validation
L'environnement actuel ne contient toujours pas l'exécutable Godot 4.7.2. Les fixtures PC,
les gates P15→P19, la compilation Python et le contrôle structurel des GDScript sont exécutés.
Le smoke Godot P19 est livré mais n'est pas déclaré exécuté ici.
