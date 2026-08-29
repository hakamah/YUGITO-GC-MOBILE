extends Node

const BattleScene: PackedScene = preload("res://Battle.tscn")
const PreBattleScene: PackedScene = preload("res://PreBattle.tscn")
const MenuCard = preload("res://scripts/MenuCard.gd")
const SynergyDB = preload("res://scripts/SynergyDB.gd")
const AssetCache = preload("res://scripts/AssetCache.gd")
const HomeVideoBackground = preload("res://scripts/HomeVideoBackground.gd")
const DraftCanvas = preload("res://scripts/DraftCanvas.gd")
const SocialManagerScript = preload("res://scripts/SocialManager.gd")
const ClassicNetworkManagerScript = preload("res://scripts/ClassicNetworkManager.gd")
const RewardManagerScript = preload("res://scripts/RewardManager.gd")
const WeeklyCollectionServiceScript = preload("res://scripts/WeeklyCollectionService.gd")
const EconomyServiceScript = preload("res://scripts/EconomyService.gd")

const MAX_DECK_SIZE: int = 8
const MAX_TOTAL_STARS: float = 32.5
const STAR_CAPS: Dictionary = {
    3.0: -1,
    3.5: 4,
    4.0: 3,
    4.5: 2,
    5.0: 1,
}

const CARD_ROLE_PRIMARY: Array[String] = ["DPS", "TANK", "PROTECTEUR", "CONTROLE", "SOUTIEN", "SOIGNEUR"]
const CARD_ROLE_ADVANCED: Array[String] = ["SUSTAIN", "BURST", "POISON", "COUNTER", "ESQUIVE", "ANTI-DEFENSE", "RESURRECTION", "SCALING", "SACRIFICE", "TRACKER", "ZONE", "PERTURBATION", "RESISTANCE", "PIEGEUR"]
const CARD_ROLE_LABELS: Dictionary = {
    "CONTROLE":"CONTRÔLE",
    "ANTI-DEFENSE":"ANTI-DÉFENSE",
    "RESURRECTION":"RÉSURRECTION",
    "RESISTANCE":"RÉSISTANCE",
    "PIEGEUR":"PIÉGEUR",
}

var cards_by_id: Dictionary = {}
var sorted_cards: Array[Dictionary] = []
var deck_ids: Array[String] = []

var app_video: YugitoHomeVideoBackground = null
var menu_root: Control
var screen_root: Control
var content_panel: Panel
var title_label: Label
var subtitle_label: Label
var footer_notice: Label
var battle_instance: Node = null
var prebattle_instance: Node = null
var battle_return_button: Button
var profile_header_name_label: Label = null
var profile_header_status_label: Label = null

var collection_selected_id: String = "naruto"
var collection_search_query: String = ""
var collection_role_filters: Array[String] = []
var collection_grid: GridContainer = null
var collection_count_label: Label = null

# P53.2 — Collection Android = même catalogue Canvas que le Draft.
# Une seule texture atlas + un seul CanvasItem pour les 70 cartes.
var collection_mobile_scroll: ScrollContainer = null
var collection_mobile_canvas: YugitoDraftCanvas = null
var collection_mobile_saved_scroll: float = 0.0
var collection_mobile_cards: Array[Dictionary] = []
var collection_mobile_index_by_id: Dictionary = {}
var collection_mobile_detail_root: Control = null

var deck_search_query: String = ""
var deck_role_filters: Array[String] = []
var deck_grid: GridContainer = null
var deck_count_label: Label = null
var deck_notice: String = "Construis un deck de 8 Ninjas uniques."

# P54 — Deck Android = même moteur atlas que Draft/Collection.
var deck_mobile_scroll: ScrollContainer = null
var deck_mobile_canvas: YugitoDraftCanvas = null
var deck_mobile_saved_scroll: float = 0.0
var deck_mobile_cards: Array[Dictionary] = []
var deck_mobile_index_by_id: Dictionary = {}
var deck_mobile_detail_root: Control = null

# P55 — Boutique Android, même moteur atlas que Draft/Collection/Deck.
var shop_mobile_scroll: ScrollContainer = null
var shop_mobile_canvas: YugitoDraftCanvas = null
var shop_mobile_saved_scroll: float = 0.0
var shop_mobile_cards: Array[Dictionary] = []
var shop_mobile_index_by_id: Dictionary = {}
var shop_mobile_detail_root: Control = null
var shop_search_query: String = ""
var shop_role_filters: Array[String] = []
var shop_ownership_filter: String = ""

var SocialManager: Node = null
var ClassicNet: Node = null
var Rewards: Node = null
var WeeklyCollection: Node = null
var Economy: Node = null
var shop_pending_purchase_id: String = ""
var last_reward_notice: String = ""
var multiplayer_show_rooms: bool = false
var multiplayer_chat_input: LineEdit = null
var social_friend_rows: Dictionary = {}
var social_selected_peer_id: String = ""
var social_tab: String = "friends"
var social_search_input: LineEdit = null
var social_message_input: LineEdit = null
var social_friend_filter: String = ""
var social_status_notice: String = ""
var current_screen: String = "home"
var music_volume_percent: float = 38.0
var sfx_volume_percent: float = 58.0
var home_overlay: Control = null
var ui_hover_cooldown_until: int = 0

func _ensure_social_manager_runtime() -> void:
    if SocialManager != null and is_instance_valid(SocialManager):
        return

    var existing: Node = get_node_or_null("/root/SocialManager")
    if existing != null:
        SocialManager = existing
        return

    var runtime_manager: Node = SocialManagerScript.new()
    runtime_manager.name = "SocialManagerRuntime"
    get_tree().root.add_child(runtime_manager)
    SocialManager = runtime_manager

func _ensure_classic_network_runtime() -> void:
    if ClassicNet != null and is_instance_valid(ClassicNet):
        return
    var existing: Node = get_node_or_null("/root/ClassicNetworkManager")
    if existing != null:
        ClassicNet = existing
    else:
        var runtime_manager: Node = ClassicNetworkManagerScript.new()
        runtime_manager.name = "ClassicNetworkRuntime"
        get_tree().root.add_child(runtime_manager)
        ClassicNet = runtime_manager

    if ClassicNet.has_signal("transport_changed") and not ClassicNet.is_connected("transport_changed",Callable(self,"_on_classic_transport_changed")):
        ClassicNet.connect("transport_changed",Callable(self,"_on_classic_transport_changed"))
    if ClassicNet.has_signal("rooms_changed") and not ClassicNet.is_connected("rooms_changed",Callable(self,"_on_classic_rooms_changed")):
        ClassicNet.connect("rooms_changed",Callable(self,"_on_classic_rooms_changed"))
    if ClassicNet.has_signal("room_changed") and not ClassicNet.is_connected("room_changed",Callable(self,"_on_classic_room_changed")):
        ClassicNet.connect("room_changed",Callable(self,"_on_classic_room_changed"))
    if ClassicNet.has_signal("event_received") and not ClassicNet.is_connected("event_received",Callable(self,"_on_classic_event")):
        ClassicNet.connect("event_received",Callable(self,"_on_classic_event"))

func _ensure_reward_manager_runtime() -> void:
    if Rewards != null and is_instance_valid(Rewards):
        return
    var existing: Node = get_node_or_null("/root/RewardManager")
    if existing != null:
        Rewards = existing
        return
    var runtime_manager: Node = RewardManagerScript.new()
    runtime_manager.name = "RewardManagerRuntime"
    get_tree().root.add_child(runtime_manager)
    Rewards = runtime_manager

func _ensure_economy_runtime() -> void:
    if Economy != null and is_instance_valid(Economy):
        return
    var existing: Node = get_node_or_null("/root/EconomyService")
    if existing != null:
        Economy = existing
    else:
        var runtime_service: Node = EconomyServiceScript.new()
        runtime_service.name = "EconomyServiceRuntime"
        get_tree().root.add_child(runtime_service)
        Economy = runtime_service

    if Economy.has_signal("state_updated") and not Economy.is_connected("state_updated",Callable(self,"_on_economy_state_updated")):
        Economy.connect("state_updated",Callable(self,"_on_economy_state_updated"))
    if Economy.has_signal("purchase_completed") and not Economy.is_connected("purchase_completed",Callable(self,"_on_economy_purchase_completed")):
        Economy.connect("purchase_completed",Callable(self,"_on_economy_purchase_completed"))
    if Economy.has_signal("request_failed") and not Economy.is_connected("request_failed",Callable(self,"_on_economy_request_failed")):
        Economy.connect("request_failed",Callable(self,"_on_economy_request_failed"))

func _on_economy_state_updated(_state: Dictionary) -> void:
    if current_screen == "shop":
        call_deferred("_show_shop")
    elif current_screen == "deck":
        call_deferred("_show_deck_creator")
    _refresh_identity_surfaces()

func _on_economy_purchase_completed(card_id: String, result: Dictionary) -> void:
    shop_pending_purchase_id = ""
    var purchase: Dictionary = result.get("purchase",{}) as Dictionary
    var price: int = int(purchase.get("price_yt",0))
    var data: Dictionary = cards_by_id.get(card_id,{}) as Dictionary
    last_reward_notice = "Achat confirmé • %s • -%d YT" % [str(data.get("name",card_id)),price]
    if current_screen == "shop":
        _show_shop()
        call_deferred("_open_shop_mobile_sheet",card_id)

func _on_economy_request_failed(kind: String, message: String) -> void:
    if kind == "purchase":
        shop_pending_purchase_id = ""
    if current_screen == "shop" or current_screen == "deck":
        footer_notice.text = message

func _economy_balance() -> int:
    if Economy != null and Economy.has_method("yt_balance"):
        return int(Economy.call("yt_balance"))
    return 0

func _available_collection_count() -> int:
    if Economy != null and Economy.has_method("available_card_ids"):
        var ids: Array[String] = Economy.call("available_card_ids") as Array[String]
        # Ne compte que les IDs réellement présents dans le catalogue Godot.
        var count: int = 0
        for cid: String in ids:
            if cards_by_id.has(cid):
                count += 1
        if count > 0:
            return count
    # Tant que le serveur n'a pas répondu, seules les 3★ de base sont certaines.
    var fallback: int = 0
    for data: Dictionary in sorted_cards:
        if float(data.get("stars",0.0)) <= 3.0:
            fallback += 1
    return fallback

func _economy_state_available() -> bool:
    if Economy == null:
        return false
    var st: Dictionary = Economy.get("state") as Dictionary
    return not st.is_empty()

func _refresh_economy(include_catalog: bool = true) -> void:
    if Economy != null and Economy.has_method("refresh_state") and AuthManager.is_session_available():
        Economy.call("refresh_state",include_catalog)

func _ensure_weekly_collection_runtime() -> void:
    if WeeklyCollection != null and is_instance_valid(WeeklyCollection):
        return

    var existing: Node = get_node_or_null("/root/WeeklyCollectionService")
    if existing != null:
        WeeklyCollection = existing
    else:
        var runtime_service: Node = WeeklyCollectionServiceScript.new()
        runtime_service.name = "WeeklyCollectionServiceRuntime"
        get_tree().root.add_child(runtime_service)
        WeeklyCollection = runtime_service

    if WeeklyCollection.has_method("configure"):
        WeeklyCollection.call("configure",Rewards)

    if WeeklyCollection.has_signal("rotation_updated"):
        if not WeeklyCollection.is_connected("rotation_updated",Callable(self,"_on_weekly_rotation_updated")):
            WeeklyCollection.connect("rotation_updated",Callable(self,"_on_weekly_rotation_updated"))

    if WeeklyCollection.has_signal("rotation_failed"):
        if not WeeklyCollection.is_connected("rotation_failed",Callable(self,"_on_weekly_rotation_failed")):
            WeeklyCollection.connect("rotation_failed",Callable(self,"_on_weekly_rotation_failed"))

func _on_weekly_rotation_updated(_payload: Dictionary) -> void:
    if current_screen == "shop":
        call_deferred("_show_shop")

func _on_weekly_rotation_failed(message: String) -> void:
    if current_screen == "shop":
        footer_notice.text = message + " • dernière rotation serveur valide conservée."

func _ready() -> void:
    _ensure_economy_runtime()
    _ensure_weekly_collection_runtime()
    _ensure_reward_manager_runtime()
    _ensure_classic_network_runtime()
    _ensure_social_manager_runtime()
    get_window().title = "YUGITO GC MOBILE - PROTOTYPE 47M.4 PREBATTLE SAFE BOOT"
    MobilePlatform.enforce_landscape()
    if not MobilePlatform.back_requested.is_connected(_on_mobile_back_requested):
        MobilePlatform.back_requested.connect(_on_mobile_back_requested)
    _load_cards()
    if WeeklyCollection != null:
        WeeklyCollection.call_deferred("refresh",true)
    if Economy != null and AuthManager.is_session_available():
        Economy.call_deferred("refresh_state",true)
    _load_saved_deck()
    _build_audio()
    _build_menu_shell()
    if not IdentityManager.profile_changed.is_connected(_on_identity_profile_changed):
        IdentityManager.profile_changed.connect(_on_identity_profile_changed)
    if not AuthManager.auth_progress.is_connected(_on_auth_progress):
        AuthManager.auth_progress.connect(_on_auth_progress)
    if not AuthManager.auth_failed.is_connected(_on_auth_failed):
        AuthManager.auth_failed.connect(_on_auth_failed)
    if not AuthManager.auth_flow_started.is_connected(_on_auth_flow_started):
        AuthManager.auth_flow_started.connect(_on_auth_flow_started)
    if not AuthManager.authenticated.is_connected(_on_auth_authenticated):
        AuthManager.authenticated.connect(_on_auth_authenticated)
    if not AuthManager.session_changed.is_connected(_on_auth_session_changed):
        AuthManager.session_changed.connect(_on_auth_session_changed)
    if SocialManager != null and SocialManager.has_signal("data_changed"):
        if not SocialManager.is_connected("data_changed", Callable(self, "_on_social_data_changed")):
            SocialManager.connect("data_changed", Callable(self, "_on_social_data_changed"))
    _refresh_identity_surfaces()
    # P47M.3 : le menu n'est jamais affiché avec une session seulement "présente"
    # mais pas encore validée. On passe d'abord par l'écran Compte.
    if IdentityManager.is_account_connected():
        _show_home()
    else:
        _show_identity_account()

func _unhandled_input(event: InputEvent) -> void:
    if (battle_instance != null or prebattle_instance != null) and event.is_action_pressed("ui_cancel"):
        _return_from_battle()

func _on_mobile_back_requested() -> void:
    if battle_instance != null or prebattle_instance != null:
        _return_from_battle()
        return
    if current_screen != "home":
        _show_home()
        return
    # Sur l'accueil, le bouton Retour Android quitte réellement YUGITO GC.
    get_tree().quit()

func _load_cards() -> void:
    var file: FileAccess = FileAccess.open("res://data/cards.json", FileAccess.READ)
    if file == null:
        push_error("Impossible d'ouvrir res://data/cards.json")
        return
    var parsed: Variant = JSON.parse_string(file.get_as_text())
    if not (parsed is Array):
        push_error("cards.json invalide")
        return
    var raw_cards: Array = parsed as Array
    for raw_item: Variant in raw_cards:
        if raw_item is Dictionary:
            var data: Dictionary = raw_item as Dictionary
            var cid: String = str(data.get("id", ""))
            if cid == "":
                continue
            cards_by_id[cid] = data
            sorted_cards.append(data)
    sorted_cards.sort_custom(_sort_cards)

func _sort_cards(a: Dictionary, b: Dictionary) -> bool:
    var sa: float = float(a.get("stars", 0.0))
    var sb: float = float(b.get("stars", 0.0))
    if not is_equal_approx(sa, sb):
        return sa > sb
    return str(a.get("name", "")) < str(b.get("name", ""))

func _sort_collection_mobile_like_draft(a: Dictionary, b: Dictionary) -> bool:
    var sa: float = float(a.get("stars", 0.0))
    var sb: float = float(b.get("stars", 0.0))
    if not is_equal_approx(sa, sb):
        return sa < sb
    return str(a.get("name", "")) < str(b.get("name", ""))

func _prepare_collection_mobile_cards() -> void:
    collection_mobile_cards.clear()
    collection_mobile_index_by_id.clear()
    for data: Dictionary in sorted_cards:
        collection_mobile_cards.append(data)
    collection_mobile_cards.sort_custom(_sort_collection_mobile_like_draft)
    for i: int in range(collection_mobile_cards.size()):
        collection_mobile_index_by_id[str(collection_mobile_cards[i].get("id",""))] = i

func _prepare_deck_mobile_cards() -> void:
    deck_mobile_cards.clear()
    deck_mobile_index_by_id.clear()
    for data: Dictionary in sorted_cards:
        deck_mobile_cards.append(data)
    deck_mobile_cards.sort_custom(_sort_collection_mobile_like_draft)
    for i: int in range(deck_mobile_cards.size()):
        deck_mobile_index_by_id[str(deck_mobile_cards[i].get("id",""))] = i

func _prepare_shop_mobile_cards() -> void:
    shop_mobile_cards.clear()
    shop_mobile_index_by_id.clear()
    for data: Dictionary in sorted_cards:
        shop_mobile_cards.append(data)
    shop_mobile_cards.sort_custom(_sort_collection_mobile_like_draft)
    for i: int in range(shop_mobile_cards.size()):
        shop_mobile_index_by_id[str(shop_mobile_cards[i].get("id",""))] = i

func _shop_price_yt(stars: float) -> int:
    if stars <= 3.0:
        return 0
    if is_equal_approx(stars, 3.5):
        return 500
    if is_equal_approx(stars, 4.0):
        return 1000
    if is_equal_approx(stars, 4.5):
        return 1500
    if stars >= 5.0:
        return 2000
    return 0

func _shop_price_label(stars: float) -> String:
    var price: int = _shop_price_yt(stars)
    return "GRATUIT" if price <= 0 else "%d YT" % price

func _shop_weekly_free_ids() -> Array[String]:
    if Economy != null and Economy.has_method("free_card_ids"):
        return Economy.call("free_card_ids") as Array[String]
    return []

func _shop_ownership_status(data: Dictionary) -> String:
    var cid: String = str(data.get("id",""))
    var stars: float = float(data.get("stars",0.0))
    if Economy != null and Economy.has_method("ownership_status"):
        return str(Economy.call("ownership_status",cid,stars))
    return "base" if stars <= 3.0 else "missing"

func _shop_is_currently_owned(data: Dictionary) -> bool:
    return _shop_ownership_status(data) in ["base","permanent","weekly"]

func _shop_is_permanently_owned(data: Dictionary) -> bool:
    return _shop_ownership_status(data) in ["base","permanent"]

func _shop_matches_ownership(data: Dictionary) -> bool:
    match shop_ownership_filter:
        "current":
            return _shop_is_currently_owned(data)
        "permanent":
            return _shop_is_permanently_owned(data)
        "missing":
            return _shop_ownership_status(data) == "missing"
        _:
            return true

func _shop_matches_all_filters(data: Dictionary) -> bool:
    return _card_matches_filters(data,shop_search_query,shop_role_filters) and _shop_matches_ownership(data)

func _shop_ownership_label(data: Dictionary) -> String:
    var cid: String = str(data.get("id",""))
    var stars: float = float(data.get("stars",0.0))
    if Economy != null and Economy.has_method("ownership_label"):
        return str(Economy.call("ownership_label",cid,stars))
    return "DÉBLOQUÉE DE BASE" if stars <= 3.0 else "NON POSSÉDÉE"

func _shop_card_price(data: Dictionary) -> int:
    var fallback: int = _shop_price_yt(float(data.get("stars",0.0)))
    if Economy != null and Economy.has_method("card_price"):
        return int(Economy.call("card_price",str(data.get("id","")),fallback))
    return fallback

func _shop_card_purchasable(data: Dictionary) -> bool:
    if Economy != null and Economy.has_method("card_purchasable"):
        return bool(Economy.call("card_purchasable",str(data.get("id",""))))
    return true

func _purchase_shop_card(cid: String) -> void:
    if Economy == null or not AuthManager.is_session_available():
        footer_notice.text = "Connecte ton compte YUGITO pour acheter cette carte."
        return
    if not shop_pending_purchase_id.is_empty():
        return
    shop_pending_purchase_id = cid
    footer_notice.text = "Achat en cours…"
    Economy.call("purchase_card",cid)

func _shop_toggle_ownership_filter(value: String) -> void:
    shop_ownership_filter = "" if shop_ownership_filter == value else value
    _capture_shop_mobile_scroll()
    _show_shop()

func _build_audio() -> void:
    # P45 — source unique pour toute l'application.
    music_volume_percent = AudioManager.get_music_percent()
    sfx_volume_percent = AudioManager.get_sfx_percent()
    AudioManager.play_music("res://assets/audio/music/menu.mp3",0.0)

func _play_ui_sound() -> void:
    AudioManager.play_sfx("res://assets/audio/ui/pick.mp3",-5.0)

func _play_ui_hover() -> void:
    var now: int = Time.get_ticks_msec()
    if now < ui_hover_cooldown_until:
        return
    ui_hover_cooldown_until = now + 90
    AudioManager.play_sfx("res://assets/audio/ui/pick.mp3",-16.0)

func _build_menu_shell() -> void:
    # P47M.3 — une seule vidéo persistante pour Menu + Shifumi/Draft.
    # Elle n'est plus enfant de menu_root, donc elle reste visible lorsque
    # le menu est masqué pour afficher PreBattle.
    app_video = HomeVideoBackground.new()
    app_video.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    add_child(app_video)

    menu_root = Control.new()
    menu_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    add_child(menu_root)

    # Header flottant en verre.
    var header: Panel = _glass_surface(menu_root, Rect2(22, 16, 1556, 66), 20, 0.10, 0.44, 10)
    _logo_in(header, Vector2(22, 13), 38)
    _label_in(header, "YUGITO", Rect2(72, 8, 154, 42), 26, Color("ffffff"), HORIZONTAL_ALIGNMENT_LEFT, true)
    _label_in(header, "GODOT 2.0", Rect2(224, 10, 104, 18), 8, Color("f5fbff"), HORIZONTAL_ALIGNMENT_LEFT, true)
    _label_in(header, "BUILD 47M.4 • PREBATTLE FIX", Rect2(224, 29, 190, 18), 7, Color("d9e8f3"), HORIZONTAL_ALIGNMENT_LEFT, false)

    var nav_items: Array[Dictionary] = [
        {"label":"ACCUEIL", "fn":Callable(self, "_show_home")},
        {"label":"JOUER", "fn":Callable(self, "_show_play")},
        {"label":"CARTES", "fn":Callable(self, "_show_collection")},
        {"label":"DECK", "fn":Callable(self, "_show_deck_builder")},
        {"label":"GUIDE", "fn":Callable(self, "_show_guide")},
        {"label":"OPTIONS", "fn":Callable(self, "_show_options")},
    ]
    var nx: float = 500.0
    for item: Dictionary in nav_items:
        var btn: Button = _button_in(header, Rect2(nx, 12, 118, 40), str(item.get("label","")), Color("d8f0ff"), false)
        var callback: Callable = item.get("fn") as Callable
        btn.pressed.connect(_nav_pressed.bind(callback))
        nx += 124.0

    var profile: Panel = _glass_surface(header, Rect2(1292, 8, 240, 48), 14, 0.07, 0.30, 3)
    var profile_hit := Button.new()
    profile_hit.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    profile_hit.text = ""
    profile_hit.flat = true
    profile_hit.focus_mode = Control.FOCUS_ALL
    profile_hit.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
    profile_hit.tooltip_text = "Ouvrir le profil YUGITO"
    var transparent := StyleBoxEmpty.new()
    profile_hit.add_theme_stylebox_override("normal",transparent)
    profile_hit.add_theme_stylebox_override("hover",transparent)
    profile_hit.add_theme_stylebox_override("pressed",transparent)
    profile_hit.add_theme_stylebox_override("focus",transparent)
    profile.add_child(profile_hit)
    profile_hit.pressed.connect(_show_profile)
    profile_header_name_label = _label_in(profile, "JOUEUR", Rect2(14, 5, 120, 18), 10, Color("ffffff"), HORIZONTAL_ALIGNMENT_LEFT, true)
    profile_header_status_label = _label_in(profile, "ELO 100  •  GOOGLE REQUIS", Rect2(14, 23, 206, 17), 7, Color("dce8f1"), HORIZONTAL_ALIGNMENT_LEFT, false)

    content_panel = _glass_surface(menu_root, Rect2(22, 96, 1556, 748), 24, 0.085, 0.42, 14)
    _apply_screen_frost(content_panel, 1.65, 0.055)

    screen_root = Control.new()
    screen_root.position = Vector2(22, 96)
    screen_root.size = Vector2(1556, 748)
    menu_root.add_child(screen_root)

    var footer_glass: Panel = _glass_surface(menu_root, Rect2(22, 856, 1556, 30), 12, 0.08, 0.26, 3)
    footer_notice = _label_in(footer_glass, "YUGITO GC MOBILE • PAYSAGE", Rect2(14, 3, 1500, 24), 8, Color("eef6fb"), HORIZONTAL_ALIGNMENT_LEFT, false)

    battle_return_button = _button_in(self, Rect2(1454, 16, 126, 44), "MENU", Color("f3c6d7"), true)
    battle_return_button.z_index = 20000
    battle_return_button.visible = false
    battle_return_button.pressed.connect(_return_from_battle)

func _glass_surface(parent: Node, rect: Rect2, radius: int = 18, fill_alpha: float = 0.08, border_alpha: float = 0.34, shadow_size: int = 6) -> Panel:
    var panel := Panel.new()
    panel.position = rect.position
    panel.size = rect.size
    panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
    var style := StyleBoxFlat.new()
    style.bg_color = Color(0.012, 0.025, 0.043, maxf(0.36, fill_alpha))
    style.border_color = Color(0.78, 0.90, 1.0, maxf(0.30, border_alpha))
    style.set_border_width_all(1)
    style.set_corner_radius_all(radius)
    style.shadow_color = Color(0,0,0,0.18)
    style.shadow_size = shadow_size
    style.shadow_offset = Vector2(0,4)
    panel.add_theme_stylebox_override("panel", style)
    parent.add_child(panel)
    return panel

func _apply_screen_frost(panel: Control, lod: float = 1.7, frost: float = 0.055) -> void:
    if MobilePlatform.is_android():
        var mobile_tint := ColorRect.new()
        mobile_tint.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
        mobile_tint.mouse_filter = Control.MOUSE_FILTER_IGNORE
        mobile_tint.color = Color(0.010, 0.024, 0.042, 0.52)
        panel.add_child(mobile_tint)
        return
    var blur := ColorRect.new()
    blur.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    blur.mouse_filter = Control.MOUSE_FILTER_IGNORE
    var mat := ShaderMaterial.new()
    var shader := Shader.new()
    shader.code = """
shader_type canvas_item;
uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_linear_mipmap;
uniform float lod = 1.7;
uniform float frost = 0.055;
void fragment() {
    vec4 c = textureLod(screen_texture, SCREEN_UV, lod);
    c.rgb = mix(c.rgb, vec3(0.012,0.026,0.045), 0.50 + frost);
    COLOR = vec4(c.rgb, 0.91);
}
"""
    mat.shader = shader
    mat.set_shader_parameter("lod", lod)
    mat.set_shader_parameter("frost", frost)
    blur.material = mat
    panel.add_child(blur)

func _nav_pressed(callback: Callable) -> void:
    _destroy_home_overlay()
    callback.call()

func _destroy_home_overlay() -> void:
    if home_overlay != null and is_instance_valid(home_overlay):
        home_overlay.queue_free()
    home_overlay = null
    if content_panel != null:
        content_panel.visible = true
    if screen_root != null:
        screen_root.visible = true

func _home_go(callback: Callable) -> void:
    _play_ui_sound()
    _destroy_home_overlay()
    callback.call()

