# YUGITO 2.0 Godot — Prototype 23 COMBAT TIMER / TIMEOUT LOCK

## But
Fermer les points 96–97 de la feuille de route combat : vrai chrono de 30 secondes pendant la phase de décision du joueur et résolution automatique au timeout, sans régression du plan Classic verrouillé en P22.

## P23
- Le faux `30 s` statique du HUD est remplacé par un vrai compteur temps réel.
- Chaque nouveau tour humain repart à exactement 30 s.
- Le chrono est suspendu pendant résolution, tour IA et fenêtre de remplacement.
- Comme le PC, le chrono apparaît au centre puis glisse vers sa position haute en 0,58 s avec easing cubic-out.
- Une validation manuelle coupe immédiatement le chrono.
- À 0 s, le comportement suit `app_PC_latest.py::_phase_timer_expired()` : fin/validation du tour automatique.
- Si Hiraishin/A1/A2 sont déjà préparés, ils sont conservés et résolus normalement.
- Si aucun plan n'est préparé, le timeout est autorisé à valider un tour vide, contrairement au bouton manuel.
- Une A2 adverse en attente reste consommée/résolue avant le passage de tour, même lors d'un timeout.

## Validation
- Gate P23 rejoue les invariants P15→P21 et les verrous P22 encore pertinents.
- Smoke Godot `P23CombatTimerSmoke.gd` livré.
- L'environnement de travail ne contient pas l'exécutable Godot ; le smoke est donc fourni mais non exécuté ici.
