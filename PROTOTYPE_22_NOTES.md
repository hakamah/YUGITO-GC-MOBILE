# YUGITO 2.0 Godot — Prototype 22 CLASSIC TURN PLAN LOCK

## But
Verrouiller le plan de tour Godot sur le comportement du client PC Classic avant de poursuivre les couches restantes.

## Corrections P22
- Trois emplacements de plan réellement distincts : **Minato gratuit / Action 1 / Action 2**.
- Cliquer la case Hiraishin sélectionne automatiquement Minato, comme le PC.
- Hiraishin reste strictement une attaque normale et ne consomme ni A1 ni A2.
- Annulation indépendante de Hiraishin, A1 et A2.
- Si A1 est un Switch et que A2 dépend de l'entrant virtuel, annuler A1 nettoie aussi cette A2 incohérente.
- L'attaque directe n'est plus préparée implicitement en choisissant TAI/NIN/GEN.
- Bouton **ATTAQUE DIRECTE** explicite, activable uniquement avec un art normal sélectionné et les 3 slots adverses vides.
- Dégâts directs inchangés : `max(100, stat / 2)`.
- La ressource **COPIE** de Kakashi conserve sa ligne propre et ne partage plus l'emplacement Hiraishin.
- Ordre de validation conservé : **A2 adverse -> Hiraishin gratuit -> A1** ; A2 du joueur est armée pour la prochaine validation adverse.

## Validation
- Le gate P22 rejoue les invariants fonctionnels pertinents P15→P21 sans leurs anciens tests de métadonnées.
- Fixture P21 A2/Shikamaru/Tobi rejouée bit-à-bit.
- Contrôles statiques P22 sur les trois slots, annulations, attaque directe et copie Kakashi.
- `python -m py_compile` sur tous les outils de parité et la référence PC.
- Smoke Godot P22 livré pour une machine disposant de Godot 4.7.2.

## Limite de l'environnement
L'exécutable Godot n'est pas installé dans l'environnement de génération actuel : le smoke `P22TurnPlanSmoke.gd` est livré mais non exécuté ici.