func _clear_screen() -> void:
    if screen_root == null:
        return
    collection_mobile_scroll = null
    collection_mobile_canvas = null
    collection_mobile_detail_root = null
    deck_mobile_scroll = null
    deck_mobile_canvas = null
    deck_mobile_detail_root = null
    shop_mobile_scroll = null
    shop_mobile_canvas = null
    shop_mobile_detail_root = null
    social_search_input = null
    social_message_input = null
    multiplayer_chat_input = null
    social_friend_rows.clear()
    for child: Node in screen_root.get_children():
        screen_root.remove_child(child)
        child.queue_free()

func _screen_heading(title: String, subtitle: String) -> void:
    title_label = _label_in(screen_root, title, Rect2(38, 16, 900, 44), 29, Color("ffffff"), HORIZONTAL_ALIGNMENT_LEFT, true)
    subtitle_label = _label_in(screen_root, subtitle, Rect2(40, 58, 1110, 28), 10, Color("eef6fb"), HORIZONTAL_ALIGNMENT_LEFT, false)

func _show_home() -> void:
    current_screen = "home"
    _clear_screen()
    _destroy_home_overlay()

    # L'accueil reste clair : pas de grand panneau sombre interne.
    if content_panel != null:
        content_panel.visible = false
    if screen_root != null:
        screen_root.visible = false

    home_overlay = Control.new()
    home_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    home_overlay.z_index = 500
    menu_root.add_child(home_overlay)

    # Panneau central ~70 % écran.
    var glass_rect := Rect2(308, 150, 984, 626)
    var glass := Panel.new()
    glass.position = glass_rect.position
    glass.size = glass_rect.size
    glass.clip_contents = true
    glass.mouse_filter = Control.MOUSE_FILTER_STOP
    var glass_style := StyleBoxFlat.new()
    glass_style.bg_color = Color(0.98, 0.99, 1.0, 0.035)
    glass_style.border_color = Color(1.0, 1.0, 1.0, 0.52)
    glass_style.set_border_width_all(1)
    glass_style.set_corner_radius_all(28)
    glass_style.shadow_color = Color(0,0,0,0.20)
    glass_style.shadow_size = 18
    glass_style.shadow_offset = Vector2(0,8)
    glass.add_theme_stylebox_override("panel", glass_style)
    home_overlay.add_child(glass)

    # Vrai verre dépoli : on échantillonne l'écran déjà dessiné derrière.
    # Le blur reste uniquement dans le panneau, jamais sur les labels.
    var blur_layer := ColorRect.new()
    blur_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    blur_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
    if MobilePlatform.is_android():
        blur_layer.color = Color(1.0,1.0,1.0,0.025)
        glass.add_child(blur_layer)
    else:
        var blur_mat := ShaderMaterial.new()
        var blur_shader := Shader.new()
        blur_shader.code = """
shader_type canvas_item;
uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_linear_mipmap;
uniform float lod = 2.35;
uniform float frost = 0.10;
void fragment() {
    vec4 c = textureLod(screen_texture, SCREEN_UV, lod);
    c.rgb = mix(c.rgb, vec3(0.97,0.985,1.0), frost);
    COLOR = vec4(c.rgb, 0.91);
}
"""
        blur_mat.shader = blur_shader
        blur_layer.material = blur_mat
        glass.add_child(blur_layer)

    # Pellicule lumineuse très légère.
    var frost := ColorRect.new()
    frost.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    frost.color = Color(1.0,1.0,1.0,0.035)
    frost.mouse_filter = Control.MOUSE_FILTER_IGNORE
    glass.add_child(frost)

    var gloss := ColorRect.new()
    gloss.position = Vector2(1,1)
    gloss.size = Vector2(glass_rect.size.x - 2, 86)
    gloss.color = Color(1,1,1,0.045)
    gloss.mouse_filter = Control.MOUSE_FILTER_IGNORE
    glass.add_child(gloss)

    _frosted_home_button(glass, Rect2(44, 38, 428, 94), "⚔", "SOLO", "VS IA", Color("ff9fba"), Callable(self, "_start_battle"))
    _frosted_home_button(glass, Rect2(512, 38, 428, 94), "◉", "MULTIJOUEUR", "EN LIGNE", Color("7dd2f4"), Callable(self, "_show_play"))

    _frosted_home_button(
        glass,
        Rect2(44, 150, 428, 94),
        "▣",
        "COLLECTION",
        "%d / %d CARTES DISPONIBLES" % [_available_collection_count(),sorted_cards.size()],
        Color("f4ca78"),
        Callable(self, "_show_collection")
    )
    _frosted_home_button(glass, Rect2(512, 150, 428, 94), "◇", "CRÉER UN DECK", "32,5★ MAX", Color("8fd6ae"), Callable(self, "_show_deck_builder"))

    _frosted_home_button(glass, Rect2(44, 262, 428, 94), "▤", "GUIDE", "RÈGLES CLASSIC", Color("f1cf82"), Callable(self, "_show_guide"))
    _frosted_home_button(glass, Rect2(512, 262, 428, 94), "▰", "BOUTIQUE", "CARTES & BOOSTERS", Color("93d89d"), Callable(self, "_show_shop"))

    _frosted_home_button(glass, Rect2(44, 374, 428, 94), "◌", "AMIS & MESSAGES", "DISCUTER & INVITER", Color("8fd2e4"), Callable(self, "_show_social"))
    _frosted_home_button(glass, Rect2(512, 374, 428, 94), "△", "TEEPEE", "SOUTENIR LE PROJET", Color("c1a4f2"), Callable(self, "_show_options"))

    _frosted_home_button(glass, Rect2(44, 494, 278, 76), "◈", "DISCORD", "COMMUNAUTÉ", Color("9ab8ff"), Callable(self, "_show_play"), true)
    _frosted_home_button(glass, Rect2(352, 494, 278, 76), "≋", "AUDIO", "SONS & MUSIQUES", Color("e6c59d"), Callable(self, "_show_options"), true)
    _frosted_home_button(glass, Rect2(660, 494, 280, 76), "↪", "QUITTER", "FERMER LE JEU", Color("d9dce3"), Callable(self, "_quit_game"), true)

    var version_panel := Panel.new()
    version_panel.position = Vector2(663, 794)
    version_panel.size = Vector2(274, 36)
    var version_style := StyleBoxFlat.new()
    version_style.bg_color = Color(0.20,0.24,0.30,0.24)
    version_style.border_color = Color(1,1,1,0.26)
    version_style.set_border_width_all(1)
    version_style.set_corner_radius_all(18)
    version_panel.add_theme_stylebox_override("panel", version_style)
    home_overlay.add_child(version_panel)
    _label_in(version_panel, "◉    YUGITO 2.0    ◉", Rect2(0,0,274,36), 10, Color("ffffff"), HORIZONTAL_ALIGNMENT_CENTER, true)

func _frosted_home_button(parent: Control, rect: Rect2, icon_text: String, title: String, subtitle: String, accent: Color, callback: Callable, compact: bool = false) -> Button:
    var btn := Button.new()
    btn.position = rect.position
    btn.size = rect.size
    btn.text = ""
    btn.flat = true
    btn.focus_mode = Control.FOCUS_ALL
    btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
    btn.tooltip_text = title + " — " + subtitle

    var normal := StyleBoxFlat.new()
    normal.bg_color = Color(0.95,0.98,1.0,0.075)
    normal.border_color = Color(1.0,1.0,1.0,0.40)
    normal.set_border_width_all(1)
    normal.set_corner_radius_all(17 if not compact else 14)
    normal.shadow_color = Color(0,0,0,0.10)
    normal.shadow_size = 5
    normal.shadow_offset = Vector2(0,2)

    var hover: StyleBoxFlat = normal.duplicate() as StyleBoxFlat
    hover.bg_color = Color(1.0,1.0,1.0,0.14)
    hover.border_color = Color(accent.r,accent.g,accent.b,0.82)
    hover.shadow_color = Color(accent.r,accent.g,accent.b,0.12)
    hover.shadow_size = 10

    var pressed: StyleBoxFlat = hover.duplicate() as StyleBoxFlat
    pressed.bg_color = Color(accent.r,accent.g,accent.b,0.13)

    btn.add_theme_stylebox_override("normal", normal)
    btn.add_theme_stylebox_override("hover", hover)
    btn.add_theme_stylebox_override("focus", hover)
    btn.add_theme_stylebox_override("pressed", pressed)
    parent.add_child(btn)

    # Icône et textes restent totalement nets.
    var icon_w: float = 78.0 if not compact else 62.0
    _label_in(btn, icon_text, Rect2(18, 0, icon_w, rect.size.y), 30 if not compact else 24, Color("ffffff"), HORIZONTAL_ALIGNMENT_CENTER, true)
    _label_in(btn, title, Rect2(104 if not compact else 82, 19 if not compact else 11, rect.size.x - (145 if not compact else 112), 34), 18 if not compact else 13, Color("ffffff"), HORIZONTAL_ALIGNMENT_LEFT, true)
    _label_in(btn, subtitle, Rect2(104 if not compact else 82, 53 if not compact else 40, rect.size.x - (145 if not compact else 112), 22), 9 if not compact else 8, Color("eef5fb"), HORIZONTAL_ALIGNMENT_LEFT, false)

    # Accent très léger uniquement au bord gauche.
    var accent_line := ColorRect.new()
    accent_line.position = Vector2(0, 15 if not compact else 12)
    accent_line.size = Vector2(2, rect.size.y - (30 if not compact else 24))
    accent_line.color = Color(accent.r,accent.g,accent.b,0.82)
    accent_line.mouse_filter = Control.MOUSE_FILTER_IGNORE
    btn.add_child(accent_line)

    btn.button_down.connect(_play_ui_sound)
    btn.mouse_entered.connect(_play_ui_hover)
    btn.pressed.connect(_home_go.bind(callback))
    return btn

func _quit_game() -> void:
    get_tree().quit()

func _on_auth_progress(message: String) -> void:
    if footer_notice != null:
        footer_notice.text = message

func _on_auth_failed(message: String) -> void:
    if footer_notice != null:
        footer_notice.text = "Compte : " + message
    if current_screen == "identity":
        call_deferred("_show_identity_account")

func _on_auth_flow_started(_verification_url: String, _expires_in: int) -> void:
    if current_screen == "identity":
        call_deferred("_show_identity_account")

func _on_auth_authenticated(_account: Dictionary) -> void:
    _refresh_identity_surfaces()
    _refresh_economy(true)
    if footer_notice != null:
        footer_notice.text = "Compte Google YUGITO connecté."
    if current_screen == "identity":
        call_deferred("_show_home")
    elif current_screen == "profile":
        call_deferred("_show_profile")

func _on_auth_session_changed(connected: bool) -> void:
    _refresh_identity_surfaces()
    if connected:
        _refresh_economy(true)
    # Si une session mémorisée vient d'être refusée par le serveur, le joueur
    # retombe sur l'écran Google plutôt que de rester avec "GOOGLE REQUIS"
    # dans un coin du menu.
    if not connected and not AuthManager.is_session_available() and current_screen == "home":
        call_deferred("_show_identity_account")

func _on_identity_profile_changed(_profile: Dictionary) -> void:
    _refresh_identity_surfaces()
    if current_screen == "profile":
        _show_profile()
    elif current_screen == "identity":
        _show_identity_account()

func _refresh_identity_surfaces() -> void:
    var data: Dictionary = IdentityManager.profile()
    if profile_header_name_label != null:
        profile_header_name_label.text = IdentityManager.display_name().to_upper()
    if profile_header_status_label != null:
        var state_text: String = "CONNECTÉ" if bool(data.get("connected",false)) else "HORS LIGNE"
        if str(data.get("auth_state","")) == IdentityManager.AUTH_GOOGLE_REQUIRED:
            state_text = "GOOGLE REQUIS"
        elif str(data.get("auth_state","")) == IdentityManager.AUTH_PSEUDO_REQUIRED:
            state_text = "PSEUDO REQUIS"
        profile_header_status_label.text = "ELO %d  •  %s" % [int(data.get("elo",IdentityManager.DEFAULT_ELO)),state_text]

func _profile_status_short() -> String:
    match IdentityManager.auth_state:
        IdentityManager.AUTH_CONNECTED:
            return "GOOGLE CONNECTÉ"
        IdentityManager.AUTH_CONNECTING:
            return "CONNEXION…"
        IdentityManager.AUTH_PSEUDO_REQUIRED:
            return "PSEUDO REQUIS"
        IdentityManager.AUTH_ERROR:
            return "ERREUR COMPTE"
        IdentityManager.AUTH_OFFLINE_CACHE:
            return "PROFIL HORS LIGNE"
        _:
            return "GOOGLE REQUIS"

func _profile_status_color() -> Color:
    match IdentityManager.auth_state:
        IdentityManager.AUTH_CONNECTED:
            return Color("61dba5")
        IdentityManager.AUTH_CONNECTING:
            return Color("77c8f1")
        IdentityManager.AUTH_PSEUDO_REQUIRED:
            return Color("e7c75b")
        IdentityManager.AUTH_ERROR:
            return Color("ef787e")
        IdentityManager.AUTH_OFFLINE_CACHE:
            return Color("f0b96a")
        _:
            return Color("9db2c8")

func _show_profile() -> void:
    _destroy_home_overlay()
    current_screen = "profile"
    _clear_screen()

    var data: Dictionary = IdentityManager.profile()
    var status_color: Color = _profile_status_color()

    _screen_heading(
        "PROFIL SHINOBI",
        "Identité YUGITO • ELO • YT • statistiques classées • profil commun PC / Mobile."
    )

    # P60 — plus aucun panneau technique COMPTE à droite.
    # Toute la largeur est dédiée aux informations vraiment utiles au joueur.
    var panel: Panel = _panel_in(
        screen_root,
        Rect2(32,98,1492,618),
        Color(0.010,0.026,0.045,0.96),
        Color(0.58,0.82,1.0,0.42),
        24,
        12
    )

    _label_in(
        panel,
        IdentityManager.display_name().to_upper(),
        Rect2(54,34,850,72),
        46,
        Color("ffffff"),
        HORIZONTAL_ALIGNMENT_LEFT,
        true
    )

    _capsule_in(
        panel,
        Rect2(1118,44,300,42),
        _profile_status_short(),
        status_color
    )

    # ELO principal — volontairement énorme.
    _label_in(
        panel,
        "ELO ACTUEL",
        Rect2(56,128,310,38),
        22,
        Color("a9bfd1"),
        HORIZONTAL_ALIGNMENT_LEFT,
        true
    )
    _label_in(
        panel,
        str(int(data.get("elo",100))),
        Rect2(54,166,400,108),
        72,
        Color("f1d27e"),
        HORIZONTAL_ALIGNMENT_LEFT,
        true
    )

    _label_in(
        panel,
        "MEILLEUR ELO",
        Rect2(530,132,300,38),
        22,
        Color("a9bfd1"),
        HORIZONTAL_ALIGNMENT_LEFT,
        true
    )
    _label_in(
        panel,
        str(int(data.get("best_elo",100))),
        Rect2(528,174,340,86),
        52,
        Color("e6edf4"),
        HORIZONTAL_ALIGNMENT_LEFT,
        true
    )

    _label_in(
        panel,
        "GOOGLE / YUGITO",
        Rect2(1010,132,300,38),
        22,
        Color("a9bfd1"),
        HORIZONTAL_ALIGNMENT_LEFT,
        true
    )
    _label_in(
        panel,
        "SOLDE YT  •  %d" % (_economy_balance()),
        Rect2(1010,218,360,34),
        18,
        Color("e7c75b"),
        HORIZONTAL_ALIGNMENT_LEFT,
        true
    )
    _label_in(
        panel,
        "CONNECTÉ" if IdentityManager.is_account_connected() else _profile_status_short(),
        Rect2(1008,176,360,62),
        30,
        status_color,
        HORIZONTAL_ALIGNMENT_LEFT,
        true
    )

    # Trois stats géantes.
    _profile_stat_card_p60(
        panel,
        Rect2(54,304,420,170),
        "PARTIES CLASSÉES",
        str(int(data.get("ranked_matches",0))),
        Color("77c8f1")
    )
    _profile_stat_card_p60(
        panel,
        Rect2(512,304,420,170),
        "VICTOIRES / DÉFAITES",
        "%d / %d" % [int(data.get("wins",0)),int(data.get("losses",0))],
        Color("61dba5")
    )
    _profile_stat_card_p60(
        panel,
        Rect2(970,304,448,170),
        "TAUX DE VICTOIRE",
        "%.1f %%" % float(data.get("winrate",0.0)),
        Color("c3a6f2")
    )

    # Actions principales — plus grosses et beaucoup plus lisibles.
    var account_btn: Button = _button_in(
        panel,
        Rect2(54,514,398,68),
        "COMPTE GOOGLE",
        Color("77a9ff"),
        true
    )
    account_btn.add_theme_font_size_override("font_size",18)
    account_btn.pressed.connect(_show_identity_account)

    var play_btn: Button = _button_in(
        panel,
        Rect2(500,514,398,68),
        "JOUER",
        Color("61dba5"),
        true
    )
    play_btn.add_theme_font_size_override("font_size",18)
    play_btn.pressed.connect(_show_play)

    var home_btn: Button = _button_in(
        panel,
        Rect2(946,514,472,68),
        "RETOUR ACCUEIL",
        Color("b8c9d8"),
        false
    )
    home_btn.add_theme_font_size_override("font_size",18)
    home_btn.pressed.connect(_show_home)

    footer_notice.text = "Profil : informations essentielles uniquement • lisibilité mobile renforcée."

func _profile_stat_card_p60(parent: Control, rect: Rect2, title: String, value: String, accent: Color) -> void:
    var card: Panel = _panel_in(
        parent,
        rect,
        Color(0.018,0.042,0.070,0.90),
        Color(accent.r,accent.g,accent.b,0.52),
        18,
        6
    )
    _label_in(
        card,
        title,
        Rect2(24,22,rect.size.x-48,38),
        18,
        accent,
        HORIZONTAL_ALIGNMENT_LEFT,
        true
    )
    _label_in(
        card,
        value,
        Rect2(24,72,rect.size.x-48,74),
        42,
        Color("ffffff"),
        HORIZONTAL_ALIGNMENT_LEFT,
        true
    )

func _profile_stat_card(parent: Control, rect: Rect2, title: String, value: String, accent: Color) -> void:
    var card: Panel = _panel_in(parent,rect,Color(0.018,0.042,0.070,0.86),Color(accent.r,accent.g,accent.b,0.45),15,5)
    _label_in(card,title,Rect2(18,16,rect.size.x-36,24),9,accent,HORIZONTAL_ALIGNMENT_LEFT,true)
    _label_in(card,value,Rect2(18,46,rect.size.x-36,48),25,Color("ffffff"),HORIZONTAL_ALIGNMENT_LEFT,true)

func _show_identity_account() -> void:
    _destroy_home_overlay()
    current_screen = "identity"
    _clear_screen()
    var data: Dictionary = IdentityManager.profile()
    _screen_heading("COMPTE YUGITO • GOOGLE", "Connexion réelle au serveur YUGITO • même identité PC et mobile.")

    var panel: Panel = _panel_in(
        screen_root,
        Rect2(220,96,1116,600),
        Color(0.010,0.026,0.045,0.96),
        Color(0.48,0.68,0.90,0.46),
        24,
        14
    )
    _logo_in(panel,Vector2(56,38),84)
    _label_in(panel,"YUGITO",Rect2(164,38,340,50),34,Color("ffffff"),HORIZONTAL_ALIGNMENT_LEFT,true)
    _label_in(panel,"AUTH SERVEUR",Rect2(166,84,230,22),9,Color("76aef5"),HORIZONTAL_ALIGNMENT_LEFT,true)

    var state: String = IdentityManager.auth_state
    var connected: bool = IdentityManager.is_account_connected()
    var status_color: Color = _profile_status_color()
    _label_in(
        panel,
        "GOOGLE EST CONNECTÉ" if connected else _profile_status_short(),
        Rect2(56,128,1000,42),
        20,
        status_color,
        HORIZONTAL_ALIGNMENT_CENTER,
        true
    )
    _label_in(
        panel,
        IdentityManager.auth_message,
        Rect2(120,170,876,44),
        10,
        Color("c7d6e3"),
        HORIZONTAL_ALIGNMENT_CENTER,
        false
    )

    if connected:
        _draw_connected_account(panel,data)
    elif state == IdentityManager.AUTH_PSEUDO_REQUIRED:
        _draw_pseudo_claim(panel,data)
    elif state == IdentityManager.AUTH_CONNECTING:
        _draw_connecting_account(panel)
    else:
        _draw_google_required_account(panel,data)

    _label_in(
        panel,
        "Serveur : https://yugito-auth-server.onrender.com",
        Rect2(56,556,1000,22),
        8,
        Color("71879b"),
        HORIZONTAL_ALIGNMENT_CENTER,
        false
    )
    footer_notice.text = IdentityManager.auth_message

func _draw_connected_account(panel: Control, data: Dictionary) -> void:
    _label_in(panel,IdentityManager.display_name().to_upper(),Rect2(56,222,1000,48),28,Color("ffffff"),HORIZONTAL_ALIGNMENT_CENTER,true)
    _label_in(panel,str(data.get("email","")),Rect2(56,270,1000,28),10,Color("9fb4c7"),HORIZONTAL_ALIGNMENT_CENTER,false)

    var account_box: Panel = _panel_in(panel,Rect2(190,320,736,96),Color(0.018,0.045,0.074,0.80),Color(0.42,0.66,0.88,0.34),16)
    _label_in(account_box,"ELO %d" % int(data.get("elo",100)),Rect2(24,12,210,30),16,Color("f1d27e"),HORIZONTAL_ALIGNMENT_LEFT,true)
    _label_in(account_box,"ID YUGITO",Rect2(270,10,120,22),8,Color("8fa6bb"),HORIZONTAL_ALIGNMENT_LEFT,true)
    var aid: String = str(data.get("account_id",""))
    _label_in(account_box,aid,Rect2(270,31,438,24),9,Color("edf5fa"),HORIZONTAL_ALIGNMENT_LEFT,false)
    _label_in(account_box,"Session restaurable automatiquement sur cet appareil.",Rect2(24,60,684,22),8,Color("8fa6bb"),HORIZONTAL_ALIGNMENT_LEFT,false)

    var profile_btn: Button = _button_in(panel,Rect2(190,446,230,52),"PROFIL SHINOBI",Color("61dba5"),true)
    profile_btn.pressed.connect(_show_profile)
    var verify_btn: Button = _button_in(panel,Rect2(443,446,230,52),"VÉRIFIER SESSION",Color("77c8f1"),false)
    verify_btn.pressed.connect(AuthManager.validate_saved_session)
    var logout_btn: Button = _button_in(panel,Rect2(696,446,230,52),"DÉCONNECTER",Color("ef8b91"),false)
    logout_btn.pressed.connect(_logout_yugito)

func _draw_google_required_account(panel: Control, data: Dictionary) -> void:
    var has_cache: bool = IdentityManager.has_cached_identity()
    var message: String = (
        "Ton profil local est conservé, mais Google doit être revérifié."
        if has_cache
        else
        "Connecte Google pour retrouver la même identité YUGITO sur Windows et Android."
    )
    _label_in(panel,message,Rect2(130,230,856,74),13,Color("c8d7e3"),HORIZONTAL_ALIGNMENT_CENTER,false)

    if has_cache:
        _label_in(
            panel,
            "Profil connu : %s  •  ELO %d" % [IdentityManager.display_name(),int(data.get("elo",100))],
            Rect2(130,312,856,30),
            10,
            Color("f0c978"),
            HORIZONTAL_ALIGNMENT_CENTER,
            true
        )

    var google_btn: Button = _button_in(panel,Rect2(120,350,876,142),"     SE CONNECTER AVEC GOOGLE",Color("6ba7ff"),true)
    google_btn.add_theme_font_size_override("font_size",24)
    google_btn.disabled = AuthManager.is_busy()
    google_btn.pressed.connect(_begin_google_auth)
    var google_icon := TextureRect.new()
    google_icon.position = Vector2(54,31)
    google_icon.size = Vector2(78,78)
    google_icon.texture = load("res://assets/ui/google_g.svg")
    google_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
    google_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
    google_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
    google_btn.add_child(google_icon)

    _label_in(
        panel,
        "Une page Google sécurisée s'ouvre. Après validation, reviens dans YUGITO : le jeu détecte automatiquement la connexion.",
        Rect2(180,510,756,54),
        9,
        Color("91a7bb"),
        HORIZONTAL_ALIGNMENT_CENTER,
        false
    )

func _draw_connecting_account(panel: Control) -> void:
    _label_in(
        panel,
        "VALIDATION GOOGLE EN COURS",
        Rect2(130,236,856,42),
        17,
        Color("77c8f1"),
        HORIZONTAL_ALIGNMENT_CENTER,
        true
    )
    _label_in(
        panel,
        "Choisis ton compte dans la page Google puis reviens ici.\nYUGITO interroge automatiquement le serveur toutes les quelques secondes.",
        Rect2(130,288,856,70),
        11,
        Color("c8d7e3"),
        HORIZONTAL_ALIGNMENT_CENTER,
        false
    )

    var reopen_btn: Button = _button_in(panel,Rect2(260,390,286,56),"RÉOUVRIR GOOGLE",Color("6ba7ff"),true)
    reopen_btn.disabled = AuthManager.last_verification_url.is_empty()
    reopen_btn.pressed.connect(AuthManager.reopen_google_page)
    var cancel_btn: Button = _button_in(panel,Rect2(570,390,286,56),"ANNULER",Color("ef8b91"),false)
    cancel_btn.pressed.connect(AuthManager.cancel_google_login)

    _label_in(
        panel,
        "Le lien expire automatiquement après 10 minutes.",
        Rect2(130,470,856,26),
        9,
        Color("91a7bb"),
        HORIZONTAL_ALIGNMENT_CENTER,
        false
    )

func _draw_pseudo_claim(panel: Control, data: Dictionary) -> void:
    _label_in(panel,"GOOGLE EST CONNECTÉ",Rect2(130,218,856,34),16,Color("61dba5"),HORIZONTAL_ALIGNMENT_CENTER,true)
    _label_in(
        panel,
        str(data.get("email","")),
        Rect2(130,252,856,26),
        9,
        Color("91a7bb"),
        HORIZONTAL_ALIGNMENT_CENTER,
        false
    )
    _label_in(
        panel,
        "Ce compte Google n'a encore aucun pseudo YUGITO.\nCe choix n'apparaît qu'une seule fois pour un nouveau compte.",
        Rect2(130,286,856,60),
        10,
        Color("c8d7e3"),
        HORIZONTAL_ALIGNMENT_CENTER,
        false
    )
    _label_in(panel,"TON PSEUDO",Rect2(260,360,160,22),9,Color("f0c978"),HORIZONTAL_ALIGNMENT_LEFT,true)

    var pseudo_input := LineEdit.new()
    pseudo_input.position = Vector2(260,386)
    pseudo_input.size = Vector2(596,48)
    pseudo_input.placeholder_text = "3 à 20 caractères"
    pseudo_input.max_length = 20
    pseudo_input.add_theme_font_size_override("font_size",14)
    panel.add_child(pseudo_input)
    _style_glass_line_edit(pseudo_input)
    pseudo_input.grab_focus()

    _label_in(
        panel,
        "Lettres, chiffres, espaces, - et _ • ne commence/termine pas par - ou _",
        Rect2(260,438,596,24),
        8,
        Color("91a7bb"),
        HORIZONTAL_ALIGNMENT_CENTER,
        false
    )

    var validate_btn: Button = _button_in(panel,Rect2(260,482,596,54),"VALIDER MON PSEUDO",Color("f0a965"),true)
    validate_btn.pressed.connect(_submit_identity_pseudo.bind(pseudo_input))

func _begin_google_auth() -> void:
    footer_notice.text = "Ouverture de Google…"
    AuthManager.begin_google_login()

