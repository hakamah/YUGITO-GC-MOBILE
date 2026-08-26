# DEV — Audit « 7 différences » Classic/Tkinter ↔ Godot — P20

Cette matrice accompagne la passe P20. Elle ne remplace pas les fixtures moteur : elle
force la revue de ce que le joueur VOIT et de ce que le moteur FAIT pour les cartes déjà
passées dans les verrous P15→P19.

| Carte / système | Cible / action | États / durée | Image / identité | Animation / impact | Persistance / K.O. | Gate |
|---|---|---|---|---|---|---|
| Choji | interception avant lancement | défense permanente | carte normale | trait + impact vers Choji | cible effective unique | P17/P20 |
| Shikamaru | cible choisie = libre | Ombres 3T, rupture HP réel | identité normale | liens vers cibles prises | nettoyage source mort/switch | P17/P20 |
| Gengetsu | clone 0 arts | clone 2T / retour | artwork + nom clone | bandeau explosion | état original restauré | P17/P18/P20 |
| Ino | contrôle du vrai corps | inciblable / durée étoiles | adopte cible en direct | lien TRANSFERT | état du corps intact | P16/P20 |
| Tobi | bombe/prédiction | intangible + bombes ×1..×5 | identité normale | marqueurs bombes visibles | explosion avant switch / cleanup mort | P17/P18 |
| Zetsu | interception/reveal switch | caché / STUN entrée A1 | identité normale | état visible | règles A1/A2 verrouillées | P17 |
| Kakashi | Raikiri + COPIE séparée | counter-switch | identité normale | impact cible effective | copie persistante | P17 |
| Sasuke | Chidori absolu | Sharingan/counter-switch | identité normale | bypass cohérent | matrices survies | P18/P19 |
| Mifune | Trancheur | défenses exactes PC | identité normale | cible réelle | boucliers/survies | P17/P18/P19 |
| Killer Bee | actions non perdues | immunité STUN, pas Scellé | identité normale | standard | contrôles verrouillés | P18 |
| Madara | contrôles incapacitants ignorés | immunités | identité normale | standard | contrôles verrouillés | P18 |
| Temari | cible soufflée | états restent attachés | même instance | AOE centrée correctement | réserve/tracker/bombes | P18/P19 |
| Kisame | prison liée à source | prison aqueuse visible | identité normale | lien PRISON | cleanup source | P17/P19 |
| Hidan | Jashin lié à source | compteur Jashin | identité normale | lien JASHIN | cleanup source | P17/P19 |
| Chiyo | sauvetage létal | usage unique visible | identité normale | standard | ordre survies | P17/P19 |
| Kabuto | sauvetage / Scalpel | usage visible | identité normale | bypass sans détruire shield | ordre survies | P17/P19 |
| Kurenai | protection spéciale ciblée | shield caché / protection | identité normale | cadre shield | ordre shield visible/caché | P17/P19 |
| Tsunade | passif début tour | soin +200 <50% | identité normale | feedback heal backend | ordre début tour | P18 |
| Haku | garde d'entrée | prison glace / garde | identité normale | bandes dédiées | entrée réserve | P15/P20 UI |
| Gai | seuils 75/50/25 | PORTES ×N | artwork stages | chip visible | stats persistantes | P15/P20 UI |
| Jûgo | stades | STADE N | artwork stages | chip visible | PV max/stats persistants | P15/P20 UI |
| Jiraiya | mode ermite | MODE ERMITE | artwork sage | chip visible | permanent | P20 UI |
| Naruto | seuil <50% | bonus actif | artwork passif | identité dynamique | recalcul live | P20 UI |
| Konohamaru | Sexy Jutsu / contre | Sexy Jutsu | artwork sexy | contre = dégâts fixes normaux | pipeline central | P17/P20 UI |
| Rin | Isobu <25% | ISOBU ÉVEILLÉ | aucun asset alternatif fourni | chip très visible | PV max/stats persistants | P15/P20 UI |
| Kakuzu | résurrections | cœurs ♥ ×N | identité normale | standard | matrice survies | P19/P20 UI |
| Mû | division | JINTON OFF | identité normale | standard | persistance | P15/P20 UI |
| Chôjûrô | stock | Hiramekarei +N | identité normale | spécial interceptable | stock persistant | P17/P20 UI |

## Règles globales P20
- Une animation d'attaque utilise la **même cible effective** que le moteur de dégâts.
- Les états majeurs ne dépendent plus d'un petit badge : voile d'art, grosse bannière,
  cadre ou chip permanent selon le type.
- Les liens source→cible (Ino/Shikamaru/Kisame/Hidan) sont visibles tant qu'ils existent.
- Les transformations changent l'artwork en temps réel si l'asset est présent.
- Collection / Deck / Draft / starters utilisent le même ratio externe 252×396 que la
  carte de combat Godot.
