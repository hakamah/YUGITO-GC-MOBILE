from __future__ import annotations

from fractions import Fraction
from pathlib import Path
import ctypes
import os
import random
import secrets
import re
import sys
import threading
import queue
import subprocess
import tempfile
import time
import zipfile
import math
import webbrowser
import tkinter as tk
import tkinter.font as tkfont
from tkinter import messagebox

from .audio_manager import AudioManager
from .cards import CardDefinition, load_cards
from .game_engine import GameEngine, STYLE_LABELS, STAR_VALUE_LIMITS, MAX_TOTAL_STAR_VALUE, SYNERGY_FAMILIES, SYNERGY_DUOS
from .game_modes import SOLO_AI, MULTIPLAYER, GameMode
from .network_manager import LanNetworkManager, InternetNetworkManager, DEFAULT_PORT
from .identity_manager import (
    IdentityStore, IdentityError, PseudoTakenError, RegistryUnavailableError,
    InternetIdentityRegistry, YugitoIdentity, normalize_pseudo, validate_pseudo,
)
from .auth_manager import (
    AuthSessionStore, AuthIdentityHintStore, YugitoAuthClient, AuthError, AuthUnavailableError, AuthRejectedError,
)
from .update_manager import APP_VERSION, UpdateInfo, check_for_update, download_update, cleanup_previous_update
from .social_manager import SocialManager
from .ranked_manager import RankedStore, DEFAULT_ELO, normalize_elo
from .gpu_field_renderer import FieldCaptureSpec, GPUFieldRenderer


VIRTUAL_W = 1600
VIRTUAL_H = 900
MIN_W = 1050
MIN_H = 650
DRAFT_SIZE_PER_PLAYER = 8

# 1.2.9 — Guide de combat enrichi pour nouveaux joueurs + 67 cartes.
# Le gagnant du premier Shifumi choisit selon la séquence W,L,L,W,W,L,L,...
# Chaque valeur indique le PALIER qui se débloque à ce moment du draft.
# IMPORTANT 1.5.2 : un palier débloqué ne se referme JAMAIS. La séquence ci-dessous
# décrit le rythme auquel J1/J2 peuvent atteindre les meilleures raretés si chacun
# cherche les cartes les plus fortes au plus vite ; ce n'est pas une fenêtre obligatoire.
DRAFT_PICK_CAPS = (3.0, 3.0, 3.5, 3.5, 4.0, 4.0, 4.5, 4.5, 5.0, 5.0, 4.5, 4.5, 4.0, 4.0, 4.0, 4.0)
DRAFT_PICK_RELATIVE = (
    "first", "second", "second",
    "first", "first", "second", "second",
    "first", "first", "second", "second",
    "first", "first", "second", "second",
    "first",
)
DRAFT_ROUND_BY_PICK = (1, 1, 1, 2, 2, 2, 2, 3, 3, 3, 3, 4, 4, 4, 4, 5)
STARTER_COUNT = 3

# V5 : le catalogue du draft est une longue zone verticale, comme une page web.
DRAFT_CARD_W = 200
DRAFT_CARD_H = 282
DRAFT_COLS = 3
DRAFT_GAP_X = 24
DRAFT_GAP_Y = 24
DRAFT_VIEW_TOP = 162
DRAFT_VIEW_BOTTOM = 842
DRAFT_START_X = 72

BG_TOP = "#111827"
BG_BOTTOM = "#06090f"
PANEL = "#141b27"
PANEL_2 = "#1d2635"
TEXT = "#f7f2e9"
MUTED = "#aab3c2"
ACCENT = "#f0782a"
ACCENT_2 = "#ff9c48"
RED = "#d95454"
BLUE = "#4c74d8"
GREEN = "#55b982"
PURPLE = "#a769df"
GOLD = "#d8a43f"
CREAM = "#f3f0e8"
INK = "#111111"

ELEMENT_COLORS = {
    "feu": "#c94b3f",
    "vent": "#5ea66c",
    "foudre": "#d2a93b",
    "terre": "#9b704c",
    "eau": "#4e82bb",
    "tous": "#8a6bb8",
}

ELEMENT_SHORT = {
    "feu": "FEU",
    "vent": "VENT",
    "foudre": "FOUDRE",
    "terre": "TERRE",
    "eau": "EAU",
    "tous": "TOUS",
}

CARD_ROLE_PRIMARY = ("DPS", "TANK", "PROTECTEUR", "CONTROLE", "SOUTIEN", "SOIGNEUR")
CARD_ROLE_ADVANCED = ("SUSTAIN", "BURST", "POISON", "COUNTER", "ESQUIVE", "ANTI-DEFENSE", "RESURRECTION", "SCALING", "SACRIFICE", "TRACKER", "ZONE", "PERTURBATION", "RESISTANCE", "PIEGEUR")
CARD_ROLE_LABELS = {"CONTROLE":"CONTRÔLE", "ANTI-DEFENSE":"ANTI-DÉFENSE", "RESURRECTION":"RÉSURRECTION", "RESISTANCE":"RÉSISTANCE", "PIEGEUR":"PIÉGEUR"}

ELEMENT_KANJI = {
    "feu": "火",
    "vent": "風",
    "foudre": "雷",
    "terre": "土",
    "eau": "水",
    "tous": "五",
}

RPS_BEATS = {
    "pierre": "ciseaux",
    "ciseaux": "feuille",
    "feuille": "pierre",
}

RPS_LABEL = {
    "pierre": "PIERRE",
    "feuille": "FEUILLE",
    "ciseaux": "CISEAUX",
}

PROJECT_ROOT = Path(__file__).resolve().parent.parent
ASSET_DIR = PROJECT_ROOT / "assets"
FONT_DIR = ASSET_DIR / "fonts"
DISPLAY_FONT_TOKEN = "@display"
TIPEEE_URL = "https://fr.tipeee.com/hakamahproduction"
DISCORD_URL = "https://discord.com/channels/1539287372607397958/1539287373139939341"


class YugitoApp:
    def __init__(self, root: tk.Tk):
        self.root = root
        self.root.title("YUGITO Classic 1.9.0 GPU - Naruto Card Game")
        self.root.geometry("1280x720")
        self.root.minsize(MIN_W, MIN_H)
        self.root.resizable(True, True)
        self.root.configure(bg="#080b11")

        self.display_font_family = "Arial Black"
        self.ui_font_family = "Segoe UI"
        self._registered_font_paths: list[str] = []
        self._register_custom_fonts()

        self.cards = load_cards()
        self.random = random.Random()

        # Classic 1.1.4 : rupture d'identité. L'ancien token V40.21/1.1.3
        # est chargé au maximum UNE fois pour une migration silencieuse puis son
        # fichier local est détruit. La seule identité persistante devient une
        # session YUGITO émise après authentification Google.
        self.identity_store = IdentityStore()              # legacy uniquement
        self.auth_session_store = AuthSessionStore()       # nouvelle session Google
        self.auth_hint_store = AuthIdentityHintStore()     # pseudo/account_id sans token, DPAPI
        self.auth_client = YugitoAuthClient()
        self.identity: YugitoIdentity | None = None
        self.auth_account: dict = {}
        self.auth_identity_hint: dict = self.auth_hint_store.load()
        self.legacy_identity: YugitoIdentity | None = None
        self.legacy_ranked_profile: dict | None = None
        self.identity_load_error = ""

        try:
            old_identity = self.identity_store.load()
            if old_identity is not None:
                self.legacy_identity = old_identity
                try:
                    self.legacy_ranked_profile = RankedStore(old_identity).profile()
                except Exception:
                    self.legacy_ranked_profile = None
        except IdentityError as exc:
            self.identity_load_error = str(exc)
        finally:
            # Exigence 1.1.4 : aucun ancien token de compte ne reste enregistré.
            self.identity_store.clear()

        try:
            session = self.auth_session_store.load()
            if session is not None:
                self.identity = session.identity
                self.auth_account = dict(session.account)
                # Sauvegarde séparée du token : même si Render invalide la session,
                # le client sait encore quel pseudo/account_id appartenait à Google.
                try:
                    self.auth_identity_hint = self.auth_hint_store.save(self.auth_account)
                except Exception:
                    pass
        except AuthError as exc:
            self.identity_load_error = str(exc)
            self.auth_session_store.clear()

        self.ranked: RankedStore | None = RankedStore(self.identity) if self.identity is not None else None
        self.ranked_needs_server_push = False
        if self.ranked is not None and self.auth_account:
            try:
                # Si un classé interrompu vient d'être régularisé en défaite au
                # démarrage, cette nouvelle valeur locale doit partir au serveur
                # AVANT qu'un ancien ELO distant ne puisse l'écraser.
                if self.ranked.data.get("last_forfeit_recovered"):
                    self.ranked_needs_server_push = True
                else:
                    self.ranked.sync_from_server(self.auth_account.get("elo", DEFAULT_ELO))
            except Exception:
                pass

        self.identity_stage = "ready" if self.identity is not None else "google"
        self.pending_google_token = ""
        self.pending_google_account: dict = {}
        self.identity_network_status = "Compte Google YUGITO connecté" if self.identity is not None else "Connexion Google requise"
        self.identity_busy = False
        self.identity_notice = self.identity_load_error
        self.identity_conflict = False
        self.identity_events: queue.Queue[tuple[str, object]] = queue.Queue()

        # V40.21U : mises à jour officielles via GitHub Releases.
        self.update_info: UpdateInfo | None = None
        self.update_busy = False
        self.update_progress = 0.0
        self.update_status = "Verification des mises a jour..."
        self.update_events: queue.Queue[tuple[str, object]] = queue.Queue()
        self.update_previous_screen = "menu"
        self.update_dismissed_version = ""

        self.is_fullscreen = False
        self.windowed_geometry = "1280x720"
        self.current_screen = "menu"
        self.current_mode: GameMode | None = None
        self.engine: GameEngine | None = None

        # Duel state.
        self.selected_hand_index: int | None = None
        self.selected_attacker_slot: int | None = None
        self.selected_style: str | None = None
        # None / "own" / "copy". Une spéciale ciblée utilise ensuite le clic sur
        # une carte ennemie, exactement comme une attaque normale.
        self.selected_special_mode: str | None = None
        self.tobi_prediction_enemy_id: str | None = None
        self.inspected_enemy_slot: int | None = None
        # Classic 1.0.0 : le tour est préparé avant d'être résolu.
        # - free : attaque normale gratuite de Minato (si utilisée)
        # - actions[0] : action immédiate à la validation
        # - actions[1] : ordre réactif à la prochaine validation adverse
        self.turn_plan_free: dict | None = None
        self.turn_plan_actions: list[dict] = []
        # Classic 1.1.3 : la frappe Hiraishin de Minato est un choix explicite.
        # None = prochaine action vers Action 1/2 ; "free" = prochaine attaque
        # normale de Minato vers la case MINATO — GRATUIT.
        self.turn_plan_target_slot: str | None = None
        self.turn_commit_pending_end = False
        self.turn_commit_player: int | None = None
        self.turn_commit_queue: list[dict] = []
        self.turn_commit_delayed: dict | None = None
        self.switch_select_slot: int | None = None
        self.switch_return_screen = "duel"
        self.notice = ""
        self.ai_busy = False
        self.result_audio_winner: int | None = None

        # Pre-game / Shifumi / draft state.
        self.rps_context: str | None = None  # "draft" or "start"
        self.rps_choices: dict[int, str] = {}
        self.rps_waiting_player = 1
        self.rps_winner: int | None = None
        self.rps_tie = False
        self.draft_pool: list[CardDefinition] = []
        self.draft_owner: dict[str, int | None] = {}
        self.draft_decks: dict[int, list[CardDefinition]] = {1: [], 2: []}
        self.draft_active_player = 1
        self.draft_first_picker = 1
        self.starting_player = 1
        self.draft_preview_card: CardDefinition | None = None
        self.draft_page = 0  # conservé pour compatibilité avec d’anciennes sauvegardes
        self.draft_scroll = 0.0
        # YUGITO06 R2 : la molette modifie directement la position et regroupe
        # les rafales d'événements en un seul redraw idle (pas d'animation 60 FPS).
        self._draft_scroll_redraw_job = None
        # YUGITO06 R3 : le draft redessine beaucoup de texte. L'ancien moteur
        # recréait des objets Font et remesurait les mêmes phrases à CHAQUE cran
        # de molette. Sur Tk/Windows cela suffit à bloquer la boucle UI même sur
        # une grosse machine. Ces caches rendent le layout de texte quasi gratuit
        # après sa première apparition.
        self._fit_text_cache: dict[tuple, tuple[str, int]] = {}
        self._tk_measure_fonts: dict[tuple, tkfont.Font] = {}

        # V4: choix des 3 Ninjas de départ, caché entre les joueurs.
        self.starter_choices: dict[int, list[CardDefinition]] = {1: [], 2: []}
        self.lineup_active_player = 1
        self.lineup_revealed = False
        self.lineup_preview_card: CardDefinition | None = None

        # V35 : encyclopédie / liste des cartes accessible depuis le menu.
        self.card_catalog_page = 0
        self.card_catalog_per_page = 8
        self.card_catalog_selected_id: str | None = self.cards[0].id if self.cards else None
        self.card_catalog_scroll = 0.0
        self.card_catalog_ownership_filter = "all"
        self.card_catalog_role_filters: set[str] = set()
        self.card_catalog_roles_expanded = False
        self.card_catalog_query = ""

        # V40.11 : constructeur de deck libre depuis le menu. Le deck reste
        # limité à 8 Ninjas et utilise exactement les règles d'étoiles du draft.
        self.deck_builder_deck: list[CardDefinition] = []
        # V40.12 : le constructeur utilise désormais un catalogue vertical
        # de vraies cartes, identique au panel de draft.
        self.deck_builder_scroll = 0.0
        self.deck_builder_page = 0  # conservé pour compatibilité avec d'anciens états
        self.deck_builder_per_page = 12
        self.deck_builder_notice = ""
        # YUGITO06 ECONOMIE : état autoritaire reçu du serveur Google/YUGITO.
        # Aucun solde/achat n'est considéré valide depuis un fichier local.
        self.economy_state: dict = {"economy_available": False, "yt_balance": 0, "available_card_ids": [], "owned_card_ids": [], "free_card_ids": [], "base_card_ids": []}
        self.economy_loaded = False
        self.economy_busy = False
        self.economy_last_refresh = 0.0
        self.economy_notice = ""
        self.shop_view = "root"
        self.shop_page = 0
        self.shop_scroll = 0.0
        self.shop_filter = "all"
        self.collection_scroll = 0.0
        self.collection_filter = "all"
        self.deck_builder_filter = "owned"
        self.economy_own_permit = ""
        self.economy_peer_permit = ""
        self.economy_peer_account_id = ""
        self.economy_peer_available_ids: set[str] = set()
        self.economy_peer_verified = False
        self.economy_match_id = ""
        self.economy_result_applied = False
        self.economy_finish_reason = "natural"

        # Fiche complète : overlay lisible depuis le duel, le draft et la liste
        # des cartes. On garde l'écran courant actif pour ne pas réinitialiser
        # le timer de 30 secondes en ouvrant/fermant une fiche.
        self.card_reader_card: CardDefinition | None = None
        self.card_reader_instance = None
        # 1.2.7 : la fiche complète devient une vraie page verticale.
        # La carte reste fixe à gauche tandis que les informations détaillées
        # (passif, technique, synergies, statistiques) se parcourent à la molette.
        self.card_reader_scroll = 0.0

        # Classic 1.2.8 : le menu principal et le guide de combat sont
        # de vraies zones verticales. Le menu ne rapetisse plus ses boutons
        # lorsqu'on ajoute une rubrique : on fait simplement défiler le panneau.
        self.main_menu_scroll = 0.0
        self.combat_guide_scroll = 0.0

        # V4: remplacement après K.O.
        self.replacement_resume_ai = False
        # V9: sélection d'une carte dans le cimetière ennemi pour Orochimaru.
        self.grave_select_context: dict | None = None

        self._pending_ai_job: str | None = None
        # V10 : fin de tour automatique lorsque plus aucune action n'est possible.
        self._auto_end_job: str | None = None

        # V7 : effets visuels de combat. Les règles restent dans GameEngine ;
        # l'interface ne conserve ici que des animations temporaires.
        self.transient_fx: list[dict] = []
        self._fx_job: str | None = None
        self._status_anim_job: str | None = None
        self._status_anim_phase = 0

        # Classic 1.9.0 — la carte de terrain est désormais un sprite OpenGL.
        # Tk ne possède plus aucun moteur de flottement. Il dessine seulement la
        # référence visuelle quand l'état logique change ; GPUFieldRenderer gère
        # ensuite le mouvement float + filtrage bilinéaire à la cadence écran.
        self._field_card_widgets: dict[tuple[int, int], tk.Canvas] = {}
        self._field_card_snapshots: dict[tuple[int, int], tk.PhotoImage] = {}
        self._scale_override: tuple[float, float, float] | None = None
        self._active_draw_tags: tuple[str, ...] = ()

        # Canvas hitboxes.
        self.click_regions: list[tuple[tuple[float, float, float, float], callable]] = []

        # Static image assets + menu GIF overlay.
        self.base_images: dict[str, tk.PhotoImage] = {}
        self.scaled_images: dict[tuple[str, int, int], tk.PhotoImage] = {}
        self.base_gif_frames: dict[str, list[tk.PhotoImage]] = {}
        self.scaled_gif_frames: dict[tuple[str, int, int, int], tk.PhotoImage] = {}
        self.menu_gif_index = 0
        self.menu_gif_durations: list[int] = []
        self._menu_gif_job: str | None = None
        self._load_assets()
        # V33 : icône YUGITO dans la barre de titre / barre des tâches.
        try:
            icon_ico = ASSET_DIR / "YUGITO.ico"
            if icon_ico.exists():
                self.root.iconbitmap(default=str(icon_ico))
        except Exception:
            pass
        try:
            app_icon = self.base_images.get("app_icon")
            if app_icon is not None:
                self.root.iconphoto(True, app_icon)
        except Exception:
            pass

        # Audio natif Windows via MCI. Le jeu reste jouable même si l'audio
        # ne peut pas s'initialiser.
        self.audio = AudioManager(ASSET_DIR)
        self.audio_return_screen = "menu"

        # V39 : deux transports multijoueur séparés :
        # - INTERNET : relais MQTT/TLS persistant (aucune connexion directe)
        # - LAN : relais local + découverte automatique sur le réseau domestique.
        self.network = InternetNetworkManager()
        self.identity_broker_host = self.network.broker_host
        self.identity_broker_port = self.network.broker_port
        self.identity_broker_tls = self.network.broker_tls
        if self.identity is not None:
            self.network.display_name = self.identity.pseudo
        self.network_peer_name = ""
        self.multiplayer_scope: str | None = None  # internet / lan
        self.network_local_player: int | None = None
        self.network_seed: int | None = None
        self.network_status = "Hors ligne"
        self.network_room_code = ""
        self.network_peer_connected = False
        self.network_lobby_role: str | None = None
        self.multiplayer_view = "scope"  # scope / internet_mode / choice / join / host / ranked_search
        self.multiplayer_match_type = "classic"  # classic / ranked / private / tournament
        self.ranked_search_started = 0.0
        self.ranked_search_job: str | None = None
        self.ranked_peer_elo = DEFAULT_ELO
        self.ranked_result_applied = False
        self.ranked_last_result: dict | None = None
        self._disconnect_forfeit_job: str | None = None
        self._duel_started_network = False
        self.multiplayer_rooms: list[dict] = []
        self.multiplayer_selected_room_id: str | None = None
        self._last_room_signature = None

        # Classic 1.0.3 : espace social persistant (amis, MP, invitations privées).
        self.social: SocialManager | None = None
        self.social_selected_friend_id: str | None = None
        self.social_friend_page = 0
        self.social_notice = ""
        self.social_busy = False
        self.social_unread: set[str] = set()
        self.social_invite_pending: dict | None = None
        # Classic 1.1.0 : invitation privée directe. Le salon est créé en
        # arrière-plan et démarre automatiquement dès que l'ami rejoint.
        self.social_private_autostart = False
        self.social_private_invited_account_id: str | None = None
        # Classic 1.1.2 : profil, modération et conversations de groupe.
        self.social_tab = "friends"
        self.social_selected_group_id: str | None = None
        self.social_profile_friend_id: str | None = None
        self.social_group_unread: set[str] = set()
        self.social_tournament_invite_pending: dict | None = None
        self.tournament_state: dict | None = None
        self.social_add_var = tk.StringVar()
        self.social_dm_var = tk.StringVar()
        if self.identity is not None:
            self._start_social_manager()

        # Timer V40 : 30 secondes pour chaque phase où un joueur doit agir/choisir.
        self.phase_timer_seconds = 30
        self._phase_timer_key = None
        self._phase_timer_job: str | None = None
        # V40 : chaque nouveau tour/choix fait apparaître le chrono au centre
        # puis le fait glisser vers sa position normale en haut de l'écran.
        self._phase_timer_anim_key = None
        self._phase_timer_anim_started = 0.0
        self._phase_timer_anim_job: str | None = None
        self._phase_timer_anim_duration = 0.58

        # Tchat multijoueur : les messages passent par le même relais que
        # le duel et n'affichent aucune adresse réseau. V40.2 remplace la
        # popup de saisie par une vraie barre de discussion intégrée.
        self.chat_open = False
        self.chat_unread = 0
        self.chat_messages: list[tuple[str, str]] = []
        self.chat_input_var = tk.StringVar()
        self.identity_input_var = tk.StringVar()
        self.card_catalog_query_var = tk.StringVar(value=self.card_catalog_query)

        self.canvas = tk.Canvas(root, bg="#080b11", highlightthickness=0, bd=0)
        self.canvas.pack(fill="both", expand=True)

        self.chat_entry = tk.Entry(
            self.canvas,
            textvariable=self.chat_input_var,
            bg="#111824",
            fg="#f4eff9",
            insertbackground="#ffd84d",
            selectbackground="#6f3c94",
            selectforeground="#ffffff",
            relief="flat",
            bd=0,
            highlightthickness=2,
            highlightbackground="#7c5d90",
            highlightcolor=PURPLE,
            font=(self.ui_font_family, 11),
            validate="key",
            validatecommand=(self.root.register(self._validate_chat_input), "%P"),
        )
        self.chat_entry.bind("<Return>", self._submit_chat_entry)
        self.chat_entry.bind("<KP_Enter>", self._submit_chat_entry)
        self.chat_entry.bind("<Escape>", self._chat_entry_escape)
        self.chat_entry.place_forget()

        self.identity_entry = tk.Entry(
            self.canvas,
            textvariable=self.identity_input_var,
            bg="#101a28",
            fg="#f7f2e9",
            insertbackground="#ffb457",
            selectbackground="#7b3f21",
            selectforeground="#ffffff",
            relief="flat", bd=0,
            highlightthickness=2,
            highlightbackground="#7c4b2d",
            highlightcolor=ACCENT,
            font=(self.ui_font_family, 18, "bold"),
            justify="center",
        )
        self.identity_entry.bind("<Return>", self._submit_identity_entry)
        self.identity_entry.bind("<KP_Enter>", self._submit_identity_entry)
        self.identity_entry.place_forget()

        self.card_catalog_search_entry = tk.Entry(
            self.canvas, textvariable=self.card_catalog_query_var,
            bg="#101a28", fg="#f7f2e9", insertbackground="#ffb457",
            selectbackground="#7b3f21", selectforeground="#ffffff",
            relief="flat", bd=0, highlightthickness=2,
            highlightbackground="#33445c", highlightcolor=ACCENT,
            font=(self.ui_font_family, 11, "bold"),
        )
        self.card_catalog_search_entry.bind("<KeyRelease>", self._catalog_search_changed)
        self.card_catalog_search_entry.place_forget()

        self.social_add_entry = tk.Entry(
            self.canvas, textvariable=self.social_add_var,
            bg="#101a28", fg="#f7f2e9", insertbackground="#ffb457",
            selectbackground="#7b3f21", selectforeground="#ffffff",
            relief="flat", bd=0, highlightthickness=2,
            highlightbackground="#33445c", highlightcolor=ACCENT,
            font=(self.ui_font_family, 12, "bold"),
        )
        self.social_add_entry.bind("<Return>", self._social_submit_add)
        self.social_add_entry.bind("<KP_Enter>", self._social_submit_add)
        self.social_add_entry.place_forget()

        self.social_dm_entry = tk.Entry(
            self.canvas, textvariable=self.social_dm_var,
            bg="#101a28", fg="#f7f2e9", insertbackground="#6fb8ff",
            selectbackground="#36577a", selectforeground="#ffffff",
            relief="flat", bd=0, highlightthickness=2,
            highlightbackground="#33445c", highlightcolor=BLUE,
            font=(self.ui_font_family, 11),
        )
        self.social_dm_entry.bind("<Return>", self._social_submit_dm)
        self.social_dm_entry.bind("<KP_Enter>", self._social_submit_dm)
        self.social_dm_entry.place_forget()

        self.root.bind("<F11>", self._toggle_fullscreen)
        self.root.bind("<Escape>", self._escape)
        self.canvas.bind("<Configure>", lambda _e: self.redraw())
        self.canvas.bind("<Button-1>", self._on_click)

        # Classic 1.9.0 GPU : le Canvas Tk reste le shell UI, mais les six cartes
        # de terrain sont présentées par un vrai swap-chain OpenGL. Le moteur GPU
        # ne reçoit une nouvelle texture que quand l'état visuel change ; pendant
        # le flottement, seul un transform float est envoyé au GPU.
        self.gpu_field_renderer = GPUFieldRenderer(self, self._dispatch_virtual_click)
        self._gpu_field_sync_job: str | None = None
        # YUGITO06 R2 : un SEUL chemin de molette. Un événement reçu par le
        # Canvas remontait aussi jusqu'au bind_all et pouvait donc être traité
        # deux fois. Le bind global suffit, puis le handler vérifie la zone visée.
        self.root.bind_all("<MouseWheel>", self._on_mousewheel, add="+")
        self.root.bind_all("<Button-4>", self._on_mousewheel, add="+")
        self.root.bind_all("<Button-5>", self._on_mousewheel, add="+")
        self.root.protocol("WM_DELETE_WINDOW", self._close_app)

        if self.identity is None:
            self.show_identity_screen()
        else:
            self.show_main_menu()
        self._schedule_menu_gif()
        self._poll_network()
        self.root.after(150, self._poll_identity_events)
        self.root.after(180, self._poll_social_events)
        self.root.after(350, self._background_online_boot)
        if self.identity is not None:
            self.root.after(700, self._start_identity_verify)
        self._phase_timer_job = self.root.after(1000, self._phase_timer_tick)

        # La sauvegarde d'une mise à jour précédente n'est supprimée qu'après
        # le démarrage effectif de la nouvelle version.
        cleanup_previous_update(PROJECT_ROOT.parent)
        self.root.after(180, self._poll_update_events)
        self.root.after(1200, self._start_update_check)


    # ------------------------------------------------------------------
    # V40.21U - Mise à jour automatique via GitHub Releases
    # ------------------------------------------------------------------
    def _start_update_check(self):
        if self.update_busy:
            return
        def worker():
            try:
                info = check_for_update(APP_VERSION)
                self.update_events.put(("found" if info else "none", info))
            except Exception as exc:
                # Une panne GitHub / Internet ne doit jamais empêcher YUGITO de démarrer.
                self.update_events.put(("check_error", str(exc)))
        threading.Thread(target=worker, daemon=True, name="YUGITOUpdateCheck").start()

    def _poll_update_events(self):
        try:
            while True:
                kind, payload = self.update_events.get_nowait()
                if kind == "found" and isinstance(payload, UpdateInfo):
                    if payload.version != self.update_dismissed_version:
                        self.update_info = payload
                        self.update_previous_screen = self.current_screen
                        self.current_screen = "update"
                        self.update_status = "Une nouvelle version de YUGITO est disponible."
                        self.redraw()
                elif kind == "progress":
                    received, total = payload
                    self.update_progress = (received / total) if total else 0.0
                    if total:
                        self.update_status = f"Telechargement... {int(self.update_progress * 100)} %"
                    else:
                        self.update_status = "Telechargement de la mise a jour..."
                    if self.current_screen == "update":
                        self.redraw()
                elif kind == "downloaded":
                    self.update_progress = 1.0
                    self.update_status = "Mise a jour verifiee. Installation..."
                    if self.current_screen == "update":
                        self.redraw()
                    self.root.after(120, lambda path=payload: self._launch_downloaded_update(Path(path)))
                elif kind == "download_error":
                    self.update_busy = False
                    self.update_status = f"Echec du telechargement : {payload}"
                    if self.current_screen == "update":
                        self.redraw()
                elif kind in {"none", "check_error"}:
                    # Silence volontaire : pas de popup si Internet/GitHub est indisponible.
                    pass
        except queue.Empty:
            pass
        finally:
            try:
                self.root.after(180, self._poll_update_events)
            except Exception:
                pass

    def _update_later(self):
        if self.update_info is not None:
            self.update_dismissed_version = self.update_info.version
        target = self.update_previous_screen or "menu"
        if target == "identity" and self.identity is None:
            self.show_identity_screen()
        else:
            self.current_screen = "menu" if target == "update" else target
            self.redraw()

    def _begin_update_download(self):
        if self.update_busy or self.update_info is None:
            return
        self.update_busy = True
        self.update_progress = 0.0
        self.update_status = "Connexion a GitHub..."
        self.redraw()
        info = self.update_info

        def progress(received, total):
            self.update_events.put(("progress", (received, total)))

        def worker():
            try:
                path = download_update(info, progress_callback=progress)
                self.update_events.put(("downloaded", str(path)))
            except Exception as exc:
                self.update_events.put(("download_error", str(exc)))

        threading.Thread(target=worker, daemon=True, name="YUGITOUpdateDownload").start()

    def _launch_downloaded_update(self, package_path: Path):
        if self.update_info is None:
            return
        updater = PROJECT_ROOT / "updater.py"
        install_root = PROJECT_ROOT.parent
        if not updater.exists():
            self.update_busy = False
            self.update_status = "Updater YUGITO introuvable."
            self.redraw()
            return
        try:
            # IMPORTANT WINDOWS : l'Updater ne doit JAMAIS s'exécuter depuis
            # le dossier app qu'il va remplacer. Un processus dont le dossier
            # de travail se trouve dans app peut empêcher Windows de renommer
            # ce dossier (WinError 32). On copie donc le script dans %TEMP% et
            # on le lance avec %TEMP% comme dossier de travail.
            updater_temp_dir = Path(tempfile.gettempdir()) / "YUGITO_Updater"
            updater_temp_dir.mkdir(parents=True, exist_ok=True)
            safe_version = re.sub(r"[^0-9A-Za-z_.-]+", "_", self.update_info.version)
            temp_updater = updater_temp_dir / f"updater_{safe_version}_{os.getpid()}.py"
            temp_updater.write_bytes(updater.read_bytes())

            creationflags = getattr(subprocess, "CREATE_NO_WINDOW", 0) if os.name == "nt" else 0
            subprocess.Popen(
                [
                    sys.executable, str(temp_updater),
                    "--package", str(package_path),
                    "--version", self.update_info.version,
                    "--install-root", str(install_root),
                    "--parent-pid", str(os.getpid()),
                ],
                cwd=str(updater_temp_dir),
                creationflags=creationflags,
                close_fds=True,
            )
            self.update_status = "YUGITO va redemarrer automatiquement..."
            self.redraw()
            self.root.after(350, self._close_app)
        except Exception as exc:
            self.update_busy = False
            self.update_status = f"Impossible de lancer l'Updater : {exc}"
            self.redraw()

    def _draw_update_screen(self):
        self._gradient_background("#101827", "#05080d")
        self.canvas.delete("all")
        self.click_regions.clear()
        self._rect(175, 85, 1425, 815, fill="#0e1520", outline="#3a465b", width=2, radius=28)
        self._rect(175, 85, 1425, 205, fill="#151f2d", outline="", radius=28)
        self._rect(175, 180, 1425, 205, fill="#151f2d", outline="")
        self._text(235, 126, "YUGITO", size=34, weight="bold", anchor="w", family=DISPLAY_FONT_TOKEN)
        self._text(235, 171, "MISE A JOUR OFFICIELLE", size=13, fill=ACCENT_2, weight="bold", anchor="w")
        self._text(1365, 135, f"VERSION INSTALLEE  {APP_VERSION}", size=10, fill=MUTED, weight="bold", anchor="e")

        info = self.update_info
        if info is None:
            self._text(800, 420, "Verification des mises a jour...", size=23, weight="bold")
            return

        self._text(240, 260, "NOUVELLE VERSION DISPONIBLE", size=23, weight="bold", anchor="w")
        self._text(240, 312, f"YUGITO V{info.version}", size=31, fill=GREEN, weight="bold", anchor="w", family=DISPLAY_FONT_TOKEN)
        title = info.title.strip() or f"YUGITO V{info.version}"
        self._text(240, 360, title, size=13, fill="#dfe7f2", weight="bold", anchor="w", width=1080, justify="left")

        notes = (info.notes or "Mise a jour YUGITO disponible.").strip()
        # Le Canvas gere le retour a la ligne ; on limite juste une Release abusement longue.
        if len(notes) > 1100:
            notes = notes[:1097] + "..."
        self._rect(235, 395, 1365, 595, fill="#111a27", outline="#2d3b50", width=1, radius=16)
        self._text(270, 425, "NOTES DE MISE A JOUR", size=11, fill=ACCENT_2, weight="bold", anchor="nw")
        self._text(270, 465, notes, size=11, fill="#cbd5e3", anchor="nw", width=1020, justify="left")

        # Barre de progression dans la DA YUGITO.
        self._rect(240, 630, 1360, 668, fill="#111824", outline="#36465d", width=1, radius=12)
        fill_w = 1116 * max(0.0, min(1.0, float(self.update_progress)))
        if fill_w > 1:
            self._rect(242, 632, 242 + fill_w, 666, fill=ACCENT, outline="", radius=10)
        self._text(800, 695, self.update_status, size=10, fill=MUTED, weight="bold")

        if not self.update_busy:
            self._button(240, 725, 760, 785, "METTRE A JOUR", self._begin_update_download, fill="#1b261f", accent=GREEN)
            self._button(785, 725, 1100, 785, "PLUS TARD", self._update_later, fill="#171d27", accent="#66758c")
        else:
            self._rect(240, 725, 1100, 785, fill="#141a24", outline="#293548", width=1, radius=12)
            self._text(670, 755, "TELECHARGEMENT ET VERIFICATION EN COURS...", size=12, fill="#d9e1ec", weight="bold")
        self._text(1365, 755, "Source : GitHub / hakamah/YUGITO-Releases", size=8, fill="#6f7f95", anchor="e")


    # ------------------------------------------------------------------
    # Classic 1.1.4 - Compte YUGITO lié à Google
    # ------------------------------------------------------------------
    def _identity_registry(self) -> InternetIdentityRegistry:
        # Le registre MQTT n'est plus l'autorité de compte. Il reste seulement
        # un annuaire compatible avec l'espace social historique.
        return InternetIdentityRegistry(
            self.identity_broker_host,
            self.identity_broker_port,
            self.identity_broker_tls,
        )

    def _apply_identity_to_network(self):
        if self.identity is not None and hasattr(self, "network"):
            self.network.display_name = self.identity.pseudo

    def _local_pseudo(self) -> str:
        return self.identity.pseudo if self.identity is not None else "Joueur"

    def _player_display_name(self, player_number: int) -> str:
        if self.current_mode and self.current_mode.id == "multiplayer":
            if self.network_local_player == 0 and self.multiplayer_match_type == "tournament" and self.tournament_state:
                pair = self.tournament_state.get("current_pair") or {}
                members = dict(self.tournament_state.get("members") or {})
                aid = str(pair.get("p1") if player_number == 1 else pair.get("p2") or "")
                return str(members.get(aid) or ("Joueur 1" if player_number == 1 else "Joueur 2"))
            if self.network_local_player == player_number:
                return self._local_pseudo()
            if self.network_local_player in (1, 2):
                return self.network_peer_name or getattr(self.network, "peer_display_name", "") or "Adversaire"
            return self._local_pseudo() if player_number == 1 else "Adversaire"
        if self.current_mode and self.current_mode.id == "solo_ai":
            return self._local_pseudo() if player_number == 1 else "IA"
        return f"Joueur {player_number}"

    def _hide_identity_entry(self):
        if hasattr(self, "identity_entry"):
            try:
                self.identity_entry.place_forget()
            except tk.TclError:
                pass

    def _place_identity_entry(self):
        if (
            self.current_screen != "identity"
            or self.identity_stage != "pseudo"
            or not hasattr(self, "identity_entry")
        ):
            self._hide_identity_entry()
            return
        x1, y1 = self.P(520, 465)
        x2, y2 = self.P(1080, 535)
        scale, _, _ = self._scale()
        try:
            self.identity_entry.configure(font=(self.ui_font_family, max(12, int(18 * scale)), "bold"))
            self.identity_entry.place(x=int(x1), y=int(y1), width=max(200, int(x2-x1)), height=max(42, int(y2-y1)))
            self.identity_entry.lift()
        except tk.TclError:
            pass

    def show_identity_screen(self, stage: str | None = None):
        self.current_screen = "identity"
        self.current_mode = None
        if stage:
            self.identity_stage = stage
        if self.identity_stage == "pseudo":
            if not self.identity_input_var.get().strip() and self.legacy_identity is not None:
                self.identity_input_var.set(self.legacy_identity.pseudo)
        else:
            self._hide_identity_entry()
        self.redraw()
        if self.identity_stage == "pseudo":
            self.root.after_idle(lambda: self.identity_entry.focus_set() if hasattr(self, "identity_entry") else None)

    def _draw_identity_screen(self):
        self._gradient_background("#101827", "#05080d")
        self._rect(220, 80, 1380, 820, fill="#0d1521", outline="#34465f", width=2, radius=28)
        self._rect(260, 120, 1340, 250, fill="#151f2e", outline="#27364a", width=1, radius=20)
        self._text(800, 165, "YUGITO", size=46, weight="bold", family=DISPLAY_FONT_TOKEN)
        self._text(800, 218, "COMPTE YUGITO • GOOGLE", size=20, fill="#f0e4d5", weight="bold")

        if self.identity_stage == "pseudo":
            self._text(800, 305, "GOOGLE EST CONNECTE", size=17, fill=GREEN, weight="bold")
            email = str(self.pending_google_account.get("email") or "")
            if email:
                self._text(800, 340, email, size=10, fill="#8fa4bf", weight="bold")
            self._text(
                800, 390,
                "Ce compte Google n'a encore aucun pseudo YUGITO enregistré.\n"
                "Ce choix n'apparaît qu'une seule fois pour un nouveau compte.",
                size=12, fill=MUTED, justify="center", width=920,
            )
            self._text(800, 450, "TON PSEUDO", size=12, fill=GOLD, weight="bold")
            self._rect(500, 450, 1100, 550, fill="#0a111c", outline="#7c4b2d", width=2, radius=16)
            self._place_identity_entry()
            self._text(800, 570, "3 à 20 caractères • lettres, chiffres, espaces, - et _", size=9, fill="#8492a6")
            button_label = "ENREGISTREMENT…" if self.identity_busy else "VALIDER MON PSEUDO"
            self._button(555, 690, 1045, 755, button_label, self._submit_identity_entry, fill="#231d18", accent=ACCENT, enabled=not self.identity_busy)
        else:
            self._hide_identity_entry()
            self._text(800, 315, "UNE IDENTITE UNIQUE SUR PC ET MOBILE", size=18, fill=GREEN, weight="bold")
            self._text(
                800, 370,
                "À partir de YUGITO 1.1.4, ton compte n'est plus un token local.\n"
                "Connecte Google pour retrouver la même identité YUGITO sur Windows et Android.",
                size=13, fill=MUTED, justify="center", width=940,
            )
            self._rect(475, 455, 1125, 565, fill="#0a111c", outline="#33465e", width=2, radius=18)
            self._text(800, 490, "ANCIENS TOKENS LOCAUX", size=11, fill=GOLD, weight="bold")
            legacy_text = "SUPPRIME DE CE PC"
            if self.legacy_identity is not None:
                legacy_text += f" • migration disponible pour {self.legacy_identity.pseudo}"
            self._text(800, 530, legacy_text, size=10, fill="#9ec7a8", weight="bold", width=590)
            button_label = "CONNEXION EN COURS…" if self.identity_busy else "SE CONNECTER AVEC GOOGLE"
            self._button(500, 655, 1100, 730, button_label, self._begin_google_login, fill="#17243a", accent="#6ba7ff", enabled=not self.identity_busy)
            self._text(800, 765, "Google utilise sa fenêtre sécurisée. YUGITO reprend automatiquement dès la validation.", size=9, fill="#6f7e91")

        status_fill = GREEN if ("connect" in self.identity_network_status.lower() or "google" in self.identity_network_status.lower()) and "indisponible" not in self.identity_network_status.lower() else MUTED
        self._text(800, 610, self.identity_network_status, size=10, fill=status_fill, weight="bold")
        if self.identity_notice:
            fitted, fsize = self._fit_text_box(self.identity_notice, 920, 48, start_size=10, min_size=7, max_lines=2)
            self._text(800, 635, fitted, size=fsize, fill="#f2b2b2", weight="bold", justify="center", width=920)

    def _begin_google_login(self):
        if self.identity_busy:
            return
        self.identity_busy = True
        self.identity_notice = "Préparation de la connexion Google…"
        self.identity_network_status = "Connexion au serveur de comptes YUGITO…"
        self.redraw()

        def worker():
            try:
                start = self.auth_client.start_device("windows")
                self.identity_events.put(("auth_device_started", start))
                code = str(start.get("device_code") or "")
                interval = max(1.0, float(start.get("interval") or 2.0))
                deadline = time.time() + max(60.0, float(start.get("expires_in") or 600))
                while time.time() < deadline:
                    time.sleep(interval)
                    try:
                        status = self.auth_client.device_status(code)
                    except AuthRejectedError as exc:
                        if exc.status == 410:
                            self.identity_events.put(("auth_error", "La connexion Google a expiré. Relance-la depuis YUGITO."))
                            return
                        raise
                    state = str(status.get("status") or "")
                    if state == "authenticated":
                        self.identity_events.put(("auth_authenticated", status))
                        return
                    if state == "expired":
                        self.identity_events.put(("auth_error", "La connexion Google a expiré. Relance-la depuis YUGITO."))
                        return
                self.identity_events.put(("auth_error", "La connexion Google a expiré. Relance-la depuis YUGITO."))
            except Exception as exc:
                self.identity_events.put(("auth_error", str(exc)))

        threading.Thread(target=worker, name="YUGITO-GoogleLogin", daemon=True).start()

    def _submit_identity_entry(self, _event=None):
        if self.identity_busy or self.identity_stage != "pseudo":
            return "break"
        ok, message, clean = validate_pseudo(self.identity_input_var.get())
        if not ok:
            self.identity_notice = message
            self.redraw()
            return "break"
        if not self.pending_google_token:
            self.identity_notice = "La session Google n'est plus disponible. Recommence la connexion."
            self.identity_stage = "google"
            self.redraw()
            return "break"
        self.identity_input_var.set(clean)
        self.identity_busy = True
        self.identity_notice = "Enregistrement du pseudo sur ton compte Google YUGITO…"
        self.redraw()

        legacy = self.legacy_identity
        legacy_profile = dict(self.legacy_ranked_profile or {})
        legacy_payload = None
        if legacy is not None and normalize_pseudo(legacy.pseudo) == normalize_pseudo(clean):
            legacy_payload = {
                "pseudo": legacy.pseudo,
                "account_id": legacy.account_id,
                "token": legacy.token,
                "elo": normalize_elo(legacy_profile.get("elo", DEFAULT_ELO)),
            }

        token = self.pending_google_token
        hint = dict(self.auth_identity_hint or {})
        recovery_payload = None
        if hint and normalize_pseudo(hint.get("pseudo")) == normalize_pseudo(clean):
            recovery_payload = {
                "pseudo": str(hint.get("pseudo") or clean),
                "account_id": str(hint.get("account_id") or ""),
                "email": str(hint.get("email") or ""),
                "recovery_token": str(hint.get("recovery_token") or ""),
            }

        def worker():
            try:
                result = self.auth_client.claim_pseudo(token, clean, legacy=legacy_payload, recovery=recovery_payload)
                self.identity_events.put(("auth_claimed", (str(result.get("session_token") or token), result)))
            except Exception as exc:
                self.identity_events.put(("register_error", str(exc)))

        threading.Thread(target=worker, name="YUGITO-GooglePseudo", daemon=True).start()
        return "break"

    def _complete_google_identity(self, session_token: str, account: dict, *, migrated_legacy: bool = False):
        account = dict(account or {})
        pseudo = str(account.get("pseudo") or "").strip()
        aid = str(account.get("account_id") or "").strip()
        if not pseudo or not aid or len(str(session_token or "")) < 32:
            raise AuthError("Le serveur n'a pas renvoyé un compte YUGITO complet.")

        old_legacy = self.legacy_identity
        old_profile = dict(self.legacy_ranked_profile or {})
        session = self.auth_session_store.save(str(session_token), account)
        self.identity = session.identity
        self.auth_account = dict(account)
        try:
            self.auth_identity_hint = self.auth_hint_store.save(self.auth_account)
        except Exception:
            pass
        self.ranked = RankedStore(self.identity)

        remote_elo = normalize_elo(account.get("elo", DEFAULT_ELO))
        # Si le serveur 1.1.4 vient de reprendre exactement l'ancien account_id,
        # le profil DPAPI local est encore la meilleure source pour la toute
        # première migration. Il est ensuite synchronisé vers le serveur.
        if old_legacy is not None and aid == old_legacy.account_id and old_profile:
            local_elo = normalize_elo(old_profile.get("elo", DEFAULT_ELO))
            remote_elo = max(remote_elo, local_elo)
            try:
                self.ranked.data["ranked_matches"] = max(int(self.ranked.data.get("ranked_matches") or 0), int(old_profile.get("ranked_matches") or 0))
                self.ranked.data["wins"] = max(int(self.ranked.data.get("wins") or 0), int(old_profile.get("wins") or 0))
                self.ranked.data["losses"] = max(int(self.ranked.data.get("losses") or 0), int(old_profile.get("losses") or 0))
                self.ranked.data["best_elo"] = max(normalize_elo(self.ranked.data.get("best_elo")), normalize_elo(old_profile.get("best_elo", remote_elo)))
            except Exception:
                pass
        self.ranked.sync_from_server(remote_elo)
        self.auth_account["elo"] = self.ranked.elo
        try:
            self.auth_session_store.save(str(session_token), self.auth_account)
        except Exception:
            pass

        self.pending_google_token = ""
        self.pending_google_account = {}
        self.identity_stage = "ready"
        self.identity_busy = False
        self.identity_notice = ""
        self.identity_conflict = False
        self.identity_network_status = "Compte Google YUGITO connecté"
        self._apply_identity_to_network()
        self._start_social_manager()

        # Rotation de l'ancien annuaire MQTT en arrière-plan. L'ancien token
        # n'est conservé que dans cette closure le temps de la migration.
        identity_now = self.identity
        def promote_worker():
            try:
                self._identity_registry().promote_google(identity_now, old_legacy, timeout=6.0)
            except Exception:
                pass
        threading.Thread(target=promote_worker, name="YUGITO-GoogleRegistry", daemon=True).start()

        # Le token legacy n'est plus nécessaire après cette ligne.
        self.legacy_identity = None
        self.legacy_ranked_profile = None
        self.notice = f"Bienvenue, {self.identity.pseudo}. Compte Google lié."
        self.show_main_menu()
        self._sync_ranked_profile_to_server()

    def _sync_ranked_profile_to_server(self):
        if self.identity is None or self.identity.auth_mode != "google" or self.ranked is None:
            return
        token = self.identity.token
        profile = self.ranked.profile()
        def worker():
            try:
                result = self.auth_client.sync_elo(token, self.ranked.elo, profile)
                if isinstance(result, dict) and result.get("ok") and isinstance(result.get("account"), dict):
                    self.identity_events.put(("elo_synced", (str(result.get("session_token") or token), dict(result["account"]), dict(result.get("profile") or {}))))
            except Exception:
                # Une panne du service de profil ne doit pas casser un duel fini.
                pass
        threading.Thread(target=worker, name="YUGITO-EloSync", daemon=True).start()

    def _background_online_boot(self):
        # La connexion Internet du duel se prépare discrètement. Le compte
        # Google utilise son propre service HTTPS et n'est plus créé via MQTT.
        if not hasattr(self, "network") or not isinstance(self.network, InternetNetworkManager):
            return
        if self.identity is None:
            self.identity_network_status = "Connexion Google requise"
        if self.current_screen == "identity":
            self.redraw()

        def worker():
            try:
                ok, msg = self.network.test_connectivity()
                self.identity_events.put(("connectivity", (ok, msg)))
            except Exception as exc:
                self.identity_events.put(("connectivity", (False, str(exc))))

        threading.Thread(target=worker, name="YUGITO-OnlineBoot", daemon=True).start()

    def _start_identity_verify(self):
        if self.identity is None or self.identity_busy or self.identity.auth_mode != "google":
            return
        token = self.identity.token

        def worker():
            try:
                account = self.auth_client.me(token)
                self.identity_events.put(("verified", account))
            except AuthRejectedError as exc:
                if exc.status == 401:
                    self.identity_events.put(("auth_invalid", "Ta session YUGITO a expiré. Reconnecte ton compte Google."))
                else:
                    self.identity_events.put(("verify_offline", str(exc)))
            except Exception as exc:
                # Une panne Render/Internet ne supprime pas une session locale
                # encore valide : le joueur peut au moins accéder au jeu.
                self.identity_events.put(("verify_offline", str(exc)))

        threading.Thread(target=worker, name="YUGITO-GoogleVerify", daemon=True).start()

    def _poll_identity_events(self):
        try:
            while True:
                kind, payload = self.identity_events.get_nowait()
                if kind == "connectivity":
                    ok, msg = payload
                    if self.identity is None and not self.identity_busy:
                        self.identity_network_status = "Connexion Google requise"
                    elif ok:
                        self.identity_network_status = "Réseau YUGITO connecté"
                    else:
                        self.identity_network_status = "Réseau de duel indisponible"
                    if not ok and self.current_screen == "identity" and not self.identity_busy:
                        self.identity_notice = str(msg)
                elif kind == "auth_device_started":
                    data = dict(payload or {})
                    self.identity_network_status = "Validation Google sécurisée en cours"
                    self.identity_notice = "Choisis ton compte Google. YUGITO reprendra automatiquement ensuite."
                    url = str(data.get("verification_url") or "")
                    if url:
                        try:
                            webbrowser.open(url, new=2)
                        except Exception:
                            self.identity_notice = "Ouvre ce lien dans ton navigateur : " + url
                elif kind == "auth_authenticated":
                    data = dict(payload or {})
                    token = str(data.get("session_token") or "")
                    account = dict(data.get("account") or {})
                    if not token or not account:
                        self.identity_busy = False
                        self.identity_notice = "Connexion Google incomplète. Recommence."
                    elif str(account.get("pseudo") or "").strip():
                        try:
                            self._complete_google_identity(token, account)
                            try:
                                self.root.deiconify(); self.root.lift(); self.root.focus_force()
                            except Exception:
                                pass
                        except Exception as exc:
                            self.identity_busy = False
                            self.identity_notice = str(exc)
                    else:
                        # 1.1.8 : si ce Google avait déjà une identité connue sur ce
                        # PC, on la restaure silencieusement. Plus de demande de pseudo
                        # après une simple MAJ / perte de la SQLite Render.
                        hint = dict(self.auth_identity_hint or {})
                        email_ok = (
                            bool(hint.get("pseudo"))
                            and bool(hint.get("account_id"))
                            and str(hint.get("email") or "").strip().casefold()
                                == str(account.get("email") or "").strip().casefold()
                        )
                        if email_ok:
                            self.identity_busy = True
                            self.identity_network_status = "Récupération automatique de ton identité YUGITO…"
                            self.identity_notice = f"Compte Google reconnu • restauration de {hint.get('pseudo')}"
                            recovery = {
                                "pseudo": str(hint.get("pseudo") or ""),
                                "account_id": str(hint.get("account_id") or ""),
                                "email": str(hint.get("email") or ""),
                                "recovery_token": str(hint.get("recovery_token") or ""),
                            }
                            def recover_worker():
                                try:
                                    result = self.auth_client.claim_pseudo(token, str(hint.get("pseudo") or ""), recovery=recovery)
                                    self.identity_events.put(("auth_claimed", (str(result.get("session_token") or token), result)))
                                except Exception as exc:
                                    self.identity_events.put(("auth_auto_recover_failed", (token, account, str(exc))))
                            threading.Thread(target=recover_worker, name="YUGITO-GoogleAutoRecover", daemon=True).start()
                        else:
                            self.pending_google_token = token
                            self.pending_google_account = account
                            self.identity_busy = False
                            self.identity_stage = "pseudo"
                            self.identity_network_status = "Nouveau compte Google • choisis ton pseudo YUGITO"
                            self.identity_notice = ""
                            self.identity_input_var.set(self.legacy_identity.pseudo if self.legacy_identity is not None else "")
                            self.show_identity_screen("pseudo")
                elif kind == "auth_auto_recover_failed":
                    token, account, message = payload
                    self.pending_google_token = str(token)
                    self.pending_google_account = dict(account or {})
                    self.identity_busy = False
                    self.identity_stage = "pseudo"
                    self.identity_network_status = "Récupération automatique impossible"
                    self.identity_notice = "Ton ancien pseudo n'a pas pu être restauré automatiquement : " + str(message)
                    hint = dict(self.auth_identity_hint or {})
                    self.identity_input_var.set(str(hint.get("pseudo") or ""))
                    self.show_identity_screen("pseudo")
                elif kind == "auth_claimed":
                    token, result = payload
                    result = dict(result or {})
                    try:
                        self._complete_google_identity(str(token), dict(result.get("account") or {}), migrated_legacy=bool(result.get("migrated_legacy")))
                    except Exception as exc:
                        self.identity_busy = False
                        self.identity_notice = str(exc)
                elif kind in {"auth_error", "register_error"}:
                    self.identity_busy = False
                    self.identity_notice = str(payload)
                elif kind == "verified":
                    account = dict(payload or {})
                    # Un token signé 1.1.8 restaure déjà le compte même si Render
                    # vient de redémarrer. Le pseudo serveur ne doit donc plus
                    # redevenir vide après une mise à jour.
                    if not str(account.get("pseudo") or "").strip() and self.identity is not None:
                        account["pseudo"] = self.identity.pseudo
                        account["account_id"] = self.identity.account_id
                    self.auth_account = account
                    try:
                        self.auth_identity_hint = self.auth_hint_store.save(account)
                    except Exception:
                        pass
                    self.identity_network_status = "Compte Google YUGITO vérifié"
                    if self.ranked is not None:
                        try:
                            if self.ranked_needs_server_push:
                                self._sync_ranked_profile_to_server()
                            else:
                                self.ranked.sync_from_server(account.get("elo", self.ranked.elo))
                        except Exception:
                            pass
                    try:
                        self.auth_session_store.save(self.identity.token, account)
                    except Exception:
                        pass
                elif kind == "elo_synced":
                    if isinstance(payload, (tuple, list)) and len(payload) >= 3:
                        new_token, account, server_profile = payload[0], payload[1], payload[2]
                    else:
                        new_token, account = payload
                        server_profile = {}
                    account = dict(account or {})
                    self.auth_account.update(account)
                    if self.identity is not None and str(new_token or "") and str(new_token) != self.identity.token:
                        try:
                            session = self.auth_session_store.save(str(new_token), self.auth_account)
                            self.identity = session.identity
                        except Exception:
                            pass
                    try:
                        self.auth_identity_hint = self.auth_hint_store.save(self.auth_account)
                    except Exception:
                        pass
                    self.ranked_needs_server_push = False
                    if self.ranked is not None and server_profile:
                        try:
                            self.ranked.sync_profile_from_server(server_profile, account.get("elo"))
                        except Exception:
                            pass
                    if self.ranked is not None:
                        self.ranked.data.pop("last_forfeit_recovered", None)
                        try:
                            self.ranked.save()
                        except Exception:
                            pass
                    try:
                        self.auth_session_store.save(self.identity.token, self.auth_account)
                    except Exception:
                        pass
                elif kind == "economy_state":
                    self.economy_state=dict(payload or {}); self.economy_state["economy_available"]=True
                    self.economy_loaded=True; self.economy_busy=False; self.economy_last_refresh=time.time(); self.economy_notice=""
                    if self.current_screen in {"menu","shop","deck_builder","multiplayer"}: self.redraw()
                elif kind == "economy_error":
                    self.economy_busy=False; self.economy_loaded=True
                    self.economy_state={"economy_available":False,"yt_balance":0,"available_card_ids":[],"owned_card_ids":[],"free_card_ids":[],"base_card_ids":[]}
                    self.economy_notice=str(payload)
                    if self.current_screen in {"menu","shop","deck_builder","multiplayer"}: self.redraw()
                elif kind == "economy_purchase":
                    data=dict(payload or {}); st=dict(data.get("state") or {})
                    # purchase/state compact may omit catalog: preserve current catalog.
                    if st:
                        st.setdefault("catalog",self.economy_state.get("catalog",[])); st["economy_available"]=True; self.economy_state=st
                    self.economy_busy=False; self.economy_loaded=True; self.economy_last_refresh=time.time(); self.economy_notice="Achat validé définitivement ✓"
                    self._economy_refresh_async(force=True); self.redraw()
                elif kind == "economy_purchase_error":
                    self.economy_busy=False; self.economy_notice=str(payload); self.redraw()
                elif kind == "economy_own_permit":
                    self.economy_own_permit=str(payload or "")
                    if self.economy_own_permit and getattr(self.network,"connected",False):
                        self._net_send({"type":"economy_hello","permit":self.economy_own_permit,"match_id":self.economy_match_id if self.network_lobby_role=="host" else ""})
                    # Les deux permis peuvent arriver dans n'importe quel ordre.
                    if self.network_lobby_role=="host" and self._economy_multiplayer_ready():
                        if self.multiplayer_match_type=="ranked": self.root.after(150,self._start_ranked_duel_if_ready)
                        elif self.multiplayer_match_type=="private" and self.social_private_autostart: self.root.after(150,self._start_social_private_duel_if_ready)
                        elif self.multiplayer_match_type=="tournament": self.root.after(150,self._start_tournament_duel_if_ready)
                    if self.current_screen=="multiplayer": self.redraw()
                elif kind == "economy_permit_error":
                    self.economy_own_permit=""; self.economy_notice=str(payload); self.notice="Matchmaking sécurisé indisponible : "+str(payload); self.redraw()
                elif kind == "economy_peer_verified":
                    permit,info=payload; self.economy_peer_permit=str(permit); self.economy_peer_account_id=str(info.get("aid") or "")
                    self.economy_peer_available_ids={str(x) for x in info.get("available",[])}; self.economy_peer_verified=bool(self.economy_peer_account_id)
                    if self.current_screen=="multiplayer": self.redraw()
                    if self.network_lobby_role=="host" and self._economy_multiplayer_ready():
                        if self.multiplayer_match_type=="ranked": self.root.after(150,self._start_ranked_duel_if_ready)
                        elif self.multiplayer_match_type=="private" and self.social_private_autostart: self.root.after(150,self._start_social_private_duel_if_ready)
                        elif self.multiplayer_match_type=="tournament": self.root.after(150,self._start_tournament_duel_if_ready)
                elif kind == "economy_peer_error":
                    self.economy_peer_verified=False; self.economy_peer_permit=""; self.notice="Collection adverse non vérifiée : "+str(payload); self.redraw()
                elif kind == "economy_match_settled":
                    data=dict(payload or {}); st=dict(data.get("state") or {})
                    if st:
                        st.setdefault("catalog",self.economy_state.get("catalog",[])); st["economy_available"]=True; self.economy_state=st
                    rw=int(data.get("reward_winner") or 0); rl=int(data.get("reward_loser") or 0)
                    self.economy_notice=f"Récompenses YT validées : gagnant +{rw} • perdant +{rl}"
                    if self.current_screen=="duel": self.redraw()
                elif kind == "economy_match_error":
                    self.economy_notice="Résultat YT non validé : "+str(payload)
                    if self.current_screen=="duel": self.redraw()
                elif kind == "verify_offline":
                    self.identity_network_status = "Compte Google local actif • serveur temporairement indisponible"
                elif kind == "auth_invalid":
                    if self.social is not None:
                        try:
                            self.social.stop()
                        except Exception:
                            pass
                        self.social = None
                    try:
                        if self.auth_account:
                            self.auth_identity_hint = self.auth_hint_store.save(self.auth_account)
                    except Exception:
                        pass
                    self.auth_session_store.clear()
                    self.identity = None
                    self.ranked = None
                    self.auth_account = {}
                    self.identity_busy = False
                    self.identity_stage = "google"
                    self.identity_notice = str(payload)
                    self.identity_network_status = "Connexion Google requise"
                    self.show_identity_screen("google")
                if self.current_screen == "identity":
                    self.redraw()
        except queue.Empty:
            pass
        self.root.after(150, self._poll_identity_events)


    # ------------------------------------------------------------------
    # Classic 1.0.3 - Espace social : amis / MP / invitations privées
    # ------------------------------------------------------------------
    def _start_social_manager(self):
        if self.identity is None:
            return
        if self.social is not None:
            try:
                self.social.stop()
            except Exception:
                pass
        try:
            self.social = SocialManager(
                self.identity,
                self.identity_broker_host,
                self.identity_broker_port,
                self.identity_broker_tls,
                self.auth_client,
                self.identity.token,
            )
            self.social.profile_provider = (lambda: self.ranked.profile() if self.ranked is not None else {"elo": DEFAULT_ELO})
            self.social.start()
        except Exception as exc:
            self.social = None
            self.social_notice = f"Réseau social indisponible : {exc}"

    def _hide_social_entries(self):
        for name in ("social_add_entry", "social_dm_entry"):
            widget = getattr(self, name, None)
            if widget is not None:
                try:
                    widget.place_forget()
                except Exception:
                    pass

    def _place_social_entry(self, widget, x1, y1, x2, y2, *, font_size=11, bold=False):
        if widget is None or self.current_screen != "social":
            return
        sx, sy = self.P(x1, y1)
        ex, ey = self.P(x2, y2)
        scale, _, _ = self._scale()
        try:
            widget.configure(font=(self.ui_font_family, max(9, int(font_size * scale)), "bold" if bold else "normal"))
            widget.place(x=int(sx), y=int(sy), width=max(80, int(ex - sx)), height=max(30, int(ey - sy)))
            widget.lift()
        except Exception:
            pass

    def show_social(self):
        if self.identity is None:
            self.show_identity_screen()
            return
        if self.social is None:
            self._start_social_manager()
        if self.social is not None:
            try:
                self.social.refresh_presence()
            except Exception:
                pass
        self.current_screen = "social"
        self.social_notice = ""
        friends = self.social.friends_snapshot() if self.social is not None else []
        ids = {f["account_id"] for f in friends}
        if self.social_selected_friend_id not in ids:
            self.social_selected_friend_id = friends[0]["account_id"] if friends else None
        if self.social_selected_friend_id:
            self.social_unread.discard(self.social_selected_friend_id)
        self.redraw()

    def _social_select_friend(self, account_id: str):
        self.social_selected_friend_id = str(account_id)
        self.social_unread.discard(str(account_id))
        self.social_notice = ""
        self.redraw()
        try:
            self.social_dm_entry.focus_set()
        except Exception:
            pass

    def _social_friend_page_change(self, delta: int):
        if self.social is None:
            return
        friends = self.social.friends_snapshot()
        max_page = max(0, (len(friends) - 1) // 7)
        self.social_friend_page = max(0, min(max_page, self.social_friend_page + int(delta)))
        self.redraw()

    def _social_submit_add(self, _event=None):
        if self.social is None or self.social_busy:
            return "break"
        pseudo = self.social_add_var.get().strip()
        if not pseudo:
            self.social_notice = "Entre le pseudo exact du joueur."
            self.redraw()
            return "break"
        self.social_busy = True
        self.social_notice = f"Recherche de {pseudo} sur le réseau YUGITO…"
        self.redraw()

        def worker():
            try:
                ok, msg = self.social.request_friend(pseudo) if self.social is not None else (False, "Réseau social indisponible.")
                if self.social is not None:
                    self.social.events.put({"type": "ui_friend_request_result", "ok": ok, "message": msg})
            except Exception as exc:
                if self.social is not None:
                    self.social.events.put({"type": "ui_friend_request_result", "ok": False, "message": str(exc)})

        threading.Thread(target=worker, daemon=True, name="YUGITO-FriendRequest").start()
        return "break"

    def _social_submit_dm(self, _event=None):
        if self.social is None:
            return "break"
        text = self.social_dm_var.get()
        if self.social_tab == "groups":
            if not self.social_selected_group_id:
                return "break"
            ok, msg = self.social.send_group_message(self.social_selected_group_id, text)
        else:
            if not self.social_selected_friend_id:
                return "break"
            ok, msg = self.social.send_dm(self.social_selected_friend_id, text)
        self.social_notice = msg
        if ok:
            self.social_dm_var.set("")
        self.redraw()
        return "break"

    def _social_accept_request(self, account_id: str):
        if self.social is not None and self.social.accept_friend(account_id):
            self.social_selected_friend_id = str(account_id)
            self.social_notice = "Demande acceptée. Vous êtes maintenant amis."
            self.redraw()

    def _social_reject_request(self, account_id: str):
        if self.social is not None and self.social.reject_friend(account_id):
            self.social_notice = "Demande refusée."
            self.redraw()

    def _social_remove_selected(self):
        if self.social is None or not self.social_selected_friend_id:
            return
        friend_id = self.social_selected_friend_id
        friend = self.social.store.friends.get(friend_id, {})
        pseudo = str(friend.get("pseudo") or "cet ami")
        if self.social.remove_friend(friend_id):
            self.social_selected_friend_id = None
            self.social_notice = f"{pseudo} a été retiré de tes amis."
            self.show_social()

    def _social_switch_tab(self, tab: str):
        self.social_tab = "groups" if tab == "groups" else "friends"
        self.social_notice = ""
        if self.social_tab == "groups" and self.social is not None:
            groups = self.social.groups_snapshot()
            ids = {g.get("group_id") for g in groups}
            if self.social_selected_group_id not in ids:
                self.social_selected_group_id = str(groups[0].get("group_id")) if groups else None
            if self.social_selected_group_id:
                self.social_group_unread.discard(self.social_selected_group_id)
        self.redraw()

    def _social_toggle_friend_flag(self, flag: str):
        if self.social is None or not self.social_selected_friend_id:
            return
        value = self.social.toggle_friend_flag(self.social_selected_friend_id, flag)
        labels = {
            "blocked": "bloqué" if value else "débloqué",
            "muted": "mis en muet" if value else "retiré du muet",
            "ignore_invites": "invitations ignorées" if value else "invitations réactivées",
        }
        self.social_notice = labels.get(flag, "Préférence mise à jour.")
        self.redraw()

    def _social_show_profile(self):
        if self.social_selected_friend_id:
            self.social_profile_friend_id = str(self.social_selected_friend_id)
            self.redraw()

    def _social_close_profile(self):
        self.social_profile_friend_id = None
        self.redraw()

    def _social_create_group_with_selected(self):
        if self.social is None or not self.social_selected_friend_id:
            return
        ok, msg, gid = self.social.create_group_with_friend(self.social_selected_friend_id)
        self.social_notice = msg
        if ok:
            self.social_selected_group_id = gid
            self.social_tab = "groups"
        self.redraw()

    def _social_select_group(self, group_id: str):
        self.social_selected_group_id = str(group_id)
        self.social_group_unread.discard(str(group_id))
        self.social_notice = ""
        self.redraw()
        try:
            self.social_dm_entry.focus_set()
        except Exception:
            pass

    def _social_add_selected_friend_to_group(self):
        if self.social is None or not self.social_selected_group_id or not self.social_selected_friend_id:
            return
        ok, msg = self.social.add_friend_to_group(self.social_selected_group_id, self.social_selected_friend_id)
        self.social_notice = msg
        self.redraw()

    # ------------------------------------------------------------------
    # Classic 1.1.2 - Tournois privés (2 à 5 joueurs)
    # ------------------------------------------------------------------
    def _social_start_tournament_from_group(self):
        if self.social is None or self.identity is None or not self.social_selected_group_id:
            return
        group = self.social.store.group(self.social_selected_group_id)
        if not group:
            return
        members = dict(group.get("members") or {})
        members[self.identity.account_id] = self.identity.pseudo
        if not (2 <= len(members) <= 5):
            self.social_notice = "Un tournoi privé doit contenir entre 2 et 5 joueurs."
            self.redraw()
            return
        tid = "TRN-" + __import__("secrets").token_hex(5)
        self.tournament_state = {
            "id": tid,
            "host_id": self.identity.account_id,
            "host_pseudo": self.identity.pseudo,
            "name": f"Tournoi de {self.identity.pseudo}",
            "members": members,
            "accepted": [self.identity.account_id],
            "stage": "waiting",
            "round": 0,
            "round_pairs": [],
            "round_winners": [],
            "current_pair": None,
            "handled_matches": [],
            "champion": None,
        }
        payload = {"tournament_id": tid, "host_id": self.identity.account_id, "host_pseudo": self.identity.pseudo, "name": self.tournament_state["name"], "members": members}
        for aid in members:
            if aid != self.identity.account_id:
                self.social.send_tournament_event(aid, "invite", payload)
        self.current_screen = "tournament"
        self.social_notice = "Invitations de tournoi envoyées."
        self.redraw()

    def _tournament_accept_invite(self):
        invite = dict(self.social_tournament_invite_pending or {})
        self.social_tournament_invite_pending = None
        if not invite or self.social is None or self.identity is None:
            return
        host_id = str(invite.get("host_id") or "")
        self.tournament_state = {
            "id": str(invite.get("tournament_id") or ""),
            "host_id": host_id,
            "host_pseudo": str(invite.get("host_pseudo") or "Shinobi"),
            "name": str(invite.get("name") or "Tournoi privé"),
            "members": dict(invite.get("members") or {}),
            "accepted": [self.identity.account_id],
            "stage": "waiting",
            "round": 0,
            "round_pairs": [],
            "round_winners": [],
            "current_pair": None,
            "handled_matches": [],
            "champion": None,
        }
        self.social.send_tournament_event(host_id, "accept", {"tournament_id": self.tournament_state["id"], "account_id": self.identity.account_id, "pseudo": self.identity.pseudo})
        self.current_screen = "tournament"
        self.redraw()

    def _tournament_reject_invite(self):
        invite = dict(self.social_tournament_invite_pending or {})
        self.social_tournament_invite_pending = None
        if invite and self.social is not None:
            self.social.send_tournament_event(str(invite.get("host_id") or ""), "reject", {"tournament_id": str(invite.get("tournament_id") or "")})
        self.notice = "Invitation de tournoi refusée."
        self.redraw()

    def _tournament_broadcast(self, event_name: str, data: dict):
        if self.social is None or self.identity is None or not self.tournament_state:
            return
        accepted = list(self.tournament_state.get("accepted") or [])
        for aid in accepted:
            if aid == self.identity.account_id:
                continue
            self.social.send_tournament_event(aid, event_name, data)

    def _tournament_sync(self):
        if not self.tournament_state:
            return
        data = {
            "tournament_id": self.tournament_state.get("id"),
            "accepted": list(self.tournament_state.get("accepted") or []),
            "stage": self.tournament_state.get("stage"),
            "round": int(self.tournament_state.get("round") or 0),
            "current_pair": self.tournament_state.get("current_pair"),
            "champion": self.tournament_state.get("champion"),
            "members": dict(self.tournament_state.get("members") or {}),
        }
        self._tournament_broadcast("sync", data)

    def _tournament_launch(self):
        if not self.tournament_state or self.identity is None:
            return
        if str(self.tournament_state.get("host_id")) != self.identity.account_id:
            return
        accepted = [aid for aid in self.tournament_state.get("accepted", []) if aid in self.tournament_state.get("members", {})]
        if len(accepted) < 2:
            self.social_notice = "Il faut au moins 2 joueurs ayant accepté."
            self.redraw()
            return
        # Ordre déterministe : pseudo puis account_id. Chaque round se joue
        # séquentiellement pour que tous les joueurs hors match soient spectateurs.
        members = dict(self.tournament_state.get("members") or {})
        accepted.sort(key=lambda aid: (str(members.get(aid, "")).casefold(), aid))
        self.tournament_state["round_players"] = accepted
        self.tournament_state["round"] = 0
        self.tournament_state["stage"] = "running"
        self._tournament_prepare_round()

    def _tournament_prepare_round(self):
        if not self.tournament_state:
            return
        players = list(self.tournament_state.get("round_players") or [])
        self.tournament_state["round"] = int(self.tournament_state.get("round") or 0) + 1
        pairs = []
        winners = []
        i = 0
        while i + 1 < len(players):
            pairs.append([players[i], players[i + 1]])
            i += 2
        if i < len(players):
            winners.append(players[i])  # bye
        self.tournament_state["round_pairs"] = pairs
        self.tournament_state["round_winners"] = winners
        self._tournament_sync()
        self._tournament_start_next_match()

    def _tournament_start_next_match(self):
        if not self.tournament_state or self.identity is None or str(self.tournament_state.get("host_id")) != self.identity.account_id:
            return
        pairs = list(self.tournament_state.get("round_pairs") or [])
        if not pairs:
            winners = list(self.tournament_state.get("round_winners") or [])
            if len(winners) <= 1:
                champion = winners[0] if winners else None
                self.tournament_state["champion"] = champion
                self.tournament_state["stage"] = "finished"
                self.tournament_state["current_pair"] = None
                self._tournament_sync()
                self.redraw()
                return
            self.tournament_state["round_players"] = winners
            self.root.after(800, self._tournament_prepare_round)
            return
        pair = pairs.pop(0)
        self.tournament_state["round_pairs"] = pairs
        match_id = f"{self.tournament_state.get('id')}-R{self.tournament_state.get('round')}-M{len(self.tournament_state.get('handled_matches') or []) + 1}"
        self.tournament_state["current_pair"] = {"match_id": match_id, "p1": pair[0], "p2": pair[1]}
        self._tournament_sync()
        payload = {
            "tournament_id": self.tournament_state.get("id"),
            "match_id": match_id,
            "coordinator": self.identity.account_id,
            "p1": pair[0],
            "p2": pair[1],
            "members": dict(self.tournament_state.get("members") or {}),
            "accepted": list(self.tournament_state.get("accepted") or []),
        }
        if pair[0] == self.identity.account_id:
            self._tournament_prepare_match_host(payload)
        else:
            self.social.send_tournament_event(pair[0], "prepare_host", payload)

    def _tournament_prepare_match_host(self, data: dict):
        if self.identity is None or self.social is None:
            return
        if self.tournament_state is not None:
            self.tournament_state["current_pair"] = {"match_id": str(data.get("match_id") or ""), "p1": str(data.get("p1") or ""), "p2": str(data.get("p2") or "")}
            self.tournament_state["stage"] = "running"
        try:
            if hasattr(self, "network"):
                self.network.close()
            self.network = InternetNetworkManager()
            self._apply_identity_to_network()
            self.current_mode = MULTIPLAYER
            self.multiplayer_scope = "internet"
            self.multiplayer_match_type = "tournament"
            self.multiplayer_view = "host"
            self.network_local_player = 1
            self.network_lobby_role = "host"
            self.network_peer_connected = False
            self.network_status = "Préparation du combat de tournoi…"
            self.network.host(room_name="Combat de tournoi", private=True, match_type="tournament", elo=self._local_elo())
            info = self.network.private_room_info()
            report = dict(data)
            report.update(info)
            coordinator = str(data.get("coordinator") or "")
            if coordinator == self.identity.account_id:
                self._tournament_room_ready(report)
            else:
                self.social.send_tournament_event(coordinator, "room_ready", report)
            self.current_screen = "multiplayer"
            self.redraw()
        except Exception as exc:
            self.notice = f"Tournoi : impossible de préparer le combat : {exc}"
            self.current_screen = "tournament"
            self.redraw()

    def _tournament_room_ready(self, data: dict):
        if not self.tournament_state or self.identity is None or self.social is None:
            return
        pair = self.tournament_state.get("current_pair") or {}
        if str(data.get("match_id") or "") != str(pair.get("match_id") or ""):
            return
        p1, p2 = str(pair.get("p1") or ""), str(pair.get("p2") or "")
        room_payload = {
            "tournament_id": self.tournament_state.get("id"),
            "match_id": pair.get("match_id"),
            "p1": p1, "p2": p2,
            "coordinator": self.identity.account_id,
            "room_id": str(data.get("room_id") or ""),
            "channel": str(data.get("channel") or ""),
            "room_name": str(data.get("room_name") or "Combat de tournoi"),
            "host_name": str(data.get("host_name") or self.tournament_state.get("members", {}).get(p1, "Shinobi")),
            "members": dict(self.tournament_state.get("members") or {}),
        }
        for aid in list(self.tournament_state.get("accepted") or []):
            if aid == p1:
                continue
            event_name = "join_match" if aid == p2 else "spectate_match"
            if aid == self.identity.account_id:
                self._handle_tournament_command(event_name, room_payload)
            else:
                self.social.send_tournament_event(aid, event_name, room_payload)

    def _handle_tournament_command(self, event_name: str, data: dict):
        if self.identity is None:
            return
        if event_name in {"join_match", "spectate_match"} and self.tournament_state is not None:
            self.tournament_state["current_pair"] = {"match_id": str(data.get("match_id") or ""), "p1": str(data.get("p1") or ""), "p2": str(data.get("p2") or "")}
            self.tournament_state["stage"] = "running"
        if event_name == "join_match":
            try:
                if hasattr(self, "network"):
                    self.network.close()
                self.network = InternetNetworkManager()
                self._apply_identity_to_network()
                self.current_mode = MULTIPLAYER
                self.multiplayer_scope = "internet"
                self.multiplayer_match_type = "tournament"
                self.multiplayer_view = "private_client"
                self.network_local_player = 2
                self.network_lobby_role = "client"
                self.network_peer_connected = False
                self.network_room_code = str(data.get("room_id") or "")
                self.network.join_private(self.network_room_code, str(data.get("channel") or ""), room_name=str(data.get("room_name") or "Tournoi privé"), host_name=str(data.get("host_name") or "Shinobi"))
                self.current_screen = "multiplayer"
                self.redraw()
            except Exception as exc:
                self.notice = f"Tournoi : connexion au combat impossible : {exc}"
                self.current_screen = "tournament"
                self.redraw()
            return
        if event_name == "spectate_match":
            try:
                if hasattr(self, "network"):
                    self.network.close()
                self.network = InternetNetworkManager()
                self._apply_identity_to_network()
                self.current_mode = MULTIPLAYER
                self.multiplayer_scope = "internet"
                self.multiplayer_match_type = "tournament"
                self.multiplayer_view = "tournament_spectator"
                self.network_local_player = 0
                self.network_lobby_role = "spectator"
                self.network_peer_connected = True
                self.network.spectate_private(str(data.get("room_id") or ""), str(data.get("channel") or ""), room_name=str(data.get("room_name") or "Tournoi privé"), host_name=str(data.get("host_name") or "Shinobi"))
                self.current_screen = "multiplayer"
                self.redraw()
            except Exception as exc:
                self.notice = f"Mode spectateur indisponible : {exc}"
                self.current_screen = "tournament"
                self.redraw()
            return
        if event_name == "return_lobby":
            try:
                self.network.close()
            except Exception:
                pass
            self.network_peer_connected = False
            self._duel_started_network = False
            self.current_mode = None
            self.current_screen = "tournament"
            if self.social is not None:
                self.social.set_status("online")
            self.redraw()

    def _handle_tournament_social_event(self, event: dict):
        event_name = str(event.get("event_name") or "")
        data = dict(event.get("data") or {})
        sender = str(event.get("from_account") or "")
        if event_name == "invite":
            self.social_tournament_invite_pending = data
            self.notice = f"Invitation au tournoi privé de {event.get('from_pseudo', 'un ami')}."
            return
        if event_name == "accept" and self.tournament_state and str(self.tournament_state.get("host_id")) == (self.identity.account_id if self.identity else ""):
            if str(data.get("tournament_id") or "") != str(self.tournament_state.get("id") or ""):
                return
            aid = str(data.get("account_id") or sender)
            accepted = list(self.tournament_state.get("accepted") or [])
            if aid and aid not in accepted:
                accepted.append(aid)
                self.tournament_state["accepted"] = accepted
            self._tournament_sync()
            if self.current_screen == "tournament":
                self.redraw()
            return
        if event_name == "reject" and self.current_screen == "tournament":
            self.notice = f"{event.get('from_pseudo','Un joueur')} a refusé le tournoi."
            self.redraw()
            return
        if event_name == "sync":
            if self.tournament_state and str(data.get("tournament_id") or "") == str(self.tournament_state.get("id") or ""):
                for key in ("accepted", "stage", "round", "current_pair", "champion", "members"):
                    if key in data:
                        self.tournament_state[key] = data[key]
                if self.current_screen == "tournament":
                    self.redraw()
            return
        if event_name == "prepare_host":
            self._tournament_prepare_match_host(data)
            return
        if event_name == "room_ready":
            self._tournament_room_ready(data)
            return
        if event_name in {"join_match", "spectate_match", "return_lobby"}:
            self._handle_tournament_command(event_name, data)
            return
        if event_name == "match_result" and self.tournament_state and self.identity is not None and str(self.tournament_state.get("host_id")) == self.identity.account_id:
            match_id = str(data.get("match_id") or "")
            handled = list(self.tournament_state.get("handled_matches") or [])
            if not match_id or match_id in handled:
                return
            pair = self.tournament_state.get("current_pair") or {}
            if match_id != str(pair.get("match_id") or ""):
                return
            winner_id = str(data.get("winner_id") or "")
            if winner_id not in {str(pair.get("p1") or ""), str(pair.get("p2") or "")}:
                return
            handled.append(match_id)
            self.tournament_state["handled_matches"] = handled
            winners = list(self.tournament_state.get("round_winners") or [])
            winners.append(winner_id)
            self.tournament_state["round_winners"] = winners
            self.tournament_state["current_pair"] = None
            payload = {"tournament_id": self.tournament_state.get("id"), "match_id": match_id}
            self._tournament_broadcast("return_lobby", payload)
            self._handle_tournament_command("return_lobby", payload)
            self.root.after(1200, self._tournament_start_next_match)

    def _finalize_tournament_result_once(self, winner: int):
        if self.multiplayer_match_type != "tournament" or not self.tournament_state or self.identity is None or self.social is None:
            return
        if self.network_local_player not in (1, 2):
            return
        pair = self.tournament_state.get("current_pair") or {}
        match_id = str(pair.get("match_id") or "")
        if not match_id:
            return
        local_key = "p1" if int(self.network_local_player) == 1 else "p2"
        if str(pair.get(local_key) or "") != self.identity.account_id:
            return
        sent_key = f"reported:{match_id}"
        if self.tournament_state.get(sent_key):
            return
        winner_id = str(pair.get("p1") if int(winner) == 1 else pair.get("p2"))
        coordinator = str(self.tournament_state.get("host_id") or "")
        self.tournament_state[sent_key] = True
        data = {"tournament_id": self.tournament_state.get("id"), "match_id": match_id, "winner_id": winner_id}
        if coordinator == self.identity.account_id:
            self._handle_tournament_social_event({"event_name": "match_result", "data": data, "from_account": self.identity.account_id, "from_pseudo": self.identity.pseudo})
        else:
            self.social.send_tournament_event(coordinator, "match_result", data)

    def _start_tournament_duel_if_ready(self):
        if self.multiplayer_match_type == "tournament" and self.network_lobby_role == "host" and self.network.connected:
            self._start_multiplayer_standard_host()

    def _cancel_social_private_room(self):
        self.social_private_autostart = False
        self.social_private_invited_account_id = None
        try:
            self.network.close()
        except Exception:
            pass
        self.network_peer_connected = False
        self.network_lobby_role = None
        self.network_local_player = None
        self.network_room_code = ""
        self.network_status = "Hors ligne"
        if self.current_screen == "social":
            self.current_mode = None

    def _social_invite_selected(self):
        if self.social is None or not self.social_selected_friend_id:
            return
        friend = self.social.store.friends.get(self.social_selected_friend_id)
        if not friend:
            return
        status = next((f.get("status") for f in self.social.friends_snapshot() if f.get("account_id") == self.social_selected_friend_id), "offline")
        if status != "online":
            self.social_notice = (f"{friend.get('pseudo', 'Cet ami')} est déjà en partie." if status == "in_game" else f"{friend.get('pseudo', 'Cet ami')} est hors ligne.")
            self.redraw()
            return
        try:
            if hasattr(self, "network"):
                self.network.close()
            self.network = InternetNetworkManager()
            self._apply_identity_to_network()
            self.current_mode = MULTIPLAYER
            self.multiplayer_scope = "internet"
            self.multiplayer_match_type = "private"
            self.multiplayer_view = "host"
            self.network_local_player = 1
            self.network_lobby_role = "host"
            self.network_peer_connected = False
            self.network_status = "Création du duel privé…"
            self.network_room_code = ""
            self.social_private_autostart = True
            self.social_private_invited_account_id = str(self.social_selected_friend_id)

            # Le joueur reste dans ESPACE SHINOBI : aucune ouverture manuelle
            # de serveur/salon. Tout est préparé en sous-marin.
            self.social_notice = f"Préparation de l'invitation pour {friend.get('pseudo', 'ton ami')}…"
            self.redraw()
            self.network.host(room_name=f"Partie privée de {self._local_pseudo()}", private=True)
            invite = self.network.private_room_info()
            self.network_room_code = str(invite.get("room_id") or "")
            ok, msg = self.social.send_invite(self.social_selected_friend_id, invite)
            if not ok:
                self._cancel_social_private_room()
                self.social_notice = msg
            else:
                self.social_notice = f"Invitation envoyée à {friend.get('pseudo', 'ton ami')} — le duel démarrera automatiquement s'il accepte."
                self.notice = self.social_notice
        except Exception as exc:
            self._cancel_social_private_room()
            self.social_notice = f"Impossible de créer l'invitation privée : {exc}"
            self.notice = self.social_notice
        self.redraw()

    def _start_social_private_duel_if_ready(self):
        if not self.social_private_autostart:
            return
        if self.network_lobby_role != "host" or not getattr(self.network, "connected", False):
            return
        if not self._economy_multiplayer_ready():
            self.notice = "Validation sécurisée des collections en cours…"
            self._economy_send_hello_async()
            self.redraw()
            return
        self.social_private_autostart = False
        self.social_private_invited_account_id = None
        self._start_multiplayer_standard_host()

    def _accept_social_invite(self):
        invite = dict(self.social_invite_pending or {})
        if not invite:
            return
        self.social_invite_pending = None
        account_id = str(invite.get("from_account") or "")
        try:
            if self.social is not None:
                self.social.send_invite_response(account_id, True)
            if hasattr(self, "network"):
                self.network.close()
            self.network = InternetNetworkManager()
            self._apply_identity_to_network()
            self.current_mode = MULTIPLAYER
            self.multiplayer_scope = "internet"
            self.multiplayer_match_type = "private"
            self.multiplayer_view = "private_client"
            # Pas de navigateur de salons ni d'ouverture de serveur : on reste
            # sur l'écran courant pendant la connexion, puis le duel démarre.
            self.network_local_player = 2
            self.network_lobby_role = "client"
            self.network_peer_connected = False
            self.network_room_code = str(invite.get("room_id") or "")
            self.network_status = f"Connexion à {invite.get('from_pseudo', 'ton ami')}…"
            self.notice = "Connexion à la partie privée via le relais YUGITO."
            self.network.join_private(
                str(invite.get("room_id") or ""),
                str(invite.get("channel") or ""),
                room_name=str(invite.get("room_name") or "Partie privée"),
                host_name=str(invite.get("from_pseudo") or "Adversaire"),
            )
        except Exception as exc:
            self.network_status = "Connexion privée impossible"
            self.notice = str(exc)
        self.redraw()

    def _reject_social_invite(self):
        invite = dict(self.social_invite_pending or {})
        self.social_invite_pending = None
        if invite and self.social is not None:
            self.social.send_invite_response(str(invite.get("from_account") or ""), False)
        self.social_notice = "Invitation refusée."
        self.redraw()

    def _poll_social_events(self):
        if self.social is not None:
            try:
                self.social.heartbeat()
            except Exception:
                pass
            for event in self.social.poll():
                kind = str(event.get("type") or "")
                if kind == "ui_friend_request_result":
                    self.social_busy = False
                    self.social_notice = str(event.get("message") or "")
                    if event.get("ok"):
                        self.social_add_var.set("")
                elif kind == "friend_request":
                    pseudo = str(event.get("pseudo") or "Un joueur")
                    self.social_notice = f"{pseudo} t'a envoyé une demande d'ami."
                    self.notice = self.social_notice
                elif kind == "friend_accept":
                    pseudo = str(event.get("pseudo") or "Un joueur")
                    self.social_notice = f"{pseudo} a accepté ta demande d'ami."
                    self.notice = self.social_notice
                elif kind == "friend_reject":
                    self.social_notice = f"{event.get('pseudo', 'Ce joueur')} a refusé ta demande."
                elif kind == "friend_remove":
                    self.social_notice = f"{event.get('pseudo', 'Ce joueur')} t'a retiré de ses amis."
                    if self.social_selected_friend_id not in self.social.store.friends:
                        self.social_selected_friend_id = None
                elif kind == "dm":
                    account_id = str(event.get("account_id") or "")
                    if not event.get("muted") and (self.current_screen != "social" or self.social_tab != "friends" or account_id != self.social_selected_friend_id):
                        self.social_unread.add(account_id)
                        self.notice = f"Nouveau message privé de {event.get('pseudo', 'un ami')}."
                elif kind == "groups_changed":
                    gid = str(event.get("group_id") or "")
                    if gid and not self.social_selected_group_id:
                        self.social_selected_group_id = gid
                elif kind == "group_dm":
                    gid = str(event.get("group_id") or "")
                    if gid and not event.get("muted") and (self.current_screen != "social" or self.social_tab != "groups" or gid != self.social_selected_group_id):
                        self.social_group_unread.add(gid)
                        self.notice = f"Nouveau message de groupe de {event.get('pseudo', 'un shinobi')}."
                elif kind == "tournament_event":
                    self._handle_tournament_social_event(event)
                elif kind == "game_invite":
                    invite = dict(event.get("invite") or {})
                    if self.social is not None and self.social.status == "in_game":
                        self.social.send_invite_response(str(invite.get("from_account") or ""), False)
                        self.notice = f"Invitation de {invite.get('from_pseudo', 'un ami')} refusée automatiquement : tu es déjà en partie."
                    else:
                        self.social_invite_pending = invite
                        self.notice = f"Invitation privée de {self.social_invite_pending.get('from_pseudo', 'un ami')}."
                elif kind == "invite_response":
                    pseudo = str(event.get("pseudo") or "Ton ami")
                    if event.get("accepted"):
                        self.notice = f"{pseudo} a accepté ton invitation. Le duel va démarrer automatiquement…"
                        self.social_notice = self.notice
                    else:
                        self.notice = f"{pseudo} a refusé ton invitation."
                        self.social_notice = self.notice
                        if self.social_private_autostart:
                            self._cancel_social_private_room()
                if self.current_screen in {"social", "menu", "multiplayer"} or self.social_invite_pending is not None:
                    self.redraw()
        self.root.after(180, self._poll_social_events)

    def _draw_social_screen(self):
        self._gradient_background("#0d1624", "#05080e")
        social = self.social
        self._rect(35, 25, 1565, 105, fill="#0e141e", outline="#2a3547", width=1, radius=14)
        self._text(65, 57, "ESPACE SHINOBI", size=27, weight="bold", anchor="w", family=DISPLAY_FONT_TOKEN)
        status = "CONNECTÉ" if social is not None and social.connected else "HORS LIGNE"
        self._text(65, 87, f"{self._local_pseudo()}  •  RÉSEAU SOCIAL {status}", size=10, fill=GREEN if status == "CONNECTÉ" else MUTED, weight="bold", anchor="w")
        self._button(1365, 42, 1535, 88, "RETOUR MENU", self.show_main_menu, fill="#151d29", accent=ACCENT, small=True)
        self._button(910, 42, 1090, 88, "AMIS", lambda: self._social_switch_tab("friends"), fill="#182338" if self.social_tab == "friends" else "#131b27", accent=BLUE, small=True)
        self._button(1105, 42, 1285, 88, "GROUPES", lambda: self._social_switch_tab("groups"), fill="#241b2e" if self.social_tab == "groups" else "#131b27", accent=PURPLE, small=True)

        if self.social_tab == "groups":
            self._draw_social_groups_content(social)
            return

        # Recherche d'ami.
        self._rect(35, 120, 1565, 190, fill="#111a27", outline="#2d3b50", width=1, radius=14)
        self._text(65, 154, "AJOUTER UN AMI", size=11, fill=GOLD, weight="bold", anchor="w")
        self._text(205, 154, "Pseudo exact :", size=9, fill=MUTED, anchor="w")
        self._place_social_entry(getattr(self, "social_add_entry", None), 315, 133, 700, 176, font_size=11, bold=True)
        self._button(715, 133, 900, 176, "ENVOYER DEMANDE", self._social_submit_add, fill="#192433", accent=PURPLE, small=True, enabled=not self.social_busy)
        if self.social_notice:
            notice, nsize = self._fit_text_box(self.social_notice, 570, 38, start_size=9, min_size=7, max_lines=2)
            self._text(935, 153, notice, size=nsize, fill="#d7c5ef", anchor="w", width=570)

        # Colonne amis / demandes.
        self._rect(35, 205, 520, 842, fill="#0e1520", outline="#2d3b50", width=2, radius=18)
        incoming = social.incoming_snapshot() if social is not None else []
        friends = social.friends_snapshot() if social is not None else []
        self._text(65, 235, f"AMIS — {len(friends)}", size=15, weight="bold", anchor="w", family=DISPLAY_FONT_TOKEN)
        self._text(490, 235, f"{len(incoming)} demande(s)", size=8, fill=GOLD if incoming else MUTED, weight="bold", anchor="e")

        y = 265
        for req in incoming[:2]:
            account_id = str(req.get("account_id") or "")
            self._rect(60, y, 495, y + 72, fill="#1b1822", outline=PURPLE, width=1, radius=12)
            self._text(78, y + 23, str(req.get("pseudo") or "Shinobi"), size=11, weight="bold", anchor="w")
            self._text(78, y + 48, "veut devenir ton ami", size=8, fill=MUTED, anchor="w")
            self._button(320, y + 13, 397, y + 57, "OK", lambda aid=account_id: self._social_accept_request(aid), fill="#17261e", accent=GREEN, small=True)
            self._button(405, y + 13, 480, y + 57, "NON", lambda aid=account_id: self._social_reject_request(aid), fill="#26191d", accent=RED, small=True)
            y += 82

        if incoming:
            y += 8
        page_size = 7
        max_page = max(0, (len(friends) - 1) // page_size)
        self.social_friend_page = max(0, min(self.social_friend_page, max_page))
        page = friends[self.social_friend_page * page_size:(self.social_friend_page + 1) * page_size]
        for friend in page:
            account_id = str(friend.get("account_id") or "")
            selected = account_id == self.social_selected_friend_id
            status = str(friend.get("status") or "offline")
            status_label = {"online": "EN LIGNE", "in_game": "EN PARTIE", "offline": "HORS LIGNE"}.get(status, "HORS LIGNE")
            status_color = GREEN if status == "online" else (ACCENT if status == "in_game" else "#6f7b8c")
            self._rect(60, y, 495, y + 58, fill="#192538" if selected else "#131d2a", outline=BLUE if selected else "#29384b", width=2 if selected else 1, radius=11)
            unread = "  •" if account_id in self.social_unread else ""
            self._text(78, y + 21, str(friend.get("pseudo") or "Shinobi") + unread, size=11, fill="#ffffff", weight="bold", anchor="w")
            self._text(78, y + 43, status_label, size=7, fill=status_color, weight="bold", anchor="w")
            self._add_click(60, y, 495, y + 58, lambda aid=account_id: self._social_select_friend(aid))
            y += 66
        if not friends and not incoming:
            self._text(277, 500, "Aucun ami pour le moment.", size=12, fill=MUTED)
            self._text(277, 535, "Ajoute un joueur avec son pseudo YUGITO.", size=9, fill="#7f8ca0")
        if max_page > 0:
            self._button(90, 790, 195, 825, "<", lambda: self._social_friend_page_change(-1), fill="#151d29", accent="#65738b", small=True, enabled=self.social_friend_page > 0)
            self._text(277, 807, f"{self.social_friend_page + 1}/{max_page + 1}", size=8, fill=MUTED, weight="bold")
            self._button(360, 790, 465, 825, ">", lambda: self._social_friend_page_change(1), fill="#151d29", accent="#65738b", small=True, enabled=self.social_friend_page < max_page)

        # Conversation.
        self._rect(540, 205, 1565, 842, fill="#0e1520", outline="#2d3b50", width=2, radius=18)
        selected = self.social_selected_friend_id
        friend = social.store.friends.get(selected, {}) if social is not None and selected else {}
        if not friend:
            self._text(1052, 485, "SÉLECTIONNE UN AMI", size=24, fill="#7f8ca0", weight="bold", family=DISPLAY_FONT_TOKEN)
            self._text(1052, 530, "Messages privés et invitations apparaîtront ici.", size=11, fill=MUTED)
            try:
                self.social_dm_entry.place_forget()
            except Exception:
                pass
            return

        pseudo = str(friend.get("pseudo") or "Shinobi")
        snap = next((f for f in friends if f.get("account_id") == selected), {})
        status = str(snap.get("status") or "offline")
        status_label = {"online": "EN LIGNE", "in_game": "EN PARTIE", "offline": "HORS LIGNE"}.get(status, "HORS LIGNE")
        status_color = GREEN if status == "online" else (ACCENT if status == "in_game" else MUTED)
        self._text(575, 232, pseudo.upper(), size=18, weight="bold", anchor="w", family=DISPLAY_FONT_TOKEN)
        self._text(575, 260, status_label, size=8, fill=status_color, weight="bold", anchor="w")
        flags = self.social.friend_flags(selected) if self.social is not None else {"blocked": False, "muted": False, "ignore_invites": False}
        self._button(1010, 218, 1110, 258, "PROFIL", self._social_show_profile, fill="#182338", accent=GOLD, small=True)
        self._button(1120, 218, 1335, 258, "INVITER PARTIE PRIVÉE", self._social_invite_selected, fill="#182338", accent=BLUE, small=True, enabled=status == "online" and not flags.get("blocked"))
        self._button(1345, 218, 1535, 258, "GROUPE +", self._social_create_group_with_selected, fill="#211a2c", accent=PURPLE, small=True, enabled=not flags.get("blocked"))
        self._button(1010, 267, 1132, 305, "DEMUET" if flags.get("muted") else "MUET", lambda: self._social_toggle_friend_flag("muted"), fill="#161d29", accent="#8e78a8", small=True)
        self._button(1140, 267, 1278, 305, "DÉBLOQUER" if flags.get("blocked") else "BLOQUER", lambda: self._social_toggle_friend_flag("blocked"), fill="#25191d" if not flags.get("blocked") else "#17261e", accent=RED if not flags.get("blocked") else GREEN, small=True)
        self._button(1286, 267, 1428, 305, "INVIT. ON" if flags.get("ignore_invites") else "IGNORER INV.", lambda: self._social_toggle_friend_flag("ignore_invites"), fill="#161d29", accent=ACCENT, small=True)
        self._button(1436, 267, 1535, 305, "RETIRER", self._social_remove_selected, fill="#25191d", accent=RED, small=True)

        self._rect(575, 318, 1530, 752, fill="#0b121c", outline="#233247", width=1, radius=12)
        conversation = social.store.conversation(selected) if social is not None else []
        # Classic 1.1.1 : le tchat privé est volontairement très lisible.
        # On affiche moins de messages à la fois pour pouvoir doubler réellement
        # la taille des textes sans chevauchement.
        visible = conversation[-4:]
        ymsg = 345
        for msg in visible:
            outgoing = msg.get("direction") == "out"
            label = "MOI" if outgoing else pseudo
            color = BLUE if outgoing else PURPLE
            text_msg = str(msg.get("text") or "")
            fitted, fsize = self._fit_text_box(text_msg, 720, 82, start_size=26, min_size=20, max_lines=2)
            self._text(600 if not outgoing else 1505, ymsg, label, size=16, fill=color, weight="bold", anchor="w" if not outgoing else "e")
            self._text(600 if not outgoing else 1505, ymsg + 30, fitted, size=fsize, fill="#eef3f8", anchor="w" if not outgoing else "e", justify="left" if not outgoing else "right", width=720)
            ymsg += 105
        if not conversation:
            self._text(1052, 510, "Aucun message — commence la conversation.", size=16, fill=MUTED)

        self._place_social_entry(getattr(self, "social_dm_entry", None), 575, 775, 1370, 825, font_size=20)
        self._button(1390, 775, 1530, 825, "ENVOYER", self._social_submit_dm, fill="#172339", accent=BLUE, small=True)

    def _draw_social_groups_content(self, social):
        self._rect(35, 120, 1565, 190, fill="#111a27", outline="#2d3b50", width=1, radius=14)
        self._text(65, 154, "GROUPES DE DISCUSSION", size=13, fill=PURPLE, weight="bold", anchor="w")
        self._text(270, 154, "Crée un groupe depuis la fiche d'un ami puis ajoute d'autres amis.", size=9, fill=MUTED, anchor="w")
        if self.social_notice:
            notice, nsize = self._fit_text_box(self.social_notice, 520, 38, start_size=9, min_size=7, max_lines=2)
            self._text(1000, 153, notice, size=nsize, fill="#d7c5ef", anchor="w", width=520)

        groups = social.groups_snapshot() if social is not None else []
        ids = {str(g.get("group_id")) for g in groups}
        if self.social_selected_group_id not in ids:
            self.social_selected_group_id = str(groups[0].get("group_id")) if groups else None
        self._rect(35, 205, 520, 842, fill="#0e1520", outline="#2d3b50", width=2, radius=18)
        self._text(65, 238, f"GROUPES — {len(groups)}", size=15, weight="bold", anchor="w", family=DISPLAY_FONT_TOKEN)
        y = 275
        for group in groups[:8]:
            gid = str(group.get("group_id") or "")
            selected = gid == self.social_selected_group_id
            unread = "  •" if gid in self.social_group_unread else ""
            self._rect(60, y, 495, y + 62, fill="#221d31" if selected else "#151c29", outline=PURPLE if selected else "#29384b", width=2 if selected else 1, radius=11)
            self._text(78, y + 23, str(group.get("name") or "Groupe Shinobi") + unread, size=11, weight="bold", anchor="w")
            self._text(78, y + 46, f"{len(group.get('members') or {})} shinobi(s)", size=8, fill=MUTED, anchor="w")
            self._add_click(60, y, 495, y + 62, lambda group_id=gid: self._social_select_group(group_id))
            y += 72
        if not groups:
            self._text(277, 500, "Aucun groupe pour le moment.", size=12, fill=MUTED)
            self._text(277, 535, "Sélectionne un ami puis clique sur GROUPE +.", size=9, fill="#7f8ca0")

        self._rect(540, 205, 1565, 842, fill="#0e1520", outline="#2d3b50", width=2, radius=18)
        group = social.store.group(self.social_selected_group_id) if social is not None and self.social_selected_group_id else None
        if not group:
            self._text(1052, 485, "SÉLECTIONNE UN GROUPE", size=23, fill="#7f8ca0", weight="bold", family=DISPLAY_FONT_TOKEN)
            try:
                self.social_dm_entry.place_forget()
            except Exception:
                pass
            return
        gname = str(group.get("name") or "Groupe Shinobi")
        members = dict(group.get("members") or {})
        self._text(575, 238, gname.upper(), size=18, weight="bold", anchor="w", family=DISPLAY_FONT_TOKEN)
        member_names = ", ".join(list(members.values())[:5])
        self._text(575, 268, member_names, size=8, fill=MUTED, anchor="w")
        can_add = bool(self.social_selected_friend_id and self.social_selected_friend_id not in members)
        self._button(1130, 224, 1325, 272, "AJOUTER L'AMI", self._social_add_selected_friend_to_group, fill="#182338", accent=BLUE, small=True, enabled=can_add)
        self._button(1340, 224, 1535, 272, "TOURNOI PRIVÉ", self._social_start_tournament_from_group, fill="#261f18", accent=GOLD, small=True, enabled=2 <= len(members) <= 5)
        self._rect(575, 292, 1530, 752, fill="#0b121c", outline="#233047", width=1, radius=12)
        messages = list(group.get("messages") or [])[-4:]
        ymsg = 320
        for msg in messages:
            outgoing = str(msg.get("account_id") or "") == (self.identity.account_id if self.identity else "")
            label = "MOI" if outgoing else str(msg.get("pseudo") or "Shinobi")
            color = BLUE if outgoing else PURPLE
            text_msg = str(msg.get("text") or "")
            fitted, fsize = self._fit_text_box(text_msg, 720, 82, start_size=24, min_size=18, max_lines=2)
            self._text(600 if not outgoing else 1505, ymsg, label, size=15, fill=color, weight="bold", anchor="w" if not outgoing else "e")
            self._text(600 if not outgoing else 1505, ymsg + 30, fitted, size=fsize, fill="#eef3f8", anchor="w" if not outgoing else "e", justify="left" if not outgoing else "right", width=720)
            ymsg += 105
        if not messages:
            self._text(1052, 510, "Aucun message dans ce groupe.", size=16, fill=MUTED)
        self._place_social_entry(getattr(self, "social_dm_entry", None), 575, 775, 1370, 825, font_size=20)
        self._button(1390, 775, 1530, 825, "ENVOYER", self._social_submit_dm, fill="#211a2c", accent=PURPLE, small=True)

    def _draw_social_profile_overlay(self):
        if self.social_profile_friend_id is None or self.social is None:
            return
        friend = self.social.store.friends.get(self.social_profile_friend_id, {})
        if not friend:
            self.social_profile_friend_id = None
            return
        profile = dict(friend.get("ranked_profile") or {"elo": DEFAULT_ELO})
        self._hide_social_entries()
        self._rect(360, 170, 1240, 720, fill="#0a111b", outline=GOLD, width=3, radius=26)
        self._text(800, 220, "PROFIL SHINOBI", size=28, fill=GOLD, weight="bold", family=DISPLAY_FONT_TOKEN)
        self._text(800, 280, str(friend.get("pseudo") or "Shinobi").upper(), size=32, weight="bold", family=DISPLAY_FONT_TOKEN)
        elo = normalize_elo(profile.get("elo"))
        matches = int(profile.get("ranked_matches") or 0)
        wins = int(profile.get("wins") or 0)
        losses = int(profile.get("losses") or 0)
        winrate = float(profile.get("winrate") or ((wins * 100.0 / matches) if matches else 0.0))
        self._text(800, 350, f"ELO  {elo}", size=26, fill="#f1d27e", weight="bold")
        self._text(600, 430, "PARTIES CLASSÉES", size=11, fill=MUTED, weight="bold")
        self._text(600, 468, str(matches), size=24, weight="bold")
        self._text(800, 430, "VICTOIRES / DÉFAITES", size=11, fill=MUTED, weight="bold")
        self._text(800, 468, f"{wins} / {losses}", size=24, weight="bold")
        self._text(1000, 430, "TAUX DE VICTOIRE", size=11, fill=MUTED, weight="bold")
        self._text(1000, 468, f"{winrate:.1f} %", size=24, weight="bold")
        self._text(800, 535, f"MEILLEUR ELO : {normalize_elo(profile.get('best_elo') or elo)}", size=14, fill="#dce5f0", weight="bold")
        self._button(650, 620, 950, 675, "FERMER", self._social_close_profile, fill="#151d29", accent=ACCENT, small=True)

    def _draw_social_invite_overlay(self):
        # Les widgets Tk Entry sont au-dessus du Canvas : on les masque le temps
        # de l'invitation pour que la fenêtre modale reste réellement au premier plan.
        self._hide_social_entries()
        invite = self.social_invite_pending or {}
        pseudo = str(invite.get("from_pseudo") or "Un ami")
        self._rect(395, 285, 1205, 610, fill="#101824", outline=PURPLE, width=3, radius=24)
        self._rect(420, 310, 1180, 385, fill="#1a2130", outline="", radius=14)
        self._text(800, 345, "INVITATION DE PARTIE PRIVÉE", size=20, fill="#e2c0ff", weight="bold", family=DISPLAY_FONT_TOKEN)
        self._text(800, 435, pseudo, size=28, fill="#ffffff", weight="bold", family=DISPLAY_FONT_TOKEN)
        self._text(800, 480, "t'invite dans un duel privé YUGITO.", size=12, fill=MUTED)
        self._button(485, 530, 770, 585, "ACCEPTER", self._accept_social_invite, fill="#17261e", accent=GREEN)
        self._button(830, 530, 1115, 585, "REFUSER", self._reject_social_invite, fill="#26191d", accent=RED)

    # ------------------------------------------------------------------
    # Generic helpers
    # ------------------------------------------------------------------
    def _load_assets(self):
        for key, filename in {
            "card_bg_detail": "card_bg_detail.png",
            "card_bg_field": "card_bg_field.png",
            "card_bg_hand": "card_bg_hand.png",
            "card_bg_draft": "card_bg_draft.png",
            "card_back": "card_back.png",
            "screen_bg": "menu_bg.png",
            "duel_bg": "duel_bg.png",
            "app_icon": "YUGITO.png",
            "menu_discord": "menu_discord.png",
            "menu_yugito_logo": "menu_yugito_logo.png",
            "card_glass_field": "card_glass_field.png",
            "card_glass_field_selected": "card_glass_field_selected.png",
        }.items():
            path = ASSET_DIR / filename
            if path.exists():
                try:
                    self.base_images[key] = tk.PhotoImage(file=str(path))
                except tk.TclError:
                    pass

        gif_path = ASSET_DIR / "menu_overlay.gif"
        if gif_path.exists():
            self._load_gif_frames("menu_overlay", gif_path)

        # Illustrations fournies par l'utilisateur, préconverties en PNG à la
        # taille exacte de chaque variante de carte. Aucun Pillow requis au runtime.
        character_dir = ASSET_DIR / "characters"
        if character_dir.exists():
            for path in character_dir.glob("*.png"):
                try:
                    self.base_images[f"char_{path.stem}"] = tk.PhotoImage(file=str(path))
                except tk.TclError:
                    pass

    def _scaled_asset(self, key: str, extra_scale: float = 1.0) -> tk.PhotoImage | None:
        base = self.base_images.get(key)
        if base is None:
            return None
        s, _, _ = self._scale()
        combined = s * max(0.70, min(1.20, float(extra_scale or 1.0)))
        frac = Fraction(max(0.2, min(2.8, combined))).limit_denominator(24)
        cache_key = (key, frac.numerator, frac.denominator)
        if cache_key not in self.scaled_images:
            self.scaled_images[cache_key] = base.zoom(frac.numerator, frac.numerator).subsample(
                frac.denominator, frac.denominator
            )
        return self.scaled_images[cache_key]

    def _load_gif_frames(self, key: str, path: Path):
        frames: list[tk.PhotoImage] = []
        idx = 0
        while True:
            try:
                frame = tk.PhotoImage(file=str(path), format=f"gif -index {idx}")
            except tk.TclError:
                break
            frames.append(frame)
            idx += 1
        if not frames:
            try:
                frames.append(tk.PhotoImage(file=str(path)))
            except tk.TclError:
                return
        self.base_gif_frames[key] = frames
        self.menu_gif_durations = [100 for _ in frames]

    def _scaled_gif_frame(self, key: str, frame_index: int) -> tk.PhotoImage | None:
        frames = self.base_gif_frames.get(key)
        if not frames:
            return None
        frame_index %= len(frames)
        base = frames[frame_index]
        s, _, _ = self._scale()
        frac = Fraction(max(0.2, min(2.5, s))).limit_denominator(12)
        cache_key = (key, frame_index, frac.numerator, frac.denominator)
        if cache_key not in self.scaled_gif_frames:
            self.scaled_gif_frames[cache_key] = base.zoom(frac.numerator, frac.numerator).subsample(frac.denominator, frac.denominator)
        return self.scaled_gif_frames[cache_key]

    def _draw_gif(self, key: str, x: float, y: float):
        frames = self.base_gif_frames.get(key)
        if not frames:
            return
        image = self._scaled_gif_frame(key, self.menu_gif_index)
        if image is None:
            return
        px, py = self.P(x, y)
        self.canvas.create_image(px, py, image=image, anchor="nw")

    def _schedule_menu_gif(self):
        if self._menu_gif_job is not None:
            return
        def _tick():
            self._menu_gif_job = None
            frames = self.base_gif_frames.get("menu_overlay")
            if frames:
                self.menu_gif_index = (self.menu_gif_index + 1) % len(frames)
                if self.current_screen == "menu":
                    self.redraw()
            delay = 120
            if self.menu_gif_durations:
                delay = max(60, self.menu_gif_durations[self.menu_gif_index % len(self.menu_gif_durations)])
            self._menu_gif_job = self.root.after(delay, _tick)
        self._menu_gif_job = self.root.after(120, _tick)

    def _canvas_tags(self, tags=()):
        active = tuple(getattr(self, "_active_draw_tags", ()) or ())
        if isinstance(tags, str):
            tags = (tags,)
        else:
            tags = tuple(tags or ())
        if not active:
            return tags
        if not tags:
            return active
        # Préserve l'ordre tout en supprimant les doublons.
        return tuple(dict.fromkeys(active + tags))

    def _draw_asset(self, key: str, x: float, y: float, *, extra_scale: float = 1.0):
        image = self._scaled_asset(key, extra_scale=extra_scale)
        if image is None:
            return
        px, py = self.P(x, y)
        self.canvas.create_image(px, py, image=image, anchor="nw", tags=self._canvas_tags())

    def _toggle_fullscreen(self, _event=None):
        if not self.is_fullscreen:
            self.windowed_geometry = self.root.geometry()
            self.is_fullscreen = True
            self.root.attributes("-fullscreen", True)
        else:
            self.is_fullscreen = False
            self.root.attributes("-fullscreen", False)
            self.root.geometry(self.windowed_geometry or "1280x720")
        self.redraw()
        return "break"

    def _escape(self, _event=None):
        if self.current_screen == "update":
            if not self.update_busy:
                self._update_later()
            return "break"
        if self.card_reader_card is not None:
            self._close_card_reader()
            return "break"
        if self.is_fullscreen:
            self._toggle_fullscreen()
            return "break"
        if self.current_screen != "menu":
            self.show_main_menu()
        return "break"

    def _scale(self):
        override = getattr(self, "_scale_override", None)
        if override is not None:
            return override
        if not hasattr(self, "canvas"):
            return 1.0, 0.0, 0.0
        w = max(1, self.canvas.winfo_width())
        h = max(1, self.canvas.winfo_height())
        scale = min(w / VIRTUAL_W, h / VIRTUAL_H)
        ox = (w - VIRTUAL_W * scale) / 2
        oy = (h - VIRTUAL_H * scale) / 2
        return scale, ox, oy

    def P(self, x: float, y: float) -> tuple[float, float]:
        s, ox, oy = self._scale()
        return ox + x * s, oy + y * s

    def R(self, x1: float, y1: float, x2: float, y2: float) -> tuple[float, float, float, float]:
        p1 = self.P(x1, y1)
        p2 = self.P(x2, y2)
        return p1[0], p1[1], p2[0], p2[1]

    def F(self, size: int, weight: str = "normal", family: str = "Segoe UI"):
        if family == DISPLAY_FONT_TOKEN:
            family = getattr(self, "display_font_family", "Arial Black")
        elif family == "@ui":
            family = getattr(self, "ui_font_family", "Segoe UI")
        s, _, _ = self._scale()
        return (family, max(7, int(size * s)), weight)

    def _gradient_background(self, top=BG_TOP, bottom=BG_BOTTOM, bands: int = 32):
        self.canvas.delete("all")
        self.click_regions.clear()

        # Si un fond illustré est disponible, il devient le fond principal de
        # tout le jeu. Il a été préparé en 1600x900, donc il suit naturellement
        # le système de mise à l'échelle du canvas.
        bg = self._scaled_asset("screen_bg")
        if bg is not None:
            self.canvas.create_image(0, 0, image=bg, anchor="nw")
            return

        w = self.canvas.winfo_width()
        h = self.canvas.winfo_height()
        tr, tg, tb = self._hex(top)
        br, bg, bb = self._hex(bottom)
        band_h = max(1, h / bands)
        for i in range(bands):
            t = i / max(1, bands - 1)
            color = self._rgb(
                int(tr + (br - tr) * t),
                int(tg + (bg - tg) * t),
                int(tb + (bb - tb) * t),
            )
            self.canvas.create_rectangle(0, i * band_h, w + 1, (i + 1) * band_h + 1, fill=color, outline="")

    @staticmethod
    def _hex(color: str):
        color = color.lstrip("#")
        return tuple(int(color[i:i + 2], 16) for i in (0, 2, 4))

    @staticmethod
    def _rgb(r: int, g: int, b: int):
        return f"#{r:02x}{g:02x}{b:02x}"

    def _register_custom_fonts(self):
        """Charge Ninja Naruto sans redistribuer le fichier de police.

        Le jeu utilise d'abord une police déjà installée. Si elle ne l'est pas,
        il peut utiliser le ZIP original de l'utilisateur (ninja-naruto.zip)
        trouvé à côté du jeu ou dans son dossier Downloads, en extrayant le TTF
        uniquement dans le dossier temporaire Windows.
        """
        candidate_ttf: Path | None = None
        bundled = FONT_DIR / "njnaruto.ttf"
        if bundled.exists():
            candidate_ttf = bundled
        else:
            zip_candidates = [
                PROJECT_ROOT / "ninja-naruto.zip",
                Path.home() / "Downloads" / "ninja-naruto.zip",
                Path.home() / "Desktop" / "ninja-naruto.zip",
            ]
            for zpath in zip_candidates:
                if not zpath.exists():
                    continue
                try:
                    with zipfile.ZipFile(zpath, "r") as zf:
                        member = next((n for n in zf.namelist() if Path(n).name.lower() == "njnaruto.ttf"), None)
                        if member:
                            temp_font = Path(tempfile.gettempdir()) / "YUGITO_njnaruto.ttf"
                            temp_font.write_bytes(zf.read(member))
                            candidate_ttf = temp_font
                            break
                except Exception:
                    continue

        if candidate_ttf is not None and candidate_ttf.exists() and sys.platform.startswith("win"):
            try:
                FR_PRIVATE = 0x10
                added = ctypes.windll.gdi32.AddFontResourceExW(str(candidate_ttf), FR_PRIVATE, 0)
                if added:
                    self._registered_font_paths.append(str(candidate_ttf))
            except Exception:
                pass
        try:
            families = set(tkfont.families(root=self.root))
            candidates = [
                "Ninja Naruto",
                "NinjaNaruto",
                "Ninja Naruto v2",
                "Ninja Naruto Regular",
                "njnaruto",
            ]
            for cand in candidates:
                if cand in families:
                    self.display_font_family = cand
                    break
            else:
                for fam in families:
                    if "ninja" in fam.lower() and "naruto" in fam.lower():
                        self.display_font_family = fam
                        break
        except Exception:
            self.display_font_family = "Arial Black"

    def _rect(self, x1, y1, x2, y2, *, fill, outline="", width=1, radius=0):
        tags = self._canvas_tags()
        if radius <= 0:
            return self.canvas.create_rectangle(*self.R(x1, y1, x2, y2), fill=fill, outline=outline, width=width, tags=tags)
        sx, sy = self.P(x1, y1)
        ex, ey = self.P(x2, y2)
        s, _, _ = self._scale()
        r = radius * s
        points = [
            sx + r, sy, ex - r, sy, ex, sy, ex, sy + r,
            ex, ey - r, ex, ey, ex - r, ey, sx + r, ey,
            sx, ey, sx, ey - r, sx, sy + r, sx, sy,
        ]
        return self.canvas.create_polygon(points, smooth=True, splinesteps=24, fill=fill, outline=outline, width=width, tags=tags)

    def _stipple_rect(self, x1, y1, x2, y2, *, fill, stipple="gray50", outline="", width=1, tags=()):
        return self.canvas.create_rectangle(*self.R(x1, y1, x2, y2), fill=fill, outline=outline, width=width, stipple=stipple, tags=self._canvas_tags(tags))

    def _stipple_oval(self, x1, y1, x2, y2, *, fill, stipple="gray50", outline="", width=1, tags=()):
        return self.canvas.create_oval(*self.R(x1, y1, x2, y2), fill=fill, outline=outline, width=width, stipple=stipple, tags=self._canvas_tags(tags))

    @staticmethod
    def _display_text(text) -> str:
        # La police Ninja Naruto gère mal les caractères accentués. Règle du jeu/UI :
        # aucun E accentué n'est affiché. On normalise aussi les variantes courantes.
        return (str(text)
                .replace("é", "e").replace("è", "e").replace("ê", "e").replace("ë", "e")
                .replace("É", "E").replace("È", "E").replace("Ê", "E").replace("Ë", "E"))

    def _text(
        self, x, y, text, *, size=16, fill=TEXT, weight="normal", anchor="center",
        family="Segoe UI", width=None, justify="center"
    ):
        text = self._display_text(text)
        px, py = self.P(x, y)
        kwargs = {
            "text": text,
            "font": self.F(size, weight, family),
            "fill": fill,
            "anchor": anchor,
            "justify": justify,
        }
        if width is not None:
            s, _, _ = self._scale()
            kwargs["width"] = max(20, width * s)
        kwargs["tags"] = self._canvas_tags()
        return self.canvas.create_text(px, py, **kwargs)

    def _button(self, x1, y1, x2, y2, label, command, *, fill=PANEL_2, accent=ACCENT, enabled=True, small=False):
        font_size = 12 if small else 15
        fitted_label, fitted_size = self._fit_text_box(
            label,
            max_width=(x2 - x1) - 22,
            max_height=(y2 - y1) - 10,
            start_size=font_size,
            min_size=7 if small else 8,
            weight="bold",
            family="@ui",
            max_lines=2,
        )
        if not enabled:
            self._rect(x1, y1, x2, y2, fill="#232936", outline="#303847", width=1, radius=12)
            self._text((x1 + x2) / 2, (y1 + y2) / 2, fitted_label, size=fitted_size, fill="#667080", weight="bold", family="@ui", width=(x2 - x1) - 22)
            return
        self._rect(x1, y1, x2, y2, fill=fill, outline=accent, width=2, radius=12)
        self._rect(x1 + 4, y1 + 4, x1 + 8, y2 - 4, fill=accent, radius=3)
        self._text((x1 + x2) / 2 + 3, (y1 + y2) / 2, fitted_label, size=fitted_size, weight="bold", family="@ui", width=(x2 - x1) - 22)
        self._add_click(x1, y1, x2, y2, command)

    def _add_click(self, x1, y1, x2, y2, command):
        self.click_regions.append(((x1, y1, x2, y2), command))

    def _dispatch_virtual_click(self, vx: float, vy: float):
        # Le panneau du menu est scrollable : les boutons masqués sous
        # l'en-tête/footer ne doivent jamais rester cliquables.
        if self.current_screen == "menu" and 874 <= vx <= 1542 and not (142 <= vy <= 786):
            return
        for (x1, y1, x2, y2), command in reversed(self.click_regions):
            if x1 <= vx <= x2 and y1 <= vy <= y2:
                command()
                return

    def _on_click(self, event):
        s, ox, oy = self._scale()
        if s <= 0:
            return
        vx = (event.x - ox) / s
        vy = (event.y - oy) / s
        self._dispatch_virtual_click(vx, vy)

    @staticmethod
    def _short_name(name: str, max_chars: int) -> str:
        return name if len(name) <= max_chars else name[: max_chars - 1] + "…"

    def _fit_text_box(
        self,
        text: str,
        max_width: float,
        max_height: float,
        *,
        start_size: int,
        min_size: int = 5,
        weight: str = "normal",
        family: str = "Segoe UI",
        max_lines: int = 1,
    ) -> tuple[str, int]:
        """Ajuste un texte sans bloquer la boucle graphique.

        YUGITO06 R3 : l'ancienne version effectuait énormément de ``font.measure``
        caractère par caractère et recréait des ``tkfont.Font`` à chaque redraw.
        Le draft étant entièrement redessiné pendant la molette, cela provoquait
        le "scroll au ralenti" vu dans l'enregistrement utilisateur.

        Ici :
        - cache du résultat final par dimensions/échelle ;
        - cache des objets Font de mesure ;
        - arrêt du wrapping dès que le nombre de lignes visible est atteint ;
        - troncature par recherche binaire au lieu de retirer 1 caractère à la fois.
        """
        raw = " ".join(self._display_text(text).replace("\n", " ").split())
        if not raw:
            return "", start_size

        scale, _, _ = self._scale()
        max_w_px = max(8, int(max_width * scale))
        max_h_px = max(8, int(max_height * scale))
        resolved_family = family
        if family == DISPLAY_FONT_TOKEN:
            resolved_family = getattr(self, "display_font_family", "Arial Black")
        elif family == "@ui":
            resolved_family = getattr(self, "ui_font_family", "Segoe UI")

        cache_key = (
            raw, max_w_px, max_h_px, int(start_size), int(min_size), str(weight),
            str(resolved_family), int(max_lines), max(1, int(round(scale * 1000))),
        )
        cached = self._fit_text_cache.get(cache_key)
        if cached is not None:
            return cached

        def get_font(size: int) -> tkfont.Font:
            font_desc = self.F(size, weight, family)
            key = tuple(font_desc)
            font = self._tk_measure_fonts.get(key)
            if font is None:
                font = tkfont.Font(root=self.root, font=font_desc)
                self._tk_measure_fonts[key] = font
            return font

        def trim_with_ellipsis(font: tkfont.Font, value: str) -> str:
            ell = "…"
            if font.measure(value + ell) <= max_w_px:
                return value.rstrip() + ell
            lo, hi = 0, len(value)
            # Recherche du plus long préfixe qui tient : O(log n) mesures au lieu
            # d'une mesure pour chaque caractère supprimé.
            while lo < hi:
                mid = (lo + hi + 1) // 2
                if font.measure(value[:mid].rstrip() + ell) <= max_w_px:
                    lo = mid
                else:
                    hi = mid - 1
            prefix = value[:lo].rstrip()
            return (prefix + ell) if prefix else ell

        def wrap_for(font: tkfont.Font) -> list[str]:
            if max_lines <= 1:
                if font.measure(raw) <= max_w_px:
                    return [raw]
                return [trim_with_ellipsis(font, raw)]

            words = raw.split()
            lines: list[str] = []
            current = ""
            overflow = False
            idx = 0
            while idx < len(words):
                word = words[idx]
                candidate = word if not current else current + " " + word
                if font.measure(candidate) <= max_w_px:
                    current = candidate
                    idx += 1
                    continue

                if current:
                    lines.append(current)
                    current = ""
                    # Tout ce qui suit est invisible : inutile de mesurer le reste.
                    if len(lines) >= max_lines:
                        overflow = True
                        break
                    continue

                # Mot seul trop large (rare) : on affiche ce qui tient et on
                # considère le reste comme overflow. Pas de boucle caractère/char.
                lines.append(trim_with_ellipsis(font, word))
                idx += 1
                if len(lines) >= max_lines and idx < len(words):
                    overflow = True
                    break

            if not overflow and current:
                lines.append(current)
            if len(lines) > max_lines:
                lines = lines[:max_lines]
                overflow = True
            if overflow and lines:
                last = lines[-1]
                if not last.endswith("…"):
                    lines[-1] = trim_with_ellipsis(font, last)
            return lines

        for size in range(start_size, min_size - 1, -1):
            font = get_font(size)
            lines = wrap_for(font)
            line_h = max(font.metrics("linespace"), 1)
            if len(lines) * line_h <= max_h_px:
                result = ("\n".join(lines[:max_lines]), size)
                self._fit_text_cache[cache_key] = result
                return result

        font = get_font(min_size)
        result = ("\n".join(wrap_for(font)[:max_lines]), min_size)
        self._fit_text_cache[cache_key] = result
        return result

    def _fit_draft_card_text(self, text: str, *, max_chars: int, size: int, max_lines: int = 1) -> tuple[str, int]:
        """Formatage ultra-léger réservé aux petites cartes du catalogue draft.

        Ces cartes ont une géométrie fixe (200x282) : déclencher le moteur de
        mesure typographique Tk pour chaque nom/stat/passif pendant un scroll est
        beaucoup plus coûteux que le dessin lui-même. On utilise donc ici un
        wrapping conservateur par caractères, sans aucun appel à ``font.measure``.
        La grande fiche d'aperçu conserve, elle, le fitting typographique précis.
        """
        raw = " ".join(self._display_text(text).replace("\n", " ").split())
        if not raw:
            return "", size
        max_chars = max(4, int(max_chars))
        max_lines = max(1, int(max_lines))
        if max_lines == 1:
            if len(raw) <= max_chars:
                return raw, size
            return raw[: max(1, max_chars - 1)].rstrip() + "…", size

        words = raw.split()
        lines: list[str] = []
        current = ""
        consumed = 0
        for i, word in enumerate(words):
            candidate = word if not current else current + " " + word
            if len(candidate) <= max_chars:
                current = candidate
                consumed = i + 1
                continue
            if current:
                lines.append(current)
                current = ""
                if len(lines) >= max_lines:
                    break
            if len(word) > max_chars:
                lines.append(word[: max(1, max_chars - 1)] + "…")
                consumed = i + 1
                if len(lines) >= max_lines:
                    break
            else:
                current = word
                consumed = i + 1
        if current and len(lines) < max_lines:
            lines.append(current)
        if consumed < len(words) and lines:
            last = lines[-1]
            if not last.endswith("…"):
                if len(last) >= max_chars:
                    last = last[: max(1, max_chars - 1)].rstrip()
                lines[-1] = last.rstrip() + "…"
        return "\n".join(lines[:max_lines]), size

    def _draft_content_height(self) -> float:
        rows = max(1, (len(self.draft_pool) + DRAFT_COLS - 1) // DRAFT_COLS)
        return rows * DRAFT_CARD_H + max(0, rows - 1) * DRAFT_GAP_Y

    def _draft_max_scroll(self) -> float:
        viewport_h = DRAFT_VIEW_BOTTOM - DRAFT_VIEW_TOP
        return max(0.0, self._draft_content_height() - viewport_h)

    def _draft_scroll_by(self, amount: float):
        """Grand déplacement direct (clic dans la barre de défilement)."""
        if self.current_screen != "draft":
            return
        self.draft_scroll = max(0.0, min(self._draft_max_scroll(), self.draft_scroll + float(amount)))
        self.redraw()

    def _draft_scroll_wheel(self, amount: float):
        """Molette précise sans inertie artificielle ni redraw à 60 FPS."""
        if self.current_screen != "draft":
            return
        before = float(self.draft_scroll)
        self.draft_scroll = max(0.0, min(self._draft_max_scroll(), before + float(amount)))
        if abs(self.draft_scroll - before) < 0.01:
            return
        # Les souris/pavés tactiles peuvent envoyer plusieurs événements dans la
        # même boucle Tk. On les cumule puis on ne redessine qu'une seule fois.
        if self._draft_scroll_redraw_job is None:
            self._draft_scroll_redraw_job = self.root.after_idle(self._flush_draft_scroll_redraw)

    def _flush_draft_scroll_redraw(self):
        self._draft_scroll_redraw_job = None
        if self.current_screen == "draft":
            self.redraw()

    @staticmethod
    def _star_count(deck: list[CardDefinition], stars: float) -> int:
        return sum(1 for card in deck if abs(card.stars - stars) < 0.01)

    @staticmethod
    def _progressive_star_cap(cards: list[CardDefinition]) -> float:
        """Ancien calcul conservé pour compatibilité avec d'anciens états.

        Depuis 1.2.3, le draft réel n'utilise plus la présence des paliers dans
        le deck : le plafond dépend du numéro global du choix.
        """
        cap = 3.0
        for tier in (3.0, 3.5, 4.0, 4.5):
            if any(abs(c.stars - tier) < 0.01 for c in cards):
                cap = tier + 0.5
            else:
                break
        return min(5.0, cap)

    def _draft_pick_index(self) -> int:
        return len(self.draft_decks.get(1, [])) + len(self.draft_decks.get(2, []))

    def _draft_scheduled_player(self, pick_index: int | None = None) -> int | None:
        idx = self._draft_pick_index() if pick_index is None else int(pick_index)
        if idx < 0 or idx >= len(DRAFT_PICK_RELATIVE):
            return None
        first = int(self.draft_first_picker or 1)
        second = 2 if first == 1 else 1
        return first if DRAFT_PICK_RELATIVE[idx] == "first" else second

    def _draft_round(self, pick_index: int | None = None) -> int:
        idx = self._draft_pick_index() if pick_index is None else int(pick_index)
        if idx < 0:
            return 1
        if idx >= len(DRAFT_ROUND_BY_PICK):
            return 5
        return int(DRAFT_ROUND_BY_PICK[idx])

    def _draft_star_cap(self, player: int) -> float:
        """Plus haute rareté déjà débloquée dans le draft.

        1.5.2 : DRAFT_PICK_CAPS est un CALENDRIER DE DEBLOCAGE, pas une suite de
        fenêtres qui se referment. Dès que 5★ a été atteint, 5★ reste donc
        sélectionnable jusqu'à la fin (sous réserve du quota 1/1 et des 32,5★).
        Le paramètre player est conservé pour compatibilité avec les appels existants.
        """
        idx = self._draft_pick_index()
        if idx < 0:
            return 3.0
        end = min(len(DRAFT_PICK_CAPS), idx + 1)
        if end <= 0:
            return 3.0
        return max(float(v) for v in DRAFT_PICK_CAPS[:end])


    def _draft_star_limit(self, stars: float) -> int | None:
        return STAR_VALUE_LIMITS.get(float(stars))

    def _draft_card_allowed(self, player: int, card: CardDefinition) -> bool:
        if self.current_mode and self.current_mode.id == "multiplayer" and not self._economy_card_available(card.id, player):
            return False
        scheduled = self._draft_scheduled_player()
        if scheduled is not None and int(player) != int(scheduled):
            return False
        if card.stars > self._draft_star_cap(player) + 0.01:
            return False
        if self._draft_total_stars(player) + float(card.stars) > MAX_TOTAL_STAR_VALUE + 0.001:
            return False
        limit = self._draft_star_limit(card.stars)
        if limit is None:
            return True
        return self._star_count(self.draft_decks[player], card.stars) < limit

    def _draft_total_stars(self, player: int) -> float:
        return sum(float(card.stars) for card in self.draft_decks[player])

    @staticmethod
    def _star_limit_label(limit: int | None) -> str:
        return "infini" if limit is None else str(limit)

    def _lineup_card_allowed(self, player: int, card: CardDefinition) -> bool:
        # La progression d'etoiles concerne UNIQUEMENT le draft du panel.
        return True

    def _on_mousewheel(self, event):
        # La fiche complète possède désormais son propre défilement vertical.
        if self.card_reader_card is not None:
            if getattr(event, "num", None) == 4:
                direction = -1
            elif getattr(event, "num", None) == 5:
                direction = 1
            else:
                delta = getattr(event, "delta", 0)
                if delta == 0:
                    return
                direction = -1 if delta > 0 else 1
            self._card_reader_scroll_by(direction * 105)
            return "break"
        if self.current_screen in {"menu", "combat_guide"}:
            if getattr(event, "num", None) == 4:
                direction = -1
            elif getattr(event, "num", None) == 5:
                direction = 1
            else:
                delta = getattr(event, "delta", 0)
                if delta == 0:
                    return
                direction = -1 if delta > 0 else 1

            if self.current_screen == "combat_guide":
                self._combat_guide_scroll_by(direction * 105)
                return "break"

            # Sur le menu, la molette ne déplace que le panneau de droite.
            try:
                px = self.canvas.winfo_pointerx() - self.canvas.winfo_rootx()
                py = self.canvas.winfo_pointery() - self.canvas.winfo_rooty()
                scale, ox, oy = self._scale()
                vx = (px - ox) / scale
                vy = (py - oy) / scale
            except Exception:
                return
            if 874 <= vx <= 1542 and 140 <= vy <= 795:
                self._main_menu_scroll_by(direction * 86)
                return "break"
            return

        if self.current_screen in {"collection", "shop", "card_catalog"}:
            if getattr(event, "num", None) == 4:
                direction = -1
            elif getattr(event, "num", None) == 5:
                direction = 1
            else:
                delta = getattr(event, "delta", 0)
                if delta == 0:
                    return
                direction = -1 if delta > 0 else 1
            if self.current_screen == "collection":
                self._account_cards_scroll("collection", direction * 150)
            elif self.current_screen == "card_catalog":
                self._account_cards_scroll("card_catalog", direction * 150)
            elif self.current_screen == "shop" and getattr(self, "shop_view", "root") == "cards":
                self._account_cards_scroll("shop", direction * 150)
            return "break"

        if self.current_screen not in {"draft", "deck_builder"}:
            return

        # Coordonnées virtuelles du pointeur pour ne faire défiler que le
        # catalogue situé sous la souris.
        try:
            px = self.canvas.winfo_pointerx() - self.canvas.winfo_rootx()
            py = self.canvas.winfo_pointery() - self.canvas.winfo_rooty()
            scale, ox, oy = self._scale()
            vx = (px - ox) / scale
            vy = (py - oy) / scale
        except Exception:
            return

        if self.current_screen == "draft":
            if not (42 <= vx <= 825 and 105 <= vy <= 865):
                return
        else:  # deck_builder
            if not (35 <= vx <= 1035 and 200 <= vy <= 842):
                return

        wheel_units = 1.0
        if getattr(event, "num", None) == 4:
            direction = -1
        elif getattr(event, "num", None) == 5:
            direction = 1
        else:
            delta = getattr(event, "delta", 0)
            if delta == 0:
                return
            direction = -1 if delta > 0 else 1
            # Windows classique : ±120 par cran. Les pavés tactiles envoient
            # souvent de petites valeurs : surtout PAS de minimum artificiel.
            wheel_units = min(4.0, abs(float(delta)) / 120.0)

        if self.current_screen == "draft":
            self._draft_scroll_wheel(direction * 132.0 * wheel_units)
        else:
            self._deck_builder_scroll_by(direction * 125)
        return "break"

    def _controller(self, player_number: int) -> str:
        if self.current_mode and self.current_mode.id == "multiplayer":
            if not self.network.connected:
                return "remote"
            return "human" if player_number == self.network_local_player else "remote"
        if not self.current_mode:
            return "human"
        return self.current_mode.player1_controller if player_number == 1 else self.current_mode.player2_controller

    def _net_send(self, payload: dict) -> bool:
        if not hasattr(self, "network") or not self.network.connected:
            self.notice = "Connexion réseau perdue."
            return False
        data = dict(payload)
        data.setdefault("sender", self.network_local_player)
        return self.network.send(data)

    def _network_combat_is_live(self) -> bool:
        return bool(
            self.current_mode
            and self.current_mode.id == "multiplayer"
            and self.current_screen == "duel"
            and self.engine is not None
            and self.engine.winner is None
            and self.network_local_player in (1, 2)
            and self._duel_started_network
        )

    def _schedule_disconnect_forfeit(self, message: str):
        if not self._network_combat_is_live():
            return
        self.network_status = "Reconnexion en cours…"
        self.notice = message + " Défaite dans 8 s si la connexion ne revient pas."
        if self._disconnect_forfeit_job is not None:
            try:
                self.root.after_cancel(self._disconnect_forfeit_job)
            except Exception:
                pass
        self._disconnect_forfeit_job = self.root.after(8000, self._apply_disconnect_forfeit)
        self.redraw()

    def _apply_disconnect_forfeit(self):
        self._disconnect_forfeit_job = None
        if not self._network_combat_is_live():
            return
        # Si le pair est revenu entre-temps, aucune sanction.
        if getattr(self.network, "connected", False) and self.network_peer_connected:
            return
        winner = int(self.network_local_player or 1)
        self.economy_finish_reason = "disconnect"
        self.engine.winner = winner
        try:
            self.engine.log_event(f"{self._player_display_name(winner)} gagne : l'adversaire s'est déconnecté du combat.")
        except Exception:
            pass
        self.notice = "VICTOIRE PAR ABANDON / DÉCONNEXION."
        self.redraw()

    def _deck_star_total(self, player: int) -> float:
        try:
            return round(sum(float(c.stars) for c in self.draft_decks.get(int(player), [])), 1)
        except Exception:
            return 0.0

    def _finalize_ranked_result_once(self, winner: int):
        if self.multiplayer_match_type != "ranked" or self.ranked_result_applied or self.ranked is None:
            return
        if self.network_local_player not in (1, 2):
            return
        local = int(self.network_local_player)
        opponent = 2 if local == 1 else 1
        won = int(winner) == local
        result = self.ranked.record_result(
            won=won,
            opponent_elo=normalize_elo(self.ranked_peer_elo),
            own_stars=self._deck_star_total(local),
            opponent_stars=self._deck_star_total(opponent),
        )
        self.ranked_result_applied = True
        self.ranked_last_result = result
        self._sync_ranked_profile_to_server()
        if self.social is not None:
            try:
                self.social.refresh_presence()
            except Exception:
                pass

    def _poll_network(self):
        if hasattr(self, "network"):
            for event in self.network.poll():
                marker = event.get("_net")
                if marker == "master_connected":
                    self.network_status = "Relais Internet connecté" if self.multiplayer_scope == "internet" else "Relais LAN détecté"
                    self.notice = ""
                    if self.current_screen == "multiplayer":
                        self.redraw()
                    continue
                if marker == "searching_master":
                    self.network_status = "Connexion au relais Internet…" if self.multiplayer_scope == "internet" else "Recherche automatique du relais LAN…"
                    self.notice = str(event.get("message") or "Recherche d'un serveur YUGITO disponible…")
                    if self.current_screen == "multiplayer":
                        self.redraw()
                    continue
                if marker == "hosting":
                    self.network_room_code = str(event.get("room_id") or "")
                    self.network_status = ("Salon Internet créé — en attente d’un adversaire" if self.multiplayer_scope == "internet" else "Salon LAN créé — en attente d’un adversaire")
                    self.notice = ("Salon publié via le relais Internet persistant." if self.multiplayer_scope == "internet" else "Salon LAN prêt : le deuxième PC doit être sur le même réseau local.")
                    if self.current_screen == "multiplayer":
                        self.redraw()
                    continue
                if marker == "connected":
                    # Une reconnexion/connexion annule une éventuelle défaite par abandon en attente.
                    if self._disconnect_forfeit_job is not None:
                        try:
                            self.root.after_cancel(self._disconnect_forfeit_job)
                        except Exception:
                            pass
                        self._disconnect_forfeit_job = None
                    self.network_peer_connected = True
                    self.network_peer_name = str(event.get("peer_name") or getattr(self.network, "peer_display_name", "") or "Adversaire")[:20]
                    if self.network.role == "spectator":
                        self.network_local_player = 0
                        self.network_lobby_role = "spectator"
                        self.network_status = "Mode spectateur connecté"
                        self.notice = "Tu regardes le combat du tournoi en direct."
                    elif self.network.role == "host":
                        self.network_local_player = 1
                        self.network_lobby_role = "host"
                        if self.social_private_autostart and bool(getattr(self.network, "_private_room", False)):
                            self.network_status = f"{self.network_peer_name} connecté — lancement automatique"
                            self.notice = f"{self.network_peer_name} a rejoint ton duel privé. Lancement…"
                            # Laisse le join_accept parvenir au client avant d'envoyer
                            # le start_standard, puis démarre sans bouton supplémentaire.
                            self.root.after(350, self._start_social_private_duel_if_ready)
                        else:
                            self.network_status = f"{self.network_peer_name} connecté — prêt à lancer"
                            self.notice = f"{self.network_peer_name} a rejoint ton salon."
                    else:
                        self.network_local_player = 2
                        self.network_lobby_role = "client"
                        self.network_status = f"Connecté à {self.network_peer_name} — attente du lancement"
                        self.notice = f"Connecté au salon de {self.network_peer_name}."
                    if self.network.role in {"host", "client"}:
                        self.root.after(60, self._economy_send_hello_async)
                    if self.multiplayer_match_type == "ranked" and self.network.role in {"host", "client"}:
                        self.root.after(120, self._send_ranked_hello)
                        if self.network.role == "host":
                            self.network_status = f"{self.network_peer_name} trouvé — lancement classé automatique"
                            self.root.after(500, self._start_ranked_duel_if_ready)
                    if self.multiplayer_match_type == "tournament" and self.network.role == "host":
                        self.network_status = f"{self.network_peer_name} connecté — lancement du combat de tournoi"
                        self.root.after(1400, self._start_tournament_duel_if_ready)
                    if self.current_screen == "multiplayer":
                        self.redraw()
                    continue
                if marker == "peer_left":
                    self.network_peer_connected = False
                    if self._network_combat_is_live():
                        self._schedule_disconnect_forfeit("L'adversaire a quitté le combat.")
                        continue
                    if self.social_private_autostart and bool(getattr(self.network, "_private_room", False)):
                        self.social_private_autostart = False
                        self.social_private_invited_account_id = None
                    if self.network_lobby_role == "host":
                        departed = self.network_peer_name or "L'adversaire"
                        self.network_status = "Adversaire parti — salon de nouveau disponible"
                        self.notice = f"{departed} est parti. Ton salon reste ouvert."
                        self.network_peer_name = ""
                    else:
                        self.network_status = "Connexion terminée"
                        self.notice = "L'autre joueur a quitté la partie."
                    self.redraw()
                    continue
                if marker == "disconnected":
                    self.network_peer_connected = False
                    if self._network_combat_is_live():
                        self._schedule_disconnect_forfeit("Connexion de l'adversaire perdue.")
                        continue
                    self.network_status = "Connexion au relais perdue"
                    self.notice = "Connexion au serveur YUGITO perdue."
                    self.redraw()
                    continue
                if marker == "error":
                    self.network_status = "Erreur réseau"
                    self.notice = "Réseau : " + str(event.get("message", "erreur inconnue"))
                    self.redraw()
                    continue
                self._handle_network_message(event)

            if self.current_screen == "multiplayer" and self.multiplayer_view == "join":
                rooms = [r for r in self.network.discovered_rooms() if str(r.get("match_type") or "classic") == "classic"]
                signature = tuple((r.get("room_id"), r.get("players"), r.get("status"), r.get("name")) for r in rooms)
                if signature != self._last_room_signature:
                    self._last_room_signature = signature
                    self.multiplayer_rooms = rooms
                    if self.multiplayer_selected_room_id not in {r.get("room_id") for r in rooms}:
                        self.multiplayer_selected_room_id = rooms[0].get("room_id") if rooms else None
                    self.redraw()
        self.root.after(100, self._poll_network)

    # ------------------------------------------------------------------
    # Timer 30 s + tchat multijoueur
    # ------------------------------------------------------------------
    def _current_phase_timer_key(self):
        if self.current_screen == "rps" and self.rps_winner is None and not self.rps_tie:
            return ("rps", self.rps_context, int(self.rps_waiting_player), len(self.rps_choices))
        if self.current_screen == "duel" and self.engine is not None and self.engine.winner is None:
            if self.engine.pending_replacement is None and self.grave_select_context is None:
                return ("duel", int(self.engine.turn), int(self.engine.active_player))
        if self.current_screen == "draft":
            total = len(self.draft_decks.get(1, [])) + len(self.draft_decks.get(2, []))
            return ("draft", total, int(self.draft_active_player))
        if self.current_screen == "lineup" and self.lineup_revealed:
            return ("lineup", int(self.lineup_active_player))
        if self.current_screen == "replacement" and self.engine is not None and self.engine.pending_replacement is not None:
            offer = self.engine.pending_replacement
            return (
                "replacement", int(self.engine.turn), int(offer.player_number), int(offer.slot),
                tuple(card.id for card in offer.options),
            )
        if self.current_screen == "grave_select" and self.engine is not None and self.grave_select_context:
            ctx = self.grave_select_context
            return (
                "grave_select", int(self.engine.turn), int(ctx.get("player", 0)),
                int(ctx.get("attacker_slot", -1)), bool(ctx.get("copied", False)),
            )
        if self.current_screen == "switch_select" and self.engine is not None and self.switch_select_slot is not None:
            return ("switch_select", int(self.engine.turn), int(self.engine.active_player), int(self.switch_select_slot))
        return None

    def _start_phase_timer_animation(self, key):
        if key is None:
            self._phase_timer_anim_key = None
            self._phase_timer_anim_started = 0.0
            return
        self._phase_timer_anim_key = key
        self._phase_timer_anim_started = time.monotonic()
        if self._phase_timer_anim_job is None:
            self._phase_timer_anim_job = self.root.after(16, self._phase_timer_animation_tick)

    def _phase_timer_animation_tick(self):
        self._phase_timer_anim_job = None
        key = self._current_phase_timer_key()
        if key is None or key != self._phase_timer_anim_key:
            return
        elapsed = time.monotonic() - self._phase_timer_anim_started
        duel_fast_path = self.current_screen == "duel" and self.engine is not None and self.card_reader_card is None
        if duel_fast_path:
            self._redraw_phase_timer_only()
        else:
            self.redraw()
        if elapsed < self._phase_timer_anim_duration:
            self._phase_timer_anim_job = self.root.after(16, self._phase_timer_animation_tick)

    def _sync_phase_timer_key(self, key) -> bool:
        if key == self._phase_timer_key:
            return False
        self._phase_timer_key = key
        self.phase_timer_seconds = 30
        self._start_phase_timer_animation(key)
        return True

    def _phase_timer_value(self) -> int:
        key = self._current_phase_timer_key()
        self._sync_phase_timer_key(key)
        return max(0, int(self.phase_timer_seconds))

    def _phase_timer_local_authority(self) -> bool:
        if self.current_screen == "rps":
            return self._controller(self.rps_waiting_player) == "human"
        if self.current_screen == "duel":
            return bool(self.engine and self._active_is_human() and not self.ai_busy and self.engine.pending_replacement is None)
        if self.current_screen == "draft":
            return self._controller(self.draft_active_player) == "human"
        if self.current_screen == "lineup":
            return bool(self.lineup_revealed and self._controller(self.lineup_active_player) == "human")
        if self.current_screen == "replacement" and self.engine and self.engine.pending_replacement:
            return self._controller(self.engine.pending_replacement.player_number) == "human"
        if self.current_screen == "grave_select" and self.grave_select_context:
            return self._controller(int(self.grave_select_context.get("player", 0))) == "human"
        if self.current_screen == "switch_select" and self.engine and self.switch_select_slot is not None:
            return self._controller(self.engine.active_player) == "human"
        return False

    def _phase_timer_tick(self):
        try:
            key = self._current_phase_timer_key()
            changed = self._sync_phase_timer_key(key)
            if not changed and key is not None and self.phase_timer_seconds > 0:
                self.phase_timer_seconds -= 1
                if self.phase_timer_seconds <= 0 and self._phase_timer_local_authority():
                    self._phase_timer_expired()
            if key is not None:
                if self.current_screen == "duel" and self.engine is not None and self.card_reader_card is None:
                    self._redraw_phase_timer_only()
                else:
                    self.redraw()
        finally:
            self._phase_timer_job = self.root.after(1000, self._phase_timer_tick)

    def _phase_timer_expired(self):
        if self.current_screen == "rps":
            player = self.rps_waiting_player
            choice = self.random.choice(list(RPS_BEATS))
            self.notice = f"30 secondes écoulées : choix automatique pour J{player}."
            self.choose_rps(choice)
            return
        if self.current_screen == "duel":
            self.notice = "Temps écoulé : fin du tour automatique."
            self.end_turn()
            return
        if self.current_screen == "draft":
            player = self.draft_active_player
            available = [
                c for c in self.draft_pool
                if self.draft_owner.get(c.id) is None and self._draft_card_allowed(player, c)
            ]
            if not available:
                return
            preview = self.draft_preview_card
            if preview not in available:
                preview = max(
                    available,
                    key=lambda c: (c.stars, c.max_hp + c.taijutsu + c.ninjutsu + c.genjutsu, c.name),
                )
            if self.current_mode and self.current_mode.id == "multiplayer":
                self._net_send({"type": "draft_pick", "player": player, "card_id": preview.id})
            self.notice = f"30 secondes écoulées : {preview.name} est sélectionné automatiquement pour J{player}."
            self._apply_draft_pick(player, preview)
            return
        if self.current_screen == "lineup":
            player = self.lineup_active_player
            if not self.lineup_revealed:
                return
            selected = self.starter_choices[player]
            for card in self.draft_decks[player]:
                if len(selected) >= STARTER_COUNT:
                    break
                if not any(c.id == card.id for c in selected):
                    self._lineup_toggle(card)
            if len(self.starter_choices[player]) == STARTER_COUNT:
                self.notice = f"30 secondes écoulées : les 3 Ninjas de J{player} sont validés automatiquement."
                self._lineup_confirm()
            return
        if self.current_screen == "replacement" and self.engine and self.engine.pending_replacement:
            offer = self.engine.pending_replacement
            if not offer.options:
                return
            chosen = max(
                offer.options,
                key=lambda c: (c.stars, c.max_hp + c.taijutsu + c.ninjutsu + c.genjutsu, c.name),
            )
            self.notice = f"30 secondes écoulées : {chosen.name} entre automatiquement sur le terrain."
            self.choose_replacement(chosen.id)
            return
        if self.current_screen == "switch_select" and self.engine and self.switch_select_slot is not None:
            reserve = self._planning_reserve_cards()
            if reserve:
                best = max(reserve, key=lambda c: (c.stars, c.max_hp + c.taijutsu + c.ninjutsu + c.genjutsu, c.name))
                self.notice = f"30 secondes écoulées : échange préparé automatiquement avec {best.name}."
                self.choose_tactical_switch(best.id)
            else:
                self._cancel_tactical_switch()
            return
        if self.current_screen == "grave_select" and self.engine and self.grave_select_context:
            player = int(self.grave_select_context.get("player", 0))
            enemy = self.engine.opponent(player)
            if not enemy.graveyard:
                self._cancel_grave_select()
                return
            best_index = max(
                range(len(enemy.graveyard)),
                key=lambda i: (
                    enemy.graveyard[i].stars,
                    enemy.graveyard[i].max_hp + enemy.graveyard[i].taijutsu + enemy.graveyard[i].ninjutsu + enemy.graveyard[i].genjutsu,
                    enemy.graveyard[i].name,
                ),
            )
            self.notice = f"30 secondes écoulées : {enemy.graveyard[best_index].name} est choisie automatiquement."
            self.choose_grave_card(best_index)

    def _draw_animated_phase_timer(self, target_x: float, target_y: float):
        key = self._current_phase_timer_key()
        if key is None:
            return
        seconds = self._phase_timer_value()
        if self._phase_timer_anim_key != key:
            self._start_phase_timer_animation(key)

        elapsed = max(0.0, time.monotonic() - self._phase_timer_anim_started)
        progress = min(1.0, elapsed / max(0.01, self._phase_timer_anim_duration))
        # Ease-out cubic : départ très visible au centre, arrivée souple.
        eased = 1.0 - (1.0 - progress) ** 3
        x = 800.0 + (target_x - 800.0) * eased
        y = 450.0 + (target_y - 450.0) * eased

        self._rect(x - 67, y - 25, x + 67, y + 25, fill="#13130c", outline="#ffd84d", width=3, radius=12)
        self._text(x, y, f"{seconds:02d} s", size=22, fill="#ffd84d", weight="bold", family=DISPLAY_FONT_TOKEN)

    def _draw_screen_phase_timer(self):
        targets = {
            "duel": (825, 46),
            "draft": (1080, 50),
            "lineup": (1125, 50),
            "rps": (800, 210),
            "replacement": (800, 198),
            "grave_select": (800, 176),
            "switch_select": (800, 188),
        }
        target = targets.get(self.current_screen)
        if target is not None:
            previous_tags = self._active_draw_tags
            self._active_draw_tags = tuple(dict.fromkeys(previous_tags + ("phase_timer",)))
            try:
                self._draw_animated_phase_timer(*target)
            finally:
                self._active_draw_tags = previous_tags

    def _redraw_phase_timer_only(self):
        """Fast path duel : actualise uniquement le chrono, jamais tout le Canvas."""
        if self.current_screen != "duel":
            self.redraw()
            return
        self.canvas.delete("phase_timer")
        self._draw_screen_phase_timer()

    @staticmethod
    def _validate_chat_input(proposed: str) -> bool:
        return "\n" not in proposed and "\r" not in proposed and len(proposed) <= 180

    def _append_chat_message(self, who: str, text: str):
        clean = " ".join(str(text).replace("\n", " ").split())[:180]
        if not clean:
            return
        self.chat_messages.append((who, clean))
        self.chat_messages = self.chat_messages[-30:]

    def _toggle_chat(self):
        self.chat_open = not self.chat_open
        if self.chat_open:
            self.chat_unread = 0
        else:
            self._hide_chat_entry()
        self.redraw()
        if self.chat_open:
            self.root.after_idle(self._focus_chat_entry)

    def _chat_available(self) -> bool:
        return bool(
            self.current_mode
            and self.current_mode.id == "multiplayer"
            and self.network.connected
            and self.network_peer_connected
            and self.network_local_player in (1, 2)
        )

    def _hide_chat_entry(self):
        if hasattr(self, "chat_entry"):
            self.chat_entry.place_forget()

    def _focus_chat_entry(self):
        if self.chat_open and self._chat_available() and hasattr(self, "chat_entry"):
            try:
                self.chat_entry.focus_set()
                self.chat_entry.icursor(tk.END)
            except tk.TclError:
                pass

    def _place_chat_entry(self):
        if not self.chat_open or not self._chat_available():
            self._hide_chat_entry()
            return
        x1, y1 = self.P(1030, 585)
        x2, y2 = self.P(1428, 632)
        width = max(80, int(x2 - x1))
        height = max(28, int(y2 - y1))
        scale, _, _ = self._scale()
        try:
            self.chat_entry.configure(font=(self.ui_font_family, max(16, int(20 * scale))))
            self.chat_entry.place(x=int(x1), y=int(y1), width=width, height=height)
            self.chat_entry.lift()
        except tk.TclError:
            pass

    def _send_chat_input(self):
        if not self._chat_available():
            self.notice = "Le tchat est disponible quand les deux joueurs sont connectés."
            self._hide_chat_entry()
            self.redraw()
            return
        text = self.chat_input_var.get()
        clean = " ".join(str(text).replace("\n", " ").split())[:180]
        if not clean:
            self._focus_chat_entry()
            return
        who = self._local_pseudo()
        self._append_chat_message(who, clean)
        self._net_send({"type": "chat", "text": clean, "player": self.network_local_player, "pseudo": who})
        self.chat_input_var.set("")
        self.chat_open = True
        self.redraw()
        self.root.after_idle(self._focus_chat_entry)

    def _submit_chat_entry(self, _event=None):
        self._send_chat_input()
        return "break"

    def _chat_entry_escape(self, _event=None):
        self.chat_open = False
        self._hide_chat_entry()
        self.redraw()
        return "break"

    def _write_chat_message(self):
        # Compatibilité avec les anciens appels internes : plus aucune popup.
        self.chat_open = True
        self.redraw()
        self.root.after_idle(self._focus_chat_entry)

    def _draw_global_chat(self):
        if not self.current_mode or self.current_mode.id != "multiplayer":
            self._hide_chat_entry()
            return
        if not self.network.connected or not self.network_peer_connected:
            self._hide_chat_entry()
            return
        # Petit bouton disponible dans toutes les étapes du duel multijoueur.
        chat_label = "TCHAT" if self.chat_unread <= 0 else f"TCHAT ({self.chat_unread})"
        self._button(1460, 82, 1560, 118, chat_label, self._toggle_chat, fill="#161d29", accent=PURPLE, small=True)
        if not self.chat_open:
            self._hide_chat_entry()
            return
        self._rect(1005, 125, 1565, 650, fill="#0b111b", outline=PURPLE, width=3, radius=18)
        self._text(1030, 150, "TCHAT YUGITO", size=15, fill="#deb6ff", weight="bold", anchor="w", family=DISPLAY_FONT_TOKEN)
        self._button(1435, 138, 1545, 176, "FERMER", self._toggle_chat, fill="#1b1721", accent="#7c5d90", small=True)
        y = 205
        visible = self.chat_messages[-5:]
        if not visible:
            self._text(1285, 365, "Aucun message pour le moment.", size=16, fill=MUTED)
        else:
            for who, msg in visible:
                self._text(1030, y, who, size=17, fill=BLUE if who == self._local_pseudo() else RED, weight="bold", anchor="nw")
                fitted, sz = self._fit_text_box(msg, 430, 68, start_size=22, min_size=17, max_lines=2)
                self._text(1110, y, fitted, size=sz, fill="#eef3f8", anchor="nw", justify="left", width=430)
                y += 78

        # Barre de saisie intégrée, comme un tchat classique.
        self._rect(1020, 572, 1548, 642, fill="#0e1420", outline="#4f3b5f", width=1, radius=12)
        self._place_chat_entry()
        self._button(1440, 585, 1535, 632, "ENVOYER", self._send_chat_input, fill="#20182a", accent=PURPLE, small=True)
        self._text(1032, 648, "Entrée pour envoyer • 180 caractères max.", size=8, fill="#7f8998", anchor="w")

    def _handle_network_message(self, msg: dict):
        msg_type = msg.get("type")
        if not msg_type:
            return
        if msg.get("sender") == self.network_local_player:
            return

        if msg_type == "economy_hello":
            permit=str(msg.get("permit") or "")
            if self.network_lobby_role == "client" and str(msg.get("match_id") or ""):
                self.economy_match_id = str(msg.get("match_id") or "")[:160]
            if permit:
                self._economy_verify_peer_permit_async(permit)
            return
        if msg_type == "ranked_hello":
            self.ranked_peer_elo = normalize_elo(msg.get("elo"))
            if self.current_screen == "multiplayer":
                self.notice = f"Adversaire classé : {self.ranked_peer_elo} ELO."
                self.redraw()
            return
        if msg_type == "chat":
            who = str(msg.get("pseudo") or self.network_peer_name or self._player_display_name(int(msg.get('player', 0) or 0)))[:20]
            self._append_chat_message(who, str(msg.get("text", "")))
            if not self.chat_open:
                self.chat_unread = min(99, self.chat_unread + 1)
            self.redraw()
            return
        if msg_type == "start_standard":
            self._prepare_multiplayer_standard(int(msg.get("seed", 1)))
            return
        if msg_type == "rps_choice":
            self.choose_rps(str(msg.get("choice", "")), from_network=True, forced_player=int(msg.get("player", 0)))
            return
        if msg_type == "rps_restart":
            self._restart_rps(from_network=True)
            return
        if msg_type == "rps_continue":
            self._continue_after_rps(from_network=True)
            return
        if msg_type == "draft_pick":
            player=int(msg.get("player",0)); card=next((c for c in self.cards if c.id == msg.get("card_id")),None)
            if card is not None:
                if not self._draft_card_allowed(player,card):
                    self.notice="Draft réseau refusé : carte non autorisée par collection/règles."; self.redraw(); return
                self._apply_draft_pick(player,card)
            return
        if msg_type == "lineup_toggle":
            card = next((c for c in self.cards if c.id == msg.get("card_id")), None)
            if card is not None:
                self._lineup_toggle(card, from_network=True, forced_player=int(msg.get("player", 0)))
            return
        if msg_type == "lineup_confirm":
            self._lineup_confirm(from_network=True, forced_player=int(msg.get("player", 0)))
            return
        if msg_type == "turn_plan_commit":
            self._apply_remote_turn_plan(msg)
            return
        if msg_type == "duel_action":
            # Compatibilité avec d'anciennes parties pré-Classic.
            self._apply_remote_duel_action(msg)
            return
        if msg_type == "end_turn":
            self._apply_remote_end_turn(int(msg.get("player", 0)))
            return
        if msg_type == "replacement":
            self._apply_remote_replacement(int(msg.get("player", 0)), str(msg.get("card_id", "")))
            return
        if msg_type == "grave_card":
            self._apply_remote_grave_card(msg)
            return

    def _apply_remote_turn_plan(self, msg: dict):
        if not self.engine or self.engine.winner is not None:
            return
        player = int(msg.get("player", 0))
        if player not in (1, 2) or self.engine.active_player != player:
            self.notice = "Synchronisation réseau : plan reçu hors tour."
            self.redraw()
            return
        free = msg.get("free") if isinstance(msg.get("free"), dict) else None
        actions = msg.get("actions") if isinstance(msg.get("actions"), list) else []
        actions = [dict(a) for a in actions[:2] if isinstance(a, dict)]
        self._begin_committed_turn(player, free, actions, remote=True)

    def _apply_remote_duel_action(self, msg: dict):
        if not self.engine or self.engine.winner is not None:
            return
        player = int(msg.get("player", 0))
        if player not in (1, 2) or self.engine.active_player != player:
            self.notice = "Synchronisation réseau : action reçue hors tour."
            self.redraw()
            return
        kind = msg.get("kind")
        attacker_slot = int(msg.get("attacker_slot", -1))
        target_raw = msg.get("target_slot")
        target_slot = None if target_raw is None else int(target_raw)
        ok = False
        message = ""
        if kind == "normal":
            style = str(msg.get("style", ""))
            ok, message = self.engine.attack(player, attacker_slot, style, target_slot)
            if ok:
                self.audio.play_normal_attack()
        elif kind == "special":
            copied = bool(msg.get("copied", False))
            attacker = self.engine.player(player).field[attacker_slot] if 0 <= attacker_slot < 3 else None
            special_id = None
            if attacker is not None:
                special_id = attacker.copied_special_id if copied else attacker.definition.id
            ok, message = self.engine.use_special(player, attacker_slot, target_slot, copied=copied)
            if ok:
                self._play_action_special_audio(special_id)
        if not ok:
            self.notice = "Réseau : " + (message or "action distante refusée")
        else:
            self.notice = message
        self._consume_engine_visual_events()
        self.selected_attacker_slot = None
        self.selected_style = None
        self.selected_special_mode = None
        self.inspected_enemy_slot = None
        if ok and self._handle_pending_replacement():
            return
        self.redraw()

    def _apply_remote_end_turn(self, player: int):
        if not self.engine or self.engine.winner is not None or self.engine.active_player != player:
            return
        self.selected_attacker_slot = None
        self.selected_style = None
        self.selected_special_mode = None
        self.inspected_enemy_slot = None
        self.engine.end_turn()
        self.notice = f"Tour de J{self.engine.active_player}."
        self._consume_engine_visual_events()
        if self._handle_pending_replacement():
            return
        self.current_screen = "duel"
        self.redraw()

    def _apply_remote_replacement(self, player: int, card_id: str):
        if not self.engine or self.engine.pending_replacement is None:
            return
        if self.engine.pending_replacement.player_number != player:
            return
        ok, message = self.engine.choose_replacement(player, card_id)
        self.notice = message
        if not ok:
            self.redraw()
            return
        if self.engine.pending_replacement is not None:
            if self._handle_pending_replacement():
                return
        self.current_screen = "duel"
        if self.turn_commit_pending_end:
            self._continue_committed_turn()
            return
        self.redraw()

    def _apply_remote_grave_card(self, msg: dict):
        if not self.engine:
            return
        player = int(msg.get("player", 0))
        attacker_slot = int(msg.get("attacker_slot", -1))
        grave_index = int(msg.get("grave_index", -1))
        copied = bool(msg.get("copied", False))
        ok, message = self.engine.steal_from_enemy_graveyard(player, attacker_slot, grave_index, copied=copied)
        self.notice = message
        if ok:
            self.audio.play_special("orochimaru")
            self._consume_engine_visual_events()
            self.grave_select_context = None
            self.current_screen = "duel"
            self.selected_attacker_slot = None
            self.selected_style = None
            self.selected_special_mode = None
        self.redraw()

    def redraw(self):
        if self.current_screen != "duel":
            self._clear_field_card_renderers()
            if hasattr(self, "gpu_field_renderer"):
                self.gpu_field_renderer.hide()
        if self.current_screen != "identity":
            self._hide_identity_entry()
        if self.current_screen != "social":
            self._hide_social_entries()
        if self.current_screen != "card_catalog" and hasattr(self, "card_catalog_search_entry"):
            self.card_catalog_search_entry.place_forget()
        if self.current_screen not in {"multiplayer", "rps", "draft", "lineup", "replacement", "grave_select", "switch_select", "duel"}:
            self._hide_chat_entry()
        if self.current_screen == "update":
            self._draw_update_screen()
        elif self.current_screen == "identity":
            self._draw_identity_screen()
        elif self.current_screen == "menu":
            self._draw_main_menu()
        elif self.current_screen == "shop":
            self._draw_shop()
        elif self.current_screen == "collection":
            self._draw_collection()
        elif self.current_screen == "combat_guide":
            self._draw_combat_guide()
        elif self.current_screen == "social":
            self._draw_social_screen()
        elif self.current_screen == "profile":
            self._draw_profile()
        elif self.current_screen == "tournament":
            self._draw_tournament_screen()
        elif self.current_screen == "multiplayer":
            self._draw_multiplayer_placeholder()
        elif self.current_screen == "rps":
            self._draw_rps()
        elif self.current_screen == "draft":
            self._draw_draft()
        elif self.current_screen == "lineup":
            self._draw_lineup()
        elif self.current_screen == "replacement":
            self._draw_replacement()
        elif self.current_screen == "grave_select":
            self._draw_grave_select()
        elif self.current_screen == "switch_select":
            self._draw_switch_select()
        elif self.current_screen == "duel_info":
            self._draw_duel_info()
        elif self.current_screen == "audio_settings":
            self._draw_audio_settings()
        elif self.current_screen == "card_catalog":
            self._draw_card_catalog()
        elif self.current_screen == "deck_builder":
            self._draw_deck_builder()
        elif self.current_screen == "duel":
            self._draw_duel()
        if self.current_screen in {"rps", "draft", "lineup", "replacement", "grave_select", "switch_select", "duel"}:
            self._draw_screen_phase_timer()
        if self.current_screen in {"multiplayer", "rps", "draft", "lineup", "replacement", "grave_select", "switch_select", "duel"}:
            self._draw_global_chat()
        if self.social_profile_friend_id is not None and self.current_screen == "social":
            self._draw_social_profile_overlay()
        if self.social_tournament_invite_pending is not None and self.current_screen not in {"identity", "update"}:
            self._draw_tournament_invite_overlay()
        if self.social_invite_pending is not None and self.current_screen not in {"identity", "update"}:
            self._draw_social_invite_overlay()
        if self.card_reader_card is not None:
            self._draw_card_reader_overlay()

    # ------------------------------------------------------------------
    # Fiche complète des cartes
    # ------------------------------------------------------------------
    def _card_reader_section_heights(self, card: CardDefinition) -> tuple[int, int, int, int, int]:
        """Hauteurs de la page de fiche complète.

        Les synergies ont volontairement leur propre grande section. La page
        reste confortable même pour les familles nombreuses : on préfère
        faire défiler plutôt que réduire le texte jusqu'à le rendre illisible.
        """
        passive_h = 225
        special_h = 255
        synergy_text = self._catalog_synergy_text(card)
        approx_lines = max(2, (len(synergy_text) + 78) // 79)
        synergy_h = max(175, min(300, 116 + approx_lines * 24))
        stats_h = 92
        gap = 14
        total = passive_h + special_h + synergy_h + stats_h + gap * 3
        return passive_h, special_h, synergy_h, stats_h, total

    def _card_reader_max_scroll(self) -> float:
        card = self.card_reader_card
        if card is None:
            return 0.0
        *_, total = self._card_reader_section_heights(card)
        # Doit rester strictement identique au viewport de _draw_card_reader_overlay
        # (245..810 = 565). L'ancienne valeur 595 empêchait d'atteindre les
        # dernières lignes de STATISTIQUES / SYNERGIES sur toutes les cartes.
        viewport_h = 800 - 258
        return max(0.0, float(total - viewport_h))

    def _card_reader_scroll_by(self, amount: float):
        if self.card_reader_card is None:
            return
        self.card_reader_scroll = max(0.0, min(self._card_reader_max_scroll(), self.card_reader_scroll + amount))
        self.redraw()

    def _open_card_reader(self, card: CardDefinition, instance=None):
        self.card_reader_card = card
        self.card_reader_instance = instance
        self.card_reader_scroll = 0.0
        self.redraw()

    def _close_card_reader(self):
        self.card_reader_card = None
        self.card_reader_instance = None
        self.card_reader_scroll = 0.0
        self.redraw()

    def _draw_card_reader_overlay(self):
        card = self.card_reader_card
        if card is None:
            return
        instance = self.card_reader_instance

        # Capture tous les clics derrière la fiche. Les boutons ajoutés ensuite
        # ont priorité car _on_click parcourt les régions en ordre inverse.
        self._add_click(0, 0, VIRTUAL_W, VIRTUAL_H, lambda: None)
        self._rect(0, 0, VIRTUAL_W, VIRTUAL_H, fill="#05080d", outline="")
        self._rect(120, 42, 1480, 858, fill="#0e1520", outline="#51627a", width=3, radius=24)
        self._text(165, 86, "FICHE COMPLETE", size=26, weight="bold", anchor="w", family=DISPLAY_FONT_TOKEN)
        self._text(165, 119, "Passif, technique et synergies en pleine largeur", size=10, fill=MUTED, anchor="w")
        # Le bouton FERMER est dessiné après le masque de clipping, avec le reste de l'en-tête fixe.

        current_hp = None
        if instance is not None:
            try:
                current_hp = int(instance.current_hp or 0)
            except Exception:
                current_hp = None
        self._draw_card(card, 175, 185, "detail", current_hp=current_hp, instance=instance)

        info_x1, info_x2 = 505, 1402
        hp_max_reader = self.engine.max_hp(instance) if instance is not None and self.engine is not None else card.max_hp
        hp_label = f"PV {hp_max_reader}" if current_hp is None else f"PV {current_hp} / {hp_max_reader}"

        viewport_top, viewport_bottom = 258, 800
        viewport_h = viewport_bottom - viewport_top
        passive_h, special_h, synergy_h, stats_h, content_h = self._card_reader_section_heights(card)
        max_scroll = max(0.0, float(content_h - viewport_h))
        self.card_reader_scroll = max(0.0, min(float(self.card_reader_scroll), max_scroll))
        y = viewport_top - self.card_reader_scroll
        gap = 14

        def visible(section_y: float, section_h: float) -> bool:
            return section_y + section_h >= viewport_top and section_y <= viewport_bottom

        # PASSIF
        if visible(y, passive_h):
            self._rect(info_x1, y, info_x2, y + passive_h, fill="#131d2b", outline="#34445c", width=1, radius=14)
            self._text(info_x1 + 22, y + 31, "PASSIF", size=11, fill=GREEN, weight="bold", anchor="w")
            ptitle = card.passive_name or "Aucun passif"
            pt, pts = self._fit_text_box(ptitle, 825, 34, start_size=18, min_size=10, weight="bold", family=DISPLAY_FONT_TOKEN, max_lines=2)
            self._text(info_x1 + 22, y + 68, pt, size=pts, weight="bold", anchor="nw", family=DISPLAY_FONT_TOKEN, width=825)
            pdesc = card.passive or "Aucun effet passif."
            ptxt, psz = self._fit_text_box(pdesc, 825, passive_h - 116, start_size=12, min_size=8, max_lines=18)
            self._text(info_x1 + 22, y + 111, ptxt, size=psz, fill="#cbd5e2", anchor="nw", justify="left", width=825)
        y += passive_h + gap

        # TECHNIQUE SPECIALE
        if visible(y, special_h):
            self._rect(info_x1, y, info_x2, y + special_h, fill="#131d2b", outline="#34445c", width=1, radius=14)
            self._text(info_x1 + 22, y + 31, "TECHNIQUE SPECIALE", size=11, fill=GOLD, weight="bold", anchor="w")
            stitle = card.special_name or "Aucune technique"
            st, sts = self._fit_text_box(stitle, 825, 36, start_size=18, min_size=10, weight="bold", family=DISPLAY_FONT_TOKEN, max_lines=2)
            self._text(info_x1 + 22, y + 70, st, size=sts, weight="bold", anchor="nw", family=DISPLAY_FONT_TOKEN, width=825)
            sdesc = card.special or "Aucun effet spécial."
            stxt, ssz = self._fit_text_box(sdesc, 825, special_h - 120, start_size=12, min_size=8, max_lines=20)
            self._text(info_x1 + 22, y + 115, stxt, size=ssz, fill="#cbd5e2", anchor="nw", justify="left", width=825)
        y += special_h + gap

        # SYNERGIES — section complète, jamais réduite à un petit encart.
        if visible(y, synergy_h):
            self._rect(info_x1, y, info_x2, y + synergy_h, fill="#111b29", outline="#52647f", width=1, radius=14)
            self._text(info_x1 + 22, y + 31, "SYNERGIES", size=11, fill=ACCENT_2, weight="bold", anchor="w")
            self._text(info_x1 + 22, y + 58, "Liens de groupe et duos de cette carte", size=9, fill=MUTED, anchor="w")
            syn = self._catalog_synergy_text(card)
            syn_txt, syn_size = self._fit_text_box(syn, 825, synergy_h - 92, start_size=11, min_size=8, max_lines=16)
            self._text(info_x1 + 22, y + 86, syn_txt, size=syn_size, fill="#dce7f3", anchor="nw", justify="left", width=825)
        y += synergy_h + gap

        # STATISTIQUES / ETATS
        if visible(y, stats_h):
            self._rect(info_x1, y, info_x2, y + stats_h, fill="#101824", outline="#34445c", width=1, radius=12)
            self._text(info_x1 + 22, y + 27, "STATISTIQUES", size=10, fill=GOLD, weight="bold", anchor="w")
            if instance is not None and self.engine is not None:
                status = self.engine.status_text(instance) or "Aucun effet actif particulier."
                stats = (
                    f"TAI {self.engine.effective_stat(instance, 'taijutsu')}   •   "
                    f"NIN {self.engine.effective_stat(instance, 'ninjutsu')}   •   "
                    f"GEN {self.engine.effective_stat(instance, 'genjutsu')}"
                )
                footer = f"{stats}     |     {status}"
            else:
                footer = f"TAI {card.taijutsu}   •   NIN {card.ninjutsu}   •   GEN {card.genjutsu}"
            ftxt, fsz = self._fit_text_box(footer, 825, 42, start_size=11, min_size=8, max_lines=2)
            self._text(info_x1 + 22, y + 58, ftxt, size=fsz, fill="#dce4ef", anchor="w", width=825)

        # Masques de découpe universels de la fiche complète.
        #
        # IMPORTANT : les blocs de la page sont dessinés sur le Canvas principal.
        # Quand leur Y devient négatif pendant le scroll, Tk ne les clippe pas
        # automatiquement au viewport. L'ancien masque ne couvrait que 198..244,
        # ce qui laissait PASSIF / SPECIALE / SYNERGIES remonter par-dessus le nom,
        # les badges et même l'en-tête de la fiche. On masque donc TOUT ce qui est
        # hors viewport sur la colonne de droite, puis on redessine les éléments
        # fixes de l'en-tête au-dessus du masque. Cette correction est commune à
        # toutes les cartes : aucune fiche ne peut désormais déborder.
        # Clipping robuste sur LES DEUX côtés du cadre.
        #
        # Les sections sont des rectangles arrondis Canvas : leur lissage peut
        # dépasser de quelques pixels au-delà de leur bbox logique. En 1.7.10,
        # le masque commençait à y=43 et finissait à y=854 ; un bord arrondi
        # pouvait donc encore apparaître au-dessus du cadre (y<42) ou sous le
        # cadre (y>858). On masque maintenant aussi l'extérieur du panneau.
        clip_x1, clip_x2 = info_x1 - 10, 1478
        outer_top, outer_bottom = 42, 858
        # Hors de la fenêtre : couleur du fond général.
        self._rect(clip_x1, 0, clip_x2, outer_top - 1, fill="#05080d", outline="")
        self._rect(clip_x1, outer_bottom + 1, clip_x2, VIRTUAL_H, fill="#05080d", outline="")
        # Dans la fiche mais hors du viewport scrollable : couleur du panneau.
        self._rect(clip_x1, outer_top, clip_x2, viewport_top - 1, fill="#0e1520", outline="")
        self._rect(clip_x1, viewport_bottom + 1, clip_x2, outer_bottom, fill="#0e1520", outline="")
        # Le masque recouvre volontairement une partie du contour droit/haut/bas ;
        # on redessine donc le cadre global par-dessus afin d'avoir une bordure
        # parfaitement continue, quelle que soit la position du scroll.
        self._rect(120, 42, 1480, 858, fill="", outline="#51627a", width=3, radius=24)

        # En-tête fixe de la colonne d'informations, toujours au-dessus du contenu
        # scrollé et donc jamais masqué / recouvert par une section.
        self._text(info_x1, 175, card.name, size=27, weight="bold", anchor="w", family=DISPLAY_FONT_TOKEN)
        self._text(1435, 178, f"{card.star_label}   •   {ELEMENT_SHORT.get(card.element, card.element.upper())}   •   {hp_label}", size=11, fill="#dce4ef", anchor="e")
        self._draw_card_role_badges(card, info_x1, 205, max_width=880)
        # Le bouton FERMER se trouve lui aussi dans la zone masquée : on le remet
        # au premier plan après le clip pour qu'il reste toujours accessible.
        self._button(1285, 65, 1435, 108, "FERMER", self._close_card_reader, fill="#171d28", accent=ACCENT, small=True)

        # Barre de défilement dédiée à la fiche complète.
        if max_scroll > 0:
            track_x1, track_x2 = 1413, 1427
            track_y1, track_y2 = viewport_top + 8, viewport_bottom - 8
            track_h = track_y2 - track_y1
            thumb_h = max(86.0, track_h * (viewport_h / content_h))
            ratio = 0.0 if max_scroll <= 0 else self.card_reader_scroll / max_scroll
            thumb_y1 = track_y1 + (track_h - thumb_h) * ratio
            thumb_y2 = thumb_y1 + thumb_h
            self._rect(track_x1, track_y1, track_x2, track_y2, fill="#0a1018", outline="#34445c", width=1, radius=7)
            self._rect(track_x1 + 2, thumb_y1, track_x2 - 2, thumb_y2, fill="#637793", outline="#8ea4c0", width=1, radius=6)
            self._text(1400, 203, "MOLETTE POUR DEFILER", size=8, fill="#8fa4bf", weight="bold", anchor="e")
            if thumb_y1 > track_y1 + 2:
                self._add_click(track_x1 - 7, track_y1, track_x2 + 7, thumb_y1, lambda: self._card_reader_scroll_by(-viewport_h * 0.80))
            if thumb_y2 < track_y2 - 2:
                self._add_click(track_x1 - 7, thumb_y2, track_x2 + 7, track_y2, lambda: self._card_reader_scroll_by(viewport_h * 0.80))

    # ------------------------------------------------------------------
    # Main menu
    # ------------------------------------------------------------------
    # ------------------------------------------------------------------
    # YUGITO06 - Boutique / collection / économie YT autoritaire serveur
    # ------------------------------------------------------------------
    def _economy_online(self) -> bool:
        return bool(self.economy_loaded and self.economy_state.get("economy_available"))

    def _economy_available_ids(self) -> set[str]:
        return {str(x) for x in self.economy_state.get("available_card_ids", [])}

    def _economy_card_available(self, card_id: str, player: int | None = None) -> bool:
        # Le Solo ne dépend jamais de la collection en ligne.
        if not self.current_mode or self.current_mode.id != "multiplayer":
            # Le constructeur de deck utilise néanmoins la collection quand le serveur est actif.
            return (not self.economy_loaded) or (not self._economy_online()) or str(card_id) in self._economy_available_ids()
        if player is None or int(player) == int(self.network_local_player or -1):
            return str(card_id) in self._economy_available_ids()
        return self.economy_peer_verified and str(card_id) in self.economy_peer_available_ids

    def _economy_card_status(self, card_id: str) -> tuple[str, str]:
        cid=str(card_id)
        if cid in set(self.economy_state.get("base_card_ids", [])):
            return "DÉBLOQUÉE DE BASE", GREEN
        if cid in set(self.economy_state.get("owned_card_ids", [])):
            return "POSSÉDÉE", GREEN
        if cid in set(self.economy_state.get("free_card_ids", [])):
            return "GRATUITE CETTE SEMAINE", GOLD
        return "NON POSSÉDÉE", RED

    def _economy_status_badge_style(self, status: str) -> tuple[str, str, str, str]:
        """1.6.7 — palette commune Collection/Boutique pour un statut lisible immédiatement."""
        styles = {
            "DÉBLOQUÉE DE BASE": ("#123a2e", "#42d59b", "#effff8", "DÉBLOQUÉE DE BASE"),
            "POSSÉDÉE": ("#123a2e", "#42d59b", "#effff8", "POSSÉDÉE • DÉFINITIVE"),
            "GRATUITE CETTE SEMAINE": ("#4a3610", "#e6ae3d", "#fff0bd", "GRATUITE CETTE SEMAINE"),
            "NON POSSÉDÉE": ("#461b22", "#e35c68", "#ffe7ea", "NON POSSÉDÉE"),
        }
        return styles.get(str(status), ("#172133", "#60708a", "#eef3fa", str(status)))

    def _draw_economy_status_badge(self, x1: float, y1: float, x2: float, y2: float, status: str, compact: bool=False):
        bg, outline, fg, label = self._economy_status_badge_style(status)
        self._rect(x1, y1, x2, y2, fill=bg, outline=outline, width=2, radius=6 if compact else 8)
        max_w=max(20, x2-x1-10)
        max_h=max(12, y2-y1-4)
        start=8 if compact else 9
        text, size=self._fit_text_box(label,max_w,max_h,start_size=start,min_size=6,weight="bold",max_lines=2)
        self._text((x1+x2)/2,(y1+y2)/2,text,size=size,fill=fg,weight="bold",justify="center",width=max_w)

    def _economy_penalty_remaining(self) -> int:
        try:
            until=int((self.economy_state.get("penalty") or {}).get("until") or 0)
            return max(0, until-int(time.time()))
        except Exception:
            return 0

    @staticmethod
    def _format_duration(seconds: int) -> str:
        seconds=max(0,int(seconds))
        if seconds < 60: return f"{seconds} s"
        minutes=(seconds+59)//60
        if minutes < 60: return f"{minutes} min"
        hours=minutes//60; rem=minutes%60
        if hours < 48: return f"{hours} h" + (f" {rem:02d}" if rem else "")
        days=hours//24; rh=hours%24
        return f"{days} j" + (f" {rh} h" if rh else "")

    def _economy_refresh_async(self, force: bool=False):
        if self.identity is None or self.economy_busy:
            return
        if not force and self.economy_loaded and time.time()-self.economy_last_refresh < 45:
            return
        self.economy_busy=True
        token=self.identity.token
        def worker():
            try:
                data=self.auth_client.economy_state(token)
                self.identity_events.put(("economy_state", data))
            except Exception as exc:
                self.identity_events.put(("economy_error", str(exc)))
        threading.Thread(target=worker,name="YUGITO-Economy",daemon=True).start()

    def _economy_purchase(self, card: CardDefinition):
        if not self._economy_online() or self.economy_busy or self.identity is None:
            self.economy_notice="Boutique YT indisponible : serveur économie requis."
            self.redraw(); return
        catalog={str(x.get('id')):x for x in self.economy_state.get('catalog',[]) if isinstance(x,dict)}
        item=catalog.get(card.id,{})
        price=int(item.get('price_yt') or 0)
        if not messagebox.askyesno("Boutique YT", f"Acheter définitivement {card.name} pour {price} YT ?"):
            return
        self.economy_busy=True; self.economy_notice=f"Achat de {card.name}…"; self.redraw()
        token=self.identity.token
        def worker():
            try:
                data=self.auth_client.economy_purchase(token,card.id)
                self.identity_events.put(("economy_purchase", data))
            except Exception as exc:
                self.identity_events.put(("economy_purchase_error", str(exc)))
        threading.Thread(target=worker,name="YUGITO-Purchase",daemon=True).start()

    def _economy_send_hello_async(self):
        if self.identity is None or not getattr(self.network,"connected",False) or self.network_local_player not in (1,2):
            return
        token=self.identity.token
        def worker():
            try:
                permit=self.auth_client.economy_match_permit(token, self.multiplayer_match_type or "classic")
                self.identity_events.put(("economy_own_permit", str(permit.get("permit") or "")))
            except Exception as exc:
                self.identity_events.put(("economy_permit_error", str(exc)))
        threading.Thread(target=worker,name="YUGITO-MatchPermit",daemon=True).start()

    def _economy_verify_peer_permit_async(self, permit: str):
        if self.identity is None: return
        token=self.identity.token
        def worker():
            try:
                data=self.auth_client.economy_verify_permit(token,permit)
                self.identity_events.put(("economy_peer_verified", (permit,dict(data.get("permit") or {}))))
            except Exception as exc:
                self.identity_events.put(("economy_peer_error", str(exc)))
        threading.Thread(target=worker,name="YUGITO-PeerPermit",daemon=True).start()

    def _economy_multiplayer_ready(self) -> bool:
        return bool(self._economy_online() and self.economy_own_permit and self.economy_peer_verified and self.economy_peer_permit)

    def _economy_settle_result_once(self, winner: int):
        if self.economy_result_applied or self.identity is None or self.network_local_player not in (1,2):
            return
        if not self._economy_multiplayer_ready():
            return
        # Fin naturelle : l'hôte/arbitre P2P émet le règlement. En revanche,
        # après une déconnexion, le survivant doit pouvoir régler le match même
        # s'il était client (l'hôte peut justement être celui qui a disparu).
        # Le match_id serveur reste idempotent, donc aucun double crédit.
        if self.network_lobby_role != "host" and self.economy_finish_reason not in {"disconnect","abandon"}:
            return
        p1permit=self.economy_own_permit if self.network_local_player==1 else self.economy_peer_permit
        p2permit=self.economy_own_permit if self.network_local_player==2 else self.economy_peer_permit
        p1aid=(self.identity.account_id if self.network_local_player==1 else self.economy_peer_account_id)
        p2aid=(self.identity.account_id if self.network_local_player==2 else self.economy_peer_account_id)
        winner_aid=p1aid if int(winner)==1 else p2aid
        payload={
            "match_id": self.economy_match_id or ("ym-"+secrets.token_hex(16)),
            "mode": self.multiplayer_match_type if self.multiplayer_match_type in {"classic","ranked","private","tournament"} else "private",
            "player1_permit":p1permit,"player2_permit":p2permit,
            "player1_deck":[c.id for c in self.draft_decks.get(1,[])],
            "player2_deck":[c.id for c in self.draft_decks.get(2,[])],
            "winner_account_id":winner_aid,
            "finish_reason":self.economy_finish_reason if self.economy_finish_reason in {"natural","disconnect","abandon"} else "natural",
        }
        self.economy_match_id=payload["match_id"]
        self.economy_result_applied=True
        token=self.identity.token
        def worker():
            try:
                data=self.auth_client.economy_settle_match(token,payload)
                self.identity_events.put(("economy_match_settled",data))
            except Exception as exc:
                self.identity_events.put(("economy_match_error",str(exc)))
        threading.Thread(target=worker,name="YUGITO-MatchYT",daemon=True).start()

    def _account_ownership_sets(self):
        base={str(x) for x in self.economy_state.get("base_card_ids",[])}
        owned={str(x) for x in self.economy_state.get("owned_card_ids",[])}
        free={str(x) for x in self.economy_state.get("free_card_ids",[])}
        permanent=base|owned
        return base, owned, free, permanent, permanent|free

    def _account_filter_cards(self, mode: str, screen: str | None = None):
        cards=sorted(self.cards,key=lambda c:(float(c.stars),c.name.casefold()))
        if self._economy_online() and mode!="all":
            _base,_owned,_free,permanent,available=self._account_ownership_sets()
            if mode=="current": cards=[c for c in cards if c.id in available]
            elif mode=="permanent": cards=[c for c in cards if c.id in permanent]
            elif mode=="missing": cards=[c for c in cards if c.id not in available]
        if screen=="card_catalog":
            selected=set(getattr(self,"card_catalog_role_filters",set()) or set())
            if selected:
                cards=[c for c in cards if selected.issubset(set(getattr(c,"roles",()) or ()))]
            q=str(getattr(self,"card_catalog_query","") or "").strip().casefold()
            if q:
                cards=[c for c in cards if q in (c.name+" "+c.id+" "+c.element+" "+" ".join(getattr(c,"roles",()) or ())).casefold()]
        return cards

    def _account_filter_buttons(self, mode: str, setter):
        specs=[("all","TOUTES"),("current","ACTUELLEMENT POSSÉDÉES"),("permanent","RÉELLEMENT POSSÉDÉES"),("missing","NON POSSÉDÉES")]
        x=80
        widths=[150,300,290,220]
        for (key,label),w in zip(specs,widths):
            active=mode==key
            self._button(x,130,x+w,174,label,lambda k=key:setter(k),fill="#27384d" if active else "#141d29",accent=GOLD if active else "#56677f",small=True)
            x+=w+14

    def _account_grid_metrics(self, screen: str, card_count: int) -> tuple[list[int], int, int, int, int, float]:
        """1.6.8 — grille PC compacte 3×N, centrée et scrollée ligne par ligne."""
        xs = [430, 700, 970]
        top = 340 if screen == "card_catalog" else 185
        row_pitch = 340
        visible_rows = 2
        rows = max(1, (int(card_count) + 2) // 3)
        max_row_offset = max(0, rows - visible_rows)
        max_scroll = float(max_row_offset * row_pitch)
        return xs, top, row_pitch, visible_rows, rows, max_scroll

    def _account_cards_scroll(self, screen: str, delta: float):
        attr={"collection":"collection_scroll","shop":"shop_scroll","card_catalog":"card_catalog_scroll"}[screen]
        mode=getattr(self,{"collection":"collection_filter","shop":"shop_filter","card_catalog":"card_catalog_ownership_filter"}[screen],"all")
        cards=self._account_filter_cards(mode,screen=screen)
        _xs,_top,row_pitch,_visible,_rows,max_scroll=self._account_grid_metrics(screen,len(cards))
        current=float(getattr(self,attr,0.0))
        # Une encoche de molette = exactement une rangée. Plus de demi-cartes ni de grands trous.
        step = float(row_pitch if float(delta) > 0 else -row_pitch if float(delta) < 0 else 0)
        target = current + step
        target = round(target / row_pitch) * row_pitch if row_pitch else target
        setattr(self,attr,max(0.0,min(max_scroll,target)))
        self.redraw()

    def _draw_account_scroll_indicator(self, screen: str, card_count: int, scroll: float):
        """Indicateur discret à droite pour matérialiser la position dans la liste."""
        _xs,_top,row_pitch,visible_rows,rows,max_scroll=self._account_grid_metrics(screen,card_count)
        if rows <= visible_rows:
            return
        x1,x2=1543,1552; y1,y2=195,856
        self._rect(x1,y1,x2,y2,fill="#0b111b",outline="#263548",width=1,radius=4)
        track_h=y2-y1
        thumb_h=max(54,int(track_h*(visible_rows/rows)))
        ratio=0.0 if max_scroll<=0 else max(0.0,min(1.0,float(scroll)/max_scroll))
        ty=y1+int((track_h-thumb_h)*ratio)
        self._rect(x1+1,ty,x2-1,ty+thumb_h,fill="#b97832",outline="#d99a4c",width=1,radius=4)

    def _set_account_filter(self, screen: str, mode: str):
        attr={"collection":"collection_filter","shop":"shop_filter","card_catalog":"card_catalog_ownership_filter"}[screen]
        scroll={"collection":"collection_scroll","shop":"shop_scroll","card_catalog":"card_catalog_scroll"}[screen]
        setattr(self,attr,mode if mode in {"all","current","permanent","missing"} else "all")
        setattr(self,scroll,0.0)
        self.redraw()

    def show_collection(self, view: str="cards"):
        self.current_screen="collection"
        self.collection_view="cards"
        self.collection_scroll=0.0
        self.economy_notice=""
        self._economy_refresh_async(force=True)
        self.redraw()

    def _draw_collection(self):
        self._gradient_background("#101827","#05080d")
        self._text(80,62,"COLLECTION",size=32,weight="bold",anchor="w",family=DISPLAY_FONT_TOKEN)
        self._text(80,102,"Compte Google/YUGITO commun PC ↔ Mobile • 3 cartes par ligne",size=10,fill=MUTED,anchor="w")
        self._button(1410,42,1530,96,"MENU",self.show_main_menu,fill="#151d29",accent=ACCENT,small=True)
        if not self._economy_online():
            self._text(800,430,"COLLECTION INDISPONIBLE — serveur économie requis",size=20,fill=RED,weight="bold")
            return
        mode=getattr(self,"collection_filter","all")
        self._account_filter_buttons(mode,lambda k:self._set_account_filter("collection",k))
        cards=self._account_filter_cards(mode); scroll=float(getattr(self,"collection_scroll",0.0))
        _b,_o,free,permanent,available=self._account_ownership_sets()
        self._text(1515,153,f"{len(cards)} CARTES • {len(permanent)} permanentes • {len(free)} gratuites semaine",size=9,fill=MUTED,anchor="e")
        xs,top,row_pitch,_visible,_rows,_max_scroll=self._account_grid_metrics("collection",len(cards))
        for i,card in enumerate(cards):
            row,col=divmod(i,3); x=xs[col]; y=top+row*row_pitch-scroll
            if y < top or y+DRAFT_CARD_H+45 > 872: continue
            self._draw_card(card,x,y,"draft"); self._add_click(x,y,x+DRAFT_CARD_W,y+DRAFT_CARD_H,lambda c=card:self._open_card_reader(c))
            status,_=self._economy_card_status(card.id)
            self._draw_economy_status_badge(x,y+DRAFT_CARD_H+3,x+DRAFT_CARD_W,y+DRAFT_CARD_H+25,status,compact=True)
        self._draw_account_scroll_indicator("collection",len(cards),scroll)

    def show_shop(self, view: str="root"):
        self.current_screen="shop"; self.shop_view=view; self.shop_scroll=0.0; self.economy_notice=""
        self._economy_refresh_async(force=True); self.redraw()

    def _shop_set_view(self, view: str):
        self.shop_view=view; self.shop_scroll=0.0; self.economy_notice=""; self.redraw()

    def _draw_shop(self):
        self._gradient_background("#101827","#05080d")
        self._text(80,62,"BOUTIQUE",size=32,weight="bold",anchor="w",family=DISPLAY_FONT_TOKEN)
        yt=int(self.economy_state.get("yt_balance") or 0)
        self._text(80,102,"Économie commune à ton compte Google/YUGITO",size=10,fill=MUTED,anchor="w")
        self._text(1330,70,f"{yt} YT",size=20,fill=GOLD,weight="bold",anchor="e")
        self._button(1410,42,1530,96,"MENU",self.show_main_menu,fill="#151d29",accent=ACCENT,small=True)
        if not self._economy_online():
            self._text(800,430,"BOUTIQUE HORS LIGNE — serveur économie requis",size=20,fill=RED,weight="bold"); return
        if self.shop_view=="root":
            self._rect(250,240,740,650,fill="#121c2b",outline=GOLD,width=2,radius=24); self._text(495,330,"BOUTIQUE ELO",size=28,fill=GOLD,weight="bold"); self._text(495,395,"Bientôt disponible",size=13,fill=MUTED); self._button(330,530,660,590,"OUVRIR",lambda:self._shop_set_view("elo"),accent=GOLD)
            self._rect(860,240,1350,650,fill="#121c2b",outline=BLUE,width=2,radius=24); self._text(1105,330,"BOUTIQUE YT",size=28,fill=BLUE,weight="bold"); self._text(1105,395,"Achète définitivement tes cartes",size=13,fill=MUTED); self._button(940,530,1270,590,"CARTES",lambda:self._shop_set_view("cards"),accent=BLUE)
            return
        if self.shop_view=="elo":
            self._text(800,380,"BOUTIQUE ELO — BIENTÔT DISPONIBLE",size=28,fill=GOLD,weight="bold"); self._button(625,650,975,710,"RETOUR",lambda:self._shop_set_view("root")); return
        mode=getattr(self,"shop_filter","all")
        self._account_filter_buttons(mode,lambda k:self._set_account_filter("shop",k))
        cards=self._account_filter_cards(mode); scroll=float(getattr(self,"shop_scroll",0.0)); catalog={str(x.get("id")):x for x in self.economy_state.get("catalog",[]) if isinstance(x,dict)}
        xs,top,row_pitch,_visible,_rows,_max_scroll=self._account_grid_metrics("shop",len(cards))
        for i,card in enumerate(cards):
            row,col=divmod(i,3); x=xs[col]; y=top+row*row_pitch-scroll
            if y < top or y+DRAFT_CARD_H+58 > 872: continue
            self._draw_card(card,x,y,"draft"); self._add_click(x,y,x+DRAFT_CARD_W,y+DRAFT_CARD_H,lambda c=card:self._open_card_reader(c))
            status,_=self._economy_card_status(card.id); self._draw_economy_status_badge(x,y+DRAFT_CARD_H+2,x+DRAFT_CARD_W,y+DRAFT_CARD_H+22,status,compact=True)
            item=catalog.get(card.id,{}) ; price=int(item.get("price_yt") or 0)
            can_buy=bool(price and status not in {"POSSÉDÉE","DÉBLOQUÉE DE BASE"} and yt>=price)
            label=(f"ACHETER • {price} YT" if price else "GRATUITE / BASE")
            self._button(x,y+DRAFT_CARD_H+27,x+DRAFT_CARD_W,y+DRAFT_CARD_H+58,label,lambda c=card:self._economy_purchase(c),fill="#172339",accent=BLUE,small=True,enabled=can_buy)
        self._draw_account_scroll_indicator("shop",len(cards),scroll)
        self._button(1380,820,1530,858,"RETOUR",lambda:self._shop_set_view("root"),small=True)
        if self.economy_notice:self._text(800,885,self.economy_notice,size=9,fill="#f1cf91",weight="bold")

    def show_profile(self):
        self.current_screen="profile"
        self._economy_refresh_async(force=False)
        self._sync_ranked_profile_to_server()
        self.redraw()

    def _draw_profile(self):
        self._gradient_background("#101827","#05080d")
        self._text(80,70,"PROFIL YUGITO",size=34,weight="bold",anchor="w",family=DISPLAY_FONT_TOKEN)
        self._text(80,112,"Identité Google/YUGITO commune à PC et Android — aucune adresse e-mail n'est affichée",size=11,fill=MUTED,anchor="w")
        self._button(1390,42,1530,98,"MENU",self.show_main_menu,small=True)
        pseudo=self._local_pseudo(); prof=self.ranked.profile() if self.ranked is not None else {"elo":DEFAULT_ELO,"ranked_matches":0,"wins":0,"losses":0,"winrate":0.0,"best_elo":DEFAULT_ELO}
        self._rect(170,190,1430,690,fill="#111b29",outline="#9b6736",width=2,radius=24)
        self._text(260,260,pseudo.upper(),size=34,weight="bold",anchor="w")
        self._text(260,320,f"{normalize_elo(prof.get('elo'))} ELO",size=28,fill=GOLD,weight="bold",anchor="w")
        labels=[("CLASSÉES",prof.get("ranked_matches",0)),("VICTOIRES",prof.get("wins",0)),("DÉFAITES",prof.get("losses",0)),("WINRATE",f"{float(prof.get('winrate') or 0):.1f}%"),("MEILLEUR ELO",normalize_elo(prof.get("best_elo")))]
        x=250
        for label,value in labels:
            self._rect(x,410,x+210,540,fill="#0d1725",outline="#34445c",width=1,radius=16); self._text(x+105,452,str(value),size=24,fill=GOLD,weight="bold"); self._text(x+105,505,label,size=9,fill=MUTED,weight="bold"); x+=225
        if self._economy_online():
            _b,_o,free,permanent,available=self._account_ownership_sets(); yt=int(self.economy_state.get("yt_balance") or 0)
            self._text(260,610,f"COLLECTION : {len(permanent)} permanentes • {len(available)} disponibles actuellement • {yt} YT",size=13,fill="#8bd6a7",weight="bold",anchor="w")
        self._text(260,650,"GOOGLE LIÉ • COMPTE YUGITO UNIQUE PC ↔ MOBILE",size=11,fill="#83b8ff",weight="bold",anchor="w")

    def show_main_menu(self):
        if self.identity is None:
            self.show_identity_screen()
            return
        if self.current_mode and self.current_mode.id == "multiplayer" and hasattr(self, "network"):
            try:
                self.network.close()
            except Exception:
                pass
            self.network_peer_connected = False
            self.network_lobby_role = None
            self.network_local_player = None
            self.network_status = "Hors ligne"
        if self._pending_ai_job:
            try:
                self.root.after_cancel(self._pending_ai_job)
            except Exception:
                pass
            self._pending_ai_job = None
        if self._auto_end_job:
            try:
                self.root.after_cancel(self._auto_end_job)
            except Exception:
                pass
            self._auto_end_job = None
        if self._fx_job:
            try:
                self.root.after_cancel(self._fx_job)
            except Exception:
                pass
            self._fx_job = None
        if self._status_anim_job:
            try:
                self.root.after_cancel(self._status_anim_job)
            except Exception:
                pass
            self._status_anim_job = None
        self.transient_fx.clear()
        self.current_screen = "menu"
        if self.social is not None:
            self.social.set_status("online")
        if hasattr(self, "audio"):
            self.audio.play_menu_music()
        self.current_mode = None
        self.engine = None
        self.grave_select_context = None
        self.ai_busy = False
        self.selected_hand_index = None
        self.selected_attacker_slot = None
        self.selected_style = None
        self.selected_special_mode = None
        self.turn_plan_free = None
        self.turn_plan_actions = []
        self.turn_plan_target_slot = None
        self.turn_commit_pending_end = False
        self.turn_commit_queue = []
        self.turn_commit_delayed = None
        self.switch_select_slot = None
        self.notice = ""
        self._economy_refresh_async()
        self.redraw()
        self.root.focus_force()

    def _open_tipeee(self):
        """Ouvre la page de dons YUGITO dans le navigateur par défaut."""
        try:
            opened = webbrowser.open_new_tab(TIPEEE_URL)
            if not opened:
                raise RuntimeError("Aucun navigateur n'a accepté le lien.")
            self.notice = "Merci de soutenir YUGITO !"
        except Exception:
            self.notice = "Impossible d'ouvrir Tipeee automatiquement."
        self.redraw()

    def _open_discord(self):
        """Ouvre le salon Discord officiel YUGITO dans le navigateur / client Discord."""
        try:
            opened = webbrowser.open_new_tab(DISCORD_URL)
            if not opened:
                raise RuntimeError("Aucun navigateur n'a accepté le lien.")
            self.notice = "Discord YUGITO ouvert."
        except Exception:
            self.notice = "Impossible d'ouvrir Discord automatiquement."
        self.redraw()

    def _main_menu_max_scroll(self) -> float:
        # 1.6.7 : le dernier bloc est désormais OPTIONS (jusqu'à y=948).
        # À la fin du scroll, les trois boutons viennent se poser juste au-dessus
        # du footer fixe, après Tipeee puis Discord.
        return 174.0

    def _main_menu_scroll_by(self, amount: float):
        self.main_menu_scroll = max(0.0, min(self._main_menu_max_scroll(), self.main_menu_scroll + amount))
        self.redraw()

    def _menu_scroll_item_visible(self, y1: float, y2: float) -> bool:
        """1.6.7 — ne dessine jamais un contrôle scrollable hors du panneau."""
        return y1 >= 146 and y2 <= 782

    def _draw_main_menu(self):
        # Classic 1.2.8 : panneau droit scrollable + Guide de combat placé
        # en premier dans Collection. Le visuel historique de gauche est conservé.
        self.canvas.delete("all")
        self.click_regions.clear()
        w = self.canvas.winfo_width()
        h = self.canvas.winfo_height()
        tr, tg, tb = self._hex("#0a1321")
        br, bg, bb = self._hex("#03070d")
        bands = 40
        band_h = max(1, h / bands)
        for i in range(bands):
            t = i / max(1, bands - 1)
            color = self._rgb(
                int(tr + (br - tr) * t),
                int(tg + (bg - tg) * t),
                int(tb + (bb - tb) * t),
            )
            self.canvas.create_rectangle(0, i * band_h, w + 1, (i + 1) * band_h + 1, fill=color, outline="")
        self._rect(0, 0, 1600, 900, fill="", outline="#1d2939", width=2)

        # Partie gauche : exactement le visuel YUGITO historique.
        self._draw_gif("menu_overlay", 55, 52)
        self._text(455, 110, "YUGITO", size=58, weight="bold", anchor="center", family=DISPLAY_FONT_TOKEN)
        self._text(455, 176, "NARUTO CARD GAME", size=20, fill="#f0e4d5", weight="bold", anchor="center")
        self._text(455, 842, "F11 : plein écran / fenêtre    •    Échap : retour", size=11, fill="#d7dfeb", anchor="center")

        # PANNEAU DROIT
        px1, px2 = 874, 1542
        py1, py2 = 48, 842
        self._rect(px1 + 6, py1 + 7, px2 + 8, py2 + 9, fill="#03060b", outline="", radius=24)
        self._rect(px1, py1, px2, py2, fill="#0c1420", outline="#9a5a27", width=2, radius=24)
        self._rect(px1 + 5, py1 + 5, px2 - 5, py2 - 5, fill="", outline="#3b2b20", width=1, radius=21)

        # Le contenu entre l'en-tête et le footer se déplace verticalement.
        sy = -float(self.main_menu_scroll)

        # JOUER — les éléments sont réellement bornés au viewport du panneau.
        if self._menu_scroll_item_visible(146 + sy, 160 + sy):
            self._menu_section_label_pro(902, 150 + sy, "JOUER")
        if self._menu_scroll_item_visible(166 + sy, 226 + sy):
            self._menu_mode_button_pro(912, 166 + sy, 1506, 226 + sy, "SOLO VS IA", "Affronte l'IA", lambda: self.start_duel(SOLO_AI), ACCENT, "solo")
        if self._menu_scroll_item_visible(234 + sy, 294 + sy):
            self._menu_mode_button_pro(912, 234 + sy, 1506, 294 + sy, "MULTIPLAYER", "Affronte un autre joueur", self.show_multiplayer, BLUE, "multi")
        social_count = len(self.social.store.incoming) if self.social is not None else 0
        social_title = f"AMIS & MESSAGES ({social_count})" if social_count else "AMIS & MESSAGES"
        if self._menu_scroll_item_visible(302 + sy, 362 + sy):
            self._menu_mode_button_pro(912, 302 + sy, 1506, 362 + sy, "BOUTIQUE", "Cartes • YT • ELO", self.show_shop, GOLD, "shop")
        if self._menu_scroll_item_visible(370 + sy, 430 + sy):
            self._menu_compact_button_pro(912, 370 + sy, 1200, 430 + sy, social_title, "Amis & messages", self.show_social, PURPLE, "friends")
            self._menu_compact_button_pro(1212, 370 + sy, 1506, 430 + sy, "PROFIL", "Stats & compte", self.show_profile, GOLD, "profile")

        # COLLECTION
        if self._menu_scroll_item_visible(448 + sy, 464 + sy):
            self._menu_section_label_pro(902, 456 + sy, "COLLECTION")
        if self._menu_scroll_item_visible(474 + sy, 534 + sy):
            self._menu_mode_button_pro(912, 474 + sy, 1506, 534 + sy, "COLLECTION", "Cartes possédées • de base • gratuites cette semaine", self.show_collection, BLUE, "collection")
        if self._menu_scroll_item_visible(542 + sy, 602 + sy):
            self._menu_mode_button_pro(912, 542 + sy, 1506, 602 + sy, "GUIDE DE COMBAT", "Règles, éléments, actions, synergies et effets", self.show_combat_guide, "#e0a84d", "guide")
        if self._menu_scroll_item_visible(612 + sy, 676 + sy):
            self._menu_compact_button_pro(912, 612 + sy, 1200, 676 + sy, "LISTE DES CARTES", "Stats & techniques", self.show_card_catalog, GOLD, "cards")
            self._menu_compact_button_pro(1212, 612 + sy, 1506, 676 + sy, "CREE TON DECK", "Compose ton équipe", self.show_deck_builder, GREEN, "deck")

        # 1.6.7 — ordre de fin du menu : Tipeee, Discord, puis OPTIONS.
        # Les trois boutons système sont volontairement les tout derniers.
        if self._menu_scroll_item_visible(694 + sy, 764 + sy):
            self._menu_donation_button_pro(912, 694 + sy, 1506, 764 + sy)
        if self._menu_scroll_item_visible(774 + sy, 844 + sy):
            self._menu_discord_button(912, 774 + sy, 1506, 844 + sy)

        if self._menu_scroll_item_visible(866 + sy, 882 + sy):
            self._menu_section_label_pro(902, 874 + sy, "OPTIONS")
        state = "FENETRE" if self.is_fullscreen else "PLEIN ECRAN"
        if self._menu_scroll_item_visible(892 + sy, 948 + sy):
            self._menu_option_button_pro(912, 892 + sy, 1112, 948 + sy, state, self._toggle_fullscreen, "#d89a3d", "screen")
            self._menu_option_button_pro(1124, 892 + sy, 1324, 948 + sy, "AUDIO", self.show_audio_settings, "#d89a3d", "audio")
            self._menu_option_button_pro(1336, 892 + sy, 1506, 948 + sy, "QUITTER", self._close_app, "#d65b5b", "quit")

        # Masques : le contenu se comporte comme une page web à l'intérieur
        # du panneau et ne passe jamais sous l'en-tête ni le footer.
        self._rect(881, 53, 1535, 143, fill="#0c1420", outline="", radius=18)
        self._rect(881, 786, 1535, 837, fill="#0c1420", outline="", radius=18)

        # En-tête fixe.
        yugito_logo = self._scaled_asset("menu_yugito_logo")
        if yugito_logo is not None:
            lx, ly = self.P(903, 69)
            self.canvas.create_image(lx, ly, image=yugito_logo, anchor="nw")
        self._text(994, 78, f"BIENVENUE, {self._local_pseudo().upper()}", size=15, weight="bold", anchor="w")
        self._text(994, 110, "Identité YUGITO", size=10, fill="#f09a39", weight="bold", anchor="w")
        self._text(1489, 78, f"{int(self.economy_state.get('yt_balance') or 0)} YT" if self._economy_online() else "YT —", size=11, fill=GOLD if self._economy_online() else "#5d6878", weight="bold", anchor="e")
        self._text(1489, 108, "SHINOBI NETWORK", size=7, fill="#3f4a5a", weight="bold", anchor="e")
        self._rect(902, 138, 1506, 140, fill="#493421", outline="")

        # Scrollbar discrète du panneau principal.
        max_scroll = self._main_menu_max_scroll()
        track_y1, track_y2 = 151, 776
        self._rect(1517, track_y1, 1523, track_y2, fill="#182334", outline="", radius=3)
        thumb_h = 470
        ratio = 0.0 if max_scroll <= 0 else self.main_menu_scroll / max_scroll
        thumb_y = track_y1 + ratio * ((track_y2 - track_y1) - thumb_h)
        self._rect(1517, thumb_y, 1523, thumb_y + thumb_h, fill="#9a6734", outline="", radius=3)
        if self.main_menu_scroll < max_scroll - 1:
            self._text(1503, 770, "▼", size=9, fill="#d69a53", weight="bold")

        # Footer fixe.
        if self.notice:
            self._text(1209, 801, self.notice, size=8, fill="#e5b6ff", weight="bold")
        else:
            self._text(1209, 801, "MOLETTE : faire défiler le menu", size=8, fill="#9ca9ba", weight="bold")
        self._text(894, 821, "by Hakamah Production", size=8, fill="#6e7a8d", anchor="w")
        self._text(1514, 813, "YUGITO CLASSIC", size=9, fill="#d28a33", weight="bold", anchor="e")
        self._text(1514, 828, f"VERSION {APP_VERSION}", size=7, fill="#8997aa", weight="bold", anchor="e")

    def _menu_section_label_pro(self, x, y, label):
        self._text(x + 10, y, "◆", size=8, fill="#e38a32", weight="bold", anchor="w")
        self._text(x + 24, y, label, size=9, fill="#dda35f", weight="bold", anchor="w")
        self._rect(x + 105, y - 1, 1506, y + 1, fill="#493421", outline="")

    def _menu_shinobi_emblem(self, cx, cy, r):
        # Emblème original YUGITO : anneau orange + spirale, sans reprendre un logo officiel.
        self.canvas.create_oval(*self.R(cx-r, cy-r, cx+r, cy+r), fill="#111924", outline="#df8734", width=max(1, int(2*self._scale()[0])))
        self.canvas.create_oval(*self.R(cx-r+8, cy-r+8, cx+r-8, cy+r-8), fill="", outline="#7e4d27", width=max(1, int(2*self._scale()[0])))
        pts = []
        for i in range(44):
            a = i * 0.42
            rr = 2.2 + i * 0.48
            pts.extend(self.P(cx + math.cos(a)*rr, cy + math.sin(a)*rr))
        if len(pts) >= 4:
            self.canvas.create_line(*pts, fill="#ef9239", width=max(1, int(3*self._scale()[0])), smooth=True)
        # marques cardinales comme un sceau ninja.
        for dx, dy in ((0,-r-7),(r+7,0),(0,r+7),(-r-7,0)):
            self._rect(cx+dx-3, cy+dy-7 if dx else cy+dy-3, cx+dx+3, cy+dy+7 if dx else cy+dy+3, fill="#d07b2f", outline="")

    def _menu_corner_ornament(self, x, y, *, flip=False):
        # Nuage stylisé discret en bas de cadre.
        direction = -1 if flip else 1
        for ox, oy, rr in ((0,0,13),(16*direction,-5,10),(30*direction,1,14),(45*direction,-3,9)):
            self.canvas.create_oval(*self.R(x+ox-rr, y+oy-rr/2, x+ox+rr, y+oy+rr/2), fill="#6f4927", outline="#9e6837")

    def _menu_draw_icon(self, kind, x1, y1, x2, y2, accent):
        cx, cy = (x1+x2)/2, (y1+y2)/2
        scale_w = max(1, int(2*self._scale()[0]))
        if kind == "solo":
            # Un seul shinobi : silhouette claire avec bandeau et spirale centrale.
            # L'icône doit être lisible immédiatement, même en petite taille.
            self.canvas.create_oval(*self.R(cx-14, cy-15, cx+14, cy+15), fill="#efe7d8", outline="#f7f1e6", width=1)
            # Bandeau sombre + plaque métallique.
            self._rect(cx-17, cy-10, cx+17, cy-4, fill="#26364a", outline="", radius=2)
            self._rect(cx-9, cy-11, cx+9, cy-3, fill="#d9c9aa", outline="#76512d", width=1, radius=2)
            # Petite spirale YUGITO dessinée dans la plaque.
            pts=[]
            for i in range(18):
                a=i*0.55
                rr=0.5+i*0.22
                pts.extend(self.P(cx+math.cos(a)*rr, cy-7+math.sin(a)*rr))
            if len(pts)>=4:
                self.canvas.create_line(*pts, fill="#553c2b", width=max(1,int(self._scale()[0])), smooth=True)
            # Masque / col ninja pour donner une vraie silhouette et non une tête flottante.
            self.canvas.create_polygon(*self.P(cx-15,cy+5), *self.P(cx+15,cy+5), *self.P(cx+10,cy+17), *self.P(cx-10,cy+17), fill="#172235", outline="")
            self.canvas.create_line(*self.P(cx-7,cy), *self.P(cx-2,cy-1), fill="#172235", width=scale_w)
            self.canvas.create_line(*self.P(cx+2,cy-1), *self.P(cx+7,cy), fill="#172235", width=scale_w)
        elif kind == "multi":
            # Deux shinobi face à face + VS : beaucoup plus explicite que des armes croisées.
            for side in (-1, 1):
                sx = cx + side*12
                self.canvas.create_oval(*self.R(sx-8, cy-13, sx+8, cy+3), fill="#efe7d8", outline="#f7f1e6", width=1)
                self._rect(sx-10, cy-9, sx+10, cy-4, fill="#26364a", outline="", radius=2)
                self._rect(sx-5, cy-10, sx+5, cy-3, fill="#d9c9aa", outline="#76512d", width=1, radius=1)
                self.canvas.create_polygon(*self.P(sx-9,cy+2), *self.P(sx+9,cy+2), *self.P(sx+7,cy+13), *self.P(sx-7,cy+13), fill="#e9e2d8", outline="")
            self._text(cx, cy+1, "VS", size=6, fill="#e79533", weight="bold")
        elif kind == "shop":
            # Boutique : sac de boutique + pièce YT, icône dédiée.
            self._rect(cx-18, cy-8, cx+13, cy+16, fill="#e8c66f", outline="#4b3518", width=1, radius=6)
            self.canvas.create_arc(*self.R(cx-11, cy-20, cx+7, cy-1), start=0, extent=180, style="arc", outline="#f5dda0", width=scale_w)
            self.canvas.create_oval(*self.R(cx+5, cy-17, cx+23, cy+1), fill="#192231", outline=accent, width=2)
            self._text(cx+14, cy-8, "YT", size=6, fill=accent, weight="bold")
            self._rect(cx-9, cy+1, cx+5, cy+4, fill="#7a5423", outline="", radius=1)
        elif kind == "collection":
            # Collection : classeur / pile de cartes, distinct de la simple liste.
            self._rect(cx-19, cy-16, cx+9, cy+18, fill="#d9c27b", outline="#2e2a20", width=1, radius=4)
            self._rect(cx-12, cy-20, cx+16, cy+14, fill="#ecda9e", outline="#2e2a20", width=1, radius=4)
            self._rect(cx-5, cy-17, cx+13, cy+11, fill="#17263d", outline=accent, width=2, radius=3)
            self._text(cx+4, cy-3, "◆", size=9, fill=accent, weight="bold")
            self._rect(cx-19, cy-12, cx-15, cy+14, fill=accent, outline="", radius=1)
        elif kind == "friends":
            # Deux shinobi + bulle de message.
            self.canvas.create_oval(*self.R(cx-20, cy-15, cx-8, cy-3), fill="#f1ece4", outline="")
            self.canvas.create_oval(*self.R(cx+2, cy-15, cx+14, cy-3), fill="#f1ece4", outline="")
            self._rect(cx-22, cy+1, cx-6, cy+16, fill="#f1ece4", outline="", radius=6)
            self._rect(cx, cy+1, cx+16, cy+16, fill="#f1ece4", outline="", radius=6)
            self._rect(cx-20, cy-12, cx-8, cy-9, fill="#6e4d8d", outline="", radius=1)
            self._rect(cx+2, cy-12, cx+14, cy-9, fill="#6e4d8d", outline="", radius=1)
            self._rect(cx+12, cy-20, cx+25, cy-8, fill="#e8dff2", outline="", radius=4)
            self.canvas.create_polygon(*self.P(cx+16,cy-8), *self.P(cx+13,cy-3), *self.P(cx+20,cy-8), fill="#e8dff2", outline="")
        elif kind == "profile":
            self.canvas.create_oval(*self.R(cx-13,cy-18,cx+13,cy+8), fill="#efe7d8", outline=accent, width=2)
            self._rect(cx-20,cy+8,cx+20,cy+22,fill="#efe7d8",outline=accent,width=1,radius=8)
        elif kind == "guide":
            # Petit manuel ouvert : immédiatement identifiable comme aide/règles.
            self._rect(cx-22, cy-17, cx-2, cy+17, fill="#edd49a", outline="#3b2a1a", width=1, radius=3)
            self._rect(cx+2, cy-17, cx+22, cy+17, fill="#edd49a", outline="#3b2a1a", width=1, radius=3)
            self._rect(cx-2, cy-15, cx+2, cy+17, fill="#9c6a32", outline="", radius=1)
            self._text(cx-12, cy-2, "?", size=14, fill="#704316", weight="bold")
            self._text(cx+12, cy-2, "!", size=14, fill="#704316", weight="bold")
        elif kind in {"cards", "deck"}:
            self._rect(cx-18, cy-18, cx+7, cy+15, fill="#e7c271", outline="#2f2417", width=1, radius=4)
            self._rect(cx-7, cy-13, cx+18, cy+20, fill="#f0d38c", outline="#2f2417", width=1, radius=4)
            self._text(cx+6, cy+3, "◆", size=10, fill="#55412d", weight="bold")
        elif kind == "screen":
            self._rect(cx-17, cy-13, cx+17, cy+10, fill="", outline=accent, width=2, radius=3)
            self._rect(cx-3, cy+10, cx+3, cy+17, fill=accent, outline="")
            self._rect(cx-11, cy+17, cx+11, cy+20, fill=accent, outline="")
        elif kind == "audio":
            self._text(cx-5, cy, "◀", size=18, fill=accent, weight="bold")
            self.canvas.create_arc(*self.R(cx-2, cy-15, cx+24, cy+15), start=-55, extent=110, style="arc", outline=accent, width=scale_w)
            self.canvas.create_arc(*self.R(cx+5, cy-20, cx+34, cy+20), start=-48, extent=96, style="arc", outline=accent, width=scale_w)
        elif kind == "quit":
            self._rect(cx-16, cy-17, cx+5, cy+17, fill="", outline=accent, width=2, radius=2)
            self._text(cx+11, cy, ">", size=19, fill=accent, weight="bold")

    def _menu_mode_button_pro(self, x1, y1, x2, y2, title, subtitle, command, accent, icon_kind):
        self._rect(x1, y1, x2, y2, fill="#111b29", outline="#71431f", width=1, radius=13)
        self._rect(x1+1, y1+1, x1+80, y2-1, fill="#1a2940", outline="#594226", width=1, radius=12)
        self._rect(x1+2, y1+2, x1+78, y1+6, fill=accent, outline="", radius=4)
        self._menu_draw_icon(icon_kind, x1+18, y1+11, x1+62, y2-10, accent)
        cy = (y1+y2)/2
        self._text(x1+106, cy-9, title, size=16, weight="bold", anchor="w")
        self._text(x1+106, cy+15, subtitle, size=9, fill="#b2bdcc", anchor="w")
        self._text(x2-31, cy, ">", size=24, fill="#e79533", weight="bold")
        self._add_click(x1, y1, x2, y2, command)

    def _menu_compact_button_pro(self, x1, y1, x2, y2, title, subtitle, command, accent, icon_kind):
        self._rect(x1, y1, x2, y2, fill="#111b29", outline="#69411f", width=1, radius=13)
        self._menu_draw_icon(icon_kind, x1+18, y1+10, x1+68, y2-9, accent)
        self._text(x1+88, y1+24, title, size=11, weight="bold", anchor="w")
        self._text(x1+88, y1+45, subtitle, size=8, fill="#aab6c6", anchor="w")
        self._text(x2-23, (y1+y2)/2, ">", size=18, fill="#e79533", weight="bold")
        self._add_click(x1, y1, x2, y2, command)

    def _menu_option_button_pro(self, x1, y1, x2, y2, title, command, accent, icon_kind):
        outline = "#834035" if icon_kind == "quit" else "#8b5d2f"
        self._rect(x1, y1, x2, y2, fill="#111a27", outline=outline, width=1, radius=12)
        self._menu_draw_icon(icon_kind, x1+12, y1+11, x1+55, y2-10, accent)
        self._text((x1+x2)/2+19, (y1+y2)/2, title, size=11, weight="bold")
        self._add_click(x1, y1, x2, y2, command)

    def _menu_donation_button_pro(self, x1, y1, x2, y2):
        tipeee = "#f05c7f"
        self._rect(x1, y1, x2, y2, fill="#27191d", outline="#9d513e", width=2, radius=13)
        self._rect(x1+2, y1+2, x1+9, y2-2, fill="#e67432", outline="", radius=4)
        # Un seul grand cœur : il fait partie visuellement du message.
        self._text(x1+48, (y1+y2)/2, "♥", size=31, fill=tipeee, weight="bold")
        self._text(x1+91, y1+27, "FAIRE UN DON À YUGITO", size=14, weight="bold", anchor="w")
        self._text(x1+91, y1+50, "Don volontaire via Tipeee", size=8, fill="#d8b8b9", anchor="w")
        self._text(x2-58, y1+29, "tipeee", size=14, fill="#ff7f9d", weight="bold", anchor="e")
        self._text(x2-24, (y1+y2)/2, ">", size=20, fill=tipeee, weight="bold")
        self._add_click(x1, y1, x2, y2, self._open_tipeee)

    def _menu_discord_button(self, x1, y1, x2, y2):
        discord = "#7289da"
        self._rect(x1, y1, x2, y2, fill="#17223f", outline="#687fcb", width=1, radius=13)
        # Asset Discord pré-rendu, aucune dépendance Pillow nécessaire au runtime.
        image = self._scaled_asset("menu_discord")
        if image is not None:
            px, py = self.P(x1+24, y1+12)
            self.canvas.create_image(px, py, image=image, anchor="nw")
        else:
            self._text(x1+47, (y1+y2)/2, "●●", size=12, fill="#dfe6ff", weight="bold")
        self._text(x1+91, y1+27, "LIEN DISCORD", size=14, fill="#eef1ff", weight="bold", anchor="w")
        self._text(x1+91, y1+50, "Rejoindre la communauté", size=8, fill="#aebbe9", anchor="w")
        self._text(x2-24, (y1+y2)/2, ">", size=20, fill="#dfe6ff", weight="bold")
        self._add_click(x1, y1, x2, y2, self._open_discord)

    # ------------------------------------------------------------------
    # Classic 1.2.8 - Guide de combat / manuel pour nouveaux joueurs
    # ------------------------------------------------------------------
    def show_combat_guide(self):
        self.current_screen = "combat_guide"
        self.combat_guide_scroll = 0.0
        self.redraw()

    def _combat_guide_max_scroll(self) -> float:
        # Le guide 1.2.9 est volontairement très détaillé : sa hauteur est
        # supérieure à celle de la fenêtre et se comporte comme une page web.
        return 2380.0

    def _combat_guide_scroll_by(self, amount: float):
        self.combat_guide_scroll = max(0.0, min(self._combat_guide_max_scroll(), self.combat_guide_scroll + amount))
        self.redraw()

    def _guide_section(self, y: float, title: str, body: str, *, accent="#e1a24b", height=150):
        # Dessine aussi les sections partiellement visibles : les masques du
        # viewport réalisent le clipping, comme sur une vraie page scrollable.
        if y + height < 142 or y > 858:
            return
        x1, x2 = 190, 1410
        self._rect(x1, y, x2, y + height, fill="#111b29", outline="#3b4d64", width=1, radius=13)
        self._rect(x1 + 1, y + 1, x1 + 7, y + height - 1, fill=accent, outline="", radius=4)
        self._text(x1 + 26, y + 27, title, size=17, fill=accent, weight="bold", anchor="w")
        self._text(x1 + 26, y + 57, body, size=11, fill="#d8e1ec", anchor="nw", width=1158, justify="left")

    def _draw_guide_element_wheel(self, cx: float, cy: float, radius: float = 104):
        elems = [
            ("FEU", "火", "#c94b3f", -90),
            ("VENT", "風", "#5ea66c", -18),
            ("FOUDRE", "雷", "#d2a93b", 54),
            ("TERRE", "土", "#9b704c", 126),
            ("EAU", "水", "#4e82bb", 198),
        ]
        pts = []
        for label, kanji, color, deg in elems:
            a = math.radians(deg)
            x = cx + math.cos(a) * radius
            y = cy + math.sin(a) * radius
            pts.append((x, y, label, kanji, color))
        for i, (x, y, label, kanji, color) in enumerate(pts):
            nx, ny, *_ = pts[(i + 1) % len(pts)]
            p1 = self.P(x, y)
            p2 = self.P(nx, ny)
            self.canvas.create_line(*p1, *p2, fill="#d7a45c", width=max(1, int(2*self._scale()[0])), arrow=tk.LAST, arrowshape=(8,10,4))
        self.canvas.create_oval(*self.R(cx-48, cy-48, cx+48, cy+48), fill="#0c1522", outline="#40516a", width=max(1, int(2*self._scale()[0])))
        self._text(cx, cy, "◎", size=34, fill="#7990a8", weight="bold")
        for x, y, label, kanji, color in pts:
            self.canvas.create_oval(*self.R(x-31, y-31, x+31, y+31), fill="#0e1724", outline=color, width=max(1, int(3*self._scale()[0])))
            self._text(x, y-3, kanji, size=19, fill=color, weight="bold")
            self._text(x, y+39, label, size=9, fill=color, weight="bold")

    def _draw_combat_guide(self):
        self._gradient_background()
        self._rect(0, 0, 1600, 900, fill="#07101b", outline="")
        self.click_regions.clear()
        self.combat_guide_scroll = max(0.0, min(self._combat_guide_max_scroll(), float(self.combat_guide_scroll)))
        scroll = self.combat_guide_scroll
        viewport_top, viewport_bottom = 142, 817

        # Grand panneau central.
        self._rect(120, 42, 1480, 858, fill="#0c1420", outline="#5c7089", width=2, radius=18)
        self._rect(126, 48, 1474, 852, fill="", outline="#26374b", width=1, radius=16)

        # ------------------------------------------------------------------
        # Contenu scrollable. Le texte est volontairement explicite : ce guide
        # doit pouvoir servir de tutoriel à quelqu'un qui lance YUGITO pour la
        # première fois, sans supposer qu'il connaît déjà les règles.
        # ------------------------------------------------------------------
        y = 165 - scroll
        self._guide_section(
            y,
            "1. LE BUT DU DUEL",
            "Chaque joueur possède 4000 PV et combat avec 8 Ninjas. Trois Ninjas sont présents sur le terrain et les 5 autres forment la réserve. Réduis les PV du joueur adverse à 0 pour gagner. Un joueur perd également s'il ne possède plus aucune carte. Lorsqu'une attaque enlève plus de PV qu'il n'en reste au Ninja ciblé, le surplus est transmis aux PV du joueur adverse.",
            accent="#f08a36",
            height=154,
        )
        y += 174

        # 2. Attaque / défense : panneau pédagogique avec formule + exemples
        # + règle anti-écart de rareté YUGITO06 R5.
        h = 420
        if y + h >= viewport_top and y <= viewport_bottom:
            self._rect(190, y, 1410, y + h, fill="#111b29", outline="#3b4d64", width=1, radius=13)
            self._rect(191, y + 1, 197, y + h - 1, fill="#e6c35d", outline="", radius=4)
            self._text(216, y + 28, "2. ATTAQUE = TA STAT CONTRE LA MEME STAT EN DEFENSE", size=17, fill="#e6c35d", weight="bold", anchor="w")
            self._text(216, y + 60, "Quand tu choisis TAIJUTSU, NINJUTSU ou GENJUTSU, cette statistique sert A LA FOIS d'attaque pour ton Ninja et de défense pour la cible. Il n'existe pas une statistique DEF séparée : on compare toujours le même art des deux côtés.", size=10, fill="#d8e1ec", anchor="nw", width=1150, justify="left")

            self._rect(225, y + 118, 1375, y + 158, fill="#0b1420", outline="#5a6575", width=1, radius=8)
            self._text(800, y + 138, "DEGATS DE BASE = STAT DE L'ATTAQUANT - MEME STAT DE LA CIBLE   •   RESULTAT POSITIF : MINIMUM 100", size=11, fill="#f5e7b8", weight="bold")

            # Deux exemples très simples rendent la notion attaque/défense immédiate.
            self._rect(225, y + 176, 785, y + 257, fill="#0d1724", outline="#4f7ea8", width=1, radius=9)
            self._text(245, y + 195, "EXEMPLE NINJUTSU", size=9, fill="#69b6e8", weight="bold", anchor="w")
            self._text(245, y + 221, "Attaquant : 1400 NIN   -   Cible : 1000 NIN   =   400 dégâts", size=10, fill="#dce7f3", anchor="w")
            self._text(245, y + 244, "Ici les 1000 NIN de la cible jouent le rôle de sa défense Ninjutsu.", size=9, fill="#9fb1c5", anchor="w")

            self._rect(810, y + 176, 1375, y + 257, fill="#0d1724", outline="#9a6b72", width=1, radius=9)
            self._text(830, y + 195, "SI L'ATTAQUANT EST PLUS FAIBLE", size=9, fill="#e59b9b", weight="bold", anchor="w")
            self._text(830, y + 221, "Attaquant : 900 TAI   -   Cible : 1200 TAI   =   le calcul tombe à 0", size=10, fill="#dce7f3", anchor="w")
            self._text(830, y + 244, "La règle de secours par étoiles ci-dessous s'applique alors.", size=9, fill="#9fb1c5", anchor="w")

            self._rect(225, y + 274, 1375, y + 355, fill="#0b1420", outline="#c78b4a", width=1, radius=8)
            self._text(245, y + 292, "ATTAQUE A 0 DEGAT : 100 FIXES + BONUS SUR LES PV MAX DE LA CIBLE", size=10, fill="#f2bc72", weight="bold", anchor="w")
            self._text(245, y + 316, "5★ +1 %   •   4,5★ +3 %   •   4★ +6 %   •   3,5★ +9 %   •   3★ +12 %", size=11, fill="#f4e6c6", weight="bold", anchor="w")
            self._text(245, y + 339, "Le bonus en % est plafonné à +100 : le secours vaut donc 100 à 200 dégâts maximum. Il n'est pas reboosté au-delà de 200 par SUPER EFFICACE ; les boucliers s'appliquent ensuite normalement.", size=9, fill="#c9d5e3", anchor="w")

            self._text(216, y + 382, "Cette règle favorise les cartes moins rares face aux grosses défenses. Elle ne force jamais les dégâts contre une esquive, une immunité ou une cible inciblable. Les techniques à dégâts fixes gardent leur propre texte.", size=9, fill="#bdc9d8", anchor="w", width=1155)
        y += 440

        # Roue élémentaire.
        h = 330
        if y + h >= viewport_top and y <= viewport_bottom:
            self._rect(190, y, 1410, y + h, fill="#111b29", outline="#3b4d64", width=1, radius=13)
            self._text(216, y + 28, "3. ROUE DES FAIBLESSES ELEMENTAIRES", size=17, fill="#65b5df", weight="bold", anchor="w")
            self._text(216, y + 63, "FEU > VENT > FOUDRE > TERRE > EAU > FEU", size=13, fill="#f4e6c6", weight="bold", anchor="w")
            self._text(216, y + 94, "Si l'élément de l'attaquant bat celui de la cible, l'attaque est SUPER EFFICACE : les dégâts calculés gagnent +10 %, puis +150 dégâts. Les dégâts fixes ne reçoivent pas ce bonus. Kakuzu est l'exception : il n'a aucune faiblesse élémentaire et ses attaques sont toujours super efficaces.", size=10, fill="#cfdae8", anchor="nw", width=620, justify="left")
            self._draw_guide_element_wheel(1110, y + 174, 105)
        y += 350

        self._guide_section(y, "4. LES 2 ACTIONS D'UN TOUR", "Tu prépares jusqu'à deux actions. ACTION 1 est exécutée à la validation de ton tour. ACTION 2 est une réaction programmée : elle se déclenche quand l'adversaire finalise son prochain tour, AVANT ses actions. Attaque Taijutsu/Ninjutsu/Genjutsu, technique spéciale et switch suivent exactement cette même règle. Si le Ninja est mort, immobilisé ou si la cible n'existe plus au déclenchement, l'A2 est perdue. Minato possède en plus son action gratuite : elle n'utilise aucune des deux actions.", accent="#dca65e", height=198)
        y += 218
        self._guide_section(y, "5. TECHNIQUES SPECIALES & RECHARGES", "Les techniques spéciales obéissent au texte de leur carte. Certaines sont disponibles une seule fois pour cette instance, d'autres se rechargent après plusieurs tours : l'interface affiche alors T 1/3, T 2/3, etc. Les spéciales peuvent attaquer, protéger, soigner, contrôler ou modifier les règles normales ; lorsqu'une spéciale dit qu'elle ignore une défense, un bouclier ou un passif, cette exception prime.", accent="#dc804f", height=180)
        y += 200
        self._guide_section(y, "6. RESERVE, K.O. & REMPLACEMENT", "Quand un Ninja est définitivement K.O., il rejoint le cimetière. S'il reste des cartes en réserve, le jeu te propose jusqu'à 3 Ninjas et tu en choisis un pour reprendre l'emplacement. Le terrain cherche donc à conserver 3 Ninjas tant que ta réserve le permet. Certains passifs peuvent toutefois empêcher une mort, renvoyer une carte au deck, imposer un remplacement ou modifier le cimetière.", accent="#c87979", height=180)
        y += 200

        # Synergies.
        h = 245
        if y + h >= viewport_top and y <= viewport_bottom:
            self._rect(190, y, 1410, y + h, fill="#111b29", outline="#3b4d64", width=1, radius=13)
            self._text(216, y + 28, "7. SYNERGIES DE TERRAIN", size=17, fill="#8bd39b", weight="bold", anchor="w")
            self._text(216, y + 61, "Les synergies sont recalculées avec les 3 Ninjas actuellement présents sur ton terrain. Pour chaque Ninja, le jeu conserve seulement le meilleur bonus applicable : plusieurs synergies ne s'additionnent donc pas entre elles.", size=10, fill="#d5e5d8", anchor="nw", width=1155, justify="left")
            boxes = [
                (225, "+12,5 %", "2 membres d'une même famille", "#5ea66c"),
                (610, "+20 %", "3 Ninjas du terrain dans la même famille", "#d8a43f"),
                (995, "+15 %", "Duo explicite présent ensemble", "#a769df"),
            ]
            for bx, bonus, label, color in boxes:
                self._rect(bx, y + 123, bx + 340, y + 213, fill="#0d1724", outline=color, width=2, radius=10)
                self._text(bx + 170, y + 151, bonus, size=18, fill=color, weight="bold")
                self._text(bx + 170, y + 184, label, size=9, fill="#d8e1ec", width=300)
        y += 265

        self._guide_section(y, "8. EFFETS A CONNAITRE", "BOUCLIER : absorbe les prochains dégâts jusqu'à épuisement.  •  INCIBLABLE : la carte ne peut pas être choisie comme cible pendant l'effet.  •  PARALYSIE / STUN : empêche la carte d'agir pendant la durée indiquée.  •  POISON / DEGATS PAR TOUR : retirent des PV au moment précisé par l'effet.  •  SOIN : ne dépasse jamais les PV maximum de la carte.", accent="#b883db", height=188)
        y += 208

        # 9. Construction : véritable mode d'emploi, distinct du draft de match.
        h = 300
        if y + h >= viewport_top and y <= viewport_bottom:
            self._rect(190, y, 1410, y + h, fill="#111b29", outline="#3b4d64", width=1, radius=13)
            self._rect(191, y + 1, 197, y + h - 1, fill="#e0b94e", outline="", radius=4)
            self._text(216, y + 28, "9. CONSTRUIRE UN DECK LEGAL", size=17, fill="#e0b94e", weight="bold", anchor="w")
            self._text(216, y + 59, "Un deck de duel contient exactement 8 Ninjas DIFFERENTS. Les étoiles sont un budget de puissance : additionne les étoiles de tes 8 cartes sans dépasser 32,5★. Tu n'es pas obligé d'utiliser tous les paliers ni d'atteindre exactement 32,5★.", size=10, fill="#d8e1ec", anchor="nw", width=1155, justify="left")

            rules = [
                ("3★", "ILLIMITE", "#7fb0d8"),
                ("3,5★", "MAX 4", "#d7b252"),
                ("4★", "MAX 3", "#d88c52"),
                ("4,5★", "MAX 2", "#c97878"),
                ("5★", "MAX 1", "#b77bd5"),
            ]
            bx = 225
            for stars, limit, color in rules:
                self._rect(bx, y + 126, bx + 205, y + 202, fill="#0d1724", outline=color, width=1, radius=9)
                self._text(bx + 102, y + 149, stars, size=13, fill=color, weight="bold")
                self._text(bx + 102, y + 179, limit, size=9, fill="#dfe7f0", weight="bold")
                bx += 230

            self._text(216, y + 226, "IMPORTANT : le bouton CREE TON DECK du menu sert de laboratoire pour préparer et vérifier une composition. Au lancement d'un duel, les 8 cartes réellement jouées sont constituées pendant le DRAFT expliqué juste en dessous.", size=10, fill="#f4d89a", weight="bold", anchor="nw", width=1155, justify="left")
        y += 320

        # 10. Le vrai déroulement avant le combat.
        h = 330
        if y + h >= viewport_top and y <= viewport_bottom:
            self._rect(190, y, 1410, y + h, fill="#111b29", outline="#3b4d64", width=1, radius=13)
            self._rect(191, y + 1, 197, y + h - 1, fill="#67a7d8", outline="", radius=4)
            self._text(216, y + 28, "10. AVANT LE COMBAT : COMMENT TES 8 CARTES SONT CHOISIES", size=17, fill="#67a7d8", weight="bold", anchor="w")
            self._text(216, y + 58, "Le choix se fait en plusieurs étapes. Les cartes choisies pendant le draft sont retirées du choix de l'adversaire : vous construisez donc vos deux decks en vous partageant le même catalogue.", size=10, fill="#d8e1ec", anchor="nw", width=1155, justify="left")

            steps = [
                ("1", "SHIFUMI", "Le gagnant obtient le tout premier choix du draft."),
                ("2", "DRAFT : 8 CHACUN", "A tour de rôle, chacun prend un Ninja disponible jusqu'à posséder 8 cartes."),
                ("3", "DEBLOCAGE DES ETOILES", "Les raretés se débloquent progressivement. Une fois un palier atteint, il reste disponible jusqu'à la fin : choisir moins étoilé ne ferme jamais l'accès à une 4,5★ ou 5★ débloquée, sous réserve des quotas et des 32,5★."),
                ("4", "CHOISIS TES 3 DEPARTS", "Parmi tes 8 Ninjas, choisis exactement 3 cartes en privé. Elles commencent sur le terrain ; les 5 autres deviennent ta réserve cachée."),
                ("5", "SECOND SHIFUMI", "Une fois les deux trios prêts, un nouveau Shifumi décide qui joue le premier tour du duel."),
            ]
            sy = y + 115
            for num, title, txt in steps:
                self._rect(225, sy, 1375, sy + 37, fill="#0d1724", outline="#34495f", width=1, radius=7)
                self._rect(235, sy + 5, 263, sy + 32, fill="#162a3c", outline="#67a7d8", width=1, radius=6)
                self._text(249, sy + 18, num, size=9, fill="#8dc9f2", weight="bold")
                self._text(280, sy + 18, title, size=9, fill="#f3e7ca", weight="bold", anchor="w")
                self._text(500, sy + 18, txt, size=8, fill="#cbd7e5", anchor="w", width=850)
                sy += 41
        y += 350

        self._guide_section(y, "11. CONSEIL POUR DEBUTER", "Ne regarde pas uniquement les grosses statistiques. Vérifie l'élément, le passif, la spéciale et surtout les synergies de ton trio. En attaque, demande-toi toujours : 'quelle statistique de ma carte bat la MEME statistique chez sa cible ?'. Utilise LISTE DES CARTES pour lire les fiches complètes et CREE TON DECK pour préparer des idées de composition avant de lancer un duel.", accent="#f08a36", height=176)

        # Masques du viewport scrollable.
        self._rect(132, 0, 1468, 41, fill="#07101b", outline="")
        self._rect(132, 42, 1468, viewport_top - 1, fill="#0c1420", outline="")
        self._rect(132, viewport_bottom + 1, 1468, 858, fill="#0c1420", outline="")
        self._rect(132, 859, 1468, 900, fill="#07101b", outline="")

        # En-tête fixe.
        self._text(168, 79, "GUIDE DE COMBAT", size=29, weight="bold", anchor="w", family=DISPLAY_FONT_TOKEN)
        self._text(168, 113, "Les règles essentielles expliquées pas à pas pour tes premiers duels", size=11, fill="#b7c4d4", anchor="w")
        self._button(1280, 66, 1435, 112, "RETOUR MENU", self.show_main_menu, fill="#151d29", accent=ACCENT, small=True)
        self._rect(160, 132, 1440, 134, fill="#493421", outline="")

        # Scrollbar de la page.
        max_scroll = self._combat_guide_max_scroll()
        track_x1, track_x2 = 1441, 1451
        track_y1, track_y2 = 151, 806
        track_h = track_y2 - track_y1
        thumb_h = max(82, track_h * (track_h / (track_h + max_scroll)))
        ratio = 0.0 if max_scroll <= 0 else self.combat_guide_scroll / max_scroll
        thumb_y1 = track_y1 + ratio * (track_h - thumb_h)
        self._rect(track_x1, track_y1, track_x2, track_y2, fill="#182334", outline="", radius=5)
        self._rect(track_x1, thumb_y1, track_x2, thumb_y1 + thumb_h, fill="#d28a3d", outline="", radius=5)
        self._text(790, 836, "MOLETTE : faire defiler   •   ECHAP : retour au menu", size=9, fill="#8797aa")

    # ------------------------------------------------------------------
    # V35 - Liste / encyclopédie des cartes
    # ------------------------------------------------------------------
    def _catalog_cards(self) -> list[CardDefinition]:
        return sorted(self.cards, key=lambda c: (float(c.stars), c.name.lower()))

    def _catalog_synergy_text(self, card: CardDefinition) -> str:
        """Affiche chaque synergie explicitement avec les labels S 3/3 et S 2/2."""
        names = {c.id: c.name for c in self.cards}
        lines: list[str] = []
        seen_families: set[tuple[str, ...]] = set()
        for family in SYNERGY_FAMILIES:
            if card.id not in family:
                continue
            mates = tuple(sorted((names.get(cid, cid.replace("_", " ").title()) for cid in family if cid != card.id), key=str.casefold))
            if mates and mates not in seen_families:
                seen_families.add(mates)
                lines.append("S 3/3 (+20 % ALL STATS ; 2 membres = +12,5 %) : " + " • ".join(mates))
        duos: set[str] = set()
        for duo in SYNERGY_DUOS:
            if card.id in duo:
                duos.update(names.get(cid, cid.replace("_", " ").title()) for cid in duo if cid != card.id)
        if duos:
            lines.append("S 2/2 (+15 % ALL STATS) : " + " • ".join(sorted(duos, key=str.casefold)))
        return "\n".join(lines) if lines else "Aucun lien de synergie."

    def _catalog_role_label(self, role: str) -> str:
        return CARD_ROLE_LABELS.get(str(role), str(role))

    def _catalog_search_changed(self, _event=None):
        self.card_catalog_query = self.card_catalog_query_var.get()
        self.card_catalog_scroll = 0.0
        self.redraw()
        try:
            self.card_catalog_search_entry.focus_set()
        except Exception:
            pass

    def _toggle_catalog_role(self, role: str):
        role=str(role)
        if role in self.card_catalog_role_filters: self.card_catalog_role_filters.remove(role)
        else: self.card_catalog_role_filters.add(role)
        self.card_catalog_scroll=0.0; self.redraw()

    def _clear_catalog_roles(self):
        self.card_catalog_role_filters.clear(); self.card_catalog_scroll=0.0; self.redraw()

    def _draw_catalog_role_toolbar(self):
        y=185; x=80
        self._text(80,y-10,"RÔLES — clique pour cumuler (ex. TANK + POISON)",size=9,fill="#aebed0",weight="bold",anchor="w")
        roles=tuple(CARD_ROLE_PRIMARY)+tuple(CARD_ROLE_ADVANCED)
        for role in roles:
            label=self._catalog_role_label(role)
            w=max(92,min(150,54+len(label)*6))
            if x+w>1515:
                x=80; y+=42
            active=role in self.card_catalog_role_filters
            self._button(x,y,x+w,y+36,("✓ " if active else "")+label,lambda r=role:self._toggle_catalog_role(r),fill="#c66b0d" if active else "#111a26",accent="#ffbd59" if active else "#52647a",small=True)
            x+=w+7
        if self.card_catalog_role_filters:
            if x+128>1515:
                x=80; y+=42
            self._button(x,y,x+128,y+36,"TOUT EFFACER",self._clear_catalog_roles,fill="#2b161b",accent=RED,small=True)

    def _draw_card_role_badges(self, card: CardDefinition, x: float, y: float, max_width: float=850):
        cx=x
        for role in getattr(card,"roles",()) or ():
            label=self._catalog_role_label(role); w=max(80,min(150,30+len(label)*7))
            if cx+w>x+max_width: break
            self._rect(cx,y,cx+w,y+27,fill="#18283b",outline="#b97832",width=1,radius=12)
            self._text(cx+w/2,y+13.5,label,size=8,fill="#ffe9bd",weight="bold")
            cx+=w+8

    def show_card_catalog(self):
        self.current_screen="card_catalog"; self.card_catalog_scroll=0.0; self._economy_refresh_async(force=False); self.redraw()

    def _draw_card_catalog(self):
        self._gradient_background("#101827", "#05080d")
        self._text(80,52,"LISTE DES CARTES",size=30,weight="bold",anchor="w",family=DISPLAY_FONT_TOKEN)
        self._text(80,86,"Recherche ludique : possession + étoiles + rôles cumulables",size=10,fill=MUTED,anchor="w")
        self._button(1390,36,1535,88,"MENU",self.show_main_menu,small=True)
        mode=getattr(self,"card_catalog_ownership_filter","all")
        self._account_filter_buttons(mode,lambda k:self._set_account_filter("card_catalog",k))
        # Recherche texte native PC
        try:
            scale=min(self.canvas.winfo_width()/VIRTUAL_W,self.canvas.winfo_height()/VIRTUAL_H)
            ox=(self.canvas.winfo_width()-VIRTUAL_W*scale)/2; oy=(self.canvas.winfo_height()-VIRTUAL_H*scale)/2
            self.card_catalog_search_entry.configure(font=(self.ui_font_family,max(9,int(11*scale)),"bold"))
            self.card_catalog_search_entry.place(x=int(ox+1115*scale),y=int(oy+130*scale),width=int(395*scale),height=max(30,int(44*scale))); self.card_catalog_search_entry.lift()
        except Exception:
            pass
        self._draw_catalog_role_toolbar()
        cards=self._account_filter_cards(mode,screen="card_catalog"); scroll=float(getattr(self,"card_catalog_scroll",0.0))
        selected=" + ".join(self._catalog_role_label(r) for r in sorted(self.card_catalog_role_filters))
        self._text(1515,105,f"{len(cards)} carte(s)"+(f" • {selected}" if selected else ""),size=9,fill="#c2cfde",anchor="e",weight="bold")
        xs,top,row_pitch,_visible,_rows,_max_scroll=self._account_grid_metrics("card_catalog",len(cards))
        for i,card in enumerate(cards):
            row,col=divmod(i,3); x=xs[col]; y=top+row*row_pitch-scroll
            if y < top or y+DRAFT_CARD_H+30 > 872: continue
            self._draw_card(card,x,y,"draft"); self._add_click(x,y,x+DRAFT_CARD_W,y+DRAFT_CARD_H,lambda c=card:self._open_card_reader(c))
            if self._economy_online():
                status,_=self._economy_card_status(card.id); self._draw_economy_status_badge(x,y+DRAFT_CARD_H+3,x+DRAFT_CARD_W,y+DRAFT_CARD_H+25,status,compact=True)
        self._draw_account_scroll_indicator("card_catalog",len(cards),scroll)

    def _deck_builder_cards(self) -> list[CardDefinition]:
        cards=sorted(self.cards,key=lambda c:(c.stars,c.name.lower()))
        if self.deck_builder_filter == "owned" and self._economy_online():
            allowed=self._economy_available_ids(); cards=[c for c in cards if c.id in allowed]
        return cards

    def _deck_builder_total_stars(self, cards: list[CardDefinition] | None = None) -> float:
        cards = self.deck_builder_deck if cards is None else cards
        return sum(float(card.stars) for card in cards)

    def _deck_builder_final_valid(self, cards: list[CardDefinition]) -> bool:
        if len(cards) > 8:
            return False
        if self._deck_builder_total_stars(cards) > MAX_TOTAL_STAR_VALUE + 0.001:
            return False
        if len({card.id for card in cards}) != len(cards):
            return False
        for stars, limit in STAR_VALUE_LIMITS.items():
            if limit is not None and self._star_count(cards, stars) > limit:
                return False
        # 1.2.3 : la montée progressive appartient désormais au TEMPS du draft,
        # pas à la composition finale. Un deck peut donc volontairement prendre
        # des cartes moins étoilées et finir sous 32,5★.
        return True

    def _deck_builder_card_allowed(self, card: CardDefinition) -> tuple[bool, str]:
        deck = self.deck_builder_deck
        # Le créateur reste aussi un laboratoire Solo : dans l'onglet TOUTES,
        # une carte non possédée peut être ajoutée à une composition locale.
        # La vraie interdiction Multi est appliquée dans le draft + côté serveur.
        if any(existing.id == card.id for existing in deck):
            return False, "Cette carte est déjà dans ton deck."
        if len(deck) >= 8:
            return False, "Ton deck contient déjà 8 cartes."
        limit = STAR_VALUE_LIMITS.get(float(card.stars))
        if limit is not None and self._star_count(deck, card.stars) >= limit:
            return False, f"Limite atteinte pour les cartes {card.star_label}."
        if self._deck_builder_total_stars() + float(card.stars) > MAX_TOTAL_STAR_VALUE + 0.001:
            return False, f"Cette carte dépasserait la limite de {MAX_TOTAL_STAR_VALUE:g}★."
        return True, ""

    def _deck_builder_content_height(self) -> float:
        cards = self._deck_builder_cards()
        rows = max(1, (len(cards) + 2) // 3)
        row_pitch = DRAFT_CARD_H + 54
        return rows * row_pitch - 20

    def _deck_builder_max_scroll(self) -> float:
        viewport_h = 820 - 260
        return max(0.0, self._deck_builder_content_height() - viewport_h)

    def _deck_builder_scroll_by(self, amount: float):
        if self.current_screen != "deck_builder":
            return
        self.deck_builder_scroll = max(0.0, min(self._deck_builder_max_scroll(), self.deck_builder_scroll + amount))
        self.redraw()

    def _set_deck_filter(self, value: str):
        self.deck_builder_filter = "all" if value == "all" else "owned"
        self.deck_builder_scroll = 0.0
        self.redraw()

    def show_deck_builder(self):
        self.current_screen = "deck_builder"
        self._economy_refresh_async()
        self.deck_builder_scroll = max(0.0, min(self.deck_builder_scroll, self._deck_builder_max_scroll()))
        self.deck_builder_notice = ""
        self.redraw()

    def _deck_builder_add(self, card: CardDefinition):
        allowed, reason = self._deck_builder_card_allowed(card)
        if not allowed:
            self.deck_builder_notice = reason
            self.redraw()
            return
        self.deck_builder_deck.append(card)
        self.deck_builder_notice = f"{card.name} ajouté au deck."
        self.redraw()

    def _deck_builder_remove(self, card_id: str):
        candidate = list(self.deck_builder_deck)
        removed = next((c for c in candidate if c.id == card_id), None)
        if removed is None:
            return
        candidate.remove(removed)
        if not self._deck_builder_final_valid(candidate):
            self.deck_builder_notice = "Retire d'abord les cartes des paliers supérieurs pour conserver un deck légal."
            self.redraw()
            return
        self.deck_builder_deck = candidate
        self.deck_builder_notice = f"{removed.name} retiré du deck."
        self.redraw()

    def _deck_builder_clear(self):
        self.deck_builder_deck.clear()
        self.deck_builder_notice = "Deck vidé."
        self.redraw()

    def _deck_builder_page_change(self, delta: int):
        cards = self._deck_builder_cards()
        max_page = max(0, (len(cards) - 1) // self.deck_builder_per_page)
        self.deck_builder_page = max(0, min(max_page, self.deck_builder_page + delta))
        self.redraw()

    def _draw_deck_builder(self):
        self._gradient_background("#101827", "#05080d")
        cards = self._deck_builder_cards()
        deck = self.deck_builder_deck
        total_stars = self._deck_builder_total_stars()

        # ------------------------------------------------------------------
        # Catalogue à gauche : vraies cartes + fenêtre de défilement.
        # IMPORTANT : Tk Canvas ne possède pas de clipping de groupe natif.
        # Les cartes sont donc dessinées d'abord, puis les zones situées hors
        # du viewport sont recouvertes avant de redessiner tous les éléments
        # fixes. Visuellement, cela se comporte comme une vraie fenêtre scroll.
        # ------------------------------------------------------------------
        panel_x1, panel_x2 = 35, 1035
        panel_y1, panel_y2 = 200, 842
        content_top, content_bottom = 260, 820
        self._rect(panel_x1, panel_y1, panel_x2, panel_y2, fill="#0e1520", outline="#2d3b50", width=2, radius=20)

        row_pitch = DRAFT_CARD_H + 54
        col_x = (65, 375, 685)
        for idx, card in enumerate(cards):
            row, col = divmod(idx, 3)
            x1 = col_x[col]
            y1 = content_top + row * row_pitch - self.deck_builder_scroll
            y2 = y1 + DRAFT_CARD_H
            row_bottom = y2 + 36
            if row_bottom < content_top - 5 or y1 > content_bottom + 5:
                continue

            in_deck = any(c.id == card.id for c in deck)
            allowed, _reason = self._deck_builder_card_allowed(card)
            self._draw_card(card, x1, y1, "draft", selected=in_deck)

            # Une carte non encore accessible reste visible, comme dans le draft,
            # mais clairement verrouillée par les règles d'étoiles.
            if not in_deck and not allowed:
                self._stipple_rect(
                    x1 + 3, y1 + 3, x1 + DRAFT_CARD_W - 3, y2 - 3,
                    fill="#05080d", stipple="gray50", outline="#7a4650", width=2,
                )
                self._rect(x1 + 28, y1 + 112, x1 + DRAFT_CARD_W - 28, y1 + 158, fill="#171018", outline=RED, width=2, radius=8)
                self._text(x1 + DRAFT_CARD_W / 2, y1 + 135, "VERROUILLÉ", size=8, fill="#ff9a9a", weight="bold")

            controls_y1 = y2 + 5
            controls_y2 = y2 + 34
            if in_deck:
                self._rect(x1, controls_y1, x1 + 118, controls_y2, fill="#14271f", outline=GREEN, width=1, radius=7)
                self._text(x1 + 59, (controls_y1 + controls_y2) / 2, "DANS LE DECK", size=7, fill=GREEN, weight="bold")
            elif allowed:
                self._rect(x1, controls_y1, x1 + 118, controls_y2, fill="#1d261c", outline=ACCENT_2, width=1, radius=7)
                self._text(x1 + 59, (controls_y1 + controls_y2) / 2, "AJOUTER", size=7, fill=ACCENT_2, weight="bold")
            else:
                self._rect(x1, controls_y1, x1 + 118, controls_y2, fill="#111722", outline="#303847", width=1, radius=7)
                self._text(x1 + 59, (controls_y1 + controls_y2) / 2, "INDISPONIBLE", size=6, fill="#697483", weight="bold")
            self._rect(x1 + 124, controls_y1, x1 + DRAFT_CARD_W, controls_y2, fill="#171d27", outline="#655b42", width=1, radius=7)
            self._text(x1 + 162, (controls_y1 + controls_y2) / 2, "FICHE", size=7, fill=GOLD, weight="bold")

            # Les clics sont eux aussi strictement limités au viewport.
            visible_y1 = max(y1, content_top)
            visible_y2 = min(row_bottom, content_bottom)
            if visible_y2 > visible_y1:
                if not in_deck and allowed:
                    card_hit_bottom = min(y2, content_bottom)
                    if card_hit_bottom > visible_y1:
                        self._add_click(x1, visible_y1, x1 + DRAFT_CARD_W, card_hit_bottom, lambda c=card: self._deck_builder_add(c))
                    add_y1 = max(controls_y1, content_top)
                    add_y2 = min(controls_y2, content_bottom)
                    if add_y2 > add_y1:
                        self._add_click(x1, add_y1, x1 + 118, add_y2, lambda c=card: self._deck_builder_add(c))
                fiche_y1 = max(controls_y1, content_top)
                fiche_y2 = min(controls_y2, content_bottom)
                if fiche_y2 > fiche_y1:
                    self._add_click(x1 + 124, fiche_y1, x1 + DRAFT_CARD_W, fiche_y2, lambda c=card: self._open_card_reader(c))

        # ------------------------------------------------------------------
        # MASQUES DE CLIPPING.
        # Ils recouvrent TOUT ce qui sort du viewport, pas uniquement les
        # quelques pixels internes du panneau. Cela évite qu'une carte scrollée
        # passe sur « CRÉE TON DECK », les compteurs d'étoiles ou sous le panneau.
        # ------------------------------------------------------------------
        # Partie haute hors panneau (fond de page) puis en-tête interne du panneau.
        self._rect(panel_x1 - 4, 0, panel_x2 + 4, panel_y1 + 1, fill="#0b111b", outline="")
        # Chevauchement volontaire de 3 px virtuels avec le viewport. Tk/Windows
        # peut arrondir les coordonnées après mise à l'échelle et laisser une
        # couture d'un pixel où l'image des cartes reste visible.
        clip_overlap = 6
        self._rect(panel_x1 - 1, panel_y1 - 1, panel_x2 + 1, content_top + clip_overlap, fill="#0e1520", outline="")
        # Partie basse interne du panneau puis zone sous le panneau.
        self._rect(panel_x1 - 1, content_bottom - clip_overlap, panel_x2 + 1, panel_y2 + 1, fill="#0e1520", outline="")
        self._rect(panel_x1 - 3, panel_y2 + 1, panel_x2 + 3, 900, fill="#05080d", outline="")

        # ------------------------------------------------------------------
        # Tous les éléments fixes sont redessinés APRES les cartes et les
        # masques : ils restent donc toujours au-dessus du contenu scrollé.
        # ------------------------------------------------------------------
        # En-tête et résumé permanent des règles.
        self._rect(35, 25, 1565, 105, fill="#0e141e", outline="#2a3547", width=1, radius=14)
        self._text(65, 55, "CRÉE TON DECK", size=27, weight="bold", anchor="w", family=DISPLAY_FONT_TOKEN)
        state_fill = GREEN if len(deck) == 8 and self._deck_builder_final_valid(deck) else "#dce4ef"
        self._text(65, 86, f"{len(deck)}/8 CARTES   •   {total_stars:g}/{MAX_TOTAL_STAR_VALUE:g}★", size=12, fill=state_fill, weight="bold", anchor="w")
        self._button(900, 40, 1080, 88, "POSSÉDÉES", lambda: self._set_deck_filter("owned"), fill="#172339", accent=GREEN, small=True, enabled=self.deck_builder_filter!="owned")
        self._button(1090, 40, 1270, 88, "TOUTES", lambda: self._set_deck_filter("all"), fill="#172339", accent=BLUE, small=True, enabled=self.deck_builder_filter!="all")
        self._button(1360, 40, 1535, 88, "RETOUR MENU", self.show_main_menu, fill="#151d29", accent=ACCENT, small=True)

        # Règles d'étoiles en direct.
        self._rect(35, 120, 1565, 184, fill="#111a27", outline="#2d3b50", width=1, radius=14)
        tiers = [(3.0, 155), (3.5, 370), (4.0, 585), (4.5, 800), (5.0, 1015)]
        for stars, x in tiers:
            limit = STAR_VALUE_LIMITS.get(stars)
            count = self._star_count(deck, stars)
            label_limit = self._star_limit_label(limit)
            full = limit is not None and count >= limit
            fill = "#ff9d86" if full else "#ffd36a"
            self._text(x, 144, f"{stars:g}★", size=12, fill=GOLD, weight="bold")
            self._text(x, 166, f"{count}/{label_limit}", size=11, fill=fill, weight="bold")
        cap = self._progressive_star_cap(deck)
        self._text(1260, 143, "PALIER DÉBLOQUÉ", size=9, fill=MUTED, weight="bold")
        self._text(1260, 166, f"JUSQU'À {cap:g}★", size=12, fill=GREEN, weight="bold")

        # Bordure et titre fixes du catalogue.
        self._rect(panel_x1, panel_y1, panel_x2, panel_y2, fill="", outline="#2d3b50", width=2, radius=20)
        self._text(65, 228, "NINJAS DISPONIBLES", size=15, weight="bold", anchor="w", family=DISPLAY_FONT_TOKEN)
        self._text(1000, 228, "MOLETTE ↑↓   •   CLIQUE CARTE = AJOUTER", size=8, fill=MUTED, anchor="e", weight="bold")

        # Barre de défilement.
        track_x1, track_x2 = 1004, 1019
        track_y1, track_y2 = content_top, content_bottom
        self._rect(track_x1, track_y1, track_x2, track_y2, fill="#0a0f17", outline="#344258", width=1, radius=7)
        max_scroll = self._deck_builder_max_scroll()
        viewport_h = content_bottom - content_top
        content_h = max(viewport_h, self._deck_builder_content_height())
        thumb_h = max(58.0, viewport_h * viewport_h / content_h)
        thumb_travel = max(1.0, viewport_h - thumb_h)
        ratio = 0.0 if max_scroll <= 0 else self.deck_builder_scroll / max_scroll
        thumb_y1 = track_y1 + ratio * thumb_travel
        thumb_y2 = thumb_y1 + thumb_h
        self._rect(track_x1 + 2, thumb_y1, track_x2 - 2, thumb_y2, fill="#60708a", outline="#8797b0", width=1, radius=5)
        if thumb_y1 > track_y1 + 2:
            self._add_click(track_x1 - 5, track_y1, track_x2 + 5, thumb_y1, lambda: self._deck_builder_scroll_by(-viewport_h * 0.82))
        if thumb_y2 < track_y2 - 2:
            self._add_click(track_x1 - 5, thumb_y2, track_x2 + 5, track_y2, lambda: self._deck_builder_scroll_by(viewport_h * 0.82))

        # Deck construit à droite.
        self._rect(1055, 200, 1565, 842, fill="#0e1520", outline="#2d3b50", width=2, radius=20)
        self._text(1085, 228, "TON DECK", size=15, weight="bold", anchor="w", family=DISPLAY_FONT_TOKEN)
        self._button(1392, 212, 1535, 246, "VIDER", self._deck_builder_clear, fill="#171d27", accent="#8a5252", small=True, enabled=bool(deck))

        for slot in range(8):
            y1 = 263 + slot * 62
            y2 = y1 + 51
            if slot < len(deck):
                card = deck[slot]
                self._rect(1080, y1, 1540, y2, fill="#162131", outline="#33445c", width=1, radius=10)
                self._text(1095, (y1 + y2) / 2, f"{slot + 1}.", size=9, fill=MUTED, weight="bold", anchor="w")
                display_name = self._short_name(card.name, 24)
                self._text(1122, (y1 + y2) / 2, display_name, size=10, weight="bold", anchor="w")
                self._text(1390, (y1 + y2) / 2, card.star_label, size=9, fill="#ffd36a", weight="bold")
                self._text(1522, (y1 + y2) / 2, "RETIRER", size=7, fill="#ff9d86", weight="bold", anchor="e")
                self._add_click(1430, y1, 1540, y2, lambda cid=card.id: self._deck_builder_remove(cid))
                self._add_click(1080, y1, 1428, y2, lambda c=card: self._open_card_reader(c))
            else:
                self._rect(1080, y1, 1540, y2, fill="#111823", outline="#273342", width=1, radius=10)
                self._text(1310, (y1 + y2) / 2, f"EMPLACEMENT {slot + 1}", size=8, fill="#5f6b7d", weight="bold")

        legal = self._deck_builder_final_valid(deck)
        if len(deck) == 8 and legal:
            self._rect(1080, 766, 1540, 814, fill="#14271f", outline=GREEN, width=2, radius=10)
            self._text(1310, 790, "DECK COMPLET ET LÉGAL ✓", size=11, fill=GREEN, weight="bold")
        else:
            self._rect(1080, 766, 1540, 814, fill="#131b27", outline="#33445c", width=1, radius=10)
            msg = self.deck_builder_notice or "Construis librement tes synergies — 8 Ninjas maximum."
            msg, msize = self._fit_text_box(msg, 420, 34, start_size=9, min_size=6, weight="bold", max_lines=2)
            self._text(1310, 790, msg, size=msize, fill="#d6dde8" if not self.deck_builder_notice else "#ffd58a", weight="bold", width=420)

        self._text(1515, 865, "by Hakamah Production", size=10, fill="#728095", anchor="e")

    def _play_action_special_audio(self, card_id: str | None) -> bool:
        """Joue le son d'une spéciale déclenchée directement par une action.

        Le Transfert de l'esprit d'Ino est probabiliste : son audio est émis
        par le moteur uniquement quand le Transfert réussit réellement. Cela
        évite de jouer le son sur un échec (50 %) ou sur une cible inciblable.
        """
        if (card_id or "").lower().strip() == "ino":
            return False
        return self.audio.play_special(card_id)

    def show_audio_settings(self):
        self.audio_return_screen = self.current_screen if self.current_screen != "audio_settings" else self.audio_return_screen
        self.current_screen = "audio_settings"
        self.redraw()

    def _return_from_audio(self):
        target = self.audio_return_screen or "menu"
        self.current_screen = target
        self.redraw()

    def _audio_music_down(self):
        self.audio.change_music_volume(-0.10)
        self.redraw()

    def _audio_music_up(self):
        self.audio.change_music_volume(0.10)
        self.redraw()

    def _audio_sfx_down(self):
        self.audio.change_sfx_volume(-0.10)
        self.redraw()

    def _audio_sfx_up(self):
        self.audio.change_sfx_volume(0.10)
        self.redraw()

    def _audio_pause_toggle(self):
        self.audio.pause_music()
        self.redraw()

    def _audio_test_ingame(self):
        self.audio.play_ingame_music(force=True)
        self.redraw()

    def _audio_test_itachi(self):
        self.audio.play_special("itachi")
        self.redraw()

    def _audio_test_madara(self):
        self.audio.play_special("madara")
        self.redraw()

    def _draw_audio_settings(self):
        self._gradient_background("#0b1220", "#04070d")
        self._rect(390, 120, 1210, 780, fill="#0e1622", outline="#33445c", width=2, radius=28)
        self._text(800, 180, "AUDIO", size=34, weight="bold", family=DISPLAY_FONT_TOKEN)

        if not self.audio.available:
            self._rect(470, 235, 1130, 360, fill="#23191b", outline="#8c5555", width=2, radius=16)
            self._text(800, 270, "AUDIO INDISPONIBLE", size=18, fill="#ff9a9a", weight="bold")
            self._text(800, 315, "Le moteur audio natif Windows n'a pas pu demarrer.\nLe jeu reste jouable sans son.", size=11, fill="#d9c1c1")
            self._button(630, 650, 970, 715, "RETOUR", self._return_from_audio, accent=ACCENT)
            return

        self._text(520, 280, "MUSIQUE", size=17, weight="bold", anchor="w")
        self._button(520, 320, 640, 372, "VOL -", self._audio_music_down, fill="#18212e", accent=BLUE, small=True)
        self._rect(665, 320, 820, 372, fill="#151e2b", outline="#33445c", width=1, radius=12)
        self._text(742, 346, f"{self.audio.music_percent}%", size=14, weight="bold")
        self._button(845, 320, 965, 372, "VOL +", self._audio_music_up, fill="#18212e", accent=BLUE, small=True)
        pause_label = "REPRENDRE" if self.audio.music_paused else "PAUSE"
        self._button(990, 320, 1110, 372, pause_label, self._audio_pause_toggle, fill="#202019", accent=GOLD, small=True)

        self._text(520, 445, "EFFETS SONORES", size=17, weight="bold", anchor="w")
        self._button(520, 485, 640, 537, "VOL -", self._audio_sfx_down, fill="#18212e", accent=GREEN, small=True)
        self._rect(665, 485, 820, 537, fill="#151e2b", outline="#33445c", width=1, radius=12)
        self._text(742, 511, f"{self.audio.sfx_percent}%", size=14, weight="bold")
        self._button(845, 485, 965, 537, "VOL +", self._audio_sfx_up, fill="#18212e", accent=GREEN, small=True)
        self._button(990, 485, 1110, 537, "TEST", self.audio.play_normal_attack, fill="#1c2520", accent=GREEN, small=True)

        self._text(520, 575, "TESTS RAPIDES", size=13, weight="bold", anchor="w", fill="#dfe7f2")
        self._button(520, 600, 700, 642, "MUSIQUE COMBAT", self._audio_test_ingame, fill="#18212e", accent=ACCENT, small=True)
        self._button(720, 600, 890, 642, "KATON ITACHI", self._audio_test_itachi, fill="#18212e", accent=RED, small=True)
        self._button(910, 600, 1080, 642, "SUSANOO MADARA", self._audio_test_madara, fill="#18212e", accent=PURPLE, small=True)

        track_names = {"menu": "MENU", "selection": "TAIKO / SELECTION", "ingame": "COMBAT"}
        track = track_names.get(self.audio.current_music, "AUCUNE")
        state = "EN PAUSE" if self.audio.music_paused else ("EN LECTURE" if self.audio.music_is_active() else "ARRETEE")
        self._text(800, 670, f"MUSIQUE {track} — {state}", size=10, fill=MUTED, weight="bold")
        if self.audio.error_message:
            err, err_size = self._fit_text_box(self.audio.error_message, 650, 36, start_size=8, min_size=6, max_lines=2)
            self._text(800, 700, err, size=err_size, fill="#ff9b9b", width=650, justify="center")
        self._button(630, 720, 970, 765, "RETOUR", self._return_from_audio, accent=ACCENT, small=True)

    def _close_app(self):
        try:
            if hasattr(self, "gpu_field_renderer"):
                self.gpu_field_renderer.shutdown()
            if hasattr(self, "network"):
                self.network.close()
            if self.social is not None:
                self.social.stop()
            if hasattr(self, "audio"):
                self.audio.shutdown()
        finally:
            self.root.destroy()

    def _draw_tournament_screen(self):
        self._gradient_background("#0d1420", "#05080e")
        state = self.tournament_state or {}
        members = dict(state.get("members") or {})
        accepted = list(state.get("accepted") or [])
        host_id = str(state.get("host_id") or "")
        is_host = bool(self.identity and host_id == self.identity.account_id)
        self._rect(35, 25, 1565, 105, fill="#0e141e", outline="#6d572c", width=2, radius=14)
        self._text(65, 57, "TOURNOI PRIVÉ", size=27, fill=GOLD, weight="bold", anchor="w", family=DISPLAY_FONT_TOKEN)
        self._text(65, 87, str(state.get("name") or "Tournoi Shinobi"), size=10, fill=MUTED, weight="bold", anchor="w")
        self._button(1365, 42, 1535, 88, "QUITTER", self.show_main_menu, fill="#25191d", accent=RED, small=True)

        self._rect(80, 145, 600, 805, fill="#0f1723", outline="#33445c", width=2, radius=20)
        self._text(115, 185, f"JOUEURS — {len(accepted)}/{len(members)}", size=18, weight="bold", anchor="w")
        y = 235
        for aid, pseudo in list(members.items())[:5]:
            ok = aid in accepted
            active_pair = state.get("current_pair") or {}
            playing = aid in {str(active_pair.get("p1") or ""), str(active_pair.get("p2") or "")}
            label = "EN COMBAT" if playing else ("PRÊT" if ok else "INVITÉ")
            color = GREEN if ok else MUTED
            if playing:
                color = GOLD
            self._rect(110, y, 570, y + 78, fill="#182336" if ok else "#121a25", outline=color if playing else "#2c3c50", width=2 if playing else 1, radius=12)
            self._text(135, y + 27, str(pseudo), size=14, weight="bold", anchor="w")
            self._text(540, y + 27, label, size=9, fill=color, weight="bold", anchor="e")
            profile = {}
            if self.social is not None:
                f = self.social.store.friends.get(aid, {})
                profile = dict(f.get("ranked_profile") or {})
            elo = normalize_elo(profile.get("elo") if "elo" in profile else DEFAULT_ELO)
            self._text(135, y + 55, f"ELO {elo}", size=8, fill=MUTED, anchor="w")
            y += 92

        self._rect(640, 145, 1520, 805, fill="#0f1723", outline="#5f4f2d", width=2, radius=20)
        stage = str(state.get("stage") or "waiting")
        if stage == "waiting":
            self._text(1080, 250, "SALLE D'ATTENTE", size=30, fill=GOLD, weight="bold", family=DISPLAY_FONT_TOKEN)
            if is_host:
                self._text(1080, 325, "Lance quand au moins 2 joueurs ont accepté.", size=14, fill=MUTED)
                self._button(850, 410, 1310, 475, "LANCER LE TOURNOI", self._tournament_launch, fill="#261f18", accent=GOLD, enabled=len(accepted) >= 2)
            else:
                self._text(1080, 340, f"En attente de {state.get('host_pseudo','l’organisateur')}…", size=16, fill=MUTED)
                self._text(1080, 390, "Les combats et le mode spectateur se lanceront automatiquement.", size=12, fill="#b9c4d3")
        elif stage == "running":
            pair = state.get("current_pair") or {}
            p1, p2 = str(pair.get("p1") or ""), str(pair.get("p2") or "")
            self._text(1080, 225, f"ROUND {int(state.get('round') or 1)}", size=22, fill=GOLD, weight="bold")
            if p1 and p2:
                self._text(1080, 320, str(members.get(p1, "Shinobi")).upper(), size=26, weight="bold")
                self._text(1080, 370, "VS", size=22, fill=RED, weight="bold")
                self._text(1080, 420, str(members.get(p2, "Shinobi")).upper(), size=26, weight="bold")
                if self.identity and self.identity.account_id not in {p1, p2}:
                    self._text(1080, 505, "MODE SPECTATEUR", size=17, fill=PURPLE, weight="bold")
                    self._text(1080, 545, "Le combat s'ouvre automatiquement dès que le salon est prêt.", size=11, fill=MUTED)
            else:
                self._text(1080, 360, "PRÉPARATION DU PROCHAIN COMBAT…", size=19, fill=MUTED, weight="bold")
        elif stage == "finished":
            champion = str(state.get("champion") or "")
            self._text(1080, 280, "TOURNOI TERMINÉ", size=30, fill=GOLD, weight="bold", family=DISPLAY_FONT_TOKEN)
            self._text(1080, 380, "CHAMPION", size=17, fill=MUTED, weight="bold")
            self._text(1080, 440, str(members.get(champion, "Shinobi")).upper(), size=36, fill=GREEN, weight="bold", family=DISPLAY_FONT_TOKEN)
        self._text(1080, 735, "Déconnexion pendant son combat = défaite • spectateurs non sanctionnés", size=10, fill="#8997aa")

    def _draw_tournament_invite_overlay(self):
        invite = dict(self.social_tournament_invite_pending or {})
        self._hide_social_entries()
        self._rect(390, 240, 1210, 650, fill="#0b121c", outline=GOLD, width=3, radius=26)
        self._text(800, 300, "INVITATION TOURNOI PRIVÉ", size=26, fill=GOLD, weight="bold", family=DISPLAY_FONT_TOKEN)
        self._text(800, 365, str(invite.get("name") or "Tournoi Shinobi"), size=22, weight="bold")
        members = dict(invite.get("members") or {})
        self._text(800, 420, f"{len(members)} joueurs maximum • les joueurs hors combat regardent en spectateur", size=12, fill=MUTED)
        self._button(520, 525, 780, 590, "ACCEPTER", self._tournament_accept_invite, fill="#17261e", accent=GREEN)
        self._button(820, 525, 1080, 590, "REFUSER", self._tournament_reject_invite, fill="#25191d", accent=RED)

    def show_multiplayer(self):
        if not self._economy_online():
            self.notice = "Multijoueur indisponible : connexion au serveur économie YUGITO requise. Le Solo reste disponible."
            self._economy_refresh_async(force=True); self.current_screen="menu"; self.redraw(); return
        remaining=self._economy_penalty_remaining()
        if remaining>0:
            self.notice=f"Matchmaking suspendu encore {self._format_duration(remaining)} après un abandon/déconnexion."
            self.current_screen="menu"; self.redraw(); return
        self.economy_own_permit=""; self.economy_peer_permit=""; self.economy_peer_account_id=""; self.economy_peer_available_ids=set(); self.economy_peer_verified=False; self.economy_match_id="ym-"+secrets.token_hex(16); self.economy_result_applied=False; self.economy_finish_reason="natural"
        try:
            self.network.close()
        except Exception:
            pass
        self.current_screen = "multiplayer"
        self.current_mode = MULTIPLAYER
        self.multiplayer_scope = None
        self.multiplayer_view = "scope"
        self.multiplayer_rooms = []
        self.multiplayer_selected_room_id = None
        self._last_room_signature = None
        self.network_local_player = None
        self.network_lobby_role = None
        self.network_peer_connected = False
        self.network_status = "Hors ligne"
        self.network_room_code = ""
        self.notice = ""
        self.redraw()

    def _choose_multiplayer_scope(self, scope: str):
        try:
            self.network.close()
        except Exception:
            pass
        scope = "lan" if scope == "lan" else "internet"
        self.multiplayer_scope = scope
        self.network = LanNetworkManager() if scope == "lan" else InternetNetworkManager()
        self._apply_identity_to_network()
        self.network_peer_name = ""
        self.multiplayer_match_type = "classic"
        # Internet possède désormais un vrai choix CLASSIQUE / CLASSÉ.
        self.multiplayer_view = "choice" if scope == "lan" else "internet_mode"
        self.multiplayer_rooms = []
        self.multiplayer_selected_room_id = None
        self._last_room_signature = None
        self.network_local_player = None
        self.network_lobby_role = None
        self.network_peer_connected = False
        self.network_room_code = ""
        self.network_status = "LAN prêt" if scope == "lan" else "Internet prêt"
        self.notice = ""
        self.redraw()

    def _choose_internet_mode(self, mode: str):
        mode = "ranked" if str(mode).lower() == "ranked" else "classic"
        self.multiplayer_match_type = mode
        if mode == "ranked":
            self._start_ranked_matchmaking()
        else:
            self.multiplayer_view = "choice"
            self.notice = ""
            self.redraw()

    def _local_elo(self) -> int:
        return self.ranked.elo if self.ranked is not None else DEFAULT_ELO

    def _start_ranked_matchmaking(self):
        if self.multiplayer_scope != "internet":
            return
        try:
            self.network.close()
        except Exception:
            pass
        self.network = InternetNetworkManager()
        self._apply_identity_to_network()
        self.multiplayer_match_type = "ranked"
        self.multiplayer_view = "ranked_search"
        self.multiplayer_rooms = []
        self.multiplayer_selected_room_id = None
        self._last_room_signature = None
        self.network_local_player = None
        self.network_lobby_role = None
        self.network_peer_connected = False
        self.network_room_code = ""
        self.ranked_peer_elo = DEFAULT_ELO
        self.ranked_result_applied = False
        self.ranked_last_result = None
        self.ranked_search_started = time.monotonic()
        self.network_status = "Recherche d'un adversaire classé…"
        self.notice = f"ELO {self._local_elo()} — recherche de l'ELO le plus proche."
        self.redraw()
        try:
            self.network.start_discovery()
        except Exception as exc:
            self.notice = f"Matchmaking classé indisponible : {exc}"
            self.redraw()
            return
        if self.ranked_search_job is not None:
            try:
                self.root.after_cancel(self.ranked_search_job)
            except Exception:
                pass
        self.ranked_search_job = self.root.after(450, self._ranked_matchmaking_tick)

    def _ranked_matchmaking_tick(self):
        self.ranked_search_job = None
        if self.current_screen != "multiplayer" or self.multiplayer_view != "ranked_search" or self.multiplayer_match_type != "ranked":
            return
        rooms = [r for r in self.network.discovered_rooms() if str(r.get("match_type") or "classic") == "ranked"]
        own = self._local_elo()
        if rooms:
            rooms.sort(key=lambda r: (abs(normalize_elo(r.get("elo")) - own), str(r.get("room_id") or "")))
            room = rooms[0]
            self.ranked_peer_elo = normalize_elo(room.get("elo"))
            rid = str(room.get("room_id") or "")
            if rid:
                try:
                    self.network.join_room(rid)
                    self.network_local_player = 2
                    self.network_lobby_role = "client"
                    self.network_room_code = rid
                    self.network_status = f"Adversaire trouvé — ELO {self.ranked_peer_elo}"
                    self.notice = f"Matchmaking classé : adversaire le plus proche trouvé ({self.ranked_peer_elo} ELO)."
                    self.redraw()
                    return
                except Exception:
                    # Le salon a pu être pris quelques millisecondes avant nous : on continue.
                    pass
        elapsed = time.monotonic() - self.ranked_search_started
        # Petit délai aléatoire : évite que deux joueurs qui cliquent au même instant
        # créent tous les deux un salon au lieu de se rejoindre.
        if elapsed >= 1.4:
            try:
                self.network.close()
                self.network = InternetNetworkManager()
                self._apply_identity_to_network()
                self.network_local_player = 1
                self.network_lobby_role = "host"
                self.network_status = "File classée créée — attente de l'ELO le plus proche…"
                self.notice = f"ELO {own} — ton attente est invisible dans le matchmaking classique."
                self.network.host(room_name="Matchmaking classé YUGITO", match_type="ranked", elo=own)
                self.network_room_code = str(getattr(self.network, "room_id", "") or "")
                self.redraw()
                return
            except Exception as exc:
                self.notice = f"Impossible d'ouvrir la file classée : {exc}"
                self.redraw()
                return
        self.ranked_search_job = self.root.after(450, self._ranked_matchmaking_tick)

    def _send_ranked_hello(self):
        if self.multiplayer_match_type == "ranked" and getattr(self.network, "connected", False):
            self._net_send({"type": "ranked_hello", "elo": self._local_elo()})

    def _start_ranked_duel_if_ready(self):
        if self.multiplayer_match_type != "ranked" or self.network_lobby_role != "host" or not self.network.connected:
            return
        self._send_ranked_hello()
        self._start_multiplayer_standard_host()

    def _open_join_browser(self):
        try:
            self.network.close()
            self.multiplayer_view = "join"
            self.multiplayer_rooms = []
            self.multiplayer_selected_room_id = None
            self._last_room_signature = None
            self.network_status = "Connexion au serveur YUGITO…"
            self.notice = ""
            self.redraw()
            self.network.start_discovery()
            self.network_status = "Recherche automatique des parties en attente…"
        except Exception as exc:
            self.network_status = "Serveur YUGITO indisponible"
            self.notice = f"Impossible de joindre le serveur maître : {exc}"
        self.redraw()

    def _start_network_host(self):
        try:
            self.network.close()
            self.multiplayer_view = "host"
            self.network_local_player = 1
            self.network_lobby_role = "host"
            self.network_peer_connected = False
            self.network_room_code = ""
            self.network_status = "Création du salon LAN…" if self.multiplayer_scope == "lan" else "Création du salon Internet…"
            self.notice = "Démarrage du relais LAN…" if self.multiplayer_scope == "lan" else "Connexion au relais Internet chiffré…"
            self.redraw()
            self.network.host(room_name="Matchmaking YUGITO")
        except Exception as exc:
            self.network_status = "Serveur YUGITO indisponible"
            self.notice = f"Impossible de créer la partie : {exc}"
        self.redraw()

    def _select_discovered_room(self, room_id: str):
        self.multiplayer_selected_room_id = room_id
        self.redraw()

    def _join_selected_room(self):
        room = next((r for r in self.multiplayer_rooms if r.get("room_id") == self.multiplayer_selected_room_id), None)
        if not room:
            self.notice = "Sélectionne d'abord une partie dans la liste."
            self.redraw()
            return
        room_id = str(room.get("room_id", "")).strip()
        if not room_id:
            self.notice = "ID de salon invalide."
            self.redraw()
            return
        self.network_status = f"Connexion à {room.get('name', 'la partie')}…"
        self.notice = "Connexion via le relais — aucune connexion directe entre joueurs."
        self.redraw()
        try:
            self.network.join_room(room_id)
            self.network_local_player = 2
            self.network_lobby_role = "client"
            self.network_room_code = room_id
            # L'événement 'connected' confirme réellement l'association J1/J2.
            self.network_status = "Demande envoyée au serveur YUGITO…"
        except Exception as exc:
            self.network_peer_connected = False
            self.network_status = "Connexion impossible"
            self.notice = f"Connexion impossible : {exc}"
            try:
                self.network.start_discovery()
            except Exception:
                pass
        self.redraw()

    def _leave_network_lobby(self):
        try:
            self.network.close()
        except Exception:
            pass
        self.network_local_player = None
        self.network_lobby_role = None
        self.network_peer_connected = False
        self.network_status = "Hors ligne"
        self.network_room_code = ""
        self.multiplayer_view = "choice"
        if self.social is not None:
            self.social.set_status("online")
        self.show_main_menu()

    def _multiplayer_back(self):
        if self.multiplayer_view == "scope":
            self._leave_network_lobby()
            return
        try:
            self.network.close()
        except Exception:
            pass
        if self.multiplayer_view == "choice":
            if self.multiplayer_scope == "internet":
                self.multiplayer_view = "internet_mode"
            else:
                self.multiplayer_scope = None
                self.multiplayer_view = "scope"
        elif self.multiplayer_view == "internet_mode":
            self.multiplayer_scope = None
            self.multiplayer_view = "scope"
        elif self.multiplayer_view == "ranked_search":
            self.multiplayer_match_type = "classic"
            self.multiplayer_view = "internet_mode"
        else:
            self.multiplayer_view = "choice"
        self.multiplayer_rooms = []
        self.multiplayer_selected_room_id = None
        self.network_local_player = None
        self.network_lobby_role = None
        self.network_peer_connected = False
        self.network_status = "Hors ligne"
        self.notice = ""
        self.redraw()

    def _start_multiplayer_standard_host(self):
        if self.network_lobby_role != "host" or not self.network.connected:
            self.notice = "Il faut attendre qu'un joueur rejoigne la partie."
            self.redraw()
            return
        if not self._economy_multiplayer_ready():
            self.notice = "Validation sécurisée des collections en cours…"
            self._economy_send_hello_async(); self.redraw(); return
        seed = self.random.randint(1, 2_000_000_000)
        self.network_seed = seed
        self.network.send({"type": "start_standard", "seed": seed})
        self._prepare_multiplayer_standard(seed)

    def _prepare_multiplayer_standard(self, seed: int):
        self.current_mode = MULTIPLAYER
        self._duel_started_network = False
        self.economy_result_applied = False
        self.economy_finish_reason = "natural"
        if self.multiplayer_match_type == "ranked":
            self.ranked_result_applied = False
            self.ranked_last_result = None
        if self.social is not None:
            self.social.set_status("in_game")
        self.network_seed = int(seed)
        if hasattr(self, "audio"):
            self.audio.play_selection_music(force=True)
        self._reset_duel_flow_state()
        self.draft_pool = list(self.cards)
        self.draft_owner = {card.id: None for card in self.draft_pool}
        self.draft_decks = {1: [], 2: []}
        self.draft_preview_card = self.draft_pool[0] if self.draft_pool else None
        self.draft_page = 0
        self.draft_scroll = 0.0
        self.starter_choices = {1: [], 2: []}
        self.lineup_active_player = 1
        self.lineup_revealed = False
        self.lineup_preview_card = None
        self._begin_rps("draft")
        self.notice = f"Multiplayer connecté — tu es J{self.network_local_player}."
        self.redraw()

    def _draw_multiplayer_placeholder(self):
        self.canvas.delete("all")
        self.click_regions.clear()
        w = self.canvas.winfo_width()
        h = self.canvas.winfo_height()
        tr, tg, tb = self._hex("#0c1421")
        br, bg, bb = self._hex("#05080e")
        bands = 32
        band_h = max(1, h / bands)
        for i in range(bands):
            t = i / max(1, bands - 1)
            color = self._rgb(int(tr + (br-tr)*t), int(tg + (bg-tg)*t), int(tb + (bb-tb)*t))
            self.canvas.create_rectangle(0, i*band_h, w+1, (i+1)*band_h+1, fill=color, outline="")

        self._rect(28, 22, 1572, 82, fill="#0e141e", outline="#2a3547", width=1, radius=14)
        self._text(55, 52, "YUGITO", size=24, weight="bold", anchor="w", family=DISPLAY_FONT_TOKEN)
        scope_label = "INTERNET" if self.multiplayer_scope == "internet" else ("LAN" if self.multiplayer_scope == "lan" else "CHOIX DU RÉSEAU")
        self._text(205, 52, f"MULTIPLAYER — {scope_label} — DUEL STANDARD", size=14, fill=MUTED, weight="bold", anchor="w")
        self._rect(1070, 33, 1392, 70, fill="#101b28", outline="#294057", width=1, radius=10)
        privacy_label = "CONNEXION : RELAIS TLS" if self.multiplayer_scope == "internet" else ("LAN LOCAL" if self.multiplayer_scope == "lan" else "DUEL STANDARD")
        self._text(1231, 51, privacy_label, size=10, fill=GREEN, weight="bold")
        self._button(1415, 32, 1540, 72, "MENU", self._leave_network_lobby, fill="#151d29", accent="#7b5860", small=True)

        if self.multiplayer_view == "join":
            self._draw_multiplayer_join_browser()
        elif self.multiplayer_view == "internet_mode":
            self._draw_multiplayer_internet_mode()
        elif self.multiplayer_view == "ranked_search":
            self._draw_ranked_matchmaking()
        elif self.multiplayer_view == "private_client":
            self._draw_multiplayer_private_client()
        elif self.multiplayer_view == "tournament_spectator":
            self._draw_tournament_spectator_waiting()
        elif self.multiplayer_view == "host":
            self._draw_multiplayer_host_waiting()
        elif self.multiplayer_view == "choice":
            self._draw_multiplayer_choice()
        else:
            self._draw_multiplayer_scope()

    def _draw_multiplayer_scope(self):
        self._text(800, 145, "MULTIPLAYER", size=42, weight="bold", family=DISPLAY_FONT_TOKEN)
        self._text(800, 195, "CHOISIS COMMENT TU VEUX JOUER", size=16, fill=MUTED, weight="bold")

        self._rect(245, 285, 760, 650, fill="#121c2b", outline="#304158", width=2, radius=24)
        self._text(502, 345, "INTERNET", size=34, weight="bold", family=DISPLAY_FONT_TOKEN)
        self._text(502, 400, "PARTIES PUBLIQUES", size=22, weight="bold")
        self._text(502, 462, "Trouve des parties même chez des joueurs\nsitués sur une autre box ou dans un autre pays.", size=15, fill=MUTED, justify="center")
        self._text(502, 530, "Les deux joueurs passent par un relais Internet chiffré.\nAucune connexion directe entre les deux PC.", size=13, fill="#b8c5d7", justify="center")
        self._button(325, 575, 680, 625, "JOUER SUR INTERNET", lambda: self._choose_multiplayer_scope("internet"), fill="#172339", accent=BLUE)

        self._rect(840, 285, 1355, 650, fill="#121c2b", outline="#304158", width=2, radius=24)
        self._text(1097, 345, "LAN", size=34, weight="bold", family=DISPLAY_FONT_TOKEN)
        self._text(1097, 400, "RÉSEAU LOCAL", size=22, weight="bold")
        self._text(1097, 462, "Pour jouer facilement à la maison :\nles PC doivent être sur le même Wi-Fi / réseau.", size=15, fill=MUTED, justify="center")
        self._text(1097, 530, "Découverte automatique du salon\nsans adresse réseau à saisir.", size=13, fill="#b8c5d7", justify="center")
        self._button(920, 575, 1275, 625, "JOUER EN LAN", lambda: self._choose_multiplayer_scope("lan"), fill="#261f18", accent=ACCENT)

        self._rect(360, 700, 1240, 775, fill="#0f1824", outline="#2c3d52", width=1, radius=14)
        self._text(800, 726, "INTERNET = RELAIS PUBLIC   •   LAN = CONNEXION MAISON", size=12, fill=GREEN, weight="bold")
        self._text(800, 752, "Le duel standard et ses règles restent exactement les mêmes dans les deux modes.", size=11, fill="#b8c5d7")

    def _draw_multiplayer_internet_mode(self):
        self._text(800, 145, "MULTIPLAYER INTERNET", size=40, weight="bold", family=DISPLAY_FONT_TOKEN)
        self._text(800, 195, "CHOISIS TON TYPE DE MATCHMAKING", size=16, fill=MUTED, weight="bold")

        self._rect(245, 285, 760, 650, fill="#121c2b", outline="#304158", width=2, radius=24)
        self._text(502, 345, "MATCHMAKING", size=24, fill=BLUE, weight="bold", family=DISPLAY_FONT_TOKEN)
        self._text(502, 390, "CLASSIQUE", size=31, weight="bold", family=DISPLAY_FONT_TOKEN)
        self._text(502, 465, "Parties publiques sans classement.\nRejoins un salon ou crée le tien.", size=15, fill=MUTED, justify="center")
        self._button(325, 565, 680, 625, "MATCHMAKING CLASSIQUE", lambda: self._choose_internet_mode("classic"), fill="#172339", accent=BLUE)

        self._rect(840, 285, 1355, 650, fill="#121c2b", outline=GOLD, width=2, radius=24)
        self._text(1097, 345, "MATCHMAKING", size=24, fill=GOLD, weight="bold", family=DISPLAY_FONT_TOKEN)
        self._text(1097, 390, "CLASSÉ", size=31, weight="bold", family=DISPLAY_FONT_TOKEN)
        self._text(1097, 455, f"ELO ACTUEL : {self._local_elo()}", size=18, fill="#f3d782", weight="bold")
        self._text(1097, 500, "Recherche automatique de l'adversaire\ndont l'ELO est le plus proche du tien.", size=14, fill=MUTED, justify="center")
        self._button(920, 565, 1275, 625, "LANCER LE CLASSÉ", lambda: self._choose_internet_mode("ranked"), fill="#261f18", accent=GOLD)

        self._button(650, 735, 950, 790, "RETOUR", self._multiplayer_back, fill="#151d29", accent="#65738b", small=True)

    def _draw_ranked_matchmaking(self):
        self._text(800, 145, "MATCHMAKING CLASSÉ", size=40, weight="bold", family=DISPLAY_FONT_TOKEN)
        self._text(800, 198, "RECHERCHE AUTOMATIQUE — ELO LE PLUS PROCHE", size=15, fill=GOLD, weight="bold")
        self._rect(340, 275, 1260, 650, fill="#101824", outline="#7f6530", width=2, radius=28)
        self._text(800, 345, f"TON ELO : {self._local_elo()}", size=28, fill="#f2d27a", weight="bold", family=DISPLAY_FONT_TOKEN)
        if self.network.connected:
            self._text(800, 420, f"ADVERSAIRE TROUVÉ : {self.network_peer_name or 'Shinobi'}", size=22, fill=GREEN, weight="bold")
            self._text(800, 465, f"ELO ADVERSE : {normalize_elo(self.ranked_peer_elo)}", size=18, fill="#d8e1ed", weight="bold")
            self._text(800, 520, "Le duel va démarrer automatiquement…", size=15, fill=MUTED)
        elif self.network_lobby_role == "host":
            self._text(800, 420, "EN ATTENTE D'UN ADVERSAIRE…", size=22, fill=GOLD, weight="bold")
            self._text(800, 470, "Ta file est cachée du matchmaking classique.", size=14, fill=MUTED)
        else:
            dots = "." * (1 + int((time.monotonic() - self.ranked_search_started) * 2) % 3)
            self._text(800, 420, "RECHERCHE" + dots, size=24, fill=GOLD, weight="bold")
            self._text(800, 470, "YUGITO compare les files disponibles et prend l'ELO le plus proche.", size=14, fill=MUTED)
        if self.notice:
            self._text(800, 585, self.notice, size=11, fill="#dce5f0", weight="bold")
        self._button(610, 715, 990, 775, "ANNULER LE MATCHMAKING", self._multiplayer_back, fill="#25191d", accent=RED, small=True)

    def _draw_multiplayer_choice(self):
        title = "MATCHMAKING CLASSIQUE" if self.multiplayer_scope == "internet" else "MULTIPLAYER LAN"
        self._text(800, 145, title, size=42, weight="bold", family=DISPLAY_FONT_TOKEN)
        backend_desc = "INTERNET PUBLIC — RELAIS TLS PERSISTANT" if self.multiplayer_scope == "internet" else "RÉSEAU LOCAL — DÉCOUVERTE AUTOMATIQUE"
        self._text(800, 195, f"DUEL STANDARD 1 CONTRE 1 — {backend_desc}", size=16, fill=MUTED, weight="bold")

        self._rect(245, 285, 760, 625, fill="#121c2b", outline="#304158", width=2, radius=24)
        self._text(502, 350, "REJOINDRE", size=34, weight="bold", family=DISPLAY_FONT_TOKEN)
        self._text(502, 405, "UNE PARTIE", size=25, weight="bold")
        self._text(502, 465, "Affiche les salons publics actuellement\nen attente d'un deuxième joueur.", size=15, fill=MUTED, justify="center")
        self._button(325, 535, 680, 595, "REJOINDRE UNE PARTIE", self._open_join_browser, fill="#172339", accent=BLUE)

        self._rect(840, 285, 1355, 625, fill="#121c2b", outline="#304158", width=2, radius=24)
        self._text(1097, 350, "CRÉER", size=34, weight="bold", family=DISPLAY_FONT_TOKEN)
        self._text(1097, 405, "UNE PARTIE", size=25, weight="bold")
        create_desc = ("Crée une partie publique visible depuis Internet.\nLes échanges passent par une connexion persistante." if self.multiplayer_scope == "internet" else "Crée une partie visible par les PC de ton réseau local.\nLe relais LAN démarre automatiquement.")
        self._text(1097, 465, create_desc, size=15, fill=MUTED, justify="center")
        self._button(920, 535, 1275, 595, "CRÉER UNE PARTIE", self._start_network_host, fill="#261f18", accent=ACCENT)

        self._rect(360, 680, 1240, 755, fill="#0f1824", outline="#2c3d52", width=1, radius=14)
        self._text(800, 705, "CONFIDENTIALITÉ RÉSEAU", size=13, fill=GREEN, weight="bold")
        privacy = ("Les deux joueurs communiquent uniquement via le relais • aucune connexion directe entre joueurs" if self.multiplayer_scope == "internet" else "Mode LAN : découverte locale automatique • aucune adresse réseau à saisir")
        self._text(800, 733, privacy, size=11, fill="#b8c5d7")
        if self.notice:
            self._text(800, 810, self.notice, size=11, fill="#dce5f0", weight="bold")

    def _draw_multiplayer_join_browser(self):
        self._text(105, 140, "REJOINDRE UNE PARTIE", size=32, weight="bold", anchor="w", family=DISPLAY_FONT_TOKEN)
        join_info = ("Liste mondiale fournie par le relais Internet persistant." if self.multiplayer_scope == "internet" else "Liste des parties détectées automatiquement sur ton réseau local.")
        self._text(105, 182, join_info, size=13, fill=MUTED, anchor="w")
        self._button(1260, 130, 1485, 180, "RETOUR", self._multiplayer_back, accent="#65738b", small=True)

        self._rect(95, 225, 1505, 720, fill="#0f1723", outline="#33445c", width=2, radius=22)
        self._text(125, 260, "PARTIES PUBLIQUES EN ATTENTE", size=20, weight="bold", anchor="w")
        self._text(1450, 260, f"{len(self.multiplayer_rooms)} trouvée(s)", size=12, fill=MUTED, anchor="e")

        if not self.multiplayer_rooms:
            self._text(800, 440, "Aucune partie publique en attente pour le moment.", size=18, fill="#c7d1df")
            empty_sub = ("La liste Internet se met à jour automatiquement en temps réel." if self.multiplayer_scope == "internet" else "La liste LAN se met à jour automatiquement dès qu'un hôte est détecté.")
            self._text(800, 480, empty_sub, size=13, fill=MUTED)
            if self.notice:
                fitted, fsize = self._fit_text_box(self.notice, 1100, 54, start_size=11, min_size=8, max_lines=2)
                self._text(800, 545, fitted, size=fsize, fill="#e0b2b2", width=1100, justify="center")
        else:
            y = 300
            for room in self.multiplayer_rooms[:5]:
                rid = str(room.get("room_id", ""))
                selected = rid == self.multiplayer_selected_room_id
                self._rect(125, y, 1475, y+72, fill="#192538" if selected else "#131d2b", outline=BLUE if selected else "#2d3b50", width=2 if selected else 1, radius=14)
                self._text(155, y+24, "MATCHMAKING CLASSIQUE", size=18, weight="bold", anchor="w")
                self._text(155, y+50, f"Adversaire anonyme   •   Duel standard   •   File {rid[-6:]}", size=11, fill=MUTED, anchor="w")
                self._text(1435, y+36, "1 / 2 — EN ATTENTE", size=11, fill=GREEN, weight="bold", anchor="e")
                self._add_click(125, y, 1475, y+72, lambda room_id=rid: self._select_discovered_room(room_id))
                y += 84

        enabled = bool(self.multiplayer_selected_room_id and self.multiplayer_rooms and not self.network.connected)
        self._button(515, 755, 1085, 815, "REJOINDRE LA PARTIE SÉLECTIONNÉE", self._join_selected_room, fill="#172339", accent=BLUE, enabled=enabled)
        if self.network_lobby_role == "client" and self.network.connected:
            self._text(800, 850, f"✓ Connecté à {self.network_peer_name or 'l’hôte'} via le relais. Attente du lancement du duel.", size=11, fill=GREEN, weight="bold")
        elif self.notice:
            fitted, fsize = self._fit_text_box(self.notice, 1250, 28, start_size=10, min_size=8, max_lines=1)
            self._text(800, 850, fitted, size=fsize, fill="#dce5f0")

    def _draw_tournament_spectator_waiting(self):
        self._text(800, 150, "TOURNOI PRIVÉ", size=38, fill=GOLD, weight="bold", family=DISPLAY_FONT_TOKEN)
        self._text(800, 205, "MODE SPECTATEUR", size=20, fill=PURPLE, weight="bold")
        self._rect(330, 270, 1270, 650, fill="#101a28", outline="#5b466d", width=2, radius=26)
        self._text(800, 350, "CONNECTÉ AU COMBAT", size=24, weight="bold")
        self._text(800, 410, "Tu ne peux effectuer aucune action.", size=14, fill=MUTED)
        self._text(800, 455, "Le Shifumi, le draft puis le duel apparaîtront automatiquement.", size=13, fill="#c6d0df")
        self._text(800, 525, "Une déconnexion spectateur n'entraîne aucune défaite.", size=12, fill=GREEN, weight="bold")

    def _draw_multiplayer_private_client(self):
        self._text(800, 150, "PARTIE PRIVÉE", size=38, weight="bold", family=DISPLAY_FONT_TOKEN)
        self._text(800, 198, "INVITATION D'UN AMI — DUEL STANDARD", size=15, fill=MUTED, weight="bold")
        self._rect(330, 270, 1270, 650, fill="#101a28", outline="#33465f", width=2, radius=26)
        self._text(800, 335, "CONNEXION PRIVÉE", size=24, weight="bold")
        self._text(800, 390, f"Hôte : {self.network_peer_name or getattr(self.network, 'peer_display_name', '') or 'ton ami'}", size=16, fill="#dbe4ef", weight="bold")
        self._text(800, 438, f"Salon : {self.network_room_code or 'connexion…'}", size=12, fill=MUTED)
        if self.network.connected:
            self._text(800, 510, "✓ CONNECTÉ — ATTENTE DU LANCEMENT PAR L'HÔTE", size=14, fill=GREEN, weight="bold")
            self._text(800, 555, "Tu n'as rien d'autre à faire : le duel démarrera automatiquement.", size=11, fill=MUTED)
            self._button(590, 700, 1010, 755, "QUITTER LA PARTIE PRIVÉE", self._multiplayer_back, fill="#25191d", accent=RED, small=True)
        else:
            self._text(800, 510, self.network_status or "Connexion en cours…", size=14, fill=GOLD, weight="bold")
            self._button(590, 700, 1010, 755, "ANNULER", self._multiplayer_back, fill="#25191d", accent=RED, small=True)
        if self.notice:
            fitted, fsize = self._fit_text_box(self.notice, 1050, 36, start_size=10, min_size=8, max_lines=2)
            self._text(800, 815, fitted, size=fsize, fill="#dce5f0", width=1050, justify="center")

    def _draw_multiplayer_host_waiting(self):
        is_private = bool(getattr(self.network, "_private_room", False))
        host_title = "PARTIE PRIVÉE CRÉÉE" if is_private else ("PARTIE INTERNET CRÉÉE" if self.multiplayer_scope == "internet" else "PARTIE LAN CRÉÉE")
        self._text(800, 145, host_title, size=36, weight="bold", family=DISPLAY_FONT_TOKEN)
        host_sub = "DUEL STANDARD — RELAIS INTERNET PERSISTANT" if self.multiplayer_scope == "internet" else "DUEL STANDARD — RÉSEAU LOCAL"
        self._text(800, 195, host_sub, size=15, fill=MUTED, weight="bold")

        self._rect(310, 250, 1290, 655, fill="#101a28", outline="#33465f", width=2, radius=26)
        self._text(800, 310, "SALON EN ATTENTE", size=25, weight="bold")
        host_line = ("Salon invisible au public — seul ton ami invité peut le rejoindre." if is_private else ("Ta partie est publiée dans la liste Internet." if self.multiplayer_scope == "internet" else "Ta partie est annoncée sur ton réseau local."))
        self._text(800, 355, host_line, size=15, fill="#dbe4ef")
        host_priv = ("Invitation directe via le réseau YUGITO. Le salon n'apparaît pas dans les parties publiques." if is_private else ("Le futur adversaire voit le salon via le relais, sans connexion directe à ton PC." if self.multiplayer_scope == "internet" else "Le futur adversaire voit le salon automatiquement s’il est sur le même LAN."))
        self._text(800, 390, host_priv, size=13, fill=MUTED)

        self._rect(450, 445, 1150, 555, fill="#0c1520", outline="#405673", width=1, radius=14)
        self._text(800, 480, "ID DU SALON", size=11, fill=MUTED, weight="bold")
        self._text(800, 520, self.network_room_code or "création…", size=23, fill="#dce4f1", weight="bold", family=DISPLAY_FONT_TOKEN)

        status_color = GREEN if self.network.connected else GOLD
        self._text(800, 595, self.network_status, size=14, fill=status_color, weight="bold")

        if self.network.connected:
            self._text(800, 635, f"✓ {(self.network_peer_name or 'ADVERSAIRE').upper()} CONNECTÉ VIA LE RELAIS", size=14, fill=GREEN, weight="bold")
            self._button(550, 700, 1050, 765, "LANCER LE DUEL STANDARD", self._start_multiplayer_standard_host, fill="#18261f", accent=GREEN)
        else:
            self._button(550, 700, 1050, 765, "ANNULER LA PARTIE", self._multiplayer_back, fill="#25191d", accent="#8a5252")

        if self.notice:
            fitted, fsize = self._fit_text_box(self.notice, 1200, 32, start_size=10, min_size=8, max_lines=1)
            self._text(800, 825, fitted, size=fsize, fill="#dce5f0")

    # ------------------------------------------------------------------
    # New-game flow: Shifumi -> draft -> 3 starters -> Shifumi -> duel
    # ------------------------------------------------------------------
    def start_duel(self, mode: GameMode):
        self.current_mode = mode
        if self.social is not None:
            self.social.set_status("in_game")
        if hasattr(self, "audio"):
            self.audio.play_selection_music(force=True)
        self._reset_duel_flow_state()

        # V4 : toutes les cartes disponibles participent au draft. Chaque joueur
        # n'en garde toujours que 8 pour son deck.
        self.draft_pool = list(self.cards)
        self.draft_owner = {card.id: None for card in self.draft_pool}
        self.draft_decks = {1: [], 2: []}
        self.draft_preview_card = self.draft_pool[0] if self.draft_pool else None
        self.draft_page = 0
        self.draft_scroll = 0.0

        self.starter_choices = {1: [], 2: []}
        self.lineup_active_player = 1
        self.lineup_revealed = False
        self.lineup_preview_card = None

        self._begin_rps("draft")

    def _reset_duel_flow_state(self):
        self.engine = None
        self.ai_busy = False
        self.result_audio_winner = None
        self.selected_hand_index = None
        self.selected_attacker_slot = None
        self.selected_style = None
        self.selected_special_mode = None
        self.inspected_enemy_slot = None
        self.replacement_resume_ai = False

    def _begin_rps(self, context: str):
        self.current_screen = "rps"
        if hasattr(self, "audio"):
            self.audio.play_selection_music()
        self.rps_context = context
        self.rps_choices = {}
        self.rps_waiting_player = 1
        self.rps_winner = None
        self.rps_tie = False
        self.notice = ""
        self.redraw()

    def choose_rps(self, choice: str, *, from_network: bool = False, forced_player: int | None = None):
        if self.current_screen != "rps" or self.rps_winner is not None or self.rps_tie:
            return
        player = self.rps_waiting_player if forced_player is None else int(forced_player)
        if not from_network and self._controller(player) != "human":
            return
        if choice not in RPS_BEATS:
            return
        if player != self.rps_waiting_player:
            return

        self.rps_choices[player] = choice
        if self.current_mode and self.current_mode.id == "multiplayer" and not from_network:
            self._net_send({"type": "rps_choice", "player": player, "choice": choice})

        if player == 1:
            if self._controller(2) == "ai":
                self.rps_choices[2] = self.random.choice(list(RPS_BEATS))
                self._resolve_rps()
            else:
                self.rps_waiting_player = 2
                self.notice = f"Choix de {self._player_display_name(1)} enregistré. {self._player_display_name(2)} choisit maintenant."
                self.redraw()
        else:
            self._resolve_rps()

    def _resolve_rps(self):
        c1 = self.rps_choices.get(1)
        c2 = self.rps_choices.get(2)
        if not c1 or not c2:
            return
        if c1 == c2:
            self.rps_tie = True
            self.rps_winner = None
        elif RPS_BEATS[c1] == c2:
            self.rps_winner = 1
        else:
            self.rps_winner = 2
        self.redraw()

    def _restart_rps(self, *, from_network: bool = False):
        if self.current_mode and self.current_mode.id == "multiplayer" and not from_network:
            if self.network_lobby_role != "host":
                self.notice = "Seul l'hôte relance le Shifumi."
                self.redraw()
                return
            self._net_send({"type": "rps_restart", "context": self.rps_context})
        if self.rps_context:
            self._begin_rps(self.rps_context)

    def _continue_after_rps(self, *, from_network: bool = False):
        if self.rps_winner not in (1, 2):
            return
        if self.current_mode and self.current_mode.id == "multiplayer" and not from_network:
            if self.network_lobby_role != "host":
                self.notice = "L'hôte valide la suite de la partie."
                self.redraw()
                return
            self._net_send({"type": "rps_continue"})
        if self.rps_context == "draft":
            self.draft_first_picker = self.rps_winner
            self.draft_active_player = int(self._draft_scheduled_player(0) or self.rps_winner)
            self.current_screen = "draft"
            self.notice = f"{self._player_display_name(self.draft_active_player)} ouvre le draft (T1 • 3★ max)."
            self.redraw()
            self._maybe_schedule_ai_draft()
        elif self.rps_context == "start":
            self.starting_player = self.rps_winner
            self._launch_engine()

    def _draw_rps(self):
        self._gradient_background("#141b27", "#070a10")
        context_title = "QUI CHOISIT LA PREMIÈRE CARTE ?" if self.rps_context == "draft" else "QUI COMMENCE LA PARTIE ?"
        context_sub = (
            "Le gagnant fera le premier choix du draft."
            if self.rps_context == "draft"
            else "Les 3 Ninjas sont déjà choisis. Le gagnant jouera le premier tour."
        )

        self._text(800, 95, "SHIFUMI", size=42, weight="bold", family=DISPLAY_FONT_TOKEN)
        self._text(800, 150, context_title, size=19, fill=ACCENT, weight="bold")
        self._text(800, 183, context_sub, size=12, fill=MUTED)

        self._rect(275, 230, 1325, 720, fill="#101722", outline="#2f3d52", width=2, radius=26)

        if self.rps_tie or self.rps_winner is not None:
            c1 = self.rps_choices.get(1, "?")
            c2 = self.rps_choices.get(2, "?")
            self._rps_result_card(420, 315, 690, 525, 1, c1, BLUE)
            self._rps_result_card(910, 315, 1180, 525, 2, c2, RED)
            self._text(800, 420, "VS", size=28, weight="bold", fill="#7c889b")
            if self.rps_tie:
                self._text(800, 575, "ÉGALITÉ", size=30, fill=GOLD, weight="bold")
                self._button(620, 625, 980, 685, "REJOUER LE SHIFUMI", self._restart_rps, fill="#1b2533", accent=GOLD)
            else:
                self._text(800, 565, f"JOUEUR {self.rps_winner} GAGNE", size=30, fill=GREEN, weight="bold")
                label = "PASSER AU DRAFT" if self.rps_context == "draft" else "COMMENCER LE DUEL"
                self._button(620, 625, 980, 685, label, self._continue_after_rps, fill="#18261f", accent=GREEN)
        else:
            player = self.rps_waiting_player
            accent = BLUE if player == 1 else RED
            self._text(800, 275, f"JOUEUR {player} — À TOI DE CHOISIR", size=18, fill=accent, weight="bold")
            if self.notice:
                self._text(800, 305, self.notice, size=10, fill=MUTED)

            options = [
                ("pierre", 365, "PIERRE"),
                ("feuille", 675, "FEUILLE"),
                ("ciseaux", 985, "CISEAUX"),
            ]
            for key, x, label in options:
                self._rect(x, 350, x + 250, 565, fill="#192231", outline=accent, width=2, radius=22)
                self._draw_rps_symbol(key, x + 125, 430, accent, scale=1.15)
                self._text(x + 125, 510, label, size=18, weight="bold")
                self._add_click(x, 350, x + 250, 565, lambda ch=key: self.choose_rps(ch))

            if player == 2 and self._controller(2) == "human":
                self._text(800, 625, f"Le choix de {self._player_display_name(1)} reste caché jusqu’au résultat.", size=11, fill="#8794a8")

        state = "FENÊTRE" if self.is_fullscreen else "PLEIN ÉCRAN"
        self._button(55, 815, 235, 865, state, self._toggle_fullscreen, fill="#151d29", accent="#5f6d82", small=True)
        self._button(1365, 815, 1545, 865, "MENU", self.show_main_menu, fill="#151d29", accent="#7b5860", small=True)

    def _draw_rps_symbol(self, choice: str, cx: float, cy: float, accent: str, *, scale: float = 1.0):
        if choice == "pierre":
            r = 27 * scale
            self.canvas.create_oval(*self.R(cx - r, cy - r, cx + r, cy + r), fill=accent, outline="#dce7f7", width=max(1, int(self._scale()[0] * 2)))
        elif choice == "feuille":
            w, h = 54 * scale, 38 * scale
            self._rect(cx - w / 2, cy - h / 2, cx + w / 2, cy + h / 2, fill=accent, outline="#dce7f7", width=2, radius=7)
            self.canvas.create_line(*self.R(cx - w * 0.34, cy, cx + w * 0.34, cy), fill="#dce7f7", width=max(1, int(self._scale()[0] * 2)))
            self.canvas.create_line(*self.R(cx, cy - h * 0.32, cx, cy + h * 0.32), fill="#dce7f7", width=max(1, int(self._scale()[0] * 2)))
        elif choice == "ciseaux":
            r = 12 * scale
            self.canvas.create_oval(*self.R(cx - 28 * scale - r, cy + 15 * scale - r, cx - 28 * scale + r, cy + 15 * scale + r), outline=accent, width=max(2, int(self._scale()[0] * 4)))
            self.canvas.create_oval(*self.R(cx + 28 * scale - r, cy + 15 * scale - r, cx + 28 * scale + r, cy + 15 * scale + r), outline=accent, width=max(2, int(self._scale()[0] * 4)))
            self.canvas.create_line(*self.R(cx - 18 * scale, cy + 6 * scale, cx + 40 * scale, cy - 34 * scale), fill=accent, width=max(2, int(self._scale()[0] * 5)))
            self.canvas.create_line(*self.R(cx + 18 * scale, cy + 6 * scale, cx - 40 * scale, cy - 34 * scale), fill=accent, width=max(2, int(self._scale()[0] * 5)))
        else:
            self._text(cx, cy, "?", size=32, fill=accent, weight="bold")

    def _rps_result_card(self, x1, y1, x2, y2, player, choice, accent):
        self._rect(x1, y1, x2, y2, fill="#18212f", outline=accent, width=3, radius=20)
        self._text((x1 + x2) / 2, y1 + 42, self._player_display_name(player).upper(), size=14, fill=accent, weight="bold")
        self._draw_rps_symbol(choice, (x1 + x2) / 2, y1 + 110, accent, scale=1.0)
        self._text((x1 + x2) / 2, y1 + 170, RPS_LABEL.get(choice, "?"), size=18, weight="bold")

    # ------------------------------------------------------------------
    # Draft panel
    # ------------------------------------------------------------------
    def _draw_draft(self):
        self._gradient_background("#101824", "#06090f")
        self._text(55, 46, "SÉLECTION DU DECK", size=28, weight="bold", anchor="w", family=DISPLAY_FONT_TOKEN)
        self._text(55, 82, f"{len(self.draft_pool)} cartes disponibles • 8 cartes par joueur • draft progressif", size=11, fill=MUTED, anchor="w")
        self._text(790, 50, f"TOUR DE SÉLECTION T{self._draft_round()} : J{self.draft_active_player} • JUSQU'À {str(self._draft_star_cap(self.draft_active_player)).replace('.0','').replace('.5',',5')}★ DÉBLOQUÉES", size=16, fill=BLUE if self.draft_active_player == 1 else RED, weight="bold")

        state = "FENÊTRE" if self.is_fullscreen else "PLEIN ÉCRAN"
        self._button(1260, 28, 1405, 73, state, self._toggle_fullscreen, fill="#151d29", accent="#5f6d82", small=True)
        self._button(1418, 28, 1544, 73, "MENU", self.show_main_menu, fill="#151d29", accent="#7b5860", small=True)

        # Catalogue : une seule longue page verticale.
        panel_x1, panel_x2 = 42, 825
        self._rect(panel_x1, 105, panel_x2, 865, fill="#111a26", outline="#324158", width=2, radius=20)

        content_top = DRAFT_VIEW_TOP
        content_bottom = DRAFT_VIEW_BOTTOM
        # YUGITO 06 : même ordre que le mobile, 3★ en haut puis 3,5★ / 4★ / 4,5★ / 5★.
        draft_cards = sorted(self.draft_pool, key=lambda c: (float(c.stars), c.name.lower()))
        for idx, card in enumerate(draft_cards):
            row, col = divmod(idx, DRAFT_COLS)
            x1 = DRAFT_START_X + col * (DRAFT_CARD_W + DRAFT_GAP_X)
            y1 = content_top + row * (DRAFT_CARD_H + DRAFT_GAP_Y) - self.draft_scroll
            y2 = y1 + DRAFT_CARD_H
            if y2 < content_top - 5 or y1 > content_bottom + 5:
                continue
            owner = self.draft_owner.get(card.id)
            selected = self.draft_preview_card is not None and self.draft_preview_card.id == card.id
            self._draw_card(card, x1, y1, "draft", selected=selected, owner=owner)
            if owner is None and not self._draft_card_allowed(self.draft_active_player, card):
                # Toute carte actuellement imprenable est grisée : palier, quota
                # d'étoiles ou plafond total de 32,5★. Les cartes déjà prises
                # gardent leur marquage J1/J2, comme sur mobile.
                self._stipple_rect(x1 + 3, y1 + 3, x1 + DRAFT_CARD_W - 3, y1 + DRAFT_CARD_H - 3, fill="#05080d", stipple="gray50", outline="#6f737c", width=2)
                cap = self._draft_star_cap(self.draft_active_player)
                if card.stars > cap + 0.01:
                    lock_label = "PALIER VERROUILLÉ"
                elif self._draft_total_stars(self.draft_active_player) + float(card.stars) > MAX_TOTAL_STAR_VALUE + 0.001:
                    lock_label = "TOTAL 32,5★ MAX"
                else:
                    lock_label = "QUOTA ATTEINT"
                self._rect(x1 + 32, y1 + 116, x1 + DRAFT_CARD_W - 32, y1 + 158, fill="#15171b", outline="#7d838d", width=2, radius=8)
                self._text(x1 + DRAFT_CARD_W / 2, y1 + 137, lock_label, size=7, fill="#c8cbd1", weight="bold")
            # La zone cliquable est elle aussi limitée à la partie visible.
            hit_y1 = max(y1, content_top)
            hit_y2 = min(y2, content_bottom)
            if hit_y2 > hit_y1:
                self._add_click(x1, hit_y1, x1 + DRAFT_CARD_W, hit_y2, lambda c=card: self._select_draft_preview(c))

        # Masques de clipping : les cartes passent visuellement sous l'en-tête et
        # sous le bas du panneau, sans jamais déborder sur le titre ou le reste
        # de l'écran. On redessine ensuite les éléments qui doivent rester au-dessus.
        self._rect(panel_x1, 0, panel_x2, 104, fill="#101824", outline="")
        self._rect(panel_x1 + 2, 105, panel_x2 - 2, content_top - 1, fill="#111a26", outline="")
        self._rect(panel_x1 + 2, content_bottom + 1, panel_x2 - 2, 865, fill="#111a26", outline="")
        self._rect(panel_x1, 866, panel_x2, 900, fill="#06090f", outline="")
        self._rect(panel_x1, 105, panel_x2, 865, fill="", outline="#324158", width=2, radius=20)

        # Le masque supérieur recouvre cette partie du header global : on la
        # redessine volontairement au premier plan.
        self._text(55, 46, "SÉLECTION DU DECK", size=28, weight="bold", anchor="w", family=DISPLAY_FONT_TOKEN)
        self._text(55, 82, f"{len(self.draft_pool)} cartes disponibles • 8 cartes par joueur • draft progressif", size=11, fill=MUTED, anchor="w")
        self._text(68, 132, "CARTES DISPONIBLES", size=13, fill=GREEN, weight="bold", anchor="w")
        self._text(790, 132, "MOLETTE ↑↓", size=9, fill=MUTED, weight="bold", anchor="e")

        # Barre de défilement verticale. Le clic au-dessus / en dessous du curseur
        # fait avancer d'environ une hauteur d'écran.
        track_x1, track_x2 = 797, 812
        track_y1, track_y2 = content_top, content_bottom
        self._rect(track_x1, track_y1, track_x2, track_y2, fill="#0a0f17", outline="#344258", width=1, radius=7)
        max_scroll = self._draft_max_scroll()
        viewport_h = content_bottom - content_top
        content_h = max(viewport_h, self._draft_content_height())
        thumb_h = max(58.0, viewport_h * viewport_h / content_h)
        thumb_travel = max(1.0, viewport_h - thumb_h)
        ratio = 0.0 if max_scroll <= 0 else self.draft_scroll / max_scroll
        thumb_y1 = track_y1 + ratio * thumb_travel
        thumb_y2 = thumb_y1 + thumb_h
        self._rect(track_x1 + 2, thumb_y1, track_x2 - 2, thumb_y2, fill="#60708a", outline="#8797b0", width=1, radius=5)
        if thumb_y1 > track_y1 + 2:
            self._add_click(track_x1 - 5, track_y1, track_x2 + 5, thumb_y1, lambda: self._draft_scroll_by(-viewport_h * 0.82))
        if thumb_y2 < track_y2 - 2:
            self._add_click(track_x1 - 5, thumb_y2, track_x2 + 5, track_y2, lambda: self._draft_scroll_by(viewport_h * 0.82))

        # Panneau d'aperçu / validation.
        self._rect(850, 105, 1555, 865, fill="#0e151f", outline="#2c3a4e", width=2, radius=20)
        accent = BLUE if self.draft_active_player == 1 else RED
        self._text(885, 140, f"{self._player_display_name(self.draft_active_player).upper()} CHOISIT", size=19, fill=accent, weight="bold", anchor="w")
        self._text(885, 175, f"{self._player_display_name(1)} : {len(self.draft_decks[1])}/{DRAFT_SIZE_PER_PLAYER}    •    {self._player_display_name(2)} : {len(self.draft_decks[2])}/{DRAFT_SIZE_PER_PLAYER}", size=11, fill=MUTED, anchor="w")

        preview = self.draft_preview_card
        if preview:
            self._draw_card(preview, 885, 215, "detail", selected=False)
            self._add_click(885, 215, 1165, 635, lambda c=preview: self._open_card_reader(c))
            self._text(1025, 638, "CLIQUE LA GRANDE CARTE = FICHE COMPLETE", size=7, fill="#8fa4bf", weight="bold")
        can_take_preview = (
            preview is not None
            and self.draft_owner.get(preview.id) is None
            and self._controller(self.draft_active_player) == "human"
            and self._draft_card_allowed(self.draft_active_player, preview)
        )
        self._button(885, 650, 1165, 710, f"PRENDRE POUR J{self.draft_active_player}", self._draft_confirm_pick, fill="#18261f", accent=accent, enabled=can_take_preview, small=True)

        self._rect(885, 728, 1165, 835, fill="#151e2b", outline="#3d3422", width=1, radius=12)
        if preview:
            self._text(900, 747, f"SPÉCIALE — {preview.special_name}", size=8, fill=GOLD, weight="bold", anchor="w")
            special_txt, special_size = self._fit_text_box(preview.special, 245, 62, start_size=7, min_size=5, max_lines=4)
            self._text(900, 770, special_txt, size=special_size, fill="#cfd7e2", anchor="nw", justify="left", width=245)

        self._rect(1190, 215, 1518, 500, fill="#151e2b", outline="#2a374b", width=1, radius=14)
        self._text(1215, 240, "DECKS & LIMITES", size=13, fill=GREEN, weight="bold", anchor="w")

        # Les deux joueurs gardent leurs compteurs visibles en permanence :
        # on voit immédiatement, tour après tour, ce qu'il reste à chacun.
        headers = ((1, 1215, BLUE), (2, 1372, RED))
        for pnum, xx, color in headers:
            marker = "  ◀" if pnum == self.draft_active_player else ""
            self._text(xx, 276, f"{self._player_display_name(pnum)}  {len(self.draft_decks[pnum])}/8{marker}", size=10, fill=color, weight="bold", anchor="w")
            self._text(xx, 302, f"TOTAL {self._draft_total_stars(pnum):g}/{MAX_TOTAL_STAR_VALUE:g}★", size=8, fill="#ffd84d", weight="bold", anchor="w")

        star_rows = [(3.0, 338), (3.5, 370), (4.0, 402), (4.5, 434), (5.0, 466)]
        for stars, yy in star_rows:
            limit = self._draft_star_limit(stars)
            stars_txt = str(stars).replace(".0", "").replace(".5", ",5")
            for pnum, xx, color in headers:
                count = self._star_count(self.draft_decks[pnum], stars)
                self._text(
                    xx, yy, f"{stars_txt}★ = {count}/{self._star_limit_label(limit)}",
                    size=9, fill=(color if pnum == self.draft_active_player else "#dce4ee"),
                    weight="bold", anchor="w",
                )

        self._rect(1190, 515, 1518, 790, fill="#121a25", outline="#2a374b", width=1, radius=14)
        self._text(1215, 545, "RÈGLE DU DRAFT", size=11, fill=GREEN, weight="bold", anchor="w")
        self._text(
            1215, 580,
            "Les raretés se DÉBLOQUENT progressivement et ne se referment jamais.\n"
            "Prendre moins étoilé ne fait pas perdre un palier déjà débloqué.\n\n"
            "Rythme si chacun vise le maximum :\n"
            "T1 : 3★ / 3★+3,5★   •   T2 : 3,5★+4★ / 4★+4,5★\n"
            "T3 : 4,5★+5★ / 5★+4,5★   •   T4 : 4,5★+4★ / 4★+4★\n"
            "T5 : dernier choix 4★ du gagnant\n\n"
            "Exemple : une fois 5★ débloquée, elle reste disponible si 5★=0/1 et si le total reste ≤32,5★.\n"
            "Limites : 3,5★×4 • 4★×3 • 4,5★×2 • 5★×1.",
            size=9, fill="#cfd7e2", anchor="nw", justify="left", width=275
        )
        if self._controller(self.draft_active_player) == "ai":
            self._text(1215, 735, "L'IA choisit…", size=11, fill=ACCENT, weight="bold", anchor="w")
        elif preview and self.draft_owner.get(preview.id) is None and not self._draft_card_allowed(self.draft_active_player, preview):
            cap = self._draft_star_cap(self.draft_active_player)
            if preview.stars > cap + 0.01:
                msg = f"Carte verrouillée : les cartes jusqu'à {str(cap).replace('.0','').replace('.5',',5')}★ sont déjà débloquées."
            elif self._draft_total_stars(self.draft_active_player) + float(preview.stars) > MAX_TOTAL_STAR_VALUE + 0.001:
                msg = f"Valeur totale maximale atteinte : {MAX_TOTAL_STAR_VALUE:g}★."
            else:
                limit = self._draft_star_limit(preview.stars)
                msg = f"Limite atteinte : {preview.star_label} = {self._star_count(self.draft_decks[self.draft_active_player], preview.stars)}/{self._star_limit_label(limit)}."
            self._text(1215, 735, msg, size=10, fill=RED, weight="bold", anchor="w", width=270)
        else:
            self._text(1215, 735, "Clique une carte disponible.", size=10, fill=accent, weight="bold", anchor="w")

    def _select_draft_preview(self, card: CardDefinition):
        if self.current_screen != "draft":
            return
        self.draft_preview_card = card
        self.redraw()

    def _draft_confirm_pick(self):
        card = self.draft_preview_card
        if card is None or self.current_screen != "draft" or self.draft_owner.get(card.id) is not None:
            return
        player = self.draft_active_player
        if self._controller(player) != "human":
            return
        if self.current_mode and self.current_mode.id == "multiplayer":
            self._net_send({"type": "draft_pick", "player": player, "card_id": card.id})
        self._apply_draft_pick(player, card)

    def _apply_draft_pick(self, player: int, card: CardDefinition):
        scheduled = self._draft_scheduled_player()
        if scheduled is not None and int(player) != int(scheduled):
            return
        if int(player) != int(self.draft_active_player):
            return
        if self.draft_owner.get(card.id) is not None:
            return
        if len(self.draft_decks[player]) >= DRAFT_SIZE_PER_PLAYER:
            return
        if not self._draft_card_allowed(player, card):
            cap = self._draft_star_cap(player)
            if card.stars > cap + 0.01:
                self.notice = f"Impossible : cette rareté n'est pas encore débloquée (jusqu'à {str(cap).replace('.0','').replace('.5',',5')}★ actuellement)."
            elif self._draft_total_stars(player) + float(card.stars) > MAX_TOTAL_STAR_VALUE + 0.001:
                self.notice = f"Impossible : J{player} ne peut pas dépasser {MAX_TOTAL_STAR_VALUE:g}★ au total."
            else:
                limit = self._draft_star_limit(card.stars)
                self.notice = f"Impossible : J{player} a atteint la limite {card.star_label} ({self._star_count(self.draft_decks[player], card.stars)}/{self._star_limit_label(limit)})."
            self.redraw()
            return
        self.draft_owner[card.id] = player
        self.draft_decks[player].append(card)
        self.draft_preview_card = card
        if hasattr(self, "audio"):
            self.audio.play_selection_pick()

        if all(len(self.draft_decks[p]) >= DRAFT_SIZE_PER_PLAYER for p in (1, 2)):
            self._begin_lineup_selection()
            return

        next_player = self._draft_scheduled_player()
        if next_player is None:
            self._begin_lineup_selection()
            return
        self.draft_active_player = int(next_player)
        cap = self._draft_star_cap(self.draft_active_player)
        self.notice = (
            f"{self._player_display_name(self.draft_active_player)} choisit maintenant "
            f"(T{self._draft_round()} • jusqu'à {str(cap).replace('.0','').replace('.5',',5')}★ débloquées)."
        )
        self.redraw()
        self._maybe_schedule_ai_draft()

    def _maybe_schedule_ai_draft(self):
        if self.current_screen != "draft":
            return
        if self._controller(self.draft_active_player) != "ai":
            return
        if self._pending_ai_job:
            try:
                self.root.after_cancel(self._pending_ai_job)
            except Exception:
                pass
        self._pending_ai_job = self.root.after(500, self._ai_draft_pick)

    def _ai_draft_pick(self):
        self._pending_ai_job = None
        if self.current_screen != "draft" or self._controller(self.draft_active_player) != "ai":
            return
        available = [
            c for c in self.draft_pool
            if self.draft_owner.get(c.id) is None
            and self._draft_card_allowed(self.draft_active_player, c)
        ]
        if not available:
            return
        card = max(
            available,
            key=lambda c: c.max_hp * 0.35 + max(c.taijutsu, c.ninjutsu, c.genjutsu) + (c.taijutsu + c.ninjutsu + c.genjutsu) * 0.20 + self.random.random() * 80,
        )
        self._apply_draft_pick(self.draft_active_player, card)

    # ------------------------------------------------------------------
    # Private selection of the 3 starting Ninjas
    # ------------------------------------------------------------------
    def _begin_lineup_selection(self):
        self.current_screen = "lineup"
        if hasattr(self, "audio"):
            self.audio.play_selection_music()
        self.starter_choices = {1: [], 2: []}
        self.lineup_active_player = 1
        self.lineup_revealed = False
        self.lineup_preview_card = self.draft_decks[1][0] if self.draft_decks[1] else None
        self.notice = ""
        self.redraw()

    def _lineup_reveal(self):
        if self.current_screen != "lineup":
            return
        if self._controller(self.lineup_active_player) != "human":
            self.notice = f"{self._player_display_name(self.lineup_active_player)} choisit ses Ninjas sur l’autre PC."
            self.redraw()
            return
        self.lineup_revealed = True
        deck = self.draft_decks[self.lineup_active_player]
        self.lineup_preview_card = deck[0] if deck else None
        self.redraw()

    def _lineup_toggle(self, card: CardDefinition, *, from_network: bool = False, forced_player: int | None = None):
        if self.current_screen != "lineup":
            return
        player = self.lineup_active_player if forced_player is None else int(forced_player)
        if player != self.lineup_active_player:
            return
        if not from_network:
            if not self.lineup_revealed or self._controller(player) != "human":
                return
        selected = self.starter_choices[player]
        existing_index = next((i for i, c in enumerate(selected) if c.id == card.id), None)
        selecting = existing_index is None
        if existing_index is not None:
            selected.pop(existing_index)
            self.notice = f"{card.name} retire des Ninjas de depart."
        elif len(selected) < STARTER_COUNT:
            selected.append(card)
            if hasattr(self, "audio"):
                self.audio.play_selection_pick()
            self.notice = f"{card.name} selectionne comme Ninja de depart."
        else:
            self.notice = "Tu as deja choisi 3 Ninjas de depart. Retire-en un pour en changer."
            self.redraw()
            return
        if self.current_mode and self.current_mode.id == "multiplayer" and not from_network:
            self._net_send({"type": "lineup_toggle", "player": player, "card_id": card.id, "selecting": selecting})
        self.lineup_preview_card = card if self._controller(player) == "human" else None
        self.redraw()

    def _lineup_confirm(self, *, from_network: bool = False, forced_player: int | None = None):
        player = self.lineup_active_player if forced_player is None else int(forced_player)
        if self.current_screen != "lineup" or player != self.lineup_active_player or len(self.starter_choices[player]) != STARTER_COUNT:
            return
        if not from_network and self._controller(player) != "human":
            return
        if self.current_mode and self.current_mode.id == "multiplayer" and not from_network:
            self._net_send({"type": "lineup_confirm", "player": player})
        if player == 1:
            self.lineup_active_player = 2
            if self._controller(2) == "ai":
                self._ai_choose_starters()
                self._begin_rps("start")
            else:
                self.lineup_revealed = False
                self.lineup_preview_card = None
                self.notice = f"{self._player_display_name(2)} choisit maintenant ses 3 Ninjas."
                self.redraw()
        else:
            self._begin_rps("start")

    def _ai_choose_starters(self):
        deck = list(self.draft_decks[2])
        ranked = sorted(
            deck,
            key=lambda c: (
                c.stars,
                c.max_hp * 0.35 + max(c.taijutsu, c.ninjutsu, c.genjutsu) + (c.taijutsu + c.ninjutsu + c.genjutsu) * 0.20,
            ),
            reverse=True,
        )
        self.starter_choices[2] = ranked[:STARTER_COUNT]

    def _draw_lineup(self):
        self._gradient_background("#111925", "#06090f")
        player = self.lineup_active_player
        accent = BLUE if player == 1 else RED

        self._text(55, 48, "3 NINJAS DE DEPART", size=28, weight="bold", anchor="w", family=DISPLAY_FONT_TOKEN)
        self._text(55, 84, "Choisis exactement 3 cartes. Elles seront placees automatiquement sur le terrain.", size=11, fill=MUTED, anchor="w")
        state = "FENETRE" if self.is_fullscreen else "PLEIN ECRAN"
        self._button(1260, 28, 1405, 73, state, self._toggle_fullscreen, fill="#151d29", accent="#5f6d82", small=True)
        self._button(1418, 28, 1544, 73, "MENU", self.show_main_menu, fill="#151d29", accent="#7b5860", small=True)

        if not self.lineup_revealed:
            self._rect(390, 210, 1210, 710, fill="#0f1621", outline=accent, width=3, radius=28)
            self._text(800, 305, self._player_display_name(player).upper(), size=34, fill=accent, weight="bold", family=DISPLAY_FONT_TOKEN)
            if self._controller(player) == "human":
                self._text(800, 385, "TON DECK EST CACHE", size=26, weight="bold")
                self._text(800, 435, "Affiche ton deck pour choisir tes 3 Ninjas de depart.", size=12, fill=MUTED)
                self._button(600, 515, 1000, 595, "AFFICHER MON DECK", self._lineup_reveal, fill="#18261f", accent=accent)
            else:
                self._text(800, 385, f"{self._player_display_name(player).upper()} CHOISIT SES 3 NINJAS", size=26, weight="bold")
                self._text(800, 435, "Son choix reste cache sur son propre PC. Attends sa validation.", size=12, fill=MUTED)
                self._text(800, 535, "EN ATTENTE…", size=20, fill=GOLD, weight="bold")
            return

        selected = self.starter_choices[player]
        self._text(790, 50, f"JOUEUR {player} — {len(selected)}/3 SÉLECTIONNÉES", size=15, fill=accent, weight="bold")

        # Les cartes sont volontairement espacees : 4 colonnes de 200 px dans un panneau de 958 px.
        self._rect(42, 115, 1000, 855, fill="#0f1722", outline="#2f3d52", width=2, radius=20)
        deck = self.draft_decks[player]
        card_w, card_h = DRAFT_CARD_W, DRAFT_CARD_H
        gap_x, gap_y = 26, 44
        start_x, start_y = 65, 165
        for i, card in enumerate(deck):
            row, col = divmod(i, 4)
            x1 = start_x + col * (card_w + gap_x)
            y1 = start_y + row * (card_h + gap_y)
            is_selected = any(c.id == card.id for c in selected)
            self._draw_card(card, x1, y1, "draft", selected=is_selected)
            if is_selected:
                self._rect(x1 + 25, y1 + card_h + 5, x1 + card_w - 25, y1 + card_h + 34, fill="#0b1018", outline=accent, width=2, radius=7)
                self._text(x1 + card_w / 2, y1 + card_h + 19, "DEPART", size=8, fill=accent, weight="bold", family=DISPLAY_FONT_TOKEN)
            self._add_click(x1, y1, x1 + card_w, y1 + card_h, lambda c=card: self._lineup_toggle(c))

        self._rect(1030, 115, 1555, 855, fill="#101722", outline="#2f3d52", width=2, radius=20)
        self._text(1060, 150, "APERCU", size=13, fill=accent, weight="bold", anchor="w")
        if self.lineup_preview_card:
            self._draw_card(self.lineup_preview_card, 1145, 190, "detail")
            self._add_click(1145, 190, 1425, 610, lambda c=self.lineup_preview_card: self._open_card_reader(c))
            self._text(1285, 620, "CLIQUE LA CARTE = FICHE COMPLETE", size=7, fill="#8fa4bf", weight="bold")
        self._text(1060, 640, "REGLE", size=11, fill=GREEN, weight="bold", anchor="w")
        rule = (
            "Le deck de 8 cartes est deja constitue.\n"
            "Ici, aucune restriction d'etoiles : choisis librement\n"
            "n'importe quelles 3 cartes de ton deck pour commencer.\n"
            "Les 5 autres cartes formeront la reserve cachee."
        )
        rule_txt, rule_size = self._fit_text_box(rule, 445, 92, start_size=10, min_size=7, max_lines=6)
        self._text(1060, 675, rule_txt, size=rule_size, fill="#cfd7e2", anchor="nw", justify="left", width=445)
        self._button(1100, 785, 1490, 840, "VALIDER MES 3 NINJAS", self._lineup_confirm, fill="#18261f", accent=accent, enabled=len(selected) == STARTER_COUNT)

    # ------------------------------------------------------------------
    # Card renderer based on CARTE.png + FOND1 + character art
    # ------------------------------------------------------------------
    def _draw_card(
        self,
        card: CardDefinition,
        x1: float,
        y1: float,
        variant: str,
        *,
        current_hp: int | None = None,
        selected: bool = False,
        owner: int | None = None,
        instance=None,
        visual_scale: float = 1.0,
    ):
        dims = {
            "draft": (DRAFT_CARD_W, DRAFT_CARD_H, "card_bg_draft"),
            "hand": (132, 198, "card_bg_hand"),
            "field": (230, 330, "card_bg_field"),
            "detail": (280, 420, "card_bg_detail"),
        }
        base_w, base_h, asset = dims[variant]
        visual_scale = max(0.72, min(1.04, float(visual_scale or 1.0))) if variant == "field" else 1.0
        cx, cy = x1 + base_w / 2, y1 + base_h / 2
        w, h = base_w * visual_scale, base_h * visual_scale
        if visual_scale != 1.0:
            x1, y1 = cx - w / 2, cy - h / 2
        x2, y2 = x1 + w, y1 + h
        card_font_scale = visual_scale if variant == "field" else 1.0

        # Transfert de l'esprit d'Ino : sa carte prend visuellement l'identité
        # du corps contrôlé (nom, étoiles, élément, image, PV et stats actuels).
        controlled_target = None
        if instance is not None and card.id == "ino":
            candidate = getattr(instance, "ino_possession_target", None)
            if candidate is not None and int(getattr(candidate, "current_hp", 0) or 0) > 0:
                controlled_target = candidate
        display_card = controlled_target.definition if controlled_target is not None else card
        display_element = display_card.element

        # NEW DESIGN 1.7.15 : objet physique plus discret. Le verre est une
        # vraie surcouche PNG alpha, dessinée APRÈS le contenu de la carte.
        # Ici on ne garde que l'ombre et le support extérieur.
        if variant == "field":
            # 1.7.16 : AUCUN halo/rectangle de sélection. Le seul feedback de
            # sélection est l'agrandissement à +4 %, comme demandé.
            self._stipple_rect(x1 + 4, y1 + 6, x2 + 8, y2 + 10, fill="#000000", stipple="gray50", outline="")
            self._rect(x1 - 4, y1 - 4, x2 + 4, y2 + 4, fill="#0a111b", outline="#687787", width=2, radius=9)
            self._rect(x1 - 1, y1 - 1, x2 + 1, y2 + 1, fill="", outline="#aebbc7", width=1, radius=6)

        self._draw_asset(asset, x1, y1, extra_scale=visual_scale)

        if selected and variant != "field":
            self._rect(x1 - 3, y1 - 3, x2 + 3, y2 + 3, fill="", outline=ACCENT_2, width=4)
        if owner in (1, 2):
            owner_color = BLUE if owner == 1 else RED
            self._rect(x1 - 2, y1 - 2, x2 + 2, y2 + 2, fill="", outline=owner_color, width=4)
        self._rect(x1, y1, x2, y2, fill="", outline="#d8e2ed" if variant == "field" else "#080808", width=4 if variant == "field" else 3)

        mx = w * 0.045
        my = h * 0.018
        header_top = y1 + my
        header_bottom = y1 + h * 0.095
        art_top = y1 + h * 0.115
        art_bottom = y1 + h * 0.625
        stats_top = y1 + h * 0.645
        stats_bottom = y1 + h * 0.805
        passive_top = y1 + h * 0.825
        passive_bottom = y2 - my

        name_right = x1 + w * 0.54
        hp_left = x1 + w * 0.57
        self._rect(x1 + mx, header_top, name_right, header_bottom, fill=CREAM, outline=INK, width=2)
        self._rect(hp_left, header_top, x2 - mx, header_bottom, fill=CREAM, outline=INK, width=2)

        # Image du personnage. Si elle n'existe pas, aucun substitut n'est
        # dessiné : FOND1 reste visible dans l'encadrement, conformément à la règle.
        if instance is not None and card.id == "gai":
            gai_hp = int(getattr(instance, "current_hp", 0) or 0)
            gai_stage = None
            if gai_hp * 100 <= card.max_hp * 25:
                gai_stage = 3
            elif gai_hp * 100 <= card.max_hp * 50:
                gai_stage = 2
            elif gai_hp * 100 <= card.max_hp * 75:
                gai_stage = 1
            stage_key = f"char_gai_stade{gai_stage}_{variant}" if gai_stage else ""
            char_key = stage_key if stage_key in self.base_images else f"char_{card.id}_{variant}"
        elif instance is not None and card.id == "jugo" and int(getattr(instance, "jugo_stage", 0) or 0) > 0:
            stage = min(2, int(getattr(instance, "jugo_stage", 0) or 0))
            stage_key = f"char_jugo_stade{stage}_{variant}"
            char_key = stage_key if stage_key in self.base_images else f"char_{card.id}_{variant}"
        elif (
            instance is not None
            and card.id == "jiraiya"
            and bool(getattr(instance, "jiraiya_sage_active", False))
            and f"char_jiraiya_sage_{variant}" in self.base_images
        ):
            char_key = f"char_jiraiya_sage_{variant}"
        elif controlled_target is not None:
            if (
                controlled_target.definition.id == "jiraiya"
                and bool(getattr(controlled_target, "jiraiya_sage_active", False))
                and f"char_jiraiya_sage_{variant}" in self.base_images
            ):
                char_key = f"char_jiraiya_sage_{variant}"
            else:
                char_key = f"char_{controlled_target.definition.id}_{variant}"
        elif (
            instance is not None
            and card.id == "konohamaru"
            and int(getattr(instance, "konohamaru_sexy_turns", 0)) > 0
            and f"char_konohamaru_sexy_{variant}" in self.base_images
        ):
            char_key = f"char_konohamaru_sexy_{variant}"
        elif instance is not None and getattr(instance, "gengetsu_clone_active", False):
            char_key = f"char_gengetsu_clone_{variant}"
        elif (
            instance is not None
            and card.id == "naruto"
            and int(getattr(instance, "current_hp", 0) or 0) * 2 < card.max_hp
            and f"char_naruto_passif_{variant}" in self.base_images
        ):
            char_key = f"char_naruto_passif_{variant}"
        else:
            char_key = f"char_{card.id}_{variant}"
        if char_key in self.base_images:
            self._draw_asset(char_key, x1 + mx, art_top, extra_scale=visual_scale)
        self._rect(x1 + mx, art_top, x2 - mx, art_bottom, fill="", outline=INK, width=2)

        # Badge d'étoiles : toujours dans l'illustration pour ne jamais empiéter
        # sur les cadres du nom et des PV.
        badge_w = (66 if variant == "detail" else (50 if variant == "draft" else 42)) * card_font_scale
        badge_h = (28 if variant == "detail" else (22 if variant == "draft" else 18)) * card_font_scale
        bx1 = x1 + mx + 5
        by1 = art_top + 5
        self._rect(bx1, by1, bx1 + badge_w, by1 + badge_h, fill="#16120a", outline=GOLD, width=2, radius=5)
        self._text(
            bx1 + badge_w / 2, by1 + badge_h / 2,
            display_card.star_label,
            size=max(5, int(round((9 if variant == "detail" else (7 if variant == "draft" else 6)) * card_font_scale))),
            fill="#ffd36a", weight="bold"
        )

        # Classic 1.5.2 : repère compact de la synergie ACTIVE sur le terrain.
        # [S 2/2] = duo explicite (+15 %), [S 2/3] = famille partielle
        # (+12,5 %), [S 3/3] = trio de famille complet (+20 %).
        # Le badge n'existe volontairement que sur les cartes de TERRAIN :
        # Le repère reste limité aux cartes réellement présentes sur le terrain.
        synergy_field_badge = ""
        synergy_field_badge_h = 0
        if variant == "field" and instance is not None:
            synergy_pct = float(getattr(instance, "synergy_bonus_pct", 0.0) or 0.0)
            if synergy_pct >= 0.199:
                synergy_field_badge = "[S 3/3]"
            elif synergy_pct >= 0.149:
                synergy_field_badge = "[S 2/2]"
            elif synergy_pct >= 0.124:
                synergy_field_badge = "[S 2/3]"
            if synergy_field_badge:
                synergy_field_badge_w = 58 * card_font_scale
                synergy_field_badge_h = 20 * card_font_scale
                sx2 = x2 - mx - 5
                sy1 = art_top + 5
                self._rect(
                    sx2 - synergy_field_badge_w, sy1, sx2, sy1 + synergy_field_badge_h,
                    fill="#102219", outline="#62d58b", width=2, radius=5
                )
                self._text(
                    sx2 - synergy_field_badge_w / 2, sy1 + synergy_field_badge_h / 2,
                    synergy_field_badge, size=max(5, int(round(6 * card_font_scale))), fill="#c8f6d6", weight="bold"
                )

        self._rect(x1 + mx, stats_top, x2 - mx, stats_bottom, fill=CREAM, outline=INK, width=2)
        self._rect(x1 + mx, passive_top, x2 - mx, passive_bottom, fill=CREAM, outline=INK, width=2)

        if controlled_target is not None:
            hp_value = int(getattr(controlled_target, "current_hp", display_card.max_hp) or 0)
        else:
            hp_value = card.max_hp if current_hp is None else current_hp
        if variant == "detail":
            name_size, hp_size, stat_size, pass_size = 13, 13, 10, 10
        elif variant == "field":
            name_size, hp_size, stat_size, pass_size = (
                max(6, int(round(11 * card_font_scale))),
                max(6, int(round(10 * card_font_scale))),
                max(5, int(round(8 * card_font_scale))),
                max(5, int(round(7 * card_font_scale))),
            )
        elif variant == "hand":
            name_size, hp_size, stat_size, pass_size = 7, 7, 6, 6
        else:
            # V5 : les cartes du catalogue sont volontairement bien plus grandes.
            name_size, hp_size, stat_size, pass_size = 10, 10, 8, 7

        # NOM : réduction automatique plutôt qu'un texte qui sort de son cadre.
        name_box_w = (name_right - (x1 + mx)) - w * 0.035
        name_box_h = (header_bottom - header_top) * 0.78
        if variant == "draft":
            name_text, fitted_name_size = self._fit_draft_card_text(display_card.name, max_chars=19, size=name_size, max_lines=1)
        else:
            name_text, fitted_name_size = self._fit_text_box(
                display_card.name, name_box_w, name_box_h, start_size=name_size, min_size=5, weight="bold", family=DISPLAY_FONT_TOKEN, max_lines=1
            )
        self._text(
            x1 + mx + w * 0.018, (header_top + header_bottom) / 2, name_text,
            size=fitted_name_size, fill=INK, weight="bold", anchor="w", width=name_box_w, family=DISPLAY_FONT_TOKEN
        )

        hp_box_w = (x2 - mx - hp_left)
        header_mid_y = (header_top + header_bottom) / 2
        if instance is not None and self.engine is not None:
            effect_instance = self.engine._effect_carrier(instance)
        else:
            effect_instance = instance
        shield_value = int(getattr(effect_instance, "shield", 0)) if effect_instance is not None else 0
        if shield_value > 0:
            hp_text, fitted_hp_size = self._fit_text_box(
                f"PV {hp_value}", hp_box_w * 0.55, name_box_h,
                start_size=hp_size, min_size=5, weight="bold", max_lines=1
            )
            shield_text, shield_size = self._fit_text_box(
                f"+ {shield_value}", hp_box_w * 0.28, name_box_h,
                start_size=hp_size, min_size=5, weight="bold", max_lines=1
            )
            self._text(hp_left + hp_box_w * 0.28, header_mid_y, hp_text, size=fitted_hp_size, fill=INK, weight="bold")
            self._text(hp_left + hp_box_w * 0.76, header_mid_y, shield_text, size=shield_size, fill="#4da8ff", weight="bold")
        else:
            if variant == "draft":
                hp_text, fitted_hp_size = self._fit_draft_card_text(f"PV {hp_value}", max_chars=8, size=hp_size, max_lines=1)
            else:
                hp_text, fitted_hp_size = self._fit_text_box(
                    f"PV {hp_value}", hp_box_w * 0.88, name_box_h,
                    start_size=hp_size, min_size=5, weight="bold", max_lines=1
                )
            self._text((hp_left + x2 - mx) / 2, header_mid_y, hp_text, size=fitted_hp_size, fill=INK, weight="bold")

        # STATS : la partie gauche possède une largeur stricte afin de ne jamais
        # empiéter sur l'élément fétiche à droite.
        left_x = x1 + mx + w * 0.026
        stats_left_w = w * 0.60
        line_y = stats_top + (stats_bottom - stats_top) * 0.22
        line_gap = (stats_bottom - stats_top) * 0.28
        # Sur le terrain, les chiffres imprimés deviennent les statistiques
        # RÉELLES de la carte (buffs, debuffs, portes de Gai, etc.). Les cartes
        # hors duel continuent d'afficher leurs valeurs de base.
        if instance is not None and self.engine is not None:
            shown_tai = self.engine.effective_stat(instance, "taijutsu")
            shown_nin = self.engine.effective_stat(instance, "ninjutsu")
            shown_gen = self.engine.effective_stat(instance, "genjutsu")
        else:
            shown_tai, shown_nin, shown_gen = card.taijutsu, card.ninjutsu, card.genjutsu

        for n, stat_line in enumerate((
            f"TAIJUTSU : {shown_tai}",
            f"NINJUTSU : {shown_nin}",
            f"GENJUTSU : {shown_gen}",
        )):
            if variant == "draft":
                fitted, fitted_size = self._fit_draft_card_text(stat_line, max_chars=18, size=stat_size, max_lines=1)
            else:
                fitted, fitted_size = self._fit_text_box(
                    stat_line, stats_left_w, line_gap * 0.92, start_size=stat_size, min_size=5, weight="bold", max_lines=1
                )
            self._text(left_x, line_y + line_gap * n, fitted, size=fitted_size, fill=INK, weight="bold", anchor="w")

        element_color = ELEMENT_COLORS.get(display_element, "#555555")
        element_x = x1 + w * 0.79
        element_box_w = w * 0.27
        if display_card.id == "kakuzu":
            # Kakuzu possède les cinq affinités. On les juxtapose vraiment sur
            # la carte au lieu d'afficher un faux élément unique.
            label = "TOUS LES ÉLÉMENTS" if variant == "detail" else "TOUS"
            elem_start = 7 if variant in ("detail", "draft") else 5
            if variant == "draft":
                elem_label, elem_size = self._fit_draft_card_text(label, max_chars=8, size=elem_start, max_lines=1)
            else:
                elem_label, elem_size = self._fit_text_box(
                    label, element_box_w, (stats_bottom-stats_top)*0.24,
                    start_size=elem_start, min_size=5, weight="bold", max_lines=1
                )
            self._text(element_x, stats_top + (stats_bottom - stats_top) * 0.27, elem_label, size=elem_size, fill=INK, weight="bold")
            elements = ("feu", "vent", "foudre", "terre", "eau")
            spacing = element_box_w / 5.5
            start_x = element_x - spacing * 2
            kanji_size = max(5, int(round((12 if variant == "detail" else (8 if variant == "draft" else 7)) * card_font_scale)))
            for idx_elem, elem in enumerate(elements):
                self._text(
                    start_x + idx_elem * spacing,
                    stats_top + (stats_bottom - stats_top) * 0.70,
                    ELEMENT_KANJI[elem],
                    size=kanji_size,
                    fill=ELEMENT_COLORS[elem],
                    weight="bold",
                )
        elif variant == "detail":
            elem_label, elem_size = self._fit_text_box("ÉLÉMENT FÉTICHE", element_box_w, (stats_bottom-stats_top)*0.25, start_size=8, min_size=5, weight="bold", max_lines=1)
            self._text(element_x, stats_top + (stats_bottom - stats_top) * 0.28, elem_label, size=elem_size, fill=INK, weight="bold")
            self._text(element_x, stats_top + (stats_bottom - stats_top) * 0.68, ELEMENT_KANJI.get(display_element, "?"), size=24, fill=element_color, weight="bold")
        else:
            elem_start = 7 if variant == "draft" else 5
            if variant == "draft":
                elem_label, elem_size = self._fit_draft_card_text(ELEMENT_SHORT.get(display_element, display_element.upper()), max_chars=8, size=elem_start, max_lines=1)
            else:
                elem_label, elem_size = self._fit_text_box(ELEMENT_SHORT.get(display_element, display_element.upper()), element_box_w, (stats_bottom-stats_top)*0.25, start_size=elem_start, min_size=5, weight="bold", max_lines=1)
            self._text(element_x, stats_top + (stats_bottom - stats_top) * 0.31, elem_label, size=elem_size, fill=INK, weight="bold")
            self._text(element_x, stats_top + (stats_bottom - stats_top) * 0.69, ELEMENT_KANJI.get(display_element, "?"), size=max(5, int(round((15 if variant == "draft" else 13) * card_font_scale))), fill=element_color, weight="bold")

        if controlled_target is not None:
            turns = max(0, int(getattr(instance, "ino_possession_turns_left", 0)))
            passive = (
                f"TRANSFERT DE L'ESPRIT — Ino contrôle {controlled_target.definition.name}. "
                f"Stats et élément copiés • {turns} tour(s) restant(s) • spéciale ennemie interdite."
            )
        elif instance is not None and getattr(instance, "ino_possessed_by", None) is not None:
            passive = "TRANSFERT DE L'ESPRIT — Corps bloqué et inciblable tant qu'Ino conserve le contrôle."
        else:
            passive = (
                f"{card.passive_name} — {card.passive}"
                if card.passive_name and card.passive
                else (card.passive or card.passive_name or "Aucun passif défini.")
            )
        passive_w = w - 2 * mx - (18 if variant == "detail" else 12)
        passive_h = (passive_bottom - passive_top) * 0.80
        passive_lines = 3 if variant in ("detail", "draft") else 2
        if variant == "draft":
            passive_text, fitted_pass_size = self._fit_draft_card_text(passive, max_chars=43, size=pass_size, max_lines=passive_lines)
        else:
            passive_text, fitted_pass_size = self._fit_text_box(
                passive, passive_w, passive_h, start_size=pass_size, min_size=5, weight="normal", max_lines=passive_lines
            )
        self._text(
            (x1 + x2) / 2, (passive_top + passive_bottom) / 2, passive_text,
            size=fitted_pass_size, fill=INK, width=passive_w, justify="center"
        )

        # Recharge visible directement sur la carte : T 1/3, T 2/3, etc.
        if instance is not None and self.engine is not None:
            cooldown = self.engine.special_cooldown_progress(instance)
            if cooldown is not None:
                done, total = cooldown
                badge_w2 = (70 if variant == "detail" else 56) * card_font_scale
                badge_h2 = (25 if variant == "detail" else 20) * card_font_scale
                cx2 = x2 - mx - 5
                cy1 = art_top + 5
                if variant == "field" and synergy_field_badge:
                    cy1 += synergy_field_badge_h + 5
                self._rect(cx2 - badge_w2, cy1, cx2, cy1 + badge_h2, fill="#16120a", outline="#ffd84d", width=2, radius=5)
                self._text(
                    cx2 - badge_w2 / 2, cy1 + badge_h2 / 2,
                    f"T {done}/{total}",
                    size=max(5, int(round((8 if variant == "detail" else 6) * card_font_scale))), fill="#ffd84d", weight="bold"
                )

        # Visuel du Transfert d'Ino.
        if controlled_target is not None:
            turns = max(0, int(getattr(instance, "ino_possession_turns_left", 0)))
            self._rect(
                x1 + w * 0.16, y1 + h * 0.555, x1 + w * 0.84, y1 + h * 0.615,
                fill="#17101f", outline="#c69cff", width=2, radius=5
            )
            label, label_size = self._fit_text_box(
                f"CONTRÔLE • {turns}T", w * 0.62, h * 0.042,
                start_size=8 if variant == "detail" else 6, min_size=5,
                weight="bold", max_lines=1
            )
            self._text(x1 + w * 0.50, y1 + h * 0.585, label, size=label_size, fill="#f2ddff", weight="bold")

        possessed_by = getattr(instance, "ino_possessed_by", None) if instance is not None else None
        if possessed_by is not None and int(getattr(possessed_by, "current_hp", 0) or 0) > 0:
            overlay_key = f"char_ino_white_overlay_{variant}"
            if overlay_key in self.base_images:
                self._draw_asset(overlay_key, x1, y1, extra_scale=visual_scale)
            if f"char_ino_ghost_{variant}" in self.base_images:
                self._draw_asset(f"char_ino_ghost_{variant}", x1 + mx, art_top, extra_scale=visual_scale)
            self._rect(
                x1 + w * 0.12, y1 + h * 0.47, x1 + w * 0.88, y1 + h * 0.57,
                fill="#f8f8fb", outline="#8b6ca8", width=2, radius=6
            )
            ghost_label, ghost_size = self._fit_text_box(
                "ESPRIT TRANSFÉRÉ • INCIBLABLE", w * 0.70, h * 0.07,
                start_size=8 if variant == "detail" else 6, min_size=5,
                weight="bold", max_lines=2
            )
            self._text(
                x1 + w * 0.50, y1 + h * 0.52, ghost_label,
                size=ghost_size, fill="#5b3a73", weight="bold", width=w * 0.70
            )
            # Réaffiche un contour propre après le voile blanc.
            self._rect(x1, y1, x2, y2, fill="", outline="#080808", width=3)

        if variant == "field":
            # 1.7.16 : vraie plaque de verre transparente FIXE. Aucun shader de
            # sélection, aucune ligne blanche ajoutée par-dessus : la réflexion
            # appartient exclusivement à cette texture de verre.
            self._draw_asset("card_glass_field", x1, y1, extra_scale=visual_scale)

        if owner in (1, 2):
            owner_color = BLUE if owner == 1 else RED
            self._rect(x1 + w * 0.25, y1 + h * 0.54, x1 + w * 0.75, y1 + h * 0.62, fill="#0b1018", outline=owner_color, width=2, radius=6)
            self._text(x1 + w * 0.50, y1 + h * 0.58, self._player_display_name(owner)[:10], size=8, fill=owner_color, weight="bold")

    # ------------------------------------------------------------------
    # Duel lifecycle and actions
    # ------------------------------------------------------------------
    def _launch_engine(self):
        self.current_screen = "duel"
        if hasattr(self, "audio"):
            self.audio.play_ingame_music(force=True)
            # Certains pilotes MCI ont besoin de quelques millisecondes pour
            # libérer la piste Taiko précédente. On effectue un second contrôle
            # non destructif juste après l'ouverture du duel.
            self.root.after(250, self._ensure_ingame_music)
        if self.current_mode and self.current_mode.id == "multiplayer":
            self._duel_started_network = True
        self.engine = GameEngine(
            deck1=self.draft_decks[1],
            deck2=self.draft_decks[2],
            starters1=self.starter_choices[1],
            starters2=self.starter_choices[2],
            starting_player=self.starting_player,
            seed=self.network_seed if self.current_mode and self.current_mode.id == "multiplayer" else None,
        )
        # Le combat classé devient officiel ici seulement : le draft/choix des
        # cartes est terminé et le vrai duel vient de commencer. Si le processus
        # est tué ensuite, RankedStore régularisera une défaite au prochain lancement.
        if self.multiplayer_match_type == "ranked" and self.ranked is not None and self.network_local_player in (1, 2):
            try:
                self.ranked.begin_match(
                    opponent_elo=normalize_elo(self.ranked_peer_elo),
                    own_stars=self._deck_star_total(int(self.network_local_player)),
                    opponent_stars=self._deck_star_total(2 if int(self.network_local_player) == 1 else 1),
                    match_id=str(self.network_room_code or self.network_seed or ""),
                )
            except Exception:
                pass
        self.selected_attacker_slot = None
        self.selected_style = None
        self.selected_special_mode = None
        self.inspected_enemy_slot = None
        self.turn_plan_free = None
        self.turn_plan_actions = []
        self.turn_plan_target_slot = None
        self.turn_commit_pending_end = False
        self.turn_commit_player = None
        self.turn_commit_queue = []
        self.turn_commit_delayed = None
        self.switch_select_slot = None
        self.ai_busy = False
        self.replacement_resume_ai = False
        self.notice = f"{self._player_display_name(self.starting_player)} commence. Les 3 Ninjas de départ sont déjà en jeu."
        self._consume_engine_visual_events()
        self.redraw()
        if self.current_mode and self.current_mode.id == "solo_ai" and self.engine.active_player == 2:
            self._pending_ai_job = self.root.after(650, self._start_ai_turn)

    def _ensure_ingame_music(self):
        if self.current_screen != "duel" or not hasattr(self, "audio"):
            return
        if not self.audio.music_is_active("ingame"):
            self.audio.play_ingame_music(force=True)

    def _active_is_human(self) -> bool:
        if not self.current_mode or not self.engine:
            return False
        return self._controller(self.engine.active_player) == "human"

    # ------------------------------------------------------------------
    # Classic 1.0.0 - planification du tour
    # ------------------------------------------------------------------
    def _reset_turn_plan(self):
        self.turn_plan_free = None
        self.turn_plan_actions = []
        self.turn_plan_target_slot = None
        self.selected_attacker_slot = None
        self.selected_style = None
        self.selected_special_mode = None
        self.inspected_enemy_slot = None
        self.switch_select_slot = None

    def _planned_immediate_switch(self):
        if self.turn_plan_actions and self.turn_plan_actions[0].get("kind") == "switch":
            return self.turn_plan_actions[0]
        return None

    def _planned_immediate_switch_for_slot(self, slot: int):
        action = self._planned_immediate_switch()
        if action and int(action.get("slot", -1)) == int(slot):
            return action
        return None

    def _planning_actor_for_slot(self, slot: int):
        """Carte visible pour planifier l'action suivante, y compris après un switch Action 1."""
        if not self.engine:
            return None, False
        player_number = self.engine.active_player
        switch = self._planned_immediate_switch_for_slot(slot)
        if switch:
            incoming_id = str(switch.get("incoming_id") or "")
            inst = self.engine.preview_reserve_instance(player_number, incoming_id)
            if inst is not None:
                return inst, True
        player = self.engine.player(player_number)
        if 0 <= slot < len(player.field):
            return player.field[slot], False
        return None, False

    def _planning_reserve_cards(self) -> list[CardDefinition]:
        if not self.engine:
            return []
        player = self.engine.player(self.engine.active_player)
        cards = list(player.deck)
        # Après un switch immédiat planifié, la réserve virtuelle a déjà perdu
        # la carte entrante et récupéré la carte sortante. Cela permet par ex.
        # de programmer ensuite un deuxième switch ou une attaque avec l'entrant.
        sw = self._planned_immediate_switch()
        if sw:
            incoming = str(sw.get("incoming_id") or "")
            outgoing = str(sw.get("outgoing_id") or "")
            cards = [c for c in cards if c.id != incoming]
            if not any(c.id == outgoing for c in cards):
                loc = self.engine._field_card_by_id(self.engine.active_player, outgoing)
                if loc is not None:
                    cards.append(loc[1].definition)
        return cards

    def _planned_special_count(self) -> int:
        # Conservé pour diagnostics/UI historiques. Depuis YUGITO06 R2, la
        # restriction n'est PLUS globale : A1 Ino spéciale + A2 Shikamaru
        # spéciale est volontairement légal car A2 part au tour suivant.
        return sum(1 for a in self.turn_plan_actions if a.get("kind") in {"special", "grave_special"})

    def _planned_special_for_actor(self, actor_id: str | None) -> bool:
        aid = str(actor_id or "")
        if not aid:
            return False
        return any(
            a.get("kind") in {"special", "grave_special"}
            and str(a.get("actor_id") or "") == aid
            for a in self.turn_plan_actions
        )

    def _plan_action_label(self, action: dict | None) -> str:
        if not self.engine or not action:
            return "—"
        return self.engine.action_description(action)

    def _plan_action(self, action: dict) -> bool:
        """Ajoute une décision sans produire le moindre effet de combat."""
        if not self.engine or self.engine.winner is not None:
            return False
        kind = str(action.get("kind") or "")
        actor_id = str(action.get("actor_id") or "")

        # Classic 1.1.3 : Hiraishin n'est plus aspiré automatiquement. Le joueur
        # choisit d'abord la case MINATO — GRATUIT, puis son art et sa cible.
        if self.turn_plan_target_slot == "free":
            actual_minato = self.engine._field_card_by_id(self.engine.active_player, "minato")
            if kind != "normal" or actor_id != "minato" or actual_minato is None:
                self.notice = "La case MINATO — GRATUIT accepte uniquement une attaque normale de Minato déjà sur le terrain."
                self.redraw()
                return False
            if self.turn_plan_free is not None:
                self.notice = "L'action gratuite de Minato est déjà préparée."
                self.turn_plan_target_slot = None
                self.redraw()
                return False
            planned = dict(action)
            planned["minato_free"] = True
            self.turn_plan_free = planned
            self.turn_plan_target_slot = None
            self.notice = "Hiraishin préparé. Minato peut encore attaquer en Action 1 et sa spéciale peut être programmée en Action 2."
            self.selected_attacker_slot = None
            self.selected_style = None
            self.selected_special_mode = None
            self.inspected_enemy_slot = None
            self.redraw()
            return True

        if bool(getattr(self.engine, "tobi_bomb_choice_required", {}).get(self.engine.active_player, False)):
            self.notice = "TOBI : place d'abord ta bombe secrète en cliquant une carte ennemie."
            self.redraw()
            return False

        if len(self.turn_plan_actions) >= 2:
            self.notice = "Tes deux actions sont déjà préparées. Annule une action ou valide le tour."
            self.redraw()
            return False

        if kind in {"special", "grave_special"} and self._planned_special_for_actor(actor_id):
            self.notice = "Ce Ninja a déjà sa technique spéciale prévue dans ce plan. Choisis un autre Ninja pour l'Action 2."
            self.redraw()
            return False

        # Classic 1.1.7 : Action 2 appartient à la prochaine VALIDATION ADVERSE. Le même Ninja
        # peut donc faire l'Action 1 maintenant et être programmé en attaque
        # normale en réaction au prochain tour adverse. La légalité réelle sera revérifiée
        # au déclenchement de l'ordre différé.

        planned = dict(action)
        if kind == "normal":
            # Important : même si l'acteur est Minato, une action placée ici est
            # une vraie Action 1/2 et doit donc consommer cette action.
            planned["minato_free"] = False
        self.turn_plan_actions.append(planned)
        idx = len(self.turn_plan_actions)
        when = "IMMÉDIATE À LA VALIDATION" if idx == 1 else "RÉACTIVE — VALIDATION ADVERSE"
        self.notice = f"Action {idx}/2 préparée — {when}. Rien ne se déclenche avant validation."
        self.selected_attacker_slot = None
        self.selected_style = None
        self.selected_special_mode = None
        self.inspected_enemy_slot = None
        self.redraw()
        return True

    def _select_minato_free_slot(self):
        """Arme explicitement la prochaine attaque normale de Minato comme Hiraishin."""
        if not self.engine or not self._active_is_human() or self.ai_busy or self.engine.winner is not None:
            return
        if self.turn_plan_free is not None:
            self.notice = "L'action gratuite de Minato est déjà préparée. Annule-la d'abord pour la modifier."
            self.redraw()
            return
        loc = self.engine._field_card_by_id(self.engine.active_player, "minato")
        if loc is None:
            self.notice = "Minato doit déjà être sur le terrain pour préparer Hiraishin."
            self.redraw()
            return
        slot, minato = loc
        self.turn_plan_target_slot = "free"
        self.selected_attacker_slot = int(slot)
        self.selected_style = None
        self.selected_special_mode = None
        self.inspected_enemy_slot = None
        self.notice = "HIRAISHIN sélectionné : choisis TAIJUTSU, NINJUTSU ou GENJUTSU, puis la cible. Cette frappe ne consommera ni Action 1 ni Action 2."
        self.redraw()

    def _cancel_planned_free(self):
        if self.turn_plan_free is not None or self.turn_plan_target_slot == "free":
            self.turn_plan_free = None
            self.turn_plan_target_slot = None
            self.selected_style = None
            self.selected_special_mode = None
            self.notice = "Action gratuite de Minato annulée."
            self.redraw()

    def _cancel_planned_action(self, index: int):
        if index < 0 or index >= len(self.turn_plan_actions):
            return
        removed = self.turn_plan_actions.pop(index)
        # Si l'action immédiate était un switch, l'action différée pouvait avoir
        # été préparée avec la carte virtuelle entrante : on l'annule aussi pour
        # ne jamais conserver un ordre incohérent.
        if index == 0 and removed.get("kind") == "switch" and self.turn_plan_actions:
            self.turn_plan_actions.clear()
            self.notice = "Action 1 annulée ; l'Action 2 dépendante a aussi été annulée."
        else:
            self.notice = f"Action {index + 1} annulée."
        self.selected_attacker_slot = None
        self.selected_style = None
        self.selected_special_mode = None
        self.redraw()

    def _cancel_current_action_selection(self):
        self.selected_attacker_slot = None
        self.selected_style = None
        self.selected_special_mode = None
        self.inspected_enemy_slot = None
        self.turn_plan_target_slot = None
        self.notice = "Sélection en cours annulée. Tes actions déjà préparées sont conservées."
        self.redraw()

    def _open_tactical_switch(self):
        if not self.engine or not self._active_is_human() or self.ai_busy:
            return
        if len(self.turn_plan_actions) >= 2:
            self.notice = "Tes deux actions sont déjà préparées."
            self.redraw()
            return
        if self.selected_attacker_slot is None:
            self.notice = "Sélectionne d'abord le Ninja du terrain que tu veux échanger, puis clique sur RÉSERVE."
            self.redraw()
            return
        actor, _virtual = self._planning_actor_for_slot(self.selected_attacker_slot)
        if actor is None:
            return
        reserve = self._planning_reserve_cards()
        if not reserve:
            self.notice = "Ta réserve est vide : aucun échange possible."
            self.redraw()
            return
        self.switch_select_slot = self.selected_attacker_slot
        self.current_screen = "switch_select"
        self.notice = f"Choisis librement la carte qui remplacera {actor.definition.name}."
        self.redraw()

    def choose_tactical_switch(self, incoming_id: str):
        if not self.engine or self.switch_select_slot is None:
            return
        slot = self.switch_select_slot
        actor, _virtual = self._planning_actor_for_slot(slot)
        if actor is None:
            self.current_screen = "duel"
            self.switch_select_slot = None
            self.redraw()
            return
        incoming = next((c for c in self._planning_reserve_cards() if c.id == incoming_id), None)
        if incoming is None:
            self.notice = "Cette carte n'est plus disponible dans la réserve."
            self.redraw()
            return
        action = {
            "kind": "switch",
            "outgoing_id": actor.definition.id,
            "outgoing_name": actor.definition.name,
            "incoming_id": incoming.id,
            "incoming_name": incoming.name,
            "slot": int(slot),
        }
        self.current_screen = "duel"
        self.switch_select_slot = None
        self._plan_action(action)

    def _cancel_tactical_switch(self):
        self.switch_select_slot = None
        self.current_screen = "duel"
        self.notice = "Échange annulé."
        self.redraw()

    def click_own_slot(self, slot: int):
        if not self.engine or self.engine.winner is not None or not self._active_is_human() or self.ai_busy:
            return
        if self.engine.pending_replacement is not None:
            return

        # Tobi 1.7.7 : après avoir choisi secrètement le Ninja ennemi,
        # le clic sur un allié termine la prédiction attaquant -> cible.
        if self.selected_special_mode == "tobi_ally" and self.selected_attacker_slot is not None:
            attacker, _virtual = self._planning_actor_for_slot(self.selected_attacker_slot)
            target, _ = self._planning_actor_for_slot(slot)
            if attacker is not None and target is not None and self.tobi_prediction_enemy_id:
                enemy = self.engine.opponent(self.engine.active_player)
                predicted = next((c for c in enemy.field if c is not None and c.definition.id == self.tobi_prediction_enemy_id), None)
                if predicted is not None:
                    action = {"kind":"special","actor_id":attacker.definition.id,"actor_name":attacker.definition.name,
                              "target_id":predicted.definition.id,"target_name":predicted.definition.name,
                              "target_slot":next((i for i,c in enumerate(enemy.field) if c is predicted),0),
                              "prediction_ally_id":target.definition.id,"prediction_ally_name":target.definition.name,
                              "copied":False,"special_name":attacker.definition.special_name}
                    self.tobi_prediction_enemy_id = None
                    self.selected_special_mode = None
                    self._plan_action(action)
                    return

        # Une spéciale alliée ciblée ne s'exécute plus ici : elle est seulement
        # inscrite dans le plan du tour.
        if self.selected_special_mode is not None and self.selected_attacker_slot is not None:
            copied = self.selected_special_mode == "copy"
            attacker, _virtual = self._planning_actor_for_slot(self.selected_attacker_slot)
            if attacker is not None:
                special_id = attacker.copied_special_id if copied else attacker.definition.id
                if self.engine.special_targets_ally_id(special_id):
                    target, _ = self._planning_actor_for_slot(slot)
                    if target is None:
                        return
                    action = {
                        "kind": "special",
                        "actor_id": attacker.definition.id,
                        "actor_name": attacker.definition.name,
                        "target_id": target.definition.id,
                        "target_name": target.definition.name,
                        "target_slot": int(slot),
                        "copied": copied,
                        "special_name": attacker.copied_special_name if copied else attacker.definition.special_name,
                    }
                    self._plan_action(action)
                    return

        card, virtual = self._planning_actor_for_slot(slot)
        if card is not None:
            if self.turn_plan_target_slot == "free" and (virtual or card.definition.id != "minato"):
                # Cliquer un autre Ninja signifie que le joueur revient à la
                # préparation normale d'Action 1/2.
                self.turn_plan_target_slot = None
            self.selected_attacker_slot = slot
            self.selected_style = None
            self.selected_special_mode = None
            self.inspected_enemy_slot = None
            status = self.engine.status_text(card)
            if virtual:
                self.notice = f"{card.definition.name} est prévu après le switch immédiat — tu peux préparer son action différée."
            elif self.engine.is_disabled(card):
                self.notice = f"{card.definition.name} est sélectionné mais actuellement inutilisable. {status}"
            else:
                self.notice = f"{card.definition.name} sélectionné — choisis un art, sa spéciale ou la RÉSERVE pour un échange."
            self.redraw()

    def select_style(self, style: str):
        if not self.engine or self.selected_attacker_slot is None or not self._active_is_human() or self.ai_busy:
            return
        if self.engine.pending_replacement is not None:
            return
        card, _virtual = self._planning_actor_for_slot(self.selected_attacker_slot)
        if card is None:
            return
        if not self.engine.can_use_style(card, style):
            if self.engine.is_disabled(card):
                self.notice = f"{card.definition.name} est actuellement inutilisable."
            elif card.definition.stat(style) == 0:
                self.notice = f"{card.definition.name} possède 0 en {STYLE_LABELS[style]} : cet art est impossible."
            elif card.blocked_styles.get(style, 0) > 0:
                self.notice = f"{STYLE_LABELS[style]} est bloqué pour {card.definition.name}."
            else:
                self.notice = f"{card.definition.name} ne peut pas préparer cet art."
            self.redraw()
            return
        self.selected_style = style
        self.selected_special_mode = None
        enemy = self.engine.opponent()
        if any(c is not None for c in enemy.field):
            self.notice = f"{STYLE_LABELS[style]} choisi — clique maintenant un Ninja adverse. Rien ne sera exécuté avant validation."
        else:
            self.notice = f"{STYLE_LABELS[style]} choisi — l'attaque directe peut être préparée."
        self.redraw()

    def select_special(self, copied: bool = False):
        if not self.engine or self.selected_attacker_slot is None or not self._active_is_human() or self.ai_busy:
            return
        if self.turn_plan_target_slot == "free":
            self.notice = "Hiraishin gratuit est une attaque normale uniquement. Annule/termine cette sélection pour programmer le Rasengan en Action 1 ou Action 2."
            self.redraw()
            return
        if self.engine.pending_replacement is not None:
            return
        card, _virtual = self._planning_actor_for_slot(self.selected_attacker_slot)
        if card is None:
            return
        if not self.engine.special_available(card, copied=copied):
            self.notice = "Cette technique spéciale n'est pas disponible."
            self.redraw()
            return
        if self._planned_special_for_actor(card.definition.id):
            self.notice = "Ce Ninja a déjà sa technique spéciale prévue. Un autre Ninja peut encore programmer la sienne en Action 2."
            self.redraw()
            return

        mode = "copy" if copied else "own"
        special_id = card.copied_special_id if copied else card.definition.id
        special_name = card.copied_special_name if copied else card.definition.special_name
        if not self.engine.special_requires_target(card, copied=copied):
            if special_id == "ao":
                enemy = self.engine.opponent(self.engine.active_player)
                if not enemy.deck:
                    self.notice = "La réserve ennemie est vide : Byakugan dérobé n'a aucune carte à traquer."
                    self.redraw()
                    return
                self.grave_select_context = {
                    "mode": "tracker", "player": self.engine.active_player, "attacker_slot": self.selected_attacker_slot,
                    "actor_id": card.definition.id, "actor_name": card.definition.name, "copied": copied,
                    "planning": True, "partial_action": {"kind":"special","actor_id":card.definition.id,"actor_name":card.definition.name,"target_id":None,"copied":copied,"special_name":special_name},
                }
                self.current_screen = "grave_select"
                self.notice = "Byakugan : choisis la carte de réserve adverse qui devra obligatoirement entrer."
                self.redraw()
                return
            if special_id == "orochimaru":
                enemy = self.engine.opponent(self.engine.active_player)
                if not enemy.graveyard:
                    self.notice = "Le cimetière ennemi est vide : Réincarnation des âmes ne peut pas être préparée."
                    self.redraw()
                    return
                self.grave_select_context = {
                    "player": self.engine.active_player,
                    "attacker_slot": self.selected_attacker_slot,
                    "actor_id": card.definition.id,
                    "actor_name": card.definition.name,
                    "copied": copied,
                    "planning": True,
                }
                self.current_screen = "grave_select"
                self.notice = "Choisis maintenant la carte du cimetière à associer à l'action programmée d'Orochimaru."
                self.redraw()
                return
            action = {
                "kind": "special",
                "actor_id": card.definition.id,
                "actor_name": card.definition.name,
                "target_id": None,
                "copied": copied,
                "special_name": special_name,
            }
            self._plan_action(action)
            return

        self.selected_style = None
        self.selected_special_mode = mode
        if self.engine.special_targets_ally_id(special_id):
            self.notice = f"{special_name} sélectionnée — clique une carte alliée. Rien ne part avant validation."
        else:
            self.notice = f"{special_name} sélectionnée — clique une carte ennemie. Rien ne part avant validation."
        self.redraw()

    def _handle_pending_replacement(self) -> bool:
        """Traite les remplacements IA en chaîne et ouvre l'écran pour un humain."""
        if not self.engine:
            return False
        while self.engine.pending_replacement is not None:
            offer = self.engine.pending_replacement
            controller = self._controller(offer.player_number)
            if controller == "ai":
                chosen = self.engine.ai_choose_replacement(offer.player_number)
                if chosen is None:
                    break
                self.engine.choose_replacement(offer.player_number, chosen.id)
                self.notice = f"L'IA remplace automatiquement par {chosen.name}."
                continue

            self.replacement_resume_ai = bool(
                self.current_mode
                and self.current_mode.id == "solo_ai"
                and self.engine.active_player == 2
            )
            self.current_screen = "replacement"
            self.redraw()
            return True
        return False

    def click_enemy_slot(self, slot: int):
        if not self.engine or self.engine.winner is not None or not self._active_is_human() or self.ai_busy:
            return

        # Tobi : la pose de bombe est obligatoire au début de son tour et reste
        # totalement secrète pour l'adversaire.
        if bool(getattr(self.engine, "tobi_bomb_choice_required", {}).get(self.engine.active_player, False)):
            enemy = self.engine.opponent(self.engine.active_player)
            target = enemy.field[slot] if 0 <= slot < len(enemy.field) else None
            if target is not None:
                ok, msg = self.engine.place_tobi_bomb(self.engine.active_player, slot)
                self.notice = msg
                self.redraw()
            return

        if self.selected_special_mode is None and self.selected_style is None:
            enemy = self.engine.opponent(self.engine.active_player)
            card = enemy.field[slot]
            if card is None:
                return
            self.inspected_enemy_slot = slot
            self.selected_attacker_slot = None
            self.notice = f"Inspection : {card.definition.name}."
            self.redraw()
            return

        if self.selected_attacker_slot is None:
            self.notice = "Sélectionne d'abord ton Ninja."
            self.redraw()
            return

        attacker, _virtual = self._planning_actor_for_slot(self.selected_attacker_slot)
        if attacker is None:
            return
        enemy = self.engine.opponent(self.engine.active_player)
        target = enemy.field[slot]
        if target is None:
            return

        if self.selected_special_mode is not None:
            copied = self.selected_special_mode == "copy"
            special_id = attacker.copied_special_id if copied else attacker.definition.id
            if special_id == "tobi" and not copied:
                self.tobi_prediction_enemy_id = target.definition.id
                self.selected_special_mode = "tobi_ally"
                self.notice = f"C'était prévu ! — {target.definition.name} est l'attaquant prédit. Clique maintenant le Ninja ALLIÉ qu'il devrait attaquer."
                self.redraw()
                return
            action = {
                "kind": "special",
                "actor_id": attacker.definition.id,
                "actor_name": attacker.definition.name,
                "target_id": target.definition.id,
                "target_name": target.definition.name,
                "target_slot": int(slot),
                "copied": copied,
                "special_name": attacker.copied_special_name if copied else attacker.definition.special_name,
            }
            special_id = attacker.copied_special_id if copied else attacker.definition.id
            if special_id in {"neji", "hinata"}:
                reserve = self.engine.opponent(self.engine.active_player).deck
                if reserve:
                    self.grave_select_context = {"mode":"tracker","player":self.engine.active_player,"planning":True,"partial_action":action}
                    self.current_screen = "grave_select"
                    self.selected_special_mode = None
                    self.notice = "Byakugan : choisis maintenant la carte de réserve adverse à traquer."
                    self.redraw()
                    return
        else:
            action = {
                "kind": "normal",
                "actor_id": attacker.definition.id,
                "actor_name": attacker.definition.name,
                "target_id": target.definition.id,
                "target_name": target.definition.name,
                "target_slot": int(slot),
                "style": self.selected_style,
            }
        self._plan_action(action)

    def direct_attack(self):
        if not self.engine or self.selected_attacker_slot is None or self.selected_style is None:
            return
        if self.selected_special_mode is not None:
            return
        if not self._active_is_human() or self.ai_busy or self.engine.pending_replacement is not None:
            return
        attacker, _virtual = self._planning_actor_for_slot(self.selected_attacker_slot)
        if attacker is None:
            return
        if any(c is not None for c in self.engine.opponent(self.engine.active_player).field):
            self.notice = "Une attaque directe n'est possible que si le terrain adverse est vide."
            self.redraw()
            return
        action = {
            "kind": "normal",
            "actor_id": attacker.definition.id,
            "actor_name": attacker.definition.name,
            "target_id": None,
            "style": self.selected_style,
        }
        self._plan_action(action)

    def choose_replacement(self, card_id: str):
        if not self.engine or self.engine.pending_replacement is None:
            return
        player_number = self.engine.pending_replacement.player_number
        if self.current_mode and self.current_mode.id == "multiplayer" and self._controller(player_number) != "human":
            self.notice = f"{self._player_display_name(player_number)} choisit son remplaçant sur l’autre PC."
            self.redraw()
            return
        resume_ai = self.replacement_resume_ai
        ok, msg = self.engine.choose_replacement(player_number, card_id)
        self.notice = msg
        if not ok:
            self.redraw()
            return
        if self.current_mode and self.current_mode.id == "multiplayer":
            self._net_send({"type": "replacement", "player": player_number, "card_id": card_id})

        if self.engine.pending_replacement is not None:
            if self._handle_pending_replacement():
                return

        self.replacement_resume_ai = False
        self.current_screen = "duel"
        if self.turn_commit_pending_end and self.engine.pending_replacement is None:
            self._continue_committed_turn()
            return
        self.redraw()
        if resume_ai and self.engine.winner is None and self.engine.pending_replacement is None:
            self._pending_ai_job = self.root.after(550, self._ai_attack_step)


    def choose_grave_card(self, grave_index: int):
        if not self.engine or not self.grave_select_context:
            return
        ctx = self.grave_select_context
        player = int(ctx["player"])
        enemy = self.engine.opponent(player)
        if ctx.get("mode") == "tracker":
            cards = list(enemy.deck)
            if grave_index < 0 or grave_index >= len(cards):
                return
            chosen = cards[grave_index]
            action = dict(ctx.get("partial_action") or {})
            action["tracker_id"] = chosen.id
            action["tracker_name"] = chosen.name
            self.grave_select_context = None
            self.current_screen = "duel"
            self._plan_action(action)
            return
        if grave_index < 0 or grave_index >= len(enemy.graveyard):
            return
        chosen = enemy.graveyard[grave_index]

        # Classic 1.0.0 : Orochimaru est désormais planifié comme les autres
        # actions. La carte du cimetière est mémorisée par ID et ne sera volée
        # qu'au moment réel de l'exécution.
        if ctx.get("planning"):
            action = {
                "kind": "grave_special",
                "actor_id": str(ctx.get("actor_id") or "orochimaru"),
                "actor_name": str(ctx.get("actor_name") or "Orochimaru"),
                "grave_card_id": chosen.id,
                "grave_card_name": chosen.name,
                "copied": bool(ctx.get("copied", False)),
                "special_name": "Réincarnation des âmes",
            }
            self.grave_select_context = None
            self.current_screen = "duel"
            self._plan_action(action)
            return

        # Compatibilité avec les anciens appels réseau/IA éventuels.
        resume_ai = bool(self.current_mode and self.current_mode.id == "solo_ai" and self.engine.active_player == 2)
        ok, msg = self.engine.steal_from_enemy_graveyard(
            player, int(ctx.get("attacker_slot", -1)), grave_index, copied=ctx.get("copied", False),
        )
        self.notice = msg
        if not ok:
            self.redraw()
            return
        if self.current_mode and self.current_mode.id == "multiplayer":
            self._net_send({
                "type": "grave_card", "player": player, "attacker_slot": int(ctx.get("attacker_slot", -1)),
                "grave_index": grave_index, "copied": bool(ctx.get("copied", False)),
            })
        self._consume_engine_visual_events()
        self.audio.play_special("orochimaru")
        self.grave_select_context = None
        self.current_screen = "duel"
        self.selected_attacker_slot = None
        self.selected_style = None
        self.selected_special_mode = None
        self.redraw()
        if resume_ai and self.engine.winner is None and self.engine.pending_replacement is None:
            self._pending_ai_job = self.root.after(550, self._ai_attack_step)

    def _draw_switch_select(self):
        self._gradient_background("#0d141f", "#05080d")
        if not self.engine or self.switch_select_slot is None:
            self.current_screen = "duel"
            self.redraw()
            return
        actor, virtual = self._planning_actor_for_slot(self.switch_select_slot)
        if actor is None:
            self._cancel_tactical_switch()
            return
        cards = self._planning_reserve_cards()
        self._text(800, 68, "ÉCHANGE TACTIQUE", size=28, weight="bold", family=DISPLAY_FONT_TOKEN)
        self._text(800, 108, f"REMPLACER {actor.definition.name.upper()} — CHOISIS LIBREMENT DANS TA RÉSERVE", size=14, fill=GREEN, weight="bold")
        self._text(800, 140, "L'échange compte comme une action. En Action 2, il se déclenche à la prochaine validation adverse, avant ses actions.", size=10, fill=MUTED)
        if virtual:
            self._text(800, 165, "Cette carte est virtuelle : elle doit d'abord entrer via ton Action 1.", size=9, fill=GOLD)
        self._button(1370, 42, 1545, 82, "↩ ANNULER", self._cancel_tactical_switch, fill="#1c1720", accent=RED, small=True)

        if not cards:
            self._text(800, 420, "RÉSERVE VIDE", size=24, fill=MUTED, weight="bold")
            return
        cols = 4
        gap_x, gap_y = 30, 34
        cw, ch = DRAFT_CARD_W, DRAFT_CARD_H
        total_w = min(cols, len(cards)) * cw + max(0, min(cols, len(cards)) - 1) * gap_x
        start_x = (1600 - total_w) / 2
        start_y = 205
        for i, card in enumerate(cards):
            row, col = divmod(i, cols)
            row_count = min(cols, len(cards) - row * cols)
            row_total = row_count * cw + max(0, row_count - 1) * gap_x
            row_x = (1600 - row_total) / 2
            x = row_x + col * (cw + gap_x)
            y = start_y + row * (ch + 78 + gap_y)
            inst = self.engine.reserve_instance(self.engine.active_player, card.id)
            # Cas spécial : la carte sortante du switch Action 1 est dans la
            # réserve virtuelle mais pas encore physiquement dans reserve_instances.
            sw = self._planned_immediate_switch()
            if inst is None and sw and str(sw.get("outgoing_id")) == card.id:
                loc = self.engine._field_card_by_id(self.engine.active_player, card.id)
                if loc is not None:
                    inst = loc[1]
            hp = int(inst.current_hp) if inst is not None else card.max_hp
            self._draw_card(card, x, y, "draft", current_hp=hp, instance=inst)
            self._button(x, y + ch + 14, x + cw, y + ch + 54, "CHOISIR", lambda cid=card.id: self.choose_tactical_switch(cid), fill="#18261f", accent=GREEN, small=True)

    def _draw_grave_select(self):
        self._gradient_background("#0d141f", "#05080d")
        if not self.engine or not self.grave_select_context:
            self.current_screen = "duel"
            self.redraw()
            return
        ctx = self.grave_select_context
        player = int(ctx["player"])
        enemy = self.engine.opponent(player)
        tracker_mode = ctx.get("mode") == "tracker"
        source_cards = list(enemy.deck) if tracker_mode else list(enemy.graveyard)
        if not source_cards:
            self.grave_select_context = None
            self.current_screen = "duel"
            self.notice = "La réserve ennemie est vide." if tracker_mode else "Le cimetière ennemi est vide."
            self.redraw()
            return

        accent = BLUE if player == 1 else RED
        self._text(800, 70, "BYAKUGAN — TRAQUEUR" if tracker_mode else "RÉINCARNATION DES ÂMES", size=28, weight="bold", family=DISPLAY_FONT_TOKEN)
        self._text(800, 112, f"JOUEUR {player} — CHOISIS LA PROCHAINE CARTE ADVERSE À ENTRER" if tracker_mode else f"JOUEUR {player} — CHOISIS UNE CARTE DANS LE CIMETIÈRE ENNEMI", size=15, fill=accent, weight="bold")
        self._text(800, 145, "Cette carte sera imposée au prochain switch ou remplacement adverse." if tracker_mode else "La carte volée quitte définitivement le cimetière adverse et rejoint ta réserve cachée.", size=11, fill=MUTED)
        self._button(1385, 42, 1548, 78, "ANNULER", lambda: self._cancel_grave_select(), fill="#151d29", accent="#7b5860", small=True)

        cards = source_cards
        cols = 4
        gap_x, gap_y = 26, 30
        card_w, card_h = DRAFT_CARD_W, DRAFT_CARD_H
        total_w = cols * card_w + (cols - 1) * gap_x
        start_x = (1600 - total_w) / 2
        start_y = 190
        for i, card in enumerate(cards):
            row, col = divmod(i, cols)
            x = start_x + col * (card_w + gap_x)
            y = start_y + row * (card_h + 88)
            self._draw_card(card, x, y, "draft")
            label = "TRAQUER CETTE CARTE" if tracker_mode else "VOLER CETTE CARTE"
            self._button(x, y + card_h + 16, x + card_w, y + card_h + 56, label, lambda idx=i: self.choose_grave_card(idx), fill="#18261f", accent=accent, small=True)


    def _cancel_grave_select(self):
        self.grave_select_context = None
        self.current_screen = "duel"
        self.notice = "Sélection de cimetière annulée."
        self.redraw()

    def _begin_committed_turn(self, player: int, free_action: dict | None, actions: list[dict], *, remote: bool = False):
        """Verrouille le plan puis résout uniquement ce qui doit partir maintenant."""
        if not self.engine or self.engine.active_player != player or self.engine.winner is not None:
            return
        self.turn_commit_pending_end = True
        self.turn_commit_player = player
        self._reactive_switch_checked_169 = False
        self.turn_commit_queue = []
        if isinstance(free_action, dict):
            self.turn_commit_queue.append(dict(free_action))
        if actions:
            self.turn_commit_queue.append(dict(actions[0]))
        self.turn_commit_delayed = dict(actions[1]) if len(actions) > 1 else None
        self.selected_attacker_slot = None
        self.selected_style = None
        self.selected_special_mode = None
        self.inspected_enemy_slot = None
        self.notice = "Tour validé : résolution des actions…"
        self._continue_committed_turn()

    def _continue_committed_turn(self):
        if not self.engine or not self.turn_commit_pending_end:
            return
        player = self.turn_commit_player
        if player not in (1, 2) or self.engine.active_player != player:
            self.turn_commit_pending_end = False
            self.turn_commit_queue = []
            self.turn_commit_delayed = None
            return
        if self.engine.winner is not None:
            self.turn_commit_pending_end = False
            self.turn_commit_queue = []
            self.turn_commit_delayed = None
            self._reset_turn_plan()
            self.redraw()
            return
        if self.engine.pending_replacement is not None:
            if self._handle_pending_replacement():
                return

        # 1.6.9 — juste au moment où le joueur finalise son plan, toute A2
        # adverse en attente se résout AVANT Hiraishin et l'Action 1 courante.
        # Une attaque déjà préparée conserve sa case cible et peut donc frapper
        # immédiatement le Ninja entrant (fenêtre de contre-switch).
        if not getattr(self, "_reactive_switch_checked_169", False):
            self._reactive_switch_checked_169 = True
            self.engine.resolve_reactive_a2_before_actions(player)
            self._consume_engine_visual_events()
            if self.engine.pending_replacement is not None and self._handle_pending_replacement():
                return

        while self.turn_commit_queue and self.engine.winner is None and self.engine.pending_replacement is None:
            action = self.turn_commit_queue.pop(0)
            ok, msg = self.engine.execute_action_descriptor(player, action, preserve_turn_budget=False)
            self.notice = msg
            self._consume_engine_visual_events()
            if not ok:
                self.engine.log_event(msg or "Une action préparée n'a pas pu être exécutée.")
                # Si le switch immédiat a échoué, un ordre différé qui dépendait
                # de la carte censée entrer n'a plus de source valide.
                if action.get("kind") == "switch" and self.turn_commit_delayed:
                    incoming = str(action.get("incoming_id") or "")
                    if str(self.turn_commit_delayed.get("actor_id") or self.turn_commit_delayed.get("outgoing_id") or "") == incoming:
                        self.engine.log_event("Action programmée annulée : elle dépendait d'un échange immédiat qui a échoué.")
                        self.turn_commit_delayed = None
            if self.engine.pending_replacement is not None:
                if self._handle_pending_replacement():
                    return

        if self.engine.winner is not None:
            self.turn_commit_pending_end = False
            self.turn_commit_queue = []
            self.turn_commit_delayed = None
            self._reset_turn_plan()
            self.redraw()
            return

        # Une fois les effets immédiats terminés, l'Action 2 devient l'ordre réactif
        # qui attend la prochaine validation adverse. Elle n'est jamais exécutée maintenant.
        self.engine.set_delayed_action(player, self.turn_commit_delayed)
        self.turn_commit_delayed = None
        self.turn_commit_pending_end = False
        self.turn_commit_player = None
        self.turn_commit_queue = []
        self._reactive_switch_checked_169 = False
        self._reset_turn_plan()

        old_player = player
        self.engine.end_turn()
        self._consume_engine_visual_events()
        if self.current_mode and self.current_mode.id == "solo_ai" and old_player == 2:
            self.ai_busy = False
        self.notice = f"Tour de {self._player_display_name(self.engine.active_player)}."
        # L'action différée du nouveau joueur peut avoir provoqué un K.O. et
        # donc un choix de remplacement avant même sa phase de planification.
        if self._handle_pending_replacement():
            return
        self.current_screen = "duel"
        self.redraw()
        if self.current_mode and self.current_mode.id == "solo_ai" and self.engine.winner is None and self.engine.active_player == 2:
            self._start_ai_turn()

    def end_turn(self):
        """Classic 1.0.0 : valide le plan complet, puis seulement les effets partent."""
        if self._auto_end_job:
            try:
                self.root.after_cancel(self._auto_end_job)
            except Exception:
                pass
            self._auto_end_job = None
        if not self.engine or self.engine.winner is not None or self.ai_busy or not self._active_is_human():
            return
        if self.engine.pending_replacement is not None or self.turn_commit_pending_end:
            return
        player = self.engine.active_player
        free = dict(self.turn_plan_free) if self.turn_plan_free else None
        actions = [dict(a) for a in self.turn_plan_actions[:2]]
        if self.current_mode and self.current_mode.id == "multiplayer":
            self._net_send({"type": "turn_plan_commit", "player": player, "free": free, "actions": actions})
        self._begin_committed_turn(player, free, actions, remote=False)

    def restart_duel(self):
        if self.current_mode and self.current_mode.id == "multiplayer":
            if self.network_lobby_role == "host" and self.network.connected:
                self._start_multiplayer_standard_host()
            else:
                self.notice = "L'hôte doit lancer la revanche."
                self.redraw()
            return
        if self.current_mode:
            self.start_duel(self.current_mode)

    # ------------------------------------------------------------------
    # Basic duel AI
    # ------------------------------------------------------------------
    def _start_ai_turn(self):
        self._pending_ai_job = None
        if not self.engine or self.engine.winner is not None:
            return
        self.ai_busy = True
        self.notice = "L'IA réfléchit…"
        self.redraw()
        self._pending_ai_job = self.root.after(550, self._ai_attack_step)

    def _ai_attack_step(self):
        self._pending_ai_job = None
        if not self.engine or self.engine.winner is not None or self.engine.active_player != 2:
            self.ai_busy = False
            self.redraw()
            return
        if self.engine.pending_replacement is not None:
            if self._handle_pending_replacement():
                return

        player = self.engine.player(2)
        enemy = self.engine.opponent(2)
        free = None
        actions: list[dict] = []

        # Minato : son premier coup normal du cycle est gratuit.
        minato_loc = self.engine._field_card_by_id(2, "minato")
        if minato_loc is not None:
            _slot, minato = minato_loc
            legal_styles = [s for s in STYLE_LABELS if self.engine.can_use_style(minato, s)]
            targets = [c for c in enemy.field if c is not None]
            if legal_styles:
                style = max(legal_styles, key=lambda s: self.engine.effective_stat(minato, s))
                target = min(targets, key=lambda c: int(c.current_hp or 0)) if targets else None
                free = {
                    "kind": "normal", "actor_id": "minato", "actor_name": minato.definition.name,
                    "style": style, "target_id": target.definition.id if target else None,
                    "target_name": target.definition.name if target else None,
                    "target_slot": (enemy.field.index(target) if target in enemy.field else None) if target else None,
                    "minato_free": True,
                }

        # L'IA utilise parfois un switch immédiat pour sauver une carte très faible.
        weak = [
            (slot, c) for slot, c in enumerate(player.field)
            if c is not None and int(c.current_hp or 0) / max(1, c.definition.max_hp) <= 0.30
        ]
        if weak and player.deck and self.random.random() < 0.55:
            slot, outgoing = min(weak, key=lambda item: int(item[1].current_hp or 0) / max(1, item[1].definition.max_hp))
            incoming = max(player.deck, key=lambda c: c.max_hp + max(c.taijutsu, c.ninjutsu, c.genjutsu) + c.stars * 50)
            actions.append({
                "kind": "switch", "outgoing_id": outgoing.definition.id, "outgoing_name": outgoing.definition.name,
                "incoming_id": incoming.id, "incoming_name": incoming.name, "slot": slot,
            })

        if not actions:
            special_choice = self.engine.ai_choose_special(2)
            if special_choice:
                slot, target_slot, copied = special_choice
                attacker = player.field[slot]
                if attacker is not None:
                    special_id = attacker.copied_special_id if copied else attacker.definition.id
                    # Orochimaru choisit directement la meilleure carte du cimetière.
                    if special_id == "orochimaru" and enemy.graveyard:
                        chosen = max(enemy.graveyard, key=lambda c: c.stars * 100 + c.max_hp + c.taijutsu + c.ninjutsu + c.genjutsu)
                        actions.append({
                            "kind": "grave_special", "actor_id": attacker.definition.id,
                            "actor_name": attacker.definition.name, "grave_card_id": chosen.id,
                            "grave_card_name": chosen.name, "copied": copied,
                            "special_name": attacker.copied_special_name if copied else attacker.definition.special_name,
                        })
                    else:
                        target_id = None
                        target_name = None
                        if target_slot is not None:
                            target_side = player if self.engine.special_targets_ally_id(special_id) else enemy
                            if 0 <= target_slot < len(target_side.field) and target_side.field[target_slot] is not None:
                                target_id = target_side.field[target_slot].definition.id
                                target_name = target_side.field[target_slot].definition.name
                        actions.append({
                            "kind": "special", "actor_id": attacker.definition.id, "actor_name": attacker.definition.name,
                            "target_id": target_id, "target_name": target_name, "target_slot": target_slot, "copied": copied,
                            "special_name": attacker.copied_special_name if copied else attacker.definition.special_name,
                        })

        if not actions:
            choice = self.engine.ai_choose_attack(2)
            if choice:
                slot, style, target_slot = choice
                attacker = player.field[slot]
                target = enemy.field[target_slot] if target_slot is not None and 0 <= target_slot < 3 else None
                if attacker is not None:
                    actions.append({
                        "kind": "normal", "actor_id": attacker.definition.id, "actor_name": attacker.definition.name,
                        "style": style, "target_id": target.definition.id if target else None,
                        "target_name": target.definition.name if target else None,
                        "target_slot": target_slot,
                        "minato_free": False,
                    })

        # Action 2 : elle sera réellement jouée à la prochaine validation du joueur, avant ses actions.
        # Depuis 1.1.7 le même Ninja peut être programmé : l'Action 1 et l'Action 2
        # n'appartiennent pas au même tour réel.
        used_normal_actor = None
        if len(actions) < 2:
            candidates = []
            switch_out = actions[0].get("outgoing_id") if actions and actions[0].get("kind") == "switch" else None
            for slot, card in enumerate(player.field):
                if card is None or card.definition.id in {used_normal_actor, switch_out}:
                    continue
                for style in STYLE_LABELS:
                    if self.engine.can_use_style(card, style):
                        candidates.append((self.engine.effective_stat(card, style), card, style))
            # Si l'Action 1 est un switch, l'IA peut déjà programmer l'Action 2
            # avec la carte qui va entrer, comme un joueur humain.
            if actions and actions[0].get("kind") == "switch":
                incoming_preview = self.engine.preview_reserve_instance(2, str(actions[0].get("incoming_id") or ""))
                if incoming_preview is not None:
                    for style in STYLE_LABELS:
                        if self.engine.can_use_style(incoming_preview, style):
                            candidates.append((self.engine.effective_stat(incoming_preview, style), incoming_preview, style))
            if candidates:
                _score, attacker, style = max(candidates, key=lambda x: x[0])
                targets = [c for c in enemy.field if c is not None]
                target = min(targets, key=lambda c: int(c.current_hp or 0)) if targets else None
                actions.append({
                    "kind": "normal", "actor_id": attacker.definition.id, "actor_name": attacker.definition.name,
                    "style": style, "target_id": target.definition.id if target else None,
                    "target_name": target.definition.name if target else None,
                    "target_slot": (enemy.field.index(target) if target in enemy.field else None) if target else None,
                    "minato_free": False,
                })

        self.notice = "L'IA a terminé son plan. Résolution…"
        self._begin_committed_turn(2, free, actions, remote=False)
        # _continue_committed_turn relancera le flux ou repassera la main à J1.
        if self.engine and self.engine.active_player != 2:
            self.ai_busy = False

    # ------------------------------------------------------------------
    # Replacement selection
    # ------------------------------------------------------------------
    def _draw_replacement(self):
        self._gradient_background("#0d141f", "#05080d")
        if not self.engine or not self.engine.pending_replacement:
            self.current_screen = "duel"
            self.redraw()
            return
        offer = self.engine.pending_replacement
        player = offer.player_number
        accent = BLUE if player == 1 else RED

        self._text(800, 75, "REMPLACEMENT OBLIGATOIRE", size=32, weight="bold", family=DISPLAY_FONT_TOKEN)
        self._text(800, 125, f"JOUEUR {player} — UN NINJA EST TOMBÉ", size=17, fill=accent, weight="bold")
        self._text(800, 160, f"3 cartes maximum ont été tirées au hasard de ta réserve cachée. Choisis celle qui prendra l'emplacement {offer.slot + 1}.", size=11, fill=MUTED)

        if self.current_mode and self.current_mode.id == "multiplayer" and self._controller(player) != "human":
            self._rect(390, 250, 1210, 650, fill="#0f1621", outline=accent, width=3, radius=28)
            self._text(800, 350, f"{self._player_display_name(player).upper()} CHOISIT SON REMPLAÇANT", size=28, fill=accent, weight="bold", family=DISPLAY_FONT_TOKEN)
            self._text(800, 420, "Le choix de sa réserve reste privé sur son PC.", size=13, fill=MUTED)
            self._text(800, 500, "EN ATTENTE…", size=22, fill=GOLD, weight="bold")
            return

        count = len(offer.options)
        card_w = 280
        gap = 80
        total = count * card_w + max(0, count - 1) * gap
        start_x = (1600 - total) / 2
        y = 220
        for i, card in enumerate(offer.options):
            x = start_x + i * (card_w + gap)
            self._draw_card(card, x, y, "detail")
            self._add_click(x, y, x + card_w, y + 420, lambda c=card: self._open_card_reader(c))
            self._button(x, 660, x + card_w, 720, "CHOISIR CE NINJA", lambda cid=card.id: self.choose_replacement(cid), fill="#18261f", accent=accent, small=True)

        self._rect(400, 770, 1200, 835, fill="#111925", outline="#2d3b50", width=1, radius=12)
        self._text(800, 802, "Les cartes non choisies retournent dans la réserve. Le remplaçant arrive avec tous ses PV.", size=11, fill="#cfd7e2")

    def show_duel_info(self):
        if not self.engine:
            return
        self.current_screen = "duel_info"
        self.redraw()

    def _draw_duel_info(self):
        self._gradient_background("#111827", "#070b11")
        if not self.engine:
            self.current_screen = "duel"
            self.redraw()
            return
        p1 = self.engine.player(1)
        p2 = self.engine.player(2)
        self._rect(60, 35, 1540, 865, fill="#0e1520", outline="#2d3b50", width=2, radius=22)
        self._text(90, 78, "JOURNAL DU DUEL", size=30, weight="bold", anchor="w", family=DISPLAY_FONT_TOKEN)
        self._button(1355, 55, 1510, 95, "RETOUR AU DUEL", self._return_to_duel, fill="#151d29", accent=ACCENT, small=True)

        self._text(95, 135, "INFORMATIONS PUBLIQUES", size=13, fill=GREEN, weight="bold", anchor="w")
        self._rect(90, 160, 735, 315, fill="#121b28", outline="#314158", width=1, radius=14)
        self._text(120, 190, self._player_display_name(1).upper(), size=15, fill=BLUE, weight="bold", anchor="w", family=DISPLAY_FONT_TOKEN)
        self._text(120, 225, f"PV joueur : {p1.hp} / 4000", size=11, fill="#dce4ee", anchor="w")
        self._text(120, 255, f"Réserve cachée : {len(p1.deck)} carte(s)", size=11, fill="#dce4ee", anchor="w")
        self._text(120, 285, f"Cimetière : {len(p1.graveyard)} carte(s)", size=11, fill="#dce4ee", anchor="w")

        self._rect(865, 160, 1510, 315, fill="#121b28", outline="#314158", width=1, radius=14)
        self._text(895, 190, self._player_display_name(2).upper(), size=15, fill=RED, weight="bold", anchor="w", family=DISPLAY_FONT_TOKEN)
        self._text(895, 225, f"PV joueur : {p2.hp} / 4000", size=11, fill="#dce4ee", anchor="w")
        self._text(895, 255, f"Réserve cachée : {len(p2.deck)} carte(s)", size=11, fill="#dce4ee", anchor="w")
        self._text(895, 285, f"Cimetière : {len(p2.graveyard)} carte(s)", size=11, fill="#dce4ee", anchor="w")

        self._text(95, 360, "CYCLE CLASSIC", size=13, fill=GOLD, weight="bold", anchor="w")
        self._rect(90, 385, 1510, 465, fill="#121b28", outline="#314158", width=1, radius=14)
        active_name = self._player_display_name(self.engine.active_player)
        inherited = self.engine.delayed_actions.get(self.engine.active_player)
        delayed_txt = self.engine.action_description(inherited) if inherited else "Aucune action héritée en attente"
        self._text(120, 412, f"Tour actuel : {active_name} — planifie d'abord tout son cycle, puis valide.", size=11, fill="#dce4ee", anchor="w")
        fitted_delay, dsz = self._fit_text_box("Action 2 réactive : " + delayed_txt, 720, 18, start_size=10, min_size=7, weight="bold", max_lines=1)
        self._text(120, 443, fitted_delay, size=dsz, fill=ACCENT, weight="bold", anchor="w", width=720)
        self._text(900, 443, "Action 1 = à la validation   •   Action 2 = avant les actions à la validation adverse", size=9, fill=MUTED, anchor="w")

        self._text(95, 510, "HISTORIQUE", size=13, fill=MUTED, weight="bold", anchor="w")
        self._rect(90, 535, 1510, 820, fill="#0b111a", outline="#314158", width=1, radius=14)
        logs = self.engine.log[-14:]
        if logs:
            line_y = 565
            for line in logs:
                line = str(line).replace("J1", self._player_display_name(1)).replace("J2", self._player_display_name(2))
                fitted, fitted_size = self._fit_text_box("• " + line, 1350, 17, start_size=9, min_size=6, max_lines=1)
                self._text(120, line_y, fitted, size=fitted_size, fill="#b9c4d3", anchor="nw", justify="left", width=1350)
                line_y += 17
        else:
            self._text(120, 565, "Aucune action enregistrée.", size=9, fill="#728096", anchor="nw")
        self._text(800, 842, "Le contenu exact des réserves reste caché pendant le duel.", size=9, fill="#728096")

    def _return_to_duel(self):
        self.current_screen = "duel"
        self.redraw()

    # ------------------------------------------------------------------
    # Duel drawing
    # ------------------------------------------------------------------
    def _draw_duel(self):
        # Un redraw logique reconstruit la référence Tk stable. Le viewport GPU
        # est masqué pendant quelques millisecondes pour que la capture GDI lise
        # réellement le Canvas fraîchement dessiné, jamais son propre swap-chain.
        if hasattr(self, "gpu_field_renderer"):
            self.gpu_field_renderer.hide()
        self._clear_field_card_renderers()
        self.canvas.delete("all")
        self.click_regions.clear()
        duel_bg = self._scaled_asset("duel_bg")
        if duel_bg is not None:
            self.canvas.create_image(0, 0, image=duel_bg, anchor="nw")
        else:
            self._gradient_background("#121926", "#070b11")
        if hasattr(self, "audio") and not self.audio.music_is_active("ingame"):
            self.audio.play_ingame_music(force=True)
        if not self.engine or not self.current_mode:
            return

        active = self.engine.active_player
        human_turn = self._active_is_human() and not self.ai_busy and self.engine.pending_replacement is None
        self._rect(24, 18, 1576, 74, fill="#0e141e", outline="#2a3547", width=1, radius=14)
        self._text(48, 46, "YUGITO", size=23, weight="bold", anchor="w", family=DISPLAY_FONT_TOKEN)
        if self.current_mode.id == "multiplayer":
            mode_label = f"MULTIPLAYER — {self._local_pseudo()}"
        else:
            mode_label = "SOLO VS IA"
        self._text(190, 47, mode_label, size=11, fill=MUTED, weight="bold", anchor="w")
        self._text(700, 46, f"TOUR {self.engine.turn}   •   {self._player_display_name(active).upper()}", size=14, weight="bold", fill="#dfe7f2")
        state = "FENÊTRE" if self.is_fullscreen else "PLEIN ÉCRAN"
        self._button(1035, 27, 1150, 65, "JOURNAL", self.show_duel_info, fill="#151d29", accent="#667ea0", small=True)
        self._button(1160, 27, 1270, 65, "AUDIO", self.show_audio_settings, fill="#151d29", accent="#55a6c9", small=True)
        self._button(1280, 27, 1410, 65, state, self._toggle_fullscreen, fill="#151d29", accent="#5f6d82", small=True)
        self._button(1420, 27, 1544, 65, "MENU", self.show_main_menu, fill="#151d29", accent="#7b5860", small=True)

        p2 = self.engine.player(2)
        p1 = self.engine.player(1)
        self._draw_player_header(p2, 101, active=(active == 2))
        self._draw_player_header(p1, 818, active=(active == 1))

        self._rect(44, 120, 1255, 802, fill="#0e1520", outline="#28364a", width=2, radius=22)
        self._text(650, 133, "ZONE DE COMBAT — 3 NINJAS MAXIMUM", size=9, fill="#718097", weight="bold", family=DISPLAY_FONT_TOKEN)
        self.canvas.create_line(*self.R(205, 458, 1075, 458), fill="#35455c", width=max(1, int(self._scale()[0] * 2)))

        self._draw_side_piles(p2, top=True)
        self._draw_side_piles(p1, top=False)

        # La rangée active est dessinée en dernier : une carte sélectionnée à
        # +4 % se comporte comme une vraie carte soulevée au-dessus du plateau.
        if active == 1:
            self._draw_field_row(2, top=True, clickable_enemy=human_turn, clickable_own=False)
            self._draw_field_row(1, top=False, clickable_enemy=False, clickable_own=human_turn)
        else:
            self._draw_field_row(1, top=False, clickable_enemy=human_turn, clickable_own=False)
            self._draw_field_row(2, top=True, clickable_enemy=False, clickable_own=human_turn)
        self._draw_transient_fx()

        # V12 : le gros panneau "réserves + logs" a été retiré du terrain.
        # Les informations restent accessibles via le bouton JOURNAL en haut.
        self._draw_action_panel(active, human_turn)

        self._rect(30, 856, 1248, 886, fill="#0f151f", outline="#273247", width=1, radius=8)
        notice_color = "#d8e1ed" if not self.engine.winner else "#ffd27a"
        self._text(50, 871, self.notice or "", size=10, fill=notice_color, anchor="w")

        if self.engine.winner is not None:
            self._draw_winner_overlay(self.engine.winner)

        self._ensure_status_animation()
        self._ensure_card_motion_animation()
        self._schedule_gpu_field_sync()
        self._schedule_auto_end_if_needed()

    def _gpu_field_capture_specs(self) -> list[FieldCaptureSpec]:
        """Rectangles physiques des cartes telles que Tk vient de les dessiner.

        Le padding inclut ombre, liserés et le +4 % de sélection. La texture
        capturée contient donc exactement le rendu YUGITO actuel (verre compris),
        mais son déplacement ultérieur ne dépend plus du rasterizer Tk.
        """
        if not self.engine:
            return []
        scale, _, _ = self._scale()
        rx1, ry1, _rx2, _ry2 = GPUFieldRenderer.REGION
        region_px_x, region_px_y = self.P(rx1, ry1)
        specs: list[FieldCaptureSpec] = []
        padding = 13.0
        active = self.engine.active_player
        for player_number in (2, 1):
            player = self.engine.player(player_number)
            top = player_number == 2
            for slot, instance in enumerate(player.field):
                if instance is None:
                    continue
                x1, y1, x2, y2 = self._field_slot_coords(slot, top)
                selected = player_number == active and self.selected_attacker_slot == slot
                visual_scale = self._field_selected_visual_scale(player_number, slot) if selected else self._field_base_visual_scale()
                cx, cy = (x1 + x2) / 2.0, (y1 + y2) / 2.0
                vw, vh = 230.0 * visual_scale, 330.0 * visual_scale
                vx1, vy1 = cx - vw / 2.0, cy - vh / 2.0
                vx2, vy2 = vx1 + vw, vy1 + vh
                px1, py1 = self.P(vx1 - padding, vy1 - padding)
                px2, py2 = self.P(vx2 + padding, vy2 + padding)
                ix1, iy1 = int(math.floor(px1)), int(math.floor(py1))
                ix2, iy2 = int(math.ceil(px2)), int(math.ceil(py2))
                specs.append(FieldCaptureSpec(
                    key=(int(player_number), int(slot)),
                    x=ix1, y=iy1, width=max(2, ix2 - ix1), height=max(2, iy2 - iy1),
                    local_x=float(ix1) - float(region_px_x),
                    local_y=float(iy1) - float(region_px_y),
                    screen_scale=float(scale), selected=bool(selected),
                ))
        return specs

    def _schedule_gpu_field_sync(self):
        gpu = getattr(self, "gpu_field_renderer", None)
        if gpu is None or not gpu.enabled or self.current_screen != "duel" or not self.engine:
            return
        # Les FX de combat actuels vivent encore sur le Canvas. Pendant leur
        # courte durée on laisse donc Tk visible ; le GPU revient dès qu'ils se
        # terminent. Cette transition sera supprimée lorsque les FX passeront à
        # leur tour sur le backend 1.9.x.
        if self.transient_fx:
            gpu.hide()
            return
        if self._gpu_field_sync_job is None:
            self._gpu_field_sync_job = self.root.after_idle(self._sync_gpu_field_from_canvas)

    def _sync_gpu_field_from_canvas(self):
        self._gpu_field_sync_job = None
        gpu = getattr(self, "gpu_field_renderer", None)
        if gpu is None or not gpu.enabled or self.current_screen != "duel" or not self.engine:
            return
        if self.transient_fx:
            gpu.hide()
            return
        specs = self._gpu_field_capture_specs()
        if not specs:
            gpu.hide()
            return
        ok = gpu.sync_from_canvas(specs)
        if not ok and gpu.last_error:
            # Fallback sûr : les cartes Tk restent dessinées et jouables. On ne
            # déclenche pas de redraw ici pour éviter une boucle d'échec.
            self.notice = "GPU indisponible — rendu Canvas de secours actif."

    def _schedule_auto_end_if_needed(self):
        """Classic : auto-fin uniquement si aucune attaque, aucun switch et aucun plan."""
        if self._auto_end_job is not None:
            return
        if self.current_screen != "duel" or not self.engine or self.engine.winner is not None:
            return
        if self.ai_busy or self.engine.pending_replacement is not None or not self._active_is_human() or self.turn_commit_pending_end:
            return
        if self.turn_plan_free is not None or self.turn_plan_actions:
            return
        player = self.engine.player(self.engine.active_player)
        if player.deck:
            return
        if self.engine.player_has_any_action(self.engine.active_player):
            return
        self.notice = "Aucune action possible — passage automatique…"
        self._auto_end_job = self.root.after(1150, self._auto_end_turn)

    def _auto_end_turn(self):
        self._auto_end_job = None
        if self.current_screen != "duel" or not self.engine or self.engine.winner is not None:
            return
        if self.ai_busy or self.engine.pending_replacement is not None or not self._active_is_human():
            return
        player = self.engine.player(self.engine.active_player)
        if player.deck or self.engine.player_has_any_action(self.engine.active_player):
            self.redraw()
            return
        self.notice = "Aucune action possible : tour passé automatiquement."
        self.end_turn()

    def _draw_hidden_reserve_summary(self, player, x: float, y: float, accent: str):
        # A card back communicates that cards exist without revealing identities.
        self._rect(x, y - 34, x + 310, y + 48, fill="#111925", outline="#2b394d", width=1, radius=12)
        self._text(x + 20, y - 13, f"JOUEUR {player.number}", size=10, fill=accent, weight="bold", anchor="w")
        self._text(x + 20, y + 17, f"Réserve : {len(player.deck)} carte(s) cachée(s)", size=10, fill="#dbe2ea", anchor="w")
        for i in range(min(5, len(player.deck))):
            bx = x + 205 + i * 16
            self._rect(bx, y - 22 - i * 2, bx + 42, y + 36 - i * 2, fill="#182434", outline=accent if i == min(5, len(player.deck)) - 1 else "#33445e", width=1, radius=4)

    def _draw_player_header(self, player, y: float, *, active: bool):
        accent = BLUE if player.number == 1 else RED
        if active:
            accent = ACCENT
        self._rect(72, y - 17, 1230, y + 17, fill="#111925", outline="#29374b", width=1, radius=9)
        self._rect(72, y - 17, 82, y + 17, fill=accent, radius=5)
        self._text(98, y, self._player_display_name(player.number).upper(), size=12, weight="bold", anchor="w")
        self._text(225, y, f"PV {player.hp} / 4000", size=11, fill="#e6ebf2", weight="bold", anchor="w")
        self._rect(355, y - 6, 665, y + 7, fill="#252e3d", radius=5)
        ratio = max(0.0, min(1.0, player.hp / 4000))
        if ratio > 0:
            self._rect(357, y - 4, 357 + 306 * ratio, y + 5, fill=accent, radius=4)
        self._text(705, y, f"Réserve {len(player.deck)}", size=10, fill=MUTED, anchor="w")
        self._text(840, y, f"Terrain {sum(c is not None for c in player.field)}/3", size=10, fill=MUTED, anchor="w")
        self._text(970, y, f"Cimetière {len(player.graveyard)}", size=10, fill=MUTED, anchor="w")
        if active:
            self._text(1195, y, "ACTIF", size=9, fill=ACCENT, weight="bold", anchor="e")

    def _draw_side_piles(self, player, *, top: bool):
        y = 210 if top else 530
        active_switch = bool(
            self.engine and self.engine.active_player == player.number and self._active_is_human()
            and not self.ai_busy and self.engine.pending_replacement is None and not self.turn_commit_pending_end
        )
        outline = ACCENT if active_switch and self.selected_attacker_slot is not None else "#4a5d78"
        self._rect(82, y, 195, y + 160, fill="#182434", outline=outline, width=2, radius=10)
        self._text(138, y + 40, "RÉSERVE", size=9, weight="bold")
        self._rect(108, y + 65, 168, y + 137, fill="#0d2238", outline="#7089a8", width=2, radius=7)
        self._text(138, y + 99, "?", size=18, fill="#8ea4bf", weight="bold")
        self._text(138, y + 145, str(len(player.deck)), size=9, fill=MUTED)
        if active_switch:
            self._text(138, y + 157, "CLIQUE = ÉCHANGE", size=6, fill=GREEN if player.deck else MUTED, weight="bold")
            if player.deck:
                self._add_click(82, y, 195, y + 160, self._open_tactical_switch)
            # Bouton demandé au-dessus de la pioche : il annule le choix que le
            # joueur est en train de préparer, sans toucher aux actions validées.
            has_selection = self.selected_attacker_slot is not None or self.selected_style is not None or self.selected_special_mode is not None
            self._button(84, y - 34, 193, y - 5, "↩ ANNULER", self._cancel_current_action_selection, fill="#1d1720", accent=RED, enabled=has_selection, small=True)

        self._rect(1095, y, 1208, y + 160, fill="#191f29", outline="#5f5056", width=2, radius=10)
        self._text(1151, y + 63, "CIM.", size=11, weight="bold", fill="#d9c7cc")
        self._text(1151, y + 94, str(len(player.graveyard)), size=10, fill=MUTED)

    def _field_slot_coords(self, index: int, top: bool):
        # 1.7.18 : les deux trios convergent nettement vers le centre du combat.
        # Horizontalement, l'écart entre centres diminue exactement de 5 %
        # (234 -> 222.3) tout en gardant le trio centré sur x=705.
        field_center_x = 705.0
        step_x = 234.0 * 0.95
        x1 = (field_center_x - 115.0) + (index - 1) * step_x

        # 1.7.17 : top=88 / bottom=502. On rapproche ici chaque rangée de
        # 42 px du centre. Les hitboxes 230x330 se touchent sans se chevaucher.
        y1 = 130.0 if top else 460.0
        return x1, y1, x1 + 230.0, y1 + 330.0

    def _field_motion_offset(self, player_number: int, slot: int, *, selected: bool = False) -> tuple[float, float]:
        # Classic 1.9.0 : le Canvas ne bouge PLUS les cartes. Il dessine une
        # image de référence parfaitement stable, capturée seulement quand
        # l'état visuel change. Le mouvement fractionnaire vit exclusivement
        # dans le swap-chain OpenGL de GPUFieldRenderer.
        return 0.0, 0.0

    def _field_selected_visual_scale(self, player_number: int, slot: int) -> float:
        return self._field_base_visual_scale() * 1.04

    def _field_base_visual_scale(self) -> float:
        # 1.7.18 : +5 % exactement par rapport à 1.7.17 (0.792).
        return 0.792 * 1.05

    def _clear_field_card_renderers(self):
        for widget in list(getattr(self, "_field_card_widgets", {}).values()):
            try:
                widget.destroy()
            except Exception:
                pass
        self._field_card_widgets = {}
        # Les PhotoImage composites doivent rester référencées tant qu'elles
        # vivent sur le canvas principal.
        self._field_card_snapshots = {}

    def _render_field_card_as_one_object(
        self, player_number: int, slot: int, display_instance, *, selected: bool,
        inspected: bool, virtual_switch, visual_scale: float,
        world_x1: float, world_y1: float, clickable_enemy: bool, clickable_own: bool,
    ):
        """Dessine la référence visuelle stable d'une carte de terrain.

        En 1.9.0 ce groupe Canvas ne bouge jamais. Une fois le redraw logique
        terminé, GPUFieldRenderer capture cette apparence (cadre, illustration,
        textes, états et verre) et la transforme en texture OpenGL. Le Canvas
        reste donc l'autorité de composition, pas l'autorité d'animation.
        """
        base_w, base_h = 230.0, 330.0
        vw, vh = base_w * visual_scale, base_h * visual_scale

        # world_x1/world_y1 désignent le coin du VISUEL réduit. _draw_card, lui,
        # reçoit l'origine du slot logique 230x330 puis recentre visual_scale.
        input_x = world_x1 - (base_w - vw) / 2.0
        input_y = world_y1 - (base_h - vh) / 2.0
        tag = f"fieldcard_{player_number}_{slot}"

        saved_tags = self._active_draw_tags
        try:
            self._active_draw_tags = tuple(dict.fromkeys(saved_tags + (tag, "fieldcard_group")))
            self._draw_card(
                display_instance.definition, input_x, input_y, "field",
                current_hp=int(display_instance.current_hp), selected=selected,
                instance=display_instance, visual_scale=visual_scale,
            )
            self._draw_card_status_fx(display_instance, world_x1, world_y1, world_x1 + vw, world_y1 + vh)
            if virtual_switch:
                self._rect(world_x1 + 7, world_y1 + 7, world_x1 + vw - 7, world_y1 + 34, fill="#10261e", outline=GREEN, width=2, radius=7)
                self._text(world_x1 + vw / 2, world_y1 + 20, "APRES ACTION 1 : ECHANGE", size=6, fill="#a9f4c1", weight="bold")
            if inspected:
                self._rect(world_x1 + 3, world_y1 + 3, world_x1 + vw - 3, world_y1 + vh - 3, fill="", outline="#6eb8ff", width=2, radius=8)
        finally:
            self._active_draw_tags = saved_tags

        # Les clics restent gérés par les hitboxes logiques de _draw_field_row.
        # Retourner le premier item du groupe n'est pas nécessaire : l'animation
        # cible directement le tag commun.
        return None

    def _ensure_card_motion_animation(self):
        # 1.9.0 GPU : aucune animation de carte n'est planifiée sur Tk.
        return

    def _card_motion_tick(self):
        # Compatibilité : aucun mouvement de carte n'est effectué côté Tk.
        return

    def _draw_field_row(self, player_number: int, *, top: bool, clickable_enemy: bool, clickable_own: bool):
        if not self.engine:
            return
        player = self.engine.player(player_number)
        active = self.engine.active_player
        for i, instance in enumerate(player.field):
            x1, y1, x2, y2 = self._field_slot_coords(i, top)
            selected = player_number == active and self.selected_attacker_slot == i
            inspected = player_number != active and self.inspected_enemy_slot == i
            motion_x, motion_y = self._field_motion_offset(player_number, i, selected=selected)
            visual_scale = self._field_selected_visual_scale(player_number, i) if selected else self._field_base_visual_scale()
            vcx, vcy = (x1 + x2) / 2 + motion_x, (y1 + y2) / 2 + motion_y
            vw, vh = 230 * visual_scale, 330 * visual_scale
            vx1, vy1 = vcx - vw / 2, vcy - vh / 2

            display_instance = instance
            virtual_switch = None
            if player_number == active:
                virtual_switch = self._planned_immediate_switch_for_slot(i)
                if virtual_switch:
                    preview = self.engine.preview_reserve_instance(player_number, str(virtual_switch.get("incoming_id") or ""))
                    if preview is not None:
                        display_instance = preview

            if display_instance is None:
                self._rect(x1, y1, x2, y2, fill="#111a27", outline="#35445c", width=2, radius=12)
                self._text((x1 + x2) / 2, (y1 + y2) / 2 - 12, "VIDE", size=13, fill="#55657d", weight="bold")
                self._text((x1 + x2) / 2, (y1 + y2) / 2 + 22, f"EMPLACEMENT {i + 1}", size=8, fill="#67758a", weight="bold")
            else:
                self._render_field_card_as_one_object(
                    player_number, i, display_instance, selected=selected,
                    inspected=inspected, virtual_switch=virtual_switch, visual_scale=visual_scale,
                    world_x1=vx1, world_y1=vy1, clickable_enemy=clickable_enemy,
                    clickable_own=clickable_own,
                )

            # Les hitboxes restent volontairement larges (230x330) même si le
            # visuel a diminué : ergonomie inchangée, rendu plus aéré.
            if clickable_own and display_instance is not None:
                self._add_click(x1, y1, x2, y2, lambda s=i: self.click_own_slot(s))
            elif clickable_enemy and instance is not None:
                self._add_click(x1, y1, x2, y2, lambda s=i: self.click_enemy_slot(s))

    # ------------------------------------------------------------------
    # V7 - Feedback visuel du combat
    # ------------------------------------------------------------------
    def _field_center(self, player_number: int, slot: int) -> tuple[float, float]:
        x1, y1, x2, y2 = self._field_slot_coords(slot, top=(player_number == 2))
        dx = dy = 0.0
        gpu = getattr(self, "gpu_field_renderer", None)
        if gpu is not None and gpu.enabled:
            try:
                dx, dy = gpu.current_offset((int(player_number), int(slot)))
            except Exception:
                dx = dy = 0.0
        return (x1 + x2) / 2 + dx, (y1 + y2) / 2 + dy

    def _card_has_transparency_fx(self, instance) -> bool:
        if instance is None:
            return False
        if not getattr(instance, "definition", None):
            return False
        if instance.definition.id == "obito" and getattr(instance, "obito_intangible", False):
            return True
        if instance.definition.id == "zabuza" and getattr(instance, "zabuza_untargetable", False):
            return True
        if (
            instance.definition.id == "gengetsu"
            and getattr(instance, "gengetsu_untargetable", False)
            and not getattr(instance, "gengetsu_clone_active", False)
        ):
            return True
        return False

    def _draw_fog_overlay(self, x1: float, y1: float, x2: float, y2: float, *, phase: int):
        self._stipple_rect(x1, y1, x2, y2, fill="#9aa6b7", stipple="gray50", outline="", width=0)
        drift = 0 if phase == 0 else 5
        self._stipple_oval(x1 + 8 + drift, y1 + 24, x1 + 78 + drift, y1 + 72, fill="#f4f7fb", stipple="gray50", outline="")
        self._stipple_oval(x1 + 38 - drift, y1 + 46, x1 + 122 - drift, y1 + 100, fill="#eef2f8", stipple="gray25", outline="")
        self._stipple_oval(x1 + 16, y2 - 78 - drift, x1 + 102, y2 - 30 - drift, fill="#f7f9fc", stipple="gray50", outline="")
        self._stipple_oval(x2 - 108, y2 - 92 + drift, x2 - 22, y2 - 34 + drift, fill="#edf1f7", stipple="gray25", outline="")

    def _draw_transparency_overlay(self, x1: float, y1: float, x2: float, y2: float, *, phase: int, label: str = "INCIBLABLE"):
        border = "#8fd3ff" if phase == 0 else "#5ca7e6"
        self._stipple_rect(x1, y1, x2, y2, fill="#dbeeff", stipple="gray50", outline=border, width=2)
        self._stipple_oval(x1 + 12, y1 + 18, x2 - 12, y1 + 84, fill="#eff8ff", stipple="gray25", outline="")
        self._text((x1 + x2) / 2, y1 + 16, label, size=7, fill=border, weight="bold")

    def _draw_card_status_fx(self, instance, x1: float, y1: float, x2: float, y2: float):
        """Effets persistants directement posés sur une carte du terrain."""
        if not self.engine:
            return
        phase = self._status_anim_phase % 2

        # Effet de transparence pour les cartes réellement inciblables.
        if self._card_has_transparency_fx(instance):
            label = "KAMUI"
            if instance.definition.id == "zabuza":
                label = "BRUME"
            elif instance.definition.id == "gengetsu":
                label = "PALOURDE"
            self._draw_transparency_overlay(x1 + 4, y1 + 4, x2 - 4, y2 - 4, phase=phase, label=label)

        if int(getattr(instance, "konohamaru_sexy_turns", 0)) > 0:
            turns = int(instance.konohamaru_sexy_turns)
            band_y1 = y1 + (y2 - y1) * 0.29
            band_y2 = band_y1 + 34
            self._rect(x1 + 15, band_y1, x2 - 15, band_y2, fill="#5b174f", outline="#ff9be9", width=3, radius=8)
            self._text((x1 + x2) / 2, (band_y1 + band_y2) / 2, f"SEXY JUTSU {turns}T", size=8, fill="#ffe4fa", weight="bold")

        # Clone aqueux explosif : bandeau très visible avec compte à rebours.
        if getattr(instance, "gengetsu_clone_active", False):
            turns = max(0, int(getattr(instance, "gengetsu_clone_turns_left", 0)))
            glow = "#ff9a4f" if phase == 0 else "#ffd066"
            band_y1 = y1 + (y2 - y1) * 0.37
            band_y2 = band_y1 + 42
            self._rect(x1 + 12, band_y1, x2 - 12, band_y2, fill="#31170d", outline=glow, width=3, radius=9)
            self._text((x1 + x2) / 2, band_y1 + 14, "CLONE EXPLOSIF", size=8, fill="#fff1d0", weight="bold")
            self._text((x1 + x2) / 2, band_y1 + 30, f"EXPLOSION DANS {turns}T", size=8, fill=glow, weight="bold")

        if int(getattr(self.engine._effect_carrier(instance), "sealed_turns", 0) or 0) > 0:
            sealed = self.engine._effect_carrier(instance)
            turns = int(getattr(sealed, "sealed_turns", 0) or 0)
            glow = "#ffd85a" if phase == 0 else "#d6a92a"
            band_y1 = y1 + (y2 - y1) * 0.30
            band_y2 = band_y1 + 38
            self._rect(x1 + 13, band_y1, x2 - 13, band_y2, fill="#3b2d08", outline=glow, width=3, radius=8)
            self._text((x1 + x2) / 2, (band_y1 + band_y2) / 2, f"SCELLÉ {turns}T", size=9, fill="#fff1a6", weight="bold")

        if self.engine.is_disabled(instance):
            # OMBRE DES NARA possède son propre bandeau noir. Les autres contrôles
            # conservent le brouillard / bandeau violet historique.
            self._draw_fog_overlay(x1 + 6, y1 + 6, x2 - 6, y2 - 6, phase=phase)
            shadow_turns = int(self.engine._shadow_stun_turns(instance))
            band_y1 = y1 + (y2 - y1) * 0.38
            band_y2 = band_y1 + 34
            if shadow_turns > 0:
                self._rect(x1 + 12, band_y1, x2 - 12, band_y2, fill="#050608", outline="#45484f", width=3, radius=8)
                self._text((x1 + x2) / 2, (band_y1 + band_y2) / 2, f"OMBRE DES NARA • {shadow_turns}T", size=8, fill="#f4f4f4", weight="bold")
            else:
                if int(getattr(self.engine._effect_carrier(instance), "sealed_turns", 0) or 0) > 0:
                    label = f"SCELLÉ {int(getattr(self.engine._effect_carrier(instance), 'sealed_turns', 0))}T"
                elif int(getattr(instance, "haku_ice_prison_turns", 0)) > 0:
                    label = f"GLACE {int(instance.haku_ice_prison_turns)}T"
                elif instance.prisoned_by is not None and self.engine._is_alive_instance(instance.prisoned_by):
                    label = "PRISON"
                else:
                    turns = max(1, int(instance.disabled_turns))
                    label = f"STUN {turns}T"
                glow = "#d37cff" if phase == 0 else "#8e55bd"
                self._rect(x1 + 15, band_y1, x2 - 15, band_y2, fill="#281631", outline=glow, width=3, radius=8)
                self._text((x1 + x2) / 2, (band_y1 + band_y2) / 2, label, size=9, fill="#f1ccff", weight="bold")
                # Petites étincelles qui changent de position/couleur à chaque phase.
                off = 5 if phase == 0 else -4
                self._text(x1 + 22 + off, y1 + 70, "✦", size=11, fill=glow, weight="bold")
                self._text(x2 - 22 - off, y1 + 122, "✦", size=9, fill=glow, weight="bold")

        if int(getattr(instance, "delayed_damage", 0)) > 0:
            glow = "#72db72" if phase == 0 else "#3e9f58"
            self._rect(x1 + 18, y2 - 52, x2 - 18, y2 - 27, fill="#102a18", outline=glow, width=2, radius=7)
            self._text((x1 + x2) / 2, y2 - 39, f"POISON {instance.delayed_damage}", size=7, fill="#b7f5b8", weight="bold")

        if int(getattr(instance, "doom_turns", 0)) > 0:
            # Badge Jashin volontairement placé près du bas de la carte pour ne
            # plus disparaître visuellement derrière les autres états/illustrations.
            glow = "#ff6b6b" if phase == 0 else "#cf4545"
            self._rect(x1 + 18, y2 - 92, x2 - 18, y2 - 62, fill="#351010", outline=glow, width=3, radius=8)
            self._text((x1 + x2) / 2, y2 - 77, f"JASHIN {int(instance.doom_turns)}", size=9, fill="#ffe0e0", weight="bold")

    def _consume_engine_visual_events(self):
        if not self.engine:
            return
        now = time.monotonic()
        for event in self.engine.drain_visual_events():
            event_type = event.get("type")
            if event_type == "ko":
                self.audio.play_death()
                continue
            if event_type == "passive_audio":
                self.audio.play_passive(event.get("card_id"))
                continue
            if event_type == "special_audio":
                self.audio.play_special(event.get("card_id"), variant=event.get("variant"))
                continue
            if event_type == "planned_normal_audio":
                self.audio.play_normal_attack()
                continue
            if event_type == "planned_special_audio":
                self._play_action_special_audio(event.get("card_id"))
                continue
            # Une attaque produit déjà son propre nombre de dégâts : on garde
            # les événements damage séparés uniquement pour poison/zone/retardé.
            if event_type == "damage" and event.get("label") in ("attaque", "spéciale"):
                continue
            duration = {
                "attack": 1.05,
                "heal": 1.15,
                "shield": 0.95,
                "damage": 0.90,
                "player_damage": 1.15,
                "poison_burst": 1.05,
                "poison_apply": 1.00,
                "stun_apply": 1.00,
            }.get(event.get("type"), 0.9)
            fx = dict(event)
            # Le chrono démarre au PREMIER affichage de l'effet, pas au moment
            # où le moteur termine son calcul. Ainsi un redraw lourd ne peut pas
            # faire expirer l'animation avant qu'elle soit visible.
            fx["duration"] = duration
            fx["start"] = None
            fx["end"] = None
            self.transient_fx.append(fx)
        if self.transient_fx:
            self._schedule_fx_tick()

    def _schedule_fx_tick(self):
        if self._fx_job is None:
            self._fx_job = self.root.after(60, self._fx_tick)

    def _fx_tick(self):
        self._fx_job = None
        now = time.monotonic()
        self.transient_fx = [
            fx for fx in self.transient_fx
            if fx.get("end") is None or float(fx.get("end")) > now
        ]
        if self.current_screen == "duel":
            self._draw_transient_fx()
            gpu = getattr(self, "gpu_field_renderer", None)
            if gpu is not None and gpu.enabled:
                if self.transient_fx:
                    gpu.hide()
                else:
                    self._schedule_gpu_field_sync()
        if self.transient_fx:
            self._schedule_fx_tick()

    def _has_persistent_status_fx(self) -> bool:
        if not self.engine:
            return False
        for player in self.engine.players.values():
            for card in player.field:
                if card is None:
                    continue
                if self.engine.is_disabled(card) or card.delayed_damage > 0 or card.doom_turns > 0:
                    return True
        return False

    def _ensure_status_animation(self):
        if self.current_screen != "duel" or not self._has_persistent_status_fx():
            if self._status_anim_job:
                try:
                    self.root.after_cancel(self._status_anim_job)
                except Exception:
                    pass
                self._status_anim_job = None
            return
        if self._status_anim_job is None:
            self._status_anim_job = self.root.after(360, self._status_animation_tick)

    def _status_animation_tick(self):
        self._status_anim_job = None
        if self.current_screen != "duel":
            return
        self._status_anim_phase = (self._status_anim_phase + 1) % 2
        self._draw_status_animation_layer()
        if self._has_persistent_status_fx():
            self._ensure_status_animation()

    def _draw_status_animation_layer(self):
        self.canvas.delete("status_anim")
        if not self.engine or self.current_screen != "duel":
            return
        scale, _, _ = self._scale()
        for pnum, player in self.engine.players.items():
            for slot, card in enumerate(player.field):
                if card is None:
                    continue
                cx, cy = self._field_center(pnum, slot)
                if self.engine.is_disabled(card):
                    radius = 72 if self._status_anim_phase == 0 else 78
                    self.canvas.create_oval(
                        *self.R(cx - radius, cy - radius, cx + radius, cy + radius),
                        outline="#c777f1" if self._status_anim_phase == 0 else "#7f4aa0",
                        width=max(1, int(2 * scale)), tags=("status_anim",),
                    )
                if card.delayed_damage > 0:
                    radius = 64 if self._status_anim_phase == 0 else 70
                    self.canvas.create_oval(
                        *self.R(cx - radius, cy - radius, cx + radius, cy + radius),
                        outline="#62d56e" if self._status_anim_phase == 0 else "#367d43",
                        width=max(1, int(2 * scale)), tags=("status_anim",),
                    )

    def _fx_text(self, x, y, text, *, size=12, fill="#ffffff", weight="bold", anchor="center", family="Segoe UI"):
        px, py = self.P(x, y)
        return self.canvas.create_text(px, py, text=text, font=self.F(size, weight, family), fill=fill, anchor=anchor, tags=("transient_fx",))

    def _draw_transient_fx(self):
        self.canvas.delete("transient_fx")
        if not self.engine or not self.transient_fx or self.current_screen != "duel":
            return
        now = time.monotonic()
        kept: list[dict] = []
        scale, _, _ = self._scale()
        for fx in self.transient_fx:
            if fx.get("start") is None:
                fx["start"] = now
                fx["end"] = now + float(fx.get("duration", 1.0))
            start = float(fx["start"])
            end = float(fx["end"])
            if now >= end:
                continue
            kept.append(fx)
            progress = max(0.0, min(1.0, (now - start) / max(0.01, end - start)))
            typ = fx.get("type")

            if typ == "attack":
                fp, fs = int(fx["from_player"]), int(fx["from_slot"])
                tp, ts = int(fx["to_player"]), int(fx["to_slot"])
                sx, sy = self._field_center(fp, fs)
                tx, ty = self._field_center(tp, ts)
                style = str(fx.get("style") or "")
                style_color = {"taijutsu":"#ff9f68", "ninjutsu":"#75c9ff", "genjutsu":"#d18bff"}.get(style, "#dfe9f5")
                line_color = GOLD if fx.get("advantage") else ("#ffe4a6" if fx.get("special") else style_color)
                glow_color = "#6b5728" if fx.get("advantage") else ({"taijutsu":"#5c2f23", "ninjutsu":"#244d66", "genjutsu":"#4d3263"}.get(style, "#405064"))

                # Courbe quadratique, toujours légèrement arquée pour éviter la
                # vieille sensation de flèche de debug rectiligne.
                dx, dy = tx - sx, ty - sy
                dist = max(1.0, math.hypot(dx, dy))
                perp_x, perp_y = -dy / dist, dx / dist
                direction = -1.0 if (fs + ts + fp + tp) % 2 else 1.0
                bend = min(82.0, max(42.0, dist * 0.12)) * direction
                cx, cy = (sx + tx) / 2 + perp_x * bend, (sy + ty) / 2 + perp_y * bend
                def bezier(t):
                    u = 1.0 - t
                    return (u*u*sx + 2*u*t*cx + t*t*tx, u*u*sy + 2*u*t*cy + t*t*ty)
                pts=[]
                for j in range(19):
                    qx,qy=bezier(j/18)
                    pts.extend(self.P(qx,qy))
                self.canvas.create_line(*pts, fill=glow_color, width=max(4, int(10 * scale)), smooth=True, splinesteps=20, tags=("transient_fx",))
                self.canvas.create_line(*pts, fill=line_color, width=max(2, int((4 if fx.get("special") else 3) * scale)), smooth=True, splinesteps=20, arrow=tk.LAST, arrowshape=(13 * scale, 17 * scale, 7 * scale), tags=("transient_fx",))
                travel = min(1.0, progress * 1.65)
                bx, by = bezier(travel)
                r = 9 + (3 if fx.get("special") else 0)
                self.canvas.create_oval(*self.R(bx - r - 5, by - r - 5, bx + r + 5, by + r + 5), fill=glow_color, outline="", stipple="gray50", tags=("transient_fx",))
                self.canvas.create_oval(*self.R(bx - r, by - r, bx + r, by + r), fill=line_color, outline="#ffffff", width=max(1, int(2 * scale)), tags=("transient_fx",))
                for trail_i, trail_t in enumerate((max(0.0, travel-.055), max(0.0, travel-.105))):
                    qx,qy=bezier(trail_t); rr=max(2,5-trail_i*2)
                    self.canvas.create_oval(*self.R(qx-rr,qy-rr,qx+rr,qy+rr), fill=line_color, outline="", tags=("transient_fx",))
                if fx.get("damage", 0) > 0:
                    rise = 16 + progress * 24
                    self._fx_text(tx, ty - 92 - rise, f"-{int(fx['damage'])} PV", size=13, fill="#ff6d6d")
                if fx.get("immune"):
                    self._fx_text((sx + tx) / 2, (sy + ty) / 2 - 24, "IMMUNISÉ !", size=14, fill="#bfa6ff")
                elif fx.get("advantage"):
                    pulse_size = 15 if int(progress * 8) % 2 == 0 else 18
                    self._fx_text(800, 352, "SUPER EFFICACE !", size=pulse_size, fill="#ffd66e", family=DISPLAY_FONT_TOKEN)

            elif typ == "player_damage":
                player = int(fx.get("player", 1))
                cy = 101 if player == 2 else 818
                rise = progress * 24
                self._fx_text(760, cy - 24 - rise, f"SURPLUS -{int(fx.get('amount', 0))} PV JOUEUR", size=13, fill="#ff7a66", family=DISPLAY_FONT_TOKEN)
            elif typ in ("heal", "shield", "damage", "poison_burst", "poison_apply", "stun_apply"):
                player = int(fx.get("player", 1)); slot = int(fx.get("slot", 0))
                cx, cy = self._field_center(player, slot); rise = progress * 34
                if typ == "heal":
                    self._fx_text(cx, cy - 70 - rise, f"+{int(fx.get('amount', 0))} PV", size=14, fill="#66e39a")
                    self._fx_text(cx - 34, cy - 20 - rise / 2, "+", size=18, fill="#8cf0b3")
                    self._fx_text(cx + 34, cy + 8 - rise / 3, "+", size=14, fill="#8cf0b3")
                elif typ == "shield":
                    self._fx_text(cx, cy - 72 - rise, f"BOUCLIER +{int(fx.get('amount', 0))}", size=11, fill="#79c8ff")
                elif typ == "damage":
                    self._fx_text(cx, cy - 72 - rise, f"-{int(fx.get('amount', 0))} PV", size=13, fill="#ff6d6d")
                elif typ in ("poison_burst", "poison_apply"):
                    label = "POISON !" if typ == "poison_apply" else f"POISON -{int(fx.get('amount', 0))}"
                    self._fx_text(cx, cy - 74 - rise, label, size=13, fill="#66dc72")
                    rr = 36 + progress * 18
                    self.canvas.create_oval(*self.R(cx - rr, cy - rr, cx + rr, cy + rr), outline="#5bd16b", width=max(1, int(3 * scale)), tags=("transient_fx",))
                elif typ == "stun_apply":
                    label = fx.get("label", "STUN")
                    self._fx_text(cx, cy - 78 - rise, f"{label} !", size=14, fill="#d787ff")
                    rr = 42 + progress * 24
                    self.canvas.create_oval(*self.R(cx - rr, cy - rr, cx + rr, cy + rr), outline="#b36ce0", width=max(1, int(3 * scale)), tags=("transient_fx",))

        self.transient_fx = kept

    def _draw_action_panel(self, active_player: int, human_turn: bool):
        if not self.engine:
            return
        self._rect(1280, 88, 1572, 886, fill="#0f1620", outline="#2b394d", width=2, radius=20)
        self._text(1304, 116, "PLAN DU TOUR", size=15, weight="bold", anchor="w")
        self._text(1550, 116, "RIEN NE PART AVANT VALIDATION", size=6, fill=GOLD, weight="bold", anchor="e")

        # --------------------------------------------------------------
        # 3 emplacements maximum : Minato gratuit + Action 1 + Action 2.
        # --------------------------------------------------------------
        has_minato = self.engine._field_card_by_id(active_player, "minato") is not None or self.turn_plan_free is not None
        y0 = 138
        if has_minato:
            choosing_free = self.turn_plan_target_slot == "free" and self.turn_plan_free is None
            free_outline = GOLD if choosing_free else "#3f7b63"
            self._rect(1300, y0, 1552, y0 + 38, fill="#15231e", outline=free_outline, width=2 if choosing_free else 1, radius=8)
            self._text(1310, y0 + 10, "MINATO — GRATUIT", size=6, fill=GOLD if choosing_free else "#8de5b2", weight="bold", anchor="w")
            if self.turn_plan_free is not None:
                label = self._plan_action_label(self.turn_plan_free)
                fitted, sz = self._fit_text_box(label, 170, 16, start_size=7, min_size=5, weight="bold", max_lines=1)
                self._text(1310, y0 + 27, fitted, size=sz, fill="#dcefe4", anchor="w", width=170)
                self._button(1497, y0 + 5, 1543, y0 + 33, "↩", self._cancel_planned_free, fill="#24181b", accent=RED, enabled=True, small=True)
            else:
                hint = "CHOISIS L'ATTAQUE →" if not choosing_free else "CHOISIS UN ART + UNE CIBLE"
                self._text(1310, y0 + 27, hint, size=5, fill="#dcefe4" if choosing_free else MUTED, weight="bold", anchor="w")
                self._button(1447, y0 + 5, 1543, y0 + 33, "CHOISIR" if not choosing_free else "ACTIF", self._select_minato_free_slot, fill="#173126" if choosing_free else "#17251f", accent=GOLD if choosing_free else GREEN, enabled=not choosing_free, small=True)
            y0 += 44

        rows = [
            (0, "ACTION 1 — IMMÉDIATE", GREEN, "S'exécute quand tu valides"),
            (1, "ACTION 2 — RÉACTION", ACCENT, "Se déclenche à la prochaine validation adverse"),
        ]
        for idx, title, accent, hint in rows:
            action = self.turn_plan_actions[idx] if idx < len(self.turn_plan_actions) else None
            self._rect(1300, y0, 1552, y0 + 50, fill="#151e2b", outline=accent if action else "#2c394b", width=1, radius=8)
            self._text(1310, y0 + 10, title, size=6, fill=accent, weight="bold", anchor="w")
            label = self._plan_action_label(action) if action else hint
            fitted, sz = self._fit_text_box(label, 180, 22, start_size=7, min_size=5, weight="bold" if action else "normal", max_lines=2)
            self._text(1310, y0 + 29, fitted, size=sz, fill="#e0e7f0" if action else MUTED, anchor="w", width=180)
            self._button(1497, y0 + 10, 1543, y0 + 40, "↩", lambda i=idx: self._cancel_planned_action(i), fill="#24181b", accent=RED, enabled=action is not None, small=True)
            y0 += 56

        # --------------------------------------------------------------
        # Carte actuellement sélectionnée / observée.
        # --------------------------------------------------------------
        player = self.engine.player(active_player)
        own_selected = None
        if self.selected_attacker_slot is not None:
            own_selected, _ = self._planning_actor_for_slot(self.selected_attacker_slot)
        enemy_player = self.engine.opponent(active_player)
        viewed_enemy = None
        if own_selected is None and self.inspected_enemy_slot is not None and 0 <= self.inspected_enemy_slot < len(enemy_player.field):
            viewed_enemy = enemy_player.field[self.inspected_enemy_slot]
        selected = own_selected if own_selected is not None else viewed_enemy
        viewing_enemy = own_selected is None and viewed_enemy is not None

        info_y = y0 + 2
        self._rect(1300, info_y, 1552, info_y + 105, fill="#121b28", outline="#2f3d51", width=1, radius=10)
        if selected is None:
            self._text(1426, info_y + 38, "Sélectionne un Ninja", size=10, fill=MUTED)
            self._text(1426, info_y + 68, "ou clique un ennemi pour l'observer", size=6, fill="#718096")
        else:
            display_card = self.engine._combat_definition(selected)
            state = self.engine._effect_carrier(selected)
            self._text(1312, info_y + 12, "ENNEMI" if viewing_enemy else "NINJA SÉLECTIONNÉ", size=6, fill="#8cc8ff" if viewing_enemy else GREEN, weight="bold", anchor="w")
            nm, nsz = self._fit_text_box(display_card.name, 170, 18, start_size=10, min_size=6, weight="bold", family=DISPLAY_FONT_TOKEN, max_lines=1)
            self._text(1312, info_y + 32, nm, size=nsz, weight="bold", anchor="w", family=DISPLAY_FONT_TOKEN, width=170)
            self._text(1538, info_y + 32, display_card.star_label, size=8, fill=GOLD, weight="bold", anchor="e")
            max_hp = self.engine.max_hp(state)
            self._text(1312, info_y + 54, f"PV {int(state.current_hp or 0)}/{max_hp}", size=7, fill="#d9e2eb", anchor="w")
            self._text(1312, info_y + 73, f"TAI {self.engine.effective_stat(selected, 'taijutsu')}   NIN {self.engine.effective_stat(selected, 'ninjutsu')}   GEN {self.engine.effective_stat(selected, 'genjutsu')}", size=6, fill="#d9e2eb", anchor="w")
            status = self.engine.status_text(selected) or ("Aucun effet actif." if viewing_enemy else "Prêt à être planifié.")
            fitted, ssz = self._fit_text_box(status, 220, 20, start_size=6, min_size=5, weight="bold", max_lines=2)
            self._text(1312, info_y + 90, fitted, size=ssz, fill=RED if self.engine.is_disabled(selected) else MUTED, anchor="w", width=220)

        controls_y = info_y + 115
        self._text(1304, controls_y, "PRÉPARER UNE ACTION", size=7, fill=MUTED, weight="bold", anchor="w")
        styles = [("taijutsu", "TAIJUTSU", "#d46555"), ("ninjutsu", "NINJUTSU", "#4e82bb"), ("genjutsu", "GENJUTSU", "#9a64c5")]
        yy = controls_y + 12
        for style, label, accent in styles:
            chosen = self.selected_style == style and self.selected_special_mode is None
            can_plan_more = len(self.turn_plan_actions) < 2 or (
                self.turn_plan_target_slot == "free"
                and selected is not None and selected.definition.id == "minato"
                and self.turn_plan_free is None
            )
            enabled = bool(human_turn and not viewing_enemy and selected is not None and can_plan_more and self.engine.can_use_style(selected, style))
            self._button(1302, yy, 1550, yy + 31, label + ("  ✓" if chosen else ""), lambda st=style: self.select_style(st), fill="#1c2737" if chosen else "#151e2b", accent=accent, enabled=enabled, small=True)
            yy += 35

        can_regular = len(self.turn_plan_actions) < 2
        special_enabled = bool(self.turn_plan_target_slot != "free" and not viewing_enemy and human_turn and selected is not None and can_regular and not self._planned_special_for_actor(selected.definition.id) and self.engine.special_available(selected, copied=False))
        own_chosen = self.selected_special_mode == "own"
        special_label = self._short_name(((selected.definition.special_name if selected else "TECHNIQUE SPÉCIALE") or "TECHNIQUE SPÉCIALE").upper(), 27)
        self._button(1302, yy, 1550, yy + 34, special_label + ("  ✓" if own_chosen else ""), lambda: self.select_special(False), fill="#2a2117" if own_chosen else "#1b2029", accent=GOLD, enabled=special_enabled, small=True)
        yy += 38

        copy_enabled = bool(self.turn_plan_target_slot != "free" and not viewing_enemy and human_turn and selected is not None and getattr(selected, 'copied_special_id', None) and can_regular and not self._planned_special_for_actor(selected.definition.id) and self.engine.special_available(selected, copied=True))
        copy_label = "COPIE : " + self._short_name(selected.copied_special_name.upper(), 18) if selected is not None and getattr(selected, 'copied_special_id', None) else "COPIE : AUCUNE"
        self._button(1302, yy, 1550, yy + 31, copy_label, lambda: self.select_special(True), fill="#171d28", accent=PURPLE, enabled=copy_enabled, small=True)
        yy += 35

        direct_available = bool(not viewing_enemy and human_turn and selected is not None and self.selected_style is not None and self.selected_special_mode is None and not any(c is not None for c in enemy_player.field))
        self._button(1302, yy, 1550, yy + 31, "ATTAQUE DIRECTE", self.direct_attack, fill="#251d1a", accent=ACCENT, enabled=direct_available, small=True)
        yy += 35

        switch_enabled = bool(self.turn_plan_target_slot != "free" and human_turn and not viewing_enemy and selected is not None and can_regular and len(self._planning_reserve_cards()) > 0)
        self._button(1302, yy, 1550, yy + 31, "ÉCHANGE AVEC LA RÉSERVE", self._open_tactical_switch, fill="#13251e", accent=GREEN, enabled=switch_enabled, small=True)
        yy += 39

        plan_count = len(self.turn_plan_actions) + (1 if self.turn_plan_free else 0)
        validate_label = "VALIDER LE PLAN" if plan_count else "PASSER LE TOUR"
        self._button(1302, yy, 1550, yy + 43, validate_label, self.end_turn, fill="#18261f", accent=GREEN, enabled=human_turn and self.engine.winner is None and not self.turn_commit_pending_end)
        yy += 50

        # Résumé de la carte plutôt que l'ancien long panneau, la fiche complète
        # reste accessible en cliquant ici.
        self._rect(1300, yy, 1552, 866, fill="#101824", outline="#34445b", width=1, radius=10)
        if selected is not None:
            self._text(1312, yy + 14, "PASSIF", size=6, fill="#8fd69a", weight="bold", anchor="w")
            title = selected.definition.passive_name or "AUCUN PASSIF"
            fitted, tsz = self._fit_text_box(title, 215, 17, start_size=7, min_size=5, weight="bold", max_lines=1)
            self._text(1312, yy + 31, fitted, size=tsz, fill="#c9f1d0", anchor="w", width=215)
            desc, dsz = self._fit_text_box(selected.definition.passive or "Aucune description.", 215, max(20, 850 - (yy + 40)), start_size=6, min_size=5, max_lines=3)
            self._text(1312, yy + 48, desc, size=dsz, fill="#aeb9c8", anchor="nw", justify="left", width=215)
            self._text(1538, yy + 14, "FICHE >", size=6, fill="#8fa4bf", weight="bold", anchor="e")
            self._add_click(1300, yy, 1552, 866, lambda c=selected.definition, inst=selected: self._open_card_reader(c, inst))
        else:
            self._text(1426, yy + 35, "Les actions préparées peuvent être\nannulées avec le bouton ↩.", size=7, fill=MUTED)

    def _play_result_audio_once(self, winner: int):
        if self.result_audio_winner == winner:
            return
        self.result_audio_winner = winner
        local_player = 1
        if self.current_mode and self.current_mode.id == "multiplayer" and self.network_local_player in (1, 2):
            local_player = int(self.network_local_player)
        if winner == local_player:
            self.audio.play_victory()
        else:
            self.audio.play_defeat()

    def _draw_winner_overlay(self, winner: int):
        self._play_result_audio_once(winner)
        self._finalize_ranked_result_once(winner)
        self._finalize_tournament_result_once(winner)
        if self.current_mode and self.current_mode.id == "multiplayer":
            self._economy_settle_result_once(winner)
        self._rect(410, 280, 1190, 650 if self.multiplayer_match_type == "ranked" else 610, fill="#0c1119", outline=GOLD, width=3, radius=26)
        self._text(800, 350, "DUEL TERMINÉ", size=23, fill=GOLD, weight="bold")
        self._text(800, 430, f"{self._player_display_name(winner).upper()} GAGNE", size=38, weight="bold", family=DISPLAY_FONT_TOKEN)
        button_y1, button_y2 = 550, 620
        if self.multiplayer_match_type == "ranked" and self.ranked_last_result:
            rr = self.ranked_last_result
            sign = "+" if rr.get("won") else "-"
            self._text(800, 495, f"ELO  {rr.get('before', 100)}  →  {rr.get('after', 100)}   ({sign}{rr.get('delta', 0)})", size=19, fill=GREEN if rr.get("won") else RED, weight="bold")
        else:
            button_y1, button_y2 = 510, 580
        if self.economy_notice:
            self._text(800, 535 if button_y1 > 540 else 490, self.economy_notice, size=9, fill=GOLD, weight="bold", width=650)
        self._button(575, button_y1, 790, button_y2, "REJOUER", self.restart_duel, fill="#1c2733", accent=GREEN)
        self._button(810, button_y1, 1025, button_y2, "MENU", self.show_main_menu, fill="#1c2733", accent=ACCENT)


def run():
    root = tk.Tk()
    YugitoApp(root)
    root.mainloop()
