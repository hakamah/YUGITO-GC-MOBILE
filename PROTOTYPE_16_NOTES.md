# YUGITO 2.0 — Prototype 16 — PARITY HARNESS + A2 TORTURE + INO

## But

Deuxième passe de Projet YUGITO 09 : rendre la parité PC ↔ Godot mesurable avant de poursuivre les 70 cartes.

## P16 livré

- Harness PC portable avec RNG LCG identique au RNG QA Godot.
- Fixture JSON déterministe avec checkpoints complets terrain/réserve/cimetière/actions retardées.
- Scénario `a2_torture` : Switch A2 réactif, suivi de slot uniquement dans ce cas, Counter-Switch Sasuke, K.O., offre de remplacement et reprise.
- Scénario `ino_live_body` : Transfert réussi, vrai corps contrôlé conservant PV/bouclier/poison/buffs/STUN, puis restitution du même état.
- Ino Godot n'utilise plus une copie figée de stats : lien réciproque par `battle_uid` vers le vrai `CardActor` contrôlé.
- Ino adopte dynamiquement statistiques et élément du corps, mais jamais sa spéciale.
- Ino et le corps possédé sont inciblables ; le propriétaire du corps ne peut pas l'utiliser.
- Les états du corps continuent d'exister sur l'instance réelle et ne sont pas effacés à la restitution.
- La durée du Transfert est gérée atomiquement à la fin des tours d'Ino, sans consommer le tour d'activation.
- Cooldown Ino aligné sur Classic : T 1/3 après usage, puis retour disponible au 3e tour suivant.
- Smoke Godot `P16BattleSmoke.gd` ajouté pour vérifier A2/counter et Ino sans interface de combat.

## Validation disponible

```text
python tools/parity/parity_harness.py
python tools/parity/check_p16.py
godot --headless --path . --script res://tools/parity/P16BattleSmoke.gd
```

Le runtime Godot 4.7.x n'est pas disponible dans l'environnement ayant produit ce ZIP : les deux commandes Python sont exécutées ici ; le smoke Godot est livré prêt à être lancé mais doit être validé sur une machine avec Godot.

## Suite recommandée P17

Étendre le même format de fixture aux cartes moteur les plus risquées : Gengetsu, Tobi/Zetsu, Shikamaru, Kakashi, Mifune/Sasuke, Hidan et les chaînes de survie Kabuto/Chiyo/Kurotsuchi.
