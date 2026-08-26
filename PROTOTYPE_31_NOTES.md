# YUGITO 2.0 Godot — Prototype 31 CHARACTER AUDIT I

## Portée
Audit profond feuille de route 197→206 contre `legacy_reference/game_engine.py` (snapshot PC Classic 1.8.21).

Personnages audités : Hashirama, Madara, Nagato, Obito, Itachi, Jiraiya, Killer Bee, Maito Gai, Minato, Naruto.

## Correction réelle P31
- **Maito Gai / Hirudora** : le recul non létal de 150 PV réévalue désormais immédiatement les seuils 75/50/25 %. Si Hirudora fait franchir un seuil, la porte correspondante s'ouvre tout de suite et ajoute +250 Taijutsu, comme le moteur PC.

## Règles confirmées sans modification
- Hashirama : AOE fixe -100 au début de son tour + soin 200 après Dragon de bois si dégâts.
- Madara : immunité spéciales Genjutsu, immunité contrôles incapacitants, Susanoo +500 puis bouclier 300.
- Nagato : -200 dégâts NIN/GEN et blocage Taijutsu après Shinra Tensei.
- Obito : commence intangible, alternance sur tours adverses, Kamui supprime les boucliers avant frappe.
- Itachi : Tsukuyomi après vrais dégâts HP, immunités Bee/Madara, Counter-Switch, Katon 350 fixes aux autres cibles.
- Jiraiya : +10 aux trois arts par tour complet de terrain et Mode ermite permanent.
- Killer Bee : ne perd pas son tour (hors Scellement Uzumaki), spéciale non bloquée, bouclier si Bijûdama inflige au moins 400 PV.
- Minato : Hiraishin gratuit, toutes ses attaques ignorent les passifs défensifs, Rasengan +300, bouclier après K.O.
- Naruto : +350 TAI/NIN sous 50 %, illustration dynamique, Rasengan -100 NIN pour la durée PC.

## Validation
`python tools/parity/check_p31.py` : 30/30.
`python -m py_compile tools/parity/*.py legacy_reference/*.py` : OK.
`python tools/parity/check_gd_structure.py` : 21 fichiers GDScript OK.

Godot 4.7.2 n'est pas disponible dans l'environnement : pas de smoke runtime headless exécuté ici.
