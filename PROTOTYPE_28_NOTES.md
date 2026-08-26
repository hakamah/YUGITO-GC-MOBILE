# YUGITO 09 — PROTOTYPE 28 TRANSFORMATION LOCK

Roadmap 173→179 verrouillée.

- Naruto : illustration `naruto_passif_field.png` sous 50 %.
- Jiraiya : `jiraiya_sage_field.png` dès Mode ermite.
- Gai : `gai_stade1/2/3_field.png` aux seuils 75/50/25 %.
- Gengetsu : `gengetsu_clone_field.png` pendant le clone.
- Jûgo : `jugo_stade1/2_field.png` aux stades 1/2.
- Rin / Isobu : le pack source ne contient aucun artwork Isobu alternatif ; P28 ne fabrique pas un faux asset. L'éveil change immédiatement l'identité en `Rin • Isobu`, conserve le marqueur dédié et affiche les stats transformées.
- Konohamaru : `konohamaru_sexy_field.png` pendant Sexy Jutsu.

Les transformations sont recalculées dynamiquement par `refresh_dynamic_identity()` et survivent aux exports/imports de l'instance via `status_tags`.
