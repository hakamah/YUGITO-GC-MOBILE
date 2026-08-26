YUGITO 2.0 — GODOT PROTOTYPE 14 CLASSIC PARITY

OBJECTIF
- Recentrage total sur la parité du client PC Tkinter YUGITO(4).
- Accueil refait dans l'esprit du menu Classic fourni par l'utilisateur : grande illustration à gauche, panneau vertical à droite.
- Plus d'expansion de menus secondaires pour cette passe.

A1 / A2
- Descripteurs stables par UID/slot : aucune référence Node conservée dans les actions différées.
- Ordre de validation PC : A2 adverse -> Hiraishin gratuit -> A1.
- Switch A2 réellement réactif avant les attaques ; Counter-Switch / Yamato conservés.
- Une cible ne suit son slot qu'après une vraie entrée A2 réactive pendant cette résolution.
- File de résolution séquentielle suspendue par les remplacements K.O.

PASSIFS / SPECIALES / ETATS
- Couverture de branche/config spéciale : 70/70 IDs de cartes.
- Environ 57 types de badges/bandeaux d'état déclarés sur les cartes.
- Ajouts de cette passe : Ao anticipation + Byakugan dérobé, Orochimaru vol de cimetière, Tobi bombes/prédiction, Makibishi sur entrées, Kushina/Shizune/Chiyo/Karui à la mort, Gai seuils de portes, Temari +100 NIN sans avantage, Omoi 1/3 oubli / +20 %, A3 Raikage contrecoup, Sasori poison Taijutsu, Jûgo pile ou face sexe, Mifune +500/+750, Tsunade Byakugô, Zetsu régénération + punition Switch A1, Chôjûrô +/-200, traqueurs Ao/Neji/Hinata.
- Tobi : bombe obligatoire au début de son tour, max 5 par cible, 320 fixes par bombe au Switch, prédiction exacte attaquant+cible, disparition des bombes si Tobi meurt.

VALIDATIONS STATIQUES
- 70 cartes uniques dans data/cards.json.
- 70 illustrations terrain présentes.
- Aucun res:// statique manquant.
- Délimiteurs/chaînes équilibrés sur tous les scripts GDScript.
- Aucune fonction privée appelée mais absente dans les scripts principaux.
- Aucun descripteur A1/A2 ne stocke directement un objet Node source/target.

LIMITES
- Godot 4.7.2 n'est pas installé dans l'environnement de build : validation runtime finale à effectuer sur Windows/Godot.
- Certaines interactions ultra-spécifiques peuvent encore nécessiter une passe de parité après test réel.
