# Audit YUGITO PC — Solo / Shifumi / Draft / IA

Source auditée : YUGITO(4).zip, `app/src/app.py` et `app/src/game_engine.py`.

## Ordre officiel d'une partie
`Shifumi draft -> Draft -> choix des 3 starters -> Shifumi départ -> Duel`.

## Shifumi
- Pierre bat Ciseaux ; Feuille bat Pierre ; Ciseaux bat Feuille.
- En Solo, l'IA choisit aléatoirement.
- Une égalité relance le Shifumi.
- Le premier Shifumi donne le premier choix de draft.
- Le second choisit le joueur qui commence le duel.

## Draft
- 8 cartes par joueur, 16 picks.
- Séquence relative : first, second, second, first, first, second, second, first, first, second, second, first, first, second, second, first.
- Calendrier de déblocage : 3, 3, 3.5, 3.5, 4, 4, 4.5, 4.5, 5, 5, 4.5, 4.5, 4, 4, 4, 4.
- Le plafond réel est cumulatif : un palier déjà débloqué ne se referme jamais.
- 32,5★ max et quotas par rareté.
- Les picks sont exclus du pool partagé.

## IA PC originale
### Draft
Score principal : `PV*0.35 + meilleure_stat + somme_stats*0.20 + aléatoire`.

### Starters
Trie par étoiles puis par `PV*0.35 + meilleure_stat + somme_stats*0.20`, décroissant.

### Combat
- Hiraishin gratuit de Minato si présent.
- Peut switcher une carte <=30% PV, avec une probabilité d'environ 55%.
- Tente une spéciale modérément selon son utilité.
- Sinon choisit l'attaque qui produit le plus de dégâts calculés.
- Prépare une Action 2 pour la prochaine validation adverse.
- Choisit le meilleur remplaçant parmi l'offre de 3 cartes.

## Améliorations Godot P12
- Le draft garde les règles PC mais l'IA favorise aussi les rôles absents et la diversité élémentaire.
- Le combat ajoute des bonus de score pour K.O., menace, surplus et contrôle.
- Les switches sont plus déterministes quand une carte est réellement en danger.