func _submit_identity_pseudo(input: LineEdit) -> void:
    if input == null:
        return
    var result: Dictionary = IdentityManager.validate_pseudo(input.text)
    if not bool(result.get("ok",false)):
        footer_notice.text = str(result.get("message","Pseudo invalide."))
        return
    AuthManager.claim_pseudo(str(result.get("clean","")))

func _logout_yugito() -> void:
    AuthManager.logout()
    footer_notice.text = "Session Google déconnectée • profil local conservé."
    call_deferred("_show_identity_account")

func _on_social_data_changed() -> void:
    if current_screen == "social":
        call_deferred("_show_social")

func _show_social() -> void:
    _destroy_home_overlay()
    current_screen = "social"
    _clear_screen()
    SocialManager.prune_expired_invites()

    _screen_heading("ESPACE SHINOBI","Amis • messages privés • présence • invitations de combat")

    var profile: Dictionary = IdentityManager.profile()
    var online: bool = SocialManager.can_network()
    var net_color := Color("55d58b") if online else Color("d8aa4b")

    _panel_in(screen_root,Rect2(24,96,1508,72),Color(0.010,0.024,0.042,0.97),Color(0.33,0.60,0.76,0.34),18,8)
    _panel_in(screen_root,Rect2(44,107,50,50),Color(0.05,0.12,0.17,0.96),Color("78c9ef"),25,5)
    _label_in(screen_root,"忍",Rect2(44,107,50,50),19,Color("ffffff"),HORIZONTAL_ALIGNMENT_CENTER,true)
    _label_in(screen_root,IdentityManager.display_name().to_upper(),Rect2(110,105,340,28),18,Color("ffffff"),HORIZONTAL_ALIGNMENT_LEFT,true)
    _label_in(screen_root,"ELO %d" % int(profile.get("elo",100)),Rect2(110,135,120,20),9,Color("9fb2c1"),HORIZONTAL_ALIGNMENT_LEFT,true)
    _capsule_in(screen_root,Rect2(252,123,190,26),"EN LIGNE" if online else "SOCIAL HORS LIGNE",net_color)

    var unread: int = int(SocialManager.total_unread())
    _label_in(screen_root,"%d AMIS" % SocialManager.friend_list().size(),Rect2(920,116,120,24),9,Color("8fa4b5"),HORIZONTAL_ALIGNMENT_CENTER,true)
    _label_in(screen_root,"%d NON LU%s" % [unread,"" if unread==1 else "S"],Rect2(1045,116,140,24),9,Color("6ed1f5") if unread>0 else Color("708596"),HORIZONTAL_ALIGNMENT_CENTER,true)
    _label_in(screen_root,"%d DEMANDE%s" % [SocialManager.incoming_list().size(),"" if SocialManager.incoming_list().size()==1 else "S"],Rect2(1190,116,150,24),9,Color("e5bf55"),HORIZONTAL_ALIGNMENT_CENTER,true)
    _label_in(screen_root,"%d INVITATION%s" % [SocialManager.pending_invites.size(),"" if SocialManager.pending_invites.size()==1 else "S"],Rect2(1342,116,166,24),9,Color("bf99e8"),HORIZONTAL_ALIGNMENT_CENTER,true)

    var tabs: Array[Dictionary] = [
        {"id":"friends","label":"AMIS & MESSAGES","color":Color("58aff0")},
        {"id":"requests","label":"DEMANDES","color":Color("e4b94f")},
        {"id":"invites","label":"INVITATIONS","color":Color("ba85ed")}
    ]
    var x := 42.0
    for tab: Dictionary in tabs:
        var b := _button_in(screen_root,Rect2(x,182,226,48),str(tab["label"]),tab["color"] as Color,social_tab==str(tab["id"]))
        b.add_theme_font_size_override("font_size",10)
        b.pressed.connect(_set_social_tab.bind(str(tab["id"])))
        x += 238.0

    if social_tab == "friends":
        _draw_social_friends_p59()
    elif social_tab == "requests":
        _draw_social_requests_p59()
    else:
        _draw_social_invites_p59()

    footer_notice.text = social_status_notice if not social_status_notice.is_empty() else SocialManager.transport_message

func _set_social_tab(tab: String) -> void:
    social_tab = tab
    social_status_notice = ""
    _show_social()

func _draw_social_friends_p59() -> void:
    _panel_in(screen_root,Rect2(24,246,470,468),Color(0.010,0.025,0.043,0.96),Color(0.33,0.58,0.74,0.30),16,8)
    _panel_in(screen_root,Rect2(508,246,696,468),Color(0.010,0.025,0.043,0.96),Color(0.33,0.58,0.74,0.30),16,8)
    _panel_in(screen_root,Rect2(1218,246,314,468),Color(0.010,0.025,0.043,0.96),Color(0.33,0.58,0.74,0.30),16,8)

    _label_in(screen_root,"CONVERSATIONS",Rect2(44,262,230,28),16,Color("f5f8fb"),HORIZONTAL_ALIGNMENT_LEFT,true)
    social_search_input = LineEdit.new()
    social_search_input.position = Vector2(44,300)
    social_search_input.size = Vector2(300,46)
    social_search_input.placeholder_text = "Rechercher un ami…"
    social_search_input.text = social_friend_filter
    social_search_input.add_theme_font_size_override("font_size",13)
    screen_root.add_child(social_search_input)
    _style_glass_line_edit(social_search_input)
    social_search_input.text_changed.connect(_social_friend_filter_changed)
    var add := _button_in(screen_root,Rect2(354,300,116,46),"+ AMI",Color("55d58b"),true)
    add.pressed.connect(_social_open_add_friend)

    var ls := ScrollContainer.new()
    ls.position = Vector2(42,358)
    ls.size = Vector2(430,338)
    ls.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
    ls.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
    ls.scroll_deadzone = 10
    screen_root.add_child(ls)
    var box := VBoxContainer.new()
    box.custom_minimum_size = Vector2(412,0)
    box.add_theme_constant_override("separation",7)
    ls.add_child(box)

    social_friend_rows.clear()
    var shown := 0
    for row: Dictionary in SocialManager.friend_list():
        var pseudo := str(row.get("pseudo",""))
        if not social_friend_filter.is_empty() and not pseudo.to_lower().contains(social_friend_filter.to_lower()):
            continue
        shown += 1
        _social_friend_card_p59(box,row)
    if shown == 0:
        _social_empty_p59(box,"AUCUN AMI","Ajoute un joueur avec son pseudo YUGITO.")

    _draw_social_chat_p59()
    _draw_social_profile_p59()

func _social_friend_card_p59(parent: Control,row: Dictionary) -> void:
    var peer := str(row.get("id",""))
    var pseudo := str(row.get("pseudo",peer))
    var status := str(row.get("status","offline"))
    var unread := int(row.get("unread",0))
    var sc := Color("55d58b") if status=="online" else (Color("e3b84f") if status=="in_game" else Color("687b8b"))
    var sl := "EN LIGNE" if status=="online" else ("EN PARTIE" if status=="in_game" else "HORS LIGNE")
    var selected := social_selected_peer_id == peer

    var p := _panel_in(parent,Rect2(0,0,412,80),Color(0.020,0.042,0.066,0.98),Color("67c8f2") if selected else Color(sc.r,sc.g,sc.b,0.28),13,5)
    p.custom_minimum_size = Vector2(412,80)
    social_friend_rows[peer] = p
    _panel_in(p,Rect2(12,14,48,48),Color(0.04,0.09,0.13,0.96),Color(sc.r,sc.g,sc.b,0.70),24,3)
    _label_in(p,pseudo.left(1).to_upper(),Rect2(12,14,48,48),16,Color("ffffff"),HORIZONTAL_ALIGNMENT_CENTER,true)
    _label_in(p,pseudo,Rect2(74,9,228,24),12,Color("f3f7fa"),HORIZONTAL_ALIGNMENT_LEFT,true)
    _label_in(p,sl,Rect2(74,33,110,17),8,sc,HORIZONTAL_ALIGNMENT_LEFT,true)
    _label_in(p,str(row.get("preview","Aucune conversation")),Rect2(74,52,260,17),8,Color("8297a8"),HORIZONTAL_ALIGNMENT_LEFT,false)
    if unread > 0:
        _capsule_in(p,Rect2(350,18,42,24),str(mini(unread,99)),Color("4bc2ed"))
    else:
        _label_in(p,"›",Rect2(360,27,24,28),18,Color("728697"),HORIZONTAL_ALIGNMENT_CENTER,true)
    var hit := Button.new()
    hit.flat = true
    hit.position = Vector2.ZERO
    hit.size = Vector2(412,80)
    p.add_child(hit)
    hit.pressed.connect(_social_select_peer.bind(peer))

func _draw_social_chat_p59() -> void:
    if social_selected_peer_id.is_empty():
        _label_in(screen_root,"MESSAGES",Rect2(532,262,230,28),16,Color("f5f8fb"),HORIZONTAL_ALIGNMENT_LEFT,true)
        _social_empty_p59(screen_root,"SÉLECTIONNE UN AMI","La conversation apparaîtra ici.",Rect2(648,394,420,136))
        return

    var friend: Dictionary = SocialManager.get_friend(social_selected_peer_id)
    if friend.is_empty():
        social_selected_peer_id = ""
        return
    SocialManager.mark_thread_read(social_selected_peer_id)

    var pseudo := str(friend.get("pseudo",social_selected_peer_id))
    var status := str(friend.get("status","offline"))
    var sc := Color("55d58b") if status=="online" else (Color("e3b84f") if status=="in_game" else Color("687b8b"))
    _label_in(screen_root,pseudo,Rect2(532,260,280,28),17,Color("ffffff"),HORIZONTAL_ALIGNMENT_LEFT,true)
    _label_in(screen_root,"En ligne" if status=="online" else ("En partie" if status=="in_game" else "Hors ligne"),Rect2(532,289,120,18),8,sc,HORIZONTAL_ALIGNMENT_LEFT,true)
    if SocialManager.is_typing(social_selected_peer_id):
        _label_in(screen_root,"écrit…",Rect2(654,289,100,18),8,Color("78c9ef"),HORIZONTAL_ALIGNMENT_LEFT,false)

    var ms := ScrollContainer.new()
    ms.name = "SocialMessageScroll"
    ms.position = Vector2(532,322)
    ms.size = Vector2(648,310)
    ms.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
    ms.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
    ms.scroll_deadzone = 10
    screen_root.add_child(ms)
    var thread := VBoxContainer.new()
    thread.custom_minimum_size = Vector2(628,0)
    thread.add_theme_constant_override("separation",7)
    ms.add_child(thread)

    var messages: Array[Dictionary] = SocialManager.get_messages(social_selected_peer_id)
    if messages.is_empty():
        _social_empty_p59(thread,"DÉMARRE LA CONVERSATION","Aucun message échangé avec %s." % pseudo)
    else:
        var previous_day := ""
        for msg: Dictionary in messages:
            var ts := int(msg.get("ts",0))
            var day := Time.get_date_string_from_unix_time(ts)
            if day != previous_day:
                previous_day = day
                _label_in(thread,day,Rect2(0,0,628,22),8,Color("6d8394"),HORIZONTAL_ALIGNMENT_CENTER,true)
            _social_bubble_p59(thread,msg,pseudo)

    social_message_input = LineEdit.new()
    social_message_input.position = Vector2(532,646)
    social_message_input.size = Vector2(524,48)
    social_message_input.placeholder_text = "Écrire à %s…" % pseudo
    social_message_input.add_theme_font_size_override("font_size",13)
    screen_root.add_child(social_message_input)
    _style_glass_line_edit(social_message_input)
    social_message_input.text_submitted.connect(func(_v:String)->void:_social_send_message())
    var send := _button_in(screen_root,Rect2(1066,646,114,48),"ENVOYER",Color("58aff0"),true)
    send.pressed.connect(_social_send_message)
    call_deferred("_social_scroll_bottom_p59")

func _social_bubble_p59(parent: Control,msg: Dictionary,pseudo: String) -> void:
    var mine := str(msg.get("from","")) == "me"
    var wrap := Control.new()
    wrap.custom_minimum_size = Vector2(628,62)
    parent.add_child(wrap)
    var x := 184.0 if mine else 12.0
    var p := _panel_in(wrap,Rect2(x,3,430,56),Color(0.035,0.135,0.190,0.97) if mine else Color(0.035,0.050,0.070,0.97),Color(0.25,0.70,0.92,0.42) if mine else Color(0.42,0.51,0.60,0.28),13,3)
    _label_in(p,"TOI" if mine else pseudo,Rect2(14,5,390,14),7,Color("8ecfec"),HORIZONTAL_ALIGNMENT_LEFT,true)
    _label_in(p,str(msg.get("text","")),Rect2(14,20,398,24),10,Color("e8eef3"),HORIZONTAL_ALIGNMENT_LEFT,false)
    var stamp := Time.get_time_string_from_unix_time(int(msg.get("ts",0))).substr(0,5)
    if mine:
        stamp += "  ✓"
    _label_in(p,stamp,Rect2(330,38,84,13),7,Color("7890a3"),HORIZONTAL_ALIGNMENT_RIGHT,false)

func _social_scroll_bottom_p59() -> void:
    var s := screen_root.get_node_or_null("SocialMessageScroll") as ScrollContainer
    if s != null:
        s.scroll_vertical = 1000000

func _draw_social_profile_p59() -> void:
    _label_in(screen_root,"PROFIL",Rect2(1240,262,120,28),16,Color("f5f8fb"),HORIZONTAL_ALIGNMENT_LEFT,true)
    if social_selected_peer_id.is_empty():
        _social_empty_p59(screen_root,"PROFIL AMI","Sélectionne un ami pour voir ses actions.",Rect2(1242,388,266,132))
        return
    var friend: Dictionary = SocialManager.get_friend(social_selected_peer_id)
    if friend.is_empty():
        return
    var pseudo := str(friend.get("pseudo",social_selected_peer_id))
    var status := str(friend.get("status","offline"))
    var sc := Color("55d58b") if status=="online" else (Color("e3b84f") if status=="in_game" else Color("687b8b"))
    var sl := "EN LIGNE" if status=="online" else ("EN PARTIE" if status=="in_game" else "HORS LIGNE")

    _panel_in(screen_root,Rect2(1302,308,146,146),Color(0.04,0.09,0.13,0.96),Color(sc.r,sc.g,sc.b,0.65),73,5)
    _label_in(screen_root,pseudo.left(1).to_upper(),Rect2(1302,308,146,146),42,Color("ffffff"),HORIZONTAL_ALIGNMENT_CENTER,true)
    _label_in(screen_root,pseudo.to_upper(),Rect2(1242,470,266,28),15,Color("ffffff"),HORIZONTAL_ALIGNMENT_CENTER,true)
    _capsule_in(screen_root,Rect2(1280,505,190,26),sl,sc)
    _label_in(screen_root,"ELO %d" % int(friend.get("elo",100)),Rect2(1280,538,190,22),10,Color("aebdca"),HORIZONTAL_ALIGNMENT_CENTER,true)

    var invite := _button_in(screen_root,Rect2(1244,580,262,48),"⚔ INVITER EN COMBAT",Color("ba85ed"),true)
    invite.disabled = status=="offline" or SocialManager.is_blocked(social_selected_peer_id)
    invite.pressed.connect(_social_invite_private.bind(social_selected_peer_id))
    var mute := _button_in(screen_root,Rect2(1244,638,126,40),"RÉACTIVER" if SocialManager.is_muted(social_selected_peer_id) else "MUET",Color("71879a"),true)
    mute.pressed.connect(_social_toggle_mute.bind(social_selected_peer_id))
    var block := _button_in(screen_root,Rect2(1380,638,126,40),"DÉBLOQUER" if SocialManager.is_blocked(social_selected_peer_id) else "BLOQUER",Color("d46a6f"),true)
    block.pressed.connect(_social_toggle_block.bind(social_selected_peer_id))
    var remove := _button_in(screen_root,Rect2(1244,686,262,32),"SUPPRIMER L'AMI",Color("b5535a"),true)
    remove.pressed.connect(_social_remove_friend.bind(social_selected_peer_id))

func _draw_social_requests_p59() -> void:
    _panel_in(screen_root,Rect2(24,246,1508,468),Color(0.010,0.025,0.043,0.96),Color(0.70,0.56,0.24,0.30),16,8)
    _label_in(screen_root,"DEMANDES D'AMIS",Rect2(48,268,400,32),20,Color("ffffff"),HORIZONTAL_ALIGNMENT_LEFT,true)
    _label_in(screen_root,"Les demandes restent disponibles même si tu étais hors ligne.",Rect2(48,304,650,22),10,Color("98acbc"),HORIZONTAL_ALIGNMENT_LEFT,false)
    social_search_input = LineEdit.new()
    social_search_input.position = Vector2(900,266)
    social_search_input.size = Vector2(390,46)
    social_search_input.placeholder_text = "Pseudo YUGITO…"
    social_search_input.add_theme_font_size_override("font_size",13)
    screen_root.add_child(social_search_input)
    _style_glass_line_edit(social_search_input)
    var add := _button_in(screen_root,Rect2(1302,266,196,46),"ENVOYER DEMANDE",Color("55d58b"),true)
    add.pressed.connect(_social_send_friend_request)

    var scroll := ScrollContainer.new()
    scroll.position = Vector2(48,346)
    scroll.size = Vector2(1446,342)
    scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
    screen_root.add_child(scroll)
    var grid := GridContainer.new()
    grid.columns = 3
    grid.custom_minimum_size = Vector2(1418,0)
    grid.add_theme_constant_override("h_separation",14)
    grid.add_theme_constant_override("v_separation",14)
    scroll.add_child(grid)
    var rows: Array[Dictionary] = SocialManager.incoming_list()
    if rows.is_empty():
        _social_empty_p59(grid,"AUCUNE DEMANDE","Les nouvelles demandes apparaîtront ici.")
        return
    for row: Dictionary in rows:
        var peer := str(row.get("id",""))
        var p := _panel_in(grid,Rect2(0,0,458,142),Color(0.020,0.042,0.066,0.98),Color(0.78,0.62,0.24,0.42),14,5)
        p.custom_minimum_size = Vector2(458,142)
        _panel_in(p,Rect2(16,18,62,62),Color(0.05,0.10,0.14,0.95),Color("ddb84d"),31,3)
        _label_in(p,str(row.get("pseudo",peer)).left(1).to_upper(),Rect2(16,18,62,62),19,Color("ffffff"),HORIZONTAL_ALIGNMENT_CENTER,true)
        _label_in(p,str(row.get("pseudo",peer)),Rect2(94,17,330,27),14,Color("ffffff"),HORIZONTAL_ALIGNMENT_LEFT,true)
        _label_in(p,"ELO %d" % int(row.get("elo",100)),Rect2(94,48,180,20),9,Color("aebdca"),HORIZONTAL_ALIGNMENT_LEFT,true)
        var a := _button_in(p,Rect2(94,86,148,38),"ACCEPTER",Color("55d58b"),true)
        a.pressed.connect(_social_accept_request.bind(peer))
        var r := _button_in(p,Rect2(254,86,148,38),"REFUSER",Color("e85c66"),true)
        r.pressed.connect(_social_refuse_request.bind(peer))

func _draw_social_invites_p59() -> void:
    _panel_in(screen_root,Rect2(24,246,1508,468),Color(0.010,0.025,0.043,0.96),Color(0.61,0.42,0.82,0.32),16,8)
    _label_in(screen_root,"INVITATIONS DE COMBAT",Rect2(48,268,430,32),20,Color("ffffff"),HORIZONTAL_ALIGNMENT_LEFT,true)
    _label_in(screen_root,"Une invitation privée expire automatiquement après 5 minutes.",Rect2(48,304,650,22),10,Color("9faebc"),HORIZONTAL_ALIGNMENT_LEFT,false)
    var scroll := ScrollContainer.new()
    scroll.position = Vector2(48,346)
    scroll.size = Vector2(1446,342)
    scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
    screen_root.add_child(scroll)
    var grid := GridContainer.new()
    grid.columns = 2
    grid.custom_minimum_size = Vector2(1418,0)
    grid.add_theme_constant_override("h_separation",18)
    grid.add_theme_constant_override("v_separation",16)
    scroll.add_child(grid)
    if SocialManager.pending_invites.is_empty():
        _social_empty_p59(grid,"AUCUNE INVITATION","Les invitations privées reçues apparaîtront ici.")
        return
    for i in range(SocialManager.pending_invites.size()):
        var inv: Dictionary = SocialManager.pending_invites[i] as Dictionary
        var left: int = int(SocialManager.invite_seconds_left(i))
        var p := _panel_in(grid,Rect2(0,0,696,156),Color(0.028,0.040,0.070,0.98),Color(0.61,0.42,0.82,0.56),14,5)
        p.custom_minimum_size = Vector2(696,156)
        _label_in(p,"⚔ COMBAT PRIVÉ",Rect2(20,14,240,28),14,Color("d6b7f3"),HORIZONTAL_ALIGNMENT_LEFT,true)
        _label_in(p,str(inv.get("from_pseudo","JOUEUR")),Rect2(20,48,320,30),18,Color("ffffff"),HORIZONTAL_ALIGNMENT_LEFT,true)
        _capsule_in(p,Rect2(520,16,144,26),"%02d:%02d" % [left/60,left%60],Color("ba85ed"))
        _label_in(p,"Salon privé • invitation temporaire",Rect2(20,82,390,20),9,Color("9faebc"),HORIZONTAL_ALIGNMENT_LEFT,false)
        var accept := _button_in(p,Rect2(418,108,118,34),"ACCEPTER",Color("55d58b"),true)
        accept.disabled = true
        var refuse := _button_in(p,Rect2(546,108,118,34),"REFUSER",Color("e85c66"),true)
        refuse.pressed.connect(_social_dismiss_invite.bind(i))

func _social_empty_p59(parent: Control,title: String,body: String,rect: Rect2 = Rect2()) -> void:
    var host := parent
    var r := rect
    if r.size == Vector2.ZERO:
        var wrap := Control.new()
        wrap.custom_minimum_size = Vector2(404,126)
        parent.add_child(wrap)
        host = wrap
        r = Rect2(0,0,404,126)
    _panel_in(host,r,Color(0.018,0.037,0.057,0.72),Color(0.34,0.52,0.65,0.20),14)
    _label_in(host,title,Rect2(r.position+Vector2(18,18),Vector2(r.size.x-36,28)),13,Color("a8bdcb"),HORIZONTAL_ALIGNMENT_CENTER,true)
    _label_in(host,body,Rect2(r.position+Vector2(18,52),Vector2(r.size.x-36,54)),10,Color("7f93a3"),HORIZONTAL_ALIGNMENT_CENTER,false)

func _social_friend_filter_changed(value: String) -> void:
    social_friend_filter = value
    var q: String = value.strip_edges().to_lower()
    for peer_id: Variant in social_friend_rows.keys():
        var row: Control = social_friend_rows[peer_id] as Control
        if row == null or not is_instance_valid(row):
            continue
        var friend: Dictionary = SocialManager.get_friend(str(peer_id))
        var pseudo: String = str(friend.get("pseudo",peer_id)).to_lower()
        row.visible = q.is_empty() or pseudo.contains(q)

func _social_open_add_friend() -> void:
    social_tab = "requests"
    _show_social()
    if social_search_input != null:
        social_search_input.grab_focus()

func _social_select_peer(peer_id: String) -> void:
    social_selected_peer_id = peer_id
    SocialManager.mark_thread_read(peer_id)
    social_status_notice = ""
    _show_social()

func _social_send_friend_request() -> void:
    if social_search_input == null:
        return
    var result: Dictionary = SocialManager.request_friend_by_pseudo(social_search_input.text)
    social_status_notice = str(result.get("message",""))
    footer_notice.text = social_status_notice

func _social_accept_request(peer_id: String) -> void:
    var result: Dictionary = SocialManager.accept_request(peer_id)
    social_status_notice = str(result.get("message",""))
    if bool(result.get("ok",false)):
        social_selected_peer_id = peer_id
        social_tab = "friends"
    _show_social()

func _social_refuse_request(peer_id: String) -> void:
    SocialManager.refuse_request(peer_id)
    social_status_notice = "Demande refusée."
    _show_social()

func _social_remove_friend(peer_id: String) -> void:
    var friend: Dictionary = SocialManager.get_friend(peer_id)
    SocialManager.remove_friend(peer_id)
    social_selected_peer_id = ""
    social_status_notice = "%s a été retiré de tes amis." % str(friend.get("pseudo","Ce joueur"))
    _show_social()

func _social_toggle_mute(peer_id: String) -> void:
    var state: bool = bool(SocialManager.toggle_mute(peer_id))
    social_status_notice = "Notifications coupées." if state else "Notifications réactivées."
    _show_social()

func _social_toggle_block(peer_id: String) -> void:
    var state: bool = bool(SocialManager.toggle_block(peer_id))
    social_status_notice = "Joueur bloqué." if state else "Joueur débloqué."
    _show_social()

func _social_send_message() -> void:
    if social_message_input == null or social_selected_peer_id.is_empty():
        return
    var value := social_message_input.text.strip_edges()
    if value.is_empty():
        return
    var result: Dictionary = SocialManager.send_message(social_selected_peer_id,value)
    social_status_notice = str(result.get("message",""))
    footer_notice.text = social_status_notice

func _social_invite_private(peer_id: String) -> void:
    var result: Dictionary = SocialManager.invite_private_match(peer_id)
    social_status_notice = str(result.get("message",""))
    footer_notice.text = social_status_notice

func _social_dismiss_invite(index: int) -> void:
    SocialManager.dismiss_invite(index)
    social_status_notice = "Invitation refusée."
    _show_social()

func _show_play() -> void:
    _destroy_home_overlay()
    current_screen = "play"
    _clear_screen()

    _screen_heading(
        "JOUER",
        "Solo contre l'IA ou Multijoueur Classic."
    )

    _mode_card(
        Rect2(94,132,650,492),
        "SOLO VS IA",
        "COMPLET",
        "Shifumi → Draft Classic → choix des 3 Ninjas → second Shifumi → combat complet contre l'IA tactique.",
        Color("55d58b"),
        Callable(self,"_start_battle"),
        "01"
    )

    _mode_card(
        Rect2(816,132,650,492),
        "MULTIJOUEUR",
        "CLASSIC",
        "Créer ou rejoindre une partie YUGITO Classic, jouer en ligne et accéder au matchmaking classé.",
        Color("58aff0"),
        Callable(self,"_show_multiplayer_hub"),
        "02"
    )

    footer_notice.text = "Solo complet • Multijoueur Classic PC ↔ Android."

func _mode_card(rect: Rect2, title: String, state: String, description: String, accent: Color, callback: Callable, number: String = "") -> void:
    _panel_in(
        screen_root,
        rect,
        Color(0.018,0.038,0.063,0.94),
        Color(accent.r,accent.g,accent.b,0.46),
        18,
        10
    )

    _panel_in(
        screen_root,
        Rect2(rect.position + Vector2(20,20),Vector2(54,54)),
        Color(accent.r*0.10,accent.g*0.10,accent.b*0.10,0.86),
        Color(accent.r,accent.g,accent.b,0.58),
        14
    )

    _label_in(
        screen_root,
        number,
        Rect2(rect.position + Vector2(20,20),Vector2(54,54)),
        15,
        accent.lightened(0.18),
        HORIZONTAL_ALIGNMENT_CENTER,
        true
    )

    _label_in(
        screen_root,
        title,
        Rect2(rect.position + Vector2(88,23),Vector2(rect.size.x-114,34)),
        21,
        Color("f2f6fa"),
        HORIZONTAL_ALIGNMENT_LEFT,
        true
    )

    _capsule_in(
        screen_root,
        Rect2(rect.position + Vector2(88,62),Vector2(154,25)),
        state,
        accent
    )

    _panel_in(
        screen_root,
        Rect2(rect.position + Vector2(22,116),Vector2(rect.size.x-44,246)),
        Color(0.010,0.025,0.043,0.58),
        Color(accent.r,accent.g,accent.b,0.18),
        12
    )

    _rich_text_in(
        screen_root,
        description,
        Rect2(rect.position + Vector2(42,140),Vector2(rect.size.x-84,196)),
        11,
        Color("a8bacb")
    )

    var btn: Button = _button_in(
        screen_root,
        Rect2(rect.position + Vector2(28,rect.size.y-82),Vector2(rect.size.x-56,52)),
        "OUVRIR",
        accent,
        true
    )
    btn.pressed.connect(callback)

