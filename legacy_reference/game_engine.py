from __future__ import annotations

from dataclasses import dataclass, field as dc_field
import random
import copy
from typing import Optional

from .cards import CardDefinition


ELEMENT_BEATS = {
    "feu": "vent",
    "vent": "foudre",
    "foudre": "terre",
    "terre": "eau",
    "eau": "feu",
}

STYLE_LABELS = {
    "taijutsu": "Taijutsu",
    "ninjutsu": "Ninjutsu",
    "genjutsu": "Genjutsu",
}

# V40 : limites de composition par valeur d'étoiles. Le palier 3★ reste
# illimité (dans les faits : au plus 8 cartes puisque le deck contient 8 Ninjas).
STAR_VALUE_LIMITS: dict[float, int | None] = {
    3.0: None,
    3.5: 4,
    4.0: 3,
    4.5: 2,
    5.0: 1,
}
MAX_TOTAL_STAR_VALUE = 32.5
# Constante conservée pour compatibilité avec d'anciens imports/outils.
MAX_SAME_STAR_VALUE = 3

SPECIAL_COOLDOWN_TOTALS = {
    "ino": 3,
    "karin": 3,
    "konohamaru": 4,
    "shikamaru": 4,
    "gengetsu": 4,
}

# YUGITO06 R5 — dégâts de secours anti-écart de rareté.
# Si une vraie attaque valide tombe à 0 dégât (sans esquive/immunité),
# elle reçoit 100 dégâts fixes + un pourcentage des PV max de la cible.
# Le bonus en pourcentage est toujours plafonné à +100, donc le secours
# brut ne dépasse jamais 200 avant l'absorption éventuelle des boucliers.
ZERO_DAMAGE_STAR_PCT = {
    5.0: 0.01,
    4.5: 0.03,
    4.0: 0.06,
    3.5: 0.09,
    3.0: 0.12,
}

# Cartes féminines actuellement présentes dans le roster. Utilisé uniquement
# par le Sexy Jutsu de Konohamaru. Haku est classé parmi les Ninjas masculins.
FEMALE_CARD_IDS = {"karin", "tsunade", "sakura", "hinata", "temari", "tenten", "chiyo", "mei", "ino", "kurenai", "kushina", "rin", "shizune", "konan", "kurotsuchi", "karui", "anko"}

# Classic 1.2.5 — Synergies de terrain + Omoi/Karui/Anko.
# Les familles ci-dessous contiennent au moins 3 personnages. Deux membres
# présents ensemble donnent +12,5 % ; si les 3 Ninjas du terrain appartiennent
# tous à une même famille, chacun reçoit +20 %. Les duos explicites donnent
# +15 %. Les bonus ne se cumulent jamais : chaque Ninja garde le meilleur.
SYNERGY_FAMILIES: tuple[frozenset[str], ...] = (
    frozenset({"sarutobi", "jiraiya", "minato"}),
    frozenset({"gaara", "chiyo", "kankuro", "temari"}),
    frozenset({"jiraiya", "tsunade", "orochimaru", "sarutobi"}),
    frozenset({"orochimaru", "sasuke", "kabuto"}),
    frozenset({"orochimaru", "kimimaro", "kabuto"}),
    frozenset({"kakashi", "gai", "kurenai", "asuma"}),
    frozenset({"kakashi", "sasuke", "naruto", "sakura"}),
    frozenset({"yamato", "naruto", "sakura", "kakashi", "sai"}),
    frozenset({"sasuke", "karin", "jugo", "suigetsu"}),
    frozenset({"gai", "rock_lee", "tenten", "neji"}),
    frozenset({"kurenai", "shino", "kiba", "hinata"}),
    frozenset({"asuma", "ino", "shikamaru", "choji"}),
    frozenset({"mei", "ao", "chojuro"}),
    frozenset({"kisame", "gengetsu", "zabuza", "suigetsu"}),
    frozenset({"a3_raikage", "a_raikage", "killer_bee", "omoi", "karui"}),
    frozenset({"minato", "kakashi", "obito", "rin"}),
    frozenset({"minato", "naruto", "kushina"}),
    frozenset({"obito", "sasuke", "itachi", "madara", "shisui"}),
    frozenset({"danzo", "itachi", "kakashi", "yamato", "sai"}),
    frozenset({"onoki", "kurotsuchi", "mu"}),
)

SYNERGY_DUOS: tuple[frozenset[str], ...] = (
    frozenset({"kisame", "itachi"}),
    frozenset({"kakuzu", "hidan"}),
    frozenset({"deidara", "sasori"}),
    frozenset({"obito", "deidara"}),
    frozenset({"madara", "obito"}),
    frozenset({"tsunade", "sakura"}),
    frozenset({"tsunade", "shizune"}),
    frozenset({"nagato", "konan"}),
    frozenset({"sakura", "ino"}),
    frozenset({"shino", "torune"}),
    frozenset({"konohamaru", "naruto"}),
    frozenset({"konohamaru", "sarutobi"}),
    frozenset({"hashirama", "tsunade"}),
    frozenset({"haku", "zabuza"}),
    frozenset({"tobirama", "sarutobi"}),
    frozenset({"anko", "orochimaru"}),
    frozenset({"killer_bee", "naruto"}),
    frozenset({"danzo", "yamato"}),
    frozenset({"tobi", "deidara"}),
    frozenset({"tobi", "zetsu"}),
    frozenset({"zetsu", "deidara"}),
    frozenset({"zetsu", "sasori"}),
    frozenset({"zetsu", "itachi"}),
    frozenset({"zetsu", "kisame"}),
    frozenset({"zetsu", "hidan"}),
    frozenset({"zetsu", "kakuzu"}),
    frozenset({"zetsu", "madara"}),
    frozenset({"zetsu", "konan"}),
    frozenset({"zetsu", "nagato"}),
)


@dataclass
class TimedModifier:
    style: str
    amount: int
    turns_left: int
    label: str = ""


@dataclass
class SasukeArtLock:
    """Immunité du Sharingan contre un art précis d'une carte précise."""

    source: Optional["CardInstance"]
    style: str
    turns_left: int = 3
    created_turn: int = -1


@dataclass
class CardInstance:
    definition: CardDefinition
    current_hp: int | None = None
    has_attacked: bool = False
    special_used: bool = False
    copied_special_id: str | None = None
    copied_special_name: str = ""
    copied_special_used: bool = False
    shield: int = 0
    kurenai_hidden_shield: int = 0
    kurenai_special_protection: bool = False
    permanent_buffs: dict[str, int] = dc_field(default_factory=lambda: {"taijutsu": 0, "ninjutsu": 0, "genjutsu": 0})
    timed_modifiers: list[TimedModifier] = dc_field(default_factory=list)
    disabled_turns: int = 0
    # 1.1.6 : stuns de Possession des ombres liés à leur lanceur.
    # Ils disparaissent immédiatement si le Ninja qui les a posés meurt.
    shadow_stuns: list[dict] = dc_field(default_factory=list)
    blocked_styles: dict[str, int] = dc_field(default_factory=dict)
    special_block_turns: int = 0
    defense_triggered_turn: int = -1
    jiraiya_turns_completed: int = 0
    jiraiya_sage_active: bool = False
    gai_thresholds: set[int] = dc_field(default_factory=set)
    rock_lee_tai_boosts_left: int = 2
    kiba_first_tai: bool = True
    tenten_tai_used_this_turn: bool = False
    previous_attack_style: str | None = None
    survival_used: bool = False
    kankuro_decoy_used: bool = False
    obito_intangible: bool = True
    kankuro_defense_active: bool = False
    choji_guard_active: bool = False
    kabuto_reanimation_armed: bool = False
    minato_free_attack_used: bool = False
    delayed_damage: int = 0
    shino_poisoned: bool = False
    hanzo_poisoned: bool = False
    kakuzu_revivals_left: int = 2
    ino_possession_target: Optional["CardInstance"] = None
    ino_possession_turns_left: int = 0
    ino_possession_started_turn: int = -1
    ino_possessed_by: Optional["CardInstance"] = None
    ino_special_cooldown: int = 0
    doom_turns: int = 0
    doom_source: Optional["CardInstance"] = None
    prisoned_by: Optional["CardInstance"] = None
    karin_turn_counter: int = 0
    karin_special_cooldown: int = 0
    tobirama_attack_counter: int = 0
    shisui_attack_counter: int = 0
    haku_attack_counter: int = 0
    haku_entry_guard: bool = False
    haku_ice_prison_turns: int = 0
    choji_pill_turns: int = 0
    choji_pill_started_turn: int = -1
    konohamaru_sexy_turns: int = 0
    konohamaru_sexy_cooldown: int = 0
    konohamaru_sexy_started_turn: int = -1
    shikamaru_special_cooldown: int = 0
    chiyo_passive_used: bool = False
    chiyo_puppets_active: bool = False
    zabuza_untargetable: bool = True
    gengetsu_untargetable: bool = True
    gengetsu_clone_active: bool = False
    gengetsu_clone_turns_left: int = 0
    gengetsu_saved_hp: int | None = None
    gengetsu_saved_shield: int = 0
    gengetsu_special_cooldown: int = 0
    sasuke_art_locks: list[SasukeArtLock] = dc_field(default_factory=list)
    # 1.1.7 — contre-switch / traqueurs / nouveaux poisons.
    switch_counter_armed: bool = False
    switch_counter_armed_turn: int = -1
    reactive_switch_turn: int = -1
    neji_passive_used: bool = False
    torune_contact_poison: int = 0
    torune_micro_poison: int = 0
    # 1.2.0 — nouveaux états (10 cartes).
    max_hp_bonus: int = 0
    sealed_turns: int = 0
    shizune_poisoned: bool = False
    shizune_paralysis_turns: int = 0
    rin_isobu_active: bool = False
    kimimaro_fury_active: bool = False
    asuma_smoke_triggered: bool = False
    asuma_smoke_turns: int = 0
    chojuro_chakra_stock: int = 0
    konan_untargetable: bool = True
    konan_mine_active: bool = False
    jugo_stage: int = 0
    kurotsuchi_guard_used: bool = False
    mu_division_used: bool = False
    synergy_bonus_pct: float = 0.0
    # 1.2.5 — Omoi / Karui / Anko.
    karui_electric_turns: int = 0
    karui_electric_started_turn: int = -1
    anko_curse_used: bool = False
    anko_serpent_armed: bool = False
    anko_poison_turns: int = 0
    # 1.7.4 — Yamato / Prison du Mokuton.
    rooted_turns: int = 0
    yamato_counter_gift: bool = False
    # 1.7.6 — Zetsu : alternance ciblable/inciblable.
    zetsu_hidden: bool = False

    def __post_init__(self):
        if self.current_hp is None:
            self.current_hp = self.definition.max_hp


@dataclass
class ReplacementOffer:
    player_number: int
    slot: int
    options: list[CardDefinition]


@dataclass
class PlayerState:
    number: int
    hp: int = 4000
    # Le deck est une réserve cachée ; il n'existe pas de main pendant le duel.
    deck: list[CardDefinition] = dc_field(default_factory=list)
    field: list[Optional[CardInstance]] = dc_field(default_factory=lambda: [None, None, None])
    graveyard: list[CardDefinition] = dc_field(default_factory=list)


@dataclass
class AttackOutcome:
    damage: int = 0
    hp_damage: int = 0
    overflow_damage: int = 0
    advantage: bool = False
    atk: int = 0
    defense: int = 0
    target_slot: int | None = None
    killed: bool = False
    immune: bool = False


