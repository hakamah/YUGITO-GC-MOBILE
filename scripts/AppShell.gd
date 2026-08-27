extends Node

const BattleScene: PackedScene = preload("res://Battle.tscn")
const PreBattleScene: PackedScene = preload("res://PreBattle.tscn")
const MenuCard = preload("res://scripts/MenuCard.gd")
const SynergyDB = preload("res://scripts/SynergyDB.gd")
const AssetCache = preload("res://scripts/AssetCache.gd")
const HomeVideoBackground = preload("res://scripts/HomeVideoBackground.gd")

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
var deck_search_query: String = ""
var deck_role_filters: Array[String] = []
var deck_grid: GridContainer = null
var deck_count_label: Label = null
var deck_notice: String = "Construis un deck de 8 Ninjas uniques."
var current_screen: String = "home"
var music_volume_percent: float = 38.0
var sfx_volume_percent: float = 58.0
var home_overlay: Control = null
var ui_hover_cooldown_until: int = 0

func _ready() -> void:
    get_window().title = "YUGITO GC MOBILE - PROTOTYPE 47M.3 MENU PREBATTLE FIX"
    MobilePlatform.enforce_landscape()
    if not MobilePlatform.back_requested.is_connected(_on_mobile_back_requested):
        MobilePlatform.back_requested.connect(_on_mobile_back_requested)
    _load_cards()
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
    _label_in(header, "BUILD 47M.3 • FIX", Rect2(224, 29, 190, 18), 7, Color("d9e8f3"), HORIZONTAL_ALIGNMENT_LEFT, false)

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
    battle_return_button.z_index = 10000
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

    _frosted_home_button(glass, Rect2(44, 150, 428, 94), "▣", "COLLECTION", "70 / 70 CARTES", Color("f4ca78"), Callable(self, "_show_collection"))
    _frosted_home_button(glass, Rect2(512, 150, 428, 94), "◇", "CRÉER UN DECK", "32,5★ MAX", Color("8fd6ae"), Callable(self, "_show_deck_builder"))

    _frosted_home_button(glass, Rect2(44, 262, 428, 94), "▤", "GUIDE", "RÈGLES CLASSIC", Color("f1cf82"), Callable(self, "_show_guide"))
    _frosted_home_button(glass, Rect2(512, 262, 428, 94), "▰", "BOUTIQUE", "CARTES & BOOSTERS", Color("93d89d"), Callable(self, "_show_collection"))

    _frosted_home_button(glass, Rect2(44, 374, 428, 94), "◌", "AMIS & MESSAGES", "DISCUTER & INVITER", Color("8fd2e4"), Callable(self, "_show_play"))
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
    if footer_notice != null:
        footer_notice.text = "Compte Google YUGITO connecté."
    if current_screen == "identity":
        call_deferred("_show_home")
    elif current_screen == "profile":
        call_deferred("_show_profile")