func _classic_net_configure() -> void:
    if ClassicNet == null:
        return
    ClassicNet.call("configure",IdentityManager.display_name(),int(IdentityManager.profile().get("elo",100)))
    ClassicNet.call("start")

func _classic_net_bool(prop: String) -> bool:
    return bool(ClassicNet.get(prop)) if ClassicNet != null else false

func _classic_net_string(prop: String) -> String:
    return str(ClassicNet.get(prop)) if ClassicNet != null else ""

func _classic_net_int(prop: String, fallback: int = 0) -> int:
    return int(ClassicNet.get(prop)) if ClassicNet != null else fallback

func _on_classic_transport_changed(_state: String,_message: String) -> void:
    if current_screen.begins_with("multiplayer"):
        call_deferred("_show_multiplayer_hub")

func _on_classic_rooms_changed() -> void:
    if current_screen == "multiplayer" and multiplayer_show_rooms and not _classic_net_bool("connected"):
        call_deferred("_show_multiplayer_hub")

func _on_classic_room_changed() -> void:
    if current_screen.begins_with("multiplayer"):
        call_deferred("_show_multiplayer_hub")

func _reward_multiplayer_result(
    mode: String,
    victory: bool,
    clean_completed: bool,
    abandoned: bool,
    duration_seconds: float,
    turns: int,
    player_stars: float,
    opponent_stars: float,
    match_id: String = ""
) -> Dictionary:
    if Rewards == null:
        return {}
    var opponent_key: String = _classic_net_string("peer_name").strip_edges().to_lower()
    var result: Dictionary = Rewards.call(
        "settle_multiplayer",
        mode,
        victory,
        opponent_key,
        clean_completed,
        abandoned,
        duration_seconds,
        turns,
        int(IdentityManager.profile().get("elo",100)),
        _classic_net_int("peer_elo",100),
        player_stars,
        opponent_stars,
        match_id
    ) as Dictionary
    last_reward_notice = str(result.get("message",""))
    return result

func _on_classic_event(event: Dictionary) -> void:
    var t := str(event.get("type",""))
    if t == "error":
        footer_notice.text = str(event.get("message","Erreur réseau."))
    elif t == "peer_left":
        footer_notice.text = "Adversaire déconnecté."
    elif t == "start_standard":
        # Le moteur de récompense est déjà prêt. Le règlement Classic/Classé
        # sera appelé à la fin du duel cross-play dès que la synchro combat l'émettra.
        footer_notice.text = "Duel accepté • récompenses : 30 YT victoire / 10 YT défaite propre • anti-farm actif."

func _show_multiplayer_hub() -> void:
    _destroy_home_overlay()
    current_screen = "multiplayer"
    _clear_screen()
    _classic_net_configure()

    if ClassicNet == null:
        _screen_heading("MULTIJOUEUR INTERNET","Relais YUGITO indisponible.")
        return

    if not _classic_net_string("role").is_empty() or _classic_net_bool("connected"):
        _show_multiplayer_lobby_p61()
        return

    var transport := _classic_net_string("transport_state").to_upper()
    if transport.is_empty():
        transport = "CONNEXION…"
    var classic_rooms: Array[Dictionary] = ClassicNet.call("rooms","classic",true)
    var ranked_searching: bool = bool(ClassicNet.get("ranked_searching"))

    _screen_heading("MULTIJOUEUR INTERNET","Créer et rejoindre sont deux choix distincts • compatible salons Classic PC.")
    _capsule_in(screen_root,Rect2(1280,112,230,32),"RELAIS " + transport,Color("55d58b") if transport=="CONNECTED" else Color("d8aa4b"))

    _multiplayer_mode_panel(
        Rect2(36,178,470,362),"REJOINDRE","SALONS CLASSIC PC",
        "Affiche les salons YUGITO Classic PC réellement disponibles et choisis ton adversaire.",
        Color("58aff0"),"REJOINDRE UNE PARTIE",Callable(self,"_multiplayer_show_classic_rooms")
    )
    _multiplayer_mode_panel(
        Rect2(545,178,470,362),"CRÉER","MATCHMAKING CLASSIQUE",
        "Crée immédiatement ton salon Internet et attends qu'un joueur PC le rejoigne.",
        Color("55d58b"),"CRÉER UNE PARTIE",Callable(self,"_multiplayer_host_classic")
    )
    _multiplayer_mode_panel(
        Rect2(1054,178,470,362),"MATCHMAKING CLASSÉ","ELO LE PLUS PROCHE",
        "Recherche automatiquement le salon classé PC dont l'ELO est le plus proche du tien.",
        Color("d8b050"),"RECHERCHE…" if ranked_searching else "LANCER LE CLASSÉ",Callable(self,"_multiplayer_start_ranked")
    )

    _label_in(screen_root,"%d ELO" % int(IdentityManager.profile().get("elo",100)),Rect2(1180,500,220,30),13,Color("e1c366"),HORIZONTAL_ALIGNMENT_CENTER,true)

    if multiplayer_show_rooms:
        _panel_in(screen_root,Rect2(150,562,1260,154),Color(0.010,0.026,0.045,0.97),Color(0.32,0.59,0.75,0.34),15,5)
        _label_in(screen_root,"PARTIES À REJOINDRE",Rect2(178,578,420,30),17,Color("ffffff"),HORIZONTAL_ALIGNMENT_LEFT,true)
        _capsule_in(screen_root,Rect2(1240,580,126,26),str(classic_rooms.size()),Color("58aff0"))
        var sc := ScrollContainer.new()
        sc.position = Vector2(178,614)
        sc.size = Vector2(1188,86)
        sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
        sc.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
        screen_root.add_child(sc)
        var vb := VBoxContainer.new()
        vb.custom_minimum_size = Vector2(1168,0)
        vb.add_theme_constant_override("separation",6)
        sc.add_child(vb)
        if classic_rooms.is_empty():
            _label_in(vb,"Aucune partie YUGITO Classic PC en attente pour le moment. La liste se rafraîchit automatiquement.",Rect2(0,0,1168,54),11,Color("8fa5b6"),HORIZONTAL_ALIGNMENT_CENTER,false)
        else:
            for room: Dictionary in classic_rooms:
                var b := _button_in(vb,Rect2(0,0,1168,56),"MATCHMAKING CLASSIQUE  •  %s  •  PC     REJOINDRE" % str(room.get("host_name","Adversaire")),Color("58aff0"),true)
                b.custom_minimum_size = Vector2(1168,56)
                b.add_theme_font_size_override("font_size",11)
                b.pressed.connect(_multiplayer_join_room.bind(room))
    else:
        _label_in(screen_root,"Appuie sur REJOINDRE pour ouvrir la liste des salons PC.",Rect2(420,590,720,40),13,Color("879cab"),HORIZONTAL_ALIGNMENT_CENTER,false)

    var private_btn := _button_in(screen_root,Rect2(560,660,440,48),"INVITATIONS PRIVÉES",Color("ba85ed"),true)
    private_btn.pressed.connect(_multiplayer_open_private_invites)
    footer_notice.text = "Multijoueur : protocole lobby MQTT/WSS de YUGITO Mobile 1.7.12 porté dans Godot."

func _multiplayer_mode_panel(rect: Rect2, title: String, subtitle: String, description: String, accent: Color, action_text: String, callback: Callable) -> void:
    _panel_in(
        screen_root,
        rect,
        Color(0.014,0.032,0.052,0.96),
        Color(accent.r,accent.g,accent.b,0.46),
        18,
        8
    )

    _label_in(
        screen_root,
        title,
        Rect2(rect.position + Vector2(28,26),Vector2(rect.size.x-56,42)),
        27,
        Color("ffffff"),
        HORIZONTAL_ALIGNMENT_LEFT,
        true
    )

    _label_in(
        screen_root,
        subtitle,
        Rect2(rect.position + Vector2(28,76),Vector2(rect.size.x-56,28)),
        12,
        accent,
        HORIZONTAL_ALIGNMENT_LEFT,
        true
    )

    _panel_in(
        screen_root,
        Rect2(rect.position + Vector2(24,120),Vector2(rect.size.x-48,150)),
        Color(0.008,0.021,0.036,0.78),
        Color(accent.r,accent.g,accent.b,0.16),
        13
    )

    _rich_text_in(
        screen_root,
        description,
        Rect2(rect.position + Vector2(42,140),Vector2(rect.size.x-84,112)),
        13,
        Color("b8cad7")
    )

    var btn: Button = _button_in(
        screen_root,
        Rect2(rect.position + Vector2(28,286),Vector2(rect.size.x-56,54)),
        action_text,
        accent,
        true
    )
    btn.add_theme_font_size_override("font_size",13)
    btn.pressed.connect(callback)

func _multiplayer_show_classic_rooms() -> void:
    multiplayer_show_rooms = true
    _show_multiplayer_hub()

func _multiplayer_host_classic() -> void:
    _classic_net_configure()
    ClassicNet.call("host","classic",false)
    multiplayer_show_rooms = false
    _show_multiplayer_hub()

func _multiplayer_start_ranked() -> void:
    _classic_net_configure()
    ClassicNet.call("start_ranked")
    multiplayer_show_rooms = false
    _show_multiplayer_hub()

func _multiplayer_join_room(room: Dictionary) -> void:
    _classic_net_configure()
    var result: Dictionary = ClassicNet.call("join_room",room)
    if not bool(result.get("ok",false)):
        footer_notice.text = str(result.get("message","Salon indisponible."))
    _show_multiplayer_hub()

func _show_multiplayer_lobby_p61() -> void:
    var connected: bool = _classic_net_bool("connected")
    var role: String = _classic_net_string("role")
    var match_type: String = _classic_net_string("match_type")
    var ranked: bool = match_type == "ranked"
    var peer: String = _classic_net_string("peer_name")
    if peer.is_empty():
        peer = "EN ATTENTE…"

    _screen_heading("MATCHMAKING CLASSÉ" if ranked else "MATCHMAKING CLASSIQUE", "Connexion cross-play YUGITO PC ↔ Android")
    _capsule_in(screen_root,Rect2(1280,112,230,32),"YUGITO CONNECTÉ" if connected else "EN ATTENTE",Color("55d58b") if connected else Color("d8aa4b"))

    _panel_in(screen_root,Rect2(230,184,1100,236),Color(0.010,0.026,0.045,0.97),Color(0.34,0.62,0.78,0.38),20,8)
    _label_in(screen_root,"ANDROID",Rect2(300,216,350,30),14,Color("7fcdf0"),HORIZONTAL_ALIGNMENT_CENTER,true)
    _label_in(screen_root,IdentityManager.display_name().to_upper(),Rect2(270,258,410,48),26,Color("ffffff"),HORIZONTAL_ALIGNMENT_CENTER,true)
    _label_in(screen_root,"%d ELO" % int(IdentityManager.profile().get("elo",100)),Rect2(300,314,350,28),13,Color("e1c366"),HORIZONTAL_ALIGNMENT_CENTER,true)
    _label_in(screen_root,"VS",Rect2(720,246,120,70),34,Color("c9d6df"),HORIZONTAL_ALIGNMENT_CENTER,true)
    _label_in(screen_root,"ADVERSAIRE",Rect2(910,216,350,30),14,Color("ba9ce5"),HORIZONTAL_ALIGNMENT_CENTER,true)
    _label_in(screen_root,peer.to_upper(),Rect2(880,258,410,48),26,Color("ffffff"),HORIZONTAL_ALIGNMENT_CENTER,true)
    _label_in(screen_root,("%d ELO" % _classic_net_int("peer_elo",100)) if ranked and connected else ("CONNECTÉ" if connected else "ATTENTE D'UN JOUEUR PC"),Rect2(910,314,350,28),13,Color("e1c366") if ranked else Color("86d6aa"),HORIZONTAL_ALIGNMENT_CENTER,true)

    if connected and role == "host" and not ranked:
        var launch := _button_in(screen_root,Rect2(500,438,560,62),"LANCER LE DUEL CROSS-PLAY",Color("55d58b"),true)
        launch.add_theme_font_size_override("font_size",16)
        launch.pressed.connect(func() -> void: ClassicNet.call("start_standard"))
    elif ranked:
        _label_in(screen_root,"Le duel classé démarre automatiquement quand le protocole de combat est synchronisé.",Rect2(390,446,780,48),13,Color("a9bdca"),HORIZONTAL_ALIGNMENT_CENTER,false)
    else:
        _label_in(screen_root,"Attente qu'un joueur PC rejoigne ton salon…",Rect2(390,446,780,48),13,Color("a9bdca"),HORIZONTAL_ALIGNMENT_CENTER,false)

    _multiplayer_chat_p61()
    var leave := _button_in(screen_root,Rect2(610,662,340,46),"QUITTER LA PARTIE",Color("e85c66"),true)
    leave.pressed.connect(_multiplayer_leave_room)

func _multiplayer_chat_p61() -> void:
    _panel_in(screen_root,Rect2(320,514,920,132),Color(0.008,0.021,0.036,0.90),Color(0.30,0.53,0.68,0.24),13)
    var messages: Array = ClassicNet.get("chat") as Array
    var y := 524.0
    for i in range(maxi(0,messages.size()-3),messages.size()):
        var msg: Dictionary = messages[i] as Dictionary
        _label_in(screen_root,"%s : %s" % [str(msg.get("who","?")),str(msg.get("text",""))],Rect2(344,y,858,22),9,Color("cbd8e1"),HORIZONTAL_ALIGNMENT_LEFT,false)
        y += 24.0
    multiplayer_chat_input = LineEdit.new()
    multiplayer_chat_input.position = Vector2(344,596)
    multiplayer_chat_input.size = Vector2(710,40)
    multiplayer_chat_input.placeholder_text = "Écrire un message…"
    multiplayer_chat_input.max_length = 180
    multiplayer_chat_input.add_theme_font_size_override("font_size",11)
    screen_root.add_child(multiplayer_chat_input)
    _style_glass_line_edit(multiplayer_chat_input)
    multiplayer_chat_input.text_submitted.connect(func(_v:String)->void:_multiplayer_send_chat())
    var send := _button_in(screen_root,Rect2(1064,596,150,40),"ENVOYER",Color("58aff0"),true)
    send.pressed.connect(_multiplayer_send_chat)

func _multiplayer_send_chat() -> void:
    if multiplayer_chat_input == null:
        return
    var value := multiplayer_chat_input.text.strip_edges()
    if value.is_empty():
        return
    if bool(ClassicNet.call("send_chat",value)):
        multiplayer_chat_input.text = ""
    _show_multiplayer_hub()

func _multiplayer_leave_room() -> void:
    ClassicNet.call("leave")
    multiplayer_show_rooms = false
    _show_multiplayer_hub()

func _multiplayer_open_private_invites() -> void:
    social_tab = "invites"
    _show_social()

func _role_label(role: String) -> String:
    return str(CARD_ROLE_LABELS.get(role, role))

func _card_matches_filters(data: Dictionary, query: String, roles: Array[String]) -> bool:
    var role_words: Array[String] = []
    for raw_role: Variant in data.get("roles",[]) as Array:
        role_words.append(str(raw_role))
    var haystack: String = (
        str(data.get("name","")) + " " +
        str(data.get("id","")) + " " +
        str(data.get("element","")) + " " +
        str(data.get("passive_name","")) + " " +
        str(data.get("special_name","")) + " " +
        " ".join(role_words)
    ).to_lower()
    var q: String = query.strip_edges().to_lower()
    if not q.is_empty() and haystack.find(q) < 0:
        return false
    var card_roles: Array = data.get("roles",[]) as Array
    for role: String in roles:
        if not card_roles.has(role):
            return false
    return true

func _filtered_collection_cards() -> Array[Dictionary]:
    var result: Array[Dictionary] = []
    for data: Dictionary in sorted_cards:
        if _card_matches_filters(data, collection_search_query, collection_role_filters):
            result.append(data)
    return result

func _filtered_deck_cards() -> Array[Dictionary]:
    var result: Array[Dictionary] = []
    for data: Dictionary in sorted_cards:
        if _card_matches_filters(data, deck_search_query, deck_role_filters):
            result.append(data)
    return result

func _show_collection() -> void:
    _refresh_economy(false)
    _destroy_home_overlay()
    current_screen = "collection"
    _clear_screen()

    if MobilePlatform.is_android():
        _show_collection_mobile_like_draft()
        return

    _screen_heading("COLLECTION", "%d / %d Ninjas disponibles • recherche, rôles, fiche longue et synergies Classic." % [_available_collection_count(),sorted_cards.size()])

    _panel_in(screen_root, Rect2(30, 100, 1112, 616), Color(0.015,0.031,0.052,0.84), Color(0.25,0.43,0.59,0.28), 14)
    var search := LineEdit.new()
    search.position = Vector2(44, 116)
    search.size = Vector2(346, 44 if MobilePlatform.is_android() else 38)
    search.placeholder_text = "Rechercher nom, élément, rôle, technique…"
    search.text = collection_search_query
    search.add_theme_font_size_override("font_size", 11)
    screen_root.add_child(search)
    _style_glass_line_edit(search)
    search.text_changed.connect(_on_collection_search_changed)

    collection_count_label = _label_in(screen_root, "", Rect2(406, 118, 250, 34), 10, Color("9fb3c6"), HORIZONTAL_ALIGNMENT_LEFT, true)
    var clear_btn: Button = _button_in(screen_root, Rect2(992, 116, 130, 38), "EFFACER", Color("70879d"), false)
    clear_btn.pressed.connect(_clear_collection_filters)

    _build_collection_role_toolbar()
    var scroll := ScrollContainer.new()
    scroll.position = Vector2(44, 244)
    scroll.size = Vector2(1084, 458)
    scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
    screen_root.add_child(scroll)
    collection_grid = GridContainer.new()
    collection_grid.columns = 3
    collection_grid.add_theme_constant_override("h_separation", 12)
    collection_grid.add_theme_constant_override("v_separation", 12)
    scroll.add_child(collection_grid)
    _refresh_collection_grid()

    _build_collection_detail(Rect2(1160, 100, 374, 616))
    footer_notice.text = "Collection : %d / %d cartes actuellement disponibles." % [_available_collection_count(),sorted_cards.size()]

func _show_collection_mobile_like_draft() -> void:
    _prepare_collection_mobile_cards()

    _screen_heading(
        "COLLECTION",
        "%d / %d Ninjas disponibles • les autres sont grisés • touche pour lire." % [_available_collection_count(),collection_mobile_cards.size()]
    )

    # Barre recherche claire et tactile.
    var search := LineEdit.new()
    search.position = Vector2(246, 106)
    search.size = Vector2(720, 50)
    search.placeholder_text = "Rechercher nom, élément, rôle, passif ou spéciale…"
    search.text = collection_search_query
    search.add_theme_font_size_override("font_size", 15)
    screen_root.add_child(search)
    _style_glass_line_edit(search)
    search.text_changed.connect(_on_collection_search_changed)

    collection_count_label = _label_in(
        screen_root,
        "",
        Rect2(984, 110, 360, 38),
        13,
        Color("d7e4ed"),
        HORIZONTAL_ALIGNMENT_LEFT,
        true
    )

    var clear_btn := _button_in(
        screen_root,
        Rect2(1360, 106, 150, 50),
        "EFFACER",
        Color("70879d"),
        true
    )
    clear_btn.add_theme_font_size_override("font_size", 12)
    clear_btn.pressed.connect(_clear_collection_filters)

    # Filtres rôles sur une seule ligne horizontale.
    var role_scroll := ScrollContainer.new()
    role_scroll.position = Vector2(246, 166)
    role_scroll.size = Vector2(1264, 52)
    role_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
    role_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
    role_scroll.scroll_deadzone = 10
    screen_root.add_child(role_scroll)

    var role_row := HBoxContainer.new()
    role_row.add_theme_constant_override("separation", 7)
    role_scroll.add_child(role_row)

    var roles: Array[String] = CARD_ROLE_PRIMARY + CARD_ROLE_ADVANCED
    for role: String in roles:
        var active: bool = collection_role_filters.has(role)
        var btn := _button_in(
            role_row,
            Rect2(0,0,142,44),
            ("✓ " if active else "") + _role_label(role),
            Color("d28a31") if active else Color("40586f"),
            active
        )
        btn.custom_minimum_size = Vector2(142,44)
        btn.add_theme_font_size_override("font_size",10)
        btn.pressed.connect(_toggle_collection_role.bind(role))

    # Même cadre et mêmes dimensions utiles que le pool du Draft.
    _panel_in(
        screen_root,
        Rect2(394, 228, 786, 488),
        Color(0.014,0.030,0.050,0.92),
        Color(0.27,0.44,0.60,0.30),
        14
    )

    var scroll := ScrollContainer.new()
    scroll.position = Vector2(404,238)
    scroll.size = Vector2(766,422)
    scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
    scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
    scroll.scroll_deadzone = 10
    scroll.follow_focus = false
    screen_root.add_child(scroll)
    collection_mobile_scroll = scroll

    _build_collection_mobile_canvas(scroll)
    call_deferred("_restore_collection_mobile_scroll")

    _label_in(
        screen_root,
        "COLLECTION",
        Rect2(38, 260, 310, 38),
        25,
        Color("f4f8fb"),
        HORIZONTAL_ALIGNMENT_CENTER,
        true
    )
    _label_in(
        screen_root,
        "Même rendu que le Draft\n70 Ninjas dans un seul atlas\nAucune armée de Nodes par carte",
        Rect2(42, 316, 300, 110),
        13,
        Color("9eb3c4"),
        HORIZONTAL_ALIGNMENT_CENTER,
        false
    )
    _label_in(
        screen_root,
        "GLISSE POUR DÉFILER\nTOUCHE POUR LIRE",
        Rect2(1210, 316, 300, 92),
        16,
        Color("69c9f0"),
        HORIZONTAL_ALIGNMENT_CENTER,
        true
    )

    footer_notice.text = "Collection : possession réelle + gratuites de la semaine • cartes non possédées grisées mais consultables."

func _build_collection_mobile_canvas(scroll: ScrollContainer) -> void:
    var available_by_id: Dictionary = {}
    var interactive_by_id: Dictionary = {}
    var reason_by_id: Dictionary = {}

    for data: Dictionary in collection_mobile_cards:
        var cid: String = str(data.get("id",""))
        var matches: bool = _card_matches_filters(data, collection_search_query, collection_role_filters)
        var owned_now: bool = _shop_is_currently_owned(data)
        available_by_id[cid] = matches and owned_now
        # Même non possédée, la carte reste consultable dans la Collection.
        interactive_by_id[cid] = matches
        if not matches:
            reason_by_id[cid] = "HORS FILTRE"
        elif not owned_now:
            reason_by_id[cid] = "NON POSSÉDÉE"
        else:
            reason_by_id[cid] = ""

    var canvas: YugitoDraftCanvas = DraftCanvas.new()
    canvas.configure(
        collection_mobile_cards,
        {},
        available_by_id,
        interactive_by_id,
        reason_by_id,
        collection_selected_id
    )
    canvas.card_tapped.connect(_on_collection_mobile_card_tapped)
    scroll.add_child(canvas)
    collection_mobile_canvas = canvas

    _refresh_collection_mobile_count()

func _refresh_collection_mobile_canvas() -> void:
    if not MobilePlatform.is_android() or not is_instance_valid(collection_mobile_canvas):
        return

    var available_by_id: Dictionary = {}
    var interactive_by_id: Dictionary = {}
    var reason_by_id: Dictionary = {}

    for data: Dictionary in collection_mobile_cards:
        var cid: String = str(data.get("id",""))
        var matches: bool = _card_matches_filters(data, collection_search_query, collection_role_filters)
        var owned_now: bool = _shop_is_currently_owned(data)
        available_by_id[cid] = matches and owned_now
        # Même non possédée, la carte reste consultable dans la Collection.
        interactive_by_id[cid] = matches
        if not matches:
            reason_by_id[cid] = "HORS FILTRE"
        elif not owned_now:
            reason_by_id[cid] = "NON POSSÉDÉE"
        else:
            reason_by_id[cid] = ""

    collection_mobile_canvas.configure(
        collection_mobile_cards,
        {},
        available_by_id,
        interactive_by_id,
        reason_by_id,
        collection_selected_id
    )
    _refresh_collection_mobile_count()

func _refresh_collection_mobile_count() -> void:
    if collection_count_label == null:
        return
    var matches: int = 0
    for data: Dictionary in collection_mobile_cards:
        if _card_matches_filters(data, collection_search_query, collection_role_filters):
            matches += 1
    collection_count_label.text = "%d résultat%s • %d filtre%s" % [
        matches,
        "" if matches == 1 else "s",
        collection_role_filters.size(),
        "" if collection_role_filters.size() == 1 else "s"
    ]

func _capture_collection_mobile_scroll() -> void:
    if MobilePlatform.is_android() and is_instance_valid(collection_mobile_scroll):
        collection_mobile_saved_scroll = float(collection_mobile_scroll.scroll_vertical)

func _restore_collection_mobile_scroll() -> void:
    if is_instance_valid(collection_mobile_scroll):
        collection_mobile_scroll.scroll_vertical = int(maxf(0.0, collection_mobile_saved_scroll))

func _collection_mobile_art(cid: String) -> Texture2D:
    var index: int = int(collection_mobile_index_by_id.get(cid,-1))
    if index < 0:
        return AssetCache.texture("res://assets/cards/%s_field.png" % cid)
    return DraftCanvas.card_art_texture(index)

func _on_collection_mobile_card_tapped(cid: String) -> void:
    _play_ui_sound()
    _capture_collection_mobile_scroll()
    collection_selected_id = cid
    if is_instance_valid(collection_mobile_canvas):
        collection_mobile_canvas.set_selected(cid)
    _open_collection_mobile_sheet(cid)