class GameEngine:
    """Moteur de duel YUGITO.

    Le moteur conserve le système de réserve cachée et ajoute notamment :
    - valeurs en étoiles ;
    - passifs des 35 cartes ;
    - une technique spéciale à une charge par Ninja ;
    - statuts temporaires, boucliers, survies, poisons et contrôles ;
    - file de remplacements pour gérer les effets de zone.
    """

    def __init__(
        self,
        *,
        deck1: list[CardDefinition],
        deck2: list[CardDefinition],
        starters1: list[CardDefinition],
        starters2: list[CardDefinition],
        starting_player: int = 1,
        seed: int | None = None,
    ):
        self.random = random.Random(seed)
        self.players = {1: PlayerState(1), 2: PlayerState(2)}
        self.active_player = 1 if starting_player not in (1, 2) else starting_player
        self.turn = 1
        self.winner: int | None = None
        # Compteurs bas niveau conservés pour exécuter une action Classic avec
        # les règles historiques des attaques/spéciales. La sélection du joueur
        # est désormais gérée par le plan : Action 1 immédiate à validation,
        # Action 2 réactive à la prochaine validation adverse (+ frappe gratuite de Minato).
        self.normal_attacks_used = 0
        self.special_attack_used = False
        self.log: list[str] = []
        # File d'événements purement visuels consommée par l'interface.
        # Elle ne change jamais les règles du duel : elle sert uniquement aux
        # animations (attaque, soin, bouclier, dégâts, etc.).
        self.visual_events: list[dict] = []
        self.pending_replacement: ReplacementOffer | None = None
        self._replacement_queue: list[tuple[int, int]] = []
        # Classic 1.0.0 : les cartes sorties volontairement du terrain gardent
        # leur instance (PV, boucliers, poisons, buffs, spéciale consommée...).
        # Le deck continue de contenir les définitions pour rester compatible
        # avec le reste du moteur, et ce dictionnaire conserve l'état vivant.
        self.reserve_instances: dict[int, dict[str, CardInstance]] = {1: {}, 2: {}}
        # Deuxième action d'un cycle : elle est résolue à la prochaine validation
        # adverse, juste avant les actions adverses. Une seule A2 par joueur.
        self.delayed_actions: dict[int, dict | None] = {1: None, 2: None}
        self._resolving_delayed_action: bool = False
        # Carte de réserve imposée au prochain switch/remplacement par Byakugan.
        self.forced_reserve_choice: dict[int, str | None] = {1: None, 2: None}
        # 1.7.6 — Tenten : terrain Makibishi permanent. La clé est le camp
        # dont le terrain est piégé. L’effet survit au départ / K.O. de Tenten.
        self.makibishi_active: dict[int, bool] = {1: False, 2: False}

        self._setup(deck1, deck2, starters1, starters2)
        self.log_event(f"Duel lancé : J{self.active_player} commence.")
        self.start_turn(self.active_player)

    # ------------------------------------------------------------------
    # Setup / helpers
    # ------------------------------------------------------------------
    @staticmethod
    def deck_respects_star_limit(deck: list[CardDefinition]) -> bool:
        """Valide les limites de composition 1.2.3.

        3★ : illimité ; 3,5★ : 4 ; 4★ : 3 ; 4,5★ : 2 ; 5★ : 1 ;
        total : 32,5★ maximum.

        Depuis 1.2.3, la progression des étoiles est gérée par l'ORDRE DES PICKS
        pendant le draft. La composition finale n'a donc plus besoin de contenir
        obligatoirement un exemplaire de chaque palier inférieur.
        """
        counts: dict[float, int] = {}
        for card in deck:
            stars = float(card.stars)
            counts[stars] = counts.get(stars, 0) + 1
            limit = STAR_VALUE_LIMITS.get(stars)
            if limit is not None and counts[stars] > limit:
                return False

        total = sum(float(card.stars) for card in deck)
        return total <= MAX_TOTAL_STAR_VALUE + 0.001

    def _setup(self, deck1, deck2, starters1, starters2):
        for number, deck, starters in (
            (1, list(deck1), list(starters1)),
            (2, list(deck2), list(starters2)),
        ):
            if len(starters) != 3:
                raise ValueError(f"J{number} doit choisir exactement 3 cartes de départ.")
            deck_ids = [c.id for c in deck]
            if len(set(deck_ids)) != len(deck_ids):
                raise ValueError("Le deck ne doit pas contenir deux fois le même personnage.")
            if not self.deck_respects_star_limit(deck):
                raise ValueError("Le deck ne respecte pas les limites d’étoiles (3★∞, 3,5★×4, 4★×3, 4,5★×2, 5★×1, total 32,5★ max).")
            if any(card.id not in deck_ids for card in starters):
                raise ValueError(f"Une carte de départ de J{number} n'appartient pas à son deck.")
            if len({c.id for c in starters}) != 3:
                raise ValueError("Les 3 cartes de départ doivent être différentes.")

            player = self.players[number]
            starter_ids = {c.id for c in starters}
            player.deck = [c for c in deck if c.id not in starter_ids]
            self.random.shuffle(player.deck)
            player.field = [CardInstance(card) for card in starters]

        # Les trois cartes de départ doivent recevoir immédiatement leur synergie.
        self._refresh_synergies()

    def player(self, number: int) -> PlayerState:
        return self.players[number]

    def opponent_number(self, number: int | None = None) -> int:
        n = self.active_player if number is None else number
        return 2 if n == 1 else 1

    def opponent(self, number: int | None = None) -> PlayerState:
        return self.player(self.opponent_number(number))

    # ------------------------------------------------------------------
    # Classic 1.0.0 - réserve tactique + actions programmées
    # ------------------------------------------------------------------
    def _field_card_by_id(self, player_number: int, card_id: str):
        for slot, card in enumerate(self.player(player_number).field):
            if card is not None and card.definition.id == card_id:
                return slot, card
        return None

    def reserve_instance(self, player_number: int, card_id: str) -> CardInstance | None:
        return self.reserve_instances[player_number].get(card_id)

    def preview_reserve_instance(self, player_number: int, card_id: str) -> CardInstance | None:
        saved = self.reserve_instance(player_number, card_id)
        if saved is not None:
            preview = copy.copy(saved)
            preview.has_attacked = False
            preview.minato_free_attack_used = False
            return preview
        definition = next((c for c in self.player(player_number).deck if c.id == card_id), None)
        return CardInstance(definition) if definition is not None else None

    def set_forced_reserve_choice(self, player_number: int, card_id: str | None):
        self.forced_reserve_choice[player_number] = str(card_id) if card_id else None
        if card_id:
            card = next((c for c in self.player(player_number).deck if c.id == card_id), None)
            if card is not None:
                self.log_event(f"Byakugan traqueur : {card.name} devra obligatoirement être la prochaine carte à entrer pour J{player_number}.")

    def _consume_forced_reserve_choice(self, player_number: int, incoming_id: str):
        forced = self.forced_reserve_choice.get(player_number)
        if forced and forced == incoming_id:
            self.forced_reserve_choice[player_number] = None

    def _arm_switch_counter(self, incoming: CardInstance):
        if incoming.definition.id in {"itachi", "sasuke", "kakashi"}:
            incoming.switch_counter_armed = True
            incoming.switch_counter_armed_turn = self.turn
            self.log_event(f"Contre-switch armé : {incoming.definition.name} attend la prochaine attaque adverse.")

    def _trigger_makibishi_entry(self, player_number: int, slot: int, incoming: CardInstance | None) -> bool:
        """Applique le terrain de Tenten à une VRAIE nouvelle entrée sur le terrain.

        Retourne True si le Ninja est encore vivant après les pointes. Les 7 %
        portent directement sur les PV max et traversent tous les boucliers.
        """
        if incoming is None or not self.makibishi_active.get(player_number, False):
            return incoming is not None
        # L’instance doit bien occuper ce slot au moment du déclenchement.
        if slot not in (0, 1, 2) or self.player(player_number).field[slot] is not incoming:
            return False
        amount = max(1, int(round(self.max_hp(self._effect_carrier(incoming)) * 0.07)))
        before = int(self._effect_carrier(incoming).current_hp or 0)
        hp_damage, killed, _ = self._deal_damage(
            player_number, slot, amount, attacker=None, style=None,
            is_attack=False, is_special=False, ignore_shield=True, allow_guard=False,
            label="Makibishi de Tenten",
        )
        self.log_event(
            f"Makibishi : {incoming.definition.name} entre sur le terrain et perd {hp_damage} PV "
            f"(7 % de ses PV max, {before} → {max(0, before-hp_damage)})."
        )
        self.emit_visual("poison_apply", player=player_number, slot=slot, amount=hp_damage, label="MAKIBISHI")
        return (not killed) and self.player(player_number).field[slot] is incoming and int(incoming.current_hp or 0) > 0

    def switch_card(self, player_number: int, outgoing_id: str, incoming_id: str, *, reactive: bool = False) -> tuple[bool, str]:
        """Échange libre terrain/réserve. L'instance sortante garde tous ses états."""
        if self.winner is not None:
            return False, "Le duel est terminé."
        loc = self._field_card_by_id(player_number, outgoing_id)
        if loc is None:
            return False, "Le Ninja à remplacer n'est plus sur le terrain."
        slot, outgoing = loc
        outgoing_state = self._effect_carrier(outgoing)
        if int(getattr(outgoing_state, "rooted_turns", 0) or 0) > 0:
            return False, f"{outgoing.definition.name} est ENRACINÉ et ne peut pas effectuer de Switch ({outgoing_state.rooted_turns}T)."
        yamato_relay = bool(reactive and outgoing.definition.id == "yamato")
        player = self.player(player_number)
        incoming_def = next((c for c in player.deck if c.id == incoming_id), None)
        if incoming_def is None:
            return False, "La carte choisie n'est plus dans la réserve."
        if incoming_id == outgoing_id:
            return False, "Cette carte est déjà sur le terrain."
        forced = self.forced_reserve_choice.get(player_number)
        if forced and any(c.id == forced for c in player.deck) and incoming_id != forced:
            forced_def = next((c for c in player.deck if c.id == forced), None)
            if forced_def is not None:
                self.log_event(f"Byakugan : {forced_def.name} remplace le choix initial et doit entrer lors de ce switch.")
                incoming_id = forced
                incoming_def = forced_def

        player.deck.remove(incoming_def)
        incoming = self.reserve_instances[player_number].pop(incoming_id, None)
        if incoming is None:
            incoming = CardInstance(incoming_def)
        # Une carte qui revient sur le terrain démarre disponible pour le cycle
        # courant ; ses états persistants restent intacts.
        incoming.has_attacked = False
        incoming.minato_free_attack_used = False
        if incoming.definition.id == "haku":
            incoming.haku_entry_guard = True

        # Les liens qui exigent la présence du Ninja sur le terrain cessent
        # lorsqu'il part en réserve (Prison aqueuse, Jashin, Transfert d'Ino...).
        # Ses PV/buffs/debuffs personnels restent en revanche sur l'instance.
        self._cleanup_links_to(outgoing)
        self.reserve_instances[player_number][outgoing_id] = outgoing
        player.deck.append(outgoing.definition)
        player.field[slot] = incoming
        self._refresh_synergies()
        self._consume_forced_reserve_choice(player_number, incoming_id)
        # Toute entrée par Switch marche sur les Makibishi, y compris l’A2 réactive.
        self._trigger_makibishi_entry(player_number, slot, incoming)
        # Zetsu punit uniquement le Switch immédiat A1 : le Ninja entrant est STUN 2 tours.
        if not reactive:
            enemy_zetsu = next((c for c in self.opponent(player_number).field if c is not None and c.definition.id == "zetsu" and int(c.current_hp or 0) > 0), None)
            if enemy_zetsu is not None and int(incoming.current_hp or 0) > 0:
                incoming.disabled_turns = max(int(incoming.disabled_turns or 0), 2)
                self.log_event(f"Espion souterrain : {incoming.definition.name} entre par Switch A1 et est STUN 2 tours.")
                self.emit_visual("stun_apply", player=player_number, slot=slot, label="ZETSU 2T")
        incoming.reactive_switch_turn = self.turn if reactive else -1
        if reactive:
            self._arm_switch_counter(incoming)
            if yamato_relay:
                incoming.switch_counter_armed = True
                incoming.switch_counter_armed_turn = self.turn
                incoming.yamato_counter_gift = True
                self.log_event(f"Relais protecteur : Yamato transmet Counter-Switch à {incoming.definition.name} pour la première attaque de cette résolution.")
            self.log_event(f"Échange réactif : {outgoing.definition.name} sort au moment de la validation adverse, {incoming.definition.name} entre avant les actions.")
        else:
            incoming.switch_counter_armed = False
            incoming.switch_counter_armed_turn = -1
            incoming.yamato_counter_gift = False
        self.log_event(f"Échange tactique : {outgoing.definition.name} rejoint la réserve, {incoming.definition.name} entre sur le terrain.")
        self.emit_visual("switch", player=player_number, slot=slot, outgoing_id=outgoing_id, incoming_id=incoming_id)
        return True, f"{outgoing.definition.name} ↔ {incoming.definition.name}."

    def set_delayed_action(self, player_number: int, action: dict | None):
        self.delayed_actions[player_number] = dict(action) if action else None
        if action:
            self.log_event(f"Action 2 réactive programmée pour la prochaine validation adverse : {self.action_description(action)}")
            if str(action.get("kind") or "") == "switch":
                observer = self.opponent_number(player_number)
                z = next((c for c in self.player(observer).field if c is not None and c.definition.id == "zetsu" and int(c.current_hp or 0) > 0), None)
                if z is not None:
                    out_id, in_id = str(action.get("outgoing_id") or ""), str(action.get("incoming_id") or "")
                    out_def = next((c.definition for c in self.player(player_number).field if c is not None and c.definition.id == out_id), None)
                    in_def = next((c for c in self.player(player_number).deck if c.id == in_id), None)
                    self.log_event(f"ESPION ZETSU — Switch A2 révélé : {(out_def.name if out_def else out_id)} → {(in_def.name if in_def else in_id)}.")

    def action_description(self, action: dict | None) -> str:
        if not action:
            return "Aucune"
        kind = action.get("kind")
        if kind == "normal":
            style = STYLE_LABELS.get(str(action.get("style") or ""), str(action.get("style") or "attaque"))
            return f"{action.get('actor_name') or action.get('actor_id')} — {style}"
        if kind == "special":
            return f"{action.get('actor_name') or action.get('actor_id')} — {action.get('special_name') or 'Technique spéciale'}"
        if kind == "grave_special":
            return f"{action.get('actor_name') or action.get('actor_id')} — Réincarnation des âmes"
        if kind == "switch":
            return f"Échange {action.get('outgoing_name') or action.get('outgoing_id')} → {action.get('incoming_name') or action.get('incoming_id')}"
        return str(kind or "Action")

    def _action_target_slot(self, player_number: int, action: dict, *, ally: bool = False) -> int | None:
        target_id = action.get("target_id")
        if target_id is None:
            return None
        target_player = player_number if ally else self.opponent_number(player_number)
        loc = self._field_card_by_id(target_player, str(target_id))
        if loc is not None:
            return int(loc[0])
        # 1.6.9 — un switch A2 réactif remplace la carte DANS SA CASE juste
        # avant les actions adverses. Une action déjà validée contre l'ancienne
        # carte suit donc cette case et frappe le Ninja qui vient d'entrer.
        slot = action.get("target_slot")
        try:
            slot = int(slot)
        except (TypeError, ValueError):
            return None
        field = self.player(target_player).field
        if 0 <= slot < len(field):
            current = field[slot]
            if current is not None and int(getattr(current, "reactive_switch_turn", -1)) == int(self.turn):
                return slot
        return None

    def resolve_reactive_a2_before_actions(self, acting_player: int):
        """Résout l'Action 2 adverse à la validation du tour courant.

        Règle 1.7.0 : TOUTE A2 (attaque normale, spéciale ou switch) est une
        réaction différée. Elle part lorsque l'adversaire finalise son prochain
        tour, juste avant Hiraishin/Action 1 de cet adversaire. L'ordre est
        consommé même s'il est devenu illégal entre-temps.
        """
        owner = self.opponent_number(acting_player)
        action = self.delayed_actions.get(owner)
        if not action or self.winner is not None:
            return False
        self.delayed_actions[owner] = None
        desc = self.action_description(action)
        self.log_event(f"A2 réactive de J{owner} déclenchée avant les actions de J{acting_player} : {desc}")
        kind = str(action.get("kind") or "")
        if kind == "switch":
            ok, msg = self.switch_card(
                owner,
                str(action.get("outgoing_id") or ""),
                str(action.get("incoming_id") or ""),
                reactive=True,
            )
        else:
            self._resolving_delayed_action = True
            try:
                ok, msg = self.execute_action_descriptor(owner, action, preserve_turn_budget=True)
            finally:
                self._resolving_delayed_action = False
        if not ok:
            self.log_event(msg or "L'A2 réactive est perdue.")
        return bool(ok)

    # Alias temporaire pour compatibilité avec d'anciens appels internes.
    def resolve_reactive_switch_before_actions(self, acting_player: int):
        return self.resolve_reactive_a2_before_actions(acting_player)

    def execute_action_descriptor(self, player_number: int, action: dict | None, *, preserve_turn_budget: bool = False) -> tuple[bool, str]:
        """Exécute une action planifiée à partir d'identités de cartes stables.

        preserve_turn_budget=True est utilisé pour l'action héritée du tour
        précédent : elle se produit maintenant, mais ne consomme PAS les
        nouvelles actions que le joueur va pouvoir planifier.
        """
        if not action:
            return False, "Aucune action."
        action = dict(action)
        kind = str(action.get("kind") or "")
        old_normals = self.normal_attacks_used
        old_special_turn = self.special_attack_used
        actor_before = None
        old_has_attacked = None
        old_minato_free = None

        actor_id = str(action.get("actor_id") or "")
        if actor_id:
            loc = self._field_card_by_id(player_number, actor_id)
            if loc is not None:
                actor_before = loc[1]
                old_has_attacked = bool(actor_before.has_attacked)
                old_minato_free = bool(actor_before.minato_free_attack_used)

        try:
            if kind == "switch":
                return self.switch_card(
                    player_number,
                    str(action.get("outgoing_id") or ""),
                    str(action.get("incoming_id") or ""),
                )

            loc = self._field_card_by_id(player_number, actor_id)
            if loc is None:
                return False, "Action perdue : le Ninja qui devait agir n'est plus sur le terrain."
            attacker_slot, attacker = loc

            if kind == "normal":
                target_id = action.get("target_id")
                # Depuis Classic 1.1.3, la case Hiraishin est un vrai choix du
                # joueur. Les nouveaux descripteurs portent donc minato_free=True
                # uniquement pour cette case, False pour Action 1/2. L'absence de
                # la clé reste tolérée pour les paquets 1.1.2 déjà en circulation.
                minato_override = action.get("minato_free") if "minato_free" in action else None
                if target_id is None:
                    if any(c is not None for c in self.opponent(player_number).field):
                        return False, "Action perdue : une attaque directe n'est plus possible."
                    ok, msg = self.attack(
                        player_number, attacker_slot, str(action.get("style") or ""), None,
                        minato_free_override=minato_override,
                    )
                else:
                    target_slot = self._action_target_slot(player_number, action, ally=False)
                    if target_slot is None:
                        return False, "Action perdue : la cible n'est plus sur le terrain."
                    ok, msg = self.attack(
                        player_number, attacker_slot, str(action.get("style") or ""), target_slot,
                        minato_free_override=minato_override,
                    )
                if ok:
                    self.emit_visual("planned_normal_audio")
                return ok, msg

            if kind == "grave_special":
                grave_card_id = str(action.get("grave_card_id") or "")
                enemy = self.opponent(player_number)
                grave_index = next((i for i, c in enumerate(enemy.graveyard) if c.id == grave_card_id), -1)
                if grave_index < 0:
                    return False, "Action perdue : la carte choisie n'est plus dans le cimetière."
                ok, msg = self.steal_from_enemy_graveyard(
                    player_number, attacker_slot, grave_index, copied=bool(action.get("copied", False))
                )
                if ok:
                    self.emit_visual("planned_special_audio", card_id="orochimaru")
                return ok, msg

            if kind == "special":
                copied = bool(action.get("copied", False))
                special_id = attacker.copied_special_id if copied else attacker.definition.id
                ally_target = self.special_targets_ally_id(special_id)
                target_id = action.get("target_id")
                if target_id is not None:
                    target_slot = self._action_target_slot(player_number, action, ally=ally_target)
                    if target_slot is None:
                        return False, "Action perdue : la cible de la technique n'est plus sur le terrain."
                else:
                    target_slot = None
                ok, msg = self.use_special(player_number, attacker_slot, target_slot, copied=copied)
                if ok:
                    tracker_id = action.get("tracker_id")
                    # Les trois techniques Byakugan traqueuses doivent toujours verrouiller
                    # une carte de réserve. Le joueur transmet son choix dans le descripteur ;
                    # l'IA / les appels moteur sans UI choisissent automatiquement la carte
                    # adverse la plus précieuse encore en réserve.
                    if special_id in {"ao", "neji", "hinata"}:
                        enemy_deck = self.opponent(player_number).deck
                        if tracker_id and any(c.id == str(tracker_id) for c in enemy_deck):
                            self.set_forced_reserve_choice(self.opponent_number(player_number), str(tracker_id))
                        elif enemy_deck:
                            best = max(
                                enemy_deck,
                                key=lambda c: (
                                    float(c.stars),
                                    int(c.max_hp) + int(c.taijutsu) + int(c.ninjutsu) + int(c.genjutsu),
                                    c.name,
                                ),
                            )
                            self.set_forced_reserve_choice(self.opponent_number(player_number), best.id)
                            self.log_event(f"Byakugan traqueur : {best.name} est désigné automatiquement.")
                    self.emit_visual("planned_special_audio", card_id=special_id)
                return ok, msg

            return False, "Type d'action inconnu."
        finally:
            if preserve_turn_budget:
                self.normal_attacks_used = old_normals
                self.special_attack_used = old_special_turn
                # Le compteur d'action du nouveau tour ne doit pas être consommé
                # par l'ordre hérité. Les effets réels de l'attaque restent eux.
                if actor_before is not None and self._is_alive_instance(actor_before):
                    if old_has_attacked is not None:
                        actor_before.has_attacked = old_has_attacked
                    if old_minato_free is not None:
                        actor_before.minato_free_attack_used = old_minato_free

    def _resolve_delayed_action(self, player_number: int):
        action = self.delayed_actions.get(player_number)
        if not action or self.winner is not None:
            return
        # On retire d'abord l'ordre : même s'il échoue, il est consommé.
        self.delayed_actions[player_number] = None
        desc = self.action_description(action)
        self.log_event(f"Action programmée déclenchée : {desc}")
        self._resolving_delayed_action = True
        try:
            ok, msg = self.execute_action_descriptor(player_number, action, preserve_turn_budget=True)
        finally:
            self._resolving_delayed_action = False
        if not ok:
            self.log_event(msg or "L'action programmée est perdue.")

    def _resolve_scheduled_switch_on_death(self, player_number: int, slot: int, dead: CardInstance) -> bool:
        action = self.delayed_actions.get(player_number)
        if not action or action.get("kind") != "switch":
            return False
        if str(action.get("outgoing_id") or "") != dead.definition.id:
            return False
        incoming_id = str(action.get("incoming_id") or "")
        player = self.player(player_number)
        forced = self.forced_reserve_choice.get(player_number)
        if forced and any(c.id == forced for c in player.deck):
            incoming_id = forced
            self.log_event("Byakugan : le remplacement d'urgence est redirigé vers la carte traquée.")
        incoming_def = next((c for c in player.deck if c.id == incoming_id), None)
        if incoming_def is None:
            self.delayed_actions[player_number] = None
            self.log_event("L'échange programmé est annulé : la carte de réserve n'est plus disponible.")
            return False
        player.deck.remove(incoming_def)
        incoming = self.reserve_instances[player_number].pop(incoming_id, None) or CardInstance(incoming_def)
        incoming.has_attacked = False
        incoming.minato_free_attack_used = False
        if incoming.definition.id == "haku":
            incoming.haku_entry_guard = True
        player.field[slot] = incoming
        self._refresh_synergies()
        self._consume_forced_reserve_choice(player_number, incoming_id)
        self.delayed_actions[player_number] = None
        # Un échange A2 qui entre en urgence à la mort du sortant est aussi une arrivée.
        self._trigger_makibishi_entry(player_number, slot, incoming)
        self.emit_visual("switch", player=player_number, slot=slot, outgoing_id=dead.definition.id, incoming_id=incoming_id)
        self.log_event(
            f"Échange programmé d'urgence : {dead.definition.name} tombe, {incoming.definition.name} entre immédiatement à sa place."
        )
        return True

    def log_event(self, text: str):
        self.log.append(text)
        self.log = self.log[-18:]

    def emit_visual(self, event_type: str, **payload):
        event = {"type": event_type}
        event.update(payload)
        self.visual_events.append(event)
        # Évite qu'une longue partie accumule des événements si une ancienne UI
        # ne les consomme pas immédiatement.
        self.visual_events = self.visual_events[-80:]

    def drain_visual_events(self) -> list[dict]:
        events = list(self.visual_events)
        self.visual_events.clear()
        return events

    def _find_instance(self, needle: CardInstance) -> tuple[int, int] | None:
        for pnum, player in self.players.items():
            for slot, card in enumerate(player.field):
                if card is needle:
                    return pnum, slot
        return None

    def _is_alive_instance(self, instance: CardInstance | None) -> bool:
        return instance is not None and self._find_instance(instance) is not None and int(instance.current_hp or 0) > 0

    def _effect_carrier(self, card: CardInstance) -> CardInstance:
        """Retourne le corps qui doit réellement conserver les effets.

        Pendant le Transfert de l'esprit, Ino reste la carte qui joue dans son
        slot, mais le corps ennemi contrôlé porte réellement les PV, boucliers,
        poisons, STUN, buffs/debuffs et blocages reçus pendant la possession.
        Quand le Transfert se termine, aucun recopiage n'est nécessaire : le
        CardInstance original possède déjà son état exact.
        """
        if card.definition.id == "ino" and self._is_alive_instance(card.ino_possession_target):
            return card.ino_possession_target
        return card

    def _combat_definition(self, card: CardInstance) -> CardDefinition:
        """Définition utilisée pour l'élément/identité de combat.

        Pendant un Transfert de l'esprit réussi, Ino combat avec le corps
        possédé : elle récupère donc aussi son élément pour les avantages.
        """
        if card.definition.id == "ino" and self._is_alive_instance(card.ino_possession_target):
            return card.ino_possession_target.definition
        return card.definition

    def _synergy_pct_for_field_card(self, player_number: int, card: CardInstance) -> float:
        """Meilleur bonus de synergie de cette carte avec les Ninjas vivants du terrain."""
        field_cards = [
            c for c in self.player(player_number).field
            if c is not None and int(c.current_hp or 0) > 0
        ]
        if card not in field_cards:
            return 0.0
        ids = {c.definition.id for c in field_cards}
        cid = card.definition.id

        # 1.7.6 — Zetsu possède une synergie S 2/2 (+15 %) avec n’importe quel membre de l’Akatsuki.
        akatsuki = {"deidara", "sasori", "itachi", "kisame", "hidan", "kakuzu", "madara", "konan", "nagato", "tobi"}
        if cid == "zetsu" and any(c.definition.id in akatsuki for c in field_cards if c is not card):
            return 0.15
        if cid in akatsuki and any(c.definition.id == "zetsu" for c in field_cards if c is not card):
            return 0.15

        # Trio complet : les 3 cartes vivantes appartiennent toutes à la même famille.
        if len(field_cards) == 3 and any(ids.issubset(family) for family in SYNERGY_FAMILIES):
            return 0.20

        best = 0.0
        # Famille incomplète : au moins un autre membre lié à cette carte.
        for other in field_cards:
            if other is card:
                continue
            pair = {cid, other.definition.id}
            if any(pair.issubset(family) for family in SYNERGY_FAMILIES):
                best = max(best, 0.125)
            if any(pair == set(duo) for duo in SYNERGY_DUOS):
                best = max(best, 0.15)
        return best

    @staticmethod
    def _family_linked(card_a: str, card_b: str) -> bool:
        return any(card_a in family and card_b in family for family in SYNERGY_FAMILIES)

    def _trigger_karui_electric(self, player_number: int, dead_card: CardInstance):
        """Comportement électrique : mort définitive d'un autre membre de sa famille."""
        dead_id = dead_card.definition.id
        for karui in list(self.player(player_number).field):
            if karui is None or karui is dead_card or karui.definition.id != "karui" or not self._is_alive_instance(karui):
                continue
            if not self._family_linked("karui", dead_id):
                continue
            was_active = int(karui.karui_electric_turns or 0) > 0
            if not was_active:
                old_max = self.max_hp(karui)
                karui.karui_electric_turns = 2
                karui.karui_electric_started_turn = self.turn
                new_max = self.max_hp(karui)
                karui.current_hp = min(new_max, int(karui.current_hp or 0) + max(0, new_max - old_max))
            else:
                karui.karui_electric_turns = 2
                karui.karui_electric_started_turn = self.turn
            self.log_event(f"Comportement électrique : {dead_card.definition.name} tombe — Karui gagne +300 dans toutes ses stats pendant 2 tours.")
            loc = self._find_instance(karui)
            if loc:
                self.emit_visual("passive_audio", card_id="karui")

    @staticmethod
    def _synergy_label(pct: float) -> str:
        if pct >= 0.199:
            return "+20 %"
        if pct >= 0.149:
            return "+15 %"
        if pct >= 0.124:
            return "+12,5 %"
        return ""

    def _max_hp_for_pct(self, card: CardInstance, pct: float) -> int:
        # Opère sur l'instance elle-même. max_hp() choisit ensuite le corps
        # réellement utilisé par Ino pendant le Transfert.
        if getattr(card, "gengetsu_clone_active", False):
            return 4800
        base = int(card.definition.max_hp) + int(getattr(card, "max_hp_bonus", 0) or 0)
        if card.definition.id == "karui" and int(getattr(card, "karui_electric_turns", 0) or 0) > 0:
            base += 300
        # La synergie est calculée uniquement depuis les PV DE BASE de la carte.
        bonus = int(round(int(card.definition.max_hp) * max(0.0, float(pct))))
        return max(1, base + bonus)

    def _set_synergy_pct(self, card: CardInstance, pct: float):
        """Change le bonus sans créer de soin artificiel : même % de PV avant/après."""
        pct = max(0.0, float(pct))
        old_pct = float(getattr(card, "synergy_bonus_pct", 0.0) or 0.0)
        if abs(old_pct - pct) < 1e-9:
            return
        old_max = self._max_hp_for_pct(card, old_pct)
        new_max = self._max_hp_for_pct(card, pct)
        hp = int(card.current_hp or 0)
        card.synergy_bonus_pct = pct
        if hp <= 0:
            card.current_hp = hp
            return
        ratio = hp / max(1, old_max)
        card.current_hp = max(1, min(new_max, int(round(ratio * new_max))))

    def _refresh_synergies(self):
        """Recalcule toutes les synergies après entrée/sortie/mort/remplacement."""
        for pnum, player in self.players.items():
            desired = {id(c): self._synergy_pct_for_field_card(pnum, c) for c in player.field if c is not None}
            # Les Ninjas de réserve perdent immédiatement leur synergie en gardant leur % de PV.
            for c in self.reserve_instances.get(pnum, {}).values():
                if c is not None:
                    self._set_synergy_pct(c, 0.0)
            for c in player.field:
                if c is not None:
                    self._set_synergy_pct(c, desired.get(id(c), 0.0))

    def max_hp(self, card: CardInstance) -> int:
        body = self._effect_carrier(card)
        if getattr(body, "gengetsu_clone_active", False):
            return 4800
        return self._max_hp_for_pct(body, float(getattr(body, "synergy_bonus_pct", 0.0) or 0.0))

    def _percent_hp_amount(self, card: CardInstance, percent: float) -> int:
        body = self._effect_carrier(card)
        return max(1, int(round(self.max_hp(body) * float(percent))))

    def _shadow_stun_turns(self, card: CardInstance) -> int:
        """Durée restante du STUN de Shikamaru/Kakashi copieur sur ce corps."""
        body = self._effect_carrier(card)
        active: list[dict] = []
        for entry in list(getattr(body, "shadow_stuns", []) or []):
            try:
                turns = max(0, int(entry.get("turns", 0)))
                source = entry.get("source")
            except Exception:
                continue
            if turns > 0 and source is not None:
                active.append({"source": source, "turns": turns})
        body.shadow_stuns = active
        return max((int(e["turns"]) for e in active), default=0)

    def _apply_shadow_stun(self, card: CardInstance, source: CardInstance, turns: int = 3):
        body = self._effect_carrier(card)
        if body.definition.id in {"killer_bee", "madara"}:
            return
        remaining = max(1, int(turns))
        entries = list(getattr(body, "shadow_stuns", []) or [])
        for entry in entries:
            if entry.get("source") is source:
                entry["turns"] = max(int(entry.get("turns", 0)), remaining)
                body.shadow_stuns = entries
                return
        entries.append({"source": source, "turns": remaining})
        body.shadow_stuns = entries

    def _remove_shadow_stuns_from_source(self, source: CardInstance):
        """Mort du lanceur => ses Possessions des ombres cessent immédiatement."""
        removed_names: list[str] = []
        seen: set[int] = set()
        candidates: list[CardInstance] = []
        for player in self.players.values():
            candidates.extend(card for card in player.field if card is not None)
        for store in self.reserve_instances.values():
            candidates.extend(card for card in store.values() if card is not None)
        for card in candidates:
            body = self._effect_carrier(card)
            if id(body) in seen:
                continue
            seen.add(id(body))
            before = list(getattr(body, "shadow_stuns", []) or [])
            after = [entry for entry in before if entry.get("source") is not source]
            if len(after) != len(before):
                body.shadow_stuns = after
                removed_names.append(body.definition.name)
        if removed_names:
            self.log_event(
                "Possession des ombres interrompue : le lien est rompu et libère "
                + ", ".join(removed_names) + "."
            )

    def _is_untargetable(self, card: CardInstance) -> bool:
        """Vrai quand une carte ne peut pas être choisie comme cible directe."""
        if card.definition.id == "obito" and card.obito_intangible:
            return True
        if card.definition.id == "zetsu" and bool(getattr(card, "zetsu_hidden", False)):
            return True
        if card.definition.id == "zabuza" and card.zabuza_untargetable:
            return True
        if card.definition.id == "gengetsu" and card.gengetsu_untargetable and not card.gengetsu_clone_active:
            return True
        if card.definition.id == "konan" and card.konan_untargetable:
            return True
        if card.definition.id == "asuma" and card.asuma_smoke_turns > 0:
            return True
        if card.definition.id == "ino" and self._is_alive_instance(card.ino_possession_target):
            return True
        if card.ino_possessed_by is not None and self._is_alive_instance(card.ino_possessed_by):
            return True
        return False

    def _elemental_fixed_amount(self, base_amount: int, element: str, defender: CardInstance) -> tuple[int, bool]:
        """Dégâts fixes auxquels l'avantage élémentaire normal peut s'ajouter."""
        defender_def = self._combat_definition(defender)
        # Kakuzu possède tous les éléments : aucune faiblesse élémentaire.
        advantage = defender_def.id != "kakuzu" and ELEMENT_BEATS.get(element) == defender_def.element
        amount = max(0, int(base_amount))
        if advantage:
            amount = int(round(amount * 1.10)) + 150
        return amount, advantage

    def _end_ino_possession(self, ino: CardInstance, *, reason: str = ""):
        target = ino.ino_possession_target
        if target is not None and target.ino_possessed_by is ino:
            target.ino_possessed_by = None
        ino.ino_possession_target = None
        ino.ino_possession_turns_left = 0
        ino.ino_possession_started_turn = -1
        if reason:
            self.log_event(reason)

    def _heal(self, card: CardInstance, amount: int) -> int:
        body = self._effect_carrier(card)
        if amount <= 0 or not self._is_alive_instance(body):
            return 0
        before = int(body.current_hp or 0)
        max_hp = self.max_hp(body)
        body.current_hp = min(max_hp, before + amount)
        healed = int(body.current_hp) - before
        if healed > 0:
            # Visuellement l'effet reste sur le slot d'Ino pendant le contrôle.
            loc = self._find_instance(card) or self._find_instance(body)
            if loc:
                self.emit_visual("heal", player=loc[0], slot=loc[1], amount=healed)
        return healed

    def _add_shield(self, card: CardInstance, amount: int):
        body = self._effect_carrier(card)
        if amount > 0 and self._is_alive_instance(body):
            body.shield += amount
            loc = self._find_instance(card) or self._find_instance(body)
            if loc:
                self.emit_visual("shield", player=loc[0], slot=loc[1], amount=amount)

    def _cleanse_negative_effects(self, card: CardInstance) -> list[str]:
        body = self._effect_carrier(card)
        removed: list[str] = []
        if body.disabled_turns > 0:
            body.disabled_turns = 0
            removed.append("stun")
        if getattr(body, "shadow_stuns", None):
            body.shadow_stuns.clear()
            if "stun" not in removed:
                removed.append("stun")
        if body.blocked_styles:
            body.blocked_styles.clear()
            removed.append("arts bloqués")
        if body.special_block_turns > 0:
            body.special_block_turns = 0
            removed.append("spéciale bloquée")
        neg_mods = [m for m in body.timed_modifiers if m.amount < 0]
        if neg_mods:
            body.timed_modifiers = [m for m in body.timed_modifiers if m.amount >= 0]
            removed.append("malus temporaires")
        if body.haku_ice_prison_turns > 0:
            body.haku_ice_prison_turns = 0
            removed.append("prison de glace")
        if body.prisoned_by is not None:
            body.prisoned_by = None
            removed.append("prison aqueuse")
        if body.delayed_damage > 0:
            body.delayed_damage = 0
            removed.append("dégâts retardés")
        if body.shino_poisoned:
            body.shino_poisoned = False
            removed.append("poison Shino")
        if body.hanzo_poisoned:
            body.hanzo_poisoned = False
            removed.append("poison salamandre")
        if body.shizune_poisoned:
            body.shizune_poisoned = False
            removed.append("poison de Shizune")
        if body.shizune_paralysis_turns > 0:
            body.shizune_paralysis_turns = 0
            removed.append("poison paralysant")
        if body.sealed_turns > 0:
            body.sealed_turns = 0
            removed.append("scellement")
        return removed

    def _restore_from_gengetsu_clone(self, card: CardInstance, *, reason: str = ""):
        """Rend la forme originale après destruction/expiration du clone explosif."""
        saved_hp = card.gengetsu_saved_hp
        if saved_hp is None:
            saved_hp = card.definition.max_hp
        card.gengetsu_clone_active = False
        card.gengetsu_clone_turns_left = 0
        card.current_hp = max(1, min(card.definition.max_hp, int(saved_hp)))
        card.shield = max(0, int(card.gengetsu_saved_shield))
        card.gengetsu_saved_hp = None
        card.gengetsu_saved_shield = 0
        if card.definition.id == "gengetsu":
            card.gengetsu_special_cooldown = 4
        if reason:
            self.log_event(reason)
        if card.definition.id == "gengetsu":
            self.log_event("Clone aqueux explosif : technique en recharge pendant 4 tours.")

    def _tick_gengetsu_clone(self, player_number: int, slot: int, card: CardInstance):
        if not card.gengetsu_clone_active:
            return
        card.gengetsu_clone_turns_left = max(0, int(card.gengetsu_clone_turns_left) - 1)
        if card.gengetsu_clone_turns_left > 0:
            # Le clone évolue à chacun des tours de Gengetsu : rejouer l'une
            # des prises de sa spéciale à chaque mise à jour du compte à rebours.
            self.emit_visual("special_audio", card_id="gengetsu")
            self.log_event(
                f"Clone aqueux explosif : {card.gengetsu_clone_turns_left} tour(s) avant l'explosion."
            )
            return

        enemy = self.opponent(player_number)
        self._restore_from_gengetsu_clone(
            card,
            reason="Clone aqueux explosif : le compte à rebours atteint zéro, Gengetsu reprend sa forme originale.",
        )
        total = 0
        self.emit_visual("special_audio", card_id="gengetsu", variant="explosion")
        self.log_event("EXPLOSION DU CLONE : 1300 PV fixes à toutes les cartes ennemies !")
        for enemy_slot, target in list(enumerate(enemy.field)):
            if target is not None:
                dealt, _ = self._deal_fixed_damage(
                    enemy.number,
                    enemy_slot,
                    1300,
                    source=card,
                    label="Explosion du clone aqueux",
                    allow_guard=False,
                )
                total += dealt
        self.log_event(f"Explosion terminée : {total} PV infligés au total.")

    def effective_stat(self, card: CardInstance, style: str, defender: CardInstance | None = None) -> int:
        # Transfert de l'esprit : pendant la possession, Ino utilise les
        # statistiques ACTUELLES du corps qu'elle contrôle (buffs/debuffs inclus).
        if card.definition.id == "ino" and self._is_alive_instance(card.ino_possession_target):
            return self.effective_stat(card.ino_possession_target, style, defender)

        # Clone aqueux explosif de Gengetsu : le clone n'a aucun art de combat.
        if getattr(card, "gengetsu_clone_active", False):
            return 0
        value = card.definition.stat(style)
        # Synergie : bonus calculé uniquement sur la statistique de BASE, sans
        # multiplier les buffs permanents/temporaires ni les transformations.
        synergy_pct = float(getattr(card, "synergy_bonus_pct", 0.0) or 0.0)
        if synergy_pct > 0:
            value += int(round(card.definition.stat(style) * synergy_pct))
        value += card.permanent_buffs.get(style, 0)
        value += sum(mod.amount for mod in card.timed_modifiers if mod.style == style)

        cid = card.definition.id
        hp = int(card.current_hp or 0)
        if cid == "naruto" and hp * 2 < self.max_hp(card) and style in ("taijutsu", "ninjutsu"):
            value += 350
        if cid == "choji" and style == "taijutsu" and card.choji_pill_turns > 0:
            value += 500
        if cid == "shikamaru" and style == "genjutsu" and defender is not None and defender.definition.stars > card.definition.stars:
            value += 150
        if cid == "rock_lee" and style == "taijutsu" and card.rock_lee_tai_boosts_left > 0:
            value += 150
        if cid == "kiba" and style == "taijutsu" and card.kiba_first_tai:
            value += 150
        if cid == "sarutobi" and card.previous_attack_style is not None and style != card.previous_attack_style:
            value += 100
        if cid == "karui" and card.karui_electric_turns > 0:
            value += 300
        if cid == "anko" and card.anko_curse_used:
            value += int(round(card.definition.stat(style) * 0.10))
        if cid == "kimimaro" and card.kimimaro_fury_active:
            value = int(round(value * 1.15))
        if card.shizune_paralysis_turns > 0:
            value = int(round(value * 0.50))
        return max(0, int(value))

    def status_text(self, card: CardInstance) -> str:
        state = self._effect_carrier(card)
        status: list[str] = []
        synergy_label = self._synergy_label(float(getattr(state, "synergy_bonus_pct", 0.0) or 0.0))
        if synergy_label:
            status.append(f"Synergie {synergy_label} ALL STATS")
        if state.shield > 0:
            status.append(f"Bouclier {state.shield}")
        if self.is_disabled(card):
            if state.prisoned_by is not None and self._is_alive_instance(state.prisoned_by):
                status.append("Prison aqueuse")
            else:
                blocked_turns = max(int(state.disabled_turns), self._shadow_stun_turns(state))
                if blocked_turns > 0:
                    status.append(f"Bloqué {blocked_turns} tour(s)")
        if state.special_block_turns > 0 and state.definition.id != "killer_bee":
            status.append("Spéciale bloquée")
        if state.doom_turns > 0:
            status.append(f"Jashin {state.doom_turns}")
        if state.definition.id == "obito":
            status.append("Kamui intangible" if state.obito_intangible else "Kamui vulnérable")
        if state.definition.id == "zabuza":
            status.append("Brume : inciblable" if state.zabuza_untargetable else "Brume : ciblable")
        if state.definition.id == "shisui":
            status.append("Esquive : 1 chance sur 3")
        if state.definition.id == "haku" and state.haku_entry_guard:
            status.append("Parade programmée : 2 chances sur 3")
        if state.definition.id == "choji" and state.choji_pill_turns > 0:
            status.append(f"Pilule de combat : +500 Tai ({state.choji_pill_turns}T)")
        if state.haku_ice_prison_turns > 0:
            status.append(f"Prison de glace : {state.haku_ice_prison_turns} tour(s)")
        if state.konohamaru_sexy_turns > 0:
            status.append(f"Sexy Jutsu : {state.konohamaru_sexy_turns} tour(s)")
        progress = self.special_cooldown_progress(state)
        if progress is not None:
            done, total = progress
            status.append(f"Spéciale : T {done}/{total}")
        if getattr(state, "gengetsu_clone_active", False):
            status.append(f"Clone explosif : {max(0, state.gengetsu_clone_turns_left)} tour(s)")
        elif state.definition.id == "gengetsu":
            status.append("Palourde : inciblable" if state.gengetsu_untargetable else "Palourde : ciblable")
        if state.definition.id == "kakuzu":
            status.append(f"Cœurs restants : {max(0, state.kakuzu_revivals_left)}")
        if state.hanzo_poisoned:
            status.append("Poison salamandre")
        if state.shizune_poisoned:
            status.append("Poison mortel Shizune")
        if state.shizune_paralysis_turns > 0:
            status.append(f"Poison paralysant 50 % ({state.shizune_paralysis_turns}T)")
        if state.sealed_turns > 0:
            status.append(f"SCELLÉ {state.sealed_turns}T")
        if int(getattr(state, "rooted_turns", 0) or 0) > 0:
            status.append(f"ENRACINÉ {state.rooted_turns}T — SWITCH BLOQUÉ")
        if state.definition.id == "asuma" and state.asuma_smoke_turns > 0:
            status.append(f"Nuage de fumée {state.asuma_smoke_turns}T")
        if state.definition.id == "chojuro":
            status.append(f"Hiramekarei : {state.chojuro_chakra_stock} stock")
        if state.definition.id == "konan":
            status.append("Origami : inciblable" if state.konan_untargetable else "Origami : ciblable")
            if state.konan_mine_active and not state.konan_untargetable:
                status.append("Terrain miné")
        if state.definition.id == "jugo" and state.jugo_stage > 0:
            status.append(f"Marque maudite : stade {state.jugo_stage}")
        if state.definition.id == "rin" and state.rin_isobu_active:
            status.append("Isobu manifesté")
        if state.definition.id == "kimimaro" and state.kimimaro_fury_active:
            status.append("Furie : +15 % arts / -10 % PV par tour")
        if state.definition.id == "mu" and state.mu_division_used:
            status.append("Division utilisée • Jinton verrouillé")
        if state.definition.id == "karui" and state.karui_electric_turns > 0:
            status.append(f"Électrique : +300 ALL ({state.karui_electric_turns}T)")
        if state.definition.id == "anko" and state.anko_curse_used:
            status.append("Marque maudite : +10 % arts")
        if state.definition.id == "anko" and state.anko_serpent_armed:
            status.append("Permutation du serpent prête")
        if state.anko_poison_turns > 0:
            status.append(f"Poison d’Anko : {state.anko_poison_turns}T")
        if state.shino_poisoned:
            status.append("Poison Shino")
        if card.definition.id == "ino" and self._is_alive_instance(card.ino_possession_target):
            status.append(f"Transfert : {max(0, card.ino_possession_turns_left)} tour(s)")
        elif card.ino_possessed_by is not None and self._is_alive_instance(card.ino_possessed_by):
            status.append("Esprit transféré : inciblable")
        if state.definition.id == "naruto" and int(state.current_hp or 0) * 2 < self.max_hp(state):
            status.append("Volonté indomptable : +350 Tai/Nin")
        if state.definition.id == "jiraiya":
            if state.jiraiya_sage_active:
                status.append("Mode ermite")
            if state.jiraiya_turns_completed > 0:
                status.append(f"Sannin : +{state.jiraiya_turns_completed * 10} aux 3 arts")
        if state.definition.id == "sasuke" and state.sasuke_art_locks:
            active = [lock for lock in state.sasuke_art_locks if lock.turns_left > 0 and self._is_alive_instance(lock.source)]
            if active:
                status.append(f"Sharingan : {len(active)} verrou(x)")
        return " • ".join(status)

    def special_cooldown_progress(self, card: CardInstance) -> tuple[int, int] | None:
        """Progression visuelle T x/y des techniques réellement rechargeables."""
        cid = card.definition.id
        total = SPECIAL_COOLDOWN_TOTALS.get(cid)
        if total is None:
            return None
        if cid == "ino":
            remaining = int(card.ino_special_cooldown)
        elif cid == "karin":
            remaining = int(card.karin_special_cooldown)
        elif cid == "konohamaru":
            remaining = int(card.konohamaru_sexy_cooldown)
        elif cid == "shikamaru":
            remaining = int(card.shikamaru_special_cooldown)
        else:
            remaining = int(card.gengetsu_special_cooldown)
        if remaining <= 0:
            return None
        # Affichage demandé : la recharge commence à T 1/y juste après usage,
        # puis T 2/y, etc., jusqu'au retour à DISPONIBLE.
        return max(1, min(total, total - remaining + 1)), total

    def is_disabled(self, card: CardInstance) -> bool:
        # Le propriétaire du corps possédé ne peut pas jouer cette carte.
        if card.ino_possessed_by is not None and self._is_alive_instance(card.ino_possessed_by):
            return True

        # Ino joue avec l'état réel du corps contrôlé : un STUN / une prison
        # reçu pendant le Transfert bloque donc immédiatement son action et
        # restera présent sur la carte quand elle sera restituée.
        if card.definition.id == "ino" and self._is_alive_instance(card.ino_possession_target):
            state = card.ino_possession_target
            if state.disabled_turns > 0 or self._shadow_stun_turns(state) > 0:
                return True
            if state.prisoned_by is not None and self._is_alive_instance(state.prisoned_by):
                return True
            return False

        # Madara 1.2.2 : immunité totale aux contrôles incapacitants.
        state = self._effect_carrier(card)
        if state.definition.id == "madara":
            return False

        # Le SCELLEMENT Uzumaki est un état distinct du STUN : même Killer Bee
        # reste sous sceau pendant la durée prévue.
        if int(getattr(state, "sealed_turns", 0) or 0) > 0:
            return True
        if card.definition.id == "killer_bee":
            return False
        if card.disabled_turns > 0 or self._shadow_stun_turns(card) > 0:
            return True
        if card.prisoned_by is not None and self._is_alive_instance(card.prisoned_by):
            return True
        return False

    def _sasuke_lock_active(self, defender: CardInstance, attacker: CardInstance | None, style: str | None) -> bool:
        if defender.definition.id != "sasuke" or attacker is None or style not in STYLE_LABELS:
            return False
        defender.sasuke_art_locks = [
            lock for lock in defender.sasuke_art_locks
            if lock.turns_left > 0 and self._is_alive_instance(lock.source)
        ]
        return any(
            lock.source is attacker and lock.style == style and lock.turns_left > 0
            for lock in defender.sasuke_art_locks
        )

    def _arm_sasuke_lock(self, defender: CardInstance, attacker: CardInstance, style: str):
        if defender.definition.id != "sasuke" or style not in STYLE_LABELS or not self._is_alive_instance(defender):
            return
        for lock in defender.sasuke_art_locks:
            if lock.source is attacker and lock.style == style and lock.turns_left > 0:
                return
        defender.sasuke_art_locks.append(
            SasukeArtLock(source=attacker, style=style, turns_left=3, created_turn=self.turn)
        )
        self.log_event(
            f"Sharingan : Sasuke a mémorisé le {STYLE_LABELS[style]} de {attacker.definition.name}. "
            "Cette même carte ne pourra plus le toucher avec cet art pendant 3 de ses tours."
        )

    def _tick_sasuke_locks(self, source_player: int):
        """Décompte les 3 tours du Ninja ayant déclenché le Sharingan."""
        for state in self.players.values():
            for card in state.field:
                if card is None or card.definition.id != "sasuke":
                    continue
                kept: list[SasukeArtLock] = []
                for lock in card.sasuke_art_locks:
                    if lock.turns_left <= 0 or not self._is_alive_instance(lock.source):
                        continue
                    loc = self._find_instance(lock.source)
                    if loc and loc[0] == source_player and lock.created_turn != self.turn:
                        lock.turns_left -= 1
                    if lock.turns_left > 0:
                        kept.append(lock)
                card.sasuke_art_locks = kept

    def _strip_chidori_defenses(self, defender: CardInstance):
        """Le Chidori détruit les protections actives du corps réellement touché."""
        defender = self._effect_carrier(defender)
        removed: list[str] = []
        if defender.shield > 0:
            removed.append(f"bouclier {defender.shield}")
            defender.shield = 0
        if defender.definition.id == "obito" and defender.obito_intangible:
            defender.obito_intangible = False
            removed.append("Kamui")
        if defender.definition.id == "zabuza" and defender.zabuza_untargetable:
            defender.zabuza_untargetable = False
            removed.append("Brume")
        if defender.definition.id == "gengetsu" and defender.gengetsu_untargetable and not defender.gengetsu_clone_active:
            defender.gengetsu_untargetable = False
            removed.append("Palourde")
        if defender.definition.id == "kankuro" and defender.kankuro_defense_active:
            defender.kankuro_defense_active = False
            removed.append("Défense marionnettiste")
        if removed:
            self.log_event("Chidori détruit les protections actives : " + ", ".join(removed) + ".")

    def offensive_actions_used(self) -> int:
        return int(self.normal_attacks_used) + (1 if self.special_attack_used else 0)

    def offensive_action_slots_left(self) -> int:
        return max(0, 2 - self.offensive_actions_used())

    def can_use_style(self, card: CardInstance, style: str) -> bool:
        if style not in STYLE_LABELS:
            return False
        minato_free = card.definition.id == "minato" and not card.minato_free_attack_used
        if (self.offensive_action_slots_left() <= 0 or self.normal_attacks_used >= 2) and not minato_free:
            return False
        # Une même carte ne peut faire qu'UNE attaque normale par tour.
        # Exception : Minato dispose d'une première attaque gratuite chaque tour.
        if card.has_attacked and not minato_free:
            return False
        if self.is_disabled(card):
            return False
        state = self._effect_carrier(card)
        if state.blocked_styles.get(style, 0) > 0:
            return False
        return self.effective_stat(card, style) > 0

    def special_available(self, card: CardInstance, *, copied: bool = False) -> bool:
        if self.special_attack_used or self.offensive_action_slots_left() <= 0:
            return False
        if self.is_disabled(card):
            return False
        if card.definition.id != "killer_bee" and card.special_block_turns > 0:
            return False
        if copied:
            return bool(card.copied_special_id) and not card.copied_special_used
        if card.definition.id == "ino":
            return (
                bool(card.definition.special_name)
                and not self._is_alive_instance(card.ino_possession_target)
                and card.ino_special_cooldown <= 0
            )
        if card.definition.id == "karin":
            return bool(card.definition.special_name) and card.karin_special_cooldown <= 0
        if card.definition.id == "konohamaru":
            return bool(card.definition.special_name) and card.konohamaru_sexy_cooldown <= 0
        if card.definition.id == "shikamaru":
            return bool(card.definition.special_name) and card.shikamaru_special_cooldown <= 0
        if card.definition.id == "gengetsu":
            return (
                bool(card.definition.special_name)
                and not card.gengetsu_clone_active
                and card.gengetsu_special_cooldown <= 0
            )
        if card.definition.id == "chojuro":
            return bool(card.definition.special_name)
        if card.definition.id == "mu" and card.mu_division_used:
            return False
        return bool(card.definition.special_name) and not card.special_used

    def _special_has_valid_context(self, card: CardInstance, *, copied: bool = False) -> bool:
        """Vrai si la spéciale est réellement lançable dans l'état actuel du plateau."""
        if not self.special_available(card, copied=copied):
            return False
        special_id = card.copied_special_id if copied else card.definition.id
        if not special_id:
            return False
        enemy = self.opponent(self.active_player)
        if self.special_targets_ally_id(special_id):
            owner = self.player(self.active_player)
            return any(target is not None and target is not card for target in owner.field)
        if self.special_requires_target_id(special_id):
            return any(target is not None for target in enemy.field)
        if special_id == "orochimaru":
            return bool(enemy.graveyard)
        return True

    def normal_attack_available(self, player_number: int | None = None) -> bool:
        if self.winner is not None or self.pending_replacement is not None:
            return False
        if self.normal_attacks_used >= 2 or self.offensive_action_slots_left() <= 0:
            return False
        pnum = self.active_player if player_number is None else player_number
        if pnum != self.active_player:
            return False
        for card in self.player(pnum).field:
            if card is None:
                continue
            for style in STYLE_LABELS:
                if self.can_use_style(card, style):
                    return True
        return False

    def special_attack_available(self, player_number: int | None = None) -> bool:
        if self.winner is not None or self.pending_replacement is not None or self.special_attack_used:
            return False
        if self.offensive_action_slots_left() <= 0:
            return False
        pnum = self.active_player if player_number is None else player_number
        if pnum != self.active_player:
            return False
        for card in self.player(pnum).field:
            if card is None:
                continue
            if self._special_has_valid_context(card, copied=False):
                return True
            if self._special_has_valid_context(card, copied=True):
                return True
        return False

    def player_has_any_action(self, player_number: int | None = None) -> bool:
        pnum = self.active_player if player_number is None else player_number
        return self.normal_attack_available(pnum) or self.special_attack_available(pnum)

    @staticmethod
    def special_targets_ally_id(card_id: str) -> bool:
        return card_id in {"karin", "rock_lee", "kurenai"}

    @staticmethod
    def special_requires_target_id(card_id: str) -> bool:
        return card_id not in {"gaara", "orochimaru", "choji", "kankuro", "tobirama", "gengetsu", "shisui", "konohamaru", "chiyo", "jiraiya", "ao", "kimimaro", "kurotsuchi", "konan", "anko", "tenten"}

    def special_requires_target(self, card: CardInstance, *, copied: bool = False) -> bool:
        special_id = card.copied_special_id if copied else card.definition.id
        return bool(special_id) and self.special_requires_target_id(special_id)

    # ------------------------------------------------------------------
    # Turn processing
    # ------------------------------------------------------------------
    def _tick_global_doom(self):
        victims: list[tuple[int, int, CardInstance]] = []
        for pnum, player in self.players.items():
            for slot, card in enumerate(player.field):
                if card is None or card.doom_turns <= 0:
                    continue
                # Jashin reste lié tant que son lanceur n'est pas DEFINITIVEMENT
                # retiré du terrain. Ne jamais utiliser current_hp ici : Hidan peut
                # passer brièvement à 0 PV avant que son Immortalité, Chiyo ou
                # Kabuto ne résolve le K.O. Tant que la même instance existe encore
                # sur le terrain, le rituel doit continuer. Le nettoyage définitif
                # est effectué par _cleanup_links_to() au vrai départ au cimetière.
                if card.doom_source is None or self._find_instance(card.doom_source) is None:
                    card.doom_turns = 0
                    card.doom_source = None
                    continue
                card.doom_turns -= 1
                if card.doom_turns <= 0:
                    victims.append((pnum, slot, card))
                else:
                    self.log_event(f"Rituel de Jashin : {card.definition.name} — {card.doom_turns} tour(s) restant(s).")
        for pnum, slot, card in victims:
            if self.player(pnum).field[slot] is card:
                self.log_event(f"Le Rituel de Jashin condamne {card.definition.name} !")
                card.current_hp = 0
                self._check_ko(pnum, slot, source=card.doom_source, suppress_survival=False)

    def start_turn(self, player_number: int):
        self._refresh_synergies()
        self.active_player = player_number
        self.normal_attacks_used = 0
        self.special_attack_used = False
        self._tick_global_doom()

        player = self.player(player_number)
        enemy = self.opponent(player_number)
        # Un contre-switch ne couvre qu’une seule réponse adverse. S’il n’a pas été
        # déclenché, il expire au prochain début de tour de son propriétaire.
        for c in player.field:
            if c is not None and c.switch_counter_armed and c.switch_counter_armed_turn < self.turn:
                c.switch_counter_armed = False

        # Effets retardés au début du tour du propriétaire de la carte.
        for slot, card in list(enumerate(player.field)):
            if card is None:
                continue
            # Torune : les deux toxines sont indépendantes et se cumulent.
            torune_tick = int(getattr(card, "torune_contact_poison", 0) or 0) + int(getattr(card, "torune_micro_poison", 0) or 0)
            if torune_tick > 0 and int(card.current_hp or 0) > 0:
                self.log_event(f"Toxines de Torune : {card.definition.name} perd {torune_tick} PV.")
                self._deal_fixed_damage(player_number, slot, torune_tick, source=None, label="Toxines de Torune", allow_guard=False)
                if self.player(player_number).field[slot] is not card:
                    continue
            card.has_attacked = False
            card.tenten_tai_used_this_turn = False
            if card.definition.id == "zetsu":
                card.zetsu_hidden = not bool(getattr(card, "zetsu_hidden", False))
                self.log_event(f"Espion souterrain : Zetsu est maintenant {'INCIBLABLE' if card.zetsu_hidden else 'CIBLABLE'}.")
            if card.definition.id == "minato":
                card.minato_free_attack_used = False
            if card.ino_possessed_by is not None and self._is_alive_instance(card.ino_possessed_by):
                continue
            effect_card = self._effect_carrier(card)
            if effect_card.delayed_damage > 0:
                amount = effect_card.delayed_damage
                effect_card.delayed_damage = 0
                self.log_event(f"{effect_card.definition.name} subit {amount} dégâts retardés.")
                self._deal_fixed_damage(player_number, slot, amount, source=None, label="effet retardé", allow_guard=False)

        # Poison de la Permutation du serpent : 100 PV au début de chacun des
        # 4 prochains tours du Ninja empoisonné.
        for slot, card in list(enumerate(player.field)):
            if card is None or self.player(player_number).field[slot] is not card:
                continue
            body = self._effect_carrier(card)
            if body.anko_poison_turns > 0 and int(body.current_hp or 0) > 0:
                body.anko_poison_turns -= 1
                self.log_event(f"Poison d’Anko : {body.definition.name} perd 100 PV ({body.anko_poison_turns}T après ce tic).")
                self.emit_visual("poison_burst", player=player_number, slot=slot, amount=100)
                self._deal_fixed_damage(player_number, slot, 100, source=None, label="Poison d’Anko", allow_guard=False)

        # Poison persistant de Shino : 100 PV fixes au début de chacun des
        # tours du propriétaire de la cible, jusqu'à ce que cette instance meure.
        # Le poison ne se transfère jamais à la carte de remplacement.
        for slot, card in list(enumerate(player.field)):
            if card is None or self.player(player_number).field[slot] is not card:
                continue
            if card.ino_possessed_by is not None and self._is_alive_instance(card.ino_possessed_by):
                continue
            effect_card = self._effect_carrier(card)
            if getattr(effect_card, "shino_poisoned", False) and int(effect_card.current_hp or 0) > 0:
                self.log_event(f"Poison de Shino : {effect_card.definition.name} perd 100 PV.")
                self.emit_visual("poison_burst", player=player_number, slot=slot, amount=100)
                self._deal_fixed_damage(
                    player_number,
                    slot,
                    100,
                    source=None,
                    label="Poison de Shino",
                    allow_guard=False,
                )

        # Poison de la salamandre de Hanzo : -5 % des PV max au début de
        # chaque tour de la cible, jusqu'à sa mort. Il se cumule avec la brume.
        for slot, card in list(enumerate(player.field)):
            if card is None or self.player(player_number).field[slot] is not card:
                continue
            if card.ino_possessed_by is not None and self._is_alive_instance(card.ino_possessed_by):
                continue
            effect_card = self._effect_carrier(card)
            if effect_card.hanzo_poisoned and int(effect_card.current_hp or 0) > 0:
                amount = self._percent_hp_amount(effect_card, 0.05)
                self.log_event(f"Poison de la salamandre : {effect_card.definition.name} perd {amount} PV (5 %).")
                self.emit_visual("poison_burst", player=player_number, slot=slot, amount=amount)
                self._deal_fixed_damage(
                    player_number, slot, amount, source=None,
                    label="Poison de la salamandre", allow_guard=False,
                )

        # Brume empoisonnée : au début de chacun des tours du propriétaire de
        # Hanzo, ses AUTRES alliés perdent 5 % de leurs PV max et chaque ennemi
        # perd 10 %. La brume cesse immédiatement dès que Hanzo quitte le terrain.
        hanzos = [
            card for card in list(player.field)
            if card is not None and card.definition.id == "hanzo" and int(card.current_hp or 0) > 0
            and not (card.ino_possessed_by is not None and self._is_alive_instance(card.ino_possessed_by))
        ]
        for hanzo in hanzos:
            self.emit_visual("passive_audio", card_id="hanzo")
            self.log_event("Brume empoisonnée de Hanzo : -5 % aux alliés, -10 % aux ennemis.")
            for ally_slot, ally in list(enumerate(player.field)):
                if ally is None or ally is hanzo or self.player(player_number).field[ally_slot] is not ally:
                    continue
                amount = self._percent_hp_amount(ally, 0.05)
                self.emit_visual("poison_burst", player=player_number, slot=ally_slot, amount=amount)
                self._deal_fixed_damage(
                    player_number, ally_slot, amount, source=hanzo,
                    label="Brume empoisonnée", allow_guard=False,
                )
            for enemy_slot, target in list(enumerate(enemy.field)):
                if target is None or self.player(enemy.number).field[enemy_slot] is not target:
                    continue
                amount = self._percent_hp_amount(target, 0.10)
                self.emit_visual("poison_burst", player=enemy.number, slot=enemy_slot, amount=amount)
                self._deal_fixed_damage(
                    enemy.number, enemy_slot, amount, source=hanzo,
                    label="Brume empoisonnée", allow_guard=False,
                )

        # Prison de glace de Haku : 200 PV fixes au début de chacun des
        # 3 tours emprisonnés. Le compteur de durée descend à la fin du tour.
        for slot, card in list(enumerate(player.field)):
            if card is None or self.player(player_number).field[slot] is not card:
                continue
            if card.ino_possessed_by is not None and self._is_alive_instance(card.ino_possessed_by):
                continue
            effect_card = self._effect_carrier(card)
            if effect_card.haku_ice_prison_turns > 0 and int(effect_card.current_hp or 0) > 0:
                self.log_event(f"Prison de glace : {effect_card.definition.name} perd 200 PV.")
                self.emit_visual("ice_burst", player=player_number, slot=slot, amount=200)
                self._deal_fixed_damage(
                    player_number, slot, 200, source=None, label="Prison de glace", allow_guard=False
                )

        # 1.2.0 — Poison mortel de Shizune : 30 PV au début de chaque tour jusqu'à la mort.
        for slot, card in list(enumerate(player.field)):
            if card is None or self.player(player_number).field[slot] is not card:
                continue
            body = self._effect_carrier(card)
            if body.shizune_poisoned and int(body.current_hp or 0) > 0:
                self.log_event(f"Aiguilles malicieuses : {body.definition.name} perd 30 PV de poison.")
                self.emit_visual("poison_burst", player=player_number, slot=slot, amount=30)
                self._deal_fixed_damage(player_number, slot, 30, source=None, label="Poison de Shizune", allow_guard=False)

        # Vieux os : la furie de Kimimaro lui coûte exactement 10 % de ses PV max
        # au début de chacun de ses tours. Ce coût propre n'est pas réduit par son os.
        for slot, card in list(enumerate(player.field)):
            if card is None or self.player(player_number).field[slot] is not card:
                continue
            if card.definition.id == "kimimaro" and card.kimimaro_fury_active and int(card.current_hp or 0) > 0:
                cost = max(1, int(round(self.max_hp(card) * 0.10)))
                before = int(card.current_hp or 0)
                card.current_hp = max(0, before - cost)
                self.log_event(f"Vieux os : Kimimaro perd {min(before, cost)} PV à cause de sa furie.")
                if int(card.current_hp or 0) <= 0:
                    self._check_ko(player_number, slot, source=None, suppress_survival=False)

        # Recharge du Transfert de l'esprit d'Ino : un cran au début de chacun
        # de ses tours. Après utilisation : T 1/3, puis T 2/3, T 3/3, et la
        # technique redevient disponible au 3e tour suivant.
        for card in list(player.field):
            if (
                card is not None
                and card.definition.id == "ino"
                and card.ino_special_cooldown > 0
                and not (card.ino_possessed_by is not None and self._is_alive_instance(card.ino_possessed_by))
            ):
                card.ino_special_cooldown -= 1

        # Recharge du Sexy Jutsu : exactement un cran au début de chacun des
        # tours de Konohamaru, ce qui autorise une nouvelle utilisation au 4e.
        for card in list(player.field):
            if (
                card is not None
                and card.definition.id == "konohamaru"
                and card.konohamaru_sexy_cooldown > 0
                and not (card.ino_possessed_by is not None and self._is_alive_instance(card.ino_possessed_by))
            ):
                card.konohamaru_sexy_cooldown -= 1

        # Recharge de la Possession des ombres : réutilisable au 4e tour suivant.
        for card in list(player.field):
            if (
                card is not None
                and card.definition.id == "shikamaru"
                and card.shikamaru_special_cooldown > 0
                and not (card.ino_possessed_by is not None and self._is_alive_instance(card.ino_possessed_by))
            ):
                card.shikamaru_special_cooldown -= 1
                if card.shikamaru_special_cooldown <= 0:
                    card.special_used = False

        # Recharge de Gengetsu : après la fin/destruction du clone, la technique
        # redevient disponible au 4e tour suivant de son propriétaire.
        for card in list(player.field):
            if (
                card is not None
                and card.definition.id == "gengetsu"
                and not card.gengetsu_clone_active
                and card.gengetsu_special_cooldown > 0
                and not (card.ino_possessed_by is not None and self._is_alive_instance(card.ino_possessed_by))
            ):
                card.gengetsu_special_cooldown -= 1

        # Compte à rebours du clone explosif de Gengetsu : il descend uniquement
        # au début des tours de son propriétaire. Le tour d'activation ne compte pas.
        for slot, card in list(enumerate(player.field)):
            if (
                card is not None
                and getattr(card, "gengetsu_clone_active", False)
                and not (card.ino_possessed_by is not None and self._is_alive_instance(card.ino_possessed_by))
            ):
                self._tick_gengetsu_clone(player_number, slot, card)

        # Passifs de début de tour.
        for slot, card in list(enumerate(player.field)):
            if card is None or self.player(player_number).field[slot] is not card:
                continue
            if card.ino_possessed_by is not None and self._is_alive_instance(card.ino_possessed_by):
                continue
            cid = card.definition.id
            if cid == "tsunade" and int(card.current_hp or 0) * 2 < self.max_hp(card):
                healed = self._heal(card, 200)
                if healed:
                    self.log_event(f"Byakugô : Tsunade récupère {healed} PV.")
            if cid == "kisame":
                has_prisoner = any(
                    target is not None and target.prisoned_by is card
                    for target in enemy.field
                )
                if has_prisoner:
                    card.permanent_buffs["ninjutsu"] -= 100
                    self.log_event("Prison aqueuse : Kisame perd 100 Ninjutsu.")
            if cid == "karin":
                card.karin_turn_counter += 1
                if card.karin_special_cooldown > 0:
                    card.karin_special_cooldown -= 1
                if card.karin_turn_counter % 2 == 0:
                    healed = self._heal(card, 600)
                    if healed:
                        self.log_event(f"Soin passif : Karin récupère {healed} PV.")

        # Hashirama frappe toutes les cartes adverses au début de chacun de ses tours.
        for card in list(player.field):
            if (
                card is not None
                and card.definition.id == "hashirama"
                and not (card.ino_possessed_by is not None and self._is_alive_instance(card.ino_possessed_by))
            ):
                self.emit_visual("passive_audio", card_id="hashirama")
                self.log_event("Croissance luxuriante : -100 PV à toutes les cartes ennemies.")
                for slot, target in list(enumerate(enemy.field)):
                    if target is not None:
                        self._deal_fixed_damage(enemy.number, slot, 100, source=card, label="Croissance luxuriante")

        self.log_event(f"Tour {self.turn} — J{player_number} joue.")
        # 1.7.0 : l'Action 2 n'est PLUS résolue au début du tour de son
        # propriétaire. Elle attend la prochaine validation adverse et part
        # juste avant les actions de cet adversaire (voir resolve_reactive_a2_before_actions).

    def _tick_effect_durations(self, card: CardInstance):
        if card.haku_ice_prison_turns > 0:
            card.haku_ice_prison_turns -= 1
            if card.haku_ice_prison_turns == 0:
                self.log_event(f"Prison de glace : {card.definition.name} est libéré.")
        if card.konohamaru_sexy_turns > 0 and card.konohamaru_sexy_started_turn != self.turn:
            card.konohamaru_sexy_turns -= 1
            if card.konohamaru_sexy_turns == 0:
                card.konohamaru_sexy_started_turn = -1
                self.log_event(f"Sexy Jutsu : {card.definition.name} reprend sa forme normale.")
        if card.choji_pill_turns > 0 and card.choji_pill_started_turn != self.turn:
            card.choji_pill_turns -= 1
            if card.choji_pill_turns == 0:
                card.choji_pill_started_turn = -1
                self.log_event("Pilule de combat : le bonus de Choji prend fin.")
        if card.disabled_turns > 0:
            card.disabled_turns -= 1
        if card.sealed_turns > 0:
            card.sealed_turns -= 1
            if card.sealed_turns == 0:
                self.log_event(f"Scellement : {card.definition.name} est libéré du sceau.")
        if card.rooted_turns > 0:
            card.rooted_turns -= 1
            if card.rooted_turns == 0:
                self.log_event(f"ENRACINÉ : {card.definition.name} peut de nouveau effectuer des Switchs.")
        if card.shizune_paralysis_turns > 0:
            card.shizune_paralysis_turns -= 1
            if card.shizune_paralysis_turns == 0:
                self.log_event(f"Poison paralysant : les statistiques de {card.definition.name} reviennent à la normale.")
        if getattr(card, "shadow_stuns", None):
            for entry in card.shadow_stuns:
                entry["turns"] = max(0, int(entry.get("turns", 0)) - 1)
            card.shadow_stuns = [e for e in card.shadow_stuns if int(e.get("turns", 0)) > 0]
        if card.special_block_turns > 0:
            card.special_block_turns -= 1
        for style in list(card.blocked_styles):
            card.blocked_styles[style] -= 1
            if card.blocked_styles[style] <= 0:
                del card.blocked_styles[style]
        for mod in card.timed_modifiers:
            mod.turns_left -= 1
        card.timed_modifiers = [mod for mod in card.timed_modifiers if mod.turns_left > 0]

    def _end_card_turn(self, card: CardInstance):
        # Le corps possédé ne consomme plus ses effets sur les tours de son
        # propriétaire : il les consomme lorsqu'il agit via Ino.
        if card.ino_possessed_by is not None and self._is_alive_instance(card.ino_possessed_by):
            return

        # Nuage de fumée d'Asuma : deux de ses tours complets, puis explosion.
        if card.definition.id == "asuma" and card.asuma_smoke_turns > 0:
            card.asuma_smoke_turns -= 1
            if card.asuma_smoke_turns <= 0 and self._is_alive_instance(card):
                amount = max(1, int(round(int(card.current_hp or 0) * 0.20)))
                owner_loc = self._find_instance(card)
                if owner_loc is not None:
                    enemy = self.opponent(owner_loc[0])
                    self.log_event(f"Nuage de fumée : Asuma fait exploser le nuage — {amount} PV à chaque carte ennemie.")
                    for enemy_slot, target in list(enumerate(enemy.field)):
                        if target is not None:
                            self._deal_fixed_damage(enemy.number, enemy_slot, amount, source=card, label="Explosion du nuage d'Asuma", allow_guard=False)

        controlled_body = None
        if card.definition.id == "ino" and self._is_alive_instance(card.ino_possession_target):
            controlled_body = card.ino_possession_target

        # Comportement électrique dure 2 tours COMPLETS de Karui. Le tour
        # exact du déclenchement ne consomme pas immédiatement une charge.
        if card.definition.id == "karui" and card.karui_electric_turns > 0 and card.karui_electric_started_turn != self.turn:
            old_max = self.max_hp(card)
            card.karui_electric_turns = max(0, card.karui_electric_turns - 1)
            if card.karui_electric_turns <= 0:
                card.karui_electric_started_turn = -1
                new_max = self.max_hp(card)
                card.current_hp = min(int(card.current_hp or 0), new_max)
                self.log_event("Comportement électrique : le bonus de Karui prend fin.")

        # Les effets déjà présents sur Ino elle-même continuent aussi leur durée.
        self._tick_effect_durations(card)
        if controlled_body is not None:
            self._tick_effect_durations(controlled_body)

            # Le tour d'activation ne consomme pas la durée du Transfert.
            if card.ino_possession_started_turn != self.turn:
                card.ino_possession_turns_left = max(0, card.ino_possession_turns_left - 1)
                if card.ino_possession_turns_left <= 0:
                    target_name = controlled_body.definition.name
                    self._end_ino_possession(
                        card,
                        reason=f"Transfert de l'esprit terminé : {target_name} retrouve le contrôle de son corps.",
                    )

    def end_turn(self):
        if self.winner is not None or self.pending_replacement is not None:
            return
        current = self.active_player
        for card in list(self.player(current).field):
            if card is not None:
                self._end_card_turn(card)

        # Expérience du Sannin : le bonus correspond littéralement à chaque
        # TOUR passé sur le terrain, qu'il s'agisse du tour de Jiraiya ou du
        # tour adverse. Tout Jiraiya encore vivant au moment où le tour se
        # termine gagne donc +10 dans chacun de ses trois arts.
        for owner in self.players.values():
            for card in owner.field:
                if card is None or card.definition.id != "jiraiya" or not self._is_alive_instance(card):
                    continue
                card.jiraiya_turns_completed += 1
                for style in ("taijutsu", "ninjutsu", "genjutsu"):
                    card.permanent_buffs[style] += 10
                self.log_event(
                    f"Expérience du Sannin : {card.jiraiya_turns_completed} tour(s) passé(s) sur le terrain, "
                    "+10 Taijutsu / +10 Ninjutsu / +10 Genjutsu."
                )

        # Hiramekarei : +50 de stock pour chaque tour complet passé vivant sur le terrain.
        for owner in self.players.values():
            for card in owner.field:
                if card is not None and card.definition.id == "chojuro" and self._is_alive_instance(card):
                    card.chojuro_chakra_stock += 50

        # Sharingan de Sasuke : chaque verrou dure 3 tours complets de la carte
        # qui a déclenché l'immunité. Le tour de déclenchement ne consomme pas
        # immédiatement une charge.
        self._tick_sasuke_locks(current)

        # Passifs d'inciblabilité : ils alternent uniquement à la fin d'un
        # tour ADVERSE de leur propriétaire. Le son se joue à l'entrée dans
        # l'état inciblable (False -> True), jamais à la sortie.
        other = self.opponent(current)
        for card in other.field:
            if card is None:
                continue
            cid = card.definition.id
            if cid == "obito":
                was_untargetable = bool(card.obito_intangible)
                card.obito_intangible = not card.obito_intangible
                if not was_untargetable and card.obito_intangible:
                    self.emit_visual("passive_audio", card_id="obito")
            elif cid == "zabuza":
                was_untargetable = bool(card.zabuza_untargetable)
                card.zabuza_untargetable = not card.zabuza_untargetable
                if not was_untargetable and card.zabuza_untargetable:
                    self.emit_visual("passive_audio", card_id="zabuza")
            elif cid == "gengetsu" and not card.gengetsu_clone_active:
                was_untargetable = bool(card.gengetsu_untargetable)
                card.gengetsu_untargetable = not card.gengetsu_untargetable
                if not was_untargetable and card.gengetsu_untargetable:
                    self.emit_visual("passive_audio", card_id="gengetsu")
            elif cid == "konan":
                card.konan_untargetable = not card.konan_untargetable
                if card.konan_untargetable:
                    self.emit_visual("passive_audio", card_id="konan")

        next_player = self.opponent_number(current)
        self.turn += 1
        self.start_turn(next_player)

    # ------------------------------------------------------------------
    # Damage / KO / replacement
    # ------------------------------------------------------------------
    @staticmethod
    def element_advantage(attacker: CardDefinition, defender: CardDefinition) -> bool:
        # Kakuzu possède simultanément les cinq affinités : il n'a aucune
        # faiblesse élémentaire et ses attaques sont toujours super efficaces.
        if defender.id == "kakuzu":
            return False
        if attacker.id == "kakuzu":
            return True
        return ELEMENT_BEATS.get(attacker.element) == defender.element

    @staticmethod
    def _zero_damage_star_percent(stars: float) -> float:
        key = round(float(stars) * 2.0) / 2.0
        return float(ZERO_DAMAGE_STAR_PCT.get(key, 0.0))

    def _zero_damage_fallback(self, attacker: CardInstance, defender: CardInstance) -> tuple[int, int, float]:
        attacker_def = self._combat_definition(attacker)
        stars = float(getattr(attacker_def, "stars", 0.0) or 0.0)
        pct = self._zero_damage_star_percent(stars)
        bonus = min(100, max(0, int(round(self.max_hp(defender) * pct))))
        return 100 + bonus, bonus, stars

    @classmethod
    def _definition_zero_damage_fallback(cls, attacker: CardDefinition, defender: CardDefinition) -> int:
        key = round(float(getattr(attacker, "stars", 0.0) or 0.0) * 2.0) / 2.0
        pct = float(ZERO_DAMAGE_STAR_PCT.get(key, 0.0))
        bonus = min(100, max(0, int(round(int(getattr(defender, "max_hp", 0) or 0) * pct))))
        return 100 + bonus

    def calculate_card_damage(self, attacker: CardDefinition, defender: CardDefinition, style: str) -> tuple[int, bool, int, int]:
        # Estimation simple utilisée notamment par l'IA de draft.
        atk = attacker.stat(style)
        defense = defender.stat(style)
        diff = atk - defense
        damage = max(100, diff) if diff > 0 else 0
        advantage = self.element_advantage(attacker, defender)
        # Le secours anti-écart est un plancher autonome : si le calcul de base
        # vaut 0, on n'empile pas le bonus élémentaire dessus.
        if advantage and damage > 0:
            damage = int(round(damage * 1.10)) + 150
        if damage == 0:
            damage = self._definition_zero_damage_fallback(attacker, defender)
        return damage, advantage, atk, defense

    @staticmethod
    def calculate_direct_damage(attacker: CardDefinition, style: str) -> int:
        return max(100, attacker.stat(style) // 2)

    def _guard_slot(self, player_number: int, original_slot: int) -> int:
        player = self.player(player_number)
        target = player.field[original_slot]
        if target is None or target.definition.id == "choji":
            return original_slot
        for slot, card in enumerate(player.field):
            if (
                card is not None
                and card.definition.id == "choji"
                and int(card.current_hp or 0) > 0
            ):
                return slot
        return original_slot

    def _kankuro_reduction(self, player_number: int, defender: CardInstance) -> int:
        for card in self.player(player_number).field:
            if card is not None and card is not defender and card.definition.id == "kankuro" and card.kankuro_defense_active:
                return 250
        return 0

    def _defensive_reduction(
        self,
        defender_player: int,
        defender: CardInstance,
        attacker: CardInstance | None,
        style: str | None,
        *,
        is_attack: bool,
        is_special: bool,
        bypass_defensive_passives: bool,
    ) -> tuple[int, bool]:
        """Retourne (réduction, immunité)."""
        if not is_attack:
            return 0, False
        if bypass_defensive_passives:
            return 0, False

        cid = defender.definition.id
        if cid == "ino" and self._is_alive_instance(defender.ino_possession_target):
            self.log_event("Protection Transfert : Ino est inciblable tant que son esprit contrôle une autre carte.")
            return 0, True
        if defender.ino_possessed_by is not None and self._is_alive_instance(defender.ino_possessed_by):
            self.log_event(f"Transfert de l'esprit : {defender.definition.name} est inciblable tant que son corps est contrôlé.")
            return 0, True
        if cid == "sasuke" and self._sasuke_lock_active(defender, attacker, style):
            self.log_event(
                f"Sharingan : le {STYLE_LABELS.get(style or '', style or 'même art')} de "
                f"{attacker.definition.name if attacker else 'cette carte'} ne peut plus toucher Sasuke."
            )
            return 0, True
        if cid == "obito" and defender.obito_intangible:
            return 0, True
        if cid == "zabuza" and defender.zabuza_untargetable:
            self.log_event("Brume : Zabuza est inciblable et évite l'attaque.")
            return 0, True
        if cid == "gengetsu" and defender.gengetsu_untargetable and not defender.gengetsu_clone_active:
            self.log_event("Palourde : Gengetsu est inciblable et évite l'attaque.")
            return 0, True
        if cid == "konan" and defender.konan_untargetable:
            self.log_event("Origami : Konan est inciblable et évite l'attaque.")
            return 0, True
        if cid == "asuma" and defender.asuma_smoke_turns > 0:
            self.log_event("Nuage de fumée : Asuma est inciblable et évite l'attaque.")
            return 0, True
        if cid == "madara" and is_special and style == "genjutsu":
            self.emit_visual("passive_audio", card_id="madara")
            return 0, True

        # Trancheur : Mifune conserve les règles d’inciblabilité, mais ignore ensuite
        # toutes les réductions/passifs défensifs de dégâts.
        if attacker is not None and attacker.definition.id == "mifune" and style == "taijutsu":
            return 0, False

        reduction = 0
        if cid == "nagato" and style in ("ninjutsu", "genjutsu"):
            reduction += 200
        elif cid == "sasuke" and defender.defense_triggered_turn != self.turn:
            reduction += 150
            defender.defense_triggered_turn = self.turn
        elif cid == "gaara" and defender.defense_triggered_turn != self.turn:
            reduction += 300
            defender.defense_triggered_turn = self.turn
        elif cid == "a_raikage":
            reduction += 120
        elif cid == "sasori" and style == "taijutsu" and defender.defense_triggered_turn != self.turn:
            defender.defense_triggered_turn = self.turn
            if attacker is not None and self._is_alive_instance(attacker):
                affected_attacker = self._effect_carrier(attacker)
                affected_attacker.permanent_buffs["taijutsu"] -= 100
                loc = self._find_instance(attacker)
                self.log_event(f"Poison de Sasori : {attacker.definition.name} perd définitivement 100 Taijutsu et subit 50 PV de poison.")
                if loc:
                    self.emit_visual("poison_burst", player=loc[0], slot=loc[1], amount=50)
                    self._deal_fixed_damage(loc[0], loc[1], 50, source=defender, label="Poison de Sasori", allow_guard=False)
        elif cid == "suigetsu" and style == "taijutsu" and (attacker is None or self._combat_definition(attacker).element != "foudre"):
            reduction += 150
        elif cid == "kurenai" and defender.defense_triggered_turn != self.turn:
            reduction += 200
            defender.defense_triggered_turn = self.turn
        return reduction, False

    def _update_gai_thresholds(self, card: CardInstance):
        if card.definition.id != "gai" or not self._is_alive_instance(card):
            return
        hp = int(card.current_hp or 0)
        max_hp = self.max_hp(card)
        for pct in (75, 50, 25):
            if pct not in card.gai_thresholds and hp * 100 <= max_hp * pct:
                card.gai_thresholds.add(pct)
                card.permanent_buffs["taijutsu"] += 250
                self.log_event(f"Maito Gai ouvre une porte ({pct} %) : +250 Taijutsu.")

    def _deal_damage(
        self,
        defender_player: int,
        defender_slot: int,
        amount: int,
        *,
        attacker: CardInstance | None = None,
        style: str | None = None,
        is_attack: bool = False,
        is_special: bool = False,
        bypass_defensive_passives: bool = False,
        ignore_shield: bool = False,
        absolute_bypass: bool = False,
        allow_guard: bool = True,
        suppress_survival: bool = False,
        undodgeable: bool = False,
        label: str = "",
    ) -> tuple[int, bool, bool]:
        player = self.player(defender_player)
        if defender_slot not in (0, 1, 2) or player.field[defender_slot] is None:
            return 0, False, False

        if allow_guard:
            redirected = self._guard_slot(defender_player, defender_slot)
            if redirected != defender_slot:
                guard = player.field[redirected]
                if guard is not None:
                    self.log_event(f"Expansion Akimichi : Choji protège {player.field[defender_slot].definition.name}.")
                defender_slot = redirected

        defender = player.field[defender_slot]
        if defender is None:
            return 0, False, False

        visual_defender = defender
        # Le passif Protection Transfert continue d'annuler les attaques
        # directes contre le slot d'Ino. En revanche les dégâts non ciblés,
        # contrecoups et effets déjà autorisés portent sur le vrai corps contrôlé.
        if (
            is_attack
            and visual_defender.definition.id == "ino"
            and self._is_alive_instance(visual_defender.ino_possession_target)
            and not absolute_bypass
            and not bypass_defensive_passives
        ):
            self.log_event("Protection Transfert : Ino est inciblable tant que son esprit contrôle une autre carte.")
            return 0, False, True

        defender = self._effect_carrier(visual_defender)

        # Sexy Jutsu : tant que la transformation est active, les Ninjas
        # masculins ne peuvent pas toucher la carte transformée. Le Chidori
        # absolu de Sasuke conserve son comportement spécial et traverse cet effet.
        if (
            is_attack and defender.konohamaru_sexy_turns > 0 and attacker is not None
            and self._combat_definition(attacker).id not in FEMALE_CARD_IDS and not absolute_bypass
        ):
            self.log_event(f"Sexy Jutsu : {attacker.definition.name} ne parvient pas à toucher {defender.definition.name} !")
            return 0, False, True

        # Classic 1.0.4 — Miroirs de glace : lorsqu'Haku vient d'entrer sur
        # le terrain, la première attaque PROGRAMMÉE qui le cible déclenche une
        # parade à 2 chances sur 3. La protection d'entrée est consommée après
        # cette première tentative, qu'elle réussisse ou non.
        if (
            is_attack
            and defender.definition.id == "haku"
            and defender.haku_entry_guard
            and self._resolving_delayed_action
            and not absolute_bypass
            and not undodgeable
            and (attacker is None or attacker.definition.id != "mifune")
        ):
            defender.haku_entry_guard = False
            if self.random.random() < (2.0 / 3.0):
                self.log_event("Miroirs de glace : Haku pare l'attaque programmée !")
                loc = self._find_instance(defender)
                if loc:
                    self.emit_visual("stun_apply", player=loc[0], slot=loc[1], label="PARADE")
                return 0, False, True
            self.log_event("Miroirs de glace : la parade de Haku échoue.")

        # Permutation du serpent : prochaine vraie attaque entièrement esquivée,
        # puis l'attaquant reçoit le poison d'Anko pendant 4 de ses tours.
        if is_attack and defender.definition.id == "anko" and defender.anko_serpent_armed and attacker is not None and not absolute_bypass and not undodgeable:
            defender.anko_serpent_armed = False
            poisoned = self._effect_carrier(attacker)
            poisoned.anko_poison_turns = max(poisoned.anko_poison_turns, 4)
            self.log_event(f"Permutation du serpent : Anko esquive l'attaque et empoisonne {attacker.definition.name} pendant 4 tours.")
            loc = self._find_instance(defender)
            if loc:
                self.emit_visual("stun_apply", player=loc[0], slot=loc[1], label="PERMUTATION")
            return 0, False, True

        # Konohamaru : 50 % de chance d'esquiver chaque attaque et de répondre
        # immédiatement avec 350 dégâts fixes sur l'attaquant.
        if is_attack and defender.definition.id == "konohamaru" and attacker is not None and not absolute_bypass and not undodgeable and attacker.definition.id != "mifune":
            if self.random.random() < 0.5:
                self.log_event(f"Rasengan réflexe : Konohamaru esquive et contre-attaque {attacker.definition.name} pour 350 PV fixes !")
                loc = self._find_instance(attacker)
                if loc:
                    self.emit_visual("attack", from_player=defender_player, from_slot=defender_slot, to_player=loc[0], to_slot=loc[1], advantage=False, damage=350, style="ninjutsu", special=False, immune=False)
                    self._deal_fixed_damage(loc[0], loc[1], 350, source=defender, label="Rasengan réflexe", allow_guard=False)
                return 0, False, True

        # Classic 1.0.4 — Shunshin : Shisui possède 1 chance sur 3
        # d'esquiver complètement chaque vraie attaque qui le cible.
        if is_attack and defender.definition.id == "shisui" and not absolute_bypass and not undodgeable and (attacker is None or attacker.definition.id != "mifune"):
            if self.random.random() < (1.0 / 3.0):
                self.log_event("Shunshin : Shisui esquive complètement l'attaque !")
                loc = self._find_instance(defender)
                if loc:
                    self.emit_visual("stun_apply", player=loc[0], slot=loc[1], label="ESQUIVE")
                return 0, False, True

        reduction, immune = self._defensive_reduction(
            defender_player,
            defender,
            attacker,
            style,
            is_attack=is_attack,
            is_special=is_special,
            bypass_defensive_passives=bypass_defensive_passives,
        )
        if immune:
            self.log_event(f"{defender.definition.name} ignore complètement les dégâts.")
            return 0, False, True

        final = max(0, int(amount) - reduction)
        if (
            is_attack and final > 0 and defender.konohamaru_sexy_turns > 0
            and attacker is not None and self._combat_definition(attacker).id in FEMALE_CARD_IDS
            and not absolute_bypass
        ):
            final *= 2
            self.log_event(f"Sexy Jutsu : {attacker.definition.name} inflige le double de dégâts à {defender.definition.name} !")
        # La défense marionnettiste est une technique spéciale persistante, pas un passif.
        mifune_trancheur = bool(is_attack and attacker is not None and attacker.definition.id == "mifune" and style == "taijutsu")
        if not absolute_bypass and not mifune_trancheur:
            final = max(0, final - self._kankuro_reduction(defender_player, defender))

            # Les dix marionnettes de Chiyo : les AUTRES alliés subissent 20 %
            # de dégâts en moins tant qu'une Chiyo ayant activé la technique est vivante.
            if defender.definition.id != "chiyo" and final > 0:
                chiyo = next((
                    c for c in player.field
                    if c is not None and c.definition.id == "chiyo"
                    and c.chiyo_puppets_active and int(c.current_hp or 0) > 0
                ), None)
                if chiyo is not None:
                    before = final
                    final = max(0, int(round(final * 0.80)))
                    prevented = before - final
                    if prevented > 0:
                        self.log_event(f"Les dix marionnettes : Chiyo réduit de {prevented} les dégâts reçus par {defender.definition.name}.")
        # YUGITO06 R5 — secours anti-écart de rareté. Une attaque réellement
        # esquivée/immunisée est déjà sortie plus haut et ne reçoit donc rien.
        # Si une attaque VALIDÉE tombe à 0 après les réductions, elle inflige :
        # 100 + (% des PV max de la cible), avec bonus % plafonné à +100.
        # Les boucliers s'appliquent ensuite normalement.
        if is_attack and final == 0 and attacker is not None:
            fallback, star_bonus, attacker_stars = self._zero_damage_fallback(attacker, defender)
            final = fallback
            self.log_event(
                f"Équilibrage {attacker_stars:g}★ : attaque à 0 -> {fallback} dégâts "
                f"(100 fixes + {star_bonus} selon les PV max de la cible)."
            )

        # Tombé sur un os : tous les dégâts reçus par Kimimaro sont réduits de 25 %.
        if defender.definition.id == "kimimaro" and final > 0 and not absolute_bypass:
            before_bone = final
            final = max(0, int(round(final * 0.75)))
            if final != before_bone:
                self.log_event(f"Tombé sur un os : Kimimaro réduit les dégâts de {before_bone - final}.")

        absorbed = 0
        if mifune_trancheur:
            shield_before = max(0, int(defender.shield or 0)) + max(0, int(getattr(defender, "kurenai_hidden_shield", 0) or 0))
            if shield_before > 0:
                bonus_shield = int(round(shield_before * 0.50))
                final += bonus_shield
                defender.shield = 0
                defender.kurenai_hidden_shield = 0
                self.log_event(f"Trancheur : Mifune détruit {shield_before} de bouclier et ajoute {bonus_shield} dégâts.")
        else:
            if not ignore_shield and final > 0 and defender.shield > 0:
                absorbed = min(defender.shield, final)
                defender.shield -= absorbed
                final -= absorbed
                if absorbed:
                    self.log_event(f"Bouclier de {defender.definition.name} : {absorbed} dégâts absorbés.")

            # Bouclier caché de Kurenai : il absorbe les dégâts sans jamais être
            # affiché comme un bouclier visible à l'adversaire.
            if not ignore_shield and final > 0 and getattr(defender, "kurenai_hidden_shield", 0) > 0:
                hidden_absorbed = min(defender.kurenai_hidden_shield, final)
                defender.kurenai_hidden_shield -= hidden_absorbed
                final -= hidden_absorbed

        hp_before = int(defender.current_hp or 0)

        # Multi clonage de Tobirama : une attaque sur deux ne conserve que 25 %
        # des dégâts qui auraient réellement atteint ses PV.
        if is_attack and final > 0 and defender.definition.id == "tobirama" and not absolute_bypass and not mifune_trancheur:
            defender.tobirama_attack_counter += 1
            if defender.tobirama_attack_counter % 2 == 0:
                original_final = final
                final = max(1, int(round(final * 0.25)))
                self.log_event(f"Multi clonage : Tobirama ne subit que {final} dégâts au lieu de {original_final}.")

        # Protection Doton : chaque AUTRE allié peut annuler une fois un impact létal.
        if final >= hp_before and hp_before > 0 and not absolute_bypass and defender.definition.id != "kurotsuchi" and not defender.kurotsuchi_guard_used:
            protector = next((c for c in player.field if c is not None and c.definition.id == "kurotsuchi" and int(c.current_hp or 0) > 0), None)
            if protector is not None:
                defender.kurotsuchi_guard_used = True
                self.log_event(f"Protection Doton : Kurotsuchi annule les dégâts mortels destinés à {defender.definition.name}.")
                self.emit_visual("shield", player=defender_player, slot=defender_slot, amount=0, label="DOTON")
                return 0, False, True

        # Roche super allégée : la première attaque létale visant Ônoki est
        # complètement esquivée. Aucun surplus ne traverse vers le joueur.
        if (
            is_attack and final >= hp_before and hp_before > 0
            and defender.definition.id == "onoki" and not defender.survival_used and not absolute_bypass and not mifune_trancheur
        ):
            defender.survival_used = True
            self.log_event("Roche super allégée : Ônoki esquive l'attaque mortelle !")
            return 0, False, True

        # Le surplus d'une vraie attaque traverse le Ninja et touche les PV du joueur.
        # Les dégâts fixes/passifs/poisons n'ont pas d'overkill joueur.
        overflow = max(0, final - hp_before) if is_attack else 0
        # Le clone aqueux explosif est un leurre : sa destruction ne provoque
        # jamais de dégâts de surplus sur les PV du joueur.
        if getattr(defender, "gengetsu_clone_active", False) and final >= hp_before:
            overflow = 0
        defender.current_hp = max(0, hp_before - final)
        hp_damage = hp_before - int(defender.current_hp)

        # 1.2.2 — la concentration de Shikamaru cesse au moindre dégât de PV.
        if hp_damage > 0 and defender.definition.id == "shikamaru":
            self._remove_shadow_stuns_from_source(defender)

        # 1.2.0 — seuils déclenchés uniquement si la carte reste vivante.
        if hp_damage > 0 and int(defender.current_hp or 0) > 0:
            if defender.definition.id == "rin" and not defender.rin_isobu_active and int(defender.current_hp or 0) * 100 < self.max_hp(defender) * 25:
                defender.rin_isobu_active = True
                defender.max_hp_bonus += 1000
                defender.current_hp = int(defender.current_hp or 0) + 1000
                defender.permanent_buffs["taijutsu"] += 250
                defender.permanent_buffs["ninjutsu"] += 300
                defender.permanent_buffs["genjutsu"] += 200
                self.log_event("Manifeste d'Isobu : Rin gagne +1000 PV, +250 Taijutsu, +300 Ninjutsu et +200 Genjutsu.")
                self.emit_visual("passive_audio", card_id="rin")
            if defender.definition.id == "asuma" and not defender.asuma_smoke_triggered and int(defender.current_hp or 0) * 100 < self.max_hp(defender) * 20:
                defender.asuma_smoke_triggered = True
                defender.asuma_smoke_turns = 2
                self.log_event("Nuage de fumée : Asuma passe sous 20 % de PV et devient inciblable pendant 2 de ses tours.")
                self.emit_visual("passive_audio", card_id="asuma")
            if defender.definition.id == "jugo":
                base_max = max(1, self.max_hp(defender))
                hp_now = int(defender.current_hp or 0)
                wanted = 2 if hp_now * 100 <= base_max * 40 else (1 if hp_now * 100 <= base_max * 70 else 0)
                while defender.jugo_stage < wanted:
                    defender.jugo_stage += 1
                    defender.max_hp_bonus += 100
                    defender.current_hp = int(defender.current_hp or 0) + 100
                    defender.permanent_buffs["taijutsu"] += 100
                    defender.permanent_buffs["ninjutsu"] += 100
                    defender.permanent_buffs["genjutsu"] -= 100
                    self.log_event(f"Marque maudite : Jûgo passe au stade {defender.jugo_stage} (+100 PV/Tai/Nin, -100 Gen).")
                    self.emit_visual("passive_audio", card_id="jugo")
            if defender.definition.id == "anko" and not defender.anko_curse_used and int(defender.current_hp or 0) * 100 < self.max_hp(defender) * 25:
                defender.anko_curse_used = True
                healed = self._heal(defender, 600)
                self.log_event(f"Marque maudite : Anko récupère {healed} PV et gagne définitivement +10 % dans ses trois arts.")
                self.emit_visual("passive_audio", card_id="anko")

        if hp_damage > 0:
            self.emit_visual(
                "damage", player=defender_player, slot=defender_slot, amount=hp_damage,
                label=label or ("spéciale" if is_special else "attaque"),
            )
        if overflow > 0:
            player.hp = max(0, player.hp - overflow)
            self.emit_visual("player_damage", player=defender_player, amount=overflow)
            self.log_event(f"SURPLUS : {overflow} dégâts traversent {defender.definition.name} et touchent J{defender_player}.")
            if player.hp <= 0 and self.winner is None:
                loc = self._find_instance(attacker) if attacker is not None else None
                self.winner = loc[0] if loc else self.opponent_number(defender_player)
                self.log_event(f"J{self.winner} remporte le duel par dégâts de surplus !")

        # Byakugô de Tsunade : si des dégâts la laissent vivante à 15 %
        # ou moins de ses PV maximum, elle récupère immédiatement tous ses PV.
        # IMPORTANT : ce n'est pas une résurrection. Si les dégâts la font tomber
        # à 0 PV, cet effet ne se déclenche pas et le K.O. est traité normalement.
        if (
            hp_damage > 0
            and defender.definition.id == "tsunade"
            and not absolute_bypass
            and int(defender.current_hp or 0) > 0
            and int(defender.current_hp or 0) * 100 <= defender.definition.max_hp * 15
        ):
            healed = self._heal(defender, defender.definition.max_hp)
            if healed > 0:
                self.emit_visual(
                    "heal", player=defender_player, slot=defender_slot, amount=healed,
                    label="BYAKUGÔ",
                )
                self.log_event(
                    f"Byakugô : Tsunade tombe à 15 % de PV ou moins sans être K.O. et récupère {healed} PV — régénération totale !"
                )

        # Sakura conserve son ancien effet quand elle reçoit elle-même des dégâts :
        # 25 % de soin sur elle et 10 % du même dégât sur ses autres alliés.
        if hp_damage > 0 and defender.definition.id == "sakura" and not absolute_bypass:
            self_heal = int(round(hp_damage * 0.25))
            ally_heal = int(round(hp_damage * 0.10))
            healed = self._heal(defender, self_heal)
            total_allies = 0
            for ally in player.field:
                if ally is not None and ally is not defender:
                    total_allies += self._heal(ally, ally_heal)
            if healed or total_allies:
                self.log_event(
                    f"Force concentrée : Sakura récupère {healed} PV et diffuse un soin de {ally_heal} PV à ses alliés."
                )

        # V35 : tant que Sakura est vivante sur le terrain, toute AUTRE carte
        # alliée qui subit des dégâts récupère immédiatement 25 % des PV perdus.
        # Exemple : -100 PV -> +25 PV. Le soin intervient après les dégâts et ne
        # ressuscite pas une carte déjà tombée à 0 PV.
        if (
            hp_damage > 0
            and not absolute_bypass
            and defender.definition.id != "sakura"
            and int(defender.current_hp or 0) > 0
        ):
            sakura = next(
                (c for c in player.field if c is not None and c.definition.id == "sakura" and int(c.current_hp or 0) > 0),
                None,
            )
            if sakura is not None:
                ally_heal = int(round(hp_damage * 0.25))
                healed = self._heal(defender, ally_heal)
                if healed > 0:
                    self.log_event(
                        f"Force concentrée : Sakura soigne {defender.definition.name} de {healed} PV (25 % des dégâts reçus)."
                    )

        # Zetsu : 25 % des PV réellement perdus par une AUTRE carte alliée lors d'une attaque.
        if hp_damage > 0 and is_attack and defender.definition.id != "zetsu" and int(defender.current_hp or 0) > 0:
            zetsu = next((c for c in player.field if c is not None and c.definition.id == "zetsu" and int(c.current_hp or 0) > 0), None)
            if zetsu is not None:
                amount = int(round(hp_damage * 0.25))
                healed = self._heal(defender, amount)
                if healed > 0:
                    self.log_event(f"Régénération organique : Zetsu soigne {defender.definition.name} de {healed} PV (25 % des dégâts reçus).")
                    self.emit_visual("heal", player=defender_player, slot=defender_slot, amount=healed, label="ZETSU")

        if (
            is_attack and attacker is not None and defender.definition.id == "konan"
            and defender.konan_mine_active and not defender.konan_untargetable and hp_damage > 0
            and self._is_alive_instance(attacker)
        ):
            loc = self._find_instance(attacker)
            if loc is not None:
                self.log_event(f"Carte explosive : l'attaque de {attacker.definition.name} déclenche la mine de Konan (-200 PV).")
                self._deal_fixed_damage(loc[0], loc[1], 200, source=defender, label="Carte explosive", allow_guard=False)

        if (
            is_attack
            and attacker is not None
            and style in STYLE_LABELS
            and defender.definition.id == "sai"
                    ):
            self._apply_timed_debuff(attacker, style, 200, "Encre affaiblissante", turns=2)
            self.log_event(f"Encre affaiblissante : {attacker.definition.name} perd 200 {STYLE_LABELS[style]} pendant 2 tours.")

        self._update_gai_thresholds(defender)
        killed = False
        if int(defender.current_hp or 0) <= 0:
            ko_player, ko_slot = defender_player, defender_slot
            if defender is not visual_defender:
                real_loc = self._find_instance(defender)
                if real_loc is not None:
                    ko_player, ko_slot = real_loc
            killed = self._check_ko(
                ko_player,
                ko_slot,
                source=attacker,
                suppress_survival=(suppress_survival or absolute_bypass),
            )

        return hp_damage, killed, False

    def _deal_fixed_damage(
        self,
        defender_player: int,
        defender_slot: int,
        amount: int,
        *,
        source: CardInstance | None,
        label: str,
        allow_guard: bool = True,
    ) -> tuple[int, bool]:
        hp_damage, killed, _ = self._deal_damage(
            defender_player,
            defender_slot,
            amount,
            attacker=source,
            style=None,
            is_attack=False,
            is_special=False,
            allow_guard=allow_guard,
            label=label,
        )
        return hp_damage, killed

    def _cleanup_links_to(self, dead: CardInstance):
        # 1.1.6 : les STUN de Possession des ombres sont liés au lanceur.
        self._remove_shadow_stuns_from_source(dead)
        # Si Ino ou le corps possédé disparaît par un effet de zone/poison,
        # le Transfert se termine immédiatement et les deux cartes retrouvent
        # leur comportement normal.
        if dead.ino_possession_target is not None:
            self._end_ino_possession(dead, reason="Transfert de l'esprit interrompu.")
        if dead.ino_possessed_by is not None:
            possessor = dead.ino_possessed_by
            if possessor.ino_possession_target is dead:
                self._end_ino_possession(possessor, reason="Le corps contrôlé disparaît : Transfert de l'esprit interrompu.")
            dead.ino_possessed_by = None

        for player in self.players.values():
            for card in player.field:
                if card is None:
                    continue
                if card.prisoned_by is dead:
                    card.prisoned_by = None
                    self.log_event(f"{card.definition.name} est libéré de la Prison aqueuse.")
                if card.doom_source is dead:
                    card.doom_source = None
                    card.doom_turns = 0
                    self.log_event(f"Le Rituel de Jashin visant {card.definition.name} est annulé.")

    def _try_kabuto_reanimation(self, player_number: int, slot: int, dead_instance: CardInstance) -> bool:
        """Réincarnation des âmes : intercepte automatiquement un premier K.O. allié avant qu'il soit traité comme une mort.

        La carte alliée est verrouillée à 1 PV puis immédiatement soignée à fond.
        Elle ne passe jamais au cimetière et ses liens contextuels (Jashin, prison,
        poison, etc.) restent intacts. Kabuto ne peut pas protéger sa propre mort.
        """
        player = self.player(player_number)
        if dead_instance.definition.id == "kabuto":
            return False

        kabuto = next(
            (
                c for c in player.field
                if c is not None
                and c is not dead_instance
                and c.definition.id == "kabuto"
                and not c.kabuto_reanimation_armed
                and int(c.current_hp or 0) > 0
            ),
            None,
        )
        if kabuto is None:
            return False

        kabuto.kabuto_reanimation_armed = True
        # IMPORTANT : on ne laisse jamais l'instance dans un état "morte" pour
        # les autres techniques. Le 1 PV sert d'état de fausse mort intermédiaire.
        dead_instance.current_hp = 1
        healed = self._heal(dead_instance, dead_instance.definition.max_hp)
        dead_instance.has_attacked = True
        player.field[slot] = dead_instance
        self.emit_visual(
            "heal", player=player_number, slot=slot, amount=healed,
            label="FAUSSE MORT 4G",
        )
        self.log_event(
            f"Réincarnation des âmes : {dead_instance.definition.name} est verrouillé à 1 PV puis revient immédiatement à tous ses PV, sans être considéré K.O. !"
        )
        return True

    def _try_chiyo_rescue(self, player_number: int, slot: int, dying: CardInstance) -> bool:
        """Dernier soin de Chiyo, utilisable une seule fois par Chiyo.

        - Si un AUTRE allié devrait mourir, Chiyo le soigne à fond avant le K.O.
        - Si Chiyo meurt avant d'avoir utilisé le passif, elle soigne à fond un
          autre allié aléatoire puis meurt normalement.
        """
        player = self.player(player_number)
        if dying.definition.id == "chiyo":
            if dying.chiyo_passive_used:
                return False
            dying.chiyo_passive_used = True
            allies = [
                c for c in player.field
                if c is not None and c is not dying and int(c.current_hp or 0) > 0
            ]
            injured = [c for c in allies if int(c.current_hp or 0) < c.definition.max_hp]
            if injured:
                # Le choix reste aléatoire, mais uniquement parmi les alliés qui
                # ont réellement des PV à récupérer : le passif ne peut plus
                # sembler "ne rien faire" en choisissant un allié déjà full vie.
                ally = self.random.choice(injured)
                healed = self._heal(ally, ally.definition.max_hp)
                loc = self._find_instance(ally)
                if loc:
                    self.emit_visual("heal", player=loc[0], slot=loc[1], amount=healed, label="DERNIER SOIN")
                self.log_event(f"Dernier soin : Chiyo tombe, mais soigne complètement {ally.definition.name} avant de disparaître.")
            elif allies:
                self.log_event("Dernier soin : Chiyo tombe, mais tous ses alliés encore en vie sont déjà à leurs PV maximum.")
            else:
                self.log_event("Dernier soin : Chiyo tombe sans allié restant à soigner.")
            return False

        chiyo = next(
            (
                c for c in player.field
                if c is not None
                and c is not dying
                and c.definition.id == "chiyo"
                and not c.chiyo_passive_used
                and int(c.current_hp or 0) > 0
            ),
            None,
        )
        if chiyo is None:
            return False
        chiyo.chiyo_passive_used = True
        dying.current_hp = 1
        healed = self._heal(dying, dying.definition.max_hp)
        self.emit_visual("heal", player=player_number, slot=slot, amount=healed, label="CHIYO")
        self.log_event(f"Dernier soin : Chiyo sauve {dying.definition.name} juste avant sa mort et le soigne complètement !")
        return True

    def _check_ko(
        self,
        player_number: int,
        slot: int,
        *,
        source: CardInstance | None,
        suppress_survival: bool,
    ) -> bool:
        player = self.player(player_number)
        card = player.field[slot]
        if card is None:
            return False
        cid = card.definition.id

        # La destruction du clone n'est PAS un K.O. de la carte originale.
        # L'explosion est annulée et Gengetsu (ou le copieur de sa spéciale)
        # retrouve exactement les PV/bouclier conservés avant transformation.
        if getattr(card, "gengetsu_clone_active", False):
            self._restore_from_gengetsu_clone(
                card,
                reason="Le clone aqueux est détruit avant l'explosion : aucune explosion, retour à la forme originale.",
            )
            return False

        # Le soin déclenché par la MORT de Chiyo n'est pas une survie de Chiyo :
        # même une attaque qui traverse les défenses (ex. Chidori absolu) tue bien
        # Chiyo, mais son dernier soin peut encore partir sur un allié si le passif
        # n'avait pas déjà été consommé.
        if cid == "chiyo":
            self._try_chiyo_rescue(player_number, slot, card)

        if not suppress_survival:
            if cid == "kakuzu" and card.kakuzu_revivals_left > 0:
                card.kakuzu_revivals_left -= 1
                card.current_hp = card.definition.max_hp
                # Les poisons/condamnations prennent fin puisqu'une vraie mort
                # vient d'être consommée par l'un des cœurs de Kakuzu.
                card.shino_poisoned = False
                card.hanzo_poisoned = False
                card.delayed_damage = 0
                card.doom_turns = 0
                card.doom_source = None
                card.prisoned_by = None
                card.disabled_turns = 0
                self.log_event(
                    f"Deux cœurs : Kakuzu revient à {card.definition.max_hp} PV. "
                    f"Il lui reste {card.kakuzu_revivals_left} résurrection(s)."
                )
                return False
            if cid == "danzo" and not card.survival_used:
                card.survival_used = True
                card.current_hp = 1
                self.log_event("Izanagi : Danzo survit à 1 PV.")
                return False
            if cid == "orochimaru" and not card.survival_used:
                card.survival_used = True
                card.current_hp = 250
                self.log_event("Mue : Orochimaru survit à 250 PV.")
                return False
            if cid == "hidan" and not card.survival_used:
                card.survival_used = True
                card.current_hp = 200
                self.log_event("Immortalité : Hidan survit à 200 PV.")
                return False
            if cid == "kankuro" and not card.kankuro_decoy_used:
                card.kankuro_decoy_used = True
                card.current_hp = card.definition.max_hp
                self.log_event("Karasu est détruite à la place de Kankuro : Kankuro revient avec tous ses PV.")
                return False
            if cid == "mu" and not card.mu_division_used:
                card.mu_division_used = True
                card.current_hp = self.max_hp(card)
                card.permanent_buffs["ninjutsu"] -= 450
                card.shino_poisoned = False
                card.hanzo_poisoned = False
                card.shizune_poisoned = False
                card.delayed_damage = 0
                card.doom_turns = 0
                card.doom_source = None
                card.prisoned_by = None
                card.disabled_turns = 0
                card.sealed_turns = 0
                self.log_event("Division cellulaire : Mû revient à tous ses PV, perd 450 Ninjutsu et son Jinton est désormais verrouillé.")
                self.emit_visual("passive_audio", card_id="mu")
                return False

        # Les effets qui empêchent réellement la mort doivent intervenir AVANT
        # le nettoyage des liens contextuels : sinon Jashin / prison / poison
        # considéreraient brièvement la carte comme morte. Un effet marqué
        # "survie ignorée" (ex. Chidori absolu) traverse aussi Chiyo/Kabuto.
        if not suppress_survival:
            # Chiyo elle-même a déjà déclenché son effet de mort ci-dessus. Ici,
            # Chiyo peut uniquement sauver un AUTRE allié d'un K.O. normal.
            if cid != "chiyo" and self._try_chiyo_rescue(player_number, slot, card):
                return False
            if self._try_kabuto_reanimation(player_number, slot, card):
                return False

        # Passifs de mort 1.2.0 : seulement après toutes les survies/réanimations,
        # donc uniquement sur une mort réellement définitive.
        if cid == "kushina" and source is not None and self._is_alive_instance(source):
            killer = self._effect_carrier(source)
            if killer.definition.id == "madara":
                self.log_event("Mangekyô éternel : Madara ignore le Scellement sans rancune de Kushina.")
            else:
                killer.sealed_turns = max(killer.sealed_turns, 4)
                self.log_event(f"Scellement sans rancune : {killer.definition.name} est SCELLÉ pendant 4 tours.")
                loc = self._find_instance(source)
                if loc:
                    self.emit_visual("stun_apply", player=loc[0], slot=loc[1], label="SCELLÉ")
        if cid == "shizune" and source is not None and self._is_alive_instance(source):
            killer = self._effect_carrier(source)
            killer.shizune_paralysis_turns = max(killer.shizune_paralysis_turns, 3)
            self.log_event(f"Fourberie : {killer.definition.name} perd 50 % de ses trois arts pendant 3 tours.")
            loc = self._find_instance(source)
            if loc:
                self.emit_visual("poison_apply", player=loc[0], slot=loc[1], amount=0, label="PARALYSANT")

        # Karui ne réagit qu'à une mort définitive d'un AUTRE membre allié de sa famille.
        self._trigger_karui_electric(player_number, card)

        self._cleanup_links_to(card)
        destroyed = card.definition
        self._set_synergy_pct(card, 0.0)
        player.field[slot] = None
        self._refresh_synergies()
        player.graveyard.append(destroyed)
        self.emit_visual("ko", player=player_number, slot=slot, card_id=destroyed.id)
        self.log_event(f"{destroyed.name} est envoyé au cimetière.")
        # Si ce Ninja devait être échangé au prochain tour, la carte choisie
        # entre immédiatement à sa mort et remplace le tirage aléatoire de 3.
        scheduled_switch_done = self._resolve_scheduled_switch_on_death(player_number, slot, card)
        if not self._check_no_cards_loss(player_number) and not scheduled_switch_done:
            self._queue_replacement(player_number, slot)
        return True

    def _check_no_cards_loss(self, player_number: int) -> bool:
        """Un joueur perd quand il n'a plus aucun Ninja sur le terrain ET aucune réserve."""
        if self.winner is not None:
            return True
        player = self.player(player_number)
        has_field_card = any(card is not None for card in player.field)
        if not has_field_card and not player.deck:
            self.winner = self.opponent_number(player_number)
            self.log_event(f"J{player_number} n'a plus aucune carte : J{self.winner} remporte le duel !")
            return True
        return False

    def _outstanding_replacement_slots(self, player_number: int) -> set[int]:
        slots = {slot for pnum, slot in self._replacement_queue if pnum == player_number}
        if self.pending_replacement is not None and self.pending_replacement.player_number == player_number:
            slots.add(self.pending_replacement.slot)
        return slots

    def _ensure_three_on_field(self, player_number: int):
        """Règle 1.1.6 : 3 Ninjas obligatoires si le joueur en possède au moins 3 au total."""
        if self.winner is not None:
            return
        player = self.player(player_number)
        field_count = sum(card is not None for card in player.field)
        total_cards = field_count + len(player.deck)
        required = min(3, total_cards)
        outstanding = self._outstanding_replacement_slots(player_number)
        needed = max(0, required - field_count - len(outstanding))
        if needed <= 0:
            self._prepare_next_replacement()
            return
        for slot, card in enumerate(player.field):
            if needed <= 0:
                break
            if card is None and slot not in outstanding:
                self._replacement_queue.append((player_number, slot))
                outstanding.add(slot)
                needed -= 1
        self._prepare_next_replacement()

    def _queue_replacement(self, player_number: int, slot: int):
        player = self.player(player_number)
        if not player.deck:
            self.log_event(f"J{player_number} n'a plus de carte dans sa réserve pour l'emplacement {slot + 1}.")
            return
        if slot not in self._outstanding_replacement_slots(player_number):
            self._replacement_queue.append((player_number, slot))
        self._ensure_three_on_field(player_number)

    def _prepare_next_replacement(self):
        if self.pending_replacement is not None:
            return
        while self._replacement_queue:
            player_number, slot = self._replacement_queue.pop(0)
            player = self.player(player_number)
            if player.field[slot] is not None or not player.deck:
                continue
            forced = self.forced_reserve_choice.get(player_number)
            forced_card = next((c for c in player.deck if forced and c.id == forced), None)
            options = [forced_card] if forced_card is not None else self.random.sample(player.deck, k=min(3, len(player.deck)))
            self.pending_replacement = ReplacementOffer(player_number, slot, options)
            self.log_event(f"J{player_number} doit choisir un remplaçant parmi {len(options)} carte(s).")
            return

    def choose_replacement(self, player_number: int, card_id: str) -> tuple[bool, str]:
        offer = self.pending_replacement
        if offer is None:
            return False, "Aucun remplacement n'est en attente."
        if offer.player_number != player_number:
            return False, "Ce remplacement appartient à l'autre joueur."
        chosen = next((c for c in offer.options if c.id == card_id), None)
        if chosen is None:
            return False, "Cette carte ne fait pas partie des propositions."

        player = self.player(player_number)
        deck_card = next((c for c in player.deck if c.id == chosen.id), None)
        if deck_card is None:
            return False, "La carte choisie n'est plus dans la réserve."

        player.deck.remove(deck_card)
        replacement = self.reserve_instances[player_number].pop(deck_card.id, None) or CardInstance(deck_card)
        replacement.has_attacked = False
        replacement.minato_free_attack_used = False
        if replacement.definition.id == "haku":
            replacement.haku_entry_guard = True
        player.field[offer.slot] = replacement
        self._refresh_synergies()
        self._consume_forced_reserve_choice(player_number, deck_card.id)
        self.pending_replacement = None
        # Un remplaçant choisi après K.O. arrive lui aussi sur le terrain piégé.
        self._trigger_makibishi_entry(player_number, offer.slot, replacement)
        self.log_event(f"J{player_number} remplace le Ninja détruit par {deck_card.name}.")
        self._ensure_three_on_field(player_number)
        return True, f"{deck_card.name} entre sur le terrain."

    # ------------------------------------------------------------------
    # Normal attacks
    # ------------------------------------------------------------------
    def _mark_attack_usage(self, attacker: CardInstance, style: str):
        cid = attacker.definition.id
        if cid == "rock_lee" and style == "taijutsu" and attacker.rock_lee_tai_boosts_left > 0:
            attacker.rock_lee_tai_boosts_left -= 1
        if cid == "kiba" and style == "taijutsu" and attacker.kiba_first_tai:
            attacker.kiba_first_tai = False
        if cid == "tenten" and style == "taijutsu":
            attacker.tenten_tai_used_this_turn = True
            attacker.permanent_buffs["taijutsu"] += 25
            self.log_event("Maîtrise des armes : Tenten gagne définitivement +25 Taijutsu.")
        attacker.previous_attack_style = style

    def _apply_timed_debuff(self, target: CardInstance, style: str, amount: int, label: str, turns: int = 1):
        body = self._effect_carrier(target)
        body.timed_modifiers.append(TimedModifier(style=style, amount=-abs(amount), turns_left=max(1, int(turns)), label=label))

    def _post_normal_attack_passives(
        self,
        attacker_player: int,
        attacker_slot: int,
        defender_player: int,
        outcome: AttackOutcome,
        style: str,
        *,
        is_special: bool,
        special_source_id: str | None,
    ):
        attacker = self.player(attacker_player).field[attacker_slot]
        if attacker is None:
            return
        target = None
        if outcome.target_slot is not None:
            target = self.player(defender_player).field[outcome.target_slot]

        if outcome.damage > 0:
            cid = attacker.definition.id
            if cid == "kisame" and style == "ninjutsu":
                healed = self._heal(attacker, 100)
                if healed:
                    self.log_event(f"Samehada : Kisame récupère {healed} PV.")
            if target is not None and cid == "neji" and not attacker.neji_passive_used:
                body = self._effect_carrier(target)
                loss = max(1, int(round(self.effective_stat(body, "ninjutsu") * 0.50)))
                self._apply_timed_debuff(body, "ninjutsu", loss, "Fermeture des tenketsu", turns=2)
                body.special_block_turns = max(body.special_block_turns, 2)
                attacker.neji_passive_used = True
                self.log_event(f"Byakugan : Neji scelle {target.definition.name} — Ninjutsu -50 % et spéciale bloquée pendant 2 tours.")
            if target is not None and cid == "shino" and style == "ninjutsu":
                self._apply_timed_debuff(target, "ninjutsu", 100, "Kikaichû")

            # Deidara touche les cartes adjacentes à la vraie cible.
            if cid == "deidara" and style == "ninjutsu" and outcome.target_slot is not None:
                for side in (outcome.target_slot - 1, outcome.target_slot + 1):
                    if side in (0, 1, 2) and self.player(defender_player).field[side] is not None:
                        self._deal_fixed_damage(defender_player, side, 150, source=attacker, label="Art explosif")

        # Mei répond à toute attaque Taijutsu qui lui retire réellement des PV.
        # Le contrecoup est un dégât fixe de Feu : il ignore les statistiques
        # défensives mais peut recevoir le bonus élémentaire Feu > Vent.
        original_target = target
        if (
            original_target is not None
            and original_target.definition.id == "mei"
            and style == "taijutsu"
            and outcome.hp_damage > 0
            and not outcome.killed
            and self._is_alive_instance(attacker)
        ):
            counter, advantage = self._elemental_fixed_amount(100, "feu", attacker)
            loc = self._find_instance(attacker)
            if loc:
                suffix = " (super efficace)" if advantage else ""
                self.log_event(f"Contrecoup brûlant : Mei renvoie {counter} PV de Feu à {attacker.definition.name}{suffix}.")
                self._deal_fixed_damage(
                    loc[0], loc[1], counter, source=original_target,
                    label="Contrecoup brûlant", allow_guard=False,
                )

        # Hinata riposte à chaque attaque reçue et non annulée.
        if original_target is not None and original_target.definition.id == "hinata" and not outcome.immune and self._is_alive_instance(attacker):
            loss = max(1, int(round(self.effective_stat(attacker, style) * 0.35))) if style in STYLE_LABELS else 0
            if loss:
                self._apply_timed_debuff(attacker, style, loss, "32 Points du Hakke", turns=2)
            loc = self._find_instance(attacker)
            if loc:
                self._deal_fixed_damage(loc[0], loc[1], 100, source=original_target, label="32 Points du Hakke", allow_guard=False)
            self.log_event(f"32 Points du Hakke : Hinata riposte à {attacker.definition.name} pour 100 PV et réduit son {STYLE_LABELS.get(style, style)} de 35 % pendant 2 tours.")

        # Torune contamine tout attaquant qui le touche en Taijutsu.
        if original_target is not None and original_target.definition.id == "torune" and style == "taijutsu" and not outcome.immune and self._is_alive_instance(attacker):
            body = self._effect_carrier(attacker)
            body.torune_contact_poison = max(body.torune_contact_poison, 50)
            self.log_event(f"Nano-insectes toxiques : {attacker.definition.name} perdra 50 PV par tour jusqu'à sa mort.")

        # Tsukuyomi d'Itachi se déclenche quand Itachi reçoit vraiment des dégâts de PV.
        if original_target is not None and original_target.definition.id == "itachi" and outcome.hp_damage > 0 and not outcome.killed:
            if attacker.definition.id not in {"killer_bee", "madara"}:
                affected_attacker = self._effect_carrier(attacker)
                affected_attacker.disabled_turns = max(affected_attacker.disabled_turns, 2)
                loc = self._find_instance(attacker)
                if loc:
                    self.emit_visual("stun_apply", player=loc[0], slot=loc[1], label="TSUKUYOMI")
                self.emit_visual("passive_audio", card_id="itachi")
                self.log_event(f"Tsukuyomi : {attacker.definition.name} sera inutilisable pendant son prochain tour.")

        # Kakashi copie la première spéciale adverse qui lui inflige des dégâts.
        if (
            is_special
            and original_target is not None
            and original_target.definition.id == "kakashi"
            and outcome.hp_damage > 0
            and not original_target.copied_special_id
            and special_source_id
        ):
            source_def = next((c for c in self.all_definitions() if c.id == special_source_id), None)
            if source_def is not None:
                original_target.copied_special_id = source_def.id
                original_target.copied_special_name = source_def.special_name
                self.log_event(f"Ninja copieur : Kakashi copie {source_def.special_name} !")

    def all_definitions(self) -> list[CardDefinition]:
        seen: dict[str, CardDefinition] = {}
        for player in self.players.values():
            for card in player.deck + player.graveyard:
                seen[card.id] = card
            for instance in player.field:
                if instance is not None:
                    seen[instance.definition.id] = instance.definition
        return list(seen.values())

    def _perform_attack(
        self,
        player_number: int,
        attacker_slot: int,
        style: str,
        defender_slot: int,
        *,
        bonus: int = 0,
        ignore_defense: int = 0,
        bypass_defensive_passives: bool = False,
        ignore_shield: bool = False,
        absolute_bypass: bool = False,
        ignore_guard: bool = False,
        force_advantage: bool = False,
        is_special: bool = False,
        special_source_id: str | None = None,
    ) -> AttackOutcome:
        player = self.player(player_number)
        enemy = self.opponent(player_number)
        attacker = player.field[attacker_slot]
        if attacker is None or defender_slot not in (0, 1, 2) or enemy.field[defender_slot] is None:
            return AttackOutcome()

        # Choji peut devenir la cible réelle avant le calcul des statistiques.
        # Trancheur de Mifune ignore explicitement l'interception de Choji.
        if attacker.definition.id == "mifune" and style == "taijutsu":
            ignore_guard = True
        actual_slot = defender_slot if ignore_guard else self._guard_slot(enemy.number, defender_slot)
        defender = enemy.field[actual_slot]
        if defender is None:
            return AttackOutcome()
        if actual_slot != defender_slot:
            self.log_event(f"Expansion Akimichi : Choji intercepte l'attaque destinée à {enemy.field[defender_slot].definition.name}.")

        # Doute et certitude d'Omoi : 1/3 la frappe est oubliée ; sinon +20 % dégâts finaux.
        omoi_multiplier = 1.0
        if attacker.definition.id == "omoi":
            if self.random.random() < (1.0 / 3.0):
                self.log_event(f"Doute et certitude : Omoi oublie de frapper {defender.definition.name} !")
                self.emit_visual("attack", from_player=player_number, from_slot=attacker_slot, to_player=enemy.number, to_slot=actual_slot, advantage=False, damage=0, style=style, special=bool(is_special), immune=True)
                return AttackOutcome(target_slot=actual_slot, immune=True)
            omoi_multiplier = 1.20
            self.log_event("Doute et certitude : Omoi se décide — dégâts +20 %.")

        # 1.2.1 — Kamui offensif détruit réellement les boucliers de la cible
        # effective (après une éventuelle interception de Choji), au lieu de
        # seulement les ignorer pendant le calcul des dégâts.
        if is_special and special_source_id == "obito":
            body = self._effect_carrier(defender)
            removed = max(0, int(body.shield or 0)) + max(0, int(getattr(body, "kurenai_hidden_shield", 0) or 0))
            body.shield = 0
            body.kurenai_hidden_shield = 0
            if removed:
                self.log_event(f"Kamui offensif : {removed} points de bouclier sont supprimés.")

        # 1.1.7 — contre-switch : uniquement après une entrée VOLONTAIRE via switch.
        if defender.switch_counter_armed:
            defender.switch_counter_armed = False
            yamato_gift = bool(getattr(defender, "yamato_counter_gift", False))
            defender.yamato_counter_gift = False
            cid = defender.definition.id
            if cid == "itachi":
                if attacker.definition.id not in {"killer_bee", "madara"}:
                    body = self._effect_carrier(attacker)
                    body.disabled_turns = max(body.disabled_turns, 2)
                self.log_event(f"Contre-switch — Tsukuyomi : Itachi annule l'attaque de {attacker.definition.name} et applique son Genjutsu.")
            elif cid == "sasuke":
                self._arm_sasuke_lock(defender, attacker, style)
                self.log_event(f"Contre-switch — Sharingan : Sasuke annule l'attaque de {attacker.definition.name} et verrouille immédiatement son {STYLE_LABELS.get(style, style)}.")
            elif cid == "kakashi":
                if is_special and special_source_id and not defender.copied_special_id:
                    source_def = next((c for c in self.all_definitions() if c.id == special_source_id), None)
                    if source_def is not None:
                        defender.copied_special_id = source_def.id
                        defender.copied_special_name = source_def.special_name
                self.log_event(f"Contre-switch — Permutation : Kakashi annule complètement l'attaque de {attacker.definition.name}.")
            elif yamato_gift:
                self.log_event(f"Relais protecteur — Counter-Switch transmis par Yamato : {defender.definition.name} annule complètement la première attaque de {attacker.definition.name}.")
            self.emit_visual("attack", from_player=player_number, from_slot=attacker_slot, to_player=enemy.number, to_slot=actual_slot, advantage=False, damage=0, style=style, special=bool(is_special), immune=True)
            return AttackOutcome(target_slot=actual_slot, immune=True)

        # Madara ignore les techniques spéciales de Genjutsu avant leurs effets.
        if is_special and style == "genjutsu" and defender.definition.id == "madara" and not bypass_defensive_passives:
            self.log_event("Mangekyô éternel : Madara ignore la technique spéciale de Genjutsu.")
            return AttackOutcome(target_slot=actual_slot, immune=True)

        atk = self.effective_stat(attacker, style, defender) + bonus
        if attacker.definition.id == "chojuro":
            swing = 200 if self.random.random() < 0.50 else -200
            atk = max(0, atk + swing)
            self.log_event(f"Incertitudes : Chôjûrô {'gagne' if swing > 0 else 'perd'} 200 {STYLE_LABELS.get(style, style)} pour cette frappe.")
        defense = max(0, self.effective_stat(defender, style, attacker) - ignore_defense)
        # Si la stat d'attaque ne dépasse pas du tout la même stat adverse,
        # on laisse ici 0 : le cœur de dégâts appliquera le secours par étoiles
        # après les réductions défensives, juste avant les boucliers.
        diff = atk - defense
        damage = max(100, diff) if diff > 0 else 0

        advantage = force_advantage or self.element_advantage(
            self._combat_definition(attacker), self._combat_definition(defender)
        )
        # Temari gagne +100 Ninjutsu lorsque l'avantage élémentaire n'est pas présent.
        if attacker.definition.id == "temari" and style == "ninjutsu" and not advantage:
            atk += 100
            diff = atk - defense
            damage = max(100, diff) if diff > 0 else 0
        if advantage and damage > 0:
            damage = int(round(damage * 1.10)) + 150
        if special_source_id == "jugo":
            roll = "femme" if self.random.random() < 0.50 else "homme"
            target_gender = "femme" if self._combat_definition(defender).id in FEMALE_CARD_IDS else "homme"
            mult = 1.50 if roll == target_gender else 0.50
            if damage > 0:
                damage = max(1, int(round(damage * mult)))
            self.log_event(f"Furie de Jûgo : tirage {roll.upper()} — cible {target_gender}; dégâts x{mult:g}.")

        # Lame du samouraï : le bonus 500/750 est FIXE et s'ajoute après le
        # calcul Taijutsu/élément. Le test défensif est fait avant que Trancheur
        # ne détruise les boucliers.
        if special_source_id == "mifune":
            body = self._effect_carrier(defender)
            defensive_ids = {"nagato","sasuke","gaara","a_raikage","sasori","suigetsu","kurenai","kankuro","chiyo","tobirama","onoki","danzo","orochimaru","hidan","kakuzu","haku","shisui","konohamaru","choji"}
            defended = bool(int(body.shield or 0) > 0 or int(getattr(body, "kurenai_hidden_shield", 0) or 0) > 0 or body.definition.id in defensive_ids)
            damage += 750 if defended else 500

        if omoi_multiplier != 1.0 and damage > 0:
            damage = max(1, int(round(damage * omoi_multiplier)))

        # Minato ignore tous les passifs défensifs, même avec une attaque normale.
        if attacker.definition.id == "minato":
            bypass_defensive_passives = True
        # Kabuto ignore 150 de défense sur toutes ses attaques.
        if attacker.definition.id == "kabuto" and ignore_defense < 150:
            extra = 150 - ignore_defense
            defense = max(0, defense - extra)
            diff = atk - defense
            damage = max(100, diff) if diff > 0 else 0
            if advantage and damage > 0:
                damage = int(round(damage * 1.10)) + 150
        if attacker.definition.id == "tobirama" and style == "ninjutsu" and ignore_defense < 100:
            extra = 100 - ignore_defense
            defense = max(0, defense - extra)
            diff = atk - defense
            damage = max(100, diff) if diff > 0 else 0
            if advantage and damage > 0:
                damage = int(round(damage * 1.10)) + 150

        enemy_player_hp_before = enemy.hp
        hp_damage, killed, immune = self._deal_damage(
            enemy.number,
            actual_slot,
            damage,
            attacker=attacker,
            style=style,
            is_attack=True,
            is_special=is_special,
            bypass_defensive_passives=bypass_defensive_passives,
            ignore_shield=ignore_shield,
            absolute_bypass=absolute_bypass,
            allow_guard=False,
        )
        if (
            not immune
            and not absolute_bypass
            and defender.definition.id == "sasuke"
            and self._is_alive_instance(defender)
        ):
            self._arm_sasuke_lock(defender, attacker, style)
        overflow_damage = max(0, enemy_player_hp_before - enemy.hp)
        outcome = AttackOutcome(
            # damage = dégâts réellement passés sur les PV de la carte.
            damage=max(0, hp_damage), hp_damage=hp_damage, overflow_damage=overflow_damage, advantage=advantage,
            atk=atk, defense=defense, target_slot=actual_slot, killed=killed, immune=immune,
        )
        self.emit_visual(
            "attack",
            from_player=player_number, from_slot=attacker_slot,
            to_player=enemy.number, to_slot=actual_slot,
            advantage=bool(advantage), damage=max(0, hp_damage),
            style=style, special=bool(is_special), immune=bool(immune),
        )
        self._post_normal_attack_passives(
            player_number, attacker_slot, enemy.number, outcome, style,
            is_special=is_special, special_source_id=special_source_id,
        )
        return outcome

    def _apply_a3_raikage_recoil(self, player_number: int, attacker_slot: int, dealt: int):
        """Le 3e Raikage subit 20 % des dégâts qu'il vient d'infliger."""
        if dealt <= 0:
            return
        attacker = self.player(player_number).field[attacker_slot] if attacker_slot in (0, 1, 2) else None
        if attacker is None or attacker.definition.id != "a3_raikage" or int(attacker.current_hp or 0) <= 0:
            return
        recoil = max(1, int(round(dealt * 0.20)))
        self.log_event(f"Contrecoup foudroyant : A subit {recoil} PV, soit 20 % des dégâts infligés.")
        self._deal_damage(
            player_number, attacker_slot, recoil, attacker=None, style=None,
            is_attack=False, is_special=False, ignore_shield=True, allow_guard=False,
            label="Contrecoup foudroyant",
        )

    def attack(
        self,
        player_number: int,
        attacker_slot: int,
        style: str,
        defender_slot: int | None = None,
        *,
        minato_free_override: bool | None = None,
    ) -> tuple[bool, str]:
        if self.winner is not None:
            return False, "Le duel est terminé."
        if self.pending_replacement is not None:
            return False, "Un remplacement doit d'abord être choisi."
        if player_number != self.active_player and not self._resolving_delayed_action:
            return False, "Ce n'est pas ton tour."
        if attacker_slot not in (0, 1, 2):
            return False, "Attaquant invalide."
        attacker = self.player(player_number).field[attacker_slot]
        if attacker is None:
            return False, "Il n'y a aucun Ninja ici."
        style = style.lower()
        if style not in STYLE_LABELS:
            return False, "Type d'attaque inconnu."
        auto_minato_free = attacker.definition.id == "minato" and not attacker.minato_free_attack_used
        if minato_free_override is True:
            if attacker.definition.id != "minato":
                return False, "L'action gratuite Hiraishin est réservée à Minato."
            if attacker.minato_free_attack_used:
                return False, "L'action gratuite Hiraishin de Minato a déjà été utilisée ce tour."
            minato_free = True
        elif minato_free_override is False:
            # Classic 1.1.3 : une attaque normale de Minato placée en Action 1/2
            # doit réellement consommer cette action. Hiraishin n'est plus choisi
            # automatiquement par le moteur : le joueur décide explicitement.
            minato_free = False
        else:
            # Compatibilité avec les anciens appels/réseaux : sans indication, on
            # conserve l'ancien comportement automatique.
            minato_free = auto_minato_free
        if self.offensive_action_slots_left() <= 0 and not minato_free:
            return False, "Les 2 actions offensives de ce tour ont déjà été utilisées."
        if self.normal_attacks_used >= 2 and not minato_free:
            return False, "Les 2 attaques normales de ce tour ont déjà été utilisées."
        if attacker.has_attacked and not minato_free:
            return False, f"{attacker.definition.name} a déjà effectué son attaque normale ce tour. Choisis un autre Ninja."
        if not self.can_use_style(attacker, style):
            if self.is_disabled(attacker):
                return False, f"{attacker.definition.name} est actuellement inutilisable."
            state = self._effect_carrier(attacker)
            if state.blocked_styles.get(style, 0) > 0:
                return False, f"{attacker.definition.name} ne peut pas utiliser {STYLE_LABELS[style]} ce tour."
            if self.effective_stat(attacker, style) <= 0:
                return False, f"{attacker.definition.name} possède 0 en {STYLE_LABELS[style]} et ne peut pas utiliser cet art."
            return False, "Aucune attaque normale n'est disponible avec cet art."

        enemy = self.opponent(player_number)
        enemy_has_ninja = any(card is not None for card in enemy.field)
        if defender_slot is None:
            if enemy_has_ninja:
                return False, "Il faut d'abord cibler un Ninja adverse."
            stat = self.effective_stat(attacker, style)
            damage = max(100, stat // 2)
            enemy.hp = max(0, enemy.hp - damage)
            if minato_free:
                attacker.minato_free_attack_used = True
                self.emit_visual("passive_audio", card_id="minato")
                self.log_event("Hiraishin : l'attaque de Minato est gratuite.")
            else:
                self.normal_attacks_used += 1
                attacker.has_attacked = True
            self._mark_attack_usage(attacker, style)
            if attacker.definition.id == "kisame" and style == "ninjutsu":
                self._heal(attacker, 100)
            self.log_event(f"{attacker.definition.name} attaque directement en {STYLE_LABELS[style]} : -{damage} PV à J{enemy.number}.")
            if attacker.definition.id == "a3_raikage":
                self._apply_a3_raikage_recoil(player_number, attacker_slot, damage)
            if enemy.hp <= 0:
                self.winner = player_number
                self.log_event(f"J{player_number} remporte le duel !")
            return True, f"Attaque directe : {damage} dégâts."

        if defender_slot not in (0, 1, 2) or enemy.field[defender_slot] is None:
            return False, "Cible invalide."

        outcome = self._perform_attack(player_number, attacker_slot, style, defender_slot)
        attacker = self.player(player_number).field[attacker_slot]
        if attacker is not None:
            if minato_free:
                attacker.minato_free_attack_used = True
                self.emit_visual("passive_audio", card_id="minato")
                self.log_event("Hiraishin : l'attaque de Minato est gratuite.")
            else:
                self.normal_attacks_used += 1
                attacker.has_attacked = True
            self._mark_attack_usage(attacker, style)
        if attacker is not None and attacker.definition.id == "a3_raikage" and not outcome.immune:
            self._apply_a3_raikage_recoil(player_number, attacker_slot, outcome.damage + outcome.overflow_damage)
        bonus = " + avantage élémentaire" if outcome.advantage else ""
        if outcome.immune:
            msg = "Attaque annulée par un effet défensif."
        else:
            overflow_txt = f" + {outcome.overflow_damage} dégâts de surplus à J{enemy.number}" if outcome.overflow_damage else ""
            msg = f"{outcome.damage} dégâts{bonus}{overflow_txt}."
        self.log_event(
            f"{self.player(player_number).field[attacker_slot].definition.name if self.player(player_number).field[attacker_slot] else 'Le Ninja'} "
            f"attaque en {STYLE_LABELS[style]} : {msg}"
        )
        return True, msg

    # ------------------------------------------------------------------
    # Techniques spéciales
    # ------------------------------------------------------------------
    def _consume_special(self, attacker: CardInstance, copied: bool):
        if copied:
            attacker.copied_special_used = True
        else:
            if attacker.definition.id != "chojuro":
                attacker.special_used = True
            if attacker.definition.id == "ino":
                attacker.ino_special_cooldown = 3
            if attacker.definition.id == "shikamaru":
                attacker.shikamaru_special_cooldown = 4
        self.special_attack_used = True
        # IMPORTANT : une spéciale ne consomme PAS l'attaque normale personnelle
        # de ce Ninja. Il peut donc faire spéciale + normale dans le même tour.

    def steal_from_enemy_graveyard(
        self,
        player_number: int,
        attacker_slot: int,
        grave_index: int,
        *,
        copied: bool = False,
    ) -> tuple[bool, str]:
        if self.winner is not None:
            return False, "Le duel est terminé."
        if self.pending_replacement is not None:
            return False, "Un remplacement doit d'abord être choisi."
        if player_number != self.active_player and not self._resolving_delayed_action:
            return False, "Ce n'est pas ton tour."
        if attacker_slot not in (0, 1, 2):
            return False, "Attaquant invalide."
        attacker = self.player(player_number).field[attacker_slot]
        if attacker is None:
            return False, "Il n'y a aucun Ninja ici."
        if self.special_attack_used:
            return False, "La technique spéciale de ce tour a déjà été utilisée."
        if self.offensive_action_slots_left() <= 0:
            return False, "Les 2 actions offensives de ce tour ont déjà été utilisées."
        if not self.special_available(attacker, copied=copied):
            return False, "Cette technique spéciale n'est pas disponible."
        special_id = attacker.copied_special_id if copied else attacker.definition.id
        if special_id != "orochimaru":
            return False, "Cette méthode est réservée à Réincarnation des âmes."
        enemy = self.opponent(player_number)
        if grave_index < 0 or grave_index >= len(enemy.graveyard):
            return False, "Carte de cimetière invalide."
        stolen = enemy.graveyard.pop(grave_index)
        self.player(player_number).deck.append(stolen)
        self.random.shuffle(self.player(player_number).deck)
        self._consume_special(attacker, copied)
        self.log_event(f"Réincarnation des âmes : {stolen.name} est volé au cimetière adverse et rejoint la réserve.")
        return True, f"{stolen.name} rejoint ta réserve cachée."

    def use_special(
        self,
        player_number: int,
        attacker_slot: int,
        defender_slot: int | None = None,
        *,
        copied: bool = False,
    ) -> tuple[bool, str]:
        if self.winner is not None:
            return False, "Le duel est terminé."
        if self.pending_replacement is not None:
            return False, "Un remplacement doit d'abord être choisi."
        if player_number != self.active_player and not self._resolving_delayed_action:
            return False, "Ce n'est pas ton tour."
        if attacker_slot not in (0, 1, 2):
            return False, "Attaquant invalide."
        attacker = self.player(player_number).field[attacker_slot]
        if attacker is None:
            return False, "Il n'y a aucun Ninja ici."
        if self.special_attack_used:
            return False, "La technique spéciale de ce tour a déjà été utilisée."
        if self.offensive_action_slots_left() <= 0:
            return False, "Les 2 actions offensives de ce tour ont déjà été utilisées."
        if not self.special_available(attacker, copied=copied):
            return False, "Cette technique spéciale n'est pas disponible."

        special_id = attacker.copied_special_id if copied else attacker.definition.id
        if not special_id:
            return False, "Aucune technique spéciale à utiliser."
        source_def = next((c for c in self.all_definitions() if c.id == special_id), None)
        special_name = attacker.copied_special_name if copied else attacker.definition.special_name

        # Ao anticipe toute technique spéciale adverse AVANT sa résolution.
        # Une riposte létale annule la spéciale sans la consommer comme attaque normale d'Ao.
        opposing_player = self.opponent_number(player_number)
        ao_entry = next(((slot, c) for slot, c in enumerate(self.player(opposing_player).field) if c is not None and c.definition.id == "ao" and int(c.current_hp or 0) > 0), None)
        if ao_entry is not None and attacker.definition.id != "ao":
            ao_slot, ao = ao_entry
            self.log_event(f"Anticipation du Byakugan : Ao riposte à {attacker.definition.name} avant {special_name}.")
            out = self._perform_attack(opposing_player, ao_slot, "taijutsu", attacker_slot, is_special=False)
            if self.player(player_number).field[attacker_slot] is None or int(attacker.current_hp or 0) <= 0:
                self._consume_special(attacker, copied)
                self.log_event(f"{special_name} est annulée : son lanceur a été mis K.O. par Ao.")
                return True, f"Ao met le lanceur K.O. : {special_name} est annulée."

        requires_target = self.special_requires_target_id(special_id)
        enemy = self.opponent(player_number)
        ally_target = self.special_targets_ally_id(special_id)
        if requires_target:
            target_side = self.player(player_number) if ally_target else enemy
            if defender_slot not in (0, 1, 2) or target_side.field[defender_slot] is None:
                return False, f"{special_name} nécessite une cible alliée." if ally_target else f"{special_name} nécessite une cible ennemie."
            if ally_target and target_side.field[defender_slot] is attacker and special_id in {"karin", "rock_lee"}:
                return False, "Cette technique doit cibler une autre carte alliée."

            target = target_side.field[defender_slot]
            if (not ally_target) and target is not None and target.definition.id == "madara":
                style = source_def.special_style if source_def is not None else None
                if style == "genjutsu":
                    self._consume_special(attacker, copied)
                    self.log_event(f"Mangekyô éternel : Madara ignore {special_name}.")
                    return True, f"Madara ignore {special_name}."

            # Protection Transfert : Ino et le corps qu'elle possède sont de
            # vraies cibles inciblables pendant la possession. Les techniques
            # déjà définies comme traversant les passifs défensifs gardent leur
            # comportement (Minato/Obito/Kakashi) et le Chidori absolu de Sasuke
            # traverse évidemment aussi cette protection.
            if (not ally_target) and target is not None:
                ino_locked = (
                    (target.definition.id == "ino" and self._is_alive_instance(target.ino_possession_target))
                    or (
                        target.ino_possessed_by is not None
                        and self._is_alive_instance(target.ino_possessed_by)
                    )
                )
                # Possession des ombres ne touche PAS la carte sélectionnée :
                # elle désigne celle qui reste libre. Une carte protégée par le
                # Transfert d'Ino peut donc servir de cible d'exclusion.
                if ino_locked and special_id not in {"sasuke", "minato", "obito", "kakashi", "shikamaru"}:
                    self._consume_special(attacker, copied)
                    self.log_event(f"Protection Transfert : {target.definition.name} est inciblable, {special_name} échoue.")
                    return True, f"{target.definition.name} est inciblable pendant le Transfert : technique annulée."

                protected_target = self._effect_carrier(target)
                if (not ally_target) and getattr(protected_target, "kurenai_special_protection", False):
                    protected_target.kurenai_special_protection = False
                    self._consume_special(attacker, copied)
                    self.log_event(f"Illusion protectrice : {target.definition.name} annule {special_name}.")
                    return True, f"Illusion protectrice : {target.definition.name} annule complètement {special_name}."

        # Spéciale de Rock Lee : buff permanent sur une autre carte alliée.
        if special_id == "rock_lee":
            ally = self.player(player_number).field[defender_slot] if defender_slot in (0, 1, 2) else None
            if ally is None:
                return False, "Tenue de combat nécessite une carte alliée."
            if ally is attacker:
                return False, "Rock Lee doit donner la tenue de combat à une autre carte alliée."
            ally = self._effect_carrier(ally)
            ally.permanent_buffs["taijutsu"] += 300
            self._consume_special(attacker, copied)
            self.log_event(f"Tenue de combat : {ally.definition.name} gagne définitivement +300 Taijutsu.")
            return True, f"{ally.definition.name} gagne définitivement +300 Taijutsu."

        if special_id == "kurenai":
            ally = self.player(player_number).field[defender_slot] if defender_slot in (0, 1, 2) else None
            if ally is None:
                return False, "Illusion protectrice nécessite une carte alliée."
            real_ally = self._effect_carrier(ally)
            removed = self._cleanse_negative_effects(real_ally)
            real_ally.kurenai_special_protection = True
            real_ally.kurenai_hidden_shield = 600
            self._consume_special(attacker, copied)
            removed_text = ", ".join(removed) if removed else "aucun effet négatif à dissiper"
            self.log_event(
                f"Illusion protectrice : {real_ally.definition.name} est purifié ({removed_text}), annule la prochaine spéciale ennemie qui le cible et reçoit un bouclier caché de 600 PV."
            )
            return True, f"{real_ally.definition.name} est protégé : dissipation, prochaine spéciale ennemie ciblée annulée et bouclier caché 600 PV."

        # Nouveaux Ninjas 1.1.7.
        if special_id == "ao":
            self._consume_special(attacker, copied)
            self.log_event("Byakugan dérobé : Ao désigne la prochaine carte adverse à entrer.")
            return True, "Byakugan dérobé activé."

        if special_id == "torune":
            target = enemy.field[defender_slot] if defender_slot in (0, 1, 2) else None
            if target is None:
                return False, "Microbiose toxique nécessite une cible ennemie."
            body = self._effect_carrier(target)
            body.torune_micro_poison = max(body.torune_micro_poison, 100)
            self._consume_special(attacker, copied)
            self.log_event(f"Microbiose toxique : {target.definition.name} perdra 100 PV par tour jusqu'à sa mort.")
            return True, f"{target.definition.name} est contaminé par Microbiose toxique."

        # Targetless / persistent specials.
        if special_id == "gaara":
            for ally in self.player(player_number).field:
                if ally is not None:
                    self._add_shield(ally, 600)
            self._consume_special(attacker, copied)
            self.log_event("Mur de sable : +600 de bouclier à toutes les cartes alliées.")
            return True, "Toutes les cartes alliées gagnent 600 de bouclier."

        if special_id == "orochimaru":
            if not enemy.graveyard:
                return False, "Le cimetière ennemi est vide : Réincarnation des âmes ne peut pas être utilisée."
            # Fallback moteur (IA ou appel direct) : prend la carte la plus précieuse.
            best_index = max(
                range(len(enemy.graveyard)),
                key=lambda i: (
                    enemy.graveyard[i].stars,
                    enemy.graveyard[i].max_hp + enemy.graveyard[i].taijutsu + enemy.graveyard[i].ninjutsu + enemy.graveyard[i].genjutsu,
                    enemy.graveyard[i].name,
                ),
            )
            return self.steal_from_enemy_graveyard(player_number, attacker_slot, best_index, copied=copied)

        if special_id == "choji":
            attacker.choji_pill_turns = 3
            attacker.choji_pill_started_turn = self.turn
            self._consume_special(attacker, copied)
            self.log_event("Pilule de combat : Choji gagne +500 Taijutsu pendant 3 de ses tours.")
            return True, "Choji gagne +500 Taijutsu pendant 3 tours."

        if special_id == "kankuro":
            attacker.kankuro_defense_active = True
            self._consume_special(attacker, copied)
            self.log_event("Défense marionnettiste : les autres alliés subissent 250 dégâts de moins.")
            return True, "Défense marionnettiste activée."

        if special_id == "chiyo":
            attacker.permanent_buffs["taijutsu"] += 250
            attacker.chiyo_puppets_active = True
            self._consume_special(attacker, copied)
            self.log_event("Les dix marionnettes : Chiyo gagne +250 Taijutsu et réduit de 20 % les dégâts reçus par ses autres alliés tant qu'elle reste sur le terrain.")
            return True, "Chiyo gagne +250 Taijutsu ; ses autres alliés subissent désormais 20 % de dégâts en moins tant qu'elle reste en vie."

        if special_id == "jiraiya":
            # Mode ermite : transformation permanente, sans cible et sans attaque.
            # Une copie de la technique reproduit bien les bonus, mais seul le
            # véritable Jiraiya possède l'illustration alternative dédiée.
            attacker.jiraiya_sage_active = True
            attacker.permanent_buffs["taijutsu"] += 100
            attacker.permanent_buffs["ninjutsu"] += 100
            attacker.permanent_buffs["genjutsu"] += 200
            self._consume_special(attacker, copied)
            self.log_event(
                f"Mode ermite : {attacker.definition.name} gagne définitivement "
                "+100 Taijutsu / +100 Ninjutsu / +200 Genjutsu."
            )
            return True, "Mode ermite activé : +100 Taijutsu / +100 Ninjutsu / +200 Genjutsu."

        if special_id == "gengetsu":
            if attacker.gengetsu_clone_active:
                return False, "Le clone aqueux explosif est déjà actif."
            attacker.gengetsu_saved_hp = int(attacker.current_hp or attacker.definition.max_hp)
            attacker.gengetsu_saved_shield = int(attacker.shield)
            attacker.gengetsu_clone_active = True
            attacker.gengetsu_clone_turns_left = 2
            attacker.current_hp = 4800
            attacker.shield = 0
            self._consume_special(attacker, copied)
            self.log_event(
                "Clone aqueux explosif activé : 4800 PV, 0 dans tous les arts, explosion dans 2 tours du propriétaire."
            )
            return True, "Clone explosif activé : 4800 PV, 0/0/0. Explosion dans 2 de tes tours."

        if special_id == "tobirama":
            total = 0
            for slot, target in list(enumerate(enemy.field)):
                if target is not None:
                    dealt, _ = self._deal_fixed_damage(enemy.number, slot, 650, source=attacker, label="Parchemins scalaires")
                    total += dealt
            self._consume_special(attacker, copied)
            self.log_event(f"Parchemins scalaires : 650 PV fixes infligés à chaque carte ennemie ({total} PV au total).")
            return True, "Toutes les cartes ennemies subissent 650 PV."

        if special_id == "shisui":
            affected = 0
            for slot, target in enumerate(enemy.field):
                if target is None:
                    continue
                # Killer Bee conserve son passif : il ne peut pas perdre son tour.
                if target.definition.id in {"killer_bee", "madara"}:
                    if target.definition.id == "killer_bee":
                        self.log_event("Jinchûriki parfait : Killer Bee résiste au Genjutsu de Shisui.")
                    else:
                        self.log_event("Mangekyô éternel : Madara ignore le STUN de Shisui.")
                    continue
                affected_target = self._effect_carrier(target)
                affected_target.disabled_turns = max(affected_target.disabled_turns, 2)
                affected += 1
                loc = self._find_instance(target)
                if loc:
                    self.emit_visual("stun_apply", player=loc[0], slot=loc[1], label="GENJUTSU")
            self._consume_special(attacker, copied)
            self.log_event(f"Genjutsu : {affected} carte(s) ennemie(s) sont étourdies pendant 2 tours.")
            return True, "Toutes les cartes ennemies vulnérables sont étourdies pendant 2 de leurs tours."

        if special_id == "konohamaru":
            attacker.konohamaru_sexy_turns = 2
            attacker.konohamaru_sexy_started_turn = self.turn
            if copied:
                self._consume_special(attacker, copied)
            else:
                self.special_attack_used = True
                attacker.konohamaru_sexy_cooldown = 4
            self.log_event("Sexy Jutsu : transformation pour 2 tours. Les Ninjas masculins ne peuvent plus le toucher ; les Ninjas féminins infligent x2 dégâts.")
            return True, "Sexy Jutsu actif pendant 2 tours. Réutilisable dans 4 de tes tours."

        # Les autres spéciales utilisent une cible, sauf les nouvelles techniques sans cible.
        if defender_slot is None and special_id not in {"kimimaro", "konan", "kurotsuchi", "anko", "tenten"}:
            return False, "Cette technique spéciale nécessite une cible."

        if special_id == "karin":
            target = self.player(player_number).field[defender_slot]
            if target is None or target is attacker:
                return False, "Karin doit cibler une autre carte alliée."
            healed = self._heal(target, target.definition.max_hp)
            if copied:
                self._consume_special(attacker, copied)
            else:
                self.special_attack_used = True
                attacker.karin_special_cooldown = 3
            attacker.current_hp = max(0, int(attacker.current_hp or 0) - 1000)
            self.log_event(f"Morsure revigorante : {target.definition.name} est totalement soigné (+{healed}) ; Karin perd 1000 PV.")
            if int(attacker.current_hp or 0) <= 0:
                self._check_ko(player_number, attacker_slot, source=attacker, suppress_survival=False)
            return True, f"{target.definition.name} est totalement soigné. Karin perd 1000 PV."

        if special_id == "sai":
            target = enemy.field[defender_slot]
            if target is None:
                return False, "Cible invalide."
            if target.definition.id in {"killer_bee", "madara"}:
                self._consume_special(attacker, copied)
                if target.definition.id == "killer_bee":
                    self.log_event("Jinchûriki parfait : Killer Bee résiste à la toile au monstre fantomatique.")
                else:
                    self.log_event("Mangekyô éternel : Madara ignore l'emprisonnement de Sai.")
                return True, f"{target.definition.name} est immunisé à l'emprisonnement."
            affected_target = self._effect_carrier(target)
            affected_target.disabled_turns = max(affected_target.disabled_turns, 3)
            loc = self._find_instance(target)
            if loc:
                self.emit_visual("stun_apply", player=loc[0], slot=loc[1], label="ENCRE")
            self._consume_special(attacker, copied)
            self.log_event(f"Toile au monstre fantomatique : {target.definition.name} est emprisonné pendant 3 tours.")
            return True, f"{target.definition.name} est emprisonné pendant 3 tours."

        if special_id == "haku":
            target = enemy.field[defender_slot]
            if target is None:
                return False, "Cible invalide."
            self._consume_special(attacker, copied)
            if target.definition.id in {"killer_bee", "madara"}:
                if target.definition.id == "killer_bee":
                    self.log_event("Jinchûriki parfait : Killer Bee résiste à la Prison de glace de Haku.")
                else:
                    self.log_event("Mangekyô éternel : Madara ignore la Prison de glace de Haku.")
                return True, f"{target.definition.name} est immunisé à la Prison de glace."
            affected_target = self._effect_carrier(target)
            affected_target.haku_ice_prison_turns = max(affected_target.haku_ice_prison_turns, 3)
            affected_target.disabled_turns = max(affected_target.disabled_turns, 3)
            loc = self._find_instance(target)
            if loc:
                self.emit_visual("stun_apply", player=loc[0], slot=loc[1], label="GLACE")
            self.log_event(f"Prison de glace : {target.definition.name} est enfermé pendant 3 tours et subira 200 PV par tour.")
            return True, f"{target.definition.name} est emprisonné dans la glace pendant 3 tours."

        if special_id == "danzo":
            target = enemy.field[defender_slot]
            if target is None:
                return False, "Cible invalide."
            affected_target = self._effect_carrier(target)
            affected_target.current_hp = max(1, min(int(affected_target.current_hp or 1), 1))
            self._consume_special(attacker, copied)
            attacker.current_hp = 0
            self.log_event(f"Kamikaze : {target.definition.name} tombe à 1 PV et Danzo se sacrifie.")
            # Le sacrifice ignore Izanagi.
            self._check_ko(player_number, attacker_slot, source=attacker, suppress_survival=True)
            return True, f"{target.definition.name} est réduit à 1 PV. Danzo est sacrifié."

        if special_id == "kisame":
            target = enemy.field[defender_slot]
            if target is None:
                return False, "Cible invalide."
            self._consume_special(attacker, copied)
            if target.definition.id in {"killer_bee", "madara"}:
                if target.definition.id == "killer_bee":
                    self.log_event("Jinchûriki parfait : Killer Bee résiste à la Prison aqueuse.")
                else:
                    self.log_event("Mangekyô éternel : Madara ignore la Prison aqueuse de Kisame.")
                return True, f"{target.definition.name} est immunisé à la Prison aqueuse."
            affected_target = self._effect_carrier(target)
            affected_target.prisoned_by = attacker
            loc = self._find_instance(target)
            if loc:
                self.emit_visual("stun_apply", player=loc[0], slot=loc[1], label="PRISON")
            self.log_event(f"Prison aqueuse : {target.definition.name} est bloqué tant que Kisame reste en vie.")
            return True, f"{target.definition.name} est emprisonné."

        if special_id == "hidan":
            target = enemy.field[defender_slot]
            if target is None:
                return False, "Cible invalide."
            self._consume_special(attacker, copied)
            affected_target = self._effect_carrier(target)
            affected_target.doom_turns = 5
            affected_target.doom_source = attacker
            self.log_event(f"Rituel de Jashin : {target.definition.name} est condamné dans 5 tours.")
            return True, f"{target.definition.name} est condamné dans 5 tours si Hidan survit."

        if special_id == "shikamaru":
            self._consume_special(attacker, copied)
            for slot, target in enumerate(enemy.field):
                if target is None or slot == defender_slot or target.definition.id == "killer_bee":
                    continue
                self._apply_shadow_stun(target, attacker, 3)
                loc = self._find_instance(target)
                if loc:
                    self.emit_visual("stun_apply", player=loc[0], slot=loc[1], label="STUN")
            self.log_event("Possession des ombres : les autres cartes ennemies sont bloquées 3 tours. Recharge 4 tours. Si Shikamaru subit des dégâts, ses STUN cessent immédiatement.")
            return True, "Les autres Ninjas ennemis sont bloqués 3 tours. Recharge : 4 tours ; tout dégât subi par Shikamaru brise l'effet."

        if special_id == "a3_raikage":
            target = enemy.field[defender_slot]
            if target is None:
                return False, "Cible invalide."
            amount = max(1, (int(target.current_hp or 0) + 1) // 2)
            hp_before = int(target.current_hp or 0)
            hp_damage, killed, immune = self._deal_damage(
                enemy.number, defender_slot, amount, attacker=attacker, style="taijutsu",
                is_attack=True, is_special=True, ignore_shield=True, allow_guard=True,
                label="Technique à un doigt",
            )
            self._consume_special(attacker, copied)
            self._mark_attack_usage(attacker, "taijutsu")
            if immune:
                self.log_event("Technique à un doigt : la cible évite ou annule la technique.")
                return True, "La cible évite la Technique à un doigt."
            self.log_event(f"Technique à un doigt : {target.definition.name} perd {hp_damage} PV sur {hp_before}. Aucun contrecoup pour A.")
            return True, f"{target.definition.name} perd {hp_damage} PV (50 % de ses PV actuels)."

        if special_id == "asuma":
            target = enemy.field[defender_slot]
            if target is None:
                return False, "Cible invalide."
            if self._is_untargetable(target):
                self._consume_special(attacker, copied)
                return True, f"{target.definition.name} est inciblable : Kunai lame chakra échoue."
            body = self._effect_carrier(target)
            removed = int(body.shield or 0) + int(getattr(body, "kurenai_hidden_shield", 0) or 0)
            body.shield = 0
            body.kurenai_hidden_shield = 0
            dealt, _ = self._deal_fixed_damage(enemy.number, defender_slot, 400, source=attacker, label="Kunai lame chakra", allow_guard=False)
            self._consume_special(attacker, copied)
            self.log_event(f"Kunai lame chakra : {removed} de bouclier détruit, {dealt} PV infligés.")
            return True, f"Boucliers supprimés et {dealt} PV infligés."

        if special_id == "tenten":
            affected = enemy.number
            already = bool(self.makibishi_active.get(affected, False))
            self.makibishi_active[affected] = True
            self._consume_special(attacker, copied)
            if already:
                self.log_event("Champ de Makibishi : le terrain adverse était déjà couvert de pointes ; l’effet ne se cumule pas.")
                return True, "Le terrain adverse est déjà piégé : aucun cumul."
            self.log_event("Champ de Makibishi : Tenten couvre définitivement le terrain adverse. Chaque nouvelle entrée perdra 7 % de ses PV max.")
            self.emit_visual("stun_apply", player=affected, slot=-1, label="MAKIBISHI")
            return True, "Terrain adverse piégé définitivement : -7 % PV max à chaque entrée."

        if special_id == "zetsu":
            target = enemy.field[defender_slot]
            if target is None:
                return False, "Cible invalide."
            if self._is_untargetable(target):
                self._consume_special(attacker, copied)
                return True, f"{target.definition.name} est inciblable : Embuscade souterraine échoue."
            pending = self.delayed_actions.get(enemy.number)
            intercept = bool(pending and str(pending.get("kind") or "") == "switch" and str(pending.get("outgoing_id") or "") == target.definition.id)
            if intercept:
                self.delayed_actions[enemy.number] = None
                amount = 500
                self.log_event(f"Embuscade souterraine : Zetsu intercepte le Switch A2 de {target.definition.name} — SWITCH ANNULÉ.")
            else:
                amount = 300
            dealt, _ = self._deal_fixed_damage(enemy.number, defender_slot, amount, source=attacker, label="Embuscade souterraine", allow_guard=False)
            self._consume_special(attacker, copied)
            return True, (f"Switch A2 annulé, {dealt} dégâts fixes." if intercept else f"Aucun Switch A2 à intercepter : {dealt} dégâts fixes.")

        if special_id == "yamato":
            target = enemy.field[defender_slot]
            if target is None:
                return False, "Cible invalide."
            if self._is_untargetable(target):
                self._consume_special(attacker, copied)
                return True, f"{target.definition.name} est inciblable : Prison du Mokuton échoue."
            body = self._effect_carrier(target)
            body.rooted_turns = max(int(getattr(body, "rooted_turns", 0) or 0), 3)
            amount = self._percent_hp_amount(body, 0.20)
            dealt, _ = self._deal_fixed_damage(enemy.number, defender_slot, amount, source=attacker, label="Prison du Mokuton", allow_guard=False)
            self._consume_special(attacker, copied)
            self.log_event(f"Prison du Mokuton : {target.definition.name} perd {dealt} PV et est ENRACINÉ 3 tours — aucun Switch volontaire possible.")
            loc = self._find_instance(target)
            if loc: self.emit_visual("stun_apply", player=loc[0], slot=loc[1], label="ENRACINÉ")
            return True, f"{target.definition.name} : -{dealt} PV, ENRACINÉ 3 tours."

        if special_id == "kushina":
            target = enemy.field[defender_slot]
            if target is None:
                return False, "Cible invalide."
            if self._is_untargetable(target):
                self._consume_special(attacker, copied)
                return True, f"{target.definition.name} est inciblable : Scellement Uzumaki échoue."
            body = self._effect_carrier(target)
            if body.definition.id != "madara":
                body.sealed_turns = max(body.sealed_turns, 5)
            amount = self._percent_hp_amount(body, 0.20)
            dealt, _ = self._deal_fixed_damage(enemy.number, defender_slot, amount, source=attacker, label="Scellement Uzumaki", allow_guard=False)
            self._consume_special(attacker, copied)
            if body.definition.id == "madara":
                self.log_event(f"Mangekyô éternel : Madara ignore le SCELLÉ mais subit {dealt} PV du Scellement Uzumaki.")
                return True, f"Madara ignore le SCELLÉ mais perd {dealt} PV."
            self.log_event(f"Scellement Uzumaki : {target.definition.name} est SCELLÉ 5 tours et perd {dealt} PV.")
            loc = self._find_instance(target)
            if loc: self.emit_visual("stun_apply", player=loc[0], slot=loc[1], label="SCELLÉ")
            return True, f"{target.definition.name} : SCELLÉ 5 tours, -{dealt} PV."

        if special_id == "rin":
            target = enemy.field[defender_slot]
            if target is None:
                return False, "Cible invalide."
            if self._is_untargetable(target):
                self._consume_special(attacker, copied)
                return True, f"{target.definition.name} est inciblable : Orbe du démon échoue."
            dealt, _ = self._deal_fixed_damage(enemy.number, defender_slot, 550, source=attacker, label="Orbe du démon", allow_guard=False)
            self._consume_special(attacker, copied)
            return True, f"Orbe du démon inflige {dealt} PV fixes."

        if special_id == "shizune":
            target = enemy.field[defender_slot]
            if target is None:
                return False, "Cible invalide."
            if self._is_untargetable(target):
                self._consume_special(attacker, copied)
                return True, f"{target.definition.name} est inciblable : Aiguilles malicieuses échoue."
            body = self._effect_carrier(target)
            body.shizune_poisoned = True
            if body.definition.id != "madara":
                body.disabled_turns = max(body.disabled_turns, 2)
                msg = f"{target.definition.name} est STUN 2 tours et empoisonné."
            else:
                self.log_event("Mangekyô éternel : Madara ignore le STUN des Aiguilles malicieuses.")
                msg = "Madara ignore le STUN mais reste empoisonné."
            self._consume_special(attacker, copied)
            self.log_event(f"Aiguilles malicieuses : {target.definition.name} est empoisonné à -30 PV/tour jusqu'à sa mort.")
            return True, msg

        if special_id == "kimimaro":
            attacker.kimimaro_fury_active = True
            self._consume_special(attacker, copied)
            self.log_event("Vieux os : Kimimaro entre en furie (+15 % aux trois arts, -10 % PV max par tour).")
            return True, "Kimimaro entre définitivement en furie."

        if special_id == "chojuro":
            stock = max(0, int(attacker.chojuro_chakra_stock or 0))
            outcome = self._perform_attack(player_number, attacker_slot, "taijutsu", defender_slot, bonus=stock, is_special=True, special_source_id="chojuro")
            attacker.chojuro_chakra_stock = 0
            self._consume_special(attacker, copied)
            self._mark_attack_usage(attacker, "taijutsu")
            self.log_event(f"Hiramekarei libère {stock} points de chakra : {outcome.damage} dégâts.")
            return True, f"Hiramekarei libère {stock} de stock et inflige {outcome.damage} dégâts."

        if special_id == "konan":
            attacker.konan_mine_active = True
            self._consume_special(attacker, copied)
            self.log_event("Carte explosive : Konan active le minage. Les pièges ne s'appliquent que pendant ses tours ciblables.")
            return True, "Le terrain de Konan est désormais miné pendant ses phases ciblables."

        if special_id == "jugo":
            outcome = self._perform_attack(player_number, attacker_slot, "taijutsu", defender_slot, is_special=True, special_source_id="jugo")
            self._consume_special(attacker, copied)
            self._mark_attack_usage(attacker, "taijutsu")
            return True, f"Furie inflige {outcome.damage} dégâts."

        if special_id == "kurotsuchi":
            total = 0
            for ally in self.player(player_number).field:
                if ally is not None and self._is_alive_instance(ally):
                    self._add_shield(ally, 350)
                    total += 1
            self._consume_special(attacker, copied)
            self.log_event(f"Muraille Doton : {total} carte(s) alliée(s) gagnent 350 de bouclier.")
            return True, "Toutes les cartes alliées gagnent 350 de bouclier."

        if special_id == "mu":
            if attacker.mu_division_used:
                return False, "Après Division cellulaire, Mû ne peut plus utiliser son Jinton."
            target = enemy.field[defender_slot]
            if target is None:
                return False, "Cible invalide."
            mu_nin = self.effective_stat(attacker, "ninjutsu", target)
            target_nin = self.effective_stat(target, "ninjutsu", attacker)
            if target_nin < mu_nin:
                affected = self._effect_carrier(target)
                affected.current_hp = 0
                loc = self._find_instance(affected)
                if loc is not None:
                    self._check_ko(loc[0], loc[1], source=attacker, suppress_survival=False)
                result = f"{target.definition.name} tombe à 0 PV."
            else:
                dealt, _ = self._deal_fixed_damage(enemy.number, defender_slot, 1000, source=attacker, label="Détachement du Monde Primitif")
                result = f"{target.definition.name} perd {dealt} PV."
            attacker.permanent_buffs["ninjutsu"] -= 1000
            self._consume_special(attacker, copied)
            self.log_event(f"Jinton de Mû : {result} Mû perd 1000 Ninjutsu.")
            return True, result + " Mû perd 1000 Ninjutsu."

        if special_id == "anko":
            attacker.anko_serpent_armed = True
            self._consume_special(attacker, copied)
            self.log_event("Permutation du serpent : Anko esquivera complètement la prochaine attaque reçue et empoisonnera son attaquant.")
            return True, "Permutation du serpent est prête : prochaine attaque esquivée, poison 100 PV × 4 tours."

        if special_id == "omoi":
            target = enemy.field[defender_slot]
            if target is None:
                return False, "Cible invalide."
            # Si Omoi lance sa propre technique, son passif s'applique aussi.
            amount = 500
            if attacker.definition.id == "omoi":
                if self.random.random() < (1.0 / 3.0):
                    self._consume_special(attacker, copied)
                    self.log_event(f"Doute et certitude : Omoi oublie de frapper {target.definition.name}; Lame foudroyante échoue.")
                    return True, "Omoi oublie sa frappe : aucun dégât ni paralysie."
                amount = 600
                self.log_event("Doute et certitude : Lame foudroyante gagne +20 % de dégâts (600).")
            actual_slot = self._guard_slot(enemy.number, defender_slot)
            dealt, killed, immune = self._deal_damage(
                enemy.number, actual_slot, amount, attacker=attacker, style="ninjutsu",
                is_attack=True, is_special=True, allow_guard=False, label="Lame foudroyante"
            )
            target_now = enemy.field[actual_slot] if actual_slot in (0,1,2) else None
            if not immune and target_now is not None and int(target_now.current_hp or 0) > 0:
                body = self._effect_carrier(target_now)
                if body.definition.id == "madara":
                    self.log_event("Mangekyô éternel : Madara ignore la paralysie de Lame foudroyante.")
                elif body.definition.id == "killer_bee":
                    self.log_event("Jinchûriki parfait : Killer Bee ignore la paralysie de Lame foudroyante.")
                else:
                    body.disabled_turns = max(body.disabled_turns, 1)
                    self.log_event(f"Lame foudroyante : {body.definition.name} est paralysé pendant 1 tour.")
            self._consume_special(attacker, copied)
            return True, f"Lame foudroyante inflige {dealt} dégâts" + ("." if immune else " et tente de paralyser 1 tour.")

        if special_id == "karui":
            target = enemy.field[defender_slot]
            if target is None:
                return False, "Cible invalide."
            actual_slot = self._guard_slot(enemy.number, defender_slot)
            target = enemy.field[actual_slot] or target
            dealt, killed, immune = self._deal_damage(
                enemy.number, actual_slot, 400, attacker=attacker, style="ninjutsu",
                is_attack=True, is_special=True, undodgeable=True, allow_guard=False, label="Frappe Raiton"
            )
            self._consume_special(attacker, copied)
            if immune:
                return True, f"{target.definition.name} est inciblable : Frappe Raiton est annulée."
            return True, f"Frappe Raiton inesquivable inflige {dealt} dégâts."

        if special_id == "hanzo":
            target = enemy.field[defender_slot]
            if target is None:
                return False, "Cible invalide."
            if self._is_untargetable(target):
                self._consume_special(attacker, copied)
                self.log_event(f"Poison de la salamandre : {target.definition.name} est inciblable, la technique échoue.")
                return True, f"{target.definition.name} est inciblable : le poison n'est pas appliqué."
            affected_target = self._effect_carrier(target)
            affected_target.hanzo_poisoned = True
            self._consume_special(attacker, copied)
            loc = self._find_instance(target)
            if loc:
                self.emit_visual("poison_apply", player=loc[0], slot=loc[1], amount=self._percent_hp_amount(target, 0.05))
            self.log_event(
                f"Poison de la salamandre : {target.definition.name} perdra 5 % de ses PV max au début de chacun de ses tours jusqu'à sa mort."
            )
            return True, f"{target.definition.name} est gravement empoisonné : -5 % de PV par tour jusqu'à sa mort."

        if special_id == "ino":
            target = enemy.field[defender_slot]
            if target is None:
                return False, "Cible invalide."
            # La technique d'Ino se recharge tous les 3 de ses tours, qu'elle
            # réussisse ou échoue. La recharge est armée au moment où la
            # technique est réellement consommée.
            # Une cible déjà intouchable ne peut pas recevoir le Transfert.
            if self._is_untargetable(target):
                self._consume_special(attacker, copied)
                self.log_event(f"Transfert de l'esprit : {target.definition.name} est inciblable, la technique échoue.")
                return True, f"{target.definition.name} est inciblable : Transfert de l'esprit échoue."
            if target.definition.id == "madara":
                self._consume_special(attacker, copied)
                self.log_event("Mangekyô éternel : Madara ignore le Transfert de l'esprit d'Ino.")
                return True, "Madara est immunisé au contrôle mental."

            self._consume_special(attacker, copied)
            if self.random.random() >= 0.50:
                # 4 ici car le tour courant décrémente aussitôt le compteur à 3 :
                # Ino manquera donc bien ses TROIS prochains tours.
                attacker.disabled_turns = max(attacker.disabled_turns, 4)
                loc = self._find_instance(attacker)
                if loc:
                    self.emit_visual("stun_apply", player=loc[0], slot=loc[1], label="TRANSFERT RATÉ")
                self.log_event("Transfert de l'esprit raté : Ino est étourdie pendant ses 3 prochains tours.")
                return True, "Échec du Transfert : Ino est STUN pendant 3 de ses tours."

            duration_by_stars = {3.0: 5, 3.5: 4, 4.0: 3, 4.5: 2, 5.0: 1}
            duration = duration_by_stars.get(float(target.definition.stars), 1)
            attacker.ino_possession_target = target
            attacker.ino_possession_turns_left = duration
            attacker.ino_possession_started_turn = self.turn
            target.ino_possessed_by = attacker
            # Son du Transfert uniquement quand la possession a réellement réussi.
            # L'interface ne joue volontairement aucun son Ino au simple clic.
            self.emit_visual("special_audio", card_id="ino")
            # Le corps d'Ino utilise immédiatement les statistiques et l'élément
            # actuels de la cible. Le corps ennemi d'origine reste sur son slot,
            # blanc/inciblable et inutilisable pour son propriétaire.
            self.log_event(
                f"Transfert de l'esprit réussi : Ino contrôle {target.definition.name} pendant {duration} tour(s)."
            )
            return True, (
                f"Transfert réussi : {target.definition.name} est contrôlé pendant {duration} tour(s). "
                "Ino utilise ses statistiques, mais pas sa technique spéciale."
            )

        if special_id == "mei":
            original_target = enemy.field[defender_slot]
            if original_target is None:
                return False, "Cible invalide."
            if self._is_untargetable(original_target):
                self._consume_special(attacker, copied)
                self.log_event(f"Déferlement magmatique : {original_target.definition.name} est inciblable, l'impact principal échoue.")
                return True, f"{original_target.definition.name} est inciblable : la technique n'atteint pas sa cible."

            # Choji conserve son rôle de garde sur l'impact principal.
            actual_slot = self._guard_slot(enemy.number, defender_slot)
            if actual_slot != defender_slot and enemy.field[actual_slot] is not None:
                self.log_event(
                    f"Expansion Akimichi : Choji intercepte le Déferlement magmatique destiné à {original_target.definition.name}."
                )
            main_target = enemy.field[actual_slot]
            total = 0
            if main_target is not None:
                main_amount, main_adv = self._elemental_fixed_amount(900, "feu", main_target)
                dealt, _ = self._deal_fixed_damage(
                    enemy.number, actual_slot, main_amount, source=attacker,
                    label="Déferlement magmatique", allow_guard=False,
                )
                total += dealt
                if main_adv:
                    self.log_event(f"Déferlement magmatique : avantage Feu, impact principal porté à {main_amount} PV.")

            # Les dégâts de zone restent centrés sur la carte initialement ciblée.
            for side in (defender_slot - 1, defender_slot + 1):
                splash = enemy.field[side] if side in (0, 1, 2) else None
                if splash is None:
                    continue
                splash_amount, splash_adv = self._elemental_fixed_amount(450, "feu", splash)
                dealt, _ = self._deal_fixed_damage(
                    enemy.number, side, splash_amount, source=attacker,
                    label="Déferlement magmatique (zone)", allow_guard=False,
                )
                total += dealt
                if splash_adv:
                    self.log_event(f"Déferlement magmatique : {splash.definition.name} subit un impact de zone super efficace ({splash_amount} PV).")
            self._consume_special(attacker, copied)
            self.log_event(f"Déferlement magmatique : {total} PV infligés au total.")
            return True, f"Déferlement magmatique inflige {total} PV au total."

        if special_id == "onoki":
            target = enemy.field[defender_slot]
            if target is None:
                return False, "Cible invalide."
            onoki_nin = self.effective_stat(attacker, "ninjutsu", target)
            target_nin = self.effective_stat(target, "ninjutsu", attacker)
            if target_nin < onoki_nin:
                affected_target = self._effect_carrier(target)
                affected_target.current_hp = 0
                real_loc = self._find_instance(affected_target)
                if real_loc is not None:
                    self._check_ko(real_loc[0], real_loc[1], source=attacker, suppress_survival=False)
                result = f"{target.definition.name} est frappé par le Jinton et tombe à 0 PV."
            else:
                dealt, _ = self._deal_fixed_damage(enemy.number, defender_slot, 1000, source=attacker, label="Détachement du Monde Primitif")
                result = f"{target.definition.name} perd {dealt} PV."
            attacker.permanent_buffs["ninjutsu"] -= 1000
            self._consume_special(attacker, copied)
            self.log_event(f"Détachement du Monde Primitif : {result} Ônoki perd 1000 Ninjutsu.")
            return True, result + " Ônoki perd 1000 Ninjutsu."

        # 1.2.1 — Grande rafale de Temari : la même attaque Ninjutsu +250
        # frappe chaque Ninja adverse présent. La carte choisie au départ est
        # ensuite renvoyée dans la réserve si elle a survécu, ce qui ouvre un
        # choix de remplacement normal pour son propriétaire.
        if special_id == "temari":
            selected = enemy.field[defender_slot] if defender_slot in (0, 1, 2) else None
            if selected is None:
                return False, "Grande rafale nécessite une cible ennemie."
            selected_slot = int(defender_slot)
            selected_immune = False
            total_hp_damage = 0
            for slot in range(3):
                target = enemy.field[slot]
                if target is None:
                    continue
                out = self._perform_attack(
                    player_number, attacker_slot, "ninjutsu", slot,
                    bonus=250, ignore_guard=True, is_special=True, special_source_id="temari",
                )
                total_hp_damage += max(0, int(out.hp_damage or 0))
                if slot == selected_slot:
                    selected_immune = bool(out.immune)
            self._consume_special(attacker, copied)
            self._mark_attack_usage(attacker, "ninjutsu")

            # Le renvoi ne s'applique pas si la cible a annulé la rafale ou si
            # elle a été mise K.O. par les dégâts. Son instance complète est
            # conservée dans la réserve, comme lors d'un switch tactique.
            still_there = enemy.field[selected_slot]
            if (not selected_immune) and still_there is selected and self._is_alive_instance(selected):
                self._cleanup_links_to(selected)
                self.reserve_instances[enemy.number][selected.definition.id] = selected
                enemy.field[selected_slot] = None
                self._refresh_synergies()
                self.log_event(f"Grande rafale : {selected.definition.name} est renvoyé dans la réserve.")
                self.emit_visual("switch", player=enemy.number, slot=selected_slot, outgoing_id=selected.definition.id, incoming_id="")
                # Si d'autres remplaçants existent déjà, le Ninja soufflé par
                # Temari n'est pas proposé immédiatement pour le trou qu'il
                # vient lui-même de créer. Il rejoint la réserve juste après
                # l'ouverture du choix. Si la réserve était vide, on l'ajoute
                # d'abord pour ne jamais bloquer la partie.
                if enemy.deck:
                    self._queue_replacement(enemy.number, selected_slot)
                    enemy.deck.append(selected.definition)
                    self.random.shuffle(enemy.deck)
                else:
                    enemy.deck.append(selected.definition)
                    self.random.shuffle(enemy.deck)
                    self._queue_replacement(enemy.number, selected_slot)
            else:
                self._ensure_three_on_field(enemy.number)
            return True, f"Grande rafale frappe toute l'équipe adverse ({total_hp_damage} PV de dégâts cumulés)."

        # Spéciales d'attaque standard.
        configs: dict[str, dict] = {
            "hashirama": dict(style="ninjutsu", bonus=300),
            "madara": dict(style="ninjutsu", bonus=500),
            "nagato": dict(style="ninjutsu", bonus=300),
            "obito": dict(style="ninjutsu", bonus=300, bypass=True, ignore_shield=True),
            "itachi": dict(style="ninjutsu", bonus=300),
            "killer_bee": dict(style="ninjutsu", bonus=300),
            "gai": dict(style="taijutsu", bonus=350),
            "minato": dict(style="ninjutsu", bonus=300, bypass=True),
            "naruto": dict(style="ninjutsu", bonus=500),
            "sasuke": dict(
                style="ninjutsu",
                bonus=300,
                ignore_def=100000,
                bypass=True,
                ignore_shield=True,
                absolute_bypass=True,
                ignore_guard=True,
            ),
            "a_raikage": dict(style="taijutsu", bonus=200),
            "sarutobi": dict(style="ninjutsu", bonus=250, force_adv=True),
            "kakashi": dict(style="ninjutsu", bonus=300, bypass=True),
            "kabuto": dict(style="taijutsu", bonus=300, ignore_def=100000, bypass=True, ignore_shield=True, absolute_bypass=True),
            "tsunade": dict(style="taijutsu", bonus=300),
            "deidara": dict(style="ninjutsu", bonus=300),
            "neji": dict(style="taijutsu", bonus=250),
            "sakura": dict(style="taijutsu", bonus=300),
            "sasori": dict(style="ninjutsu", bonus=250),
            "hinata": dict(style="taijutsu", bonus=200),
            "kiba": dict(style="taijutsu", bonus=250),
            "shino": dict(style="ninjutsu", bonus=200),
            "suigetsu": dict(style="ninjutsu", bonus=200),
            "zabuza": dict(style="ninjutsu", bonus=200),
            "kakuzu": dict(style="ninjutsu", bonus=300, force_adv=True),
            "mifune": dict(style="taijutsu", bonus=0),
        }
        cfg = configs.get(special_id)
        if cfg is None:
            return False, "Cette technique spéciale n'est pas encore reconnue par le moteur."

        # Bonus conditionnel de Gatsûga.
        if special_id == "kiba":
            target = enemy.field[defender_slot]
            if target is not None and target.definition.taijutsu < attacker.definition.taijutsu:
                cfg = dict(cfg)
                cfg["bonus"] += 100

        # Chidori : la cible choisie est touchée directement. Les protections
        # actives sont détruites avant l'impact et aucune mécanique défensive
        # (inciblabilité, esquive, garde, bouclier, réduction ou survie) ne peut
        # annuler/réduire cette attaque.
        if special_id == "sasuke":
            target = enemy.field[defender_slot]
            if target is not None:
                self._strip_chidori_defenses(target)

        outcome = self._perform_attack(
            player_number,
            attacker_slot,
            cfg["style"],
            defender_slot,
            bonus=cfg.get("bonus", 0),
            ignore_defense=cfg.get("ignore_def", 0),
            bypass_defensive_passives=cfg.get("bypass", False),
            ignore_shield=cfg.get("ignore_shield", False),
            absolute_bypass=cfg.get("absolute_bypass", False),
            ignore_guard=cfg.get("ignore_guard", False),
            force_advantage=cfg.get("force_adv", False),
            is_special=True,
            special_source_id=special_id,
        )
        self._consume_special(attacker, copied)
        self._mark_attack_usage(attacker, cfg["style"])

        # Effets après l'attaque, uniquement si l'attaquant existe encore.
        current_attacker = self.player(player_number).field[attacker_slot]
        target = self.player(enemy.number).field[outcome.target_slot] if outcome.target_slot is not None else None
        dealt = outcome.damage > 0 and not outcome.immune

        if special_id == "hashirama" and dealt and current_attacker:
            self._heal(current_attacker, 200)
        elif special_id == "madara" and current_attacker:
            self._add_shield(current_attacker, 300)
        elif special_id == "nagato" and dealt and target:
            affected_target = self._effect_carrier(target)
            affected_target.blocked_styles["taijutsu"] = max(affected_target.blocked_styles.get("taijutsu", 0), 1)
        elif special_id == "itachi" and current_attacker:
            # Les autres cartes ennemies prennent 350 dégâts fixes.
            for slot, splash in list(enumerate(enemy.field)):
                if splash is not None and slot != outcome.target_slot:
                    self._deal_fixed_damage(enemy.number, slot, 350, source=current_attacker, label="Katon")
        elif special_id == "killer_bee" and outcome.damage >= 400 and current_attacker:
            self._add_shield(current_attacker, 100)
        elif special_id == "gai" and current_attacker:
            current_attacker.current_hp = max(1, int(current_attacker.current_hp or 1) - 150)
            self._update_gai_thresholds(current_attacker)
        elif special_id == "minato" and outcome.killed and current_attacker:
            self._add_shield(current_attacker, 150)
        elif special_id == "naruto" and dealt and target:
            self._apply_timed_debuff(target, "ninjutsu", 100, "Ôdama Rasengan")
        elif special_id == "a_raikage" and dealt and current_attacker:
            self._add_shield(current_attacker, 100)
        elif special_id == "tsunade" and current_attacker:
            self._heal(current_attacker, 100)
        elif special_id == "deidara" and current_attacker:
            # 2 car le tour actuel va décrémenter ce compteur à 1 à sa fin.
            current_attacker.blocked_styles["ninjutsu"] = max(current_attacker.blocked_styles.get("ninjutsu", 0), 2)
        elif special_id == "neji" and dealt and target:
            if target.definition.id != "killer_bee":
                affected_target = self._effect_carrier(target)
                affected_target.special_block_turns = max(affected_target.special_block_turns, 1)
        elif special_id == "sakura" and outcome.killed and current_attacker:
            self._heal(current_attacker, 200)
        elif special_id == "sasori" and dealt and target:
            affected_target = self._effect_carrier(target)
            affected_target.delayed_damage += 100
            loc = self._find_instance(target)
            if loc:
                self.emit_visual("poison_apply", player=loc[0], slot=loc[1], amount=100)
        elif special_id == "hinata" and current_attacker:
            self._add_shield(current_attacker, 150)
        elif special_id == "shino" and dealt and target:
            # Nuée d'insectes empoisonne durablement la cible. Le poison ne
            # s'empile pas : une cible empoisonnée perd toujours 100 PV par tour.
            affected_target = self._effect_carrier(target)
            affected_target.shino_poisoned = True
            loc = self._find_instance(target)
            if loc:
                self.emit_visual("poison_apply", player=loc[0], slot=loc[1], amount=100)
            self.log_event(f"Nuée d'insectes : {target.definition.name} est empoisonné jusqu'à sa mort.")
        elif special_id == "suigetsu" and current_attacker:
            self._heal(current_attacker, 150)

        msg = f"{special_name} : "
        if outcome.immune:
            msg += "effet annulé."
        else:
            msg += f"{outcome.damage} dégâts"
            if outcome.overflow_damage:
                msg += f" + {outcome.overflow_damage} de surplus à J{enemy.number}"
            msg += "."
        self.log_event(msg)
        return True, msg

    # ------------------------------------------------------------------
    # AI helpers
    # ------------------------------------------------------------------
    def strongest_style(self, card: CardDefinition) -> str:
        values = {"taijutsu": card.taijutsu, "ninjutsu": card.ninjutsu, "genjutsu": card.genjutsu}
        return max(values, key=values.get)

    def ai_choose_replacement(self, player_number: int) -> CardDefinition | None:
        offer = self.pending_replacement
        if offer is None or offer.player_number != player_number or not offer.options:
            return None
        return max(
            offer.options,
            key=lambda c: c.max_hp * 0.35 + max(c.taijutsu, c.ninjutsu, c.genjutsu) + (c.taijutsu + c.ninjutsu + c.genjutsu) * 0.20 + c.stars * 40,
        )

    def ai_choose_special(self, player_number: int = 2) -> tuple[int, int | None, bool] | None:
        if self.pending_replacement is not None:
            return None
        player = self.player(player_number)
        enemy = self.opponent(player_number)
        targets = [i for i, c in enumerate(enemy.field) if c is not None]
        for slot, card in enumerate(player.field):
            if card is None or not self.special_available(card):
                continue
            if self.special_requires_target(card):
                if self.special_targets_ally_id(card.definition.id):
                    if card.definition.id == "karin":
                        allies = [i for i, c in enumerate(player.field) if c is not None and c is not card and int(c.current_hp or 0) < c.definition.max_hp]
                        if allies and self.random.random() < 0.45:
                            target = min(allies, key=lambda s: int(player.field[s].current_hp or 0) / max(1, player.field[s].definition.max_hp))
                            return slot, target, False
                    elif card.definition.id == "rock_lee":
                        allies = [i for i, c in enumerate(player.field) if c is not None and c is not card]
                        if allies and self.random.random() < 0.45:
                            target = max(allies, key=lambda s: self.effective_stat(player.field[s], "taijutsu"))
                            return slot, target, False
                    continue
                if not targets:
                    continue
                # Utilisation modérée pour ne pas brûler toutes les charges dès le départ.
                if self.random.random() < 0.35:
                    target = min(targets, key=lambda s: int(enemy.field[s].current_hp or 0))
                    return slot, target, False
            else:
                useful = (
                    (card.definition.id == "gaara" and any(a and a.shield < 600 for a in player.field))
                    or (card.definition.id == "orochimaru" and bool(enemy.graveyard))
                    or (card.definition.id == "kabuto" and not card.kabuto_reanimation_armed)
                    or (card.definition.id in ("choji", "kankuro", "kimimaro", "kurotsuchi", "konan") and self.random.random() < 0.45)
                    or (card.definition.id == "tobirama" and any(c is not None for c in enemy.field) and self.random.random() < 0.45)
                    or (card.definition.id == "shisui" and any(c is not None and c.definition.id != "killer_bee" and not self.is_disabled(c) for c in enemy.field) and self.random.random() < 0.55)
                )
                if useful:
                    return slot, None, False
        return None

    def ai_choose_attack(self, player_number: int = 2) -> tuple[int, str, int | None] | None:
        if self.pending_replacement is not None:
            return None
        player = self.player(player_number)
        enemy = self.opponent(player_number)
        candidates = [
            (slot, card)
            for slot, card in enumerate(player.field)
            if card is not None and not self.is_disabled(card)
        ]
        if not candidates:
            return None

        best: tuple[int, str, int | None, int] | None = None
        targets = [(i, card) for i, card in enumerate(enemy.field) if card is not None]
        for slot, attacker in candidates:
            for style in STYLE_LABELS:
                if not self.can_use_style(attacker, style):
                    continue
                if targets:
                    for target_slot, target in targets:
                        atk = self.effective_stat(attacker, style, target)
                        defense = self.effective_stat(target, style, attacker)
                        diff = atk - defense
                        damage = max(100, diff) if diff > 0 else 0
                        if self.element_advantage(self._combat_definition(attacker), self._combat_definition(target)) and damage > 0:
                            damage = int(round(damage * 1.10)) + 150
                        if damage == 0:
                            damage, _, _ = self._zero_damage_fallback(attacker, target)
                        candidate = (slot, style, target_slot, damage)
                        if best is None or candidate[3] > best[3]:
                            best = candidate
                else:
                    damage = max(100, self.effective_stat(attacker, style) // 2)
                    candidate = (slot, style, None, damage)
                    if best is None or candidate[3] > best[3]:
                        best = candidate
        if best is None:
            return None
        return best[0], best[1], best[2]


# ======================================================================
# YUGITO 1.7.7 — TOBI / PIEGES SECRETS + PREDICTION
# ======================================================================
_GE177_init = GameEngine.__init__
_GE177_start_turn = GameEngine.start_turn
_GE177_switch_card = GameEngine.switch_card
_GE177_attack = GameEngine.attack
_GE177_use_special = GameEngine.use_special
_GE177_end_turn = GameEngine.end_turn
_GE177_untargetable = GameEngine._is_untargetable
_GE177_execute_desc = GameEngine.execute_action_descriptor


def _tobi_alive177(self, player_number):
    return next((c for c in self.player(player_number).field if c is not None and c.definition.id == "tobi" and int(c.current_hp or 0) > 0), None)


def _init177(self, *a, **kw):
    self.tobi_bomb_choice_required = {1: False, 2: False}
    self.tobi_predictions = {1: None, 2: None}
    return _GE177_init(self, *a, **kw)
GameEngine.__init__ = _init177


def _start177(self, player_number):
    r = _GE177_start_turn(self, player_number)
    tobi = _tobi_alive177(self, player_number)
    if tobi is not None:
        # Même cadence que son intangibilité : visible un tour, intangible le suivant.
        tobi.tobi_intangible = not bool(getattr(tobi, "tobi_intangible", False))
        self.log_event(f"Tobi est un bon garçon ! : Tobi est maintenant {'INTANGIBLE' if tobi.tobi_intangible else 'CIBLABLE'}.")
        if any(c is not None and int(c.current_hp or 0)>0 for c in self.opponent(player_number).field):
            self.tobi_bomb_choice_required[player_number] = True
            self.log_event("Tobi : choisis secrètement un Ninja ennemi sur lequel placer 1 bombe.")
    return r
GameEngine.start_turn = _start177


def _untarget177(self, card):
    if card is not None and card.definition.id == 'tobi' and bool(getattr(card,'tobi_intangible',False)):
        return True
    return _GE177_untargetable(self, card)
GameEngine._is_untargetable = _untarget177


def place_tobi_bomb(self, player_number, enemy_slot):
    if not self.tobi_bomb_choice_required.get(player_number, False):
        return False, "Aucune bombe de Tobi à placer."
    if _tobi_alive177(self, player_number) is None:
        self.tobi_bomb_choice_required[player_number]=False
        return False, "Tobi n'est plus sur le terrain."
    enemy=self.opponent(player_number)
    if enemy_slot not in (0,1,2) or enemy.field[enemy_slot] is None:
        return False, "Choisis un Ninja ennemi valide."
    target=enemy.field[enemy_slot]
    target.tobi_bombs=min(5,int(getattr(target,'tobi_bombs',0) or 0)+1)
    self.tobi_bomb_choice_required[player_number]=False
    self.log_event("Tobi place secrètement une bombe sur le terrain ennemi.")
    return True, "Bombe placée secrètement. L'adversaire ne voit ni la cible ni le nombre de charges."
GameEngine.place_tobi_bomb=place_tobi_bomb


def _explode_tobi177(self, owner_number, victim, label):
    stacks=int(getattr(victim,'tobi_bombs',0) or 0)
    if stacks<=0:return 0
    loc=self._find_instance(victim)
    victim.tobi_bombs=0
    amount=320*stacks
    if loc is None:return 0
    dealt,_=self._deal_fixed_damage(loc[0],loc[1],amount,source=None,label=label,allow_guard=False)
    self.log_event(f"{label} : {stacks} bombe(s) explosent sur {victim.definition.name} — {dealt} dégâts fixes.")
    self.emit_visual('damage',player=loc[0],slot=loc[1],amount=dealt,label='TOBI BOUM')
    return dealt
GameEngine._explode_tobi177=_explode_tobi177


def _switch177(self, player_number, outgoing_id, incoming_id, *a, **kw):
    loc=self._field_card_by_id(player_number,str(outgoing_id or ''))
    outgoing=loc[1] if loc is not None else None
    # Le piège appartient à Tobi adverse : exploser AVANT le départ.
    if outgoing is not None and int(getattr(outgoing,'tobi_bombs',0) or 0)>0 :
        self._explode_tobi177(self.opponent_number(player_number),outgoing,"Piège de Tobi — SWITCH")
        if not self._is_alive_instance(outgoing):
            return False, "Le Switch échoue : les explosifs de Tobi mettent le Ninja K.O. avant son départ."
    return _GE177_switch_card(self,player_number,outgoing_id,incoming_id,*a,**kw)
GameEngine.switch_card=_switch177


def _prediction_hit177(self, attacker_player, attacker, defender):
    owner=self.opponent_number(attacker_player)
    pred=self.tobi_predictions.get(owner)
    if not pred:return False
    if str(pred.get('enemy_id') or '')!=attacker.definition.id or str(pred.get('ally_id') or '')!=defender.definition.id:
        return False
    self.tobi_predictions[owner]=None
    self._explode_tobi177(owner,attacker,"C'était prévu !")
    self.log_event(f"C'était prévu ! : Tobi avait prédit {attacker.definition.name} → {defender.definition.name}.")
    return True
GameEngine._prediction_hit177=_prediction_hit177


def _attack177(self, player_number, attacker_slot, style, defender_slot=None, **kw):
    attacker=self.player(player_number).field[attacker_slot] if attacker_slot in (0,1,2) else None
    defender=self.opponent(player_number).field[defender_slot] if defender_slot in (0,1,2) else None
    if attacker is not None and defender is not None:
        self._prediction_hit177(player_number,attacker,defender)
        if not self._is_alive_instance(attacker):
            return False,"Les explosifs de Tobi détonnent avant l'attaque : l'attaquant est K.O."
    return _GE177_attack(self,player_number,attacker_slot,style,defender_slot,**kw)
GameEngine.attack=_attack177


def _execute177(self, player_number, action, *, preserve_turn_budget=False):
    if action and str(action.get('kind') or '')=='special' and str(action.get('actor_id') or '')=='tobi':
        self._tobi_prediction_action177=dict(action)
    try:
        return _GE177_execute_desc(self,player_number,action,preserve_turn_budget=preserve_turn_budget)
    finally:
        self._tobi_prediction_action177=None
GameEngine.execute_action_descriptor=_execute177


def _special177(self, player_number, attacker_slot, defender_slot=None, *, copied=False):
    attacker=self.player(player_number).field[attacker_slot] if attacker_slot in (0,1,2) else None
    sid=(attacker.copied_special_id if copied else attacker.definition.id) if attacker else ''
    if sid!='tobi':
        return _GE177_use_special(self,player_number,attacker_slot,defender_slot,copied=copied)
    if attacker is None or not self.special_available(attacker,copied=copied):return False,"Spéciale indisponible."
    enemy=self.opponent(player_number)
    if defender_slot not in (0,1,2) or enemy.field[defender_slot] is None:return False,"Choisis le Ninja ennemi à surveiller."
    predicted_enemy=enemy.field[defender_slot]
    action=getattr(self,'_tobi_prediction_action177',None) or {}
    ally_id=str(action.get('prediction_ally_id') or '')
    ally=next((c for c in self.player(player_number).field if c is not None and c.definition.id==ally_id),None)
    if ally is None:return False,"Choisis aussi le Ninja allié que l'ennemi devrait attaquer."
    self.tobi_predictions[player_number]={'enemy_id':predicted_enemy.definition.id,'ally_id':ally.definition.id,'armed_turn':self.turn}
    self._consume_special(attacker,copied)
    self.log_event("C'était prévu ! : Tobi arme secrètement une prédiction pour le prochain tour adverse.")
    return True,"Prédiction secrète armée pour le prochain tour adverse."
GameEngine.use_special=_special177


def _end177(self):
    if self.winner is not None or self.pending_replacement is not None:return _GE177_end_turn(self)
    current=self.active_player
    # Si le joueur courant termine son tour sans réaliser la prédiction posée par Tobi adverse,
    # le stack de la carte prédite est perdu.
    owner=self.opponent_number(current); pred=self.tobi_predictions.get(owner)
    if pred and int(pred.get('armed_turn',-1)) < int(self.turn):
        victim=next((c for c in self.player(current).field if c is not None and c.definition.id==str(pred.get('enemy_id') or '')),None)
        if victim is not None:
            lost=int(getattr(victim,'tobi_bombs',0) or 0); victim.tobi_bombs=0
            self.log_event(f"C'était prévu ! raté : la prédiction n'a pas eu lieu, {lost} bombe(s) sur {victim.definition.name} sont perdues.")
        self.tobi_predictions[owner]=None
    return _GE177_end_turn(self)
GameEngine.end_turn=_end177
