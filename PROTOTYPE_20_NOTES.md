# YUGITO 2.0 Godot — Prototype 20 CLASSIC VISUAL / GAMEPLAY PARITY

## But
Faire une vraie passe « jeu des 7 différences » entre le client Classic/Tkinter et Godot
sur les mécaniques déjà portées : la cible logique doit aussi être la cible visuelle, les
états doivent être immédiatement lisibles, les transformations doivent changer l'identité
visuelle de la carte et toutes les vues hors combat doivent conserver la même proportion
extérieure que la carte de combat Godot.

## Choji — interception logique ET visuelle
- La cible effective est maintenant résolue avant le lancement de l'animation.
- Une attaque interceptée trace sa courbe vers Choji, joue l'impact sur Choji et affiche
  un FX « EXPANSION AKIMICHI / CHOJI INTERCEPTE ».
- Les exceptions PC restent respectées : Mifune et Chidori/Sasuke ne sont pas redirigés.
- Les spéciales ciblées réellement interceptables (A 3e, Chôjûrô, Jûgo, Omoi, Karui,
  Mei et les spéciales d'attaque standards) utilisent la même cible effective pour le
  gameplay et l'animation.

## Shikamaru — Possession des ombres
- La carte choisie reste la cible LIBRE.
- Les autres ennemis légaux reçoivent chacun un lien source Shikamaru -> cible pendant 3T.
- Killer Bee et Madara restent immunisés.
- Le lancement ne tire plus un projectile sur la cible libre : des lignes d'ombre partent
  vers les Ninjas réellement immobilisés et la cible épargnée reçoit « CIBLE LIBRE ».
- Les liens persistent visuellement pendant l'état.
- Seuls de vrais dégâts HP reçus par Shikamaru rompent toutes ses ombres ; un impact
  absorbé entièrement par un bouclier ne les casse pas.
- Cooldown spécial : 4 tours.

## Gengetsu — clone réellement identifiable/jouable
- Activation : identité visuelle « Clone de Gengetsu », artwork clone, 4800 PV, 0/0/0,
  compteur 2T et grosse bannière CLONE EXPLOSIF.
- Le panneau d'action reflète aussi l'identité/statistiques du clone.
- Retour : restauration de l'identité, PV/bouclier sauvegardés et cooldown 4.
- Les règles P17/P18 restent verrouillées : mort du clone avant le compte à rebours =
  retour sans AOE ; survie du compte à rebours = retour puis 1300 fixes.

## Ino — identité et corps contrôlé
- L'Ino contrôlante adopte en direct nom/image/élément/stats du vrai corps.
- Le corps possédé reçoit le voile blanc + fantôme Classic et une grosse bannière
  « ESPRIT TRANSFÉRÉ • INCIBLABLE ».
- Un lien persistant TRANSFERT relie visuellement Ino au corps.
- Les états restent portés par la vraie instance contrôlée et sont restitués intacts.

## États / FX
- Inciblable : illustration réellement atténuée + bannière dédiée (Kamui, Brume,
  Palourde, Tobi, Zetsu, Asuma, Konan...).
- STUN / Ombres / Scellé / Enraciné / Prison glace / Prison aqueuse / Prison Sai :
  voile plein artwork + grosse bannière, au lieu d'un simple petit texte.
- Boucliers : cadre lumineux autour de la carte ; bouclier caché Kurenai identifiable.
- Counter-Switch, Défense marionnettiste, cœurs Kakuzu, Jinton OFF, Hiramekarei,
  prédiction Tobi : chips permanents visibles.
- Bombes Tobi : jusqu'à 5 marqueurs individuels sur la cible.
- Jashin / Sexy Jutsu / contrôle Ino : grosses bannières.
- Transformations déjà portées : Naruto, Gai, Jûgo, Jiraiya, Konohamaru et Gengetsu
  changent d'artwork en temps réel lorsqu'un asset existe.
- Rin/Isobu : l'asset alternatif n'existe pas dans le pack actuel ; P20 affiche donc un
  marqueur ISOBU ÉVEILLÉ très visible sans inventer une illustration.
- Attaques : trajectoire courbe avec glow + projectile mobile + impact sur la cible réelle.

## Proportions des cartes hors combat
- La carte de combat Godot reste la référence de ratio externe : 252 x 396.
- Collection, Liste des cartes, Deck, Draft et choix des starters réutilisent ce ratio.
- Les vues scrollables ont été adaptées à la hauteur supplémentaire.

## Harness P20
`tools/parity/parity_harness_p20.py` rejoue 3 scénarios Classic/Tkinter :
1. choji_effective_visual_target
2. shikamaru_three_turn_links
3. gengetsu_clone_play_state

Fixture : `tools/parity/fixtures/pc_expected_p20.json`.
Master gate : `python tools/parity/check_p20.py` ; il réexécute également les invariants
fonctionnels P15 -> P19 avant les contrôles P20.

## Smoke Godot
`tools/parity/P20ClassicVisualSmoke.gd` couvre en logique headless Choji, Shikamaru,
Gengetsu et Ino. Le binaire Godot 4.7.2 n'est pas présent dans l'environnement actuel :
le smoke est livré, mais n'est pas déclaré exécuté ici.