func _open_collection_mobile_sheet(cid: String) -> void:
    var data: Dictionary = cards_by_id.get(cid,{}) as Dictionary
    if data.is_empty():
        return

    if is_instance_valid(collection_mobile_detail_root):
        collection_mobile_detail_root.queue_free()

    var root := Control.new()
    root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    root.mouse_filter = Control.MOUSE_FILTER_STOP
    root.z_index = 4000
    screen_root.add_child(root)
    collection_mobile_detail_root = root

    var dim := ColorRect.new()
    dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    dim.color = Color(0.002,0.006,0.012,0.94)
    dim.mouse_filter = Control.MOUSE_FILTER_STOP
    root.add_child(dim)

    # Même fenêtre que le Draft.
    var win: Panel = _panel_in(
        root,
        Rect2(120,52,1360,746),
        Color(0.010,0.024,0.041,1.0),
        Color(0.42,0.68,0.86,0.82),
        18,
        12
    )

    _label_in(
        win,
        "FICHE NINJA — COLLECTION",
        Rect2(34,18,820,42),
        28,
        Color("f4f8fb"),
        HORIZONTAL_ALIGNMENT_LEFT,
        true
    )

    var close := _button_in(
        win,
        Rect2(1170,18,150,46),
        "FERMER",
        Color("8cb9d8"),
        false
    )
    close.add_theme_font_size_override("font_size",12)
    close.pressed.connect(_close_collection_mobile_sheet)

    # Gauche = présentation strictement dérivée de la fiche Draft.
    var card_box: Panel = _panel_in(
        win,
        Rect2(38,84,430,620),
        Color(0.006,0.014,0.024,0.98),
        Color(0.55,0.75,0.90,0.55),
        16,
        6
    )

    _label_in(
        card_box,
        str(data.get("name",cid)),
        Rect2(16,10,398,38),
        22,
        Color("ffffff"),
        HORIZONTAL_ALIGNMENT_CENTER,
        true
    )

    var art := TextureRect.new()
    art.position = Vector2(16,52)
    art.size = Vector2(398,354)
    art.texture = _collection_mobile_art(cid)
    art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
    art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
    art.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
    art.mouse_filter = Control.MOUSE_FILTER_IGNORE
    card_box.add_child(art)

    _label_in(
        card_box,
        "%s★  •  %s" % [
            _stars_text(float(data.get("stars",0.0))),
            str(data.get("element","")).to_upper()
        ],
        Rect2(16,420,398,32),
        16,
        _element_color(str(data.get("element",""))),
        HORIZONTAL_ALIGNMENT_CENTER,
        true
    )

    _label_in(card_box,"PV\n%d" % int(data.get("hp",0)),Rect2(18,472,92,70),15,Color("f0f4f7"),HORIZONTAL_ALIGNMENT_CENTER,true)
    _label_in(card_box,"TAI\n%d" % int(data.get("taijutsu",0)),Rect2(112,472,92,70),15,Color("ef6659"),HORIZONTAL_ALIGNMENT_CENTER,true)
    _label_in(card_box,"NIN\n%d" % int(data.get("ninjutsu",0)),Rect2(206,472,92,70),15,Color("58aff0"),HORIZONTAL_ALIGNMENT_CENTER,true)
    _label_in(card_box,"GEN\n%d" % int(data.get("genjutsu",0)),Rect2(300,472,108,70),15,Color("ba85ed"),HORIZONTAL_ALIGNMENT_CENTER,true)

    var roles: Array = data.get("roles",[]) as Array
    var role_labels: Array[String] = []
    for role: Variant in roles:
        role_labels.append(_role_label(str(role)))

    _label_in(
        card_box,
        "RÔLES  •  %s" % (" • ".join(role_labels) if not role_labels.is_empty() else "—"),
        Rect2(20,562,390,36),
        11,
        Color("9fcde9"),
        HORIZONTAL_ALIGNMENT_CENTER,
        true
    )

    # Droite : on récupère TOUT l'espace qu'occupait le CTA du Draft.
    # Donc texte plus gros et panneau scroll de 600 px de haut.
    var info_panel: Panel = _panel_in(
        win,
        Rect2(492,76,836,628),
        Color(0.006,0.016,0.028,0.92),
        Color(0.42,0.68,0.86,0.34),
        15,
        6
    )

    var info_scroll := ScrollContainer.new()
    info_scroll.position = Vector2(20,18)
    info_scroll.size = Vector2(796,590)
    info_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
    info_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
    info_scroll.scroll_deadzone = 10
    info_panel.add_child(info_scroll)

    var rich := RichTextLabel.new()
    rich.custom_minimum_size = Vector2(760,860)
    rich.bbcode_enabled = true
    rich.fit_content = true
    rich.scroll_active = false
    rich.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    rich.add_theme_font_size_override("normal_font_size",18)
    rich.add_theme_color_override("default_color",Color("dce8f1"))

    rich.text = """[color=#9fcde9][font_size=20][b]RÔLES[/b][/font_size][/color]
%s

[color=#61d6a2][font_size=25][b]PASSIF — %s[/b][/font_size][/color]
%s

[color=#e4bf51][font_size=25][b]TECHNIQUE SPÉCIALE — %s[/b][/font_size][/color]
%s

[color=#58aff0][font_size=25][b]SYNERGIES[/b][/font_size][/color]
%s
""" % [
        " • ".join(role_labels) if not role_labels.is_empty() else "—",
        str(data.get("passive_name","—")),
        str(data.get("passive","—")),
        str(data.get("special_name","—")),
        str(data.get("special","—")),
        SynergyDB.description(cid,cards_by_id)
    ]
    info_scroll.add_child(rich)

func _close_collection_mobile_sheet() -> void:
    if is_instance_valid(collection_mobile_detail_root):
        collection_mobile_detail_root.queue_free()
    collection_mobile_detail_root = null
    call_deferred("_restore_collection_mobile_scroll")

func _build_collection_role_toolbar() -> void:
    var roles: Array[String] = CARD_ROLE_PRIMARY + CARD_ROLE_ADVANCED
    var x0: float = 44.0
    var y0: float = 164.0
    var bw: float = 101.0
    for i: int in range(roles.size()):
        var role: String = roles[i]
        var row: int = i / 10
        var col: int = i % 10
        var active: bool = collection_role_filters.has(role)
        var btn: Button = _button_in(
            screen_root,
            Rect2(x0 + col * (bw + 5.0), y0 + row * (36.0 if MobilePlatform.is_android() else 34.0), bw, 34 if MobilePlatform.is_android() else 29),
            ("✓ " if active else "") + _role_label(role),
            Color("d28a31") if active else Color("40586f"),
            active
        )
        btn.add_theme_font_size_override("font_size", 7)
        btn.pressed.connect(_toggle_collection_role.bind(role))

func _toggle_collection_role(role: String) -> void:
    if collection_role_filters.has(role):
        collection_role_filters.erase(role)
    else:
        collection_role_filters.append(role)
    if MobilePlatform.is_android():
        _capture_collection_mobile_scroll()
        _show_collection()
    else:
        _show_collection()

func _clear_collection_filters() -> void:
    collection_search_query = ""
    collection_role_filters.clear()
    if MobilePlatform.is_android():
        _capture_collection_mobile_scroll()
    _show_collection()

func _on_collection_search_changed(value: String) -> void:
    collection_search_query = value
    if MobilePlatform.is_android():
        _refresh_collection_mobile_canvas()
    else:
        _refresh_collection_grid()

func _refresh_collection_grid() -> void:
    if collection_grid == null:
        return
    for child: Node in collection_grid.get_children():
        child.queue_free()
    var filtered: Array[Dictionary] = _filtered_collection_cards()
    for data: Dictionary in filtered:
        collection_grid.add_child(_collection_tile(data))
    if collection_count_label:
        collection_count_label.text = "%d résultat%s • %d filtre%s rôle" % [
            filtered.size(),
            "" if filtered.size() == 1 else "s",
            collection_role_filters.size(),
            "" if collection_role_filters.size() == 1 else "s",
        ]

func _collection_tile(data: Dictionary) -> Button:
    var cid: String = str(data.get("id", ""))
    var roles: Array = data.get("roles",[]) as Array
    var short_roles: Array[String] = []
    for i: int in range(mini(2, roles.size())):
        short_roles.append(_role_label(str(roles[i])))
    var role_text: String = " • ".join(short_roles)
    var card: YugitoMenuCard = MenuCard.new()
    var mobile_size: Vector2 = Vector2(300, 430) if MobilePlatform.is_android() else Vector2(286, 420)
    card.setup(data, mobile_size, cid == collection_selected_id, false, role_text if not role_text.is_empty() else "OUVRIR LA FICHE")
    card.pressed.connect(_on_collection_card_pressed.bind(cid))
    return card

func _on_collection_card_pressed(card_id: String) -> void:
    _play_ui_sound()
    collection_selected_id = card_id
    _show_collection()

func _build_collection_detail(rect: Rect2) -> void:
    var data: Dictionary = cards_by_id.get(collection_selected_id, {}) as Dictionary
    if data.is_empty() and not sorted_cards.is_empty():
        data = sorted_cards[0]
        collection_selected_id = str(data.get("id", ""))
    var cid: String = str(data.get("id", ""))
    var accent: Color = _element_color(str(data.get("element", "")))
    _panel_in(screen_root, rect, Color(0.018,0.038,0.062,0.97), Color(accent.r,accent.g,accent.b,0.50), 14, 8)

    var art_panel: Panel = _panel_in(screen_root, Rect2(rect.position + Vector2(16,16), Vector2(rect.size.x-32,188)), Color(0.008,0.018,0.030,1), Color(accent.r,accent.g,accent.b,0.34), 9)
    art_panel.clip_contents = true
    var art: TextureRect = TextureRect.new()
    art.position = Vector2.ZERO
    art.size = art_panel.size
    art.texture = load("res://assets/cards/%s_field.png" % cid)
    art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
    art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
    art.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
    art.mouse_filter = Control.MOUSE_FILTER_IGNORE
    art_panel.add_child(art)
    var shade: ColorRect = ColorRect.new()
    shade.position = Vector2(0, 139)
    shade.size = Vector2(art_panel.size.x,49)
    shade.color = Color(0.01,0.02,0.04,0.62)
    shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
    art_panel.add_child(shade)
    _label_in(art_panel, str(data.get("name","Ninja")), Rect2(14,145,art_panel.size.x-28,35), 17, Color("f3f7fa"), HORIZONTAL_ALIGNMENT_LEFT, true)

    _label_in(screen_root, "%s★  •  %s  •  PV %d" % [_stars_text(float(data.get("stars",0.0))),str(data.get("element","")).to_upper(),int(data.get("hp",0))], Rect2(rect.position+Vector2(18,210),Vector2(rect.size.x-36,22)), 9, accent.lightened(0.12), HORIZONTAL_ALIGNMENT_LEFT, true)
    _label_in(screen_root, "TAI %d    NIN %d    GEN %d" % [int(data.get("taijutsu",0)),int(data.get("ninjutsu",0)),int(data.get("genjutsu",0))], Rect2(rect.position+Vector2(18,234),Vector2(rect.size.x-36,22)), 9, Color("b8c7d5"), HORIZONTAL_ALIGNMENT_LEFT, true)

    var roles: Array = data.get("roles",[]) as Array
    var role_labels: Array[String] = []
    for role: Variant in roles:
        role_labels.append(_role_label(str(role)))
    _label_in(screen_root, "RÔLES  " + (" • ".join(role_labels) if not role_labels.is_empty() else "—"), Rect2(rect.position+Vector2(18,258),Vector2(rect.size.x-36,22)), 8, Color("86bce6"), HORIZONTAL_ALIGNMENT_LEFT, true)
    _label_in(screen_root, "STATUT  BASE • GRATUITE • DISPONIBLE", Rect2(rect.position+Vector2(18,280),Vector2(rect.size.x-36,22)), 8, Color("63d49b"), HORIZONTAL_ALIGNMENT_LEFT, true)

    var scroll: ScrollContainer = ScrollContainer.new()
    scroll.position = rect.position + Vector2(16, 308)
    scroll.size = Vector2(rect.size.x - 32, rect.size.y - 324)
    scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
    screen_root.add_child(scroll)
    var rich: RichTextLabel = RichTextLabel.new()
    rich.custom_minimum_size = Vector2(rect.size.x - 52, 650)
    rich.bbcode_enabled = true
    rich.fit_content = true
    rich.scroll_active = false
    rich.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    rich.add_theme_font_size_override("normal_font_size", 8)
    rich.add_theme_color_override("default_color", Color("bdcad6"))
    rich.text = "[color=#61d6a2][b]PASSIF — %s[/b][/color]\n%s\n\n[color=#e4bf51][b]SPÉCIALE — %s[/b][/color]\n%s\n\n[color=#58aff0][b]SYNERGIES[/b][/color]\n%s" % [str(data.get("passive_name","—")),str(data.get("passive","—")),str(data.get("special_name","—")),str(data.get("special","—")),SynergyDB.description(cid,cards_by_id)]
    scroll.add_child(rich)

func _show_deck_builder() -> void:
    _destroy_home_overlay()
    current_screen = "deck"
    _clear_screen()

    if MobilePlatform.is_android():
        _show_deck_builder_mobile_like_draft()
        return

    var total: float = _deck_total_stars()
    _screen_heading("CRÉE TON DECK", "%d/8 cartes • %.1f/32.5★ • filtres et quotas en direct" % [deck_ids.size(), total])

    _panel_in(screen_root, Rect2(30, 100, 1068, 616), Color(0.015,0.031,0.052,0.84), Color(0.25,0.43,0.59,0.28), 14)
    var search := LineEdit.new()
    search.position = Vector2(44, 116)
    search.size = Vector2(330, 44 if MobilePlatform.is_android() else 38)
    search.placeholder_text = "Rechercher une carte pour ton deck…"
    search.text = deck_search_query
    search.add_theme_font_size_override("font_size", 11)
    screen_root.add_child(search)
    _style_glass_line_edit(search)
    search.text_changed.connect(_on_deck_search_changed)
    deck_count_label = _label_in(screen_root, "", Rect2(390, 118, 230, 34), 10, Color("9fb3c6"), HORIZONTAL_ALIGNMENT_LEFT, true)
    var reset_btn: Button = _button_in(screen_root, Rect2(950, 116, 132, 38), "FILTRES ×", Color("70879d"), false)
    reset_btn.pressed.connect(_clear_deck_filters)

    _build_deck_role_toolbar()
    var scroll := ScrollContainer.new()
    scroll.position = Vector2(44, 244)
    scroll.size = Vector2(1040, 458)
    scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
    screen_root.add_child(scroll)
    deck_grid = GridContainer.new()
    deck_grid.columns = 3
    deck_grid.add_theme_constant_override("h_separation", 10)
    deck_grid.add_theme_constant_override("v_separation", 10)
    scroll.add_child(deck_grid)
    _refresh_deck_grid()

    _build_deck_panel(Rect2(1118, 100, 416, 616))
    footer_notice.text = deck_notice

func _show_deck_builder_mobile_like_draft() -> void:
    _prepare_deck_mobile_cards()

    _screen_heading(
        "CRÉE TON DECK",
        "%d/8 cartes • %.1f/32,5★ • même catalogue fluide que le Draft" % [deck_ids.size(), _deck_total_stars()]
    )

    # LEFT — deck actuel, toujours visible.
    _panel_in(
        screen_root,
        Rect2(18,100,286,616),
        Color(0.014,0.030,0.050,0.94),
        Color(0.34,0.55,0.70,0.34),
        15,
        6
    )
    _label_in(screen_root,"TON DECK",Rect2(34,116,254,34),21,Color("f4f8fb"),HORIZONTAL_ALIGNMENT_CENTER,true)
    _label_in(
        screen_root,
        "%d / 8  •  %.1f / 32,5★" % [deck_ids.size(),_deck_total_stars()],
        Rect2(34,150,254,28),
        12,
        Color("e6c95b"),
        HORIZONTAL_ALIGNMENT_CENTER,
        true
    )

    var yy: float = 190.0
    for slot: int in range(MAX_DECK_SIZE):
        var has_card: bool = slot < deck_ids.size()
        var cid: String = deck_ids[slot] if has_card else ""
        var data: Dictionary = cards_by_id.get(cid,{}) as Dictionary
        var accent: Color = _element_color(str(data.get("element",""))) if has_card else Color("657788")

        _panel_in(
            screen_root,
            Rect2(32,yy,258,48),
            Color(0.020,0.041,0.066,0.90),
            Color(accent.r,accent.g,accent.b,0.40),
            9
        )
        _label_in(screen_root,"%02d" % (slot+1),Rect2(40,yy+7,28,32),9,Color("73899e"),HORIZONTAL_ALIGNMENT_CENTER,true)
        _label_in(
            screen_root,
            str(data.get("name","EMPLACEMENT LIBRE")),
            Rect2(72,yy+6,154,32),
            10,
            Color("e0e8ef") if has_card else Color("66798a"),
            HORIZONTAL_ALIGNMENT_LEFT,
            true
        )
        if has_card:
            _label_in(
                screen_root,
                "%s★" % _stars_text(float(data.get("stars",0.0))),
                Rect2(228,yy+7,48,32),
                9,
                accent,
                HORIZONTAL_ALIGNMENT_CENTER,
                true
            )
        yy += 55.0

    var clear_panel := _panel_in(
        screen_root,
        Rect2(32,648,120,50),
        Color(0.16,0.035,0.045,0.95),
        Color(0.86,0.36,0.40,0.92),
        12,
        4
    )
    var clear_btn := _button_in(clear_panel,Rect2(0,0,120,50),"VIDER",Color("e85c66"),true)
    clear_btn.disabled = deck_ids.is_empty()
    clear_btn.pressed.connect(_clear_deck)

    var legal: bool = _deck_is_legal()
    var save_accent: Color = Color("55d58b") if legal else Color("64727f")
    var save_panel := _panel_in(
        screen_root,
        Rect2(164,648,126,50),
        Color(save_accent.r*0.18,save_accent.g*0.18,save_accent.b*0.18,0.96),
        Color(save_accent.r,save_accent.g,save_accent.b,0.92),
        12,
        4
    )
    var save_btn := _button_in(save_panel,Rect2(0,0,126,50),"SAUVER",save_accent,true)
    save_btn.disabled = not legal
    save_btn.pressed.connect(_save_deck)

    # CENTER — même catalogue exact que le Draft.
    var search := LineEdit.new()
    search.position = Vector2(326,106)
    search.size = Vector2(626,50)
    search.placeholder_text = "Rechercher une carte…"
    search.text = deck_search_query
    search.add_theme_font_size_override("font_size",15)
    screen_root.add_child(search)
    _style_glass_line_edit(search)
    search.text_changed.connect(_on_deck_search_changed)

    deck_count_label = _label_in(
        screen_root,"",Rect2(970,112,250,34),12,Color("d7e4ed"),HORIZONTAL_ALIGNMENT_LEFT,true
    )

    var reset := _button_in(screen_root,Rect2(1208,106,126,50),"EFFACER",Color("70879d"),true)
    reset.add_theme_font_size_override("font_size",11)
    reset.pressed.connect(_clear_deck_filters)

    var role_scroll := ScrollContainer.new()
    role_scroll.position = Vector2(326,164)
    role_scroll.size = Vector2(1008,48)
    role_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
    role_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
    role_scroll.scroll_deadzone = 10
    screen_root.add_child(role_scroll)

    var role_row := HBoxContainer.new()
    role_row.add_theme_constant_override("separation",7)
    role_scroll.add_child(role_row)

    var roles: Array[String] = CARD_ROLE_PRIMARY + CARD_ROLE_ADVANCED
    for role: String in roles:
        var active: bool = deck_role_filters.has(role)
        var rb := _button_in(
            role_row,
            Rect2(0,0,138,44),
            ("✓ " if active else "") + _role_label(role),
            Color("d28a31") if active else Color("40586f"),
            active
        )
        rb.custom_minimum_size = Vector2(138,44)
        rb.add_theme_font_size_override("font_size",10)
        rb.pressed.connect(_toggle_deck_role.bind(role))

    _panel_in(
        screen_root,
        Rect2(424,274,786,442),
        Color(0.014,0.030,0.050,0.92),
        Color(0.27,0.44,0.60,0.30),
        14
    )

    var scroll := ScrollContainer.new()
    scroll.position = Vector2(434,284)
    scroll.size = Vector2(766,422)
    scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
    scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
    scroll.scroll_deadzone = 10
    scroll.follow_focus = false
    screen_root.add_child(scroll)
    deck_mobile_scroll = scroll
    _build_deck_mobile_canvas(scroll)
    call_deferred("_restore_deck_mobile_scroll")

    # RIGHT — règles toujours lisibles.
    _panel_in(
        screen_root,
        Rect2(1228,228,304,488),
        Color(0.014,0.030,0.050,0.94),
        Color(0.34,0.55,0.70,0.34),
        15
    )
    _label_in(screen_root,"RÈGLES DU DECK",Rect2(1244,244,272,34),18,Color("f4f8fb"),HORIZONTAL_ALIGNMENT_CENTER,true)

    var quota_text: String = """8 NINJAS UNIQUES

MAXIMUM 32,5★

3★    ILLIMITÉ
3,5★  %d / 4
4★    %d / 3
4,5★  %d / 2
5★    %d / 1

Les cartes impossibles sont grisées.
Touche-les pour lire leur fiche
et voir pourquoi elles sont bloquées.""" % [
        _deck_star_count(3.5),
        _deck_star_count(4.0),
        _deck_star_count(4.5),
        _deck_star_count(5.0)
    ]
    _label_in(
        screen_root,
        quota_text,
        Rect2(1250,294,260,330),
        13,
        Color("c8d7e2"),
        HORIZONTAL_ALIGNMENT_CENTER,
        false
    )

    var status_color: Color = Color("55d58b") if legal else Color("e2b746")
    _capsule_in(
        screen_root,
        Rect2(1260,648,240,36),
        "DECK LÉGAL" if legal else "À COMPLÉTER",
        status_color
    )

    footer_notice.text = deck_notice

func _build_deck_mobile_canvas(scroll: ScrollContainer) -> void:
    var available_by_id: Dictionary = {}
    var interactive_by_id: Dictionary = {}
    var reason_by_id: Dictionary = {}

    for data: Dictionary in deck_mobile_cards:
        var cid: String = str(data.get("id",""))
        var matches: bool = _card_matches_filters(data, deck_search_query, deck_role_filters)
        var in_deck: bool = deck_ids.has(cid)
        var info: Dictionary = _deck_card_allowed(data)
        var owned_now: bool = _shop_is_currently_owned(data)

        if not matches:
            available_by_id[cid] = false
            interactive_by_id[cid] = false
            reason_by_id[cid] = "HORS FILTRE"
        elif not owned_now:
            available_by_id[cid] = false
            interactive_by_id[cid] = true
            reason_by_id[cid] = "NON POSSÉDÉE"
        elif in_deck:
            available_by_id[cid] = true
            interactive_by_id[cid] = true
            reason_by_id[cid] = "DANS TON DECK"
        else:
            var allowed: bool = bool(info.get("ok",false))
            available_by_id[cid] = allowed
            interactive_by_id[cid] = true
            reason_by_id[cid] = "" if allowed else _deck_canvas_lock_reason(str(info.get("reason","")))

    var canvas: YugitoDraftCanvas = DraftCanvas.new()
    canvas.configure(
        deck_mobile_cards,
        {},
        available_by_id,
        interactive_by_id,
        reason_by_id,
        ""
    )
    canvas.card_tapped.connect(_on_deck_mobile_card_tapped)
    scroll.add_child(canvas)
    deck_mobile_canvas = canvas
    _refresh_deck_mobile_count()

func _refresh_deck_mobile_canvas() -> void:
    if not MobilePlatform.is_android() or not is_instance_valid(deck_mobile_canvas):
        return

    var available_by_id: Dictionary = {}
    var interactive_by_id: Dictionary = {}
    var reason_by_id: Dictionary = {}

    for data: Dictionary in deck_mobile_cards:
        var cid: String = str(data.get("id",""))
        var matches: bool = _card_matches_filters(data, deck_search_query, deck_role_filters)
        var in_deck: bool = deck_ids.has(cid)
        var info: Dictionary = _deck_card_allowed(data)
        var owned_now: bool = _shop_is_currently_owned(data)

        if not matches:
            available_by_id[cid] = false
            interactive_by_id[cid] = false
            reason_by_id[cid] = "HORS FILTRE"
        elif not owned_now:
            available_by_id[cid] = false
            interactive_by_id[cid] = true
            reason_by_id[cid] = "NON POSSÉDÉE"
        elif in_deck:
            available_by_id[cid] = true
            interactive_by_id[cid] = true
            reason_by_id[cid] = "DANS TON DECK"
        else:
            var allowed: bool = bool(info.get("ok",false))
            available_by_id[cid] = allowed
            interactive_by_id[cid] = true
            reason_by_id[cid] = "" if allowed else _deck_canvas_lock_reason(str(info.get("reason","")))

    deck_mobile_canvas.configure(
        deck_mobile_cards,
        {},
        available_by_id,
        interactive_by_id,
        reason_by_id,
        ""
    )
    _refresh_deck_mobile_count()

func _deck_canvas_lock_reason(reason: String) -> String:
    if reason.contains("8 cartes"):
        return "DECK COMPLET"
    if reason.contains("32,5"):
        return "DÉPASSERAIT 32,5★"
    if reason.contains("Limite atteinte"):
        return "QUOTA ATTEINT"
    if reason.contains("déjà dans ton deck"):
        return "DÉJÀ DANS TON DECK"
    return reason

func _refresh_deck_mobile_count() -> void:
    if deck_count_label == null:
        return
    var matches: int = 0
    for data: Dictionary in deck_mobile_cards:
        if _card_matches_filters(data, deck_search_query, deck_role_filters):
            matches += 1
    deck_count_label.text = "%d carte%s" % [matches, "" if matches == 1 else "s"]

func _capture_deck_mobile_scroll() -> void:
    if MobilePlatform.is_android() and is_instance_valid(deck_mobile_scroll):
        deck_mobile_saved_scroll = float(deck_mobile_scroll.scroll_vertical)

func _restore_deck_mobile_scroll() -> void:
    if is_instance_valid(deck_mobile_scroll):
        deck_mobile_scroll.scroll_vertical = int(maxf(0.0,deck_mobile_saved_scroll))

func _deck_mobile_art(cid: String) -> Texture2D:
    var index: int = int(deck_mobile_index_by_id.get(cid,-1))
    if index < 0:
        return AssetCache.texture("res://assets/cards/%s_field.png" % cid)
    return DraftCanvas.card_art_texture(index)

func _on_deck_mobile_card_tapped(cid: String) -> void:
    _play_ui_sound()
    _capture_deck_mobile_scroll()
    if is_instance_valid(deck_mobile_canvas):
        deck_mobile_canvas.set_selected(cid)
    _open_deck_mobile_sheet(cid)