func _on_auth_session_changed(connected: bool) -> void:
    _refresh_identity_surfaces()
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
    _screen_heading("PROFIL SHINOBI", "Identité YUGITO • profil classé compatible avec le client PC.")

    var main_panel: Panel = _panel_in(screen_root,Rect2(34,104,1014,588),Color(0.012,0.028,0.048,0.94),Color(0.58,0.82,1.0,0.40),22,12)
    _label_in(main_panel,IdentityManager.display_name().to_upper(),Rect2(42,34,650,56),34,Color("ffffff"),HORIZONTAL_ALIGNMENT_LEFT,true)
    var status_color: Color = _profile_status_color()
    _capsule_in(main_panel,Rect2(742,42,220,30),_profile_status_short(),status_color)

    _label_in(main_panel,"ELO",Rect2(42,126,170,24),11,Color("a9bfd1"),HORIZONTAL_ALIGNMENT_LEFT,true)
    _label_in(main_panel,str(int(data.get("elo",100))),Rect2(42,150,250,66),42,Color("f1d27e"),HORIZONTAL_ALIGNMENT_LEFT,true)
    _label_in(main_panel,"MEILLEUR ELO  %d" % int(data.get("best_elo",100)),Rect2(42,214,320,24),11,Color("dce5f0"),HORIZONTAL_ALIGNMENT_LEFT,true)

    _profile_stat_card(main_panel,Rect2(42,274,278,118),"PARTIES CLASSÉES",str(int(data.get("ranked_matches",0))),Color("77c8f1"))
    _profile_stat_card(main_panel,Rect2(344,274,278,118),"VICTOIRES / DÉFAITES","%d / %d" % [int(data.get("wins",0)),int(data.get("losses",0))],Color("61dba5"))
    _profile_stat_card(main_panel,Rect2(646,274,316,118),"TAUX DE VICTOIRE","%.1f %%" % float(data.get("winrate",0.0)),Color("c3a6f2"))

    _label_in(main_panel,"Le profil est lié au compte Google YUGITO. La session est chiffrée localement ; le cache profil reste non secret.",Rect2(42,424,920,50),10,Color("aebfd0"),HORIZONTAL_ALIGNMENT_LEFT,false)
    var account_btn: Button = _button_in(main_panel,Rect2(42,500,294,54),"COMPTE YUGITO / GOOGLE",Color("77a9ff"),true)
    account_btn.pressed.connect(_show_identity_account)
    var play_btn: Button = _button_in(main_panel,Rect2(354,500,270,54),"JOUER",Color("61dba5"),true)
    play_btn.pressed.connect(_show_play)
    var home_btn: Button = _button_in(main_panel,Rect2(642,500,320,54),"RETOUR ACCUEIL",Color("b8c9d8"),false)
    home_btn.pressed.connect(_show_home)

    var account_panel: Panel = _panel_in(screen_root,Rect2(1072,104,450,588),Color(0.012,0.028,0.048,0.94),Color(0.58,0.82,1.0,0.34),22,12)
    _label_in(account_panel,"COMPTE",Rect2(30,28,300,30),17,Color("ffffff"),HORIZONTAL_ALIGNMENT_LEFT,true)
    _label_in(account_panel,"État",Rect2(30,88,120,22),9,Color("92a9bc"),HORIZONTAL_ALIGNMENT_LEFT,true)
    _label_in(account_panel,IdentityManager.auth_message,Rect2(30,110,390,54),11,status_color,HORIZONTAL_ALIGNMENT_LEFT,true)
    _label_in(account_panel,"E-mail Google",Rect2(30,190,160,22),9,Color("92a9bc"),HORIZONTAL_ALIGNMENT_LEFT,true)
    _label_in(account_panel,str(data.get("email","—")) if not str(data.get("email","")).is_empty() else "—",Rect2(30,214,390,36),10,Color("eef5fa"),HORIZONTAL_ALIGNMENT_LEFT,false)
    _label_in(account_panel,"ID YUGITO",Rect2(30,278,160,22),9,Color("92a9bc"),HORIZONTAL_ALIGNMENT_LEFT,true)
    var aid: String = str(data.get("account_id",""))
    var aid_display: String = "—"
    if not aid.is_empty():
        aid_display = aid.substr(0,mini(10,aid.length())) + ("…" if aid.length() > 10 else "")
    _label_in(account_panel,aid_display,Rect2(30,302,390,36),10,Color("eef5fa"),HORIZONTAL_ALIGNMENT_LEFT,false)
    _label_in(account_panel,"SOURCE PROFIL",Rect2(30,364,180,22),9,Color("92a9bc"),HORIZONTAL_ALIGNMENT_LEFT,true)
    _label_in(account_panel,str(data.get("profile_source","none")).to_upper(),Rect2(30,388,390,34),10,Color("c8d7e3"),HORIZONTAL_ALIGNMENT_LEFT,true)
    _label_in(account_panel,"PC / MOBILE",Rect2(30,458,180,22),9,Color("92a9bc"),HORIZONTAL_ALIGNMENT_LEFT,true)
    _label_in(account_panel,"Une seule identité YUGITO liée à Google.",Rect2(30,482,390,52),10,Color("c8d7e3"),HORIZONTAL_ALIGNMENT_LEFT,false)
    footer_notice.text = "Profil : identité Google/YUGITO active • ELO prêt pour le multijoueur classé."

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

    var google_btn: Button = _button_in(panel,Rect2(260,382,596,64),"SE CONNECTER AVEC GOOGLE",Color("6ba7ff"),true)
    google_btn.disabled = AuthManager.is_busy()
    google_btn.pressed.connect(_begin_google_auth)

    _label_in(
        panel,
        "Une page Google sécurisée s'ouvre. Après validation, reviens dans YUGITO : le jeu détecte automatiquement la connexion.",
        Rect2(180,458,756,54),
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

func _show_play() -> void:
    _destroy_home_overlay()
    current_screen = "play"
    _clear_screen()
    _screen_heading("JOUER", "Choisis ton mode. Le Solo suit désormais le véritable flux Classic avant le duel.")

    _mode_card(Rect2(42, 124, 458, 500), "SOLO VS IA", "COMPLET", "Shifumi pour le premier pick, Draft Classic de 16 choix, sélection privée des 3 Ninjas, second Shifumi puis combat contre l'IA tactique.", Color("55d58b"), Callable(self, "_start_battle"), "01")
    _mode_card(Rect2(553, 124, 458, 500), "MULTIJOUEUR", "EN MIGRATION", "Compte Google et identité YUGITO sont maintenant reconnectés. La prochaine étape branche salons, matchmaking classé, ELO réseau et parties privées.", Color("58aff0"), Callable(self, "_multiplayer_placeholder"), "02")
    _mode_card(Rect2(1064, 124, 458, 500), "ENTRAÎNEMENT", "À VENIR", "Bac à sable prévu pour choisir librement les Ninjas, tester un passif ou une spéciale et reproduire rapidement un cas de combat.", Color("ba85ed"), Callable(self, "_training_placeholder"), "03")
    footer_notice.text = "Solo : Shifumi → Draft → 3 Ninjas → Shifumi → Combat IA."

func _mode_card(rect: Rect2, title: String, state: String, description: String, accent: Color, callback: Callable, number: String = "") -> void:
    _panel_in(screen_root, rect, Color(0.018,0.038,0.063,0.94), Color(accent.r, accent.g, accent.b, 0.46), 18, 10)
    _panel_in(screen_root, Rect2(rect.position + Vector2(20, 20), Vector2(54, 54)), Color(accent.r*0.10, accent.g*0.10, accent.b*0.10, 0.86), Color(accent.r,accent.g,accent.b,0.58), 14)
    _label_in(screen_root, number, Rect2(rect.position + Vector2(20, 20), Vector2(54,54)), 15, accent.lightened(0.18), HORIZONTAL_ALIGNMENT_CENTER, true)
    _label_in(screen_root, title, Rect2(rect.position + Vector2(88, 23), Vector2(rect.size.x - 114, 34)), 21, Color("f2f6fa"), HORIZONTAL_ALIGNMENT_LEFT, true)
    _capsule_in(screen_root, Rect2(rect.position + Vector2(88, 62), Vector2(154, 25)), state, accent)
    _panel_in(screen_root, Rect2(rect.position + Vector2(22, 116), Vector2(rect.size.x - 44, 246)), Color(0.010,0.025,0.043,0.58), Color(accent.r,accent.g,accent.b,0.18), 12)
    _rich_text_in(screen_root, description, Rect2(rect.position + Vector2(42, 140), Vector2(rect.size.x - 84, 196)), 11, Color("a8bacb"))
    var btn: Button = _button_in(screen_root, Rect2(rect.position + Vector2(28, rect.size.y - 82), Vector2(rect.size.x - 56, 52)), "OUVRIR", accent, true)
    btn.pressed.connect(callback)

func _multiplayer_placeholder() -> void:
    footer_notice.text = "Multijoueur : Google/Auth prêt • salons, matchmaking et ELO réseau arrivent en P48."

func _training_placeholder() -> void:
    footer_notice.text = "Entraînement : prévu après la parité A1/A2 et les 70 passifs/spéciales."

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
    _destroy_home_overlay()
    current_screen = "collection"
    _clear_screen()
    _screen_heading("COLLECTION", "%d/70 Ninjas • recherche, rôles, fiche longue et synergies Classic." % sorted_cards.size())

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
    footer_notice.text = "Collection : 70/70 cartes de base disponibles • filtres PC et synergies actives."

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
    _show_collection()

func _clear_collection_filters() -> void:
    collection_search_query = ""
    collection_role_filters.clear()
    _show_collection()

func _on_collection_search_changed(value: String) -> void:
    collection_search_query = value
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
    _show_deck_builder()

func _clear_deck_filters() -> void:
    deck_search_query = ""
    deck_role_filters.clear()
    _show_deck_builder()

func _on_deck_search_changed(value: String) -> void:
    deck_search_query = value
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

func _show_guide() -> void:
    _destroy_home_overlay()
    current_screen = "guide"
    _clear_screen()
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
    prebattle_instance = PreBattleScene.instantiate()
    add_child(prebattle_instance)
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
        app_video.stop()
        app_video.visible = false
    battle_instance = BattleScene.instantiate()
    add_child(battle_instance)
    if battle_instance.has_signal("return_to_menu_requested"):
        battle_instance.connect("return_to_menu_requested", Callable(self, "_return_from_battle"))
    if battle_instance.has_signal("replay_requested"):
        battle_instance.connect("replay_requested", Callable(self, "_replay_current_battle"))
    battle_return_button.visible = true
    get_window().title = "YUGITO 2.0 - COMBAT VS IA"

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
        app_video.visible = true
        if not app_video.is_playing():
            app_video.play()
    menu_root.visible = true
    AudioManager.play_music("res://assets/audio/music/menu.mp3",0.0)
    get_window().title = "YUGITO GC MOBILE - PROTOTYPE 47M.3 MENU PREBATTLE FIX"
    footer_notice.text = "Retour au menu principal."

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
