# YUGITO 2.0 — Prototype 02.1 TYPEFIX

Hotfix Godot 4.7.2 pour le mode de warnings strict.

Corrections principales :
- `CardActor.gd:317` : remplacement de `var x := clamp(...)` par un `float` explicite + `clampf()`.
- Hover : `clamp()` générique remplacé par `clampf()`.
- Tableaux d’actions, couleurs, IDs et coordonnées explicitement typés.
- Lecture JSON explicitement typée `Variant` puis conversion `Dictionary` avant `CardActor.setup`.
- Aucun changement graphique/gameplay volontaire par rapport au Prototype 02.