func _open_deck_mobile_sheet(cid: String) -> void:
    var data: Dictionary = cards_by_id.get(cid,{}) as Dictionary
    if data.is_empty():
        return

    if is_instance_valid(deck_mobile_detail_root):
        deck_mobile_detail_root.queue_free()

    var root := Control.new()
    root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    root.mouse_filter = Control.MOUSE_FILTER_STOP
    root.z_index = 4000
    screen_root.add_child(root)
    deck_mobile_detail_root = root

    var dim := ColorRect.new()
    dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    dim.color = Color(0.002,0.006,0.012,0.94)
    dim.mouse_filter = Control.MOUSE_FILTER_STOP
    root.add_child(dim)

    var win := _panel_in(
        root,
        Rect2(120,52,1360,746),
        Color(0.010,0.024,0.041,1.0),
        Color(0.42,0.68,0.86,0.82),
        18,
        12
    )

    _label_in(win,"FICHE NINJA — DECK",Rect2(34,18,760,42),28,Color("f4f8fb"),HORIZONTAL_ALIGNMENT_LEFT,true)

    var close := _button_in(win,Rect2(1170,18,150,46),"FERMER",Color("8cb9d8"),false)
    close.pressed.connect(_close_deck_mobile_sheet)

    var card_box := _panel_in(
        win,
        Rect2(38,84,430,620),
        Color(0.006,0.014,0.024,0.98),
        Color(0.55,0.75,0.90,0.55),
        16,
        6
    )
    _label_in(card_box,str(data.get("name",cid)),Rect2(16,10,398,38),22,Color("ffffff"),HORIZONTAL_ALIGNMENT_CENTER,true)

    var art := TextureRect.new()
    art.position = Vector2(16,52)
    art.size = Vector2(398,354)
    art.texture = _deck_mobile_art(cid)
    art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
    art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
    art.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
    art.mouse_filter = Control.MOUSE_FILTER_IGNORE
    card_box.add_child(art)

    _label_in(
        card_box,
        "%s★  •  %s" % [_stars_text(float(data.get("stars",0.0))),str(data.get("element","")).to_upper()],
        Rect2(16,420,398,32),
        16,
        _element_color(str(data.get("element",""))),
        HORIZONTAL_ALIGNMENT_CENTER,
        true
    )
    _label_in(card_box,"PV\n%d" % int(data.get("hp",0)),Rect2(18,472,92,70),15,Color("f0f4f7"),HORIZONTAL_ALIGNMENT_CENTER,true)
    _label_in(card_box,"TAI\n%d" % int(data.get("taijutsu",0)),Rect2(112,472,92,70),15,Color("ef6659"),HORIZONTAL_ALIGNMENT_CENTER,true)
    _label_in(card_box,"NIN\n%d" % int(data.get("ninjutsu",0)),Rect2(206,472,92,70),15,Color("58aff0"),HORIZONTAL_ALIGNMENT_CENTER,true)
    _label_in(card_box,"GEN\n%d" % int(data.get("genjutsu",0)),Rect2(300,472,108,70),15,Color("ba85ed"),HORIZONTAL_ALIGNMENT_CENTER,true)

    var roles: Array = data.get("roles",[]) as Array
    var role_labels: Array[String] = []
    for role: Variant in roles:
        role_labels.append(_role_label(str(role)))

    _label_in(
        card_box,
        "RÔLES  •  %s" % (" • ".join(role_labels) if not role_labels.is_empty() else "—"),
        Rect2(20,562,390,36),
        11,
        Color("9fcde9"),
        HORIZONTAL_ALIGNMENT_CENTER,
        true
    )

    # Droite : texte + CTA en bas, façon Draft.
    var info_panel := _panel_in(
        win,
        Rect2(492,84,836,480),
        Color(0.006,0.016,0.028,0.92),
        Color(0.42,0.68,0.86,0.34),
        15,
        6
    )

    var info_scroll := ScrollContainer.new()
    info_scroll.position = Vector2(20,18)
    info_scroll.size = Vector2(796,444)
    info_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
    info_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
    info_scroll.scroll_deadzone = 10
    info_panel.add_child(info_scroll)

    var rich := RichTextLabel.new()
    rich.custom_minimum_size = Vector2(760,760)
    rich.bbcode_enabled = true
    rich.fit_content = true
    rich.scroll_active = false
    rich.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    rich.add_theme_font_size_override("normal_font_size",17)
    rich.add_theme_color_override("default_color",Color("dce8f1"))
    rich.text = """[color=#61d6a2][font_size=23][b]PASSIF — %s[/b][/font_size][/color]
%s

[color=#e4bf51][font_size=23][b]TECHNIQUE SPÉCIALE — %s[/b][/font_size][/color]
%s

[color=#58aff0][font_size=22][b]SYNERGIES[/b][/font_size][/color]
%s
""" % [
        str(data.get("passive_name","—")),
        str(data.get("passive","—")),
        str(data.get("special_name","—")),
        str(data.get("special","—")),
        SynergyDB.description(cid,cards_by_id)
    ]
    info_scroll.add_child(rich)

    var in_deck: bool = deck_ids.has(cid)
    var info: Dictionary = _deck_card_allowed(data)
    var allowed: bool = bool(info.get("ok",false))
    var reason: String = str(info.get("reason",""))

    var cta_accent: Color = Color("e85c66") if in_deck else (Color("55d58b") if allowed else Color("66727d"))
    var cta_text: String = "RETIRER DU DECK" if in_deck else ("AJOUTER AU DECK" if allowed else "CARTE INDISPONIBLE")

    var cta_panel := _panel_in(
        win,
        Rect2(492,584,836,104),
        Color(cta_accent.r*0.16,cta_accent.g*0.16,cta_accent.b*0.16,0.98),
        Color(cta_accent.r,cta_accent.g,cta_accent.b,0.94),
        15,
        6
    )
    var cta := _button_in(cta_panel,Rect2(12,10,812,62),cta_text,cta_accent,true)
    cta.add_theme_font_size_override("font_size",18)
    cta.disabled = not in_deck and not allowed

    if in_deck:
        cta.pressed.connect(_deck_mobile_remove_from_sheet.bind(cid))
    elif allowed:
        cta.pressed.connect(_deck_mobile_add_from_sheet.bind(cid))

    _label_in(
        cta_panel,
        "Cette carte est déjà dans ton deck." if in_deck else ("Disponible • respecte actuellement toutes les règles." if allowed else reason),
        Rect2(20,74,796,24),
        10,
        Color("c8d6df") if (in_deck or allowed) else Color("e9a4a8"),
        HORIZONTAL_ALIGNMENT_CENTER,
        true
    )

func _deck_mobile_add_from_sheet(cid: String) -> void:
    _close_deck_mobile_sheet()
    _toggle_deck_card(cid)

func _deck_mobile_remove_from_sheet(cid: String) -> void:
    _close_deck_mobile_sheet()
    _remove_deck_card(cid)

func _close_deck_mobile_sheet() -> void:
    if is_instance_valid(deck_mobile_detail_root):
        deck_mobile_detail_root.queue_free()
    deck_mobile_detail_root = null
    call_deferred("_restore_deck_mobile_scroll")

func _build_deck_role_toolbar() -> void:
    var roles: Array[String] = CARD_ROLE_PRIMARY + CARD_ROLE_ADVANCED
    var x0: float = 44.0
    var y0: float = 164.0
    var bw: float = 96.0
    for i: int in range(roles.size()):
        var role: String = roles[i]
        var row: int = i / 10
        var col: int = i % 10
        var active: bool = deck_role_filters.has(role)
        var btn: Button = _button_in(
            screen_root,
            Rect2(x0 + col * (bw + 5.0), y0 + row * (36.0 if MobilePlatform.is_android() else 34.0), bw, 34 if MobilePlatform.is_android() else 29),
            ("✓ " if active else "") + _role_label(role),
            Color("d28a31") if active else Color("40586f"),
            active
        )
        btn.add_theme_font_size_override("font_size", 7)
        btn.pressed.connect(_toggle_deck_role.bind(role))

func _toggle_deck_role(role: String) -> void:
    if deck_role_filters.has(role):
        deck_role_filters.erase(role)
    else:
        deck_role_filters.append(role)
    if MobilePlatform.is_android():
        _capture_deck_mobile_scroll()
    _show_deck_builder()

func _clear_deck_filters() -> void:
    deck_search_query = ""
    deck_role_filters.clear()
    if MobilePlatform.is_android():
        _capture_deck_mobile_scroll()
    _show_deck_builder()

func _on_deck_search_changed(value: String) -> void:
    deck_search_query = value
    if MobilePlatform.is_android():
        _refresh_deck_mobile_canvas()
    else:
        _refresh_deck_grid()

func _refresh_deck_grid() -> void:
    if deck_grid == null:
        return
    for child: Node in deck_grid.get_children():
        child.queue_free()
    var filtered: Array[Dictionary] = _filtered_deck_cards()
    for data: Dictionary in filtered:
        deck_grid.add_child(_deck_tile(data))
    if deck_count_label:
        deck_count_label.text = "%d cartes affichées" % filtered.size()

func _deck_tile(data: Dictionary) -> Button:
    var cid: String = str(data.get("id", ""))
    var in_deck: bool = deck_ids.has(cid)
    var allowed_info: Dictionary = _deck_card_allowed(data)
    var allowed: bool = bool(allowed_info.get("ok", false))
    var reason: String = str(allowed_info.get("reason", ""))
    var status: String = "✓ DANS LE DECK" if in_deck else ("AJOUTER" if allowed else (reason if not reason.is_empty() else "VERROUILLÉ"))
    var card: YugitoMenuCard = MenuCard.new()
    var mobile_size: Vector2 = Vector2(286, 420) if MobilePlatform.is_android() else Vector2(270, 400)
    card.setup(data, mobile_size, in_deck, not in_deck and not allowed, status)
    card.disabled = not in_deck and not allowed
    card.pressed.connect(_toggle_deck_card.bind(cid))
    return card

func _build_deck_panel(rect: Rect2) -> void:
    _panel_in(screen_root, rect, Color(0.018,0.038,0.062,0.94), Color(0.31,0.49,0.65,0.36), 14, 8)
    _label_in(screen_root, "TON DECK", Rect2(rect.position + Vector2(20, 18), Vector2(180, 28)), 18, Color("f2f6fa"), HORIZONTAL_ALIGNMENT_LEFT, true)
    var legal: bool = _deck_is_legal()
    _capsule_in(screen_root, Rect2(rect.position + Vector2(262, 19), Vector2(132, 24)), "LÉGAL" if legal else "%d/8" % deck_ids.size(), Color("55d58b") if legal else Color("e2b746"))
    _label_in(screen_root, "%.1f / %.1f★" % [_deck_total_stars(), MAX_TOTAL_STARS], Rect2(rect.position + Vector2(20, 52), Vector2(180, 22)), 11, Color("e5c754"), HORIZONTAL_ALIGNMENT_LEFT, true)

    var quota_text: String = "3★ ∞   •   3,5★ %d/4   •   4★ %d/3\n4,5★ %d/2   •   5★ %d/1" % [
        _deck_star_count(3.5), _deck_star_count(4.0), _deck_star_count(4.5), _deck_star_count(5.0)
    ]
    _label_in(screen_root, quota_text, Rect2(rect.position + Vector2(20, 76), Vector2(370, 48)), 9, Color("8fa7bc"), HORIZONTAL_ALIGNMENT_LEFT, false)
    var yy: float = rect.position.y + 138.0
    for slot: int in range(MAX_DECK_SIZE):
        var has_card: bool = slot < deck_ids.size()
        var cid: String = deck_ids[slot] if has_card else ""
        var data: Dictionary = cards_by_id.get(cid, {}) as Dictionary
        var row_accent: Color = _element_color(str(data.get("element",""))) if has_card else Color("5b6c7d")
        _panel_in(screen_root, Rect2(rect.position.x + 18, yy, rect.size.x - 36, 43), Color(0.025,0.050,0.078,0.82), Color(row_accent.r,row_accent.g,row_accent.b,0.32), 8)
        _label_in(screen_root, "%02d" % (slot + 1), Rect2(rect.position.x + 30, yy + 5, 28, 32), 9, Color("71879c"), HORIZONTAL_ALIGNMENT_LEFT, true)
        _label_in(screen_root, str(data.get("name","EMPLACEMENT LIBRE")), Rect2(rect.position.x + 62, yy + 5, 220, 32), 10, Color("d8e2eb") if has_card else Color("697b8c"), HORIZONTAL_ALIGNMENT_LEFT, true)
        if has_card:
            _label_in(screen_root, "%s★" % _stars_text(float(data.get("stars",0.0))), Rect2(rect.position.x + 286, yy + 5, 50, 32), 9, row_accent, HORIZONTAL_ALIGNMENT_CENTER, true)
            var remove_btn: Button = _button_in(screen_root, Rect2(rect.position.x + 340, yy + 7, 54, 28), "×", Color("b85e64"), false)
            remove_btn.pressed.connect(_remove_deck_card.bind(cid))
        yy += 49.0
    var clear_btn: Button = _button_in(screen_root, Rect2(rect.position + Vector2(20, 548), Vector2(170, 44)), "VIDER", Color("b85e64"), false)
    clear_btn.disabled = deck_ids.is_empty()
    clear_btn.pressed.connect(_clear_deck)
    var save_btn: Button = _button_in(screen_root, Rect2(rect.position + Vector2(208, 548), Vector2(186, 44)), "SAUVEGARDER", Color("55d58b"), true)
    save_btn.disabled = not legal
    save_btn.pressed.connect(_save_deck)

func _toggle_deck_card(card_id: String) -> void:
    if deck_ids.has(card_id):
        _remove_deck_card(card_id)
        return
    var data: Dictionary = cards_by_id.get(card_id, {}) as Dictionary
    var info: Dictionary = _deck_card_allowed(data)
    if not bool(info.get("ok", false)):
        deck_notice = str(info.get("reason", "Carte interdite."))
        footer_notice.text = deck_notice
        return
    deck_ids.append(card_id)
    deck_notice = "%s ajouté au deck." % str(data.get("name",card_id))
    _play_ui_sound()
    _show_deck_builder()

func _remove_deck_card(card_id: String) -> void:
    if deck_ids.has(card_id):
        var data: Dictionary = cards_by_id.get(card_id, {}) as Dictionary
        deck_ids.erase(card_id)
        deck_notice = "%s retiré du deck." % str(data.get("name",card_id))
        _play_ui_sound()
        _show_deck_builder()

func _clear_deck() -> void:
    deck_ids.clear()
    deck_notice = "Deck vidé."
    _show_deck_builder()

func _deck_card_allowed(data: Dictionary) -> Dictionary:
    var cid: String = str(data.get("id", ""))
    if cid == "":
        return {"ok":false, "reason":"Carte invalide."}
    if deck_ids.has(cid):
        return {"ok":false, "reason":"Cette carte est déjà dans ton deck."}
    if deck_ids.size() >= MAX_DECK_SIZE:
        return {"ok":false, "reason":"Ton deck contient déjà 8 cartes."}
    var stars: float = float(data.get("stars", 0.0))
    var cap: int = int(STAR_CAPS.get(stars, -1))
    if cap >= 0 and _deck_star_count(stars) >= cap:
        return {"ok":false, "reason":"Limite atteinte pour les %s★." % _stars_text(stars)}
    if _deck_total_stars() + stars > MAX_TOTAL_STARS + 0.001:
        return {"ok":false, "reason":"Cette carte dépasserait la limite de 32,5★."}
    return {"ok":true, "reason":""}

func _deck_total_stars() -> float:
    var total: float = 0.0
    for cid: String in deck_ids:
        var data: Dictionary = cards_by_id.get(cid, {}) as Dictionary
        total += float(data.get("stars",0.0))
    return snappedf(total, 0.1)

func _deck_star_count(stars: float) -> int:
    var count: int = 0
    for cid: String in deck_ids:
        var data: Dictionary = cards_by_id.get(cid, {}) as Dictionary
        if is_equal_approx(float(data.get("stars",0.0)), stars):
            count += 1
    return count

func _deck_is_legal() -> bool:
    if deck_ids.size() != MAX_DECK_SIZE:
        return false
    if _deck_total_stars() > MAX_TOTAL_STARS + 0.001:
        return false
    for tier: Variant in STAR_CAPS.keys():
        var stars: float = float(tier)
        var cap: int = int(STAR_CAPS.get(stars, -1))
        if cap >= 0 and _deck_star_count(stars) > cap:
            return false
    return true

func _save_deck() -> void:
    if not _deck_is_legal():
        deck_notice = "Le deck doit contenir exactement 8 cartes et respecter les limites."
        footer_notice.text = deck_notice
        return
    var file: FileAccess = FileAccess.open("user://yugito_deck.json", FileAccess.WRITE)
    if file == null:
        deck_notice = "Impossible de sauvegarder le deck."
        return
    file.store_string(JSON.stringify(deck_ids))
    file.close()
    deck_notice = "Deck sauvegardé localement."
    footer_notice.text = deck_notice
    _play_ui_sound()

func _load_saved_deck() -> void:
    if not FileAccess.file_exists("user://yugito_deck.json"):
        return
    var file: FileAccess = FileAccess.open("user://yugito_deck.json", FileAccess.READ)
    if file == null:
        return
    var parsed: Variant = JSON.parse_string(file.get_as_text())
    if parsed is Array:
        var raw: Array = parsed as Array
        for value: Variant in raw:
            var cid: String = str(value)
            if cards_by_id.has(cid) and not deck_ids.has(cid) and deck_ids.size() < MAX_DECK_SIZE:
                deck_ids.append(cid)

func _show_shop() -> void:
    _destroy_home_overlay()
    current_screen = "shop"
    _clear_screen()
    if Economy != null and AuthManager.is_session_available():
        Economy.call("refresh_state",true)
    elif WeeklyCollection != null:
        WeeklyCollection.call("refresh",false)

    if MobilePlatform.is_android():
        _show_shop_mobile_like_draft()
        return

    _screen_heading("BOUTIQUE", "Cartes & boosters • interface économie Godot en préparation")
    _panel_in(screen_root,Rect2(270,180,1010,450),Color(0.014,0.030,0.050,0.94),Color(0.34,0.65,0.48,0.42),18)
    _label_in(screen_root,"BOUTIQUE YUGITO",Rect2(340,230,870,52),30,Color("f4f8fb"),HORIZONTAL_ALIGNMENT_CENTER,true)
    _label_in(
        screen_root,
        "La Boutique complète est désormais construite sur Android.\nLe backend économie/achats sera reconnecté à la parité Tkinter dans l'étape réseau.",
        Rect2(390,320,770,120),
        15,
        Color("b9cad6"),
        HORIZONTAL_ALIGNMENT_CENTER,
        false
    )
    footer_notice.text = "Boutique : UI Android active • économie réseau à reconnecter."

func _show_shop_mobile_like_draft() -> void:
    _prepare_shop_mobile_cards()

    _screen_heading(
        "BOUTIQUE",
        "Cartes & boosters • catalogue fluide type Draft"
    )

    # Gauche — identité Boutique.
    _panel_in(
        screen_root,
        Rect2(18,100,286,616),
        Color(0.014,0.030,0.050,0.94),
        Color(0.30,0.68,0.46,0.38),
        15,
        6
    )
    _label_in(screen_root,"BOUTIQUE",Rect2(34,118,254,38),24,Color("f4f8fb"),HORIZONTAL_ALIGNMENT_CENTER,true)
    _label_in(
        screen_root,
        "CARTES",
        Rect2(52,174,218,42),
        17,
        Color("65d79b"),
        HORIZONTAL_ALIGNMENT_CENTER,
        true
    )
    _label_in(
        screen_root,
        "PRIX DES CARTES\n\n3★      GRATUIT\n3,5★    500 YT\n4★      1000 YT\n4,5★    1500 YT\n5★      2000 YT\n\nROTATION SERVEUR : 22 CARTES / SEMAINE",
        Rect2(42,224,238,224),
        14,
        Color("b8cad6"),
        HORIZONTAL_ALIGNMENT_CENTER,
        false
    )

    var weekly_count: int = _shop_weekly_free_ids().size()
    var weekly_source: String = "AUTH SERVER" if _economy_state_available() else "INDISPONIBLE"
    _capsule_in(
        screen_root,
        Rect2(54,430,214,30),
        ("%d GRATUITES • %s" % [weekly_count,weekly_source]),
        Color("55d58b") if weekly_count > 0 else Color("d8aa4b")
    )

    var booster_panel := _panel_in(
        screen_root,
        Rect2(34,470,254,150),
        Color(0.020,0.041,0.066,0.92),
        Color(0.72,0.57,0.24,0.52),
        13
    )
    _label_in(booster_panel,"BOOSTERS",Rect2(12,12,230,30),17,Color("e6c75e"),HORIZONTAL_ALIGNMENT_CENTER,true)
    _label_in(
        booster_panel,
        "La section boosters utilisera\nla même économie que les cartes.",
        Rect2(18,54,218,62),
        11,
        Color("c8d6df"),
        HORIZONTAL_ALIGNMENT_CENTER,
        false
    )
    _capsule_in(booster_panel,Rect2(42,126,170,28),"À CONNECTER",Color("778694"))

    # Centre — même moteur que Draft/Collection/Deck.
    var search := LineEdit.new()
    search.position = Vector2(326,106)
    search.size = Vector2(626,50)
    search.placeholder_text = "Rechercher une carte…"
    search.text = shop_search_query
    search.add_theme_font_size_override("font_size",15)
    screen_root.add_child(search)
    _style_glass_line_edit(search)
    search.text_changed.connect(_on_shop_search_changed)

    var count_label := _label_in(
        screen_root,"",Rect2(970,112,230,34),12,Color("d7e4ed"),HORIZONTAL_ALIGNMENT_LEFT,true
    )
    count_label.name = "ShopCount"

    var reset := _button_in(screen_root,Rect2(1208,106,126,50),"EFFACER",Color("70879d"),true)
    reset.add_theme_font_size_override("font_size",11)
    reset.pressed.connect(_clear_shop_filters)

    var role_scroll := ScrollContainer.new()
    role_scroll.position = Vector2(326,166)
    role_scroll.size = Vector2(1008,52)
    role_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
    role_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
    role_scroll.scroll_deadzone = 10
    screen_root.add_child(role_scroll)

    var role_row := HBoxContainer.new()
    role_row.add_theme_constant_override("separation",7)
    role_scroll.add_child(role_row)

    var roles: Array[String] = CARD_ROLE_PRIMARY + CARD_ROLE_ADVANCED
    for role: String in roles:
        var active: bool = shop_role_filters.has(role)
        var rb := _button_in(
            role_row,
            Rect2(0,0,138,44),
            ("✓ " if active else "") + _role_label(role),
            Color("d28a31") if active else Color("40586f"),
            active
        )
        rb.custom_minimum_size = Vector2(138,44)
        rb.add_theme_font_size_override("font_size",10)
        rb.pressed.connect(_toggle_shop_role.bind(role))

    var own_filters: Array[Dictionary] = [
        {"id":"current","label":"ACTUELLEMENT POSSÉDÉES","color":Color("55d58b")},
        {"id":"permanent","label":"RÉELLEMENT POSSÉDÉES","color":Color("58aff0")},
        {"id":"missing","label":"NON POSSÉDÉES","color":Color("e06d70")},
    ]
    var own_x: float = 424.0
    for filter_data: Dictionary in own_filters:
        var filter_id: String = str(filter_data.get("id",""))
        var active: bool = shop_ownership_filter == filter_id
        var fb := _button_in(
            screen_root,
            Rect2(own_x,220,244,46),
            ("✓ " if active else "") + str(filter_data.get("label","")),
            filter_data.get("color",Color("70879d")) as Color,
            active
        )
        fb.add_theme_font_size_override("font_size",10)
        fb.pressed.connect(_shop_toggle_ownership_filter.bind(filter_id))
        own_x += 254.0

    _panel_in(
        screen_root,
        Rect2(424,274,786,442),
        Color(0.014,0.030,0.050,0.92),
        Color(0.27,0.44,0.60,0.30),
        14
    )

    var scroll := ScrollContainer.new()
    scroll.position = Vector2(434,284)
    scroll.size = Vector2(766,468)
    scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
    scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
    scroll.scroll_deadzone = 10
    scroll.follow_focus = false
    screen_root.add_child(scroll)
    shop_mobile_scroll = scroll

    _build_shop_mobile_canvas(scroll)
    call_deferred("_restore_shop_mobile_scroll")

    # Droite — statut économie.
    _panel_in(
        screen_root,
        Rect2(1228,228,304,488),
        Color(0.014,0.030,0.050,0.94),
        Color(0.30,0.68,0.46,0.34),
        15
    )
    _label_in(screen_root,"ACHATS",Rect2(1244,246,272,34),18,Color("f4f8fb"),HORIZONTAL_ALIGNMENT_CENTER,true)
    _label_in(
        screen_root,
        "MONNAIE : YT\n\nLes YT servent à acheter les\ncartes de la Boutique.\n\nL'ELO ne sera PAS dépensé :\nune future Boutique ELO\ndébloquera des récompenses\nquand le joueur aura atteint\ncertains paliers.",
        Rect2(1250,306,260,280),
        14,
        Color("c8d7e2"),
        HORIZONTAL_ALIGNMENT_CENTER,
        false
    )
    _capsule_in(screen_root,Rect2(1260,620,240,36),"%d YT" % (_economy_balance()),Color("e0b84e"))

    footer_notice.text = "Boutique connectée : 3 filtres de possession • solde, rotation et achats synchronisés avec Auth Server."

func _build_shop_mobile_canvas(scroll: ScrollContainer) -> void:
    var available_by_id: Dictionary = {}
    var interactive_by_id: Dictionary = {}
    var reason_by_id: Dictionary = {}

    for data: Dictionary in shop_mobile_cards:
        var cid: String = str(data.get("id",""))
        var matches: bool = _shop_matches_all_filters(data)
        var base_filters_match: bool = _card_matches_filters(data,shop_search_query,shop_role_filters)
        var usable_now: bool = _shop_is_currently_owned(data)
        available_by_id[cid] = matches and usable_now
        # Une carte non possédée reste cliquable pour consulter sa fiche/prix.
        interactive_by_id[cid] = matches
        if not base_filters_match or not _shop_matches_ownership(data):
            reason_by_id[cid] = "HORS FILTRE"
        elif not usable_now:
            reason_by_id[cid] = "NON POSSÉDÉE"
        else:
            reason_by_id[cid] = ""

    var canvas: YugitoDraftCanvas = DraftCanvas.new()
    canvas.configure(
        shop_mobile_cards,
        {},
        available_by_id,
        interactive_by_id,
        reason_by_id,
        ""
    )
    canvas.card_tapped.connect(_on_shop_mobile_card_tapped)
    scroll.add_child(canvas)
    shop_mobile_canvas = canvas
    _refresh_shop_mobile_count()

func _refresh_shop_mobile_canvas() -> void:
    if not MobilePlatform.is_android() or not is_instance_valid(shop_mobile_canvas):
        return

    var available_by_id: Dictionary = {}
    var interactive_by_id: Dictionary = {}
    var reason_by_id: Dictionary = {}

    for data: Dictionary in shop_mobile_cards:
        var cid: String = str(data.get("id",""))
        var matches: bool = _shop_matches_all_filters(data)
        var base_filters_match: bool = _card_matches_filters(data,shop_search_query,shop_role_filters)
        var usable_now: bool = _shop_is_currently_owned(data)
        available_by_id[cid] = matches and usable_now
        # Une carte non possédée reste cliquable pour consulter sa fiche/prix.
        interactive_by_id[cid] = matches
        if not base_filters_match or not _shop_matches_ownership(data):
            reason_by_id[cid] = "HORS FILTRE"
        elif not usable_now:
            reason_by_id[cid] = "NON POSSÉDÉE"
        else:
            reason_by_id[cid] = ""

    shop_mobile_canvas.configure(
        shop_mobile_cards,
        {},
        available_by_id,
        interactive_by_id,
        reason_by_id,
        ""
    )
    _refresh_shop_mobile_count()

func _refresh_shop_mobile_count() -> void:
    var lab := screen_root.get_node_or_null("ShopCount") as Label
    if lab == null:
        return
    var matches: int = 0
    for data: Dictionary in shop_mobile_cards:
        if _shop_matches_all_filters(data):
            matches += 1
    lab.text = "%d carte%s" % [matches, "" if matches == 1 else "s"]

func _on_shop_search_changed(value: String) -> void:
    shop_search_query = value
    _refresh_shop_mobile_canvas()

func _toggle_shop_role(role: String) -> void:
    if shop_role_filters.has(role):
        shop_role_filters.erase(role)
    else:
        shop_role_filters.append(role)
    _capture_shop_mobile_scroll()
    _show_shop()

func _clear_shop_filters() -> void:
    shop_search_query = ""
    shop_role_filters.clear()
    shop_ownership_filter = ""
    _capture_shop_mobile_scroll()
    _show_shop()

func _capture_shop_mobile_scroll() -> void:
    if MobilePlatform.is_android() and is_instance_valid(shop_mobile_scroll):
        shop_mobile_saved_scroll = float(shop_mobile_scroll.scroll_vertical)

func _restore_shop_mobile_scroll() -> void:
    if is_instance_valid(shop_mobile_scroll):
        shop_mobile_scroll.scroll_vertical = int(maxf(0.0,shop_mobile_saved_scroll))

func _shop_mobile_art(cid: String) -> Texture2D:
    var index: int = int(shop_mobile_index_by_id.get(cid,-1))
    if index < 0:
        return AssetCache.texture("res://assets/cards/%s_field.png" % cid)
    return DraftCanvas.card_art_texture(index)

func _on_shop_mobile_card_tapped(cid: String) -> void:
    _play_ui_sound()
    _capture_shop_mobile_scroll()
    if is_instance_valid(shop_mobile_canvas):
        shop_mobile_canvas.set_selected(cid)
    _open_shop_mobile_sheet(cid)

