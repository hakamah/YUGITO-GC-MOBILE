1. **[CRITIQUE — architecture]** Le moteur Godot est encore une réécriture manuelle du moteur Python. Tant que les deux moteurs existent séparément, chaque correction PC risque d’être oubliée côté Godot. 
2. **[CRITIQUE — tests]** Créer un banc de tests automatique PC ↔ Godot : même deck, même seed RNG, même attaque, puis comparaison PV/boucliers/états/cimetière/réserve. 
3. **[CRITIQUE — tests]** Ajouter des scénarios automatisés A2 → Switch → Counter-Switch → K.O. → remplacement → A1. 
4. **[CRITIQUE — tests]** Ajouter des tests pour chaque combinaison spéciale/passif sensible au timing. 
5. **[CRITIQUE — RNG]** Pouvoir imposer une seed identique pour tester Shisui, Omoi, Haku, Chôjûrô, Ino, Jûgo, etc. 
6. **[CRITIQUE — état]** Le PC possède énormément de champs explicites dans `CardInstance`; Godot compacte encore beaucoup de choses dans `status_tags`. Il faut s’assurer qu’aucun état ne se perd ou n’entre en collision. 
7. **[CRITIQUE — réserve]** Vérifier que *absolument tous* les états persistants survivent au Switch, pas seulement HP/bouclier/cooldown/tags génériques. 
8. **[CRITIQUE — réserve]** Vérifier que les états qui ne doivent **pas** survivre à un Switch sont bien supprimés. 
9. **[CRITIQUE — mort]** Vérifier l’ordre exact : prévention K.O. → survie → effets de mort → cimetière → effets déclenchés par mort → remplacement. 
10. **[CRITIQUE — chaînes]** Une mort au milieu d’une A2 doit réellement interrompre la file, attendre le remplacement, puis reprendre la séquence au bon endroit. 
11. **[CRITIQUE — objets Godot]** Le crash `Trying to cast a freed object` a été traité par UID/slots, mais il faut stresser ce système avec morts, switches et remplacements successifs. 
12. **[DEV]** `project.godot` porte encore un nom de Prototype 13 alors qu’on est en P14. 
13. **[DEV]** `CARD_PARITY_MATRIX.md` est devenu obsolète : il marque encore énormément de personnages « à porter ». 
14. **[DEV]** `MIGRATION_2_0.md` contient également des informations dépassées sur A1/A2. 
15. **[DEV]** Nettoyer les vieux fichiers `PROTOTYPE_03...13_NOTES.md` du build final ou les déplacer dans `/docs/history`. 
16. **[MENU]** Reproduire définitivement le menu Classic comme interface principale, sans conserver l’ancien shell horizontal Godot derrière. 
17. **[MENU]** Supprimer les mentions `GODOT 2.0`, `BUILD 14`, `CLASSIC PARITY`, `PROTOTYPE`, etc. dans une version joueur. 
18. **[MENU]** Le profil affiche actuellement `HAKAMAH / ELO 100 / PROFIL LOCAL` en dur. 
19. **[MENU]** Récupérer le vrai pseudo depuis l’identité du compte. 
20. **[MENU]** Récupérer le vrai ELO. 
21. **[MENU]** Récupérer le vrai statut connecté/hors-ligne. 
22. **[MENU]** Le bouton Boutique redirige actuellement vers la Collection : créer la vraie Boutique. 
23. **[MENU]** Le bouton Amis & Messages n’ouvre pas encore le vrai système social. 
24. **[MENU]** Le bouton Profil ouvre actuellement les Options : créer le vrai Profil. 
25. **[MENU]** Ajouter les vraies icônes Classic plutôt que les losanges temporaires `◆`. 
26. **[MENU]** Ajouter le scroll de panneau droit comme sur Tkinter. 
27. **[MENU]** Ajouter le comportement molette limité au panneau de menu. 
28. **[MENU]** Ajouter le lien Tipeee réellement cliquable. 
29. **[MENU]** Ajouter Discord réellement cliquable. 
30. **[MENU]** Ajouter Quitter. 
31. **[MENU]** Ajouter Audio directement dans le menu comme dans Classic. 
32. **[MENU]** Rebrancher F11 plein écran/fenêtre globalement. 
33. **[MENU]** Échap doit reproduire exactement la navigation arrière PC suivant l’écran courant. 
34. **[MENU]** Réimplémenter le mode **Solo DEV caché N+A+R** utile pour tester les deux camps manuellement. 
35. **[AUTH]** Google Sign-In n’existe pas encore dans le client Godot. 
36. **[AUTH]** Claim/validation du pseudo absents. 
37. **[AUTH]** Sauvegarde sécurisée de session absente. 
38. **[AUTH]** Synchronisation profil/ELO serveur absente. 
39. **[BOUTIQUE]** Économie YT absente. 
40. **[BOUTIQUE]** Propriété des cartes absente. 
41. **[BOUTIQUE]** Cartes de base / possédées / gratuites de la semaine absentes. 
42. **[BOUTIQUE]** Achat et validation serveur absents. 
43. **[BOUTIQUE]** Permis de deck multijoueur absent. 
44. **[PROFIL]** Historique/stats compte à reconstruire. 
45. **[SOCIAL]** Liste d’amis absente. 
46. **[SOCIAL]** Invitations d’amis absentes. 
47. **[SOCIAL]** Messages privés absents. 
48. **[SOCIAL]** Groupes absents. 
49. **[SOCIAL]** Tournois de groupes absents. 
50. **[SOCIAL]** Invitations à un duel privé absentes. 
51. **[MULTI]** LAN absent. 
52. **[MULTI]** Internet/MQTT absent. 
53. **[MULTI]** Héberger/rejoindre une room absent. 
54. **[MULTI]** Navigateur de salons absent. 
55. **[MULTI]** Matchmaking classé absent. 
56. **[MULTI]** Spectateur tournoi absent. 
57. **[MULTI]** Chat global/combat absent. 
58. **[MULTI]** Déconnexion = défaite à réimplémenter. 
59. **[MULTI]** Synchronisation A1/A2 réseau à réimplémenter. 
60. **[MULTI]** Autorité des timers réseau à réimplémenter. 
61. **[UPDATE]** Updater automatique Classic absent. 
62. **[UPDATE]** Écran nouvelle version/téléchargement absent. 
63. **[OPTIONS]** Les volumes du menu et du combat utilisent encore deux gestions séparées. 
64. **[OPTIONS]** La valeur Musique doit être globale et persistante. 
65. **[OPTIONS]** La valeur SFX doit être globale et persistante. 
66. **[OPTIONS]** Sauvegarder plein écran/fenêtre/VSync. 
67. **[OPTIONS]** Reprendre les fonctions de test audio du PC. 
68. **[AUDIO]** Les 38 fichiers audio PC sont bien présents dans Godot, mais tous leurs déclencheurs ne sont pas encore garantis identiques au PC. 
69. **[AUDIO]** Son passif uniquement lorsque le passif se déclenche réellement. 
70. **[AUDIO]** Son spécial uniquement lors de la consommation réelle de la spéciale. 
71. **[AUDIO]** Le cas Ino est particulièrement important : aucun son spécial au simple clic, uniquement si le Transfert réussit réellement comme sur PC. 
72. **[AUDIO]** Sons KO/victoire/défaite à vérifier sur toutes les sorties de combat. 
73. **[PRÉ-COMBAT]** Ajouter un vrai timer de 30 s au Shifumi. 
74. **[PRÉ-COMBAT]** Ajouter la résolution automatique au timeout. 
75. **[PRÉ-COMBAT]** Timer 30 s au Draft. 
76. **[PRÉ-COMBAT]** Auto-pick au timeout. 
77. **[PRÉ-COMBAT]** Timer au choix des 3 Ninjas. 
78. **[PRÉ-COMBAT]** Auto-sélection au timeout. 
79. **[PRÉ-COMBAT]** Garder le deuxième Shifumi exactement comme PC pour déterminer qui commence. 
80. **[DRAFT]** La séquence `W L L W W L L W...` est maintenant présente, mais il faut la tester sur les 16 picks sans exception. 
81. **[DRAFT]** Vérifier le plafond cumulatif 3★ → 3,5★ → 4★ → 4,5★ → 5★ pick par pick. 
82. **[DRAFT]** Vérifier tous les quotas de rareté à chaque pick. 
83. **[DRAFT]** Vérifier le total 32,5★ pendant le draft et pas uniquement à la fin. 
84. **[DRAFT]** Griser visuellement toutes les cartes illégales exactement comme le PC. 
85. **[DRAFT]** Une carte choisie doit disparaître instantanément du pool adverse. 
86. **[DRAFT]** Son de sélection à chaque vraie confirmation. 
87. **[DRAFT]** Fiche complète au clic sans sélectionner immédiatement la carte. 
88. **[DRAFT]** Séparer clairement `prévisualiser` de `confirmer ce Ninja`. 
89. **[DRAFT]** Améliorer le contraste de la carte actuellement sélectionnée. 
90. **[DRAFT]** Conserver un scroll fluide avec beaucoup de cartes. 
91. **[DRAFT IA]** Comparer l’IA Godot améliorée avec l’IA PC pour éviter qu’elle fasse des decks incohérents. 
92. **[STARTERS]** Choix de 3 : fiche détaillée doit rester disponible. 
93. **[STARTERS]** Sélection beaucoup plus visible que le simple contour actuel. 
94. **[STARTERS]** Les 5 autres cartes doivent rester réellement cachées à l’adversaire. 
95. **[STARTERS IA]** Vérifier que l’IA n’utilise aucune information qu’un joueur humain ne posséderait pas. 
96. **[COMBAT — timer]** Ajouter le vrai timer 30 secondes à chaque phase décisionnelle. 
97. **[COMBAT — timer]** Auto-validation/auto-résolution au timeout. 
98. **[COMBAT — plan]** Ajouter les boutons d’annulation séparés A1/A2 exactement comme PC. 
99. **[COMBAT — plan]** Ajouter l’annulation indépendante de Hiraishin. 
100. **[COMBAT — plan]** Permettre de remplacer une A1/A2 déjà préparée sans état fantôme. 
101. **[COMBAT — A2]** A2 doit être consommée à la **prochaine validation adverse**, même si elle est devenue illégale. 
102. **[COMBAT — A2]** Ordre exact : **A2 adverse → Hiraishin gratuit → A1 du joueur actif**. 
103. **[COMBAT — A2]** Un Switch A2 doit se produire avant l’attaque qui déclenche la réaction. 
104. **[COMBAT — A2]** L’attaque préparée doit suivre le slot uniquement lorsqu’un vrai Switch A2 réactif vient de modifier ce slot. 
105. **[COMBAT — A2]** Un remplacement après K.O. ne doit pas être confondu avec un Switch A2 et ne doit donc pas automatiquement transférer une vieille cible. 
106. **[COMBAT — A2]** A1 spéciale d’un Ninja A + A2 spéciale d’un Ninja B doit rester légal. 
107. **[COMBAT — A2]** Le même Ninja ne doit pas programmer deux fois sa propre spéciale dans le même plan. 
108. **[COMBAT — Hiraishin]** La case gratuite de Minato doit être une vraie troisième case distincte dans le HUD. 
109. **[COMBAT — Hiraishin]** Hiraishin ne doit accepter qu’une attaque normale de Minato. 
110. **[COMBAT — Hiraishin]** Minato doit pouvoir faire Hiraishin + A1 normale + A2 spéciale selon les règles PC. 
111. **[COMBAT — attaque directe]** Ajouter le bouton **ATTAQUE DIRECTE** comme dans le PC au lieu d’un comportement seulement implicite. 
112. **[COMBAT — attaque directe]** Actif uniquement lorsque les 3 slots adverses sont vides. 
113. **[COMBAT — attaque directe]** Dégâts = `max(100, stat / 2)`. 
114. **[COMBAT — Kakashi]** Il manque surtout le bouton **COPIE : \<spéciale>** dans le panneau d’action. 
115. **[COMBAT — Kakashi]** Godot sait mémoriser `copied_special_id`, mais il faut pouvoir réellement sélectionner et lancer cette copie. 
116. **[COMBAT — Kakashi]** La copie ne doit pas supprimer Raikiri. 
117. **[COMBAT — formule]** Vérifier attaque-défense identique au PC pour chaque art. 
118. **[COMBAT — formule]** Vérifier plancher 100 si différence positive faible. 
119. **[COMBAT — zéro dégât]** Reproduire exactement le fallback anti-zéro dépendant des étoiles. 
120. **[COMBAT — élément]** Feu > Vent > Foudre > Terre > Eau > Feu. 
121. **[COMBAT — élément]** Avantage = ×1,10 puis +150, dans le bon ordre. 
122. **[COMBAT — Tous]** Kakuzu ne doit subir aucune faiblesse et doit toujours frapper super-efficace. 
123. **[COMBAT — surplus]** Seules les vraies attaques doivent envoyer le surplus aux PV joueur. 
124. **[COMBAT — dégâts fixes]** Poison, DOT et dégâts fixes ne doivent jamais provoquer de surplus joueur. 
125. **[COMBAT — bouclier]** Respecter exactement l’ordre réduction → bouclier → HP. 
126. **[COMBAT — bouclier]** Gérer séparément le bouclier visible et le bouclier caché de Kurenai. 
127. **[COMBAT — défense]** Ordre : garde/interception → immunité/esquive → réduction → bouclier → survie → HP → K.O. 
128. **[COMBAT — victoire]** Défaite quand PV joueur = 0. 
129. **[COMBAT — victoire]** Défaite également lorsqu’il n’existe réellement plus aucun Ninja terrain/réserve capable de continuer. 
130. **[COMBAT — résultat]** Refaire l’overlay victoire/défaite proche du PC. 
131. **[COMBAT — résultat]** Ajouter Rejouer. 
132. **[COMBAT — journal]** Refaire le vrai Journal détaillé du PC. 
133. **[COMBAT — info]** Ajouter la fiche complète d’un Ninja ennemi au clic. 
134. **[COMBAT — info]** Ajouter les informations de passif/spéciale accessibles sans changer la sélection offensive. 
135. **[COMBAT — réserve]** Le Switch manuel doit conserver l’instance complète. 
136. **[COMBAT — réserve]** Le remplaçant de K.O. est une **nouvelle entrée depuis réserve**, pas une remise à neuf arbitraire. 
137. **[COMBAT — remplacement]** Jusqu’à 3 propositions aléatoires. 
138. **[COMBAT — remplacement]** Les cartes non choisies restent en réserve. 
139. **[COMBAT — remplacement]** Même slot que la carte morte. 
140. **[COMBAT — remplacement]** Si réserve vide, laisser le trou. 
141. **[COMBAT — remplacement]** Timeout remplacement avec choix automatique. 
142. **[COMBAT — trackers]** Neji/Hinata/Ao doivent pouvoir forcer une carte précise de la réserve au prochain Switch/remplacement. 
143. **[COMBAT — trackers]** La cible forcée doit disparaître après consommation. 
144. **[COMBAT — liens]** Nettoyer proprement les liens lorsque source/cible quitte le terrain ou meurt. 
145. **[ÉTATS UI]** Actuellement une carte n’affiche que **5 badges maximum** ; c’est insuffisant pour les combos lourds. 
146. **[ÉTATS UI]** Créer un système dynamique : badges prioritaires + compteur `+N` ou seconde colonne. 
147. **[ÉTATS UI]** Les états liés au **terrain** ne devraient pas être affichés comme s’ils appartenaient à une seule carte. 
148. **[ÉTATS UI]** Makibishi doit avoir un indicateur de terrain adverse permanent. 
149. **[ÉTATS UI]** Ajouter un vrai visuel inciblable/transparence \~40 %, comme le PC. 
150. **[ÉTATS UI]** Ajouter le voile STUN. 
151. **[ÉTATS UI]** Ajouter un rendu bouclier plus évident que le simple `PV +XXX`. 
152. **[ÉTATS UI]** Ajouter les cooldowns `T 1/3`, `T 2/3`, etc., pas seulement `SPÉ 2T`. 
153. **[ÉTATS UI]** Enraciné : bandeau clairement visible. 
154. **[ÉTATS UI]** Prison de glace : visuel dédié. 
155. **[ÉTATS UI]** Prison aqueuse : visuel dédié. 
156. **[ÉTATS UI]** Ombres de Shikamaru : lien visuel source→cibles. 
157. **[ÉTATS UI]** Jashin : compteur 5 tours visible. 
158. **[ÉTATS UI]** Poison Shino/Hanzo/Torune/Shizune/Anko/Sasori : différencier les types. 
159. **[ÉTATS UI]** Scellé Kushina : bandeau et décompte. 
160. **[ÉTATS UI]** Sexy Jutsu : transformation/état visible. 
161. **[ÉTATS UI]** Brume Zabuza/Gengetsu/Konan/Tobi/Zetsu : distinguer les différentes inciblabilités. 
162. **[ÉTATS UI]** Counter-Switch armé : badge explicite. 
163. **[ÉTATS UI]** Don Yamato Counter-Switch : badge séparé. 
164. **[ÉTATS UI]** Défense marionnettiste Kankuro active : indicateur permanent. 
165. **[ÉTATS UI]** Protection Doton Kurotsuchi : afficher qui a déjà consommé sa protection. 
166. **[ÉTATS UI]** Cœurs de Kakuzu : icône `♥ ×2`, `♥ ×1`. 
167. **[ÉTATS UI]** Division Mû : afficher Jinton bloqué. 
168. **[ÉTATS UI]** Hiramekarei : afficher le stock exact. 
169. **[ÉTATS UI]** Bombes Tobi : idéalement reprendre les petites icônes **Bombe ×1…×5** sur chaque cible, pas seulement un badge texte. 
170. **[ÉTATS UI]** Prédiction Tobi : indication secrète côté propriétaire uniquement. 
171. **[ÉTATS UI]** Possession Ino : corps contrôlé clairement blanc/inciblable. 
172. **[ÉTATS UI]** Ino doit visuellement adopter l’identité/stats/élément du corps contrôlé de façon compréhensible. 
173. **[TRANSFORMATIONS]** Les illustrations doivent changer en temps réel pour Naruto sous 50 %. 
174. **[TRANSFORMATIONS]** Jiraiya Mode ermite. 
175. **[TRANSFORMATIONS]** Gai aux différents seuils de portes. 
176. **[TRANSFORMATIONS]** Gengetsu clone. 
177. **[TRANSFORMATIONS]** Jûgo stade 1/stade 2. 
178. **[TRANSFORMATIONS]** Rin / Isobu. 
179. **[TRANSFORMATIONS]** Sexy Jutsu Konohamaru. 
180. **[IA]** L’IA Godot est déjà meilleure que la version brute PC sur le scoring, mais il faut maintenant tester qu’elle respecte **toutes les règles**, pas seulement qu’elle joue intelligemment. 
181. **[IA]** Elle doit comprendre quand une cible est inciblable avant de gaspiller une action. 
182. **[IA]** Elle doit connaître les esquives probabilistes. 
183. **[IA]** Elle doit comprendre les Counter-Switch. 
184. **[IA]** Elle doit anticiper Choji qui intercepte. 
185. **[IA]** Elle doit anticiper Kankuro qui protège. 
186. **[IA]** Elle doit anticiper un bouclier avant de choisir Mifune. 
187. **[IA]** Elle doit savoir quand une spéciale de contrôle vaut mieux qu’un gros dégât. 
188. **[IA]** Elle doit éviter d’utiliser une spéciale qui ne peut pas fonctionner sur Madara. 
189. **[IA]** Elle doit utiliser un Switch A2 défensif/réactif, pas seulement des switches de survie A1. 
190. **[IA]** Elle doit tenir compte du tracker Neji/Hinata/Ao. 
191. **[IA]** Elle doit savoir exploiter les bombes Tobi. 
192. **[IA]** Elle doit choisir une prédiction Tobi plausible attaquant+cible. 
193. **[IA]** Elle doit tenir compte des synergies perdues/gagnées lors d’un switch. 
194. **[IA]** Elle doit choisir le meilleur remplaçant parmi les 3 propositions et non juste le meilleur brut. 
195. **[IA]** Elle doit préserver une carte stratégique même si ses stats brutes sont plus faibles. 
196. **[IA]** Ajouter différents niveaux de difficulté à terme. 
197. **[CARTE — Hashirama]** Vérifier le -100 AOE au **début de chacun de ses tours**, les K.O. causés par ce tick, puis Dragon de bois + soin 200 uniquement si dégâts. 
198. **[CARTE — Madara]** Immunité aux spéciales Genjutsu + immunité complète aux contrôles incapacitants + Susanoo +500 puis bouclier 300. 
199. **[CARTE — Nagato]** Réduction 200 NIN/GEN et blocage Taijutsu après Shinra Tensei. 
200. **[CARTE — Obito]** Intangibilité un tour adverse sur deux en commençant intangible + Kamui offensif qui **détruit** les boucliers avant de frapper. 
201. **[CARTE — Itachi]** Tsukuyomi après vrais dégâts HP + immunités Killer Bee/Madara + Counter-Switch + Katon AOE 350 aux autres. 
202. **[CARTE — Jiraiya]** +10/+10/+10 permanent par tour + transformation visuelle Mode ermite. 
203. **[CARTE — Killer Bee]** Impossible de perdre son tour, spéciale impossible à bloquer, Bijûdama et condition ≥400 pour bouclier. 
204. **[CARTE — Gai]** Trois seuils 75/50/25 %, +250 cumulatif, changement d’image, Hirudora et recoil non létal. 
205. **[CARTE — Minato]** Ignore tous passifs défensifs avec toutes ses attaques + Hiraishin gratuit + Rasengan + bouclier après K.O. 
206. **[CARTE — Naruto]** Bonus +350/+350 uniquement sous 50 % + illustration + debuff Ninjutsu de la spéciale avec durée exacte. 
207. **[CARTE — Sasuke]** Immunité art/source pendant 3 tours + Counter-Switch + Chidori qui traverse absolument défense/inciblabilité/esquive/garde/réduction/bouclier/survie et supprime les protections. 
208. **[CARTE — 4e Raikage]** -120 dégâts sur toutes les attaques, pas seulement Taijutsu, puis Lariat. 
209. **[CARTE — Danzo]** Izanagi une seule fois à 1 HP + Kamikaze suicide définitif/cible à 1 HP. 
210. **[CARTE — Gaara]** Première attaque dommageable du tour adverse -300 + Mur de sable 600 à tous. 
211. **[CARTE — Hiruzen]** Bonus +100 uniquement si art différent de la frappe précédente + spéciale toujours avantage élémentaire. 
212. **[CARTE — Kakashi]** Copie de la première spéciale dommageable + utilisation manuelle de la copie + Raikiri conservé + Counter-Switch. 
213. **[CARTE — Kisame]** Heal 100 après Ninjutsu dommageable + Prison aqueuse persistante jusqu’à mort de Kisame + -100 NIN/tour. 
214. **[CARTE — Orochimaru]** Mue à 250 une fois + vol de la carte **la plus récente** du cimetière ennemi vers la réserve. 
215. **[CARTE — Tsunade]** Heal 200 en début de tour sous 50 %, full heal si elle survit ≤15 %, aucun miracle sur coup fatal, spéciale +100 heal. 
216. **[CARTE — Deidara]** Ninjutsu dommageable → 150 fixes aux voisins + C3 → Ninjutsu bloqué prochain tour. 
217. **[CARTE — Hidan]** Survie 200 une fois + Jashin 5 tours lié à la mort définitive de Hidan. 
218. **[CARTE — Kabuto]** Sauvetage d’un autre allié une fois tant qu’il vit + soin complet automatique + Scalpel bypass absolu prévu. 
219. **[CARTE — Neji]** Premier contact unique : -50 % NIN + spéciale bloquée 2 tours + 64 Poings + tracker de réserve. 
220. **[CARTE — Rock Lee]** Deux premières frappes Tai +150 + tenue +300 Tai permanente sur un allié. 
221. **[CARTE — Sakura]** Heal 25 % de ses propres dégâts reçus + soin alliés + aura qui soigne 25 % des dégâts des autres alliés + K.O. spécial = heal 200. 
222. **[CARTE — Sasori]** Une riposte Tai max par tour adverse : -100 Tai permanent + 50 poison + spéciale delayed 100 au prochain tour cible. 
223. **[CARTE — Shikamaru]** +150 Gen contre cible plus étoilée + une cible libre / toutes les autres STUN 3 tours + cooldown 4 + rupture dès le moindre HP damage reçu. 
224. **[CARTE — Temari]** +100 NIN sans avantage + AOE +250 + cible initiale soufflée en réserve + remplacement normal. 
225. **[CARTE — Choji]** Interception permanente + Pilule +500 Tai pendant exactement 3 de ses tours. 
226. **[CARTE — Hinata]** Riposte 100 + -35 % de l’art 2 tours à chaque attaque reçue non annulée + spéciale bouclier + tracker. 
227. **[CARTE — Kankuro]** Karasu absorbe le premier K.O. et remet Kankuro full HP + Défense marionnettiste persiste ensuite. 
228. **[CARTE — Kiba]** +150 première frappe Tai après **chaque entrée** terrain + Gatsûga condition sur Tai de base. 
229. **[CARTE — Shino]** Ninjutsu dommageable = -100 NIN temporaire + poison spécial permanent jusqu’à mort. 
230. **[CARTE — Suigetsu]** -150 dégâts Tai sauf attaquant Foudre + spécial + soin 150. 
231. **[CARTE — Tenten]** +25 Tai permanent à chaque frappe Tai + Makibishi 7 % HP max à **toute entrée**, bypass shield, terrain non cumulable. 
232. **[CARTE — Karin]** Heal 600 tous les 2 de ses tours + heal total allié contre -1000 HP de Karin + cooldown 3. 
233. **[CARTE — Ônoki]** Esquive du premier coup mortel + Jinton compare NIN puis -1000 NIN permanent. 
234. **[CARTE — Gengetsu]** Inciblable un tour sur deux + clone 4800 HP/0 arts 2 tours + explosion 1300 AOE seulement si clone survit + restauration état + cooldown 4 après retour. 
235. **[CARTE — Tobirama]** Une attaque sur deux à seulement 25 % des dégâts + 650 fixes AOE. 
236. **[CARTE — Zabuza]** Inciblable alterné + Dragon aqueux. 
237. **[CARTE — Shisui]** 1/3 esquive sur chaque attaque + Genjutsu AOE STUN 2 tours. 
238. **[CARTE — Konohamaru]** 1/2 esquive + Rasengan 350 uniquement sur esquive réussie + Sexy Jutsu homme/femme + cooldown 4. 
239. **[CARTE — Haku]** À l’entrée : garde 2/3 sur première attaque programmée + prison glace 3 tours avec -200/tour. 
240. **[CARTE — 3e Raikage]** Recoil 20 % après attaque normale dommageable + spéciale -50 % HP actuel sans recoil. 
241. **[CARTE — Chiyo]** Sauvetage autre allié une fois, mort avant usage = full heal aléatoire + marionnettes +250 Tai et -20 % dégâts aux autres alliés. 
242. **[CARTE — Hanzo]** À son tour : -5 % alliés / -10 % ennemis + poison 5 % permanent cumulable. 
243. **[CARTE — Kakuzu]** Deux résurrections full HP + élément Tous + spéciale forcément super-efficace. 
244. **[CARTE — Mei]** Contrecoup Feu 100 sur Tai reçu + spéciale fixe 900/450 avec avantage élémentaire par impact. 
245. **[CARTE — Ino]** Le Transfert est probablement le test de parité le plus important : réussite 50 %, durée selon étoiles, échec STUN 3 tours, cooldown 3, état du corps contrôlé conservé, stats/élément transférés, vraie mort liée, inciblabilité d’Ino. 
246. **[CARTE — Kurenai]** Première attaque -200 à chaque tour + cleanse allié + prochaine spéciale annulée + bouclier caché 600. 
247. **[CARTE — Sai]** Chaque art qui le touche inflige -200 dans cet art à l’attaquant pendant 2 tours + prison 3 tours. 
248. **[CARTE — Ao]** Riposte Tai **avant** toute spéciale ennemie ; si elle tue le lanceur, la spéciale est perdue + tracker réserve. 
249. **[CARTE — Torune]** Contact Tai → poison 50/tour jusqu’à mort + spéciale poison 100/tour cumulable. 
250. **[CARTE — Mifune]** Trancheur doit ignorer esquive/réduction/Choji mais pas inciblabilité/survie, convertir moitié du bouclier en dégâts puis détruire le bouclier ; spéciale +500/+750 selon défense initiale. 
251. **[CARTE — Asuma]** Sous 20 % vivant → inciblable 2 tours, explosion après le deuxième = 20 % de ses HP restants sur tous les ennemis + spéciale détruit boucliers puis 400 fixes. 
252. **[CARTE — Kushina]** Mort définitive scelle son tueur 4 tours + spéciale scelle 5 tours et retire 20 % HP max. 
253. **[CARTE — Rin]** Sous 25 % une fois → +1000 HP max/actuel + stats Isobu + spéciale 550 fixes. 
254. **[CARTE — Shizune]** Mort → tueur à 50 % des trois arts pendant 3 tours + spéciale STUN 2 + -30/tour jusqu’à mort. 
255. **[CARTE — Kimimaro]** -25 % tous dégâts + furie permanente +15 % arts et -10 % HP max au début de chaque tour. 
256. **[CARTE — Chôjûrô]** ±200 aléatoire juste avant chaque frappe + Hiramekarei +50 par tour complet et libération du stock, spéciale toujours réutilisable. 
257. **[CARTE — Konan]** Inciblable/tangible en alternance en commençant inciblable + mine permanente qui ne proc que quand elle est ciblable. 
258. **[CARTE — Jûgo]** Stades à 30/60 % de HP perdus + modifications HP/stats et images + spéciale tirage sexe ×1,5 ou ×0,5. 
259. **[CARTE — Kurotsuchi]** Chaque autre allié possède son propre sauvetage létal une fois + 350 shield à tous. 
260. **[CARTE — Mû]** Survie full HP une fois mais -450 NIN + Jinton définitivement désactivé ; spéciale Jinton et -1000 NIN. 
261. **[CARTE — Omoi]** 1/3 attaque annulée, sinon ×1,20 dégâts finaux ; même mécanique sur la spéciale 500 + paralysie. 
262. **[CARTE — Karui]** Mort définitive d’un membre de famille → +300 HP/arts 2 tours, durée rafraîchie non cumulée + 400 fixes inesquivable sauf inciblabilité. 
263. **[CARTE — Anko]** Sous 25 % une fois → heal 600 +10 % arts permanent + permutation prochaine attaque + poison 100 pendant 4 tours. 
264. **[CARTE — Yamato]** Le Counter transmis doit fonctionner **uniquement quand Yamato sort par Switch A2 réactif** + Mokuton -20 % HP max puis enracinement 3 tours. 
265. **[CARTE — Zetsu]** Révéler les Switch A2 adverses, STUN 2 tours sur entrée par Switch A1, ciblable alterné, soin allié 25 % des HP réellement perdus, spéciale intercepte un Switch A2 ou inflige 300. 
266. **[CARTE — Tobi]** Intangible alterné + bombe obligatoire au début de chacun de ses tours + max 5/cible + 320 fixe chacune au Switch + prédiction exacte attaquant/cible sur A1 **ou A2** + suppression du stack si échec + toutes bombes disparaissent à la mort de Tobi. 
267. **[SYNERGIES]** Les tableaux famille/duos Godot sont maintenant identiques aux constantes PC, mais il faut tester tous les recalculs dynamiques à chaque entrée/sortie/mort/transformation. 
268. **[SYNERGIES]** Trio famille = +20 %. 
269. **[SYNERGIES]** Deux membres d’une famille = +12,5 %. 
270. **[SYNERGIES]** Duo explicite = +15 %. 
271. **[SYNERGIES]** Zetsu + Akatsuki = +15 %. 
272. **[SYNERGIES]** Jamais de cumul : conserver uniquement le meilleur. 
273. **[SYNERGIES]** HP max doit évoluer avec la synergie sans soigner artificiellement : conserver le ratio HP comme le moteur PC. 
274. **[SYNERGIES]** La synergie doit disparaître/réapparaître proprement lors d’un Switch. 
275. **[COLLECTION]** Ajouter la recherche texte du catalogue PC. 
276. **[COLLECTION]** Ajouter filtres/rôles. 
277. **[COLLECTION]** Ajouter badges de rôles. 
278. **[COLLECTION]** Ajouter onglet/texte Synergies propre. 
279. **[COLLECTION]** Ajouter statut possédée/base/gratuite si on réactive l’économie. 
280. **[COLLECTION]** Fiche longue avec scroll indépendant. 
281. **[DECK]** Ajouter les filtres de cartes du deck builder PC. 
282. **[DECK]** Pagination/scroll propre. 
283. **[DECK]** Afficher en direct total étoiles + quotas. 
284. **[DECK]** Montrer clairement pourquoi une carte est interdite. 
285. **[DECK]** Déconnecter le deck local du draft Solo si nécessaire : le Solo Classic actuel draft ses 8 cartes. 
286. **[GUIDE]** Refaire le vrai guide de combat plutôt que le résumé actuel. 
287. **[GUIDE]** Roue des éléments. 
288. **[GUIDE]** Explication A1/A2 avec exemple visuel. 
289. **[GUIDE]** Hiraishin gratuit. 
290. **[GUIDE]** Switch A1 vs Switch A2. 
291. **[GUIDE]** Inciblable / esquive / bouclier / réduction / survie. 
292. **[GUIDIDE]** Cooldowns. 
293. **[GUIDE]** Synergies. 
294. **[GUIDE]** Dégâts fixes vs vraie attaque vs surplus. 
295. **[ERGONOMIE]** Ajouter des tooltips partout. 
296. **[ERGONOMIE]** Feedback sonore au hover/clic/confirmation, sans spam. 
297. **[ERGONOMIE]** Toutes les fenêtres modales doivent réellement bloquer les clics derrière. 
298. **[ERGONOMIE]** Ne jamais afficher de texte sous/derrière une modale comme le bug P09. 
299. **[ERGONOMIE]** Conserver un focus clavier/manette propre. 
300. **[ERGONOMIE]** Vérifier 16:9, 16:10, ultrawide et résolutions inférieures. 
301. **[ERGONOMIE]** UI actuellement construite majoritairement avec coordonnées 1600×900 fixes : sécuriser l’adaptation responsive. 
302. **[PERF]** Vérifier les 60/120/144 Hz et le frame pacing réel. 
303. **[PERF]** Le flottement ne doit pas changer de vitesse selon le framerate. 
304. **[PERF]** Les badges ne doivent pas être recréés inutilement à chaque frame. 
305. **[PERF]** Mettre en cache les textures/ressources audio au lieu de `load()` répétitifs pendant les actions. 
306. **[PERF]** Pooler les petits FX plutôt que créer/détruire beaucoup de Nodes. 
307. **[QA]** Faire un duel avec **chaque carte au moins une fois**. 
308. **[QA]** Tester chacune des 70 spéciales. 
309. **[QA]** Tester chacun des 70 passifs. 
310. **[QA]** Tester chaque passive après entrée normale, Switch A1, Switch A2 et remplacement K.O. lorsque pertinent. 
311. **[QA]** Tester toutes les survies en présence de Chidori/Kabuto/Chiyo/Kurotsuchi. 
312. **[QA]** Tester toutes les inciblabilités contre les attaques normales, spéciales fixes et attaques absolues. 
313. **[QA]** Tester tous les poisons simultanément. 
314. **[QA]** Tester plusieurs boucliers + Kurenai + Mifune + Obito. 
315. **[QA]** Tester Jashin pendant qu’Hidan déclenche sa propre Immortalité. 
316. **[QA]** Tester Shikamaru interrompu par poison/bouclier : seules les pertes réelles de HP pertinentes doivent casser les ombres selon le moteur PC. 
317. **[QA]** Tester Ino contrôlant une cible empoisonnée, buffée, shieldée, STUN, puis restitution. 
318. **[QA]** Tester Temari renvoyant une cible qui porte bombes Tobi/Jashin/prison/tracker. 
319. **[QA]** Tester Zetsu + Tobi + Switch A2 : c’est une des chaînes les plus complexes du jeu. 
320. **[QA]** Tester Ao qui tue le lanceur avant sa spéciale. 
321. **[QA]** Tester Chidori contre absolument chaque défense. 
322. **[QA]** Tester Mifune contre chaque défense. 
323. **[QA]** Tester Madara contre chaque contrôle. 
324. **[QA]** Tester Killer Bee contre chaque blocage/STUN. 
325. **[QA]** Tester un K.O. causé par un DOT au début du tour. 
326. **[QA]** Tester un K.O. causé par un passif de mort. 
327. **[QA]** Tester un K.O. avec réserve vide. 
328. **[QA]** Tester trois K.O. successifs et plusieurs remplacements. 
329. **[QA]** Tester le surplus joueur quand une survie intervient. 
330. **[QA]** Enfin, enregistrer ces scénarios comme tests de non-régression avant de considérer Godot comme remplaçant officiel du client Tkinter. 

Le constat global est donc assez clair : **visuellement Godot a déjà dépassé Tkinter**, les **70 données de cartes sont bien identiques**, et une grosse partie de la logique existe maintenant. Mais ce qui sépare encore P14 d’un vrai « YUGITO Godot = YUGITO Tkinter » est surtout le **niveau de précision des interactions croisées**.

La priorité de développement que je mettrais maintenant est : **A2/ordonnanceur → états persistants → 70 cartes testées une par une → badges/FX d’état → IA → seulement ensuite les services secondaires comme réseau/boutique/social**.