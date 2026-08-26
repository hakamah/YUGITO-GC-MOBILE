# YUGITO 2.0 Godot — Prototype 26 R2 FIELD LOCK / PERSISTENT STATE

## Règle d'autorité corrigée
Une carte envoyée en réserve conserve son instance complète. STUN, poison, bouclier,
buffs/debuffs, cooldowns et autres états temporisés ne sont pas nettoyés et ne tickent
pas hors terrain : ils reprennent à leur valeur restante lors du retour.

## Verrous de terrain
Les cibles affectées par les effets suivants ne peuvent pas effectuer de Switch volontaire,
y compris via un Switch A1/A2 déjà programmé :
- Ombres de Shikamaru ;
- Prison aqueuse de Kisame ;
- Scellement de Kushina ;
- Rituel de Jashin ;
- Enraciné reste également bloquant comme auparavant.

La légalité est contrôlée à l'ouverture du Switch, par l'IA, par l'état du bouton Réserve,
et une seconde fois au moment exact de la résolution A1/A2.

## Exception Temari
Grande Rafale peut expulser une cible même verrouillée. Cette sortie forcée conserve
l'état complet et les liens reçus dans l'instance de réserve. Au retour, ils reprennent
là où ils en étaient. La sortie de la SOURCE d'un lien peut toujours libérer ses cibles
selon la mécanique concernée.

## UI 145-152
- 145/146 : compteur dynamique `+N AUTRES EFFETS` déjà présent et validé.
- 147/148 : Makibishi est désormais un vrai état de terrain permanent, pas un badge Tenten.
- 149 : transparence inciblable validée.
- 150 : voile STUN validé.
- 151 : bouclier visible / bouclier caché Kurenai validés.
- 152 : cooldown `T x/y` validé.

## Note de parité
Cette P26 R2 applique la règle YUGITO explicitement définie par le concepteur. Elle devient
la règle d'autorité du portage Godot même si un ancien snapshot PC autorise encore certains
Switchs qui nettoient ces liens.
