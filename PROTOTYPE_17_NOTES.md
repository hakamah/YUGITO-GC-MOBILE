# YUGITO 2.0 Godot — Prototype 17 ENGINE PARITY LOCK

## But
Continuer la feuille de route YUGITO 09 : corriger les divergences capables de
changer le résultat d'un combat avant de reprendre les couches UI/IA/services.

## Moteur corrigé
- Pipeline central unifié pour dégâts fixes/DOT : boucliers et survivances sont
  respectés, pas de surplus joueur ; Makibishi/coûts propres gardent leurs exceptions.
- Inciblabilité : les dégâts fixes/DOT ne sont plus annulés comme des attaques.
- Kurenai : la protection spéciale n'annule que la prochaine spéciale ciblée.
- Gengetsu : explosion 1300 = dégâts fixes normaux ; restauration clone conservée.
- Shikamaru : Ombres séparées du STUN générique, rupture sur vrais dégâts HP.
- Kisame/Hidan : liens persistants attachés à l'UID exact de leur source.
- Sasuke/Itachi/Kakashi : Counter-Switch rapproché du moteur PC.
- Kakashi : COPIE séparée de Raikiri, sans voler les passifs propres du lanceur copié.
- Karin : coût propre 1000 traverse bouclier/Doton mais conserve les secours autorisés.
- Jinton : branche exécution séparée du -1000 fixe normal.
- A 3e / Omoi / Karui / Chôjûrô / Jûgo : interception Choji restaurée.
- Mei : impact principal interceptable mais splashs centrés sur le slot initial.
- Tobi : bombes 320×stack avant Switch, plafond 5, prédiction A1/A2, nettoyage mort.
- Zetsu : révélation Switch A2 et STUN uniquement à l'entrée Switch A1.
- Asuma : détruit bouclier visible + bouclier caché Kurenai avant les 400 fixes.
- Obito : Kamui détruit les deux boucliers de la cible effective après interception Choji.
- Kabuto : Scalpel ignore le bouclier sans le détruire physiquement.
- Konohamaru : Rasengan réflexe 350 repasse par les dégâts fixes normaux.

## Validation
- Les gates P15/P16 restent exécutés par le gate P17.
- 70 données de cartes Godot == PC, bit-à-bit.
- Snapshot game_engine PC 1.8.21 inchangé.
- 15 scénarios PC déterministes P17 rejoués et comparés bit-à-bit à la fixture.
- `python -m py_compile` sur la référence et les outils de parité.
- Contrôle structurel GDScript livré dans `tools/parity/check_gd_structure.py`.

## Limite de cette livraison
L'environnement de build ne contient pas l'exécutable Godot. Les smokes Godot
headless P15/P16 restent fournis mais ne peuvent pas être exécutés ici.