func _open_shop_mobile_sheet(cid: String) -> void:
    var data: Dictionary = cards_by_id.get(cid,{}) as Dictionary
    if data.is_empty():
        return

    if is_instance_valid(shop_mobile_detail_root):
        shop_mobile_detail_root.queue_free()

    var root := Control.new()
    root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    root.mouse_filter = Control.MOUSE_FILTER_STOP
    root.z_index = 4000
    screen_root.add_child(root)
    shop_mobile_detail_root = root

    var dim := ColorRect.new()
    dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    dim.color = Color(0.002,0.006,0.012,0.94)
    dim.mouse_filter = Control.MOUSE_FILTER_STOP
    root.add_child(dim)

    var win := _panel_in(
        root,
        Rect2(120,52,1360,746),
        Color(0.010,0.024,0.041,1.0),
        Color(0.35,0.75,0.52,0.82),
        18,
        12
    )

    _label_in(win,"FICHE NINJA — BOUTIQUE",Rect2(34,18,820,42),28,Color("f4f8fb"),HORIZONTAL_ALIGNMENT_LEFT,true)
    var close := _button_in(win,Rect2(1170,18,150,46),"FERMER",Color("8cb9d8"),false)
    close.pressed.connect(_close_shop_mobile_sheet)

    var card_box := _panel_in(
        win,
        Rect2(38,84,430,620),
        Color(0.006,0.014,0.024,0.98),
        Color(0.46,0.76,0.58,0.55),
        16,
        6
    )
    _label_in(card_box,str(data.get("name",cid)),Rect2(16,10,398,38),22,Color("ffffff"),HORIZONTAL_ALIGNMENT_CENTER,true)

    var art := TextureRect.new()
    art.position = Vector2(16,52)
    art.size = Vector2(398,354)
    art.texture = _shop_mobile_art(cid)
    art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
    art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
    art.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
    art.mouse_filter = Control.MOUSE_FILTER_IGNORE
    card_box.add_child(art)

    _label_in(
        card_box,
        "%s★  •  %s" % [_stars_text(float(data.get("stars",0.0))),str(data.get("element","")).to_upper()],
        Rect2(16,420,398,32),
        16,
        _element_color(str(data.get("element",""))),
        HORIZONTAL_ALIGNMENT_CENTER,
        true
    )
    _label_in(card_box,"PV\n%d" % int(data.get("hp",0)),Rect2(18,472,92,70),15,Color("f0f4f7"),HORIZONTAL_ALIGNMENT_CENTER,true)
    _label_in(card_box,"TAI\n%d" % int(data.get("taijutsu",0)),Rect2(112,472,92,70),15,Color("ef6659"),HORIZONTAL_ALIGNMENT_CENTER,true)
    _label_in(card_box,"NIN\n%d" % int(data.get("ninjutsu",0)),Rect2(206,472,92,70),15,Color("58aff0"),HORIZONTAL_ALIGNMENT_CENTER,true)
    _label_in(card_box,"GEN\n%d" % int(data.get("genjutsu",0)),Rect2(300,472,108,70),15,Color("ba85ed"),HORIZONTAL_ALIGNMENT_CENTER,true)

    var roles: Array = data.get("roles",[]) as Array
    var role_labels: Array[String] = []
    for role: Variant in roles:
        role_labels.append(_role_label(str(role)))

    _label_in(
        card_box,
        "RÔLES  •  %s" % (" • ".join(role_labels) if not role_labels.is_empty() else "—"),
        Rect2(20,562,390,36),
        11,
        Color("9fcde9"),
        HORIZONTAL_ALIGNMENT_CENTER,
        true
    )

    var info_panel := _panel_in(
        win,
        Rect2(492,84,836,480),
        Color(0.006,0.016,0.028,0.92),
        Color(0.42,0.68,0.86,0.34),
        15,
        6
    )
    var info_scroll := ScrollContainer.new()
    info_scroll.position = Vector2(20,18)
    info_scroll.size = Vector2(796,444)
    info_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
    info_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
    info_scroll.scroll_deadzone = 10
    info_panel.add_child(info_scroll)

    var rich := RichTextLabel.new()
    rich.custom_minimum_size = Vector2(760,760)
    rich.bbcode_enabled = true
    rich.fit_content = true
    rich.scroll_active = false
    rich.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    rich.add_theme_font_size_override("normal_font_size",17)
    rich.add_theme_color_override("default_color",Color("dce8f1"))
    rich.text = """[color=#61d6a2][font_size=23][b]PASSIF — %s[/b][/font_size][/color]
%s

[color=#e4bf51][font_size=23][b]TECHNIQUE SPÉCIALE — %s[/b][/font_size][/color]
%s

[color=#58aff0][font_size=22][b]SYNERGIES[/b][/font_size][/color]
%s
""" % [
        str(data.get("passive_name","—")),
        str(data.get("passive","—")),
        str(data.get("special_name","—")),
        str(data.get("special","—")),
        SynergyDB.description(cid,cards_by_id)
    ]
    info_scroll.add_child(rich)

    # Prix YT officiels. L'interface affiche désormais le vrai tarif.
    # La transaction reste désactivée tant que le compte Godot n'expose pas
    # encore le solde YT / la possession persistante.
    var stars: float = float(data.get("stars",0.0))
    var price: int = _shop_price_yt(stars)
    var price_label: String = "GRATUIT" if price <= 0 else "%d YT" % price
    var free_card: bool = price <= 0
    var ownership_status: String = _shop_ownership_status(data)
    var ownership_label: String = _shop_ownership_label(data)
    var cta_accent: Color = (
        Color("55d58b") if ownership_status in ["base","permanent"]
        else (Color("d8b84f") if ownership_status == "weekly" else Color("e06d70"))
    )

    var cta_panel := _panel_in(
        win,
        Rect2(492,584,836,104),
        Color(cta_accent.r*0.16,cta_accent.g*0.16,cta_accent.b*0.16,0.96),
        Color(cta_accent.r,cta_accent.g,cta_accent.b,0.92),
        15,
        6
    )
    var cta := _button_in(
        cta_panel,
        Rect2(12,10,812,62),
        (
            ownership_label if ownership_status in ["base","permanent","weekly"]
            else "ACHETER • %s" % price_label
        ),
        cta_accent,
        true
    )
    cta.add_theme_font_size_override("font_size",18)
    var can_afford: bool = _economy_balance() >= price
    var can_buy: bool = (
        ownership_status == "missing"
        and _shop_card_purchasable(data)
        and AuthManager.is_session_available()
        and can_afford
        and shop_pending_purchase_id.is_empty()
    )
    cta.disabled = not can_buy
    if can_buy:
        cta.pressed.connect(_purchase_shop_card.bind(cid))
    _label_in(
        cta_panel,
        (
            "Cette carte est utilisable cette semaine mais n'est pas acquise définitivement."
            if ownership_status == "weekly"
            else (
                "Carte disponible définitivement dans ton compte."
                if ownership_status in ["base","permanent"]
                else (
                    "PRIX : %s • SOLDE : %d YT%s" % [
                        price_label,
                        _economy_balance(),
                        "" if _economy_balance() >= price else " • YT INSUFFISANTS"
                    ]
                )
            )
        ),
        Rect2(20,74,796,24),
        10,
        Color("cfe7d9") if free_card else Color("d9cfa7"),
        HORIZONTAL_ALIGNMENT_CENTER,
        true
    )

func _close_shop_mobile_sheet() -> void:
    if is_instance_valid(shop_mobile_detail_root):
        shop_mobile_detail_root.queue_free()
    shop_mobile_detail_root = null
    call_deferred("_restore_shop_mobile_scroll")

func _show_guide() -> void:
    _destroy_home_overlay()
    current_screen = "guide"
    _clear_screen()

    if MobilePlatform.is_android():
        _show_guide_mobile()
        return

    _screen_heading("GUIDE CLASSIC", "Manuel de combat YUGITO • A1/A2, éléments, Switch, défenses, cooldowns, synergies et dégâts.")

    _panel_in(screen_root, Rect2(30, 100, 1504, 616), Color(0.012,0.027,0.046,0.94), Color(0.28,0.46,0.62,0.30), 14)
    var nav: VBoxContainer = VBoxContainer.new()
    nav.position = Vector2(48, 120)
    nav.size = Vector2(248, 570)
    nav.add_theme_constant_override("separation", 7)
    screen_root.add_child(nav)
    _label_in(nav, "CHAPITRES", Rect2(0,0,230,28), 15, Color("63d9a6"), HORIZONTAL_ALIGNMENT_LEFT, true)
    var chapters: Array[String] = ["BASE DU COMBAT","ROUE DES ÉLÉMENTS","A1 / A2","HIRAISHIN","SWITCH","DÉFENSES & ÉTATS","COOLDOWNS","SYNERGIES","DÉGÂTS & SURPLUS"]
    for chapter: String in chapters:
        var b := Button.new()
        b.text = chapter
        b.custom_minimum_size = Vector2(238, 42)
        b.add_theme_font_size_override("font_size", 9)
        b.add_theme_color_override("font_color",Color("ffffff"))
        var bs := StyleBoxFlat.new()
        bs.bg_color = Color(0.012,0.028,0.048,0.52)
        bs.border_color = Color(1,1,1,0.30)
        bs.set_border_width_all(1)
        bs.set_corner_radius_all(10)
        var bh := bs.duplicate() as StyleBoxFlat
        bh.bg_color = Color(0.030,0.060,0.090,0.68)
        bh.border_color = Color(0.75,0.91,1.0,0.72)
        b.add_theme_stylebox_override("normal",bs)
        b.add_theme_stylebox_override("hover",bh)
        b.add_theme_stylebox_override("pressed",bh)
        b.add_theme_stylebox_override("focus",bh)
        b.tooltip_text = "Ouvre directement le chapitre " + chapter
        nav.add_child(b)
        b.pressed.connect(_guide_jump.bind(chapter))

    var scroll := ScrollContainer.new()
    scroll.position = Vector2(316, 120)
    scroll.size = Vector2(1196, 570)
    scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
    screen_root.add_child(scroll)
    var rich := RichTextLabel.new()
    rich.name = "GuideRichText"
    rich.custom_minimum_size = Vector2(1140, 1650)
    rich.bbcode_enabled = true
    rich.fit_content = true
    rich.scroll_active = false
    rich.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    rich.add_theme_font_size_override("normal_font_size", 11)
    rich.add_theme_color_override("default_color", Color("c4d0dc"))
    rich.text = _classic_guide_bbcode()
    scroll.add_child(rich)
    footer_notice.text = "Guide Classic complet • les règles décrivent le moteur Godot audité contre le client PC."

func _show_guide_mobile() -> void:
    _screen_heading(
        "GUIDE CLASSIC",
        "Du premier Shifumi jusqu'à la victoire • toutes les règles expliquées pas à pas."
    )

    _panel_in(
        screen_root,
        Rect2(24,98,1508,618),
        Color(0.010,0.025,0.043,0.95),
        Color(0.32,0.53,0.70,0.34),
        16
    )

    var nav_scroll := ScrollContainer.new()
    nav_scroll.position = Vector2(42,114)
    nav_scroll.size = Vector2(1468,58)
    nav_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
    nav_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
    nav_scroll.scroll_deadzone = 10
    screen_root.add_child(nav_scroll)

    var nav_row := HBoxContainer.new()
    nav_row.add_theme_constant_override("separation",8)
    nav_scroll.add_child(nav_row)

    var chapters: Array[String] = [
        "1. SHIFUMI",
        "2. DRAFT",
        "3. 3 NINJAS",
        "4. DÉBUT DU DUEL",
        "5. LIRE UNE CARTE",
        "6. TAI / NIN / GEN",
        "7. DÉGÂTS",
        "8. ÉLÉMENTS",
        "9. PASSIFS",
        "10. SPÉCIALES",
        "11. A1 / A2",
        "12. SWITCH",
        "13. ÉTATS",
        "14. SYNERGIES",
        "15. K.O. / RÉSERVE",
        "16. VICTOIRE"
    ]
    for chapter: String in chapters:
        var b := _button_in(
            nav_row,
            Rect2(0,0,176,50),
            chapter,
            Color("466985"),
            true
        )
        b.custom_minimum_size = Vector2(176,50)
        b.add_theme_font_size_override("font_size",10)
        b.pressed.connect(_guide_mobile_jump.bind(chapter))

    var scroll := ScrollContainer.new()
    scroll.name = "GuideMobileScroll"
    scroll.position = Vector2(62,188)
    scroll.size = Vector2(1436,504)
    scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
    scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
    scroll.scroll_deadzone = 10
    screen_root.add_child(scroll)

    var rich := RichTextLabel.new()
    rich.name = "GuideMobileRichText"
    rich.custom_minimum_size = Vector2(1380,5900)
    rich.bbcode_enabled = true
    rich.fit_content = true
    rich.scroll_active = false
    rich.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    rich.add_theme_font_size_override("normal_font_size",18)
    rich.add_theme_color_override("default_color",Color("d8e4ed"))
    rich.text = _classic_guide_mobile_bbcode()
    scroll.add_child(rich)

    footer_notice.text = "Guide complet • Shifumi → Draft → Combat → Victoire • exemples inclus."

func _guide_mobile_jump(chapter: String) -> void:
    var scroll := screen_root.get_node_or_null("GuideMobileScroll") as ScrollContainer
    if scroll == null:
        return

    var map: Dictionary = {
        "1. SHIFUMI":0,
        "2. DRAFT":340,
        "3. 3 NINJAS":900,
        "4. DÉBUT DU DUEL":1210,
        "5. LIRE UNE CARTE":1540,
        "6. TAI / NIN / GEN":2020,
        "7. DÉGÂTS":2600,
        "8. ÉLÉMENTS":3200,
        "9. PASSIFS":3650,
        "10. SPÉCIALES":4030,
        "11. A1 / A2":4480,
        "12. SWITCH":5100,
        "13. ÉTATS":5540,
        "14. SYNERGIES":6080,
        "15. K.O. / RÉSERVE":6500,
        "16. VICTOIRE":7000
    }
    scroll.scroll_vertical = int(map.get(chapter,0))

func _classic_guide_mobile_bbcode() -> String:
    return """[color=#63d9a6][font_size=30][b]1. LE PREMIER SHIFUMI[/b][/font_size][/color]

Une partie YUGITO commence par un [b]Shifumi : Pierre / Feuille / Ciseaux[/b].

• Pierre bat Ciseaux.
• Ciseaux bat Feuille.
• Feuille bat Pierre.

Le gagnant du premier Shifumi obtient le [b]premier choix du Draft[/b].

[color=#9fcde9][font_size=21][b]EXEMPLE[/b][/font_size][/color]
Tu choisis Pierre.
L'adversaire choisit Ciseaux.
Tu gagnes : tu obtiens le premier pick du Draft.

Ce premier Shifumi ne donne pas encore le premier tour du combat. Il décide seulement qui commence le Draft.


[color=#63d9a6][font_size=30][b]2. LE DRAFT CLASSIC[/b][/font_size][/color]

Le Draft sert à construire les deux équipes de [b]8 Ninjas[/b].

Les joueurs choisissent les cartes l'un après l'autre selon l'ordre du Draft Classic. Les raretés se débloquent progressivement.

[color=#e6c75e][font_size=22][b]LIMITES D'ÉQUIPE[/b][/font_size][/color]
• 8 Ninjas uniques.
• Maximum total : [b]32,5★[/b].
• 3★ : illimité.
• 3,5★ : maximum 4.
• 4★ : maximum 3.
• 4,5★ : maximum 2.
• 5★ : maximum 1.

Une rareté déjà débloquée reste disponible ensuite tant que ton équipe respecte les limites.

[color=#9fcde9][font_size=21][b]EXEMPLE[/b][/font_size][/color]
Si les 5★ sont déjà débloquées mais que tu n'as encore choisi aucune 5★, tu peux toujours en prendre une plus tard si tu respectes 32,5★ et la limite de 1 carte 5★.

Les cartes impossibles sont grisées. Leur fiche indique pourquoi elles sont bloquées.


[color=#63d9a6][font_size=30][b]3. CHOISIR LES 3 NINJAS DE DÉPART[/b][/font_size][/color]

Après le Draft, chaque joueur possède 8 cartes.

Tu choisis alors [b]3 Ninjas parmi tes 8[/b] pour commencer sur le terrain.

Les 5 autres restent en [b]réserve[/b].

Ce choix est important : les passifs d'entrée, les synergies et les éléments de tes trois premiers Ninjas peuvent déjà influencer le début du duel.

[color=#9fcde9][font_size=21][b]EXEMPLE[/b][/font_size][/color]
Ton équipe contient Naruto, Sasuke, Sakura, Kakashi, Gaara, Temari, Shikamaru et Ino.
Tu choisis Naruto + Sasuke + Sakura.
Les cinq autres restent en réserve.


[color=#63d9a6][font_size=30][b]4. LE SECOND SHIFUMI ET LE DÉBUT DU DUEL[/b][/font_size][/color]

Juste avant le combat, un [b]second Shifumi[/b] est joué.

Cette fois, le gagnant obtient le [b]premier tour du combat[/b].

Le terrain commence avec :
• 3 Ninjas alliés.
• 3 Ninjas ennemis.
• les réserves de chaque joueur.
• les PV joueur.
• les actions A1 et A2 à préparer.

Chaque joueur possède [b]4000 PV joueur[/b].

Attention : les PV joueur sont différents des PV de tes cartes.


[color=#63d9a6][font_size=30][b]5. COMMENT LIRE UNE CARTE[/b][/font_size][/color]

Chaque Ninja possède plusieurs informations importantes.

[color=#ef6659][b]PV[/b][/color] : points de vie de la carte.
Quand ils tombent à 0, la carte est K.O. sauf effet spécial de survie/résurrection.

[color=#ef6659][b]TAI[/b][/color] : Taijutsu.
[color=#58aff0][b]NIN[/b][/color] : Ninjutsu.
[color=#ba85ed][b]GEN[/b][/color] : Genjutsu.

Ces trois valeurs servent [b]à la fois pour attaquer et pour défendre[/b].

La carte possède aussi :
• un élément ;
• une rareté en étoiles ;
• un passif ;
• une technique spéciale ;
• éventuellement des rôles et synergies.

[color=#9fcde9][font_size=21][b]PRINCIPE FONDAMENTAL[/b][/font_size][/color]
Il n'existe pas une statistique "attaque" et une statistique "défense" séparées.

TAI attaque TAI.
NIN attaque NIN.
GEN attaque GEN.


[color=#63d9a6][font_size=30][b]6. TAIJUTSU / NINJUTSU / GENJUTSU[/b][/font_size][/color]

Quand tu choisis une attaque normale, tu sélectionnes une catégorie.

[color=#ef6659][font_size=22][b]TAIJUTSU[/b][/font_size][/color]
Attaque physique / corps-à-corps.
La valeur TAI de l'attaquant est comparée à la valeur TAI de la cible.

[color=#58aff0][font_size=22][b]NINJUTSU[/b][/font_size][/color]
Techniques Ninja.
La valeur NIN de l'attaquant est comparée à la valeur NIN de la cible.

[color=#ba85ed][font_size=22][b]GENJUTSU[/b][/font_size][/color]
Illusions / contrôle mental.
La valeur GEN de l'attaquant est comparée à la valeur GEN de la cible.

[color=#9fcde9][font_size=21][b]EXEMPLE TAI[/b][/font_size][/color]
Ton Ninja possède 1400 TAI.
La cible possède 1000 TAI.
Différence = 400.
Avant modificateurs, l'attaque part donc sur une base de 400 dégâts.

[color=#9fcde9][font_size=21][b]EXEMPLE NIN[/b][/font_size][/color]
Ton Ninja possède 1200 NIN.
La cible possède 1500 NIN.
L'attaque est fortement défendue.
Les protections, passifs et règles de dégâts minimum peuvent ensuite intervenir.

Donc choisir la meilleure attaque ne signifie pas toujours choisir ta plus grosse statistique : il faut aussi regarder la défense correspondante de l'ennemi.


[color=#63d9a6][font_size=30][b]7. COMMENT SONT CALCULÉS LES DÉGÂTS[/b][/font_size][/color]

Pour une attaque normale, le moteur commence par comparer la statistique choisie :

[b]Attaque effective - Défense effective[/b]

Si l'attaque dépasse la défense, la différence devient la base de dégâts.

Le moteur applique ensuite les effets pouvant modifier le résultat :
• bonus/malus de statistiques ;
• passifs ;
• avantage élémentaire ;
• réduction de dégâts ;
• esquive ;
• bouclier ;
• effets qui ignorent une défense ;
• règles propres à certaines cartes.

[color=#9fcde9][font_size=21][b]EXEMPLE SIMPLE[/b][/font_size][/color]
Attaquant : 1500 NIN.
Défenseur : 1100 NIN.
Différence : 400.
Dégâts de base : 400 avant les autres effets.

[color=#f0a65a][font_size=21][b]SI L'ATTAQUE NE DÉPASSE PAS LA DÉFENSE[/b][/font_size][/color]
Le calcul brut peut tomber à zéro. Le moteur Classic possède ensuite sa propre sécurité anti-zéro lors de la résolution finale d'une vraie attaque, après certaines réductions et avant le bouclier.

[color=#f0a65a][font_size=21][b]ATTAQUES À DÉGÂTS FIXES[/b][/font_size][/color]
Certaines techniques annoncent directement une valeur : 300, 400, 500 dégâts fixes, etc.
Dans ce cas, leur fiche précise leurs règles : certaines ignorent une défense, une réduction, une esquive ou un bouclier.

Toujours lire la technique : une spéciale peut suivre des règles différentes d'une attaque normale.


[color=#63d9a6][font_size=30][b]8. LA ROUE DES ÉLÉMENTS[/b][/font_size][/color]

[color=#ef6256][b]FEU[/b][/color] → [color=#63d596][b]VENT[/b][/color] → [color=#c09aff][b]FOUDRE[/b][/color] → [color=#c79b6b][b]TERRE[/b][/color] → [color=#55b6f2][b]EAU[/b][/color] → [color=#ef6256][b]FEU[/b][/color]

Donc :
• FEU est fort contre VENT.
• VENT est fort contre FOUDRE.
• FOUDRE est forte contre TERRE.
• TERRE est forte contre EAU.
• EAU est forte contre FEU.

En cas d'avantage élémentaire sur une attaque qui inflige des dégâts, le moteur applique :
[b]dégâts × 1,10 puis +150[/b].

[color=#9fcde9][font_size=21][b]EXEMPLE[/b][/font_size][/color]
Une attaque devait infliger 400 dégâts.
L'attaquant possède l'avantage élémentaire.
400 × 1,10 = 440.
440 + 150 = [b]590 dégâts[/b].

Certaines cartes ont des règles particulières : leur passif ou leur spéciale peut modifier la logique normale d'élément.


[color=#63d9a6][font_size=30][b]9. QU'EST-CE QU'UN PASSIF ?[/b][/font_size][/color]

Un [b]passif[/b] est un effet propre au Ninja qui fonctionne automatiquement lorsque ses conditions sont remplies.

Tu n'appuies pas sur un bouton pour l'utiliser.

Un passif peut :
• augmenter des statistiques ;
• réduire les dégâts ;
• déclencher une esquive ;
• empoisonner ;
• soigner ;
• ressusciter ;
• réagir à une entrée sur le terrain ;
• modifier une attaque ;
• créer une règle unique.

[color=#9fcde9][font_size=21][b]EXEMPLE[/b][/font_size][/color]
Si un passif dit :
"Quand ce Ninja passe sous 25 % de PV, il se soigne de 600 PV une fois."

Tu n'as rien à sélectionner.
Dès que la condition est remplie, le jeu déclenche le passif automatiquement.

Certains passifs sont uniques par combat, d'autres peuvent fonctionner plusieurs fois. La fiche indique la règle exacte.


[color=#63d9a6][font_size=30][b]10. QU'EST-CE QU'UNE TECHNIQUE SPÉCIALE ?[/b][/font_size][/color]

La [b]technique spéciale[/b] est une action propre à chaque Ninja.

Contrairement au passif, tu dois généralement la choisir toi-même.

Une spéciale peut :
• attaquer ;
• infliger des dégâts fixes ;
• STUN ;
• empoisonner ;
• soigner ;
• mettre un bouclier ;
• rendre inciblable ;
• forcer un Switch ;
• contrôler une carte ;
• modifier les prochains tours.

Après utilisation, elle peut entrer en [b]cooldown[/b].

Le compteur T indique sa récupération :
• T 1/2 ;
• T 2/3 ;
• etc.

Une spéciale indisponible est grisée.

[color=#9fcde9][font_size=21][b]IMPORTANT[/b][/font_size][/color]
Une spéciale ne doit jamais être supposée fonctionner comme TAI/NIN/GEN.
Lis toujours son texte : ses dégâts et ses effets peuvent avoir des règles propres.


[color=#63d9a6][font_size=30][b]11. A1 ET A2 : LE CŒUR DU TOUR[/b][/font_size][/color]

Chaque tour normal te permet de préparer deux actions.

[color=#f2c75c][font_size=24][b]A1 = ACTION IMMÉDIATE[/b][/font_size][/color]
Elle s'exécute lorsque tu valides ton tour.

[color=#58aff0][font_size=24][b]A2 = ACTION PROGRAMMÉE[/b][/font_size][/color]
Elle est conservée et se déclenche lors de la prochaine validation adverse, avant ses nouvelles actions.

[color=#9fcde9][font_size=21][b]EXEMPLE COMPLET[/b][/font_size][/color]
Tour joueur A :
A1 = Naruto Ninjutsu sur Gaara.
A2 = Shikamaru spéciale sur Sasuke.
Le joueur A valide.
Naruto attaque immédiatement.
La spéciale de Shikamaru reste programmée.

Tour joueur B :
Le joueur B prépare ses actions puis valide.
Avant que ses nouvelles actions ne commencent, l'A2 de Shikamaru se déclenche.

[color=#f0a65a][font_size=21][b]RÈGLE IMPORTANTE[/b][/font_size][/color]
Un même Ninja ne peut pas prévoir deux attaques normales TAI/NIN/GEN pendant le même tour.

Il peut cependant faire :
• une attaque normale + sa spéciale ;
• sa spéciale + une attaque normale.

Deux Ninjas différents peuvent chacun faire une attaque normale.


[color=#63d9a6][font_size=30][b]12. LE SWITCH ET LA RÉSERVE[/b][/font_size][/color]

Le [b]Switch[/b] remplace un Ninja du terrain par un Ninja de réserve.

[b]Switch A1[/b] :
le changement est résolu immédiatement.

[b]Switch A2[/b] :
le changement est programmé et sera résolu au moment correspondant.

[color=#9fcde9][font_size=21][b]TRÈS IMPORTANT[/b][/font_size][/color]
Une carte qui part en réserve n'est pas recréée neuve.

Elle conserve notamment :
• ses PV ;
• ses boucliers ;
• ses poisons ;
• ses buffs ;
• ses debuffs ;
• ses cooldowns ;
• ses états persistants.

[color=#9fcde9][font_size=21][b]EXEMPLE[/b][/font_size][/color]
Kakashi quitte le terrain avec 700 PV et un poison.
Quand il revient plus tard, il ne revient pas à ses PV maximum : il revient avec son état conservé.

Certaines techniques ou états empêchent volontairement de quitter le terrain.


[color=#63d9a6][font_size=30][b]13. ÉTATS, DÉFENSES ET PROTECTIONS[/b][/font_size][/color]

[color=#58aff0][b]INCIBLABLE[/b][/color]
La carte ne peut pas être choisie comme cible tant que l'effet est actif.

[color=#9fd7ff][b]ESQUIVE[/b][/color]
La carte peut être choisie, mais l'attaque peut être évitée selon l'effet.

[color=#e6c75e][b]BOUCLIER[/b][/color]
Le bouclier absorbe des dégâts avant les PV.
Certaines attaques le détruisent ou l'ignorent.

[color=#ba85ed][b]STUN / PARALYSIE / PRISON[/b][/color]
Ces effets empêchent ou limitent l'action d'un Ninja pendant une durée donnée.

[color=#63d596][b]POISON / DOT[/b][/color]
Dégâts périodiques appliqués selon leur propre timing.

[color=#ef8b65][b]BUFF / DEBUFF[/b][/color]
Modification temporaire ou permanente d'une statistique.

[color=#d0d8df][b]RÉDUCTION DE DÉGÂTS[/b][/color]
Diminue la quantité reçue selon la règle du passif ou de la technique.

[color=#f0a65a][font_size=21][b]SUBTILITÉ[/b][/font_size][/color]
"Inciblable" et "esquive" ne veulent pas dire la même chose :
• inciblable = tu ne peux même pas choisir la carte ;
• esquive = tu peux la cibler, mais elle peut éviter l'attaque.


[color=#63d9a6][font_size=30][b]14. LES SYNERGIES[/b][/font_size][/color]

Certaines cartes liées gagnent automatiquement des bonus lorsqu'elles sont ensemble.

[b]Famille de 3 complète : +20 %[/b] PV / TAI / NIN / GEN.

[b]2 membres d'une famille de 3 : +12,5 %[/b] pour les deux membres liés.

[b]Duo explicite : +15 %[/b].

Les bonus de plusieurs familles ne se cumulent pas : le jeu conserve le meilleur bonus applicable.

[color=#9fcde9][font_size=21][b]EXEMPLE[/b][/font_size][/color]
Naruto + Sasuke + Sakura présents ensemble :
les trois profitent de la synergie complète.

Si seulement deux membres liés sont présents, la synergie partielle peut s'appliquer.

Les synergies sont recalculées quand une carte entre, sort, est remplacée ou meurt.


[color=#63d9a6][font_size=30][b]15. K.O., SURPLUS ET REMPLACEMENT[/b][/font_size][/color]

Quand les PV d'un Ninja tombent à 0, il est normalement [b]K.O.[/b].

Il quitte le terrain et rejoint le cimetière, sauf passif de survie, résurrection ou autre règle spéciale.

Si tu possèdes encore des cartes en réserve, tu dois remplacer le Ninja K.O.

Le jeu peut proposer jusqu'à [b]3 cartes de remplacement[/b] selon la situation.

[color=#ef8b65][font_size=22][b]SURPLUS[/b][/font_size][/color]
Lorsqu'une vraie attaque inflige plus de dégâts que les PV restants de la carte, l'excédent frappe les [b]PV joueur[/b].

[color=#9fcde9][font_size=21][b]EXEMPLE[/b][/font_size][/color]
La cible possède 200 PV.
Ton attaque inflige 500 dégâts.
200 PV éliminent la carte.
Les 300 dégâts restants deviennent du surplus contre le joueur.

Tous les dégâts ne produisent pas forcément du surplus : poisons, sacrifices, dégâts de terrain ou effets spéciaux suivent leurs propres règles.


[color=#63d9a6][font_size=30][b]16. COMMENT GAGNER UNE PARTIE[/b][/font_size][/color]

Une partie continue tour après tour :
• préparation A1/A2 ;
• validation ;
• résolution ;
• effets de début/fin de tour ;
• Switchs ;
• K.O. ;
• remplacements.

Tu gagnes lorsque les conditions de défaite adverses sont remplies.

[b]Condition principale :[/b]
faire tomber les [b]PV joueur ennemis à 0[/b].

[b]Autre condition :[/b]
si l'adversaire ne possède plus aucune carte disponible pour continuer le combat, il perd.

[color=#9fcde9][font_size=22][b]RÉSUMÉ D'UNE PARTIE COMPLÈTE[/b][/font_size][/color]

1. Premier Shifumi.
2. Draft des 8 Ninjas.
3. Choix des 3 Ninjas de départ.
4. Second Shifumi.
5. Le gagnant obtient le premier tour.
6. Chaque tour : A1 immédiate + A2 programmée.
7. TAI attaque TAI, NIN attaque NIN, GEN attaque GEN.
8. Les éléments, passifs, spéciales, synergies et états modifient le duel.
9. Les Switchs permettent de gérer le terrain et la réserve.
10. Les K.O. provoquent des remplacements tant qu'il reste des cartes.
11. Le surplus peut frapper directement les PV joueur.
12. Le duel continue jusqu'à la victoire.

[color=#f2c75c][font_size=22][b]CONSEIL POUR APPRENDRE[/b][/font_size][/color]
Au début, retiens surtout trois choses :
• regarde toujours TAI/NIN/GEN de ta cible avant d'attaquer ;
• lis le passif et la spéciale avant de valider ton tour ;
• pense à A2 comme à une action préparée pour le prochain échange.
"""

