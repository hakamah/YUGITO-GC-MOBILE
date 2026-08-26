# YUGITO 2.0 — Prototype 21 — A2 / Secret Status Parity

Base : Prototype 20 Classic Visual / Gameplay Parity.
Référence de règles : client Classic/Tkinter `YUGITO(4)(2).zip` + feuille de route Projet YUGITO 09.

## Correctifs ciblés depuis le test réel P20

### Shikamaru — Possession des ombres en A2
- Nouveau scénario PC déterministe `shikamaru_delayed_a2`.
- Une A2 de Shikamaru est consommée à la validation adverse, avant les actions adverses.
- La carte cliquée reste LIBRE ; toutes les autres cibles légales reçoivent 3 tours d'Ombres.
- Killer Bee et Madara restent immunisés.
- A1 et A2 utilisent désormais la même fonction Godot `_apply_shikamaru_shadows`.
- La carte laissée libre n'est plus considérée comme « attaquée » pour la prédiction de Tobi.
- Le journal identifie explicitement `A2 RÉACTION` lors d'une résolution retardée.

### Tobi — informations secrètes
- Les bombes du Tobi ennemi posées sur les cartes du joueur sont toujours présentes dans l'état moteur mais totalement masquées par l'UI locale.
- Les bombes de notre propre Tobi restent visibles sur les cartes adverses.
- Le journal du Tobi ennemi ne révèle plus ni la cible ni le nombre de bombes.
- La prédiction armée du Tobi ennemi est masquée ; seule notre propre prédiction est visible.
- Les refresh visuels sont maintenant déclenchés lors de pose/explosion/armement/nettoyage.

### Bandeaux / états — retour au placement Tkinter
- Suppression de l'empilement vertical dynamique P20 qui pouvait masquer l'image.
- Suppression des doublons « petit badge + gros bandeau » pour STUN, Ombres, Scellé, prisons, inciblabilité, clone, transfert, etc.
- Positions fixes reprises du renderer Tkinter :
  - Sexy Jutsu ≈ 29 %,
  - Scellé ≈ 30 %,
  - Clone Gengetsu ≈ 37 %,
  - contrôle principal / Ombres ≈ 38 %,
  - Jashin près du bas.
- L'inciblabilité utilise un voile/transparence + petit label (KAMUI/BRUME/PALOURDE/INTANGIBLE...) plutôt qu'un gros bandeau empilé.
- Un seul bandeau de contrôle principal est affiché avec priorité Ombres > Glace/Prison > STUN.

## Tests ajoutés
- `tools/parity/parity_harness_p21.py`
- `tools/parity/fixtures/pc_expected_p21.json`
- `tools/parity/check_p21.py`
- `tools/parity/P21A2SecretStatusSmoke.gd`

Le gate P21 rejoue les invariants P15→P19, les fixtures P20 compatibles, puis les nouveaux cas P21.
