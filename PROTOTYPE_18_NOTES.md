# YUGITO 2.0 Godot — Prototype 18 DEFENSE / CONTROL / RESERVE LOCK

## But
Poursuivre la feuille de route YUGITO 09 en ciblant les cas capables de changer
le résultat d'un duel : Chidori/Mifune contre les défenses, immunités de contrôle,
poisons simultanés, retour en réserve de Temari et ordre exact des effets de début de tour.

## Corrections P18
- Chidori : détruit le bouclier visible mais ne détruit pas le bouclier caché Kurenai ;
  il continue de l'ignorer via son impact absolu.
- Chidori : traverse l'esquive létale d'Ônoki et les protections/survies prévues par le PC.
- Mifune : liste des profils défensifs synchronisée sur le moteur PC ; Trancheur ignore
  notamment l'esquive d'Ônoki mais conserve les limites inciblabilité/survie déjà verrouillées.
- Killer Bee : ignore les STUN/pertes de tour comme le PC, mais le Scellement de Kushina le bloque.
- Madara : ignore les contrôles incapacitants, y compris Scellement et prison Sai.
- Sai : sa Prison ne s'applique plus à Killer Bee ni Madara.
- Temari : la carte soufflée rejoint réellement la réserve avec son état complet ; si d'autres
  réservistes existaient, elle n'est pas reproposée immédiatement pour son propre slot.
- Début de tour : ordre restructuré par familles d'effets pour suivre Classic :
  Torune/retardé -> Anko -> Shino -> Hanzo poison -> brume Hanzo -> Haku -> Shizune ->
  Kimimaro -> cooldowns -> clone Gengetsu -> Tsunade/Kisame/Karin -> Hashirama -> Tobi.
- Gengetsu : un poison peut maintenant détruire le clone AVANT son explosion ; la recharge
  n'a plus de tour fantôme selon que le retour survient avant ou après la phase cooldown.
- Tsunade : soin passif +200 au début de son tour sous 50 % restauré.
- Tobi : son toggle/bombe intervient après les effets du start_turn PC ; un Tobi tué par DOT
  avant cette phase ne place donc pas de bombe.

## Harness P18
`tools/parity/parity_harness_p18.py` rejoue 8 scénarios PC déterministes :
1. chidori_absolute_matrix
2. mifune_defense_matrix
3. control_immunity_bee_madara
4. poison_stack_pipeline
5. temari_reserve_state
6. start_turn_order_gengetsu
7. tsunade_start_heal
8. tobi_after_start_effects

La fixture est `tools/parity/fixtures/pc_expected_p18.json`.
Le master gate est `python tools/parity/check_p18.py` et réexécute les invariants P15/P16/P17.

## Limite
L'environnement actuel ne contient pas l'exécutable Godot 4.7.2. Les contrôles Python/PC,
les fixtures déterministes et le contrôle structurel GDScript sont exécutés ; les smokes
Godot headless restent livrés pour exécution sur une machine disposant de Godot.
