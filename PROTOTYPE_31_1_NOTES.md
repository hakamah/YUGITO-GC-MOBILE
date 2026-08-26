# YUGITO 2.0 — Prototype 31.1 SHIKAMARU MOBILE LOCK

Hotfix ciblé après test Godot mobile.

- Possession des ombres conserve strictement la règle PC : la carte ciblée reste libre, les autres cibles valides reçoivent 3 tours d'Ombres.
- A1 et A2 utilisent le même helper `_apply_shikamaru_shadows`.
- En A2, le journal identifie explicitement `A2 RÉACTION`.
- Le bandeau `OMBRE DES NARA • xT` est forcé à se reconstruire après application.
- Deuxième resynchronisation 80 ms plus tard pour les appareils mobiles où la fin d'animation A2 tombe entre deux frames UI.
- Les liens visuels Shikamaru -> cibles sont reconstruits avec le même resync.
- Les Ombres continuent d'empêcher l'action et le Switch volontaire.
- Killer Bee et Madara conservent leurs immunités prévues.
- Tout vrai dégât HP reçu par Shikamaru brise ses liens comme avant.

Aucune modification d'équilibrage.