func _guide_jump(chapter: String) -> void:
    var rich: RichTextLabel = screen_root.find_child("GuideRichText", true, false) as RichTextLabel
    if rich == null:
        return
    var map: Dictionary = {
        "BASE DU COMBAT": 0,
        "ROUE DES ÉLÉMENTS": 170,
        "A1 / A2": 330,
        "HIRAISHIN": 520,
        "SWITCH": 650,
        "DÉFENSES & ÉTATS": 820,
        "COOLDOWNS": 1060,
        "SYNERGIES": 1200,
        "DÉGÂTS & SURPLUS": 1380,
    }
    var parent_scroll: ScrollContainer = rich.get_parent() as ScrollContainer
    if parent_scroll:
        parent_scroll.scroll_vertical = int(map.get(chapter, 0))

func _classic_guide_bbcode() -> String:
    return """[color=#63d9a6][font_size=20][b]BASE DU COMBAT[/b][/font_size][/color]
Chaque joueur possède [b]4000 PV joueur[/b], séparés des PV des Ninjas. Un deck contient 8 Ninjas uniques : 3 titulaires et 5 en réserve cachée.
À chaque tour tu prépares jusqu'à deux cases : [color=#f2c75c][b]A1 immédiate[/b][/color] et [color=#58aff0][b]A2 programmée[/b][/color]. Les états d'une carte restent attachés à son instance quand elle passe en réserve : PV, poison, STUN, bouclier, buffs/debuffs et cooldowns reprennent là où ils en étaient au retour.

[color=#63d9a6][font_size=20][b]ROUE DES ÉLÉMENTS[/b][/font_size][/color]
[color=#ef6256][b]FEU[/b][/color] → [color=#63d596][b]VENT[/b][/color] → [color=#c09aff][b]FOUDRE[/b][/color] → [color=#c79b6b][b]TERRE[/b][/color] → [color=#55b6f2][b]EAU[/b][/color] → [color=#ef6256][b]FEU[/b][/color]
Une attaque avec avantage élémentaire reçoit le bonus Classic [b]×1,10 puis +150[/b]. Les personnages TOUS ou les exceptions propres aux cartes suivent leur règle spéciale.

[color=#f2c75c][font_size=20][b]A1 / A2 — EXEMPLE[/b][/font_size][/color]
[b]Ton tour :[/b]
[color=#f2c75c]CASE A1[/color]  Itachi → SPÉCIALE Katon → part dès ta validation.
[color=#58aff0]CASE A2[/color]  Shikamaru → SPÉCIALE Ombres → reste programmée.
[b]Tour adverse :[/b] au moment de sa validation, ton A2 se résout [b]avant ses actions[/b].
Une A2 peut donc être une attaque normale, une spéciale ou un Switch lorsque la mécanique l'autorise. Une spéciale consommée personnellement reste soumise à son cooldown.

[color=#e6b74e][font_size=20][b]HIRAISHIN GRATUIT — MINATO[/b][/font_size][/color]
Minato possède une [b]troisième action indépendante[/b]. Hiraishin gratuit accepte TAI / NIN / GEN, mais pas sa spéciale.
Ordre de résolution : [b]A2 adverse → Hiraishin gratuit → A1 immédiate[/b]. Ton A2 reste programmée normalement.
Exemple : Hiraishin Minato + spéciale Itachi en A1 + spéciale d'un autre Ninja en A2.

[color=#58aff0][font_size=20][b]SWITCH A1 / SWITCH A2[/b][/font_size][/color]
[b]Switch A1 :[/b] changement immédiat pendant ton tour.
[b]Switch A2 :[/b] changement programmé, utile pour faire entrer un Ninja au moment de la prochaine validation adverse.
Les états persistants suivent la carte en réserve. En revanche, [b]Jashin, Prison aqueuse, Scellement Kushina et Ombres des Nara[/b] verrouillent normalement la cible sur le terrain. Grande Rafale de Temari est l'exception d'expulsion forcée.
Itachi, Sasuke et Kakashi possèdent leurs règles de Counter-Switch ; Yamato peut transmettre son Don selon sa mécanique.

[color=#d98be8][font_size=20][b]DÉFENSES & ÉTATS[/b][/font_size][/color]
[b]Inciblable[/b] : la carte ne peut pas être choisie comme cible pendant la durée de l'effet.
[b]Esquive[/b] : la cible peut être choisie mais l'attaque peut être évitée selon la mécanique.
[b]Bouclier[/b] : réserve de protection absorbant des dégâts avant les PV, sauf règles qui l'ignorent/détruisent.
[b]Réduction[/b] : diminue les dégâts finaux selon le passif concerné.
[b]Survie[/b] : empêche ou transforme un K.O. selon la carte ; ce n'est pas un bouclier.
[b]STUN / Poison / buffs / debuffs[/b] restent sur l'instance et sont mis en pause en réserve.
Les contrôles de terrain liés (Ombres, Prison, Jashin, Scellé) possèdent leurs propres règles de rupture.

[color=#8ec8f4][font_size=20][b]COOLDOWNS[/b][/font_size][/color]
Après utilisation, une spéciale entre en récupération pour le nombre de tours prévu par sa carte. Le compteur visible indique le temps restant.
Passer en réserve [b]ne réinitialise pas gratuitement[/b] une technique. Une spéciale déjà consommée reste consommée et son état suit le Ninja.

[color=#63d9a6][font_size=20][b]SYNERGIES[/b][/font_size][/color]
[b]Famille complète de 3 : +20 %[/b] PV / TAI / NIN / GEN.
[b]Deux membres d'une famille : +12,5 %[/b] pour les deux membres liés.
[b]Duo explicite : +15 %[/b].
[b]Zetsu + membre Akatsuki : +15 %[/b].
Les bonus ne se cumulent pas : le moteur garde [b]le meilleur bonus applicable[/b]. À l'entrée, au Switch ou à la mort d'un membre, la synergie est recalculée. Le changement de PV max conserve le [b]ratio de PV[/b] : aucune guérison gratuite.

[color=#ef8b65][font_size=20][b]DÉGÂTS FIXES / VRAIE ATTAQUE / SURPLUS[/b][/font_size][/color]
[b]Vraie attaque[/b] : passe dans le pipeline d'attaque Classic (art utilisé, défense, éléments, réductions, réactions et plancher anti-zéro lorsque la règle s'applique).
[b]Dégâts fixes[/b] : infligent la quantité définie par la technique et n'utilisent pas nécessairement les mêmes étapes de calcul ; chaque spéciale peut préciser ce qu'elle ignore.
[b]Surplus[/b] : lorsqu'une vraie attaque met K.O. un Ninja avec plus de dégâts que ses PV restants, l'excédent frappe les [b]PV joueur[/b].
Ne suppose jamais qu'un DOT, un sacrifice ou un dégât de terrain est une vraie attaque : ces catégories déclenchent des réactions différentes.

[color=#9fb3c6][b]RAPPEL[/b][/color]
Les fiches de la Collection détaillent les passifs, spéciales, rôles et synergies de chaque Ninja. Le combat reste l'autorité pour les exceptions propres à une carte.
"""

func _show_options() -> void:
    _destroy_home_overlay()
    current_screen = "options"
    _clear_screen()
    _screen_heading("PARAMÈTRES", "Audio global persistant • les mêmes volumes pilotent menu, Draft et combat.")
    _panel_in(screen_root, Rect2(290, 150, 984, 486), Color(0.018,0.038,0.062,0.94), Color(0.30,0.49,0.65,0.36), 16, 8)
    _label_in(screen_root, "AUDIO", Rect2(334, 184, 300, 28), 17, Color("63d9a6"), HORIZONTAL_ALIGNMENT_LEFT, true)
    _label_in(screen_root, "Musique", Rect2(334, 230, 180, 28), 11, Color("d4dee7"), HORIZONTAL_ALIGNMENT_LEFT, true)
    var music_slider := HSlider.new()
    music_slider.position = Vector2(524, 232)
    music_slider.size = Vector2(620, 28)
    music_slider.min_value = 0.0
    music_slider.max_value = 100.0
    music_slider.value = AudioManager.get_music_percent()
    music_slider.value_changed.connect(_music_volume_changed)
    screen_root.add_child(music_slider)
    _style_glass_slider(music_slider)
    _label_in(screen_root, "Effets", Rect2(334, 282, 180, 28), 11, Color("d4dee7"), HORIZONTAL_ALIGNMENT_LEFT, true)
    var sfx_slider := HSlider.new()
    sfx_slider.position = Vector2(524, 284)
    sfx_slider.size = Vector2(620, 28)
    sfx_slider.min_value = 0.0
    sfx_slider.max_value = 100.0
    sfx_slider.value = AudioManager.get_sfx_percent()
    sfx_slider.value_changed.connect(_sfx_volume_changed)
    screen_root.add_child(sfx_slider)
    _style_glass_slider(sfx_slider)

    _label_in(screen_root, "AFFICHAGE", Rect2(334, 354, 300, 28), 17, Color("58aff0"), HORIZONTAL_ALIGNMENT_LEFT, true)
    var fullscreen_btn: Button = _button_in(screen_root, Rect2(334, 404, 300, 50), "BASCULER PLEIN ÉCRAN", Color("58aff0"), false)
    fullscreen_btn.pressed.connect(_toggle_fullscreen)
    var window_btn: Button = _button_in(screen_root, Rect2(652, 404, 300, 50), "FENÊTRE MAXIMISÉE", Color("6f91aa"), false)
    window_btn.pressed.connect(_set_maximized)
    var vsync_btn: Button = _button_in(screen_root, Rect2(970, 404, 260, 50), "VSYNC ON", Color("55d58b"), false)
    vsync_btn.pressed.connect(_enable_vsync)
    _label_in(screen_root, "Les réglages sont sauvegardés automatiquement et s'appliquent immédiatement au menu, Shifumi/Draft, combat et sons de résultat.", Rect2(334, 500, 896, 44), 10, Color("b7c9d8"), HORIZONTAL_ALIGNMENT_LEFT, false)
    var music_test: Button = _button_in(screen_root,Rect2(334,552,220,42),"TEST MUSIQUE",Color("63d9a6"),false)
    music_test.pressed.connect(func() -> void: AudioManager.preview_music())
    var sfx_test: Button = _button_in(screen_root,Rect2(574,552,220,42),"TEST EFFET",Color("58aff0"),false)
    sfx_test.pressed.connect(func() -> void: AudioManager.preview_sfx())
    footer_notice.text = "Audio global : paramètres sauvegardés dans user://yugito_audio.json."

func _music_volume_changed(value: float) -> void:
    music_volume_percent = float(value)
    AudioManager.set_music_percent(music_volume_percent)

func _sfx_volume_changed(value: float) -> void:
    sfx_volume_percent = float(value)
    AudioManager.set_sfx_percent(sfx_volume_percent)

func _toggle_fullscreen() -> void:
    DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)

func _set_maximized() -> void:
    DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_MAXIMIZED)

func _enable_vsync() -> void:
    DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED)
    footer_notice.text = "VSync activé."

func _start_battle() -> void:
    if battle_instance != null or prebattle_instance != null:
        return
    AudioManager.play_music("res://assets/audio/music/selection.mp3",-8.0)
    GameSession.clear()
    menu_root.visible = false
    if app_video != null:
        app_video.visible = true
        app_video.z_index = -100
        # P47M.4-DP — keep the current sakura frame visible, but stop decoding
        # video while Shifumi/Draft/lineup are on screen on Android.
        if MobilePlatform.is_android():
            app_video.paused = true

    prebattle_instance = PreBattleScene.instantiate()
    add_child(prebattle_instance)

    # Le pré-combat doit être un CanvasItem au-dessus du fond vidéo.
    if prebattle_instance is CanvasItem:
        (prebattle_instance as CanvasItem).z_index = 1000
    if prebattle_instance.has_signal("battle_requested"):
        prebattle_instance.connect("battle_requested", Callable(self, "_launch_battle_after_flow"))
    if prebattle_instance.has_signal("cancelled"):
        prebattle_instance.connect("cancelled", Callable(self, "_return_from_battle"))
    battle_return_button.visible = true
    get_window().title = "YUGITO 2.0 - PRÉPARATION CLASSIC"

func _launch_battle_after_flow() -> void:
    if prebattle_instance != null:
        prebattle_instance.queue_free()
        prebattle_instance = null
    _spawn_battle_instance()

func _spawn_battle_instance() -> void:
    AudioManager.play_music("res://assets/audio/music/ingame.mp3",-6.0)
    if app_video != null:
        app_video.paused = false
        app_video.stop()
        app_video.visible = false
    battle_instance = BattleScene.instantiate()
    add_child(battle_instance)
    if battle_instance.has_signal("return_to_menu_requested"):
        battle_instance.connect("return_to_menu_requested", Callable(self, "_return_from_battle"))
    if battle_instance.has_signal("replay_requested"):
        battle_instance.connect("replay_requested", Callable(self, "_replay_current_battle"))
    if battle_instance.has_signal("duel_result"):
        battle_instance.connect("duel_result", Callable(self, "_on_solo_duel_result"))
    battle_return_button.visible = true
    get_window().title = "YUGITO 2.0 - COMBAT VS IA"

func _on_solo_duel_result(victory: bool, _reason: String, _turns: int, _duration_seconds: float) -> void:
    if Rewards == null:
        return
    var result: Dictionary = Rewards.call("settle_solo",victory,"") as Dictionary
    last_reward_notice = str(result.get("message",""))
    if battle_instance != null and battle_instance.has_method("set_duel_reward_text"):
        battle_instance.call("set_duel_reward_text",last_reward_notice)

func _replay_current_battle() -> void:
    if battle_instance != null:
        battle_instance.queue_free()
        battle_instance = null
    # GameSession reste intacte : mêmes 8 Ninjas / mêmes titulaires.
    # On recrée uniquement la scène de combat à son état initial.
    call_deferred("_spawn_battle_instance")

func _return_from_battle() -> void:
    if prebattle_instance != null:
        prebattle_instance.queue_free()
        prebattle_instance = null
    if battle_instance != null:
        battle_instance.queue_free()
        battle_instance = null
    GameSession.clear()
    battle_return_button.visible = false
    if app_video != null:
        app_video.z_index = -100
        app_video.visible = true
        app_video.paused = false
        if not app_video.is_playing():
            app_video.play()
    menu_root.visible = true
    AudioManager.play_music("res://assets/audio/music/menu.mp3",0.0)
    get_window().title = "YUGITO GC MOBILE - PROTOTYPE 47M.4 PREBATTLE SAFE BOOT"
    footer_notice.text = ("Retour au menu • " + last_reward_notice) if not last_reward_notice.is_empty() else "Retour au menu principal."

func _element_color(element: String) -> Color:
    match element.to_lower():
        "feu": return Color("ef6256")
        "vent": return Color("63d596")
        "foudre": return Color("c09aff")
        "terre": return Color("c79b6b")
        "eau": return Color("55b6f2")
        _ : return Color("7c94ad")

func _stars_text(value: float) -> String:
    if is_equal_approx(value, floorf(value)):
        return "%d" % int(value)
    return "%.1f" % value

func _logo_in(parent: Node, pos: Vector2, side: float) -> void:
    var logo := TextureRect.new()
    logo.position = pos
    logo.size = Vector2(side, side)
    logo.texture = AssetCache.texture("res://assets/ui/YUGITO.png")
    logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
    logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
    logo.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
    logo.mouse_filter = Control.MOUSE_FILTER_IGNORE
    parent.add_child(logo)

func _classic_menu_row(parent: Control, y: float, title: String, subtitle: String, accent: Color, callback: Callable) -> Button:
    var btn: Button = _button_in(parent, Rect2(34, y, 598, 58), "", accent, false)
    btn.pressed.connect(_home_go.bind(callback))
    _panel_in(btn, Rect2(0, 0, 76, 58), Color(accent.r*0.20, accent.g*0.20, accent.b*0.20, 0.88), Color(accent.r,accent.g,accent.b,0.60), 5)
    _label_in(btn, "◆", Rect2(19, 7, 38, 42), 21, accent.lightened(0.12), HORIZONTAL_ALIGNMENT_CENTER, true)
    _label_in(btn, title, Rect2(98, 5, 350, 27), 17, Color("fff6ea"), HORIZONTAL_ALIGNMENT_LEFT, true)
    _label_in(btn, subtitle, Rect2(98, 31, 410, 19), 9, Color("9fb1c4"), HORIZONTAL_ALIGNMENT_LEFT, false)
    _label_in(btn, ">", Rect2(546, 8, 34, 40), 28, accent, HORIZONTAL_ALIGNMENT_CENTER, true)
    return btn

func _classic_half_row(parent: Control, rect: Rect2, title: String, subtitle: String, accent: Color, callback: Callable) -> Button:
    var btn: Button = _button_in(parent, rect, "", accent, false)
    btn.pressed.connect(_home_go.bind(callback))
    _label_in(btn, "◆", Rect2(13, 8, 32, 38), 17, accent.lightened(0.10), HORIZONTAL_ALIGNMENT_CENTER, true)
    _label_in(btn, title, Rect2(52, 6, rect.size.x-92, 25), 12, Color("fff5e8"), HORIZONTAL_ALIGNMENT_LEFT, true)
    _label_in(btn, subtitle, Rect2(52, 31, rect.size.x-92, 18), 8, Color("92a7bc"), HORIZONTAL_ALIGNMENT_LEFT, false)
    _label_in(btn, ">", Rect2(rect.size.x-38, 10, 26, 36), 20, accent, HORIZONTAL_ALIGNMENT_CENTER, true)
    return btn

func _panel_in(parent: Node, rect: Rect2, bg: Color, border: Color, radius: int, shadow_size: int = 0) -> Panel:
    var panel := Panel.new()
    panel.position = rect.position
    panel.size = rect.size
    panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
    var style := StyleBoxFlat.new()
    var glass_bg: Color = bg
    var glass_border: Color = border
    if current_screen != "home" and bg.a > 0.45:
        glass_bg = Color(0.010, 0.024, 0.042, minf(0.62, maxf(0.38, bg.a * 0.52)))
        glass_border = Color(border.r, border.g, border.b, maxf(0.32, minf(0.70, border.a + 0.18)))
    style.bg_color = glass_bg
    style.border_color = glass_border
    style.set_border_width_all(1)
    style.set_corner_radius_all(radius)
    if shadow_size > 0:
        style.shadow_size = shadow_size
        style.shadow_color = Color(0,0,0,0.34)
        style.shadow_offset = Vector2(0,4)
    panel.add_theme_stylebox_override("panel", style)
    parent.add_child(panel)
    return panel

func _label_in(parent: Node, text_value: String, rect: Rect2, font_size: int, color: Color, align: HorizontalAlignment, bold: bool) -> Label:
    var label := Label.new()
    label.text = text_value
    label.position = rect.position
    label.size = rect.size
    label.horizontal_alignment = align
    label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    label.clip_text = true
    label.add_theme_font_size_override("font_size", font_size)
    label.add_theme_color_override("font_color", color)
    label.mouse_filter = Control.MOUSE_FILTER_IGNORE
    if bold:
        label.add_theme_color_override("font_shadow_color", Color(0,0,0,0.38))
        label.add_theme_constant_override("shadow_offset_x", 1)
        label.add_theme_constant_override("shadow_offset_y", 1)
    parent.add_child(label)
    return label

func _rich_text_in(parent: Node, text_value: String, rect: Rect2, font_size: int, color: Color) -> RichTextLabel:
    var rich := RichTextLabel.new()
    rich.text = text_value
    rich.position = rect.position
    rich.size = rect.size
    rich.fit_content = false
    rich.scroll_active = false
    rich.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    rich.add_theme_font_size_override("normal_font_size", font_size)
    rich.add_theme_color_override("default_color", color)
    rich.mouse_filter = Control.MOUSE_FILTER_IGNORE
    parent.add_child(rich)
    return rich

func _style_glass_line_edit(edit: LineEdit) -> void:
    var normal := StyleBoxFlat.new()
    normal.bg_color = Color(0.010,0.026,0.045,0.58)
    normal.border_color = Color(1,1,1,0.36)
    normal.set_border_width_all(1)
    normal.set_corner_radius_all(12)
    normal.content_margin_left = 14
    normal.content_margin_right = 14
    var focus := normal.duplicate() as StyleBoxFlat
    focus.bg_color = Color(0.025,0.052,0.080,0.72)
    focus.border_color = Color(0.72,0.90,1.0,0.82)
    edit.add_theme_stylebox_override("normal",normal)
    edit.add_theme_stylebox_override("focus",focus)
    edit.add_theme_color_override("font_color",Color("ffffff"))
    edit.add_theme_color_override("font_placeholder_color",Color(0.92,0.96,1.0,0.72))
    edit.add_theme_color_override("caret_color",Color("ffffff"))

func _style_glass_slider(slider: HSlider) -> void:
    var track := StyleBoxFlat.new()
    track.bg_color = Color(1,1,1,0.14)
    track.set_corner_radius_all(4)
    slider.add_theme_stylebox_override("slider",track)
    var grab := StyleBoxFlat.new()
    grab.bg_color = Color(0.90,0.97,1.0,0.95)
    grab.border_color = Color(1,1,1,0.90)
    grab.set_border_width_all(1)
    grab.set_corner_radius_all(8)
    slider.add_theme_icon_override("grabber", _make_slider_knob_texture())
    slider.add_theme_icon_override("grabber_highlight", _make_slider_knob_texture())

func _make_slider_knob_texture() -> GradientTexture1D:
    var grad := Gradient.new()
    grad.colors = PackedColorArray([Color(0.96,0.99,1.0,1.0), Color(0.78,0.90,1.0,1.0)])
    var tex := GradientTexture1D.new()
    tex.gradient = grad
    tex.width = 18
    return tex

func _button_in(parent: Node, rect: Rect2, text_value: String, accent: Color, strong: bool) -> Button:
    var btn := Button.new()
    btn.position = rect.position
    btn.size = rect.size
    btn.text = text_value
    btn.flat = true
    btn.focus_mode = Control.FOCUS_ALL
    btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
    btn.add_theme_font_size_override("font_size", 12 if not strong else 14)
    btn.add_theme_color_override("font_color", Color("e8eef4"))
    btn.add_theme_color_override("font_hover_color", Color("ffffff"))
    var normal := StyleBoxFlat.new()
    normal.bg_color = Color(0.015,0.032,0.052,0.46)
    normal.border_color = Color(accent.r,accent.g,accent.b,0.46)
    normal.set_border_width_all(1)
    normal.set_corner_radius_all(9)
    var hover: StyleBoxFlat = normal.duplicate() as StyleBoxFlat
    hover.bg_color = Color(0.035,0.064,0.092,0.62)
    hover.border_color = Color(accent.r,accent.g,accent.b,0.78)
    var pressed: StyleBoxFlat = hover.duplicate() as StyleBoxFlat
    pressed.bg_color = Color(accent.r * 0.23, accent.g * 0.23, accent.b * 0.23, 1.0)
    var disabled: StyleBoxFlat = normal.duplicate() as StyleBoxFlat
    disabled.bg_color = Color(0.020,0.031,0.045,0.72)
    disabled.border_color = Color(0.36,0.42,0.48,0.18)
    btn.add_theme_stylebox_override("normal", normal)
    btn.add_theme_stylebox_override("hover", hover)
    btn.add_theme_stylebox_override("pressed", pressed)
    btn.add_theme_stylebox_override("focus", hover)
    btn.add_theme_stylebox_override("disabled", disabled)
    if not text_value.strip_edges().is_empty():
        btn.tooltip_text = text_value.strip_edges()
    parent.add_child(btn)
    btn.button_down.connect(_play_ui_sound)
    if not MobilePlatform.is_touch():
        btn.mouse_entered.connect(_play_ui_hover)
    return btn

func _capsule_in(parent: Node, rect: Rect2, text_value: String, accent: Color) -> void:
    _panel_in(parent, rect, Color(accent.r * 0.10, accent.g * 0.10, accent.b * 0.10, 0.78), Color(accent.r,accent.g,accent.b,0.46), int(rect.size.y / 2.0))
    _label_in(parent, text_value, rect, 8, accent.lightened(0.14), HORIZONTAL_ALIGNMENT_CENTER, true)
