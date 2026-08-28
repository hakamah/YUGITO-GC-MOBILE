extends Node2D
signal return_to_menu_requested
signal replay_requested


const CardActor = preload("res://scripts/CardActor.gd")
const Atmosphere = preload("res://scripts/Atmosphere.gd")
const ReplacementModal = preload("res://scripts/ReplacementModal.gd")
const SynergyDB = preload("res://scripts/SynergyDB.gd")
const ParityRNG = preload("res://scripts/ParityRNG.gd")
const AssetCache = preload("res://scripts/AssetCache.gd")

var cards_by_id: Dictionary = {}
var fps_label: Label
var elapsed: float = 0.0
var card_actors: Array[YugitoCardActor] = []
var selected_actor: YugitoCardActor = null
var next_actor_uid: int = 1

var selection_title_label: Label
var selection_subtitle_label: Label
var selection_stats_label: Label
var action_status_label: Label
var battle_log_label: Label
var battle_journal: Array[String] = []
var battle_journal_sequence: int = 0
var journal_overlay: Control = null
var journal_rich: RichTextLabel = null
var inspection_overlay: Control = null
var inspection_rich: RichTextLabel = null
var inspection_action_root: Control = null
var inspection_actor: YugitoCardActor = null
var action_marker_labels: Dictionary = {}
var duel_end_overlay: Control = null
var inspect_button: Button = null
var journal_button: Button = null
var top_hp_label: Label
var bottom_hp_label: Label
var top_reserve_status_label: Label
var bottom_reserve_status_label: Label
var top_field_status_label: Label
var bottom_field_status_label: Label
var enemy_field_effect_label: Label
var ally_field_effect_label: Label
var top_cemetery_status_label: Label
var bottom_cemetery_status_label: Label
var enemy_cemetery_value_label: Label
var ally_cemetery_value_label: Label
var turn_title_label: Label
var turn_capsule_label: Label
var phase_timer_root: Control
var phase_timer_label: Label
const PHASE_TIMER_LIMIT: float = 30.0
var phase_timer_seconds: float = PHASE_TIMER_LIMIT
var phase_timer_running: bool = false
var phase_timer_expired_once: bool = false

var action_buttons: Dictionary = {}
var validate_button: Button
var current_action: String = ""
var turn_counter: int = 1
var resolving_action: bool = false
var resolving_delayed_action: bool = false
var battle_rng: YugitoParityRNG = ParityRNG.new()
var planning_virtual_actor: YugitoCardActor = null

# Prototype de plan YUGITO : A1 immédiate à la validation, A2 mémorisée
# et rejouée au cycle de validation suivant. Le raccord exact à l'IA viendra
# avec le vrai moteur de tour, mais les deux slots existent déjà réellement.
var planning_slot: int = 1
var action1_plan: Dictionary = {}
var action2_plan: Dictionary = {}
var delayed_action2: Dictionary = {}
var ai_delayed_action2: Dictionary = {}
var ai_thinking: bool = false
var current_turn_team: String = "ally"
var timeline_free_button: Button
var timeline_a1_button: Button
var timeline_a2_button: Button
var timeline_free_subtitle: Label
var timeline_a1_subtitle: Label
var timeline_a2_subtitle: Label
var cancel_free_button: Button
var cancel_a1_button: Button
var cancel_a2_button: Button

var impact_ring_pool: Array[Panel] = []
var impact_core_pool: Array[Panel] = []
const IMPACT_POOL_SIZE: int = 10

# Deck de test 8 cartes par camp : 3 terrain + 5 réserve uniques. Les 70 illustrations
# du set PC sont désormais présentes dans le projet Godot.
var ally_reserve: Array[String] = ["sakura", "yamato", "sai", "minato", "ino"]
var enemy_reserve: Array[String] = ["choji", "asuma", "kurenai", "gaara", "kakashi"]
var ally_reserve_count_label: Label
var enemy_reserve_count_label: Label
var ally_cemetery_count: int = 0
var enemy_cemetery_count: int = 0

var replacement_modal: YugitoReplacementModal
var replacement_context: Dictionary = {}

var ally_player_hp: int = 4000
var enemy_player_hp: int = 4000
var duel_finished: bool = false
const PLAYER_HP_MAX: int = 4000
var ally_graveyard: Array[String] = []
var enemy_graveyard: Array[String] = []
var ally_reserve_states: Dictionary = {}
var enemy_reserve_states: Dictionary = {}
var free_action_plan: Dictionary = {}
var free_action_mode: bool = false
var free_action_button: Button
var copy_action_button: Button
var direct_attack_button: Button
var makibishi_active: Dictionary = {"ally":false, "enemy":false}
# Réserve forcée par les Byakugan traqueurs (Ao / Neji / Hinata).
var forced_reserve_choice: Dictionary = {"ally":"", "enemy":""}
# Mécaniques secrètes de Tobi. Les bombes sont portées par les instances ciblées.
var tobi_bomb_pending_team: String = ""
var tobi_prediction_enemy_uid: int = 0
var tobi_prediction_action_id: String = "special"
var tobi_predictions: Dictionary = {"ally":{}, "enemy":{}}
var resolution_queue: Array[Dictionary] = []
var resolution_done_callback: Callable = Callable()
var resolution_step_running: bool = false
var resolution_waiting_replacement: bool = false
# P19 — file sérialisée des K.O. : une AOE peut détruire plusieurs Ninjas
# avant que l'UI de remplacement ne s'ouvre. On stocke uniquement leurs UID
# stables pour éviter toute course entre plusieurs timers / objets libérés.
var pending_death_replacement_uids: Array[int] = []
var death_replacement_dispatch_scheduled: bool = false
# P20 — couche persistante des liens de statut (Ombres, Prison aqueuse, Jashin,
# Transfert d'Ino). Les liens suivent les cartes pendant leur flottement.
var status_link_root: Node2D
var status_link_elapsed: float = 0.0

func _ready() -> void:
    MobilePlatform.enforce_landscape()
    get_window().title = "YUGITO GC MOBILE - PROTOTYPE 47M.2 COMBAT PERF AUTH"
    battle_rng.configure(GameSession.parity_rng_enabled, GameSession.parity_seed)
    _load_card_data()
    _build_background()
    _build_audio()
    _build_interface()
    _build_status_link_layer()
    _build_replacement_modal()
    _configure_session_decks()
    _spawn_cards()
    _update_team_status()
    _refresh_selection_panel()
    _refresh_action_buttons()
    _refresh_plan_ui()
    if GameSession.configured and GameSession.starting_team == "enemy":
        current_turn_team = "enemy"
        resolving_action = true
        _start_team_turn("enemy")
        var start_timer: SceneTreeTimer = get_tree().create_timer(0.65)
        start_timer.timeout.connect(_start_ai_turn)
    else:
        _start_team_turn("ally")

func _process(delta: float) -> void:
    elapsed += delta
    _tick_phase_timer(delta)
    status_link_elapsed += delta
    var link_interval: float = 0.30 if MobilePlatform.is_android() else 0.08
    if status_link_elapsed >= link_interval:
        status_link_elapsed = 0.0
        # Sur Android, la plupart des tours n'ont aucun lien dynamique :
        # ne plus détruire/recréer des Nodes inutilement en permanence.
        if not MobilePlatform.is_android() or _has_dynamic_status_links():
            _refresh_persistent_status_links()
    if fps_label and elapsed >= 0.25:
        elapsed = 0.0
        fps_label.text = "%d FPS   •   GPU / VSYNC" % Engine.get_frames_per_second()

func _load_card_data() -> void:
    var file: FileAccess = FileAccess.open("res://data/cards.json", FileAccess.READ)
    if file == null:
        push_error("Impossible d'ouvrir data/cards.json")
        return
    var parsed: Variant = JSON.parse_string(file.get_as_text())
    if parsed is Array:
        for item in parsed:
            if item is Dictionary:
                cards_by_id[str(item.get("id", ""))] = item

func _build_background() -> void:
    # P42 — même univers visuel que l'accueil, mais en image fixe pour préserver
    # les performances du combat mobile.
    var bg := TextureRect.new()
    bg.position = Vector2.ZERO
    bg.size = Vector2(1600, 900)
    bg.texture = AssetCache.texture("res://assets/ui/battle_glass_bg.webp")
    bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
    bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
    bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
    bg.z_index = -30
    bg.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
    var bg_mat := ShaderMaterial.new()
    var bg_shader := Shader.new()
    bg_shader.code = """
shader_type canvas_item;
render_mode unshaded;
void fragment() {
    vec4 c = texture(TEXTURE, UV);
    float l = dot(c.rgb, vec3(0.2126, 0.7152, 0.0722));
    c.rgb = mix(vec3(l), c.rgb, 0.96);
    c.rgb = mix(c.rgb, vec3(1.0), 0.035);
    c.rgb = (c.rgb - 0.5) * 0.94 + 0.5;
    COLOR = c;
}
"""
    if not MobilePlatform.is_android():
        bg_mat.shader = bg_shader
        bg.material = bg_mat
    else:
        bg.modulate = Color(0.92,0.94,0.96,1.0)
    add_child(bg)

    if not MobilePlatform.is_android():
        var atmosphere := Atmosphere.new()
        atmosphere.modulate = Color(1,1,1,0.48)
        add_child(atmosphere)

func _battle_frost_panel(panel: Control, lod: float = 1.5, frost: float = 0.045) -> void:
    if MobilePlatform.is_android():
        var mobile_tint := ColorRect.new()
        mobile_tint.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
        mobile_tint.mouse_filter = Control.MOUSE_FILTER_IGNORE
        mobile_tint.color = Color(0.008,0.022,0.038,0.55)
        panel.add_child(mobile_tint)
        return
    var blur := ColorRect.new()
    blur.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    blur.mouse_filter = Control.MOUSE_FILTER_IGNORE
    var mat := ShaderMaterial.new()
    var sh := Shader.new()
    sh.code = """
shader_type canvas_item;
uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_linear_mipmap;
uniform float lod = 1.5;
uniform float frost = 0.045;
void fragment() {
    vec4 c = textureLod(screen_texture, SCREEN_UV, lod);
    c.rgb = mix(c.rgb, vec3(0.008,0.022,0.038), 0.52 + frost);
    COLOR = vec4(c.rgb, 0.90);
}
"""
    mat.shader = sh
    mat.set_shader_parameter("lod",lod)
    mat.set_shader_parameter("frost",frost)
    blur.material = mat
    panel.add_child(blur)

func _build_audio() -> void:
    # P45 — musique + SFX passent par l'Autoload global persistant.
    AudioManager.play_music("res://assets/audio/music/ingame.mp3",-6.0)

func _play_sfx(path: String, volume_db: float = -7.0) -> void:
    AudioManager.play_sfx(path,volume_db)

func _build_impact_pool() -> void:
    for i: int in range(IMPACT_POOL_SIZE):
        var ring := Panel.new()
        ring.visible = false
        ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
        ring.z_index = 45
        add_child(ring)
        impact_ring_pool.append(ring)
        var core := Panel.new()
        core.visible = false
        core.mouse_filter = Control.MOUSE_FILTER_IGNORE
        core.z_index = 46
        add_child(core)
        impact_core_pool.append(core)

func _acquire_impact_panel(pool: Array[Panel]) -> Panel:
    for panel: Panel in pool:
        if not panel.visible:
            panel.modulate = Color.WHITE
            panel.scale = Vector2.ONE
            return panel
    return pool[0] if not pool.is_empty() else null

func _release_impact_panel(panel: Panel) -> void:
    if panel == null:
        return
    panel.visible = false
    panel.modulate = Color.WHITE
    panel.scale = Vector2.ONE

func _build_replacement_modal() -> void:
    replacement_modal = ReplacementModal.new()
    add_child(replacement_modal)
    replacement_modal.setup(cards_by_id)
    replacement_modal.choice_selected.connect(_on_replacement_choice_pressed)
    replacement_modal.timeout_choice.connect(_on_replacement_timeout_choice)

func _build_interface() -> void:
    # HUD bord-à-bord : le duel est désormais l'écran principal.
    var top_glass: Panel = _panel(Rect2(8, 8, 1584, 66), Color(0.010,0.024,0.042,0.52), Color(0.78,0.90,1.0,0.38), 18, 10, Color(0,0,0,0.18), Vector2(0,4))
    _battle_frost_panel(top_glass, 1.35, 0.035)
    _logo(Vector2(28, 23), 37)
    _label("YUGITO", Rect2(72, 19, 155, 42), 28, Color("f5f7fa"), HORIZONTAL_ALIGNMENT_LEFT, true)
    _label("GODOT 2.0", Rect2(226, 22, 104, 20), 10, Color("6dd9ad"), HORIZONTAL_ALIGNMENT_LEFT, true)
    _label("BUILD 47M.2 • COMBAT PERF", Rect2(226, 41, 340, 20), 9, Color("91a6bd"), HORIZONTAL_ALIGNMENT_LEFT, false)
    turn_title_label = _label("TOUR %d   •   %s" % [turn_counter,IdentityManager.display_name().to_upper()], Rect2(510, 21, 250, 36), 18, Color("e7edf4"), HORIZONTAL_ALIGNMENT_CENTER, true)

    # P23 — vrai chrono Classic. Chaque nouveau tour humain repart à 30 s et
    # le compteur arrive du centre de l'écran comme sur le client Tkinter.
    phase_timer_root = Control.new()
    phase_timer_root.position = Vector2(765, 13)
    phase_timer_root.size = Vector2(150, 56)
    phase_timer_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
    phase_timer_root.z_index = 50
    add_child(phase_timer_root)
    _panel_in(phase_timer_root, Rect2(0, 0, 150, 56), Color(0.055, 0.055, 0.018, 0.95), Color(0.95, 0.79, 0.22, 0.72), 13)
    phase_timer_label = _label_in(phase_timer_root, "30 s", Rect2(0, 0, 150, 56), 25, Color("ffe26d"), HORIZONTAL_ALIGNMENT_CENTER, true)
    fps_label = _label("FPS", Rect2(1324, 25, 240, 22), 10, Color("63dda4"), HORIZONTAL_ALIGNMENT_RIGHT, true)

    # Zone de combat en grand verre dépoli, sans aplat bleu-noir.
    var arena_glass: Panel = _panel(Rect2(0, 72, 1594, 824), Color(0.008,0.022,0.038,0.54), Color(0.78,0.90,1.0,0.34), 20, 12, Color(0,0,0,0.18), Vector2(0,6))
    _battle_frost_panel(arena_glass, 1.55, 0.050)
    _panel(Rect2(7, 79, 1580, 810), Color(1,1,1,0.025), Color(1,1,1,0.10), 16)

    _status_bar(Rect2(10, 78, 1570, 40), "IA", Color("e85c66"), false)
    _status_bar(Rect2(10, 848, 1570, 40), IdentityManager.display_name().to_upper(), Color("ff7c2e"), true)

    _capsule(Rect2(154, 132, 120, 23), "ÉQUIPE ADVERSE", Color("e76872"))
    _capsule(Rect2(154, 818, 120, 23), "VOTRE ÉQUIPE", Color("ff8a45"))

    # P26 — les états de TERRAIN ne sont plus attachés à une carte précise.
    enemy_field_effect_label = _label("", Rect2(470, 128, 360, 28), 9, Color("f0c56f"), HORIZONTAL_ALIGNMENT_CENTER, true)
    ally_field_effect_label = _label("", Rect2(470, 810, 360, 28), 9, Color("f0c56f"), HORIZONTAL_ALIGNMENT_CENTER, true)

    enemy_reserve_count_label = _reserve_box(Vector2(12, 254), "RÉSERVE", str(enemy_reserve.size()), Color("7096be"))
    ally_reserve_count_label = _reserve_box(Vector2(12, 598), "RÉSERVE", str(ally_reserve.size()), Color("7096be"))
    enemy_cemetery_value_label = _cemetery_box(Vector2(1176, 254))
    ally_cemetery_value_label = _cemetery_box(Vector2(1176, 598))

    # Panneau d'action resserré contre le bord droit.
    var plan_glass: Panel = _panel(Rect2(1302, 74, 292, 814), Color(0.008,0.022,0.038,0.60), Color(0.78,0.90,1.0,0.40), 20, 12, Color(0,0,0,0.18), Vector2(0,6))
    _battle_frost_panel(plan_glass, 1.60, 0.055)
    _label("PLAN DU TOUR", Rect2(1324, 92, 195, 34), 21, Color("f3f6f9"), HORIZONTAL_ALIGNMENT_LEFT, true)
    _panel(Rect2(1510, 96, 64, 22), Color(0.12,0.18,0.25,0.35), Color(0.43,0.54,0.66,0.42), 11)
    turn_capsule_label = _label("T%d" % turn_counter, Rect2(1510, 96, 64, 22), 8, Color("9ec0dd"), HORIZONTAL_ALIGNMENT_CENTER, true)

    # P22 — fidèle au PC : 3 emplacements distincts (Minato gratuit + A1 + A2).
    timeline_free_button = _timeline_free_step_button(Rect2(1318, 138, 262, 42), "00", "MINATO — GRATUIT", Color("e2b746"))
    timeline_free_subtitle = _label_in(timeline_free_button, "Hiraishin : attaque normale gratuite", Rect2(46, 20, 174, 16), 7, Color("9a8c67"), HORIZONTAL_ALIGNMENT_LEFT, false)
    timeline_free_button.pressed.connect(_on_hiraishin_pressed)
    cancel_free_button = _mini_cancel_button(Rect2(1540, 145, 32, 28), _cancel_planned_free)

    timeline_a1_button = _timeline_step_button(Rect2(1318, 186, 262, 52), "01", "ACTION 1 — IMMÉDIATE", Color("52d6a0"), 1)
    timeline_a1_subtitle = _label_in(timeline_a1_button, "Clique ici pour préparer A1", Rect2(54, 27, 165, 17), 7, Color("8398ad"), HORIZONTAL_ALIGNMENT_LEFT, false)
    cancel_a1_button = _mini_cancel_button(Rect2(1540, 198, 32, 28), _cancel_planned_action.bind(1))
    timeline_a2_button = _timeline_step_button(Rect2(1318, 244, 262, 52), "02", "ACTION 2 — RÉACTION", Color("f2a350"), 2)
    timeline_a2_subtitle = _label_in(timeline_a2_button, "Se déclenche à la validation suivante", Rect2(54, 27, 165, 17), 7, Color("8398ad"), HORIZONTAL_ALIGNMENT_LEFT, false)
    cancel_a2_button = _mini_cancel_button(Rect2(1540, 256, 32, 28), _cancel_planned_action.bind(2))

    _panel(Rect2(1318, 306, 262, 94), Color(0.032, 0.058, 0.092, 0.86), Color(0.34, 0.51, 0.68, 0.28), 10)
    selection_title_label = _label("AUCUN NINJA SÉLECTIONNÉ", Rect2(1330, 313, 238, 22), 10, Color("9db2c8"), HORIZONTAL_ALIGNMENT_CENTER, true)
    selection_subtitle_label = _label("Clique sur une carte du terrain", Rect2(1330, 336, 238, 18), 8, Color("6f879f"), HORIZONTAL_ALIGNMENT_CENTER, false)
    selection_stats_label = _label("Sélection GPU • données réelles", Rect2(1330, 357, 238, 17), 7, Color("586f88"), HORIZONTAL_ALIGNMENT_CENTER, false)
    action_status_label = _label("Préparation : ACTION 1", Rect2(1330, 378, 166, 17), 7, Color("74c79a"), HORIZONTAL_ALIGNMENT_LEFT, false)
    inspect_button = _action_button(Rect2(1492, 368, 80, 32 if MobilePlatform.is_android() else 23), "FICHE", Color("77c8f1"), false)
    inspect_button.disabled = true
    inspect_button.pressed.connect(_open_selected_inspection)

    var actions: Array[Dictionary] = [
        {"id":"taijutsu", "label":"TAIJUTSU", "color":Color("ef6659")},
        {"id":"ninjutsu", "label":"NINJUTSU", "color":Color("58aff0")},
        {"id":"genjutsu", "label":"GENJUTSU", "color":Color("ba85ed")},
        {"id":"special", "label":"TECHNIQUE SPÉCIALE", "color":Color("e2b746")},
        {"id":"reserve", "label":"ÉCHANGE AVEC LA RÉSERVE", "color":Color("58cf8b")}
    ]
    var y: float = 408.0
    for item in actions:
        var action_id: String = str(item["id"])
        var btn: Button = _action_button(Rect2(1318, y, 262, 34), str(item["label"]), item["color"] as Color, false)
        btn.pressed.connect(_on_action_button_pressed.bind(action_id))
        action_buttons[action_id] = btn
        y += 38.0

    # Hiraishin n'est plus un bouton d'action partagé : sa vraie case est en haut.
    free_action_button = timeline_free_button
    copy_action_button = _action_button(Rect2(1318, 598, 262, 28), "COPIE : —", Color("ba85ed"), false)
    copy_action_button.visible = false
    copy_action_button.pressed.connect(_on_action_button_pressed.bind("copy_special"))
    direct_attack_button = _action_button(Rect2(1318, 630, 262, 30), "ATTAQUE DIRECTE", Color("ff7c2e"), false)
    direct_attack_button.pressed.connect(_on_direct_attack_pressed)
    validate_button = _action_button(Rect2(1318, 688, 262, 44), "VALIDER LE PLAN", Color("55d58b"), true)
    validate_button.pressed.connect(_on_validate_plan_pressed)

    _panel(Rect2(1318, 720, 262, 146), Color(0.012, 0.026, 0.043, 0.72), Color(0.27, 0.43, 0.58, 0.22), 10)
    _label("JOURNAL DU DUEL", Rect2(1330, 731, 150, 18), 9, Color("61dba5"), HORIZONTAL_ALIGNMENT_LEFT, true)
    journal_button = _action_button(Rect2(1482, 723, 90, 32 if MobilePlatform.is_android() else 23), "OUVRIR", Color("77c8f1"), false)
    journal_button.pressed.connect(_open_battle_journal)
    battle_log_label = _label("Le journal complet du duel est maintenant enregistré.", Rect2(1330, 755, 226, 92), 8, Color("b6c8d8"), HORIZONTAL_ALIGNMENT_LEFT, false)

    _build_journal_overlay()
    _build_inspection_overlay()
    _build_action_markers()

    # Le remplacement/switch utilise maintenant un vrai écran modal plein écran.

func _build_action_markers() -> void:
    # Visibles uniquement sur nos cartes. L'adversaire ne reçoit aucune info
    # sur A1/A2/AF via cette couche locale.
    for slot: int in range(3, 6):
        var marker: Label = _label("", Rect2(0,0,72,30), 14, Color("fff3a6"), HORIZONTAL_ALIGNMENT_CENTER, true)
        marker.z_index = 25000
        marker.visible = false
        action_marker_labels[slot] = marker
    _refresh_action_markers()

func _marker_add(tags: Dictionary, descriptor: Dictionary, label: String) -> void:
    if descriptor.is_empty() or str(descriptor.get("source_team", "")) != "ally":
        return
    var slot: int = int(descriptor.get("source_slot", -1))
    if slot < 3 or slot > 5:
        return
    if not tags.has(slot): tags[slot] = []
    (tags[slot] as Array).append(label)

func _refresh_action_markers() -> void:
    if action_marker_labels.is_empty(): return
    var tags: Dictionary = {}
    _marker_add(tags, free_action_plan, "AF")
    _marker_add(tags, action1_plan, "A1")
    _marker_add(tags, action2_plan, "A2")
    for slot_v: Variant in action_marker_labels.keys():
        var slot: int = int(slot_v)
        var lab: Label = action_marker_labels[slot] as Label
        var actor: YugitoCardActor = null
        for c: YugitoCardActor in card_actors:
            if c.team_name == "ally" and not c.defeated and c.seed_index_value() == slot:
                actor = c; break
        if actor == null or not tags.has(slot):
            lab.visible = false
            continue
        lab.text = " ".join(tags[slot] as Array)
        lab.position = actor.anchor_position + Vector2(-36, -218)
        lab.visible = true

func _battle_log_set(text_value: String) -> void:
    if battle_log_label != null:
        battle_log_label.text = text_value
    _record_battle_journal(text_value)

func _battle_log_append(text_value: String) -> void:
    if battle_log_label != null:
        battle_log_label.text += text_value
    _record_battle_journal(text_value)

func _record_battle_journal(text_value: String) -> void:
    var clean: String = text_value.strip_edges()
    if clean.is_empty():
        return
    battle_journal_sequence += 1
    var team_tag: String = "TOUR %d" % turn_counter
    var entry: String = "%03d  •  %s  •  %s" % [battle_journal_sequence, team_tag, clean]
    if not battle_journal.is_empty() and battle_journal[-1] == entry:
        return
    battle_journal.append(entry)
    if battle_journal.size() > 300:
        battle_journal.pop_front()
    _refresh_journal_overlay_text()

func _refresh_journal_overlay_text() -> void:
    if journal_rich == null:
        return
    var body: String = ""
    for i: int in range(battle_journal.size() - 1, -1, -1):
        body += "[color=#dbeaf5]%s[/color]\n\n" % battle_journal[i]
    if body.is_empty():
        body = "[color=#8da3b7]Aucun événement enregistré pour le moment.[/color]"
    journal_rich.text = body

func _solo_overlay_active() -> bool:
    return (
        (journal_overlay != null and journal_overlay.visible) or
        (inspection_overlay != null and inspection_overlay.visible) or
        (duel_end_overlay != null and duel_end_overlay.visible)
    )

func _modal_window(parent: Control, rect: Rect2, border: Color) -> Panel:
    var panel := Panel.new()
    panel.position = rect.position
    panel.size = rect.size
    panel.mouse_filter = Control.MOUSE_FILTER_STOP
    var st := StyleBoxFlat.new()
    st.bg_color = Color(0.012,0.026,0.043,0.90)
    st.border_color = border
    st.set_border_width_all(1)
    st.set_corner_radius_all(22)
    st.shadow_color = Color(0,0,0,0.44)
    st.shadow_size = 18
    st.shadow_offset = Vector2(0,8)
    panel.add_theme_stylebox_override("panel",st)
    parent.add_child(panel)
    return panel

func _modal_dim(root: Control, alpha: float = 0.58) -> void:
    var dim := ColorRect.new()
    dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    dim.color = Color(0.006,0.014,0.025,alpha)
    dim.mouse_filter = Control.MOUSE_FILTER_STOP
    root.add_child(dim)

func _build_journal_overlay() -> void:
    journal_overlay = Control.new()
    journal_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    journal_overlay.z_index = 28000
    journal_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
    journal_overlay.visible = false
    add_child(journal_overlay)
    _modal_dim(journal_overlay,0.56)
    var win: Panel = _modal_window(journal_overlay,Rect2(260,90,1080,720),Color(0.55,0.82,1.0,0.68))
    _label_in(win,"JOURNAL DU DUEL",Rect2(34,24,500,42),28,Color("ffffff"),HORIZONTAL_ALIGNMENT_LEFT,true)
    _label_in(win,"Historique réel des actions • plus récent en premier",Rect2(36,62,650,24),10,Color("a9bfd1"),HORIZONTAL_ALIGNMENT_LEFT,false)
    var close_btn: Button = _action_button_in(win,Rect2(900,26,142,40),"FERMER",Color("8cb9d8"),false)
    close_btn.pressed.connect(_close_battle_journal)
    var scroll := ScrollContainer.new()
    scroll.position = Vector2(34,104)
    scroll.size = Vector2(1012,574)
    scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
    win.add_child(scroll)
    journal_rich = RichTextLabel.new()
    journal_rich.custom_minimum_size = Vector2(976,900)
    journal_rich.bbcode_enabled = true
    journal_rich.fit_content = true
    journal_rich.scroll_active = false
    journal_rich.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    journal_rich.add_theme_font_size_override("normal_font_size",10)
    journal_rich.add_theme_color_override("default_color",Color("dce8f2"))
    scroll.add_child(journal_rich)
    _refresh_journal_overlay_text()

func _action_button_in(parent: Control, rect: Rect2, text_value: String, accent: Color, strong: bool) -> Button:
    var btn := Button.new()
    btn.position = rect.position
    btn.size = rect.size
    btn.text = text_value
    btn.flat = true
    btn.focus_mode = Control.FOCUS_ALL
    btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
    btn.add_theme_font_size_override("font_size",12 if strong else 10)
    btn.add_theme_color_override("font_color",Color("f6fbff"))
    var st := StyleBoxFlat.new()
    st.bg_color = Color(0.05,0.085,0.12,0.72)
    st.border_color = Color(accent.r,accent.g,accent.b,0.58)
    st.set_border_width_all(1)
    st.set_corner_radius_all(11)
    var hov := st.duplicate() as StyleBoxFlat
    hov.bg_color = Color(0.09,0.14,0.19,0.88)
    hov.border_color = Color(accent.r,accent.g,accent.b,0.90)
    btn.add_theme_stylebox_override("normal",st)
    btn.add_theme_stylebox_override("hover",hov)
    btn.add_theme_stylebox_override("pressed",hov)
    btn.add_theme_stylebox_override("focus",hov)
    parent.add_child(btn)
    return btn

func _open_battle_journal() -> void:
    if journal_overlay == null:
        return
    _refresh_journal_overlay_text()
    journal_overlay.visible = true

func _close_battle_journal() -> void:
    if journal_overlay != null:
        journal_overlay.visible = false

func _build_inspection_overlay() -> void:
    inspection_overlay = Control.new()
    inspection_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    inspection_overlay.z_index = 27000
    inspection_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
    inspection_overlay.visible = false
    add_child(inspection_overlay)
    _modal_dim(inspection_overlay,0.52)
    var win: Panel = _modal_window(inspection_overlay,Rect2(330,88,940,724),Color(0.64,0.86,1.0,0.64))
    _label_in(win,"FICHE NINJA",Rect2(34,24,420,42),28,Color("ffffff"),HORIZONTAL_ALIGNMENT_LEFT,true)
    _label_in(win,"Inspection hors action • alliés et ennemis",Rect2(36,62,600,24),10,Color("a9bfd1"),HORIZONTAL_ALIGNMENT_LEFT,false)
    var close_btn: Button = _action_button_in(win,Rect2(760,26,142,40),"FERMER",Color("8cb9d8"),false)
    close_btn.pressed.connect(_close_inspection)
    var scroll := ScrollContainer.new()
    scroll.position = Vector2(34,104)
    scroll.size = Vector2(872,576)
    scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
    win.add_child(scroll)
    inspection_rich = RichTextLabel.new()
    inspection_rich.custom_minimum_size = Vector2(836,820)
    inspection_rich.bbcode_enabled = true
    inspection_rich.fit_content = true
    inspection_rich.scroll_active = false
    inspection_rich.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    inspection_rich.add_theme_font_size_override("normal_font_size",11)
    inspection_rich.add_theme_color_override("default_color",Color("dce8f2"))
    scroll.add_child(inspection_rich)

    # P48 : actions tactiles directement dans la fiche. La SPÉCIALE est une
    # action de premier rang, au même niveau que TAI/NIN/GEN.
    inspection_action_root = Control.new()
    inspection_action_root.position = Vector2(34, 554)
    inspection_action_root.size = Vector2(872, 164)
    inspection_action_root.z_index = 4
    win.add_child(inspection_action_root)
    var sheet_actions: Array[Dictionary] = [
        {"id":"taijutsu","name":"Taijutsu","label":"TAIJUTSU","c":Color("ef6659")},
        {"id":"ninjutsu","name":"Ninjutsu","label":"NINJUTSU","c":Color("58aff0")},
        {"id":"genjutsu","name":"Genjutsu","label":"GENJUTSU","c":Color("ba85ed")},
        {"id":"special","name":"Special","label":"SPÉCIALE","c":Color("e2b746")},
        {"id":"reserve","name":"Reserve","label":"SWITCH RÉSERVE","c":Color("58cf8b")}
    ]
    for i: int in range(sheet_actions.size()):
        var item: Dictionary = sheet_actions[i]
        var col: int = i if i < 3 else i - 3
        var row_y: float = 4.0 if i < 3 else 62.0
        var b: Button = _action_button_in(inspection_action_root, Rect2(col * 286.0, row_y, 276, 50), str(item["label"]), item["c"] as Color, true)
        b.name = str(item["name"])
        b.pressed.connect(_sheet_action_pressed.bind(str(item["id"])))
    var cancel_action: Button = _action_button_in(inspection_action_root, Rect2(572, 62, 276, 50), "ANNULER ACTION", Color("e85c66"), true)
    cancel_action.name = "CancelAction"
    cancel_action.pressed.connect(_sheet_cancel_action_pressed)
    var af: Button = _action_button_in(inspection_action_root, Rect2(572, 120, 276, 38), "AF • MINATO", Color("f0d25e"), true)
    af.name = "Free"
    af.pressed.connect(_sheet_free_pressed)

func _open_selected_inspection() -> void:
    if selected_actor == null or not is_instance_valid(selected_actor) or inspection_overlay == null:
        return
    _open_actor_sheet(selected_actor)

func _open_actor_sheet(actor: YugitoCardActor) -> void:
    if actor == null or not is_instance_valid(actor) or inspection_overlay == null:
        return
    inspection_actor = actor
    _populate_inspection(actor)
    _refresh_inspection_actions(actor)
    inspection_overlay.visible = true

func _refresh_inspection_actions(actor: YugitoCardActor) -> void:
    if inspection_action_root == null:
        return
    inspection_action_root.visible = actor != null and actor.team_name == "ally" and current_turn_team == "ally" and not resolving_action and not ai_thinking
    if not inspection_action_root.visible:
        return
    var can_act_now: bool = _actor_can_act(actor)
    for key: Variant in action_buttons.keys():
        var sheet_btn: Button = inspection_action_root.get_node_or_null(str(key).capitalize()) as Button
        if sheet_btn == null:
            continue
        var enabled: bool = can_act_now
        if str(key) == "special": enabled = enabled and _actor_special_available(actor)
        if str(key) == "reserve": enabled = not ally_reserve.is_empty() and _can_leave_field_voluntarily(actor)
        sheet_btn.disabled = not enabled

func _sheet_action_pressed(action_id: String) -> void:
    if inspection_actor == null or not is_instance_valid(inspection_actor):
        return
    selected_actor = inspection_actor
    for card: YugitoCardActor in card_actors:
        card.set_selected(card == inspection_actor)
    _close_inspection()
    _on_action_button_pressed(action_id)

func _sheet_free_pressed() -> void:
    _close_inspection()
    _on_hiraishin_pressed()

func _sheet_cancel_action_pressed() -> void:
    current_action = ""
    free_action_mode = false
    tobi_prediction_enemy_uid = 0
    tobi_prediction_action_id = "special"
    _close_inspection()
    _refresh_action_buttons()
    _refresh_plan_ui()
    _battle_log_set("Action en cours annulée.")

func _close_inspection() -> void:
    if inspection_overlay != null:
        inspection_overlay.visible = false
    inspection_actor = null

func _populate_inspection(actor: YugitoCardActor) -> void:
    if inspection_rich == null:
        return
    var data: Dictionary = cards_by_id.get(actor.card_id,{}) as Dictionary
    var team_label: String = "ALLIÉ" if actor.team_name == "ally" else "ENNEMI"
    var status_lines: Array[String] = []
    if actor.shield > 0:
        status_lines.append("Bouclier : %d" % actor.shield)
    if actor.disabled_turns > 0:
        status_lines.append("STUN : %d tour(s)" % actor.disabled_turns)
    if actor.special_cooldown > 0:
        status_lines.append("Recharge spéciale : %d tour(s)" % actor.special_cooldown)
    for key: Variant in actor.status_tags.keys():
        var value: Variant = actor.status_tags[key]
        var show: bool = false
        if value is bool:
            show = bool(value)
        elif value is int:
            show = int(value) != 0
        elif value is float:
            show = not is_zero_approx(float(value))
        elif value is String:
            show = not str(value).is_empty()
        if show:
            status_lines.append("%s : %s" % [str(key).replace("_"," ").to_upper(),str(value)])
    var status_text: String = "Aucun état actif" if status_lines.is_empty() else "\n".join(status_lines)
    var roles: Array = data.get("roles",[]) as Array
    inspection_rich.text = """[font_size=24][b]%s[/b][/font_size]
[color=#9fcde9]%s • %s★ • %s[/color]

[b]PV[/b]  %d / %d
[b]TAI[/b]  %d    [b]NIN[/b]  %d    [b]GEN[/b]  %d
[b]Bouclier[/b]  %d
[b]Synergie[/b]  %s
[b]Rôles[/b]  %s

[color=#65d7a5][font_size=16][b]PASSIF — %s[/b][/font_size][/color]
%s

[color=#e7c75b][font_size=16][b]SPÉCIALE — %s[/b][/font_size][/color]
%s

[color=#8acaf0][font_size=16][b]ÉTATS ACTIFS[/b][/font_size][/color]
%s
""" % [
        actor.display_name,team_label,str(data.get("stars",actor.stars)),actor.element_name.to_upper(),
        actor.hp,actor.max_hp,_actor_effective_stat(actor,"taijutsu"),_actor_effective_stat(actor,"ninjutsu"),_actor_effective_stat(actor,"genjutsu"),
        actor.shield,actor.synergy_label() if not actor.synergy_label().is_empty() else "—"," • ".join(roles),
        str(data.get("passive_name",actor.passive_name)),str(data.get("passive","—")),
        str(data.get("special_name",actor.special_name)),str(data.get("special","—")),status_text
    ]

func _build_duel_end_overlay() -> void:
    if duel_end_overlay != null:
        duel_end_overlay.queue_free()
    duel_end_overlay = Control.new()
    duel_end_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    duel_end_overlay.z_index = 26000
    duel_end_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
    add_child(duel_end_overlay)

func _show_duel_end_overlay(victory: bool, reason: String) -> void:
    _build_duel_end_overlay()
    _modal_dim(duel_end_overlay,0.68)
    var accent: Color = Color("61dba5") if victory else Color("ef6b70")
    var win: Panel = _modal_window(duel_end_overlay,Rect2(350,150,900,600),Color(accent.r,accent.g,accent.b,0.74))
    _label_in(win,"DUEL TERMINÉ",Rect2(40,34,820,34),15,Color("b5c7d7"),HORIZONTAL_ALIGNMENT_CENTER,true)
    _label_in(win,"VICTOIRE" if victory else "DÉFAITE",Rect2(40,72,820,74),46,accent,HORIZONTAL_ALIGNMENT_CENTER,true)
    _label_in(win,reason,Rect2(100,148,700,56),12,Color("eef6fb"),HORIZONTAL_ALIGNMENT_CENTER,false)
    var summary: String = "TOUR %d   •   %s %d/%d PV   •   IA %d/%d PV\nCIMETIÈRE : TOI %d   •   IA %d   •   ÉVÉNEMENTS %d" % [
        turn_counter,IdentityManager.display_name().to_upper(),ally_player_hp,PLAYER_HP_MAX,enemy_player_hp,PLAYER_HP_MAX,
        ally_cemetery_count,enemy_cemetery_count,battle_journal.size()
    ]
    _label_in(win,summary,Rect2(100,222,700,64),11,Color("c6d6e3"),HORIZONTAL_ALIGNMENT_CENTER,false)
    var journal_preview := RichTextLabel.new()
    journal_preview.position = Vector2(80,304)
    journal_preview.size = Vector2(740,126)
    journal_preview.bbcode_enabled = true
    journal_preview.fit_content = false
    journal_preview.scroll_active = false
    journal_preview.add_theme_font_size_override("normal_font_size",9)
    var recent: Array[String] = []
    var start_i: int = maxi(0,battle_journal.size()-4)
    for i: int in range(start_i,battle_journal.size()):
        recent.append(battle_journal[i])
    journal_preview.text = "[color=#93aabd]" + "\n".join(recent) + "[/color]"
    win.add_child(journal_preview)
    var replay_btn: Button = _action_button_in(win,Rect2(74,470,230,64),"REJOUER",Color("61dba5"),true)
    replay_btn.pressed.connect(func() -> void: replay_requested.emit())
    var journal_btn: Button = _action_button_in(win,Rect2(335,470,230,64),"JOURNAL",Color("77c8f1"),true)
    journal_btn.pressed.connect(_open_battle_journal)
    var menu_btn: Button = _action_button_in(win,Rect2(596,470,230,64),"MENU",Color("ef9da5"),true)
    menu_btn.pressed.connect(func() -> void: return_to_menu_requested.emit())

func _configure_session_decks() -> void:
    if not GameSession.configured:
        return
    ally_reserve.clear()
    enemy_reserve.clear()
    for cid: String in GameSession.ally_deck:
        if not GameSession.ally_starters.has(cid):
            ally_reserve.append(cid)
    for cid: String in GameSession.enemy_deck:
        if not GameSession.enemy_starters.has(cid):
            enemy_reserve.append(cid)

func _spawn_cards() -> void:
    var enemy_ids: Array[String] = ["shikamaru", "ino", "kankuro"]
    var ally_ids: Array[String] = ["naruto", "sasuke", "kakashi"]
    if GameSession.configured and GameSession.enemy_starters.size() == 3 and GameSession.ally_starters.size() == 3:
        enemy_ids = GameSession.enemy_starters.duplicate()
        ally_ids = GameSession.ally_starters.duplicate()
    var xs: Array[float] = [410.0, 760.0, 1110.0]
    for i in range(3):
        _spawn_card(enemy_ids[i], Vector2(xs[i], 322.0), i, "enemy")
        _spawn_card(ally_ids[i], Vector2(xs[i], 678.0), i + 3, "ally")

func _spawn_card(card_id: String, anchor: Vector2, seed_index: int, team_name: String) -> void:
    if not cards_by_id.has(card_id):
        push_error("Carte absente: " + card_id)
        return
    var actor: YugitoCardActor = CardActor.new()
    var card_data: Dictionary = cards_by_id[card_id] as Dictionary
    actor.z_index = 8
    add_child(actor)
    actor.setup(card_data, anchor, seed_index, team_name)
    actor.battle_uid = next_actor_uid
    next_actor_uid += 1
    actor.selection_requested.connect(_on_card_selection_requested)
    card_actors.append(actor)

func _discard_planning_virtual_actor() -> void:
    if planning_virtual_actor != null and is_instance_valid(planning_virtual_actor):
        if selected_actor == planning_virtual_actor:
            selected_actor = null
        planning_virtual_actor.free()
    planning_virtual_actor = null

func _planning_a1_switch() -> Dictionary:
    if planning_slot != 2 or action1_plan.is_empty() or str(action1_plan.get("kind", "")) != "switch":
        return {}
    return action1_plan

func _planning_virtual_for_clicked_actor(actor: YugitoCardActor) -> YugitoCardActor:
    if actor == null or not is_instance_valid(actor) or actor.team_name != "ally":
        return actor
    var sw: Dictionary = _planning_a1_switch()
    if sw.is_empty():
        return actor
    if int(sw.get("source_uid", 0)) != actor.battle_uid:
        return actor
    var incoming_id: String = str(sw.get("incoming_id", ""))
    if incoming_id.is_empty() or not cards_by_id.has(incoming_id):
        return actor
    var source_slot: int = int(sw.get("source_slot", actor.seed_index_value()))
    if planning_virtual_actor != null and is_instance_valid(planning_virtual_actor):
        if planning_virtual_actor.card_id == incoming_id and planning_virtual_actor.seed_index_value() == source_slot:
            return planning_virtual_actor
        _discard_planning_virtual_actor()
    var virtual_actor: YugitoCardActor = CardActor.new()
    virtual_actor.setup_logic_only(cards_by_id[incoming_id] as Dictionary, source_slot, "ally")
    if ally_reserve_states.has(incoming_id):
        virtual_actor.import_state((ally_reserve_states[incoming_id] as Dictionary).duplicate(true))
    # Une entrée A1 réinitialise les états contextuels de Counter-Switch ; Haku,
    # lui, arme bien ses miroirs à chaque vraie entrée sur le terrain.
    virtual_actor.reactive_entry_guard = false
    virtual_actor.status_tags.erase("reactive_entry_cycle")
    virtual_actor.status_tags.erase("yamato_counter_gift")
    if incoming_id == "haku":
        virtual_actor.status_tags["haku_entry_guard"] = true
    virtual_actor.status_tags["planning_virtual"] = true
    virtual_actor.status_tags["planning_virtual_slot"] = source_slot
    planning_virtual_actor = virtual_actor
    return planning_virtual_actor

func _planning_reserve_ids(team_name: String) -> Array[String]:
    var result: Array[String] = (ally_reserve if team_name == "ally" else enemy_reserve).duplicate()
    if not action1_plan.is_empty() and str(action1_plan.get("kind", "")) == "switch" and str(action1_plan.get("source_team", "")) == team_name:
        var incoming_id: String = str(action1_plan.get("incoming_id", ""))
        var outgoing_id: String = str(action1_plan.get("outgoing_id", ""))
        result.erase(incoming_id)
        if not outgoing_id.is_empty() and not result.has(outgoing_id):
            result.append(outgoing_id)
    return result

func _on_card_selection_requested(actor: YugitoCardActor) -> void:
    if resolving_action or ai_thinking or current_turn_team != "ally" or _replacement_overlay_active() or _solo_overlay_active():
        return

    # Tobi doit obligatoirement placer sa bombe secrète au début de son tour.
    if tobi_bomb_pending_team == "ally":
        if actor.team_name != "enemy" or actor.defeated:
            _battle_log_set("Tobi : choisis d'abord un Ninja ENNEMI pour placer la bombe secrète.")
            return
        _place_tobi_bomb("ally", actor)
        return

    # Deuxième étape de la spéciale de Tobi (y compris une copie de Kakashi) :
    # après l'ennemi prédit, choisir l'allié que cet ennemi devrait attaquer.
    if current_action == "tobi_prediction_ally" and selected_actor != null:
        if actor.team_name != "ally" or actor.defeated:
            _battle_log_set("C'était prévu ! : choisis maintenant le Ninja ALLIÉ que l'ennemi devrait attaquer.")
            return
        var predicted_enemy: YugitoCardActor = _resolve_actor_uid(tobi_prediction_enemy_uid)
        if predicted_enemy == null or predicted_enemy.defeated:
            current_action = ""
            tobi_prediction_enemy_uid = 0
            _battle_log_set("La cible prédite n'est plus disponible.")
            return
        _store_planned_action(selected_actor, predicted_enemy, tobi_prediction_action_id, {"prediction_ally_uid":actor.battle_uid, "prediction_ally_id":actor.card_id})
        tobi_prediction_enemy_uid = 0
        tobi_prediction_action_id = "special"
        return

    var current_is_special: bool = current_action in ["special", "copy_special"]
    var current_special_id: String = ""
    if current_is_special and selected_actor != null:
        current_special_id = str(selected_actor.status_tags.get("copied_special_id", "")) if current_action == "copy_special" else selected_actor.card_id

    if current_is_special and selected_actor != null and selected_actor.team_name == "ally" and actor.team_name == "ally" and _special_targets_ally(current_special_id):
        var ally_target: YugitoCardActor = _planning_virtual_for_clicked_actor(actor)
        _store_planned_action(selected_actor, ally_target, current_action)
        return

    if current_action != "" and selected_actor != null and selected_actor.team_name == "ally" and actor.team_name == "enemy" and not actor.defeated:
        var can_target_untargetable: bool = (current_is_special and current_special_id in ["sasuke", "minato", "obito", "kakashi", "shikamaru"]) or selected_actor.card_id == "minato"
        if actor.is_untargetable() and not can_target_untargetable:
            _battle_log_set("%s est INCIBLABLE : choisis une autre cible." % actor.display_name)
            _play_sfx("res://assets/audio/ui/pick.mp3", -18.0)
            return
        if current_is_special and current_special_id == "tobi":
            tobi_prediction_enemy_uid = actor.battle_uid
            tobi_prediction_action_id = current_action
            current_action = "tobi_prediction_ally"
            action_status_label.text = "TOBI : choisis maintenant le Ninja ALLIÉ prédit"
            _battle_log_set("C'était prévu ! : %s est l'attaquant prédit. Clique maintenant le Ninja allié qu'il devrait viser." % actor.display_name)
            _play_sfx("res://assets/audio/ui/pick.mp3", -12.0)
            return
        # P25 — Neji/Hinata : comme le client PC, la cible offensive est choisie
        # d'abord, puis le joueur désigne secrètement UNE carte de la réserve
        # adverse. Cette carte sera forcée au prochain Switch OU remplacement.
        if current_is_special and current_special_id in ["neji", "hinata"]:
            var tracker_reserve: Array[String] = enemy_reserve.duplicate()
            if tracker_reserve.is_empty():
                _store_planned_action(selected_actor, actor, current_action)
                _battle_log_set("Byakugan : réserve ennemie vide, spéciale planifiée sans traque.")
                return
            replacement_context = {
                "mode":"byakugan_tracker_plan",
                "actor":selected_actor,
                "target_uid":actor.battle_uid,
                "target_id":actor.card_id,
                "action_id":current_action,
                "special_id":current_special_id,
                "candidates":tracker_reserve,
                "planning_slot":planning_slot
            }
            replacement_modal.show_choices(
                "BYAKUGAN — TRAQUEUR",
                "Choisis la prochaine carte adverse à entrer. Elle sera imposée au prochain Switch OU remplacement.",
                tracker_reserve
            )
            current_action = ""
            _battle_log_set("%s : choisis secrètement la carte de réserve adverse à traquer." % selected_actor.display_name)
            _refresh_action_buttons()
            return
        _store_planned_action(selected_actor, actor, current_action)
        return

    var selection_candidate: YugitoCardActor = _planning_virtual_for_clicked_actor(actor)
    if selected_actor == selection_candidate:
        actor.set_selected(false)
        selected_actor = null
        current_action = ""
        _refresh_selection_panel()
        _refresh_action_buttons()
        return

    for card in card_actors:
        # Quand le Ninja entrant est virtuellement sélectionné pour A2, on garde
        # le halo sur sa future case (la carte sortante est encore affichée).
        card.set_selected(card == actor)
    selected_actor = selection_candidate
    _play_sfx("res://assets/audio/ui/pick.mp3", -12.0)
    if selection_candidate != actor:
        _battle_log_set("%s est prévu après le Switch A1 : prépare maintenant son Action 2." % selection_candidate.display_name)
    _refresh_selection_panel()
    _refresh_action_buttons()
    # P48 mobile : toucher une carte ouvre sa fiche. Si une action est déjà
    # choisie, le même toucher reste évidemment le choix de cible.
    if MobilePlatform.is_android() and current_action.is_empty():
        _open_actor_sheet(selection_candidate)

func _set_planning_slot(slot: int) -> void:
    if resolving_action or ai_thinking or current_turn_team != "ally" or _replacement_overlay_active():
        return
    planning_slot = clampi(slot, 1, 2)
    free_action_mode = false
    current_action = ""
    if planning_slot == 1 and planning_virtual_actor != null and selected_actor == planning_virtual_actor:
        selected_actor = null
        for card in card_actors:
            card.set_selected(false)
        _refresh_selection_panel()
    _refresh_plan_ui()
    _refresh_action_buttons()

func _on_action_button_pressed(action_id: String) -> void:
    if resolving_action or ai_thinking or current_turn_team != "ally" or _replacement_overlay_active():
        return
    if tobi_bomb_pending_team == "ally":
        _battle_log_set("TOBI : place d'abord la bombe secrète obligatoire sur un Ninja ennemi.")
        return
    if action_id == "reserve":
        free_action_mode = false
        _manual_reserve_exchange()
        return
    if selected_actor == null or selected_actor.team_name != "ally" or selected_actor.defeated:
        _battle_log_set("Sélectionne d'abord un Ninja allié.")
        return
    if not _actor_can_act(selected_actor):
        _battle_log_set("%s est actuellement inutilisable." % selected_actor.display_name)
        return
    var is_special_choice: bool = action_id in ["special", "copy_special"]
    var chosen_special_id: String = str(selected_actor.status_tags.get("copied_special_id", "")) if action_id == "copy_special" else selected_actor.card_id
    if free_action_mode:
        if selected_actor.card_id != "minato" or bool(selected_actor.status_tags.get("minato_free_used_cycle", false)):
            free_action_mode = false
        elif action_id in ["taijutsu", "ninjutsu", "genjutsu"]:
            current_action = "free_%s" % action_id
            action_status_label.text = "HIRAISHIN : %s — choisis une cible" % _action_display_name(action_id)
            _battle_log_set("Hiraishin gratuit de Minato : clique une cible ennemie.")
            _refresh_action_buttons()
            return
    if action_id == "special" and not _actor_special_available(selected_actor):
        _battle_log_set("La technique spéciale de %s n'est pas disponible." % selected_actor.display_name)
        return
    if action_id == "copy_special" and not _actor_copied_special_available(selected_actor):
        _battle_log_set("La technique copiée de Kakashi n'est pas disponible.")
        return
    if action_id in ["taijutsu", "ninjutsu", "genjutsu"] and not _actor_can_use_style(selected_actor, action_id):
        _battle_log_set("%s ne peut pas utiliser %s actuellement." % [selected_actor.display_name, _action_display_name(action_id)])
        return

    # Tobi : la prédiction se prépare dans deux fenêtres tactiles à portraits.
    # Étape 1 = attaquant adverse prédit. Étape 2 = cible alliée prédite.
    if is_special_choice and chosen_special_id == "tobi":
        var prediction_candidates: Array[String] = []
        for predicted_enemy: YugitoCardActor in _living_cards("enemy"):
            prediction_candidates.append(predicted_enemy.card_id)
        if prediction_candidates.is_empty():
            _battle_log_set("Tobi : aucun attaquant adverse disponible pour la prédiction.")
            return
        replacement_context = {
            "mode":"tobi_prediction_enemy",
            "actor":selected_actor,
            "action_id":action_id,
            "planning_slot":planning_slot,
            "candidates":prediction_candidates
        }
        replacement_modal.show_choices("TOBI — PRÉDICTION 1/2", "Quel Ninja ennemi effectuera selon toi la PROCHAINE attaque ?", prediction_candidates)
        current_action = ""
        _battle_log_set("TOBI : choisis l'attaquant adverse prédit.")
        _refresh_action_buttons()
        return

    # Certaines spéciales PC ouvrent un choix privé avant d'être placées dans A1/A2.
    if is_special_choice and chosen_special_id == "ao":
        var ao_reserve: Array[String] = enemy_reserve
        if ao_reserve.is_empty():
            _battle_log_set("Byakugan dérobé : la réserve ennemie est vide.")
            return
        var ao_candidates: Array[String] = _make_reserve_candidates(ao_reserve, mini(5, ao_reserve.size()), false)
        replacement_context = {"mode":"ao_tracker_plan", "actor":selected_actor, "candidates":ao_candidates, "planning_slot":planning_slot}
        replacement_modal.show_choices("BYAKUGAN DÉROBÉ", "Choisis la carte ennemie qui sera FORCÉE à être la prochaine à entrer sur le terrain.", ao_candidates)
        _battle_log_set("Ao : choisis secrètement la prochaine entrée ennemie.")
        _refresh_action_buttons()
        return
    if is_special_choice and chosen_special_id == "orochimaru":
        var oro_grave: Array[String] = enemy_graveyard
        if oro_grave.is_empty():
            _battle_log_set("Réincarnation interdite : le cimetière ennemi est vide.")
            return
        var oro_candidates: Array[String] = _make_reserve_candidates(oro_grave, mini(5, oro_grave.size()), false)
        replacement_context = {"mode":"orochimaru_grave_plan", "actor":selected_actor, "candidates":oro_candidates, "planning_slot":planning_slot}
        replacement_modal.show_choices("RÉINCARNATION INTERDITE", "Choisis le Ninja du cimetière ennemi qu'Orochimaru volera pour ta réserve.", oro_candidates)
        _battle_log_set("Orochimaru : choisis une carte du cimetière ennemi.")
        _refresh_action_buttons()
        return

    # Certaines techniques du client PC ne demandent aucune cible.
    if is_special_choice and _special_requires_no_target(chosen_special_id):
        _store_planned_action(selected_actor, null, action_id)
        return

    # P22 : comme Classic, choisir un art ne prépare plus automatiquement une attaque
    # directe. Le bouton ATTAQUE DIRECTE devient explicitement disponible si le terrain
    # adverse est vide.
    current_action = action_id
    var target_text: String = "une carte alliée" if is_special_choice and _special_targets_ally(chosen_special_id) else "une carte ennemie"
    if not is_special_choice and _living_cards("enemy").is_empty():
        target_text = "ATTAQUE DIRECTE"
    action_status_label.text = "A%d : %s — choisis une cible" % [planning_slot, _action_display_name(action_id)]
    _battle_log_set("%s prépare %s en Action %d. Clique %s." % [selected_actor.display_name, _action_display_name(action_id), planning_slot, target_text])
    _refresh_action_buttons()

func _store_planned_action(source: YugitoCardActor, target: YugitoCardActor, action_id: String, extra_metadata: Dictionary = {}) -> void:
    if source == null or not is_instance_valid(source):
        return
    var is_free: bool = action_id.begins_with("free_")
    var copied_choice: bool = action_id == "copy_special"
    var stored_action: String = action_id.trim_prefix("free_") if is_free else ("special" if copied_choice else action_id)
    if copied_choice:
        extra_metadata = extra_metadata.duplicate(true)
        extra_metadata["copied"] = true
        extra_metadata["copied_special_id"] = str(source.status_tags.get("copied_special_id", ""))
        extra_metadata["special_resource"] = "copy"
    elif stored_action == "special":
        extra_metadata = extra_metadata.duplicate(true)
        extra_metadata["special_resource"] = "own"
    if is_free and (source.card_id != "minato" or bool(source.status_tags.get("minato_free_used_cycle", false))):
        _battle_log_set("Hiraishin gratuit n'est plus disponible.")
        free_action_mode = false
        current_action = ""
        return
    if stored_action == "special" and _actor_special_already_planned(source, str(extra_metadata.get("special_resource", "own"))):
        _battle_log_set("Cette ressource spéciale de ce Ninja est déjà prévue dans le plan.")
        current_action = ""
        return
    var source_virtual: bool = bool(source.status_tags.get("planning_virtual", false))
    var target_virtual: bool = target != null and bool(target.status_tags.get("planning_virtual", false))
    var descriptor: Dictionary = {
        "kind": "attack",
        "action_id": stored_action,
        "free_action": is_free,
        "source_uid": 0 if source_virtual else source.battle_uid,
        "source_id": source.card_id,
        "source_team": source.team_name,
        "source_slot": source.seed_index_value(),
        "target_uid": 0 if target == null or target_virtual else target.battle_uid,
        "target_id": "" if target == null else target.card_id,
        "target_team": "" if target == null else target.team_name,
        "target_slot": -1 if target == null else target.seed_index_value(),
        "planned_from_virtual_entry": source_virtual
    }
    for meta_key: Variant in extra_metadata.keys():
        descriptor[meta_key] = extra_metadata[meta_key]
    if is_free:
        free_action_plan = descriptor
        source.status_tags["minato_free_reserved"] = true
        free_action_mode = false
    elif planning_slot == 1:
        action1_plan = descriptor
        planning_slot = 2
    else:
        action2_plan = descriptor
    current_action = ""
    _play_sfx("res://assets/audio/ui/pick.mp3", -14.0)
    _refresh_plan_ui()
    _refresh_action_buttons()

func _actor_special_already_planned(actor: YugitoCardActor, resource: String = "own") -> bool:
    if actor == null or not is_instance_valid(actor):
        return false
    for descriptor in [action1_plan, action2_plan]:
        if descriptor.is_empty():
            continue
        if str(descriptor.get("action_id", "")) != "special" or str(descriptor.get("source_id", "")) != actor.card_id:
            continue
        if str(descriptor.get("special_resource", "own")) == resource:
            return true
    return false

func _special_requires_no_target(card_id: String) -> bool:
    return card_id in ["kankuro", "gaara", "jiraiya", "choji", "anko", "chiyo", "gengetsu", "konan", "kurotsuchi", "tenten", "tobirama", "shisui", "kimimaro", "konohamaru", "ao", "orochimaru"]

func _special_targets_ally(card_id: String) -> bool:
    return card_id in ["kurenai", "karin", "rock_lee"]

func _on_direct_attack_pressed() -> void:
    if resolving_action or ai_thinking or current_turn_team != "ally" or _replacement_overlay_active():
        return
    if selected_actor == null or selected_actor.team_name != "ally" or selected_actor.defeated:
        _battle_log_set("Sélectionne d'abord un Ninja allié.")
        return
    var normal_action: String = current_action.trim_prefix("free_")
    if normal_action not in ["taijutsu", "ninjutsu", "genjutsu"]:
        _battle_log_set("Choisis d'abord TAIJUTSU, NINJUTSU ou GENJUTSU.")
        return
    if not _living_cards("enemy").is_empty():
        _battle_log_set("Une attaque directe n'est possible que si les 3 slots adverses sont vides.")
        return
    _store_planned_action(selected_actor, null, current_action)

func _cancel_planned_free() -> void:
    if free_action_plan.is_empty() and not free_action_mode:
        return
    var source: YugitoCardActor = _resolve_descriptor_source(free_action_plan) if not free_action_plan.is_empty() else selected_actor
    if source != null and is_instance_valid(source):
        source.status_tags.erase("minato_free_reserved")
    free_action_plan = {}
    free_action_mode = false
    if current_action.begins_with("free_"):
        current_action = ""
    _battle_log_set("Action gratuite de Minato annulée.")
    _refresh_plan_ui()
    _refresh_action_buttons()

func _cancel_planned_action(slot: int) -> void:
    if slot == 1:
        if action1_plan.is_empty():
            return
        var removed_was_switch: bool = str(action1_plan.get("kind", "")) == "switch"
        action1_plan = {}
        if removed_was_switch and not action2_plan.is_empty() and bool(action2_plan.get("planned_from_virtual_entry", false)):
            action2_plan = {}
            _battle_log_set("Action 1 annulée ; l'Action 2 dépendante du Switch a aussi été annulée.")
        else:
            _battle_log_set("Action 1 annulée.")
        planning_slot = 1
        _discard_planning_virtual_actor()
    elif slot == 2:
        if action2_plan.is_empty():
            return
        action2_plan = {}
        _battle_log_set("Action 2 annulée.")
        planning_slot = 2 if not action1_plan.is_empty() else 1
    current_action = ""
    _refresh_selection_panel()
    _refresh_plan_ui()
    _refresh_action_buttons()

func _on_hiraishin_pressed() -> void:
    if resolving_action or ai_thinking or current_turn_team != "ally" or _replacement_overlay_active():
        return
    var minato: YugitoCardActor = _find_live_card("ally", "minato")
    if minato == null or minato.defeated:
        _battle_log_set("Minato doit être sur le terrain pour préparer Hiraishin.")
        return
    if bool(minato.status_tags.get("minato_free_used_cycle", false)) or not free_action_plan.is_empty():
        _battle_log_set("Hiraishin gratuit est déjà prévu/utilisé ce cycle.")
        return
    # Classic : cliquer la case gratuite sélectionne directement Minato.
    selected_actor = minato
    for card in card_actors:
        card.set_selected(card == minato)
    free_action_mode = true
    current_action = ""
    action_status_label.text = "HIRAISHIN GRATUIT — choisis TAI / NIN / GEN"
    _battle_log_set("Hiraishin ne consomme ni A1 ni A2. Choisis un art normal puis une cible.")
    _refresh_selection_panel()
    _refresh_action_buttons()

func _announce_zetsu_switch_a2(observer_team: String, descriptor: Dictionary) -> void:
    if descriptor.is_empty() or str(descriptor.get("kind", "")) != "switch":
        return
    var zetsu: YugitoCardActor = _find_live_card(observer_team, "zetsu")
    if zetsu == null:
        return
    var outgoing_id: String = str(descriptor.get("source_id", descriptor.get("outgoing_id", "")))
    var incoming_id: String = str(descriptor.get("incoming_id", ""))
    var outgoing_name: String = str((_special_data_for_id(outgoing_id)).get("name", outgoing_id))
    var incoming_name: String = str((_special_data_for_id(incoming_id)).get("name", incoming_id))
    if battle_log_label != null:
        _battle_log_append("  •  ESPION ZETSU — Switch A2 révélé : %s → %s" % [outgoing_name, incoming_name])

func _on_validate_plan_pressed() -> void:
    _commit_player_plan(false)

func _commit_player_plan(allow_empty: bool = false) -> void:
    if resolving_action or ai_thinking or current_turn_team != "ally" or _replacement_overlay_active():
        return
    if tobi_bomb_pending_team == "ally" and not allow_empty:
        _battle_log_set("Validation impossible : Tobi doit d'abord placer sa bombe secrète.")
        return
    if action1_plan.is_empty() and action2_plan.is_empty() and free_action_plan.is_empty() and ai_delayed_action2.is_empty() and not allow_empty:
        _battle_log_set("Prépare au moins une action avant de valider.")
        return

    _stop_phase_timer()
    resolving_action = true
    current_action = ""
    var steps: Array[Dictionary] = []

    # PC exact : l'A2 adverse est consommée à CETTE validation et se résout
    # avant Hiraishin puis avant A1. Même si elle devient illégale, elle est consommée.
    if not ai_delayed_action2.is_empty():
        steps.append({"descriptor":ai_delayed_action2.duplicate(true), "label":"IA • A2 RÉACTION", "delayed":true})
        ai_delayed_action2 = {}

    if not free_action_plan.is_empty():
        steps.append({"descriptor":free_action_plan.duplicate(true), "label":"HIRAISHIN GRATUIT", "delayed":false})
        free_action_plan = {}

    if not action1_plan.is_empty():
        steps.append({"descriptor":action1_plan.duplicate(true), "label":"A1 IMMÉDIATE", "delayed":false})

    # Notre A2 est armée pour la prochaine validation adverse.
    delayed_action2 = action2_plan.duplicate(true) if not action2_plan.is_empty() else {}
    if not delayed_action2.is_empty():
        _announce_zetsu_switch_a2("enemy", delayed_action2)
    action1_plan = {}
    action2_plan = {}
    planning_slot = 1
    _discard_planning_virtual_actor()
    _refresh_selection_panel()
    _refresh_plan_ui()
    _refresh_action_buttons()
    _start_resolution_sequence(steps, Callable(self, "_finish_player_validation_cycle"))

func _finish_player_validation_cycle() -> void:
    if duel_finished:
        return
    _end_team_turn("ally")
    _update_team_status()
    _refresh_selection_panel()
    if _replacement_overlay_active():
        resolving_action = false
        return
    current_turn_team = "enemy"
    _start_team_turn("enemy")
    if _replacement_overlay_active():
        resolving_action = false
        return
    ai_thinking = true
    _battle_log_set("L'IA réfléchit à son Action 1 et à sa réaction A2…")
    action_status_label.text = "TOUR IA"
    _refresh_action_buttons()
    var timer: SceneTreeTimer = get_tree().create_timer(0.55)
    timer.timeout.connect(_start_ai_turn)

func _start_ai_turn() -> void:
    if duel_finished:
        return
    current_turn_team = "enemy"
    resolving_action = true
    ai_thinking = true

    # L'IA choisit son plan au moment de sa validation, puis l'A2 du joueur
    # s'intercale avant toutes ses actions, comme dans le moteur PC.
    var ai_a1: Dictionary = _ai_choose_action(true, {})
    var ai_a2: Dictionary = _ai_choose_action(false, ai_a1)
    ai_delayed_action2 = ai_a2.duplicate(true) if not ai_a2.is_empty() else {}
    if not ai_delayed_action2.is_empty():
        _announce_zetsu_switch_a2("ally", ai_delayed_action2)
    var free_desc: Dictionary = _ai_minato_free_descriptor()

    var steps: Array[Dictionary] = []
    if not delayed_action2.is_empty():
        steps.append({"descriptor":delayed_action2.duplicate(true), "label":"A2 RÉACTION", "delayed":true})
        delayed_action2 = {}
    if not free_desc.is_empty():
        steps.append({"descriptor":free_desc.duplicate(true), "label":"IA • HIRAISHIN GRATUIT", "delayed":false})
    if not ai_a1.is_empty():
        steps.append({"descriptor":ai_a1.duplicate(true), "label":"IA • A1 IMMÉDIATE", "delayed":false})

    _start_resolution_sequence(steps, Callable(self, "_finish_ai_turn"))

func _finish_ai_turn() -> void:
    if duel_finished:
        return
    _end_team_turn("enemy")
    _update_team_status()
    _refresh_selection_panel()
    if _replacement_overlay_active():
        # Les remplacements IA sont automatiques ; si un modal allié s'est ouvert
        # suite à une A2, le joueur doit le résoudre avant de reprendre.
        resolving_action = false
        ai_thinking = false
        current_turn_team = "ally"
        return
    turn_counter += 1
    _refresh_turn_labels()
    current_turn_team = "ally"
    _start_team_turn("ally")
    if _replacement_overlay_active():
        resolving_action = false
        ai_thinking = false
        return
    resolving_action = false
    ai_thinking = false
    action_status_label.text = "Préparation : ACTION 1"
    if not ai_delayed_action2.is_empty():
        _battle_log_set("À toi. L'IA a préparé une Action 2 réactive.")
    else:
        _battle_log_set("À toi. L'IA n'a pas préparé d'Action 2 ce cycle.")
    _refresh_plan_ui()
    _refresh_action_buttons()

func _start_team_turn(team_name: String) -> void:
    if team_name == "ally":
        _reset_phase_timer()
    else:
        _stop_phase_timer()
    # P18 — ordre calé sur GameEngine.start_turn() Classic.
    # Important : les effets ne sont plus traités "carte par carte". Le PC
    # exécute chaque FAMILLE d'effets sur tout le terrain avant de passer à la
    # suivante. Cet ordre change réellement les K.O./survies/remplacements.
    _tick_global_jashin()
    var opponents: String = _opponent_team(team_name)

    for sasori_guard: YugitoCardActor in _living_cards(opponents):
        if sasori_guard.card_id == "sasori":
            sasori_guard.status_tags.erase("sasori_counter_used_cycle")

    # Phase 1 PC : toxines Torune -> resets d'entrée de tour -> effets retardés.
    # On garde le corps contrôlé par Ino hors du tour de son propriétaire : ses
    # états sont consommés quand Ino agit avec lui.
    for actor: YugitoCardActor in _living_cards(team_name).duplicate():
        if actor == null or actor.defeated or _ino_possessor(actor) != null:
            continue
        if actor.reactive_entry_guard and int(actor.status_tags.get("reactive_entry_cycle", -999)) < turn_counter:
            actor.reactive_entry_guard = false
            actor.status_tags.erase("yamato_counter_gift")
            actor.refresh_status_badges()
        if actor.card_id == "minato":
            actor.status_tags.erase("minato_free_used_cycle")
            actor.status_tags.erase("minato_free_reserved")
        if actor.card_id == "zetsu":
            actor.status_tags["zetsu_hidden"] = not bool(actor.status_tags.get("zetsu_hidden", false))

        var effect_actor: YugitoCardActor = _effect_actor(actor)
        if effect_actor == null or effect_actor.defeated:
            continue
        var torune_tick: int = int(effect_actor.status_tags.get("torune_contact_poison",0)) + int(effect_actor.status_tags.get("torune_micro_poison",0))
        if torune_tick > 0:
            _deal_fixed_status_damage(effect_actor, torune_tick, "TOXINES TORUNE")
        if effect_actor.defeated:
            continue
        if int(effect_actor.status_tags.get("delayed_damage", 0)) > 0:
            var delayed_amount: int = int(effect_actor.status_tags.get("delayed_damage", 0))
            effect_actor.status_tags.erase("delayed_damage")
            _deal_fixed_status_damage(effect_actor, delayed_amount, "DÉGÂTS RETARDÉS")

    # Phase 2 : poison Anko sur toute l'équipe.
    for actor: YugitoCardActor in _living_cards(team_name).duplicate():
        if actor == null or actor.defeated or _ino_possessor(actor) != null:
            continue
        var effect_actor: YugitoCardActor = _effect_actor(actor)
        if effect_actor != null and not effect_actor.defeated and int(effect_actor.status_tags.get("anko_poison_turns",0)) > 0:
            _deal_fixed_status_damage(effect_actor, 100, "POISON ANKO")

    # Phase 3 : poison Shino.
    for actor: YugitoCardActor in _living_cards(team_name).duplicate():
        if actor == null or actor.defeated or _ino_possessor(actor) != null:
            continue
        var effect_actor: YugitoCardActor = _effect_actor(actor)
        if effect_actor != null and not effect_actor.defeated and bool(effect_actor.status_tags.get("shino_poisoned", false)):
            _deal_fixed_status_damage(effect_actor, 100, "POISON SHINO")

    # Phase 4 : poison personnel de Hanzo.
    for actor: YugitoCardActor in _living_cards(team_name).duplicate():
        if actor == null or actor.defeated or _ino_possessor(actor) != null:
            continue
        var effect_actor: YugitoCardActor = _effect_actor(actor)
        if effect_actor != null and not effect_actor.defeated and bool(effect_actor.status_tags.get("hanzo_poisoned", false)):
            _deal_fixed_status_damage(effect_actor, maxi(1, int(round(float(effect_actor.max_hp) * 0.05))), "POISON SALAMANDRE")

    # Phase 5 PC : Brume de Hanzo AVANT les prisons/poisons suivants.
    for hanzo: YugitoCardActor in _living_cards(team_name).duplicate():
        if hanzo.card_id != "hanzo" or _ino_possessor(hanzo) != null:
            continue
        for ally: YugitoCardActor in _living_cards(team_name).duplicate():
            if ally != hanzo:
                _deal_fixed_status_damage(ally, maxi(1,int(round(float(ally.max_hp)*0.05))), "BRUME HANZO", hanzo)
        for enemy: YugitoCardActor in _living_cards(opponents).duplicate():
            _deal_fixed_status_damage(enemy, maxi(1,int(round(float(enemy.max_hp)*0.10))), "BRUME HANZO", hanzo)

    # Phase 6 : Prison de glace Haku.
    for actor: YugitoCardActor in _living_cards(team_name).duplicate():
        if actor == null or actor.defeated or _ino_possessor(actor) != null:
            continue
        var effect_actor: YugitoCardActor = _effect_actor(actor)
        if effect_actor != null and not effect_actor.defeated and int(effect_actor.status_tags.get("haku_ice_prison_turns",0)) > 0:
            _deal_fixed_status_damage(effect_actor, 200, "PRISON DE GLACE")

    # Phase 7 : poison Shizune.
    for actor: YugitoCardActor in _living_cards(team_name).duplicate():
        if actor == null or actor.defeated or _ino_possessor(actor) != null:
            continue
        var effect_actor: YugitoCardActor = _effect_actor(actor)
        if effect_actor != null and not effect_actor.defeated and bool(effect_actor.status_tags.get("shizune_poisoned", false)):
            _deal_fixed_status_damage(effect_actor, 30, "POISON SHIZUNE")

    # Phase 8 : coût propre de Kimimaro.
    for actor: YugitoCardActor in _living_cards(team_name).duplicate():
        if actor == null or actor.defeated or _ino_possessor(actor) != null:
            continue
        var effect_actor: YugitoCardActor = _effect_actor(actor)
        if effect_actor != null and not effect_actor.defeated and effect_actor.card_id == "kimimaro" and bool(effect_actor.status_tags.get("kimimaro_fury", false)):
            _deal_fixed_status_damage(effect_actor, maxi(1, int(round(float(effect_actor.max_hp) * 0.10))), "FURIE KIMIMARO", null, true, true)

    # Cooldowns/durées du prototype. Cette étape doit précéder le compte à
    # rebours du clone : si le clone explose maintenant, sa recharge de 4T ne
    # doit PAS perdre un cran sur ce même début de tour (ordre PC).
    for actor: YugitoCardActor in _living_cards(team_name).duplicate():
        if actor == null or actor.defeated or _ino_possessor(actor) != null:
            continue
        actor.tick_own_turn()
        if actor.card_id == "ino":
            var controlled: YugitoCardActor = _ino_controlled_body(actor)
            if controlled != null:
                controlled.tick_own_turn()

    # Phase 9 PC : clone Gengetsu APRES poisons et recharge. Un poison peut donc
    # détruire le clone avant son explosion ; dans ce cas aucune AOE n'a lieu.
    for actor: YugitoCardActor in _living_cards(team_name).duplicate():
        if actor == null or actor.defeated or _ino_possessor(actor) != null:
            continue
        if bool(actor.status_tags.get("gengetsu_clone_active",false)):
            var clone_left: int = maxi(0, int(actor.status_tags.get("gengetsu_clone_turns",2)) - 1)
            actor.status_tags["gengetsu_clone_turns"] = clone_left
            if clone_left <= 0:
                _restore_gengetsu_clone(actor, true)
                for clone_enemy: YugitoCardActor in _living_cards(opponents).duplicate():
                    var clone_result: Dictionary = _apply_attack_damage(actor, clone_enemy, 1300, "status", true, false, false, false, false, false, false)
                    _after_damage_resolution(actor,clone_enemy,clone_result)

    # Phase 10 PC : passifs de début de tour Tsunade / Kisame / Karin.
    for actor: YugitoCardActor in _living_cards(team_name).duplicate():
        if actor == null or actor.defeated or _ino_possessor(actor) != null:
            continue
        if actor.card_id == "tsunade" and actor.hp * 2 < actor.max_hp:
            actor.heal(200)
        elif actor.card_id == "kisame":
            var has_prisoner: bool = false
            for target: YugitoCardActor in _living_cards(opponents):
                if int(target.status_tags.get("kisame_prisoned_by_uid",0)) == actor.battle_uid:
                    has_prisoner = true
                    break
            if has_prisoner:
                actor.stat_buffs["ninjutsu"] = int(actor.stat_buffs.get("ninjutsu",0)) - 100
        elif actor.card_id == "karin":
            var kt: int = int(actor.status_tags.get("karin_turn_counter",0)) + 1
            actor.status_tags["karin_turn_counter"] = kt
            if kt % 2 == 0:
                actor.heal(600)

    # Phase 11 PC : Hashirama après les autres passifs de début de tour.
    for hashirama: YugitoCardActor in _living_cards(team_name).duplicate():
        if hashirama.card_id == "hashirama" and _ino_possessor(hashirama) == null:
            for enemy: YugitoCardActor in _living_cards(opponents).duplicate():
                _deal_fixed_status_damage(enemy, 100, "CROISSANCE LUXURIANTE", hashirama)

    # Extension Classic 1.7.7 : Tobi est traité APRÈS GameEngine.start_turn().
    # Ainsi un Tobi tué par un DOT/passif de début de tour ne pose pas de bombe.
    for tobi: YugitoCardActor in _living_cards(team_name).duplicate():
        if tobi.card_id != "tobi" or _ino_possessor(tobi) != null:
            continue
        # Tobi ne devient jamais intangible via son passif de bombes.
        tobi.status_tags.erase("tobi_intangible")
        var bomb_targets: Array[YugitoCardActor] = _living_cards(opponents)
        if bomb_targets.is_empty():
            continue
        if team_name == "ally":
            tobi_bomb_pending_team = "ally"
            var tobi_candidates: Array[String] = []
            for bomb_candidate: YugitoCardActor in bomb_targets:
                tobi_candidates.append(bomb_candidate.card_id)
            replacement_context = {"mode":"tobi_bomb", "team":"ally", "candidates":tobi_candidates}
            replacement_modal.show_choices("TOBI — BOMBE SECRÈTE", "Choisis le Ninja ennemi qui recevra +1 bombe. L'adversaire ne verra jamais cette cible.", tobi_candidates)
            _battle_log_set("TOBI : choisis secrètement le Ninja ennemi qui recevra la bombe.")
        else:
            var bomb_target: YugitoCardActor = bomb_targets[0]
            var bomb_score: float = -INF
            for candidate_bomb: YugitoCardActor in bomb_targets:
                var bscore: float = float(maxi(candidate_bomb.effective_stat("taijutsu"), maxi(candidate_bomb.effective_stat("ninjutsu"),candidate_bomb.effective_stat("genjutsu")))) + float(candidate_bomb.stars) * 100.0
                if bscore > bomb_score:
                    bomb_score = bscore
                    bomb_target = candidate_bomb
            _place_tobi_bomb("enemy", bomb_target)

    _refresh_all_status_badges()

func _end_team_turn(team_name: String) -> void:
    # Jiraiya gagne +10 aux trois arts à CHAQUE tour complet passé vivant sur le terrain,
    # qu'il s'agisse de son tour ou du tour adverse.
    for actor: YugitoCardActor in card_actors:
        if actor != null and is_instance_valid(actor) and not actor.defeated and actor.card_id == "jiraiya":
            actor.stat_buffs["taijutsu"] = int(actor.stat_buffs.get("taijutsu", 0)) + 10
            actor.stat_buffs["ninjutsu"] = int(actor.stat_buffs.get("ninjutsu", 0)) + 10
            actor.stat_buffs["genjutsu"] = int(actor.stat_buffs.get("genjutsu", 0)) + 10
            actor.status_tags["jiraiya_turns_completed"] = int(actor.status_tags.get("jiraiya_turns_completed",0)) + 1
        if actor != null and is_instance_valid(actor) and not actor.defeated and actor.card_id == "chojuro":
            actor.status_tags["chojuro_chakra_stock"] = int(actor.status_tags.get("chojuro_chakra_stock",0)) + 50

    # Nuage d'Asuma : dure exactement deux fins de tours d'Asuma puis explose.
    for asuma_actor: YugitoCardActor in _living_cards(team_name).duplicate():
        if asuma_actor.card_id == "asuma" and int(asuma_actor.status_tags.get("asuma_smoke_turns",0)) > 0:
            var smoke_left: int = maxi(0,int(asuma_actor.status_tags.get("asuma_smoke_turns",0))-1)
            asuma_actor.status_tags["asuma_smoke_turns"] = smoke_left
            if smoke_left <= 0 and not asuma_actor.defeated:
                asuma_actor.status_tags.erase("asuma_smoke_turns")
                var smoke_damage: int = maxi(1,int(round(float(asuma_actor.hp)*0.20)))
                for smoke_enemy: YugitoCardActor in _living_cards(_opponent_team(team_name)).duplicate():
                    var smoke_res: Dictionary = _apply_attack_damage(asuma_actor,smoke_enemy,smoke_damage,"special",true,false,false,false,false,false,false)
                    _after_damage_resolution(asuma_actor,smoke_enemy,smoke_res)

    # Sharingan Sasuke : les 3 tours appartiennent à la CARTE SOURCE qui a
    # déclenché le verrou, pas à Sasuke. Le tour de création ne décrémente pas.
    _tick_sasuke_locks_for_source_team(team_name)

    # Inciblabilités : alternance à la fin d'un tour ADVERSE du propriétaire.
    var other_team: String = _opponent_team(team_name)
    for actor: YugitoCardActor in _living_cards(other_team):
        match actor.card_id:
            "obito": actor.status_tags["obito_intangible"] = not bool(actor.status_tags.get("obito_intangible", true))
            "zabuza": actor.status_tags["zabuza_untargetable"] = not bool(actor.status_tags.get("zabuza_untargetable", true))
            "gengetsu":
                if not bool(actor.status_tags.get("gengetsu_clone_active",false)):
                    actor.status_tags["gengetsu_untargetable"] = not bool(actor.status_tags.get("gengetsu_untargetable", true))
            "konan": actor.status_tags["konan_untargetable"] = not bool(actor.status_tags.get("konan_untargetable", true))

    # Réinitialisation des protections "une fois par cycle adverse".
    for actor: YugitoCardActor in _living_cards(team_name):
        actor.status_tags.erase("gaara_guard_used_cycle")
        actor.status_tags.erase("sasuke_guard_used_cycle")
        actor.status_tags.erase("kurenai_guard_used_cycle")

    # Si le tour adverse se termine sans réaliser exactement la paire prédite par Tobi,
    # la prédiction échoue et la pile de bombes du Ninja prédit disparaît.
    var prediction_owner: String = _opponent_team(team_name)
    if not (tobi_predictions.get(prediction_owner,{}) as Dictionary).is_empty():
        _clear_failed_tobi_prediction(prediction_owner)
    _tick_ino_possessions_at_end(team_name)
    _refresh_all_status_badges()

func _deal_fixed_status_damage(target: YugitoCardActor, amount: int, label: String, source: YugitoCardActor = null, ignore_shield: bool = false, self_cost: bool = false) -> void:
    if target == null or target.defeated or amount <= 0:
        return
    var visual_target: YugitoCardActor = target
    var body: YugitoCardActor = _effect_actor(target)
    if body == null or body.defeated:
        return
    # Les dégâts fixes/DOT du PC passent par le même cœur que le reste :
    # réductions de technique, Kimimaro, boucliers et survivances s'appliquent,
    # mais jamais de surplus joueur. Makibishi peut ignorer le bouclier ; le
    # coût propre de Kimimaro ignore aussi ses protections sans ignorer Chiyo/Kabuto.
    var result: Dictionary = _apply_attack_damage(source, body, amount, "status", false, false, false, false, false, false, false, ignore_shield, self_cost)
    _battle_log_set("%s : %s perd %d PV." % [label, visual_target.display_name, int(result.get("hp_damage", 0))])
    _after_damage_resolution(source, body, result)

func _tick_global_jashin() -> void:
    for actor: YugitoCardActor in card_actors.duplicate():
        if actor == null or not is_instance_valid(actor) or actor.defeated:
            continue
        var doom: int = int(actor.status_tags.get("doom_turns",0))
        if doom <= 0:
            continue
        doom -= 1
        actor.status_tags["doom_turns"] = doom
        if doom <= 0:
            var source_team: String = str(actor.status_tags.get("doom_source_team",""))
            var source_uid: int = int(actor.status_tags.get("doom_source_uid", 0))
            var source_actor: YugitoCardActor = _resolve_actor_uid(source_uid)
            var source_alive: bool = source_actor != null and not source_actor.defeated and source_actor.team_name == source_team and source_actor.card_id == "hidan"
            if source_alive:
                var before: int = actor.hp
                actor.set_hp(0)
                _after_damage_resolution(actor, actor, {"hp_damage":before,"overflow":0,"killed":true,"immune":false})
            else:
                actor.status_tags.erase("doom_turns")
                actor.status_tags.erase("doom_source_team")
                actor.status_tags.erase("doom_source_uid")

func _refresh_all_status_badges() -> void:
    for actor: YugitoCardActor in card_actors:
        if actor != null and is_instance_valid(actor):
            actor.refresh_status_badges()

func _ai_minato_free_descriptor() -> Dictionary:
    for actor: YugitoCardActor in _living_cards("enemy"):
        if actor.card_id == "minato" and _actor_can_act(actor):
            return _ai_best_normal_for_actor(actor)
    return {}

func _ai_choose_action(primary: bool, previous: Dictionary) -> Dictionary:
    # 1) Sauver une carte très faible si la réserve propose mieux.
    if primary:
        var switch_desc: Dictionary = _ai_survival_switch()
        if not switch_desc.is_empty():
            return switch_desc

    var best: Dictionary = {}
    var best_score: float = -INF
    var previous_special_uid: int = 0
    var excluded_uid: int = 0
    if not previous.is_empty():
        if str(previous.get("action_id", "")) == "special":
            previous_special_uid = int(previous.get("source_uid", 0))
        if str(previous.get("kind", "attack")) == "switch":
            excluded_uid = int(previous.get("source_uid", 0))

    for actor: YugitoCardActor in _living_cards("enemy"):
        if actor.battle_uid == excluded_uid or not _actor_can_act(actor):
            continue

        # Attaques normales : évalue chaque art contre chaque cible avec la
        # véritable formule Classic déjà migrée.
        var normal: Dictionary = _ai_best_normal_for_actor(actor)
        if not normal.is_empty():
            var ns: float = float(normal.get("ai_score", 0.0))
            if ns > best_score:
                best_score = ns
                best = normal

        # Spéciales : ne pas prévoir deux fois la même spéciale du même Ninja.
        if actor.battle_uid != previous_special_uid and _actor_special_available(actor):
            var special: Dictionary = _ai_special_descriptor(actor)
            if not special.is_empty():
                var ss: float = float(special.get("ai_score", 0.0))
                if ss > best_score:
                    best_score = ss
                    best = special

    best.erase("ai_score")
    return best

func _ai_best_normal_for_actor(actor: YugitoCardActor) -> Dictionary:
    var best: Dictionary = {}
    var best_score: float = -INF
    var targets: Array[YugitoCardActor] = _living_cards("ally")
    for style: String in ["taijutsu", "ninjutsu", "genjutsu"]:
        if not _actor_can_use_style(actor, style):
            continue
        if targets.is_empty():
            var direct_damage: int = maxi(100, _actor_effective_stat(actor, style) / 2)
            var direct_score: float = float(direct_damage) + (1800.0 if direct_damage >= ally_player_hp else 0.0)
            if direct_score > best_score:
                best_score = direct_score
                best = _make_ai_attack_descriptor(actor, null, style, direct_score)
            continue
        for target: YugitoCardActor in targets:
            if _is_actor_untargetable(target) and actor.card_id != "minato":
                continue
            var calc: Dictionary = _calculate_classic_damage(actor, target, style, 0, false, false)
            var damage: int = _preview_true_attack_damage(actor, target, int(calc.get("damage", 0)))
            var effective_hp: int = target.hp + target.shield
            var threat: int = maxi(target.effective_stat("taijutsu"), maxi(target.effective_stat("ninjutsu"), target.effective_stat("genjutsu")))
            var score: float = float(damage) + float(threat) * 0.08
            if damage >= effective_hp:
                score += 950.0 + float(maxi(0, damage - effective_hp)) * 0.55
            if bool(calc.get("advantage", false)):
                score += 90.0
            if target.card_id in ["minato","hashirama","madara","obito","mifune"]:
                score += 80.0
            if score > best_score:
                best_score = score
                best = _make_ai_attack_descriptor(actor, target, style, score)
    return best

func _make_ai_attack_descriptor(source: YugitoCardActor, target: YugitoCardActor, action_id: String, score: float) -> Dictionary:
    if source == null or not is_instance_valid(source):
        return {}
    return {
        "kind":"attack",
        "action_id":action_id,
        "source_uid":source.battle_uid,
        "source_id":source.card_id,
        "source_team":source.team_name,
        "source_slot":source.seed_index_value(),
        "target_uid":0 if target == null else target.battle_uid,
        "target_id":"" if target == null else target.card_id,
        "target_team":"" if target == null else target.team_name,
        "target_slot": -1 if target == null else target.seed_index_value(),
        "ai_score":score
    }

func _ai_special_descriptor(actor: YugitoCardActor) -> Dictionary:
    var cid: String = actor.card_id
    if _special_requires_no_target(cid):
        var utility: float = 420.0
        if cid == "gaara":
            utility = 500.0 + float(_living_cards("enemy").size()) * 90.0
        elif cid == "kankuro":
            utility = 620.0 if not actor.kankuro_defense_active else 120.0
        elif cid == "jiraiya":
            utility = 680.0
        elif cid == "choji":
            utility = 590.0
        return _make_ai_attack_descriptor(actor, null, "special", utility)

    if _special_targets_ally(cid):
        var allies: Array[YugitoCardActor] = _living_cards("enemy")
        if allies.is_empty():
            return {}
        var target_ally: YugitoCardActor = allies[0]
        for candidate: YugitoCardActor in allies:
            if candidate.hp < target_ally.hp:
                target_ally = candidate
        return _make_ai_attack_descriptor(actor, target_ally, "special", 610.0 + float(target_ally.max_hp - target_ally.hp) * 0.3)

    var targets: Array[YugitoCardActor] = _living_cards("ally")
    if cid not in ["sasuke","minato","obito","kakashi","shikamaru"]:
        var legal_targets: Array[YugitoCardActor] = []
        for candidate_target: YugitoCardActor in targets:
            if not _is_actor_untargetable(candidate_target):
                legal_targets.append(candidate_target)
        targets = legal_targets
    if targets.is_empty():
        return {}
    if cid == "tobi":
        var predicted_enemy: YugitoCardActor = targets[0]
        var predicted_threat: int = -1
        for pred_candidate: YugitoCardActor in targets:
            var pthreat: int = maxi(pred_candidate.effective_stat("taijutsu"),maxi(pred_candidate.effective_stat("ninjutsu"),pred_candidate.effective_stat("genjutsu")))
            if pthreat > predicted_threat:
                predicted_threat = pthreat
                predicted_enemy = pred_candidate
        var own_targets: Array[YugitoCardActor] = _living_cards("enemy")
        if own_targets.is_empty():
            return {}
        var predicted_ally: YugitoCardActor = own_targets[0]
        for own_candidate: YugitoCardActor in own_targets:
            if own_candidate.hp < predicted_ally.hp:
                predicted_ally = own_candidate
        var tobi_desc: Dictionary = _make_ai_attack_descriptor(actor,predicted_enemy,"special",720.0)
        tobi_desc["prediction_ally_uid"] = predicted_ally.battle_uid
        tobi_desc["prediction_ally_id"] = predicted_ally.card_id
        return tobi_desc
    var best_target: YugitoCardActor = null
    var best_score: float = -INF
    var cfg: Dictionary = _special_attack_config(cid)
    for target: YugitoCardActor in targets:
        var score: float = 500.0
        if cid in ["shikamaru","ino","yamato","sai"]:
            var threat: int = maxi(target.effective_stat("taijutsu"), maxi(target.effective_stat("ninjutsu"), target.effective_stat("genjutsu")))
            score += float(threat) * 0.26
            if cid == "shikamaru":
                score += float(maxi(0, targets.size() - 1)) * 180.0
        else:
            var style: String = str(cfg.get("style", actor.special_style if actor.special_style != "" else "ninjutsu"))
            var bonus: int = int(cfg.get("bonus", 250))
            var calc: Dictionary = _calculate_classic_damage(actor, target, style, bonus, bool(cfg.get("absolute", false)), bool(cfg.get("force_advantage", false)))
            var damage: int = _preview_true_attack_damage(actor, target, int(calc.get("damage", 0)))
            score += float(damage)
            if damage >= target.hp + target.shield:
                score += 1000.0
        if score > best_score:
            best_score = score
            best_target = target
    if best_target == null:
        return {}
    return _make_ai_attack_descriptor(actor, best_target, "special", best_score)

func _ai_survival_switch() -> Dictionary:
    if enemy_reserve.is_empty():
        return {}
    var weakest: YugitoCardActor = null
    var ratio: float = 1.0
    for actor: YugitoCardActor in _living_cards("enemy"):
        var r: float = float(actor.hp) / float(maxi(1, actor.max_hp))
        if r < ratio:
            ratio = r
            weakest = actor
    if weakest == null or ratio > 0.27 or not _can_leave_field_voluntarily(weakest):
        return {}
    var incoming_id: String = ""
    var incoming_score: float = -INF
    var forced_enemy: String = str(forced_reserve_choice.get("enemy",""))
    var reserve_pool: Array[String] = [forced_enemy] if (not forced_enemy.is_empty() and enemy_reserve.has(forced_enemy)) else enemy_reserve.duplicate()
    for cid: String in reserve_pool:
        var d: Dictionary = cards_by_id.get(cid, {}) as Dictionary
        var score: float = float(int(d.get("hp",0))) * 0.45 + float(maxi(int(d.get("taijutsu",0)), maxi(int(d.get("ninjutsu",0)), int(d.get("genjutsu",0)))))
        score += float(d.get("stars",0.0)) * 50.0
        var future_ids: Array[String] = []
        for ally in _living_cards("enemy"):
            if ally != weakest:
                future_ids.append(ally.card_id)
        future_ids.append(cid)
        score += SynergyDB.bonus_for(cid, future_ids) * 1250.0
        if score > incoming_score:
            incoming_score = score
            incoming_id = cid
    if incoming_id == "":
        return {}
    return {
        "kind":"switch",
        "source_uid":weakest.battle_uid,
        "source_id":weakest.card_id,
        "source_team":weakest.team_name,
        "source_slot":weakest.seed_index_value(),
        "outgoing_id":weakest.card_id,
        "outgoing_name":weakest.display_name,
        "incoming_id":incoming_id,
        "incoming_name":str((cards_by_id.get(incoming_id,{}) as Dictionary).get("name",incoming_id)),
        "ai_score":incoming_score
    }

func _start_resolution_sequence(steps: Array[Dictionary], done_callback: Callable) -> void:
    resolution_queue = []
    for step: Dictionary in steps:
        resolution_queue.append(step.duplicate(true))
    resolution_done_callback = done_callback
    resolution_step_running = false
    resolution_waiting_replacement = false
    resolving_delayed_action = false
    _run_next_resolution_step()

func _run_next_resolution_step() -> void:
    if duel_finished:
        resolution_queue.clear()
        resolution_step_running = false
        return
    if resolution_waiting_replacement or _replacement_overlay_active():
        return
    if resolution_queue.is_empty():
        resolution_step_running = false
        var cb: Callable = resolution_done_callback
        resolution_done_callback = Callable()
        if cb.is_valid():
            cb.call()
        return
    resolution_step_running = true
    var step: Dictionary = resolution_queue.pop_front()
    var descriptor: Dictionary = step.get("descriptor", {}) as Dictionary
    var label: String = str(step.get("label", "ACTION"))
    resolving_delayed_action = bool(step.get("delayed", false))
    _launch_descriptor(descriptor.duplicate(true), label)

func _complete_resolution_step(delay: float = 0.08) -> void:
    resolution_step_running = false
    resolving_delayed_action = false
    if resolution_waiting_replacement or _replacement_overlay_active():
        return
    var timer: SceneTreeTimer = get_tree().create_timer(maxf(0.01, delay))
    timer.timeout.connect(_run_next_resolution_step)

func _resume_resolution_after_replacement() -> void:
    # Un même impact/AOE peut avoir créé plusieurs K.O. : le prochain
    # remplacement doit être résolu avant de reprendre l'ordonnanceur.
    if not pending_death_replacement_uids.is_empty():
        resolution_waiting_replacement = true
        _schedule_death_replacement_dispatch(0.02)
        return
    resolution_waiting_replacement = false
    if not resolution_step_running:
        _run_next_resolution_step()

func _schedule_descriptor(descriptor: Dictionary, delay: float, label: String) -> void:
    # Important : seuls des IDs/slots stables sont conservés dans les timers.
    # Aucun Node/CardActor n'est bindé : un K.O. ou un remplacement ne peut donc
    # plus laisser un objet Godot libéré dans une A1/A2 différée.
    var safe_descriptor: Dictionary = descriptor.duplicate(true)
    var timer: SceneTreeTimer = get_tree().create_timer(delay)
    timer.timeout.connect(_launch_descriptor.bind(safe_descriptor, label))

func _descriptor_visual_target(descriptor: Dictionary, source: YugitoCardActor, requested: YugitoCardActor) -> YugitoCardActor:
    # P20 : l'animation doit viser EXACTEMENT la même carte que le calcul.
    # Avant ce correctif, le trait partait vers la cible choisie puis Choji
    # interceptait seulement au moment du calcul des dégâts.
    if requested == null or source == null:
        return requested
    var action_id: String = str(descriptor.get("action_id", ""))
    if action_id != "special":
        return _guard_target(requested, source)
    var sid: String = _descriptor_special_id(descriptor, source)
    # Techniques explicitement non interceptables dans le moteur Classic.
    if sid in ["mifune", "sasuke"]:
        return requested
    # Spéciales avec branche dédiée qui passent par Expansion Akimichi.
    if sid in ["a3_raikage", "chojuro", "jugo", "omoi", "karui", "mei"]:
        return _guard_target(requested, source)
    # Toutes les spéciales d'attaque standard utilisent la garde sauf si leur
    # configuration Classic dit explicitement l'inverse.
    var cfg: Dictionary = _special_attack_config(sid)
    if not cfg.is_empty() and not bool(cfg.get("ignore_guard", false)):
        return _guard_target(requested, source)
    return requested

func _launch_descriptor(descriptor: Dictionary, phase_label: String) -> void:
    var kind: String = str(descriptor.get("kind", "attack"))
    if kind == "switch":
        _execute_planned_switch(descriptor, phase_label)
        return

    var source: YugitoCardActor = _resolve_descriptor_source(descriptor)
    if source == null or source.defeated:
        _battle_log_set("%s perdue : le Ninja qui devait agir n'est plus sur le terrain." % phase_label)
        _complete_resolution_step()
        return
    if not _actor_can_act(source):
        _battle_log_set("%s perdue : %s est inutilisable." % [phase_label, source.display_name])
        _complete_resolution_step()
        return

    var action_id: String = str(descriptor.get("action_id", ""))
    var target: YugitoCardActor = _resolve_descriptor_target(descriptor, source.team_name)
    var accent: Color = _action_color(action_id)

    if action_id == "special" and _special_requires_no_target(source.card_id):
        source.play_cast_fx(accent)
        _play_special_sound(source.card_id)
        var special_timer: SceneTreeTimer = get_tree().create_timer(0.30)
        special_timer.timeout.connect(_finish_descriptor_safe.bind(descriptor.duplicate(true), phase_label))
        return

    if target == null:
        if action_id in ["taijutsu", "ninjutsu", "genjutsu"] and _living_cards(_opponent_team(source.team_name)).is_empty():
            source.play_cast_fx(accent)
            _play_action_sound(action_id)
            var direct_timer: SceneTreeTimer = get_tree().create_timer(0.38)
            direct_timer.timeout.connect(_finish_descriptor_safe.bind(descriptor.duplicate(true), phase_label))
            return
        _battle_log_set("%s perdue : la cible n'est plus sur le terrain." % phase_label)
        _complete_resolution_step()
        return

    var duration: float = _action_duration(action_id)
    var visual_target: YugitoCardActor = _descriptor_visual_target(descriptor, source, target)
    source.play_cast_fx(accent)
    if action_id == "special":
        _play_special_sound(source.card_id)
    else:
        _play_action_sound(action_id)

    # Possession des ombres : la carte cliquée est justement celle qui reste
    # LIBRE. Le vieux projectile vers cette cible racontait donc l'inverse de
    # la règle. On affiche un éventail d'ombres vers les cartes réellement liées.
    if action_id == "special" and source.card_id == "shikamaru":
        _spawn_shikamaru_cast_fx(source, target, duration)
    else:
        if visual_target != null and visual_target != target:
            _spawn_interception_fx(target, visual_target)
        _spawn_projectile_fx(source.global_position, visual_target.global_position if visual_target != null else target.global_position, accent, action_id, duration)
        var visual_uid: int = visual_target.battle_uid if visual_target != null else target.battle_uid
        var visual_impact_timer: SceneTreeTimer = get_tree().create_timer(maxf(0.08, duration * 0.94))
        visual_impact_timer.timeout.connect(_spawn_descriptor_impact.bind(visual_uid, accent, action_id))
    var impact_timer: SceneTreeTimer = get_tree().create_timer(duration)
    impact_timer.timeout.connect(_finish_descriptor_safe.bind(descriptor.duplicate(true), phase_label))

func _resolve_actor_uid(uid: int) -> YugitoCardActor:
    if uid <= 0:
        return null
    for actor: YugitoCardActor in card_actors:
        if actor != null and is_instance_valid(actor) and actor.battle_uid == uid:
            return actor
    return null

# ------------------------------------------------------------------
# P16 — Transfert d'Ino : lien vivant vers la vraie instance contrôlée
# ------------------------------------------------------------------
func _ino_controlled_body(ino: YugitoCardActor) -> YugitoCardActor:
    if ino == null or not is_instance_valid(ino) or ino.defeated or ino.card_id != "ino":
        return null
    var uid: int = int(ino.status_tags.get("ino_target_uid", 0))
    var body: YugitoCardActor = _resolve_actor_uid(uid)
    if body == null or body.defeated:
        return null
    if int(body.status_tags.get("possessed_by_uid", 0)) != ino.battle_uid:
        return null
    return body

func _ino_possessor(body: YugitoCardActor) -> YugitoCardActor:
    if body == null or not is_instance_valid(body) or body.defeated:
        return null
    var uid: int = int(body.status_tags.get("possessed_by_uid", 0))
    var ino: YugitoCardActor = _resolve_actor_uid(uid)
    if ino == null or ino.defeated or ino.card_id != "ino":
        return null
    if int(ino.status_tags.get("ino_target_uid", 0)) != body.battle_uid:
        return null
    return ino

func _effect_actor(actor: YugitoCardActor) -> YugitoCardActor:
    if actor != null and actor.card_id == "ino":
        var body: YugitoCardActor = _ino_controlled_body(actor)
        if body != null:
            return body
    return actor

func _is_actor_untargetable(actor: YugitoCardActor) -> bool:
    if actor == null or not is_instance_valid(actor) or actor.defeated:
        return true
    # P33 : pendant le Transfert, seul le corps d'origine d'Ino est
    # inciblable. Le Ninja adverse possédé reste une cible normale : il peut
    # être frappé et tous les dégâts/états restent sur sa vraie instance.
    if actor.card_id == "ino" and _ino_controlled_body(actor) != null:
        return true
    if _ino_possessor(actor) != null:
        return false
    return actor.is_untargetable()

func _actor_can_act(actor: YugitoCardActor) -> bool:
    if actor == null or not is_instance_valid(actor) or actor.defeated:
        return false
    # P48 MOBILE UX/RULE LOCK : le Clone explosif est un état passif de Gengetsu,
    # jamais une source d'action. Il ne peut préparer ni AF, ni A1, ni A2.
    if actor.card_id == "gengetsu" and bool(actor.status_tags.get("gengetsu_clone_active", false)):
        return false
    if _ino_possessor(actor) != null:
        return false
    if actor.card_id == "ino":
        var body: YugitoCardActor = _ino_controlled_body(actor)
        if body != null:
            if body.disabled_turns > 0:
                return false
            if int(body.status_tags.get("shadow_turns", 0)) > 0:
                return false
            if int(body.status_tags.get("kisame_prisoned_by_uid", 0)) > 0:
                return false
            return true
    return actor.can_act()

func _actor_can_use_style(actor: YugitoCardActor, style: String) -> bool:
    if not _actor_can_act(actor) or style not in ["taijutsu", "ninjutsu", "genjutsu"]:
        return false
    var body: YugitoCardActor = _effect_actor(actor)
    if body == null:
        return false
    if int(body.status_tags.get("blocked_%s_turns" % style, 0)) > 0:
        return false
    return body.effective_stat(style) > 0

func _actor_special_available(actor: YugitoCardActor) -> bool:
    if actor == null or not is_instance_valid(actor):
        return false
    # Ino ne vole jamais la spéciale du corps contrôlé et ne peut pas relancer
    # Transfert tant qu'une possession est active.
    if actor.card_id == "ino" and _ino_controlled_body(actor) != null:
        return false
    return actor.special_available()

func _actor_copied_special_available(actor: YugitoCardActor) -> bool:
    if actor == null or not is_instance_valid(actor) or actor.defeated or actor.card_id != "kakashi":
        return false
    if not _actor_can_act(actor):
        return false
    if int(actor.status_tags.get("sealed_turns", 0)) > 0:
        return false
    if int(actor.status_tags.get("special_block_turns", 0)) > 0:
        return false
    var copied_id: String = str(actor.status_tags.get("copied_special_id", ""))
    return not copied_id.is_empty() and not bool(actor.status_tags.get("copied_special_used", false))

func _descriptor_special_id(descriptor: Dictionary, source: YugitoCardActor) -> String:
    if bool(descriptor.get("copied", false)):
        var copied_id: String = str(descriptor.get("copied_special_id", ""))
        if not copied_id.is_empty():
            return copied_id
    return source.card_id if source != null else str(descriptor.get("source_id", ""))

func _special_data_for_id(card_id: String) -> Dictionary:
    return cards_by_id.get(card_id, {}) as Dictionary

func _consume_selected_special(source: YugitoCardActor, copied: bool) -> void:
    if source == null or not is_instance_valid(source):
        return
    if copied:
        source.status_tags["copied_special_used"] = true
        source.refresh_status_badges()
    else:
        source.consume_special()

func _arm_sasuke_lock(defender: YugitoCardActor, attacker: YugitoCardActor, style: String) -> void:
    if defender == null or attacker == null or defender.card_id != "sasuke" or style not in ["taijutsu","ninjutsu","genjutsu"]:
        return
    var key: String = "sasuke_lock_%s_%s" % [attacker.card_id, style]
    if int(defender.status_tags.get(key, 0)) > 0:
        return
    defender.status_tags[key] = 3
    defender.status_tags["%s_created_cycle" % key] = turn_counter
    defender.refresh_status_badges()

func _tick_sasuke_locks_for_source_team(source_team: String) -> void:
    # Classic : le verrou dure trois tours COMPLETS de la carte qui l'a créé,
    # pas trois tours de Sasuke. Les decks étant uniques, l'ID source identifie
    # sans ambiguïté le Ninja opposé.
    for sasuke: YugitoCardActor in _living_cards(_opponent_team(source_team)):
        if sasuke.card_id != "sasuke":
            continue
        for raw_key: Variant in sasuke.status_tags.keys().duplicate():
            var key: String = str(raw_key)
            if not key.begins_with("sasuke_lock_") or key.ends_with("_created_cycle"):
                continue
            var parts: PackedStringArray = key.trim_prefix("sasuke_lock_").split("_")
            if parts.size() < 2:
                continue
            # Les IDs des cartes peuvent contenir des underscores : le style est
            # toujours le dernier segment et l'ID est tout ce qui précède.
            var style: String = str(parts[parts.size()-1])
            var source_id: String = key.trim_prefix("sasuke_lock_").trim_suffix("_%s" % style)
            var source_live: YugitoCardActor = _find_live_card(source_team, source_id)
            if source_live == null:
                sasuke.status_tags.erase(key)
                sasuke.status_tags.erase("%s_created_cycle" % key)
                continue
            var created: int = int(sasuke.status_tags.get("%s_created_cycle" % key, -999))
            if created == turn_counter:
                continue
            var left: int = maxi(0, int(sasuke.status_tags.get(key, 0)) - 1)
            if left <= 0:
                sasuke.status_tags.erase(key)
                sasuke.status_tags.erase("%s_created_cycle" % key)
            else:
                sasuke.status_tags[key] = left
        sasuke.refresh_status_badges()

func _strip_chidori_defenses(target: YugitoCardActor) -> void:
    if target == null or not is_instance_valid(target):
        return
    target.shield = 0
    # Classic 1.8.21 : Chidori détruit le bouclier visible mais le bouclier
    # caché de Kurenai est seulement IGNORÉ par l'impact absolu ; il reste
    # attaché au corps si celui-ci survit pour une autre raison.
    if target.card_id == "obito":
        target.status_tags["obito_intangible"] = false
    elif target.card_id == "zabuza":
        target.status_tags["zabuza_untargetable"] = false
    elif target.card_id == "gengetsu" and not bool(target.status_tags.get("gengetsu_clone_active", false)):
        target.status_tags["gengetsu_untargetable"] = false
    elif target.card_id == "kankuro":
        target.kankuro_defense_active = false
    target._refresh_hp_label()
    target.refresh_status_badges()

func _actor_effective_stat(actor: YugitoCardActor, style: String, defender_stars: float = -1.0) -> int:
    var body: YugitoCardActor = _effect_actor(actor)
    if body == null:
        return 0
    return body.effective_stat(style, defender_stars)

func _end_ino_possession(ino: YugitoCardActor, reason: String = "") -> void:
    if ino == null or not is_instance_valid(ino):
        return
    var body: YugitoCardActor = _ino_controlled_body(ino)
    if body != null:
        body.status_tags.erase("possessed_by_uid")
        body.status_tags.erase("possessed_by_id")
        body.refresh_status_badges()
    ino.status_tags.erase("ino_target_uid")
    ino.status_tags.erase("ino_target")
    ino.status_tags.erase("ino_target_name")
    ino.status_tags.erase("ino_visual_stars")
    ino.status_tags.erase("ino_visual_element")
    ino.status_tags.erase("ino_visual_tai")
    ino.status_tags.erase("ino_visual_nin")
    ino.status_tags.erase("ino_visual_gen")
    ino.status_tags.erase("ino_turns")
    ino.status_tags.erase("ino_started_cycle")
    ino.status_tags.erase("ino_skip_tick")
    ino.status_tags.erase("possession_stats")
    ino.status_tags.erase("possession_element")
    ino.refresh_status_badges()
    if not reason.is_empty() and battle_log_label != null:
        _battle_log_set(reason)

func _tick_ino_possessions_at_end(team_name: String) -> void:
    for ino: YugitoCardActor in _living_cards(team_name).duplicate():
        if ino.card_id != "ino":
            continue
        var body: YugitoCardActor = _ino_controlled_body(ino)
        if body == null:
            if ino.status_tags.has("ino_target_uid"):
                _end_ino_possession(ino, "Transfert terminé : le corps contrôlé n'est plus disponible.")
            continue
        var started: int = int(ino.status_tags.get("ino_started_cycle", -999))
        if started == turn_counter:
            continue
        var left: int = maxi(0, int(ino.status_tags.get("ino_turns", 0)) - 1)
        if left <= 0:
            _end_ino_possession(ino, "Transfert de l'esprit terminé : %s retrouve le contrôle de son corps." % body.display_name)
        else:
            ino.status_tags["ino_turns"] = left
            ino.refresh_status_badges()

func _resolve_descriptor_source(descriptor: Dictionary) -> YugitoCardActor:
    # Le PC résout une action différée par identité de carte, pas par adresse
    # d'objet. L'UID reste prioritaire, puis l'ID unique du Ninja permet de
    # retrouver une instance revenue sur le terrain (ou l'entrant d'un Switch A1).
    var by_uid: YugitoCardActor = _resolve_actor_uid(int(descriptor.get("source_uid", 0)))
    if by_uid != null and not by_uid.defeated:
        return by_uid
    var source_id: String = str(descriptor.get("source_id", ""))
    var source_team: String = str(descriptor.get("source_team", ""))
    if source_id.is_empty():
        return null
    for actor: YugitoCardActor in card_actors:
        if actor == null or not is_instance_valid(actor) or actor.defeated:
            continue
        if actor.card_id == source_id and (source_team.is_empty() or actor.team_name == source_team):
            return actor
    return null

func _resolve_descriptor_target(descriptor: Dictionary, source_team: String) -> YugitoCardActor:
    var desired_team: String = _opponent_team(source_team)
    if str(descriptor.get("action_id", "")) == "special":
        var sid: String = str(descriptor.get("copied_special_id", "")) if bool(descriptor.get("copied", false)) else str(descriptor.get("source_id", ""))
        if _special_targets_ally(sid):
            desired_team = source_team

    var original: YugitoCardActor = _resolve_actor_uid(int(descriptor.get("target_uid", 0)))
    if original != null and not original.defeated and original.team_name == desired_team:
        return original

    # Même règle que GameEngine._action_target_slot() : si la carte visée existe
    # encore quelque part sur le terrain, son identité prime sur la case.
    var target_id: String = str(descriptor.get("target_id", ""))
    if not target_id.is_empty():
        for actor: YugitoCardActor in card_actors:
            if actor != null and is_instance_valid(actor) and not actor.defeated and actor.team_name == desired_team and actor.card_id == target_id:
                return actor

    var target_slot: int = int(descriptor.get("target_slot", -1))
    if target_slot < 0:
        return null
    for actor: YugitoCardActor in card_actors:
        if actor == null or not is_instance_valid(actor) or actor.team_name != desired_team or actor.defeated:
            continue
        if actor.seed_index_value() % 3 != target_slot % 3:
            continue
        # Si l'ancienne cible a réellement disparu, l'action ne suit la case
        # qu'après un Switch A2 réactif de cette validation. Un remplacement K.O.
        # ordinaire ne détourne jamais une vieille cible.
        if int(actor.status_tags.get("reactive_entry_cycle", -999)) == turn_counter:
            return actor
    return null

func _finish_descriptor_safe(descriptor: Dictionary, phase_label: String) -> void:
    var source: YugitoCardActor = _resolve_descriptor_source(descriptor)
    if source == null or source.defeated:
        _battle_log_set("%s perdue : le Ninja source a quitté le terrain." % phase_label)
        _complete_resolution_step()
        return
    var action_id: String = str(descriptor.get("action_id", ""))
    var target: YugitoCardActor = _resolve_descriptor_target(descriptor, source.team_name)
    if action_id == "special":
        var sid: String = _descriptor_special_id(descriptor, source)
        if _special_requires_no_target(sid):
            _finish_special_descriptor(source, null, phase_label, descriptor)
        elif target != null:
            _finish_special_descriptor(source, target, phase_label, descriptor)
        else:
            _battle_log_set("%s perdue : cible spéciale indisponible." % phase_label)
        _complete_resolution_step(0.14)
        return
    if target == null:
        if _living_cards(_opponent_team(source.team_name)).is_empty():
            _finish_direct_attack(source, action_id, phase_label)
        else:
            _battle_log_set("%s perdue : cible indisponible." % phase_label)
        _complete_resolution_step(0.12)
        return
    _finish_normal_descriptor(source, target, action_id, phase_label)
    _complete_resolution_step(0.14)

func _finish_normal_descriptor(source: YugitoCardActor, requested_target: YugitoCardActor, action_id: String, phase_label: String) -> void:
    if source == null or not is_instance_valid(source) or requested_target == null or not is_instance_valid(requested_target) or requested_target.defeated:
        return
    _trigger_tobi_prediction(source, requested_target)
    if source.defeated:
        _battle_log_set("%s • %s est K.O. dans l'explosion de Tobi : attaque annulée." % [phase_label,source.display_name])
        return
    var actual_target: YugitoCardActor = _guard_target(requested_target, source)
    if source.card_id == "omoi":
        if battle_rng.randf() < (1.0 / 3.0):
            _battle_log_set("%s • Omoi OUBLIE sa frappe : 0 dégât." % phase_label)
            _mark_attack_usage(source, action_id)
            return
    var calc: Dictionary = _calculate_classic_damage(source, actual_target, action_id, 0, false, false)
    if source.card_id == "omoi":
        calc["damage"] = int(round(float(calc.get("damage",0)) * 1.20))
    actual_target.play_hit_fx(_action_color(action_id))
    _spawn_impact_fx(actual_target.global_position, _action_color(action_id), action_id)
    var result: Dictionary = _apply_attack_damage(source, actual_target, int(calc.get("damage", 0)), action_id, false, false, true, false, false, true)
    var dealt: int = int(result.get("hp_damage", 0))
    var extra: String = " • SUPER EFFICACE" if bool(calc.get("advantage", false)) else ""
    if bool(result.get("immune", false)):
        _battle_log_set("%s • %s → %s : attaque annulée%s" % [phase_label, source.display_name, actual_target.display_name, extra])
    else:
        _battle_log_set("%s • %s → %s : -%d PV%s" % [phase_label, source.display_name, actual_target.display_name, dealt, extra])
    _mark_attack_usage(source, action_id)
    _post_attack_passives(source, actual_target, result, action_id, false, "")
    if source.card_id == "a3_raikage" and int(result.get("hp_damage",0)) + int(result.get("overflow",0)) > 0 and not source.defeated:
        var recoil_a3: int = maxi(1,int(round(float(int(result.get("hp_damage",0)) + int(result.get("overflow",0))) * 0.20)))
        _deal_fixed_status_damage(source,recoil_a3,"CONTRECOUP 3e RAIKAGE")
    if phase_label.contains("HIRAISHIN") and source.card_id == "minato":
        source.status_tags["minato_free_used_cycle"] = true
    _after_damage_resolution(source, actual_target, result)

func _finish_direct_attack(source: YugitoCardActor, action_id: String, phase_label: String) -> void:
    if source == null or not is_instance_valid(source) or source.defeated:
        return
    var damage: int = maxi(100, _actor_effective_stat(source, action_id) / 2)
    if source.team_name == "ally":
        enemy_player_hp = maxi(0, enemy_player_hp - damage)
    else:
        ally_player_hp = maxi(0, ally_player_hp - damage)
    _battle_log_set("%s • %s attaque directement : -%d PV JOUEUR" % [phase_label, source.display_name, damage])
    _mark_attack_usage(source, action_id)
    if source.card_id == "a3_raikage" and damage > 0 and not source.defeated:
        _deal_fixed_status_damage(source,maxi(1,int(round(float(damage)*0.20))),"CONTRECOUP 3e RAIKAGE")
    if phase_label.contains("HIRAISHIN") and source.card_id == "minato":
        source.status_tags["minato_free_used_cycle"] = true
    _update_team_status()
    _check_victory_state()

func _finish_special_descriptor(source: YugitoCardActor, target: YugitoCardActor, phase_label: String, descriptor: Dictionary = {}) -> void:
    if source == null or not is_instance_valid(source) or source.defeated:
        return
    var copied: bool = bool(descriptor.get("copied", false))
    if copied:
        if not _actor_copied_special_available(source):
            _battle_log_set("%s perdue : la copie de %s n'est plus disponible." % [phase_label, source.display_name])
            return
    elif not _actor_special_available(source):
        _battle_log_set("%s perdue : la spéciale de %s n'est plus disponible." % [phase_label, source.display_name])
        return

    var cid: String = _descriptor_special_id(descriptor, source)
    var special_data: Dictionary = _special_data_for_id(cid)
    var special_name_used: String = str(special_data.get("special_name", "Spéciale copiée" if copied else source.special_name))
    var special_style_used: String = str(special_data.get("special_style", source.special_style))
    var enemy_team: String = _opponent_team(source.team_name)

    # P21 — certaines techniques ciblent une carte sans l'attaquer. Pour Shikamaru,
    # la carte cliquée est précisément celle qui reste LIBRE : elle ne peut donc
    # jamais satisfaire une prédiction offensive de Tobi.
    if target != null and target.team_name != source.team_name and cid not in ["tobi", "shikamaru"]:
        _trigger_tobi_prediction(source, target)
        if source.defeated:
            _battle_log_set("%s • %s est K.O. dans l'explosion de Tobi : spéciale annulée." % [phase_label,source.display_name])
            return

    # AO — passif PC : AVANT toute spéciale ennemie, Ao frappe immédiatement
    # l'utilisateur en Taijutsu. Si cette anticipation le met K.O., la spéciale
    # est consommée mais n'a aucun effet.
    if cid != "ao" and _ao_anticipation_cancels(source, phase_label):
        _consume_selected_special(source, copied)
        _battle_log_append("  •  SPÉCIALE ANNULÉE PAR AO")
        return

    if cid == "ao":
        var tracked_id: String = _arm_tracker_from_descriptor(source, descriptor, cid)
        _consume_selected_special(source, copied)
        var tracked_name: String = str((cards_by_id.get(tracked_id,{}) as Dictionary).get("name", tracked_id))
        _battle_log_set("%s • Byakugan dérobé : %s devra être la PROCHAINE entrée ennemie." % [phase_label, tracked_name])
        return

    if cid in ["neji", "hinata"]:
        # Le verrou doit exister AVANT l'impact : si la spéciale met K.O., le
        # remplacement déclenché par CE MÊME impact doit déjà être forcé.
        var byakugan_tracked_id: String = _arm_tracker_from_descriptor(source, descriptor, cid)
        if not byakugan_tracked_id.is_empty():
            var byakugan_name: String = str((cards_by_id.get(byakugan_tracked_id,{}) as Dictionary).get("name", byakugan_tracked_id))
            _battle_log_set("%s • Byakugan traqueur armé : %s sera la prochaine entrée adverse." % [phase_label, byakugan_name])

    if cid == "orochimaru":
        var grave: Array[String] = enemy_graveyard if source.team_name == "ally" else ally_graveyard
        var stolen_id: String = str(descriptor.get("grave_card_id", ""))
        if stolen_id.is_empty() or not grave.has(stolen_id):
            stolen_id = _best_card_id(grave)
        _consume_selected_special(source, copied)
        if stolen_id.is_empty():
            _battle_log_set("%s • Réincarnation interdite : aucun corps à voler." % phase_label)
            return
        grave.erase(stolen_id)
        var own_reserve: Array[String] = ally_reserve if source.team_name == "ally" else enemy_reserve
        own_reserve.append(stolen_id)
        ally_cemetery_count = ally_graveyard.size()
        enemy_cemetery_count = enemy_graveyard.size()
        _refresh_reserve_labels()
        var stolen_name: String = str((cards_by_id.get(stolen_id,{}) as Dictionary).get("name", stolen_id))
        _battle_log_set("%s • Réincarnation interdite : %s est volé au cimetière et rejoint la réserve." % [phase_label, stolen_name])
        return

    if cid == "tobi":
        var ally_uid: int = int(descriptor.get("prediction_ally_uid", 0))
        var ally_pred: YugitoCardActor = _resolve_actor_uid(ally_uid)
        _consume_selected_special(source, copied)
        if target == null or ally_pred == null or target.defeated or ally_pred.defeated:
            _battle_log_set("%s • C'était prévu ! : prédiction invalide." % phase_label)
            return
        tobi_predictions[source.team_name] = {
            "enemy_uid":target.battle_uid, "enemy_id":target.card_id,
            "ally_uid":ally_pred.battle_uid, "ally_id":ally_pred.card_id
        }
        source.status_tags["tobi_prediction_armed"] = true
        source.refresh_status_badges()
        source.refresh_status_visuals()
        if source.team_name == "ally":
            _battle_log_set("%s • TOBI PRÉDIT : %s attaquera %s au prochain tour adverse." % [phase_label,target.display_name,ally_pred.display_name])
        else:
            _battle_log_set("%s • Tobi prépare secrètement une prédiction." % phase_label)
        return

    # Techniques non offensives / de contrôle présentes dans les decks du prototype.
    if cid == "kankuro":
        source.kankuro_defense_active = true
        _consume_selected_special(source, copied)
        _battle_log_set("%s • Défense marionnettiste : les autres alliés subissent 250 dégâts de moins." % phase_label)
        _refresh_selection_panel()
        return
    if cid == "gaara":
        for ally in _living_cards(source.team_name):
            ally.add_shield(600)
        _consume_selected_special(source, copied)
        _battle_log_set("%s • Mur de sable : +600 bouclier à toute l'équipe." % phase_label)
        return
    if cid == "jiraiya":
        source.stat_buffs["taijutsu"] = int(source.stat_buffs.get("taijutsu", 0)) + 100
        source.stat_buffs["ninjutsu"] = int(source.stat_buffs.get("ninjutsu", 0)) + 100
        source.stat_buffs["genjutsu"] = int(source.stat_buffs.get("genjutsu", 0)) + 200
        source.status_tags["sage_mode"] = true
        _consume_selected_special(source, copied)
        _battle_log_set("%s • Mode ermite : +100 TAI / +100 NIN / +200 GEN définitivement." % phase_label)
        _refresh_selection_panel()
        return
    if cid == "choji":
        source.add_timed_modifier("taijutsu", 500, 3, "choji_pill")
        _consume_selected_special(source, copied)
        _battle_log_set("%s • Pilule de combat : +500 Taijutsu pendant 3 tours de Choji." % phase_label)
        return
    if cid == "anko":
        source.status_tags["anko_serpent_armed"] = true
        _consume_selected_special(source, copied)
        source.refresh_status_badges()
        _battle_log_set("%s • Permutation du serpent prête : prochaine attaque esquivée, attaquant empoisonné 100×4." % phase_label)
        return
    if cid == "chiyo":
        source.stat_buffs["taijutsu"] = int(source.stat_buffs.get("taijutsu",0)) + 250
        source.status_tags["chiyo_puppets_active"] = true
        _consume_selected_special(source, copied)
        source.refresh_status_badges()
        _battle_log_set("%s • Dix marionnettes : +250 TAI ; autres alliés subissent -20%% dégâts." % phase_label)
        return
    if cid == "gengetsu":
        source.status_tags["gengetsu_saved_hp"] = source.hp
        source.status_tags["gengetsu_saved_max_hp"] = source.max_hp
        source.status_tags["gengetsu_saved_shield"] = source.shield
        source.status_tags["gengetsu_clone_active"] = true
        source.status_tags["gengetsu_clone_turns"] = 2
        source.status_tags["gengetsu_untargetable"] = false
        source.max_hp = 4800
        source.hp = 4800
        source.shield = 0
        _consume_selected_special(source, copied)
        source._refresh_hp_label()
        source.refresh_status_badges()
        source.refresh_dynamic_identity()
        source.refresh_status_visuals()
        _battle_log_set("%s • Clone aqueux : 4800 PV, 0/0/0, explosion dans 2 tours de Gengetsu." % phase_label)
        return
    if cid == "tobirama":
        var total_tobirama: int = 0
        for enemy_t: YugitoCardActor in _living_cards(enemy_team).duplicate():
            var r_t: Dictionary = _apply_attack_damage(source, enemy_t, 650, "special", true, false, false, true, false, false, false)
            total_tobirama += int(r_t.get("hp_damage",0))
            _after_damage_resolution(source, enemy_t, r_t)
        _consume_selected_special(source, copied)
        _battle_log_set("%s • Parchemins scalaires : %d PV infligés au total." % [phase_label,total_tobirama])
        return
    if cid == "shisui":
        var affected_shisui: int = 0
        for enemy_s: YugitoCardActor in _living_cards(enemy_team):
            if enemy_s.card_id in ["killer_bee","madara"]:
                continue
            enemy_s.apply_disable(2, "shisui_genjutsu")
            affected_shisui += 1
        _consume_selected_special(source, copied)
        _battle_log_set("%s • Genjutsu Shisui : %d ennemi(s) STUN 2 tours." % [phase_label,affected_shisui])
        return
    if cid == "konohamaru":
        _set_special_status(source, "konohamaru_sexy_turns", 2)
        _consume_selected_special(source, copied)
        _battle_log_set("%s • Sexy Jutsu : hommes incapables de toucher, femmes x2 dégâts pendant 2 tours." % phase_label)
        return
    if cid == "kimimaro":
        source.status_tags["kimimaro_fury"] = true
        _consume_selected_special(source, copied)
        source.refresh_status_badges()
        _battle_log_set("%s • Vieux os : Furie permanente +15%% arts, -10%% PV max par tour." % phase_label)
        return
    if cid == "konan":
        source.status_tags["konan_mine_active"] = true
        _consume_selected_special(source, copied)
        source.refresh_status_badges()
        _battle_log_set("%s • Carte explosive : terrain miné pendant les phases ciblables de Konan." % phase_label)
        return
    if cid == "kurotsuchi":
        for ally_k: YugitoCardActor in _living_cards(source.team_name):
            ally_k.add_shield(350)
        _consume_selected_special(source, copied)
        _battle_log_set("%s • Muraille Doton : +350 bouclier à toute l'équipe." % phase_label)
        return
    if cid == "tenten":
        makibishi_active[enemy_team] = true
        _consume_selected_special(source, copied)
        _battle_log_set("%s • Makibishi : chaque nouvelle entrée adverse perdra 7%% de ses PV max." % phase_label)
        return

    if target == null or not is_instance_valid(target) or target.defeated:
        _battle_log_set("%s perdue : cible indisponible." % phase_label)
        return

    var ally_special: bool = _special_targets_ally(cid)
    if not ally_special and _is_actor_untargetable(target) and cid not in ["sasuke","minato","obito","kakashi","shikamaru"]:
        _consume_selected_special(source, copied)
        _battle_log_set("%s • %s est INCIBLABLE : %s échoue et est consommée." % [phase_label,target.display_name,special_name_used])
        return
    if not ally_special and target.card_id == "madara" and special_style_used == "genjutsu" and cid != "mifune":
        _consume_selected_special(source, copied)
        _battle_log_set("%s • Mangekyô éternel : Madara ignore %s." % [phase_label,special_name_used])
        return

    # Illusion protectrice de Kurenai : exactement comme le PC, elle annule
    # la prochaine SPÉCIALE ENNEMIE QUI CIBLE explicitement ce corps. Les AOE,
    # splashs et DOT qui le touchent sans le cibler ne consomment pas la protection.
    if not ally_special:
        var protected_body: YugitoCardActor = _effect_actor(target)
        if protected_body != null and bool(protected_body.status_tags.get("special_protection", false)):
            protected_body.status_tags.erase("special_protection")
            protected_body.refresh_status_badges()
            _consume_selected_special(source, copied)
            _battle_log_set("%s • Illusion protectrice : %s annule complètement %s." % [phase_label,target.display_name,special_name_used])
            return

    if cid == "rock_lee":
        if target == source:
            _battle_log_set("%s perdue : Rock Lee doit viser un autre allié." % phase_label)
            return
        target.stat_buffs["taijutsu"] = int(target.stat_buffs.get("taijutsu",0)) + 300
        _consume_selected_special(source, copied)
        _battle_log_set("%s • Tenue de combat : %s gagne +300 TAI permanent." % [phase_label,target.display_name])
        return
    if cid == "karin":
        if target == source:
            _battle_log_set("%s perdue : Karin doit viser un autre allié." % phase_label)
            return
        target.heal(target.max_hp)
        _consume_selected_special(source, copied)
        var self_cost: Dictionary = _apply_attack_damage(source, source, 1000, "status", true, false, false, false, false, false, false, true, true)
        _battle_log_set("%s • Morsure revigorante : %s full PV ; Karin perd %d PV." % [phase_label,target.display_name,int(self_cost.get("hp_damage",0))])
        _after_damage_resolution(source, source, self_cost)
        return
    if cid == "haku":
        _consume_selected_special(source, copied)
        if target.card_id in ["killer_bee","madara"]:
            _battle_log_set("%s • %s résiste à la Prison de glace." % [phase_label,target.display_name])
            return
        target.apply_disable(3, "haku_ice")
        _set_special_status(target, "haku_ice_prison_turns", 3)
        _battle_log_set("%s • Prison de glace : %s STUN 3T et -200 PV à chacun de ses tours." % [phase_label,target.display_name])
        return
    if cid == "danzo":
        target.set_hp(1)
        _consume_selected_special(source, copied)
        var before_danzo: int = source.hp
        source.set_hp(0)
        _battle_log_set("%s • Kamikaze : %s tombe à 1 PV ; Danzo se sacrifie." % [phase_label,target.display_name])
        _after_damage_resolution(source, source, {"hp_damage":before_danzo,"overflow":0,"killed":true,"immune":false,"suppress_survival":true})
        return
    if cid == "kisame":
        _consume_selected_special(source, copied)
        if target.card_id in ["killer_bee","madara"]:
            _battle_log_set("%s • %s résiste à la Prison aqueuse." % [phase_label,target.display_name])
            return
        target.status_tags["kisame_prisoned_by_uid"] = source.battle_uid
        target.refresh_status_badges()
        _battle_log_set("%s • Prison aqueuse : %s est bloqué tant que Kisame reste sur le terrain." % [phase_label,target.display_name])
        return
    if cid == "hidan":
        _consume_selected_special(source, copied)
        target.status_tags["doom_turns"] = 5
        target.status_tags["doom_source_team"] = source.team_name
        target.status_tags["doom_source_uid"] = source.battle_uid
        target.refresh_status_badges()
        _battle_log_set("%s • Jashin : %s condamné dans 5 tours si Hidan survit." % [phase_label,target.display_name])
        return
    if cid == "a3_raikage":
        # PC : le montant est 50 % des PV ACTUELS de la cible choisie, puis Choji
        # peut intercepter. La frappe ignore les boucliers mais PAS les passifs,
        # esquives, Sharingan ni réductions défensives.
        var half_now: int = maxi(1, int(ceil(float(target.hp) * 0.50)))
        var actual_a3: YugitoCardActor = _guard_target(target, source)
        var r_a3: Dictionary = _apply_attack_damage(source, actual_a3, half_now, "taijutsu", false, false, true, true, false, true, true, true, false)
        _consume_selected_special(source, copied)
        _mark_attack_usage(source,"taijutsu")
        _post_attack_passives(source,actual_a3,r_a3,"taijutsu",true,cid)
        _battle_log_set("%s • Technique à un doigt : %s perd %d PV (50%% PV actuels de la cible choisie)." % [phase_label,actual_a3.display_name,int(r_a3.get("hp_damage",0))])
        _after_damage_resolution(source,actual_a3,r_a3)
        return
    if cid == "zetsu":
        var pending_ref: Dictionary = ai_delayed_action2 if source.team_name == "ally" else delayed_action2
        var intercept: bool = not pending_ref.is_empty() and str(pending_ref.get("kind","")) == "switch" and str(pending_ref.get("source_id","")) == target.card_id
        if intercept:
            if source.team_name == "ally":
                ai_delayed_action2 = {}
            else:
                delayed_action2 = {}
        var zamount: int = 500 if intercept else 300
        var rz: Dictionary = _apply_attack_damage(source,target,zamount,"special",true,false,false,true,false,false,false)
        _consume_selected_special(source, copied)
        _battle_log_set("%s • Embuscade : %s%d PV fixes." % [phase_label,"Switch A2 ANNULÉ • " if intercept else "",int(rz.get("hp_damage",0))])
        _after_damage_resolution(source,target,rz)
        return
    if cid == "kushina":
        if target.card_id != "madara":
            _set_special_status(target,"sealed_turns",5)
        var rk: Dictionary = _apply_attack_damage(source,target,_percent_hp_amount(target,0.20),"special",true,false,false,true,false,false,false)
        _consume_selected_special(source, copied)
        _battle_log_set("%s • Scellement Uzumaki : %s%s, -%d PV." % [phase_label,target.display_name," ignore le SCELLÉ" if target.card_id=="madara" else " SCELLÉ 5T",int(rk.get("hp_damage",0))])
        _after_damage_resolution(source,target,rk)
        return
    if cid == "rin":
        var rr: Dictionary = _apply_attack_damage(source,target,550,"special",true,false,false,true,false,false,false)
        _consume_selected_special(source, copied)
        _battle_log_set("%s • Orbe du démon : -%d PV fixes." % [phase_label,int(rr.get("hp_damage",0))])
        _after_damage_resolution(source,target,rr)
        return
    if cid == "shizune":
        target.status_tags["shizune_poisoned"] = true
        if target.card_id != "madara":
            target.apply_disable(2,"shizune")
        _consume_selected_special(source, copied)
        target.refresh_status_badges()
        _battle_log_set("%s • Aiguilles : poison -30/T%s." % [phase_label," + STUN 2T" if target.card_id!="madara" else " (Madara ignore STUN)"])
        return
    if cid == "chojuro":
        var stock: int = int(source.status_tags.get("chojuro_chakra_stock",0))
        var actual_chojuro: YugitoCardActor = _guard_target(target, source)
        var cc: Dictionary = _calculate_classic_damage(source,actual_chojuro,"taijutsu",stock,false,false)
        var rc: Dictionary = _apply_attack_damage(source,actual_chojuro,int(cc.get("damage",0)),"taijutsu",false,false,true,true,false,true)
        source.status_tags["chojuro_chakra_stock"] = 0
        _consume_selected_special(source, copied)
        _mark_attack_usage(source,"taijutsu")
        _post_attack_passives(source,actual_chojuro,rc,"taijutsu",true,cid)
        _battle_log_set("%s • Hiramekarei libère %d stock : -%d PV." % [phase_label,stock,int(rc.get("hp_damage",0))])
        _after_damage_resolution(source,actual_chojuro,rc)
        return
    if cid == "jugo":
        var actual_jugo: YugitoCardActor = _guard_target(target, source)
        var jc: Dictionary = _calculate_classic_damage(source,actual_jugo,"taijutsu",0,false,false)
        var called_female: bool = battle_rng.randf() < 0.50
        var target_female: bool = _is_female_card(actual_jugo.card_id)
        var jugo_mult: float = 1.50 if called_female == target_female else 0.50
        var jugo_base: int = int(jc.get("damage",0))
        var jugo_amount: int = maxi(1,int(round(float(jugo_base)*jugo_mult))) if jugo_base > 0 else 0
        var rj: Dictionary = _apply_attack_damage(source,actual_jugo,jugo_amount,"taijutsu",false,false,true,true,false,true)
        _consume_selected_special(source, copied)
        _mark_attack_usage(source,"taijutsu")
        _post_attack_passives(source,actual_jugo,rj,"taijutsu",true,cid)
        _battle_log_set("%s • Furie Jûgo annonce %s : %s → -%d PV." % [phase_label,"FEMME" if called_female else "HOMME","BON MATCH x1,5" if jugo_mult>1.0 else "MAUVAIS MATCH x0,5",int(rj.get("hp_damage",0))])
        _after_damage_resolution(source,actual_jugo,rj)
        return
    if cid in ["mu","onoki"]:
        var own_nin: int = source.effective_stat("ninjutsu",target.stars)
        var tar_nin: int = target.effective_stat("ninjutsu",source.stars)
        var jinton_execute: bool = tar_nin < own_nin
        # PC : si le NIN adverse est inférieur, Jinton met directement le corps à
        # 0 PV : boucliers/réductions/Doton ne peuvent pas l'empêcher, mais les
        # vraies survivances puis Chiyo/Kabuto restent autorisées. Sinon = 1000 fixes.
        var rmu: Dictionary
        if jinton_execute:
            rmu = _apply_attack_damage(source, target, target.hp, "status", true, false, false, false, false, false, false, true, true)
        else:
            rmu = _apply_attack_damage(source, target, 1000, "status", true, false, false, false, false, false, false)
        source.stat_buffs["ninjutsu"] = int(source.stat_buffs.get("ninjutsu",0)) - 1000
        _consume_selected_special(source, copied)
        _battle_log_set("%s • Jinton : -%d PV ; %s perd 1000 NIN." % [phase_label,int(rmu.get("hp_damage",0)),source.display_name])
        _after_damage_resolution(source,target,rmu)
        return
    if cid == "omoi":
        _consume_selected_special(source, copied)
        var omoi_amount: int = 500
        # Le 1/3 d'oubli et le bonus +20 % appartiennent au PASSIF d'Omoi,
        # pas à la technique copiée par Kakashi. Une copie reste donc à 500 fixes.
        if source.card_id == "omoi":
            if battle_rng.randf() < (1.0/3.0):
                _battle_log_set("%s • Omoi oublie sa frappe : 0 dégât." % phase_label)
                return
            omoi_amount = 600
        var actual_omoi: YugitoCardActor = _guard_target(target, source)
        var ro: Dictionary = _apply_attack_damage(source, actual_omoi, omoi_amount, "ninjutsu", false, false, true, true, false, true, true)
        if not bool(ro.get("immune",false)) and not actual_omoi.defeated and actual_omoi.card_id not in ["madara","killer_bee"]:
            actual_omoi.apply_disable(1,"omoi")
        _mark_attack_usage(source,"ninjutsu")
        _post_attack_passives(source,actual_omoi,ro,"ninjutsu",true,cid)
        _battle_log_set("%s • Lame foudroyante : -%d PV%s." % [phase_label,int(ro.get("hp_damage",0))," + PARALYSIE" if actual_omoi.card_id not in ["madara","killer_bee"] else ""])
        _after_damage_resolution(source,actual_omoi,ro)
        return
    if cid == "karui":
        var actual_karui: YugitoCardActor = _guard_target(target, source)
        var rkarui: Dictionary = _apply_attack_damage(source, actual_karui, 400, "ninjutsu", false, false, true, true, true, true, true)
        _consume_selected_special(source, copied)
        _mark_attack_usage(source,"ninjutsu")
        _post_attack_passives(source,actual_karui,rkarui,"ninjutsu",true,cid)
        _battle_log_set("%s • Frappe Raiton : -%d PV." % [phase_label,int(rkarui.get("hp_damage",0))])
        _after_damage_resolution(source,actual_karui,rkarui)
        return
    if cid == "hanzo":
        target.status_tags["hanzo_poisoned"] = true
        _consume_selected_special(source, copied)
        target.refresh_status_badges()
        _battle_log_set("%s • Poison salamandre : -5%% PV max à chaque tour jusqu'à la mort." % phase_label)
        return
    if cid == "torune":
        target.status_tags["torune_micro_poison"] = maxi(100,int(target.status_tags.get("torune_micro_poison",0)))
        _consume_selected_special(source, copied)
        target.refresh_status_badges()
        _battle_log_set("%s • Microbiose : %s perdra 100 PV par tour jusqu'à sa mort." % [phase_label,target.display_name])
        return
    if cid == "mei":
        # PC : l'impact principal (900) peut être intercepté par Choji, mais les
        # deux splashs (450) restent centrés sur le SLOT initialement ciblé. Si
        # Choji est adjacent et intercepte, il peut donc recevoir principal + splash.
        var total_mei: int = 0
        var center_slot: int = target.seed_index_value() % 3
        var main_mei: YugitoCardActor = _guard_target(target, source)
        var main_amount: int = 900
        if main_mei.element_name == "vent":
            main_amount = int(round(float(main_amount) * 1.10)) + 150
        var main_rm: Dictionary = _apply_attack_damage(source, main_mei, main_amount, "status", true, false, false, false, false, false, false)
        total_mei += int(main_rm.get("hp_damage", 0))
        _after_damage_resolution(source, main_mei, main_rm)
        for side_slot: int in [center_slot - 1, center_slot + 1]:
            if side_slot < 0 or side_slot > 2:
                continue
            var splash_mei: YugitoCardActor = null
            for candidate_mei: YugitoCardActor in _living_cards(enemy_team):
                if candidate_mei.seed_index_value() % 3 == side_slot:
                    splash_mei = candidate_mei
                    break
            if splash_mei == null or splash_mei.defeated:
                continue
            var splash_amount: int = 450
            if splash_mei.element_name == "vent":
                splash_amount = int(round(float(splash_amount) * 1.10)) + 150
            var splash_rm: Dictionary = _apply_attack_damage(source, splash_mei, splash_amount, "status", true, false, false, false, false, false, false)
            total_mei += int(splash_rm.get("hp_damage", 0))
            _after_damage_resolution(source, splash_mei, splash_rm)
        _consume_selected_special(source, copied)
        _battle_log_set("%s • Déferlement magmatique : %d PV au total." % [phase_label,total_mei])
        return
    if cid == "temari":
        var selected_uid: int = target.battle_uid
        var total_temari: int = 0
        for enemy_te: YugitoCardActor in _living_cards(enemy_team).duplicate():
            var ct: Dictionary = _calculate_classic_damage(source,enemy_te,"ninjutsu",250,false,false)
            var rt: Dictionary = _apply_attack_damage(source,enemy_te,int(ct.get("damage",0)),"ninjutsu",false,false,true,true,false,true)
            total_temari += int(rt.get("hp_damage",0))
            _after_damage_resolution(source,enemy_te,rt)
        _consume_selected_special(source, copied)
        _mark_attack_usage(source,"ninjutsu")
        var selected_after: YugitoCardActor = _resolve_actor_uid(selected_uid)
        if selected_after != null and not selected_after.defeated:
            _force_return_to_reserve(selected_after)
        _battle_log_set("%s • Grande rafale : %d PV total ; cible survivante renvoyée en réserve." % [phase_label,total_temari])
        return

    if cid == "shikamaru":
        # P21 : A1 et A2 passent volontairement par LA MÊME fonction pure
        # d'application. La résolution retardée ne possède plus de branche
        # spéciale susceptible d'oublier les Ombres.
        var linked_count: int = _apply_shikamaru_shadows(source, target)
        _consume_selected_special(source, copied)
        _refresh_persistent_status_links()
        _schedule_shikamaru_mobile_visual_sync(source.battle_uid)
        var shadow_phase: String = "A2 RÉACTION" if resolving_delayed_action else phase_label
        _battle_log_set("%s • Possession des ombres : %d Ninja(s) lié(s) 3 tours ; la cible choisie reste libre. Recharge 4 tours." % [shadow_phase, linked_count])
        return
    if cid == "ino":
        _consume_selected_special(source, copied)
        if battle_rng.randf() >= 0.50:
            source.apply_disable(3, "ino_failure")
            _battle_log_set("%s • Transfert raté : Ino est STUN pendant 3 de ses tours." % phase_label)
            return
        var duration_map: Dictionary = {3.0: 5, 3.5: 4, 4.0: 3, 4.5: 2, 5.0: 1}
        var duration: int = int(duration_map.get(target.stars, 1))
        # P16 : le Transfert ne transforme PAS la cible en faux STUN. Le vrai
        # CardActor ennemi reste l'unique porteur de ses PV/boucliers/poisons/
        # buffs/debuffs. Ino ne garde qu'un lien stable vers cette instance.
        target.status_tags["possessed_by_uid"] = source.battle_uid
        target.status_tags["possessed_by_id"] = source.card_id
        source.status_tags["ino_target_uid"] = target.battle_uid
        source.status_tags["ino_target"] = target.card_id
        source.status_tags["ino_target_name"] = target.display_name
        source.status_tags["ino_visual_stars"] = target.stars
        source.status_tags["ino_visual_element"] = target.element_name
        source.status_tags["ino_turns"] = duration
        source.status_tags["ino_started_cycle"] = turn_counter
        source.status_tags.erase("ino_skip_tick")
        source.status_tags.erase("possession_stats")
        source.status_tags.erase("possession_element")
        source.refresh_status_badges()
        target.refresh_status_badges()
        _battle_log_set("%s • Transfert réussi : %s est contrôlé pendant %d tour(s)." % [phase_label, target.display_name, duration])
        return
    if cid == "yamato":
        var fixed: int = maxi(1, int(round(float(target.max_hp) * 0.20)))
        var result_yamato: Dictionary = _apply_attack_damage(source, target, fixed, "special", true, false, false, true, false, false, false)
        target.status_tags["rooted_turns"] = 3
        target.status_tags["rooted_turns_skip_tick"] = true
        _consume_selected_special(source, copied)
        _battle_log_set("%s • Prison du Mokuton : -%d PV et ENRACINÉ 3 tours." % [phase_label, int(result_yamato.get("hp_damage", 0))])
        _after_damage_resolution(source, target, result_yamato)
        return
    if cid == "sai":
        _consume_selected_special(source, copied)
        if target.card_id in ["killer_bee", "madara"]:
            _battle_log_set("%s • %s résiste à la Toile au monstre fantomatique." % [phase_label, target.display_name])
            return
        target.apply_disable(3, "sai_prison")
        target.status_tags["sai_prison"] = 3
        target.status_tags["sai_prison_skip_tick"] = true
        _battle_log_set("%s • Toile au monstre fantomatique : %s est emprisonné 3 tours." % [phase_label, target.display_name])
        return
    if cid == "kurenai":
        target.disabled_turns = 0
        for cleanse_key: String in [
            "sai_prison", "sai_prison_skip_tick",
            "shadow_source", "shadow_source_uid", "shadow_turns", "shadow_turns_skip_tick",
            "blocked_taijutsu_turns", "blocked_ninjutsu_turns", "blocked_genjutsu_turns",
            "special_block_turns", "haku_ice_prison_turns", "kisame_prisoned_by_uid",
            "delayed_damage", "shino_poisoned", "hanzo_poisoned", "shizune_poisoned",
            "shizune_paralysis_turns", "sealed_turns"
        ]:
            target.status_tags.erase(cleanse_key)
            target.status_tags.erase("%s_skip_tick" % cleanse_key)
        target.clear_negative_timed_modifiers()
        target.status_tags["kurenai_hidden_shield"] = 600
        target.status_tags["special_protection"] = true
        _consume_selected_special(source, copied)
        _battle_log_set("%s • Illusion protectrice : effets négatifs retirés, bouclier 600 et prochaine spéciale annulée." % phase_label)
        return
    if cid == "asuma":
        # Classic : détruit bouclier visible + bouclier caché de Kurenai
        # avant les 400 dégâts fixes.
        target.shield = 0
        target.status_tags.erase("kurenai_hidden_shield")
        target._refresh_hp_label()
        target.refresh_status_badges()
        var asuma_result: Dictionary = _apply_attack_damage(source, target, 400, "special", true, false, false, true, false, false, false)
        _consume_selected_special(source, copied)
        _battle_log_set("%s • Kunai lame chakra : boucliers détruits et -%d PV fixes." % [phase_label, int(asuma_result.get("hp_damage", 0))])
        _after_damage_resolution(source, target, asuma_result)
        return

    if cid == "mifune":
        var defensive_before: bool = target.shield > 0 or int(target.status_tags.get("kurenai_hidden_shield",0)) > 0 or target.card_id in ["nagato","sasuke","gaara","a_raikage","sasori","suigetsu","kurenai","kankuro","chiyo","tobirama","onoki","danzo","orochimaru","hidan","kakuzu","haku","shisui","konohamaru","choji"]
        var mifune_fixed: int = 750 if defensive_before else 500
        var mifune_calc: Dictionary = _calculate_classic_damage(source,target,"taijutsu",0,false,false)
        var mifune_result: Dictionary = _apply_attack_damage(source,target,int(mifune_calc.get("damage",0))+mifune_fixed,"taijutsu",true,false,true,true,true,true)
        _consume_selected_special(source, copied)
        _mark_attack_usage(source,"taijutsu")
        _post_attack_passives(source,target,mifune_result,"taijutsu",true,cid)
        _battle_log_set("%s • Mifune : Trancheur +%d fixe → -%d PV." % [phase_label,mifune_fixed,int(mifune_result.get("hp_damage",0))])
        _after_damage_resolution(source,target,mifune_result)
        return

    # Spéciales d'attaque : reprend les bonus du moteur PC pour les cartes déjà migrées.
    var cfg: Dictionary = _special_attack_config(cid)
    if cfg.is_empty():
        var fallback_style: String = special_style_used if special_style_used in ["taijutsu", "ninjutsu", "genjutsu"] else "ninjutsu"
        cfg = {"style": fallback_style, "bonus": 250, "bypass": false, "absolute": false}
    var style: String = str(cfg.get("style", "ninjutsu"))
    var bonus: int = int(cfg.get("bonus", 0))
    var bypass: bool = bool(cfg.get("bypass", false))
    var absolute: bool = bool(cfg.get("absolute", false))
    if cid == "sasuke":
        # Chidori détruit uniquement les protections actives prévues par le PC.
        # Poison, bombes Tobi, buffs, STUN et autres états personnels survivent.
        _strip_chidori_defenses(target)
    if cid == "kiba" and target.taijutsu < source.taijutsu:
        bonus += 100
    var actual_target: YugitoCardActor = target if bool(cfg.get("ignore_guard", false)) else _guard_target(target, source)
    # Kamui offensif détruit réellement les DEUX couches de bouclier de la
    # cible effective, donc après l'interception éventuelle de Choji.
    if cid == "obito" and actual_target != null:
        actual_target.shield = 0
        actual_target.status_tags.erase("kurenai_hidden_shield")
        actual_target._refresh_hp_label()
        actual_target.refresh_status_badges()
    # Scalpel de Kabuto ignore le bouclier via absolute=true mais ne le détruit
    # pas physiquement : s'il survit par une mécanique autorisée, il le garde.
    var calc: Dictionary = _calculate_classic_damage(source, actual_target, style, bonus, absolute, bool(cfg.get("force_advantage", false)))
    var result: Dictionary = _apply_attack_damage(source, actual_target, int(calc.get("damage", 0)), style, bypass, absolute, true, true, false, true)
    _consume_selected_special(source, copied)
    _mark_attack_usage(source, style)
    _post_attack_passives(source, actual_target, result, style, true, cid)
    var dealt: int = int(result.get("hp_damage", 0))
    _battle_log_set("%s • %s utilise %s : -%d PV" % [phase_label, source.display_name, special_name_used, dealt])

    if cid == "hashirama" and dealt > 0 and not source.defeated:
        source.heal(200)
    elif cid == "madara" and not source.defeated:
        source.add_shield(300)
    elif cid == "nagato" and dealt > 0 and not actual_target.defeated:
        actual_target.status_tags["blocked_taijutsu_turns"] = maxi(1, int(actual_target.status_tags.get("blocked_taijutsu_turns", 0)))
        actual_target.status_tags["blocked_taijutsu_turns_skip_tick"] = true
    elif cid == "itachi" and not source.defeated:
        for splash: YugitoCardActor in _living_cards(actual_target.team_name):
            if splash != actual_target:
                var splash_result: Dictionary = _apply_attack_damage(source, splash, 350, "special", true, false, false, true, false, false, false)
                _after_damage_resolution(source, splash, splash_result)
    elif cid == "killer_bee" and int(result.get("hp_damage", 0)) >= 400 and not source.defeated:
        source.add_shield(100)
    elif cid == "gai" and not source.defeated:
        # PC : le recul non létal de Hirudora peut lui-même franchir un seuil
        # 75/50/25 %. Les portes doivent donc être évaluées IMMÉDIATEMENT après
        # le recul, pas seulement lorsqu'il reçoit des dégâts ennemis.
        source.set_hp(maxi(1, source.hp - 150))
        _apply_threshold_passives(source)
    elif cid == "minato" and bool(result.get("killed", false)) and not source.defeated:
        source.add_shield(150)
    elif cid == "naruto" and dealt > 0 and not actual_target.defeated:
        actual_target.add_timed_modifier("ninjutsu", -100, 1, "naruto_rasengan")
    elif cid == "a_raikage" and dealt > 0 and not source.defeated:
        source.add_shield(100)
    elif cid == "tsunade" and not source.defeated:
        source.heal(100)
    elif cid == "deidara" and not source.defeated:
        source.status_tags["blocked_ninjutsu_turns"] = maxi(1, int(source.status_tags.get("blocked_ninjutsu_turns", 0)))
        source.status_tags["blocked_ninjutsu_turns_skip_tick"] = true
    elif cid == "neji" and dealt > 0 and not actual_target.defeated and actual_target.card_id != "killer_bee":
        actual_target.status_tags["special_block_turns"] = maxi(1, int(actual_target.status_tags.get("special_block_turns", 0)))
        actual_target.status_tags["special_block_turns_skip_tick"] = true
    elif cid == "sakura" and bool(result.get("killed", false)) and not source.defeated:
        source.heal(200)
    elif cid == "sasori" and dealt > 0 and not actual_target.defeated:
        actual_target.status_tags["delayed_damage"] = maxi(100, int(actual_target.status_tags.get("delayed_damage", 0)))
    elif cid == "hinata" and not source.defeated:
        source.add_shield(150)
    elif cid == "shino" and dealt > 0 and not actual_target.defeated:
        actual_target.status_tags["shino_poisoned"] = true
    elif cid == "suigetsu" and not source.defeated:
        source.heal(150)

    _after_damage_resolution(source, actual_target, result)

func _restore_gengetsu_clone(actor: YugitoCardActor, exploded: bool) -> void:
    if actor == null or not is_instance_valid(actor) or not bool(actor.status_tags.get("gengetsu_clone_active",false)):
        return
    var saved_max: int = int(actor.status_tags.get("gengetsu_saved_max_hp",actor.base_max_hp))
    var saved_hp: int = int(actor.status_tags.get("gengetsu_saved_hp",saved_max))
    var saved_shield: int = int(actor.status_tags.get("gengetsu_saved_shield",0))
    actor.status_tags.erase("gengetsu_clone_active")
    actor.status_tags.erase("gengetsu_clone_turns")
    actor.status_tags.erase("gengetsu_saved_hp")
    actor.status_tags.erase("gengetsu_saved_max_hp")
    actor.status_tags.erase("gengetsu_saved_shield")
    actor.max_hp = maxi(1,saved_max)
    actor.hp = clampi(saved_hp,1,actor.max_hp)
    actor.shield = maxi(0,saved_shield)
    if actor.card_id == "gengetsu":
        actor.special_used = false
        actor.special_cooldown = 4
        # P18 : la restauration du clone intervient après la phase de recharge
        # de ce début de tour ; le prochain tour doit donc déjà consommer 4 -> 3.
        actor.status_tags.erase("cooldown_skip_tick")
        actor.status_tags["gengetsu_untargetable"] = false
    else:
        # Une copie (Kakashi) ne doit ni restaurer Raikiri ni lui imposer le
        # cooldown personnel de Gengetsu. La ressource COPIE reste consommée.
        actor.status_tags.erase("gengetsu_untargetable")
    actor._refresh_hp_label()
    actor.refresh_status_badges()
    actor.refresh_dynamic_identity()
    actor.refresh_status_visuals()
    _battle_log_set("Clone de Gengetsu : %s" % ("EXPLOSION 1300 sur tous les ennemis." if exploded else "clone détruit, retour à la forme originale sans explosion."))

func _force_return_to_reserve(actor: YugitoCardActor) -> void:
    if actor == null or not is_instance_valid(actor) or actor.defeated:
        return
    _explode_tobi_bombs(_opponent_team(actor.team_name), actor, "BOMBES TOBI • SORTIE")
    if actor.defeated:
        return

    var reserve: Array[String] = ally_reserve if actor.team_name == "ally" else enemy_reserve
    var state_store: Dictionary = ally_reserve_states if actor.team_name == "ally" else enemy_reserve_states

    # Règle YUGITO : Grande Rafale est l'exception aux verrous de terrain. La
    # carte soufflée conserve son INSTANCE complète, y compris STUN/poisons/
    # boucliers/buffs et les verrous reçus Ombres/Prison/Scellé/Jashin.
    _cleanup_context_links_for_departure(actor, true)
    actor.set_synergy_bonus(0.0)
    state_store[actor.card_id] = actor.export_state()

    # Si d'autres cartes étaient déjà en réserve, la carte soufflée n'est PAS
    # proposée immédiatement pour combler son propre trou. Si elle était seule,
    # elle devient naturellement l'unique choix, comme GameEngine PC.
    var had_other_reserve: bool = not reserve.is_empty()
    var forced_id: String = str(forced_reserve_choice.get(actor.team_name, ""))
    var candidates: Array[String] = []
    # Byakugan/Ao s'applique à TOUT prochain Switch/remplacement, y compris le
    # trou créé par Grande rafale. La cible soufflée n'est ajoutée qu'après
    # avoir constitué l'offre lorsque d'autres réservistes existaient déjà.
    if had_other_reserve:
        if not forced_id.is_empty() and reserve.has(forced_id):
            candidates = [forced_id]
        else:
            candidates = _make_reserve_candidates(reserve, 3, true)
    if not reserve.has(actor.card_id):
        reserve.append(actor.card_id)
    if not had_other_reserve:
        if not forced_id.is_empty() and reserve.has(forced_id):
            candidates = [forced_id]
        else:
            candidates = _make_reserve_candidates(reserve, 3, true)

    if candidates.is_empty():
        return

    if actor.team_name == "ally":
        actor.visible = false
        resolution_waiting_replacement = true
        replacement_context = {
            "mode": "temari",
            "actor": actor,
            "team": actor.team_name,
            "candidates": candidates
        }
        replacement_modal.show_choices(
            "GRANDE RAFALE — REMPLACEMENT",
            "%s est soufflé dans la réserve • choisis le Ninja qui prend exactement son emplacement" % actor.display_name,
            candidates,
            true
        )
        _battle_log_set("GRANDE RAFALE — le duel est suspendu jusqu'au remplacement.")
        _refresh_reserve_labels()
        _update_team_status()
        _refresh_action_buttons()
        return

    var incoming_id: String = _ai_choose_replacement_candidate(candidates)
    if incoming_id.is_empty():
        incoming_id = candidates[0]
    reserve.erase(incoming_id)
    var blown_name: String = actor.display_name
    var incoming_name: String = str((cards_by_id.get(incoming_id,{}) as Dictionary).get("name",incoming_id))
    _replace_actor(actor, incoming_id, false, false)
    _battle_log_set("%s est soufflé en réserve • IA choisit %s parmi %d proposition(s)." % [blown_name, incoming_name, candidates.size()])
    _refresh_reserve_labels()
    _update_team_status()

func _apply_threshold_passives(target: YugitoCardActor) -> void:
    if target == null or not is_instance_valid(target) or target.defeated or target.hp <= 0:
        return
    if target.card_id == "gai":
        var thresholds: Array[int] = [75,50,25]
        for threshold_gai: int in thresholds:
            var key_gai: String = "gai_gate_%d" % threshold_gai
            if target.hp * 100 <= target.max_hp * threshold_gai and not bool(target.status_tags.get(key_gai,false)):
                target.status_tags[key_gai] = true
                target.stat_buffs["taijutsu"] = int(target.stat_buffs.get("taijutsu",0)) + 250
                target.status_tags["gai_gate_count"] = int(target.status_tags.get("gai_gate_count",0)) + 1
    if target.card_id == "tsunade" and target.hp > 0 and target.hp * 100 <= target.max_hp * 15:
        var tsunade_heal: int = target.max_hp - target.hp
        if tsunade_heal > 0:
            target.heal(tsunade_heal)
            _battle_log_append("  •  BYAKUGÔ : Tsunade régénérée à 100%")
    if target.card_id == "rin" and not bool(target.status_tags.get("rin_isobu_active",false)) and target.hp * 100 < target.max_hp * 25:
        target.status_tags["rin_isobu_active"] = true
        target.base_max_hp += 1000
        target.max_hp += 1000
        target.hp += 1000
        target.stat_buffs["taijutsu"] = int(target.stat_buffs.get("taijutsu",0))+250
        target.stat_buffs["ninjutsu"] = int(target.stat_buffs.get("ninjutsu",0))+300
        target.stat_buffs["genjutsu"] = int(target.stat_buffs.get("genjutsu",0))+200
    if target.card_id == "asuma" and not bool(target.status_tags.get("asuma_smoke_triggered",false)) and target.hp * 100 < target.max_hp * 20:
        target.status_tags["asuma_smoke_triggered"] = true
        target.status_tags["asuma_smoke_turns"] = 2
    if target.card_id == "jugo":
        var wanted: int = 2 if target.hp * 100 <= target.max_hp * 40 else (1 if target.hp * 100 <= target.max_hp * 70 else 0)
        var stage: int = int(target.status_tags.get("jugo_stage",0))
        while stage < wanted:
            stage += 1
            target.status_tags["jugo_stage"] = stage
            target.base_max_hp += 100
            target.max_hp += 100
            target.hp += 100
            target.stat_buffs["taijutsu"] = int(target.stat_buffs.get("taijutsu",0))+100
            target.stat_buffs["ninjutsu"] = int(target.stat_buffs.get("ninjutsu",0))+100
            target.stat_buffs["genjutsu"] = int(target.stat_buffs.get("genjutsu",0))-100
    if target.card_id == "anko" and not bool(target.status_tags.get("anko_curse_used",false)) and target.hp * 100 < target.max_hp * 25:
        target.status_tags["anko_curse_used"] = true
        target.heal(600)
    target._refresh_hp_label()
    target.refresh_status_badges()

func _mark_attack_usage(attacker: YugitoCardActor, style: String) -> void:
    if attacker == null or not is_instance_valid(attacker) or style not in ["taijutsu","ninjutsu","genjutsu"]:
        return
    if attacker.card_id == "rock_lee" and style == "taijutsu":
        attacker.status_tags["rock_lee_boosts_left"] = maxi(0, int(attacker.status_tags.get("rock_lee_boosts_left",0)) - 1)
    if attacker.card_id == "kiba" and style == "taijutsu":
        attacker.status_tags["kiba_first_tai"] = false
    if attacker.card_id == "tenten" and style == "taijutsu":
        attacker.stat_buffs["taijutsu"] = int(attacker.stat_buffs.get("taijutsu",0)) + 25
        _battle_log_append("  •  Tenten +25 TAI permanent")
    attacker.status_tags["previous_attack_style"] = style
    attacker.refresh_status_badges()

func _is_female_card(card_id: String) -> bool:
    return card_id in ["karin","tsunade","sakura","hinata","temari","tenten","chiyo","mei","ino","kurenai","kushina","rin","shizune","konan","kurotsuchi","karui","anko"]

func _post_attack_passives(attacker: YugitoCardActor, target: YugitoCardActor, result: Dictionary, style: String, is_special: bool, special_source_id: String) -> void:
    if attacker == null or target == null or not is_instance_valid(attacker) or not is_instance_valid(target):
        return
    var hp_damage: int = int(result.get("hp_damage",0))
    var immune: bool = bool(result.get("immune",false))
    if hp_damage > 0:
        if attacker.card_id == "kisame" and style == "ninjutsu" and not attacker.defeated:
            attacker.heal(100)
        if attacker.card_id == "neji" and not bool(attacker.status_tags.get("neji_passive_used",false)) and not target.defeated:
            var loss: int = maxi(1, int(round(float(target.effective_stat("ninjutsu")) * 0.50)))
            target.add_timed_modifier("ninjutsu", -loss, 2, "neji_tenketsu")
            target.status_tags["special_block_turns"] = maxi(2, int(target.status_tags.get("special_block_turns",0)))
            target.status_tags["special_block_turns_skip_tick"] = true
            attacker.status_tags["neji_passive_used"] = true
        if attacker.card_id == "shino" and style == "ninjutsu" and not target.defeated:
            target.add_timed_modifier("ninjutsu", -100, 1, "shino_kikaichu")
        if attacker.card_id == "deidara" and style == "ninjutsu":
            var slot: int = target.seed_index_value() % 3
            for other: YugitoCardActor in _living_cards(target.team_name):
                var oslot: int = other.seed_index_value() % 3
                if abs(oslot - slot) == 1:
                    var splash: Dictionary = _apply_attack_damage(attacker, other, 150, "ninjutsu", true, false, false, false, false, false, false)
                    _after_damage_resolution(attacker, other, splash)
    if target.card_id == "sasori" and style == "taijutsu" and not immune and not bool(result.get("defensive_bypass", false)) and not attacker.defeated and not bool(target.status_tags.get("sasori_counter_used_cycle",false)):
        target.status_tags["sasori_counter_used_cycle"] = true
        attacker.stat_buffs["taijutsu"] = int(attacker.stat_buffs.get("taijutsu",0)) - 100
        attacker.status_tags["sasori_tai_poison"] = int(attacker.status_tags.get("sasori_tai_poison",0)) + 100
        _deal_fixed_status_damage(attacker,50,"POISON MARIONNETTE SASORI")
    if target.card_id == "mei" and style == "taijutsu" and hp_damage > 0 and not target.defeated and not attacker.defeated:
        var fire_counter: int = 100
        if attacker.element_name == "vent":
            fire_counter = int(round(100.0 * 1.10)) + 150
        var mei_counter: Dictionary = _apply_attack_damage(target, attacker, fire_counter, "special", true, false, false, false, false, false, false)
        _after_damage_resolution(target, attacker, mei_counter)
    if target.card_id == "hinata" and not immune and not attacker.defeated:
        if style in ["taijutsu","ninjutsu","genjutsu"]:
            var loss_h: int = maxi(1, int(round(float(attacker.effective_stat(style)) * 0.35)))
            attacker.add_timed_modifier(style, -loss_h, 2, "hinata_hakke")
        var counter_h: Dictionary = _apply_attack_damage(target, attacker, 100, "special", true, false, false, false, false, false, false)
        _after_damage_resolution(target, attacker, counter_h)
    if target.card_id == "torune" and style == "taijutsu" and not immune and not attacker.defeated:
        attacker.status_tags["torune_contact_poison"] = maxi(50, int(attacker.status_tags.get("torune_contact_poison",0)))
    if target.card_id == "konan" and bool(target.status_tags.get("konan_mine_active",false)) and not immune and not attacker.defeated:
        target.status_tags.erase("konan_mine_active")
        target.refresh_status_badges()
        _deal_fixed_status_damage(attacker,200,"MINE EXPLOSIVE KONAN")
    if target.card_id == "itachi" and hp_damage > 0 and not target.defeated and attacker.card_id not in ["killer_bee","madara"]:
        attacker.apply_disable(2, "tsukuyomi")
    if is_special and target.card_id == "kakashi" and hp_damage > 0 and str(target.status_tags.get("copied_special_id","")).is_empty() and not special_source_id.is_empty():
        target.status_tags["copied_special_id"] = special_source_id
        var copied: Dictionary = cards_by_id.get(special_source_id,{}) as Dictionary
        target.status_tags["copied_special_name"] = str(copied.get("special_name","Spéciale copiée"))
    attacker.refresh_status_badges()
    target.refresh_status_badges()

func _percent_hp_amount(target: YugitoCardActor, pct: float) -> int:
    return maxi(1, int(round(float(target.max_hp) * pct)))

func _set_special_status(target: YugitoCardActor, key: String, turns: int) -> void:
    target.status_tags[key] = maxi(turns, int(target.status_tags.get(key,0)))
    target.status_tags["%s_skip_tick" % key] = true
    target.refresh_status_badges()

func _find_live_card(team_name: String, card_id: String) -> YugitoCardActor:
    for actor: YugitoCardActor in _living_cards(team_name):
        if actor.card_id == card_id:
            return actor
    return null

func _best_card_id(ids: Array[String]) -> String:
    var best_id: String = ""
    var best_score: float = -INF
    for cid_best: String in ids:
        var data_best: Dictionary = cards_by_id.get(cid_best, {}) as Dictionary
        var score_best: float = float(data_best.get("stars",0.0)) * 10000.0
        score_best += float(int(data_best.get("hp",0)) + int(data_best.get("taijutsu",0)) + int(data_best.get("ninjutsu",0)) + int(data_best.get("genjutsu",0)))
        if score_best > best_score:
            best_score = score_best
            best_id = cid_best
    return best_id

func _best_reserve_id(team_name: String) -> String:
    var reserve: Array[String] = ally_reserve if team_name == "ally" else enemy_reserve
    return _best_card_id(reserve)

func _ao_anticipation_cancels(special_user: YugitoCardActor, phase_label: String) -> bool:
    if special_user == null or not is_instance_valid(special_user) or special_user.defeated:
        return true
    var ao_actor: YugitoCardActor = _find_live_card(_opponent_team(special_user.team_name), "ao")
    if ao_actor == null or ao_actor.defeated:
        return false
    var guarded: YugitoCardActor = _guard_target(special_user, ao_actor)
    var calc_ao: Dictionary = _calculate_classic_damage(ao_actor, guarded, "taijutsu", 0, false, false)
    var res_ao: Dictionary = _apply_attack_damage(ao_actor, guarded, int(calc_ao.get("damage",0)), "taijutsu", false, false, true, false, false, true)
    _mark_attack_usage(ao_actor, "taijutsu")
    _post_attack_passives(ao_actor, guarded, res_ao, "taijutsu", false, "")
    _battle_log_set("%s • ANTICIPATION AO : %s frappe %s avant la spéciale (-%d PV)." % [phase_label,ao_actor.display_name,guarded.display_name,int(res_ao.get("hp_damage",0))])
    _after_damage_resolution(ao_actor, guarded, res_ao)
    return special_user.defeated

func _arm_tracker_from_descriptor(source: YugitoCardActor, descriptor: Dictionary, special_id: String) -> String:
    if source == null or not is_instance_valid(source):
        return ""
    var target_team: String = _opponent_team(source.team_name)
    var reserve: Array[String] = ally_reserve if target_team == "ally" else enemy_reserve
    var tracked_id: String = str(descriptor.get("tracker_id", ""))
    # Le moteur PC garde un fallback déterministe pour les appels sans UI / IA.
    if tracked_id.is_empty() or not reserve.has(tracked_id):
        tracked_id = _best_reserve_id(target_team)
    if tracked_id.is_empty():
        return ""
    forced_reserve_choice[target_team] = tracked_id
    source.status_tags["tracker_armed"] = true
    if special_id == "ao":
        source.status_tags["ao_tracker_target"] = tracked_id
    else:
        source.status_tags["byakugan_tracker_target"] = tracked_id
    source.refresh_status_badges()
    return tracked_id

func _tobi_bomb_key(owner_team: String) -> String:
    return "tobi_bombs_%s" % owner_team

func _refresh_tobi_bomb_total(target: YugitoCardActor) -> void:
    if target == null or not is_instance_valid(target):
        return
    var total: int = int(target.status_tags.get("tobi_bombs_ally",0)) + int(target.status_tags.get("tobi_bombs_enemy",0))
    if total > 0:
        target.status_tags["tobi_bombs"] = total
    else:
        target.status_tags.erase("tobi_bombs")
    target.refresh_status_badges()
    target.refresh_status_visuals()

func _place_tobi_bomb(owner_team: String, target: YugitoCardActor) -> void:
    if target == null or not is_instance_valid(target) or target.defeated or target.team_name == owner_team:
        return
    var key_bomb: String = _tobi_bomb_key(owner_team)
    var count_bomb: int = mini(5, int(target.status_tags.get(key_bomb,0)) + 1)
    target.status_tags[key_bomb] = count_bomb
    _refresh_tobi_bomb_total(target)
    if owner_team == "ally":
        tobi_bomb_pending_team = ""
    if owner_team == "ally":
        _battle_log_set("TOBI : bombe secrète placée sur %s (%d/5)." % [target.display_name,count_bomb])
    else:
        # Classic : l'adversaire sait que Tobi a posé quelque chose, jamais où.
        _battle_log_set("Tobi place secrètement une bombe sur votre terrain.")
    _play_sfx("res://assets/audio/ui/pick.mp3", -12.0)

func _explode_tobi_bombs(owner_team: String, target: YugitoCardActor, label: String) -> int:
    if target == null or not is_instance_valid(target) or target.defeated:
        return 0
    var key_bomb: String = _tobi_bomb_key(owner_team)
    var stacks: int = int(target.status_tags.get(key_bomb,0))
    if stacks <= 0:
        return 0
    target.status_tags.erase(key_bomb)
    _refresh_tobi_bomb_total(target)
    var amount: int = stacks * 320
    var before_hp: int = target.hp
    _deal_fixed_status_damage(target, amount, label)
    return mini(before_hp, amount)

func _trigger_tobi_prediction(attacker: YugitoCardActor, attacked_target: YugitoCardActor) -> bool:
    if attacker == null or attacked_target == null:
        return false
    var owner_team: String = _opponent_team(attacker.team_name)
    var pred: Dictionary = tobi_predictions.get(owner_team, {}) as Dictionary
    if pred.is_empty():
        return false
    var predicted_enemy_uid: int = int(pred.get("enemy_uid",0))
    var predicted_ally_uid: int = int(pred.get("ally_uid",0))
    # La toute première attaque adverse tranche la prédiction immédiatement.
    if attacker.battle_uid != predicted_enemy_uid or attacked_target.battle_uid != predicted_ally_uid:
        _clear_failed_tobi_prediction(owner_team)
        return false
    tobi_predictions[owner_team] = {}
    var tobi_owner: YugitoCardActor = _find_live_card(owner_team, "tobi")
    if tobi_owner != null:
        tobi_owner.status_tags.erase("tobi_prediction_armed")
        tobi_owner.refresh_status_badges()
        tobi_owner.refresh_status_visuals()
    # Réussite : TOUTES les bombes de Tobi présentes sur le terrain adverse explosent.
    for bombed_enemy: YugitoCardActor in _living_cards(attacker.team_name).duplicate():
        _explode_tobi_bombs(owner_team, bombed_enemy, "C'ÉTAIT PRÉVU ! • BOMBES TOBI")
    return true

func _clear_failed_tobi_prediction(owner_team: String) -> void:
    var pred: Dictionary = tobi_predictions.get(owner_team, {}) as Dictionary
    if pred.is_empty():
        return
    # Échec : -2 bombes SUR CHAQUE Ninja adverse, jamais -2 au total.
    var bomb_team: String = _opponent_team(owner_team)
    var key_bomb: String = _tobi_bomb_key(owner_team)
    for bombed: YugitoCardActor in _living_cards(bomb_team).duplicate():
        var stacks: int = int(bombed.status_tags.get(key_bomb,0))
        if stacks <= 0:
            continue
        var remaining: int = maxi(0, stacks - 2)
        if remaining > 0:
            bombed.status_tags[key_bomb] = remaining
        else:
            bombed.status_tags.erase(key_bomb)
        _refresh_tobi_bomb_total(bombed)
    tobi_predictions[owner_team] = {}
    var tobi_owner: YugitoCardActor = _find_live_card(owner_team, "tobi")
    if tobi_owner != null:
        tobi_owner.status_tags.erase("tobi_prediction_armed")
        tobi_owner.refresh_status_badges()
        tobi_owner.refresh_status_visuals()
    if owner_team == "ally":
        _battle_log_set("TOBI : prédiction ratée — chaque Ninja adverse perd jusqu'à 2 bombes.")
    else:
        _battle_log_set("Tobi : une prédiction secrète échoue.")

func _shares_family(a_id: String, b_id: String) -> bool:
    for family_raw: Variant in SynergyDB.FAMILIES:
        var family: Array = family_raw as Array
        if family.has(a_id) and family.has(b_id):
            return true
    return false

func _trigger_karui_family_death(dead_actor: YugitoCardActor) -> void:
    if dead_actor == null:
        return
    for karui_actor: YugitoCardActor in _living_cards(dead_actor.team_name):
        if karui_actor.card_id != "karui" or karui_actor == dead_actor or not _shares_family(karui_actor.card_id, dead_actor.card_id):
            continue
        if int(karui_actor.status_tags.get("karui_hp_bonus",0)) <= 0:
            karui_actor.status_tags["karui_hp_bonus"] = 300
            karui_actor.base_max_hp += 300
            karui_actor.max_hp += 300
            karui_actor.hp += 300
        _set_special_status(karui_actor,"karui_electric_turns",2)
        karui_actor.refresh_status_badges()

func _special_attack_config(card_id: String) -> Dictionary:
    # Table synchronisée avec le bloc "Spéciales d'attaque standard" du moteur PC.
    var configs: Dictionary = {
        "hashirama": {"style":"ninjutsu", "bonus":300},
        "madara": {"style":"ninjutsu", "bonus":500},
        "nagato": {"style":"ninjutsu", "bonus":300},
        "obito": {"style":"ninjutsu", "bonus":300, "bypass":true},
        "itachi": {"style":"ninjutsu", "bonus":300},
        "killer_bee": {"style":"ninjutsu", "bonus":300},
        "gai": {"style":"taijutsu", "bonus":350},
        "minato": {"style":"ninjutsu", "bonus":300, "bypass":true},
        "naruto": {"style":"ninjutsu", "bonus":500},
        "sasuke": {"style":"ninjutsu", "bonus":300, "bypass":true, "absolute":true, "ignore_guard":true},
        "a_raikage": {"style":"taijutsu", "bonus":200},
        "sarutobi": {"style":"ninjutsu", "bonus":250, "force_advantage":true},
        "kakashi": {"style":"ninjutsu", "bonus":300, "bypass":true},
        "kabuto": {"style":"taijutsu", "bonus":300, "bypass":true, "absolute":true},
        "tsunade": {"style":"taijutsu", "bonus":300},
        "deidara": {"style":"ninjutsu", "bonus":300},
        "neji": {"style":"taijutsu", "bonus":250},
        "sakura": {"style":"taijutsu", "bonus":300},
        "sasori": {"style":"ninjutsu", "bonus":250},
        "hinata": {"style":"taijutsu", "bonus":200},
        "kiba": {"style":"taijutsu", "bonus":250},
        "shino": {"style":"ninjutsu", "bonus":200},
        "suigetsu": {"style":"ninjutsu", "bonus":200},
        "zabuza": {"style":"ninjutsu", "bonus":200},
        "kakuzu": {"style":"ninjutsu", "bonus":300, "force_advantage":true},
        "mifune": {"style":"taijutsu", "bonus":0, "bypass":true}
    }
    return configs.get(card_id, {}) as Dictionary

func _calculate_classic_damage(source: YugitoCardActor, target: YugitoCardActor, style: String, bonus: int = 0, ignore_defense: bool = false, force_advantage: bool = false) -> Dictionary:
    var advantage: bool = force_advantage or _element_advantage(source, target)
    var situational_bonus: int = bonus
    # Temari PC : +100 NIN sur une attaque Ninjutsu si elle N'A PAS l'avantage élémentaire.
    if source.card_id == "temari" and style == "ninjutsu" and not advantage:
        situational_bonus += 100
    if source.card_id == "chojuro":
        var chojuro_swing: int = 200 if battle_rng.randf() < 0.50 else -200
        situational_bonus += chojuro_swing
        source.status_tags["chojuro_last_swing"] = chojuro_swing
    var atk: int = _actor_effective_stat(source, style, target.stars) + situational_bonus
    var defense: int = 0 if ignore_defense else _actor_effective_stat(target, style, source.stars)
    var diff: int = atk - defense
    var damage: int = maxi(100, diff) if diff > 0 else 0
    if advantage and damage > 0:
        damage = int(round(float(damage) * 1.10)) + 150
    # IMPORTANT : le secours anti-zéro n'est PAS appliqué ici. Le moteur PC
    # l'applique seulement après les réductions défensives et juste avant les
    # boucliers. _apply_attack_damage() est l'unique endroit qui le fait.
    return {"damage": damage, "advantage": advantage, "atk": atk, "defense": defense}

func _zero_damage_pct(stars_value: float) -> float:
    if is_equal_approx(stars_value, 5.0): return 0.01
    if is_equal_approx(stars_value, 4.5): return 0.03
    if is_equal_approx(stars_value, 4.0): return 0.06
    if is_equal_approx(stars_value, 3.5): return 0.09
    return 0.12

func _preview_true_attack_damage(source: YugitoCardActor, target: YugitoCardActor, raw_amount: int) -> int:
    # Le scoring IA ne consomme aucun état défensif ; il doit néanmoins voir le
    # même plancher anti-zéro que l'attaque réelle, sinon il sous-évalue à tort
    # les affrontements contre Nagato/Raikage/etc.
    if raw_amount > 0 or source == null or target == null:
        return maxi(0, raw_amount)
    var bonus_floor: int = mini(100, maxi(0, int(round(float(target.max_hp) * _zero_damage_pct(source.stars)))))
    return 100 + bonus_floor

func _element_advantage(source: YugitoCardActor, target: YugitoCardActor) -> bool:
    var source_body: YugitoCardActor = _effect_actor(source)
    var target_body: YugitoCardActor = _effect_actor(target)
    if source_body == null or target_body == null:
        return false
    if target_body.card_id == "kakuzu":
        return false
    if source_body.card_id == "kakuzu":
        return true
    var beats: Dictionary = {"feu":"vent", "vent":"foudre", "foudre":"terre", "terre":"eau", "eau":"feu"}
    return str(beats.get(source_body.element_name, "")) == target_body.element_name

func _guard_target(target: YugitoCardActor, source: YugitoCardActor) -> YugitoCardActor:
    if target.card_id == "choji" or source.card_id == "mifune":
        return target
    for ally in _living_cards(target.team_name):
        if ally.card_id == "choji":
            return ally
    return target

func _apply_attack_damage(source: YugitoCardActor, target: YugitoCardActor, raw_amount: int, style: String, bypass_defensive: bool = false, absolute: bool = false, allow_overflow: bool = true, is_special_attack: bool = false, undodgeable: bool = false, zero_fallback: bool = false, counts_as_attack: bool = true, ignore_shield: bool = false, self_cost: bool = false) -> Dictionary:
    if target == null or target.defeated:
        return {"hp_damage":0, "overflow":0, "killed":false, "immune":true}

    var mifune_trancheur: bool = source != null and source.card_id == "mifune" and style == "taijutsu"
    # Le paramètre bypass correspond au bypass des PASSIFS défensifs du PC
    # (Minato l'obtient sur toutes ses attaques). Trancheur est particulier :
    # Mifune respecte encore inciblabilité/Sharingan, puis ignore les réductions.
    var bypass_passives: bool = (bypass_defensive or (source != null and source.card_id == "minato")) and not mifune_trancheur

    # Inciblabilité Classic : Mifune conserve cette règle. Chidori absolu et
    # les techniques PC marquées bypass (Minato/Obito/Kakashi) la traversent.
    if counts_as_attack and _is_actor_untargetable(target) and not absolute and not bypass_passives:
        return {"hp_damage":0, "overflow":0, "killed":false, "immune":true, "reason":"untargetable"}

    # Permutation du serpent : prochaine attaque totalement esquivée puis poison.
    if counts_as_attack and bool(target.status_tags.get("anko_serpent_armed", false)) and not absolute and not undodgeable:
        target.status_tags.erase("anko_serpent_armed")
        if source != null and is_instance_valid(source) and not source.defeated:
            _set_special_status(source, "anko_poison_turns", 4)
        target.refresh_status_badges()
        return {"hp_damage":0, "overflow":0, "killed":false, "immune":true, "reason":"anko_serpent"}

    # Haku : première attaque programmée après son entrée, 2 chances sur 3 d'être parée.
    if counts_as_attack and resolving_delayed_action and bool(target.status_tags.get("haku_entry_guard", false)) and not absolute and not undodgeable and (source == null or source.card_id != "mifune"):
        target.status_tags.erase("haku_entry_guard")
        if battle_rng.randf() < (2.0 / 3.0):
            target.refresh_status_badges()
            return {"hp_damage":0, "overflow":0, "killed":false, "immune":true, "reason":"haku_mirror"}

    # Shisui : 1 attaque sur 3 esquivée.
    if counts_as_attack and target.card_id == "shisui" and not absolute and not undodgeable and (source == null or source.card_id != "mifune"):
        if battle_rng.randf() < (1.0 / 3.0):
            return {"hp_damage":0, "overflow":0, "killed":false, "immune":true, "reason":"shisui_dodge"}

    # Sexy Jutsu : hommes incapables de toucher ; femmes x2 dégâts.
    if counts_as_attack and target.card_id == "konohamaru" and int(target.status_tags.get("konohamaru_sexy_turns",0)) > 0 and source != null and not absolute:
        if not _is_female_card(source.card_id):
            return {"hp_damage":0, "overflow":0, "killed":false, "immune":true, "reason":"sexy_jutsu"}

    # Passif de Konohamaru hors Sexy Jutsu : 50 % esquive puis riposte 350.
    if counts_as_attack and target.card_id == "konohamaru" and int(target.status_tags.get("konohamaru_sexy_turns",0)) <= 0 and not absolute and not undodgeable and (source == null or source.card_id != "mifune"):
        if battle_rng.randf() < 0.50:
            if source != null and not source.defeated:
                # PC : le Rasengan réflexe est 350 dégâts fixes normaux :
                # boucliers et survivances s'appliquent, aucun surplus joueur.
                _deal_fixed_status_damage(source, 350, "Rasengan réflexe", target)
            return {"hp_damage":0, "overflow":0, "killed":false, "immune":true, "reason":"konohamaru_dodge"}

    # Counter-switch PC : première attaque annulée après une vraie entrée A2 réactive.
    # Itachi applique Tsukuyomi, Sasuke arme immédiatement son verrou d'art et
    # Kakashi peut mémoriser la spéciale annulée. Le don de Yamato n'ajoute
    # aucun effet offensif : il ne fait qu'annuler l'attaque.
    if counts_as_attack and target.reactive_entry_guard and not absolute:
        target.reactive_entry_guard = false
        target.status_tags.erase("yamato_counter_gift")
        if target.card_id == "itachi" and source != null:
            if source.card_id not in ["killer_bee", "madara"]:
                source.disabled_turns = maxi(source.disabled_turns, 2)
                source.refresh_status_badges()
            _battle_log_set("COUNTER-SWITCH — Tsukuyomi : Itachi annule l'attaque de %s." % source.display_name)
        elif target.card_id == "sasuke" and source != null:
            _arm_sasuke_lock(target, source, style)
            _battle_log_set("COUNTER-SWITCH — Sharingan : Sasuke annule l'attaque et verrouille le %s de %s." % [style.to_upper(), source.display_name])
        elif target.card_id == "kakashi" and source != null:
            if is_special_attack and str(target.status_tags.get("copied_special_id", "")).is_empty():
                var source_special_id: String = source.card_id
                var source_special_data: Dictionary = _special_data_for_id(source_special_id)
                target.status_tags["copied_special_id"] = source_special_id
                target.status_tags["copied_special_name"] = str(source_special_data.get("special_name", "Spéciale copiée"))
                target.status_tags["copied_special_used"] = false
                target.refresh_status_badges()
            _battle_log_set("COUNTER-SWITCH — Permutation : Kakashi annule complètement l'attaque de %s." % source.display_name)
        else:
            _battle_log_set("COUNTER-SWITCH : %s annule la première attaque reçue." % target.display_name)
        return {"hp_damage":0, "overflow":0, "killed":false, "immune":true}

    # Sharingan : même art + même attaquant verrouillés pour 3 tours de cet attaquant.
    if counts_as_attack and target.card_id == "sasuke" and source != null and not absolute and not bypass_passives:
        var lock_key: String = "sasuke_lock_%s_%s" % [source.card_id, style]
        if int(target.status_tags.get(lock_key, 0)) > 0:
            return {"hp_damage":0, "overflow":0, "killed":false, "immune":true}

    var amount: int = maxi(0, raw_amount)
    if target.card_id == "konohamaru" and int(target.status_tags.get("konohamaru_sexy_turns",0)) > 0 and source != null and _is_female_card(source.card_id) and not absolute:
        amount *= 2

    # Trancheur de Mifune : l'inciblabilité a déjà été respectée plus haut,
    # puis toutes les réductions/passifs défensifs de dégâts sont ignorés.
    # La conversion/destruction du bouclier intervient plus bas, APRÈS le
    # secours anti-zéro, dans le même ordre que GameEngine PC.
    # Défenses de TECHNIQUE (Kankuro/Chiyo) : Minato/Obito/Kakashi ne les
    # ignorent pas. Seuls Chidori absolu et Trancheur les traversent côté PC.
    if not absolute and not mifune_trancheur and not self_cost:
        for ally in _living_cards(target.team_name):
            if ally != target and ally.card_id == "kankuro" and ally.kankuro_defense_active:
                amount = maxi(0, amount - 250)
                break
        if target.card_id != "chiyo" and amount > 0:
            var chiyo_guard: YugitoCardActor = _find_live_card(target.team_name, "chiyo")
            if chiyo_guard != null and bool(chiyo_guard.status_tags.get("chiyo_puppets_active",false)):
                amount = maxi(0, int(round(float(amount) * 0.80)))

    # Passifs défensifs : bypassés par Minato sur TOUTES ses attaques et par
    # les techniques explicitement marquées bypass, mais pas par Mifune avant
    # sa règle spéciale de Trancheur.
    if counts_as_attack and not bypass_passives and not absolute and not mifune_trancheur:
        if target.card_id == "gaara" and not bool(target.status_tags.get("gaara_guard_used_cycle", false)) and amount > 0:
            target.status_tags["gaara_guard_used_cycle"] = true
            amount = maxi(0, amount - 300)
        elif target.card_id == "sasuke" and not bool(target.status_tags.get("sasuke_guard_used_cycle", false)) and amount > 0:
            target.status_tags["sasuke_guard_used_cycle"] = true
            amount = maxi(0, amount - 150)
        elif target.card_id == "kurenai" and not bool(target.status_tags.get("kurenai_guard_used_cycle", false)) and amount > 0:
            target.status_tags["kurenai_guard_used_cycle"] = true
            amount = maxi(0, amount - 200)

        if target.card_id == "nagato" and style in ["ninjutsu", "genjutsu"]:
            amount = maxi(0, amount - 200)
        elif target.card_id == "a_raikage":
            amount = maxi(0, amount - 120)
        elif target.card_id == "suigetsu" and style == "taijutsu" and (source == null or source.element_name != "foudre"):
            amount = maxi(0, amount - 150)

    # YUGITO06 R5 : seulement une vraie attaque validée peut recevoir le
    # secours anti-zéro. Il intervient APRÈS Kankuro/Chiyo/réductions de stat
    # mais AVANT Kimimaro et les boucliers, exactement comme GameEngine PC.
    if counts_as_attack and zero_fallback and amount == 0 and source != null:
        var pct: float = _zero_damage_pct(source.stars)
        var bonus_floor: int = mini(100, maxi(0, int(round(float(target.max_hp) * pct))))
        amount = 100 + bonus_floor
        _battle_log_append("  •  ÉQUILIBRAGE %g★ : %d dégâts de secours" % [source.stars, amount])

    # Tombé sur un os arrive après le secours anti-zéro côté PC.
    if target.card_id == "kimimaro" and amount > 0 and not absolute and not self_cost:
        amount = maxi(0, int(round(float(amount) * 0.75)))

    # Trancheur détruit ensuite bouclier visible + bouclier caché Kurenai et
    # convertit 50 % de leur valeur en dégâts supplémentaires.
    if mifune_trancheur:
        var mifune_shield: int = target.shield + int(target.status_tags.get("kurenai_hidden_shield", 0))
        if mifune_shield > 0:
            amount += int(round(float(mifune_shield) * 0.50))
            target.shield = 0
            target.status_tags.erase("kurenai_hidden_shield")
            target._refresh_hp_label()

    var absorbed: int = 0
    if not absolute and not mifune_trancheur and not ignore_shield and not self_cost and target.shield > 0 and amount > 0:
        absorbed = mini(target.shield, amount)
        target.shield -= absorbed
        amount -= absorbed
        target._refresh_hp_label()

    # Bouclier caché de Kurenai : absorbe sans apparaître dans le HUD adverse.
    if not absolute and not mifune_trancheur and not ignore_shield and not self_cost and amount > 0 and int(target.status_tags.get("kurenai_hidden_shield", 0)) > 0:
        var hidden: int = int(target.status_tags.get("kurenai_hidden_shield", 0))
        var hidden_absorbed: int = mini(hidden, amount)
        hidden -= hidden_absorbed
        amount -= hidden_absorbed
        if hidden <= 0:
            target.status_tags.erase("kurenai_hidden_shield")
        else:
            target.status_tags["kurenai_hidden_shield"] = hidden

    # Multi-clonage Tobirama : une attaque sur deux ne conserve que 25 % du dégât HP.
    if counts_as_attack and target.card_id == "tobirama" and amount > 0 and not absolute and (source == null or source.card_id != "mifune"):
        var tcount: int = int(target.status_tags.get("tobirama_attack_counter",0)) + 1
        target.status_tags["tobirama_attack_counter"] = tcount
        if tcount % 2 == 0:
            amount = maxi(1, int(round(float(amount) * 0.25)))

    var hp_before: int = target.hp
    var overflow: int = maxi(0, amount - hp_before) if allow_overflow else 0
    var hp_damage: int = mini(hp_before, amount)

    # Détruire le clone de Gengetsu ne tue jamais la carte originale et ne génère aucun surplus.
    if hp_damage >= hp_before and hp_before > 0 and bool(target.status_tags.get("gengetsu_clone_active",false)):
        _restore_gengetsu_clone(target,false)
        return {"hp_damage":hp_before,"overflow":0,"killed":false,"immune":false,"survival":"gengetsu_clone"}

    # Protection Doton : chaque AUTRE allié peut annuler une fois un impact létal.
    if hp_damage >= hp_before and hp_before > 0 and not absolute and not self_cost and target.card_id != "kurotsuchi" and not bool(target.status_tags.get("kurotsuchi_guard_used",false)):
        var kuro: YugitoCardActor = _find_live_card(target.team_name, "kurotsuchi")
        if kuro != null:
            target.status_tags["kurotsuchi_guard_used"] = true
            target.refresh_status_badges()
            return {"hp_damage":0,"overflow":0,"killed":false,"immune":true,"survival":"kurotsuchi"}

    # Survies Classic : elles interviennent avant le K.O. final. Les techniques
    # absolues (ex. Chidori) les traversent.
    if hp_damage >= hp_before and hp_before > 0 and not absolute:
        if counts_as_attack and target.card_id == "onoki" and not bool(target.status_tags.get("survival_used", false)) and not mifune_trancheur:
            target.status_tags["survival_used"] = true
            return {"hp_damage":0, "overflow":0, "killed":false, "immune":true, "survival":"onoki"}
        if target.card_id == "danzo" and not bool(target.status_tags.get("survival_used", false)):
            target.status_tags["survival_used"] = true
            target.set_hp(1)
            if allow_overflow: _apply_player_overflow(target.team_name, overflow)
            return {"hp_damage":maxi(0,hp_before-1), "overflow":overflow, "killed":false, "immune":false, "survival":"danzo"}
        if target.card_id == "orochimaru" and not bool(target.status_tags.get("survival_used", false)):
            target.status_tags["survival_used"] = true
            target.set_hp(mini(target.max_hp, 250))
            if allow_overflow: _apply_player_overflow(target.team_name, overflow)
            return {"hp_damage":maxi(0,hp_before-target.hp), "overflow":overflow, "killed":false, "immune":false, "survival":"orochimaru"}
        if target.card_id == "hidan" and not bool(target.status_tags.get("survival_used", false)):
            target.status_tags["survival_used"] = true
            target.set_hp(mini(target.max_hp, 200))
            if allow_overflow: _apply_player_overflow(target.team_name, overflow)
            return {"hp_damage":maxi(0,hp_before-target.hp), "overflow":overflow, "killed":false, "immune":false, "survival":"hidan"}
        if target.card_id == "kakuzu":
            var hearts_left: int = int(target.status_tags.get("kakuzu_revivals_left", 2))
            if hearts_left > 0:
                target.status_tags["kakuzu_revivals_left"] = hearts_left - 1
                target.set_hp(target.max_hp)
                target.disabled_turns = 0
                target.status_tags.erase("shino_poisoned")
                target.status_tags.erase("hanzo_poisoned")
                target.status_tags.erase("delayed_damage")
                target.status_tags.erase("doom_turns")
                target.status_tags.erase("doom_source_team")
                target.status_tags.erase("doom_source_uid")
                target.status_tags.erase("kisame_prisoned_by_uid")
                target.refresh_status_badges()
                if allow_overflow: _apply_player_overflow(target.team_name, overflow)
                return {"hp_damage":hp_before, "overflow":overflow, "killed":false, "immune":false, "survival":"kakuzu"}
        # Karasu : première mort évitée ; les dégâts déjà produits peuvent néanmoins
        # avoir généré un surplus sur une vraie attaque, comme dans le moteur PC.
        if target.card_id == "kankuro" and hp_damage >= hp_before and not target.kankuro_decoy_used and not absolute:
            target.kankuro_decoy_used = true
            target.set_hp(target.max_hp)
            if allow_overflow:
                _apply_player_overflow(target.team_name, overflow)
            return {"hp_damage": hp_before, "overflow":overflow, "killed":false, "immune":false, "karasu":true, "absorbed":absorbed}

        if target.card_id == "mu" and not bool(target.status_tags.get("mu_division_used", false)):
            target.status_tags["mu_division_used"] = true
            target.set_hp(target.max_hp)
            target.stat_buffs["ninjutsu"] = int(target.stat_buffs.get("ninjutsu",0)) - 450
            target.special_used = true
            target.disabled_turns = 0
            target.status_tags.erase("shino_poisoned")
            target.status_tags.erase("hanzo_poisoned")
            target.status_tags.erase("shizune_poisoned")
            target.status_tags.erase("delayed_damage")
            target.status_tags.erase("doom_turns")
            target.status_tags.erase("doom_source_team")
            target.status_tags.erase("doom_source_uid")
            target.status_tags.erase("kisame_prisoned_by_uid")
            target.status_tags.erase("sealed_turns")
            target.refresh_status_badges()
            if allow_overflow: _apply_player_overflow(target.team_name, overflow)
            return {"hp_damage":hp_before, "overflow":overflow, "killed":false, "immune":false, "survival":"mu"}

    # Dernier soin de Chiyo puis Réincarnation de Kabuto : après les survies personnelles.
    # Côté PC, le coup a déjà réellement atteint 0 PV avant le sauvetage : il peut
    # donc casser les Ombres de Shikamaru, déclencher les effets "sur dégâts HP"
    # et produire un surplus joueur si c'était une vraie attaque. On reproduit
    # ces conséquences sans faire passer le Node Godot par un état freed/KO.
    if hp_damage >= hp_before and hp_before > 0 and not absolute:
        var rescued_by: String = ""
        if target.card_id != "chiyo":
            var chiyo_rescuer: YugitoCardActor = _find_live_card(target.team_name, "chiyo")
            if chiyo_rescuer != null and not bool(chiyo_rescuer.status_tags.get("chiyo_passive_used",false)):
                chiyo_rescuer.status_tags["chiyo_passive_used"] = true
                rescued_by = "chiyo"
        if rescued_by.is_empty():
            var kabuto_rescuer: YugitoCardActor = _find_live_card(target.team_name, "kabuto")
            if target.card_id != "kabuto" and kabuto_rescuer != null and not bool(kabuto_rescuer.status_tags.get("kabuto_reanimation_used",false)):
                kabuto_rescuer.status_tags["kabuto_reanimation_used"] = true
                rescued_by = "kabuto"
        if not rescued_by.is_empty():
            if target.card_id == "shikamaru":
                _clear_shadow_stuns_from(target)
            if counts_as_attack and target.card_id == "sai" and source != null and style in ["taijutsu", "ninjutsu", "genjutsu"]:
                source.add_timed_modifier(style, -200, 2, "sai_%s" % target.card_id)
            if allow_overflow:
                _apply_player_overflow(target.team_name, overflow)
            target.set_hp(target.max_hp)
            if rescued_by == "kabuto":
                var kabuto_used: YugitoCardActor = _find_live_card(target.team_name, "kabuto")
                if kabuto_used != null:
                    kabuto_used.refresh_status_badges()
                _battle_log_append("  •  RÉINCARNATION DES ÂMES : Kabuto ramène %s à tous ses PV" % target.display_name)
            elif rescued_by == "chiyo":
                _battle_log_append("  •  DERNIER SOUFFLE : Chiyo sauve %s" % target.display_name)
            return {"hp_damage":hp_before,"overflow":overflow,"killed":false,"immune":false,"survival":rescued_by}

    target.apply_damage(hp_damage)
    if hp_damage > 0 and not target.defeated:
        _apply_threshold_passives(target)
    if allow_overflow:
        _apply_player_overflow(target.team_name, overflow)

    if counts_as_attack and target.card_id == "sasuke" and source != null and not absolute:
        _arm_sasuke_lock(target, source, style)

    # Shikamaru perd instantanément toutes ses Possessions des ombres au moindre
    # dégât de PV réel.
    if target.card_id == "shikamaru" and hp_damage > 0:
        _clear_shadow_stuns_from(target)

    # Sai : l'attaquant perd 200 dans l'art utilisé pendant 2 de ses tours.
    if counts_as_attack and target.card_id == "sai" and source != null and style in ["taijutsu", "ninjutsu", "genjutsu"]:
        source.add_timed_modifier(style, -200, 2, "sai_%s" % target.card_id)

    # Sakura : soutien/sustain PC. Les soins sont appliqués APRÈS les dégâts.
    if hp_damage > 0 and not target.defeated:
        if target.card_id == "sakura":
            target.heal(maxi(1, int(round(float(hp_damage) * 0.25))))
            for ally in _living_cards(target.team_name):
                if ally != target:
                    ally.heal(maxi(1, int(round(float(hp_damage) * 0.10))))
        else:
            var sakura: YugitoCardActor = null
            for ally in _living_cards(target.team_name):
                if ally.card_id == "sakura":
                    sakura = ally
                    break
            if sakura != null:
                target.heal(maxi(1, int(round(float(hp_damage) * 0.25))))

        # Régénération organique de Zetsu : 25 % des PV réellement perdus par
        # une AUTRE carte alliée lors d'une attaque, sans résurrection.
        if counts_as_attack and target.card_id != "zetsu" and source != null and not target.defeated:
            var zetsu_healer: YugitoCardActor = _find_live_card(target.team_name,"zetsu")
            if zetsu_healer != null:
                target.heal(maxi(1,int(round(float(hp_damage)*0.25))))

    return {"hp_damage":hp_damage, "overflow":overflow, "killed":target.defeated, "immune":false, "absorbed":absorbed, "defensive_bypass": (bypass_passives or mifune_trancheur or absolute)}

func _clear_shadow_stuns_from(source: YugitoCardActor) -> void:
    if source == null:
        return
    for actor in card_actors:
        if actor == null or not is_instance_valid(actor):
            continue
        var by_uid: bool = int(actor.status_tags.get("shadow_source_uid", 0)) == source.battle_uid and source.battle_uid > 0
        var by_id: bool = str(actor.status_tags.get("shadow_source", "")) == source.card_id
        if by_uid or by_id:
            actor.status_tags.erase("shadow_source")
            actor.status_tags.erase("shadow_source_uid")
            actor.status_tags.erase("shadow_turns")
            actor.status_tags.erase("shadow_turns_skip_tick")
            actor.status_tags.erase("shadow_fresh_application")
            # IMPORTANT : ne jamais remettre disabled_turns à zéro ici. Un STUN
            # Shisui/Ino/etc. est une autre source et doit continuer.
            actor.refresh_status_badges()

func _apply_player_overflow(team_name: String, amount: int) -> void:
    if amount <= 0:
        return
    if team_name == "ally":
        ally_player_hp = maxi(0, ally_player_hp - amount)
    else:
        enemy_player_hp = maxi(0, enemy_player_hp - amount)

func _after_damage_resolution(source: YugitoCardActor, target: YugitoCardActor, result: Dictionary) -> void:
    if bool(result.get("karasu", false)):
        _battle_log_append("  •  KARASU détruite : Kankuro revient à tous ses PV.")
    if int(result.get("overflow", 0)) > 0:
        _battle_log_append("  •  SURPLUS %d PV joueur" % int(result.get("overflow", 0)))
    if bool(result.get("killed", false)):
        _battle_log_append("  •  K.O.")
        _play_sfx("res://assets/audio/result/ko.mp3", -9.0)

        # Passifs de mort Classic.
        if target.card_id == "kushina" and source != null and is_instance_valid(source) and source != target and not source.defeated and source.card_id != "madara":
            _set_special_status(source,"sealed_turns",4)
            _battle_log_append("  •  Kushina SCELLE son meurtrier 4T")
        if target.card_id == "shizune" and source != null and is_instance_valid(source) and source != target and not source.defeated:
            _set_special_status(source,"shizune_paralysis_turns",3)
            _battle_log_append("  •  Shizune PARALYSE son meurtrier 3T")
        if target.card_id == "chiyo" and not bool(target.status_tags.get("chiyo_passive_used",false)):
            target.status_tags["chiyo_passive_used"] = true
            var heal_targets: Array[YugitoCardActor] = []
            for heal_candidate: YugitoCardActor in _living_cards(target.team_name):
                if heal_candidate != target and heal_candidate.hp < heal_candidate.max_hp:
                    heal_targets.append(heal_candidate)
            if not heal_targets.is_empty():
                var healed_chiyo: YugitoCardActor = heal_targets[battle_rng.randi_range(0, heal_targets.size() - 1)]
                healed_chiyo.set_hp(healed_chiyo.max_hp)
                _battle_log_append("  •  Dernier souffle de Chiyo : %s soigné à fond" % healed_chiyo.display_name)
        _trigger_karui_family_death(target)
        if target.card_id == "tobi":
            var dead_tobi_team: String = target.team_name
            for bombed: YugitoCardActor in _living_cards(_opponent_team(dead_tobi_team)):
                bombed.status_tags.erase(_tobi_bomb_key(dead_tobi_team))
                _refresh_tobi_bomb_total(bombed)
            tobi_predictions[dead_tobi_team] = {}
            if dead_tobi_team == "ally":
                tobi_bomb_pending_team = ""

        # Les liens de terrain cessent au K.O. DÉFINITIF immédiatement, même si
        # aucune réserve n'existe. P18 ne faisait le nettoyage que dans
        # _replace_actor(), ce qui laissait notamment Jashin/Prison aqueuse
        # actifs pour toujours lorsqu'un source mourait avec réserve vide.
        _cleanup_context_links_for_departure(target)
        _cancel_plans_for_actor(target)
        _queue_death_replacement(target)
    _update_team_status()
    _refresh_selection_panel()
    _check_victory_state()

func _play_special_sound(card_id: String) -> void:
    var special_path: String = "res://assets/audio/pc_special/%s/special.mp3" % card_id
    if ResourceLoader.exists(special_path):
        _play_sfx(special_path, -5.0)
    else:
        _play_action_sound("special")

func _living_cards(team_name: String) -> Array[YugitoCardActor]:
    var result: Array[YugitoCardActor] = []
    for actor in card_actors:
        if actor.team_name == team_name and not actor.defeated:
            result.append(actor)
    return result

func _opponent_team(team_name: String) -> String:
    return "enemy" if team_name == "ally" else "ally"

func _check_victory_state() -> void:
    if duel_finished:
        return
    var result_text: String = ""
    var victory: bool = false
    if enemy_player_hp <= 0:
        result_text = "VICTOIRE : les PV joueur adverses sont à 0."
        victory = true
    elif ally_player_hp <= 0:
        result_text = "DÉFAITE : tes PV joueur sont à 0."
    elif _living_cards("enemy").is_empty() and enemy_reserve.is_empty() and not _replacement_overlay_active():
        result_text = "VICTOIRE : l'adversaire n'a plus aucun Ninja ni réserve."
        victory = true
    elif _living_cards("ally").is_empty() and ally_reserve.is_empty() and not _replacement_overlay_active():
        result_text = "DÉFAITE : tu n'as plus aucun Ninja ni réserve."
    if result_text.is_empty():
        return
    duel_finished = true
    resolving_action = true
    _battle_log_set(result_text)
    _play_sfx("res://assets/audio/result/victory.mp3" if victory else "res://assets/audio/result/defeat.mp3", -6.0)
    _refresh_action_buttons()
    _show_duel_end_overlay(victory,result_text)

func _field_departure_lock_reason(actor: YugitoCardActor) -> String:
    if actor == null or not is_instance_valid(actor) or actor.defeated:
        return ""
    if int(actor.status_tags.get("rooted_turns", 0)) > 0:
        return "ENRACINÉ"
    if int(actor.status_tags.get("shadow_turns", 0)) > 0:
        return "OMBRES DE SHIKAMARU"
    if int(actor.status_tags.get("kisame_prisoned_by_uid", 0)) > 0:
        return "PRISON AQUEUSE"
    if int(actor.status_tags.get("sealed_turns", 0)) > 0:
        return "SCELLÉ PAR KUSHINA"
    if int(actor.status_tags.get("doom_turns", 0)) > 0:
        return "RITUEL DE JASHIN"
    return ""

func _can_leave_field_voluntarily(actor: YugitoCardActor) -> bool:
    return _field_departure_lock_reason(actor).is_empty()

func _execute_planned_switch(descriptor: Dictionary, phase_label: String) -> void:
    var outgoing: YugitoCardActor = _resolve_descriptor_source(descriptor)
    var incoming_id: String = str(descriptor.get("incoming_id", ""))
    if outgoing == null or outgoing.defeated:
        _battle_log_set("%s perdue : le Ninja à échanger n'est plus sur le terrain." % phase_label)
        _complete_resolution_step()
        return
    var departure_lock: String = _field_departure_lock_reason(outgoing)
    if not departure_lock.is_empty():
        _battle_log_set("%s perdue : %s est verrouillé sur le terrain (%s) et ne peut pas effectuer de Switch." % [phase_label, outgoing.display_name, departure_lock])
        _complete_resolution_step()
        return
    _explode_tobi_bombs(_opponent_team(outgoing.team_name), outgoing, "BOMBES TOBI • SWITCH")
    if outgoing.defeated:
        _battle_log_set("%s • Switch annulé : les bombes de Tobi mettent %s K.O." % [phase_label,outgoing.display_name])
        _complete_resolution_step(0.04)
        return
    var reserve: Array[String] = ally_reserve if outgoing.team_name == "ally" else enemy_reserve
    if not reserve.has(incoming_id):
        _battle_log_set("%s perdue : la carte entrante n'est plus dans la réserve." % phase_label)
        _complete_resolution_step()
        return

    reserve.erase(incoming_id)
    if not reserve.has(outgoing.card_id):
        reserve.append(outgoing.card_id)
    var reactive: bool = resolving_delayed_action
    var incoming_name: String = str((cards_by_id.get(incoming_id, {}) as Dictionary).get("name", incoming_id))
    _battle_log_set("%s • Échange %s → %s%s" % [phase_label, outgoing.display_name, incoming_name, " • RÉACTIF" if reactive else ""])
    _replace_actor(outgoing, incoming_id, false, reactive)
    # P49 : ne jamais conserver une référence de sélection vers la carte sortie.
    # C'était la cause du tour tactile bloqué après certains Switch (ex. Kabuto → Temari).
    if outgoing.team_name == "ally":
        selected_actor = null
        current_action = ""
        free_action_mode = false
        inspection_actor = null
        if inspection_overlay != null:
            inspection_overlay.visible = false
        for selectable_card: YugitoCardActor in card_actors:
            selectable_card.set_selected(false)
        _refresh_selection_panel()
        _refresh_action_buttons()
    _refresh_reserve_labels()
    var timer: SceneTreeTimer = get_tree().create_timer(0.22)
    timer.timeout.connect(_complete_resolution_step.bind(0.04))

func _build_status_link_layer() -> void:
    status_link_root = Node2D.new()
    status_link_root.name = "PersistentStatusLinks"
    status_link_root.z_index = 24
    add_child(status_link_root)

func _quadratic_points(start_pos: Vector2, end_pos: Vector2, bend_strength: float = 0.12) -> PackedVector2Array:
    var delta: Vector2 = end_pos - start_pos
    var dist: float = maxf(1.0, delta.length())
    var perp: Vector2 = Vector2(-delta.y, delta.x).normalized()
    var bend: float = clampf(dist * bend_strength, 38.0, 84.0)
    var control: Vector2 = (start_pos + end_pos) * 0.5 + perp * bend
    var pts := PackedVector2Array()
    for i: int in range(19):
        var t: float = float(i) / 18.0
        var u: float = 1.0 - t
        pts.append(u * u * start_pos + 2.0 * u * t * control + t * t * end_pos)
    return pts

func _status_link_anchor(actor: YugitoCardActor, toward_gap: bool = true) -> Vector2:
    # Les deux rangées se font face : on accroche la liaison au bord intérieur
    # de la carte, jamais au centre de l'illustration.
    var half_w: float = 126.0 * actor.scale.x
    var card_h: float = 396.0 * actor.scale.y
    var x: float = actor.global_position.x + half_w
    var y: float = actor.global_position.y
    if actor.team_name == "enemy":
        y += card_h + 5.0
    else:
        y -= 5.0
    return Vector2(x, y)

func _add_status_link(source: YugitoCardActor, target: YugitoCardActor, color: Color, width: float, label_text: String) -> void:
    # P35 MOBILE CLEAN LINK : aucune ligne persistante ne traverse le plateau.
    # Une relation terrain est représentée par deux marqueurs locaux discrets
    # (SOURCE / CIBLE) collés au bord des cartes concernées.
    if status_link_root == null or source == null or target == null or source.defeated or target.defeated:
        return
    var source_anchor: Vector2 = _status_link_anchor(source)
    var target_anchor: Vector2 = _status_link_anchor(target)
    var marker_text: String = label_text if not label_text.is_empty() else "LIEN"
    for marker_data: Dictionary in [
        {"pos":source_anchor, "suffix":" • SOURCE"},
        {"pos":target_anchor, "suffix":" • CIBLE"}
    ]:
        var marker_pos: Vector2 = marker_data.get("pos", Vector2.ZERO)
        var panel := Panel.new()
        panel.position = marker_pos + Vector2(-48.0,-10.0)
        panel.size = Vector2(96,20)
        panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
        panel.z_index = 55
        var box := StyleBoxFlat.new()
        box.bg_color = Color(0.018,0.026,0.038,0.90)
        box.border_color = Color(color.r,color.g,color.b,0.78)
        box.set_border_width_all(1)
        box.corner_radius_top_left = 7
        box.corner_radius_top_right = 7
        box.corner_radius_bottom_left = 7
        box.corner_radius_bottom_right = 7
        panel.add_theme_stylebox_override("panel",box)
        status_link_root.add_child(panel)
        var label := Label.new()
        label.text = "%s%s" % [marker_text,str(marker_data.get("suffix",""))]
        label.position = Vector2(3,0)
        label.size = Vector2(90,20)
        label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
        label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
        label.add_theme_font_size_override("font_size",7)
        label.add_theme_color_override("font_color",Color(color.r,color.g,color.b,0.96))
        label.mouse_filter = Control.MOUSE_FILTER_IGNORE
        panel.add_child(label)

func _has_dynamic_status_links() -> bool:
    for actor: YugitoCardActor in card_actors:
        if actor == null or not is_instance_valid(actor) or actor.defeated:
            continue
        if actor.card_id == "ino" and not str(actor.status_tags.get("ino_target","")).is_empty():
            return true
        if int(actor.status_tags.get("shadow_turns",0)) > 0:
            return true
        if int(actor.status_tags.get("kisame_prisoned_by_uid",0)) > 0:
            return true
        if int(actor.status_tags.get("doom_turns",0)) > 0:
            return true
    return false

func _refresh_persistent_status_links() -> void:
    if status_link_root == null:
        return
    for child: Node in status_link_root.get_children():
        child.queue_free()
    # Synchronise aussi l'identité visuelle d'Ino avec le corps réellement
    # contrôlé afin que portrait/stats changent comme dans le client Tkinter.
    for actor: YugitoCardActor in card_actors:
        if actor == null or not is_instance_valid(actor) or actor.defeated:
            continue
        if actor.card_id == "ino":
            var body: YugitoCardActor = _ino_controlled_body(actor)
            if body != null:
                actor.status_tags["ino_visual_tai"] = _actor_effective_stat(body, "taijutsu")
                actor.status_tags["ino_visual_nin"] = _actor_effective_stat(body, "ninjutsu")
                actor.status_tags["ino_visual_gen"] = _actor_effective_stat(body, "genjutsu")
                actor.status_tags["ino_visual_element"] = body.element_name
                actor.status_tags["ino_visual_stars"] = body.stars
                actor.status_tags["ino_target_name"] = body.display_name
                actor.refresh_dynamic_identity()
        var shadow_uid: int = int(actor.status_tags.get("shadow_source_uid", 0))
        if int(actor.status_tags.get("shadow_turns", 0)) > 0 and shadow_uid > 0:
            var shadow_source: YugitoCardActor = _resolve_actor_uid(shadow_uid)
            if shadow_source != null:
                _add_status_link(shadow_source, actor, Color("7f6aa8"), 3.4, "OMBRES")
        var prison_uid: int = int(actor.status_tags.get("kisame_prisoned_by_uid", 0))
        if prison_uid > 0:
            var prison_source: YugitoCardActor = _resolve_actor_uid(prison_uid)
            if prison_source != null:
                _add_status_link(prison_source, actor, Color("55b6f2"), 2.8, "PRISON")
        var doom_uid: int = int(actor.status_tags.get("doom_source_uid", 0))
        if int(actor.status_tags.get("doom_turns", 0)) > 0 and doom_uid > 0:
            var doom_source: YugitoCardActor = _resolve_actor_uid(doom_uid)
            if doom_source != null:
                _add_status_link(doom_source, actor, Color("d95b5b"), 2.6, "JASHIN")

func _spawn_descriptor_impact(uid: int, accent: Color, action_id: String) -> void:
    var actor: YugitoCardActor = _resolve_actor_uid(uid)
    if actor == null or not is_instance_valid(actor):
        return
    actor.play_hit_fx(accent)
    _spawn_impact_fx(actor.global_position, accent, action_id)

func _apply_shikamaru_shadows(source: YugitoCardActor, free_target: YugitoCardActor) -> int:
    if source == null or not is_instance_valid(source) or source.defeated:
        return 0
    var free_uid: int = free_target.battle_uid if free_target != null else 0
    var enemy_team: String = _opponent_team(source.team_name)
    var linked_count: int = 0
    for enemy: YugitoCardActor in _living_cards(enemy_team):
        if enemy == null or enemy.battle_uid == free_uid:
            continue
        var body: YugitoCardActor = _effect_actor(enemy)
        if body == null or body.card_id in ["killer_bee", "madara"]:
            continue
        body.status_tags["shadow_source"] = source.card_id
        body.status_tags["shadow_source_uid"] = source.battle_uid
        body.status_tags["shadow_turns"] = maxi(3, int(body.status_tags.get("shadow_turns", 0)))
        # P35 : garde explicite contre le premier tick suivant l'application,
        # indispensable quand la technique vient d'une A2 juste avant start_turn.
        body.status_tags["shadow_turns_skip_tick"] = true
        body.status_tags["shadow_fresh_application"] = true
        body.refresh_status_badges()
        body.force_refresh_status_visuals()
        linked_count += 1
    # P31.1 MOBILE LOCK : l'A2 passe par des timers/animations. Sur certains
    # appareils, le cache visuel pouvait ne pas reconstruire le bandeau au
    # frame suivant alors que shadow_turns était bien posé. On resynchronise
    # donc explicitement les deux extrémités après l'application.
    _schedule_shikamaru_mobile_visual_sync(source.battle_uid)
    return linked_count

func _schedule_shikamaru_mobile_visual_sync(source_uid: int) -> void:
    call_deferred("_refresh_shikamaru_mobile_visuals", source_uid)
    var timer: SceneTreeTimer = get_tree().create_timer(0.08)
    timer.timeout.connect(_refresh_shikamaru_mobile_visuals.bind(source_uid))

func _refresh_shikamaru_mobile_visuals(source_uid: int) -> void:
    var source: YugitoCardActor = _resolve_actor_uid(source_uid)
    if source == null or source.defeated:
        return
    var enemy_team: String = _opponent_team(source.team_name)
    for actor: YugitoCardActor in _living_cards(enemy_team):
        if actor == null or not is_instance_valid(actor):
            continue
        if int(actor.status_tags.get("shadow_source_uid", 0)) != source_uid:
            continue
        if int(actor.status_tags.get("shadow_turns", 0)) <= 0:
            continue
        actor.refresh_status_badges()
        actor.force_refresh_status_visuals()
    _refresh_persistent_status_links()

func _spawn_shikamaru_cast_fx(source: YugitoCardActor, free_target: YugitoCardActor, duration: float) -> void:
    # P35 : le cast lui-même reste lisible sans tracer de câble sur les portraits.
    # On pulse simplement Shikamaru puis les deux cartes prises par les Ombres.
    if source == null:
        return
    source.play_cast_fx(Color("a18bd2"))
    var free_uid: int = free_target.battle_uid if free_target != null else 0
    var enemy_team: String = _opponent_team(source.team_name)
    for candidate: YugitoCardActor in _living_cards(enemy_team):
        if candidate == null or candidate.battle_uid == free_uid:
            continue
        var body: YugitoCardActor = _effect_actor(candidate)
        if body == null or body.card_id in ["killer_bee","madara"]:
            continue
        body.play_hit_fx(Color("7f6aa8"))
    if free_target != null:
        var free_label := Label.new()
        free_label.text = "CIBLE LIBRE"
        free_label.position = free_target.global_position + Vector2(18,-28)
        free_label.size = Vector2(92,20)
        free_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
        free_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
        free_label.add_theme_font_size_override("font_size",8)
        free_label.add_theme_color_override("font_color",Color("d7d1e5"))
        free_label.z_index = 70
        free_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
        add_child(free_label)
        var ftw: Tween = create_tween()
        ftw.tween_interval(maxf(0.20,duration*0.55))
        ftw.tween_property(free_label,"modulate",Color(1,1,1,0),maxf(0.16,duration*0.35))
        ftw.finished.connect(free_label.queue_free)

func _spawn_interception_fx(original_target: YugitoCardActor, choji: YugitoCardActor) -> void:
    if original_target == null or choji == null:
        return
    var label := Label.new()
    label.text = "EXPANSION AKIMICHI\nCHOJI INTERCEPTE"
    label.position = choji.global_position - Vector2(94, 64)
    label.size = Vector2(188, 46)
    label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    label.add_theme_font_size_override("font_size", 11)
    label.add_theme_color_override("font_color", Color("ffe59a"))
    label.add_theme_color_override("font_shadow_color", Color(0,0,0,0.95))
    label.add_theme_constant_override("shadow_offset_x", 2)
    label.add_theme_constant_override("shadow_offset_y", 2)
    label.mouse_filter = Control.MOUSE_FILTER_IGNORE
    label.z_index = 46
    add_child(label)
    choji.play_intercept_fx()
    var tw: Tween = create_tween()
    tw.tween_property(label, "modulate", Color(1,1,1,0), 0.72).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
    tw.finished.connect(label.queue_free)

func _spawn_projectile_fx(start_pos: Vector2, end_pos: Vector2, accent: Color, action_id: String, duration: float) -> void:
    # P20 / Classic : courbe visible + glow + projectile mobile. La trajectoire
    # reçoit déjà la cible effective (Choji compris).
    var points: PackedVector2Array = _quadratic_points(start_pos, end_pos, 0.12)
    var glow := Line2D.new()
    glow.z_index = 40
    glow.width = 10.0 if action_id != "special" else 13.0
    glow.default_color = Color(accent.r * 0.38, accent.g * 0.38, accent.b * 0.38, 0.58)
    glow.begin_cap_mode = Line2D.LINE_CAP_ROUND
    glow.end_cap_mode = Line2D.LINE_CAP_ROUND
    glow.points = points
    add_child(glow)
    var line := Line2D.new()
    line.z_index = 41
    line.width = 3.8 if action_id != "special" else 5.2
    line.default_color = Color(accent.r, accent.g, accent.b, 0.98)
    line.begin_cap_mode = Line2D.LINE_CAP_ROUND
    line.end_cap_mode = Line2D.LINE_CAP_ROUND
    line.points = points
    add_child(line)

    # PathFollow2D donne le même ressenti que l'orbe Tkinter qui voyage
    # réellement le long de la courbe au lieu d'un simple trait statique.
    var path := Path2D.new()
    path.z_index = 44
    var curve := Curve2D.new()
    for point: Vector2 in points:
        curve.add_point(point)
    path.curve = curve
    add_child(path)
    var follow := PathFollow2D.new()
    follow.rotates = false
    follow.loop = false
    path.add_child(follow)
    var orb_glow := Polygon2D.new()
    var glow_poly := PackedVector2Array()
    var core_poly := PackedVector2Array()
    for i: int in range(18):
        var a: float = TAU * float(i) / 18.0
        glow_poly.append(Vector2(cos(a), sin(a)) * (14.0 if action_id == "special" else 11.0))
        core_poly.append(Vector2(cos(a), sin(a)) * (8.0 if action_id == "special" else 6.0))
    orb_glow.polygon = glow_poly
    orb_glow.color = Color(accent.r, accent.g, accent.b, 0.28)
    follow.add_child(orb_glow)
    var orb := Polygon2D.new()
    orb.polygon = core_poly
    orb.color = accent.lightened(0.16)
    follow.add_child(orb)
    var white_core := Polygon2D.new()
    var white_poly := PackedVector2Array()
    for i: int in range(14):
        var wa: float = TAU * float(i) / 14.0
        white_poly.append(Vector2(cos(wa), sin(wa)) * (3.4 if action_id == "special" else 2.6))
    white_core.polygon = white_poly
    white_core.color = Color(1,1,1,0.92)
    follow.add_child(white_core)

    var travel: Tween = create_tween()
    travel.tween_property(follow, "progress_ratio", 1.0, maxf(0.12, duration * 0.92)).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
    travel.tween_property(orb_glow, "modulate", Color(1,1,1,0), maxf(0.04, duration * 0.08))
    travel.parallel().tween_property(orb, "modulate", Color(1,1,1,0), maxf(0.04, duration * 0.08))
    travel.parallel().tween_property(white_core, "modulate", Color(1,1,1,0), maxf(0.04, duration * 0.08))
    travel.finished.connect(path.queue_free)

    var tw: Tween = create_tween()
    tw.tween_interval(duration * 0.50)
    tw.tween_property(line, "modulate", Color(1,1,1,0), duration * 0.50).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
    tw.parallel().tween_property(glow, "modulate", Color(1,1,1,0), duration * 0.50).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
    tw.finished.connect(line.queue_free)
    tw.finished.connect(glow.queue_free)


func _spawn_impact_fx(pos: Vector2, accent: Color, action_id: String) -> void:
    var side: float = 52.0 if action_id != "special" else 70.0
    var ring: Panel = _acquire_impact_panel(impact_ring_pool)
    var core: Panel = _acquire_impact_panel(impact_core_pool)
    if ring == null or core == null:
        return
    ring.visible = true
    core.visible = true
    ring.position = pos - Vector2(side * 0.5, side * 0.5)
    ring.size = Vector2(side, side)
    var rs := StyleBoxFlat.new()
    rs.bg_color = Color(accent.r, accent.g, accent.b, 0.08)
    rs.border_color = Color(accent.r, accent.g, accent.b, 0.96)
    rs.set_border_width_all(3)
    rs.set_corner_radius_all(int(side * 0.5))
    ring.add_theme_stylebox_override("panel", rs)

    core.position = pos - Vector2(9,9)
    core.size = Vector2(18,18)
    var cs := StyleBoxFlat.new()
    cs.bg_color = Color(accent.r, accent.g, accent.b, 0.88)
    cs.border_color = Color("ffffff")
    cs.set_border_width_all(2)
    cs.set_corner_radius_all(9)
    core.add_theme_stylebox_override("panel", cs)

    var tw: Tween = create_tween()
    tw.tween_property(ring, "scale", Vector2(1.85, 1.85), 0.42).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
    tw.parallel().tween_property(ring, "modulate", Color(1,1,1,0.0), 0.42).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
    tw.parallel().tween_property(core, "scale", Vector2(1.65,1.65), 0.24).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
    tw.parallel().tween_property(core, "modulate", Color(1,1,1,0.0), 0.34).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
    tw.finished.connect(_release_impact_panel.bind(ring))
    tw.finished.connect(_release_impact_panel.bind(core))


func _play_action_sound(action_id: String) -> void:
    match action_id:
        "taijutsu": _play_sfx("res://assets/audio/atk/A.mp3", -5.0)
        "ninjutsu": _play_sfx("res://assets/audio/atk/B.mp3", -5.0)
        "genjutsu": _play_sfx("res://assets/audio/atk/C.mp3", -5.0)
        "special": _play_sfx("res://assets/audio/atk/D.mp3", -4.0)

func _descriptor_duration(descriptor: Dictionary) -> float:
    if str(descriptor.get("kind", "attack")) == "switch":
        return 0.44
    return _action_duration(str(descriptor.get("action_id", "")))

func _action_duration(action_id: String) -> float:
    match action_id:
        "taijutsu": return 0.68
        "ninjutsu": return 0.82
        "genjutsu": return 0.94
        "special": return 1.06
        _ : return 0.72

func _action_damage(source: YugitoCardActor, action_id: String) -> int:
    # Conservé uniquement pour compatibilité de vieux appels de prototype.
    # Les combats réels utilisent maintenant _calculate_classic_damage().
    if source == null:
        return 0
    return maxi(100, source.effective_stat(action_id) / 2)

func _action_display_name(action_id: String) -> String:
    match action_id:
        "taijutsu": return "TAIJUTSU"
        "ninjutsu": return "NINJUTSU"
        "genjutsu": return "GENJUTSU"
        "special": return "TECHNIQUE SPÉCIALE"
        "copy_special": return "TECHNIQUE COPIÉE"
        "reserve": return "ÉCHANGE AVEC LA RÉSERVE"
        _ : return "ACTION"

func _action_color(action_id: String) -> Color:
    match action_id:
        "taijutsu": return Color("ef6659")
        "ninjutsu": return Color("58aff0")
        "genjutsu": return Color("ba85ed")
        "special": return Color("e2b746")
        _ : return Color("7a93ac")

func _replacement_overlay_active() -> bool:
    return replacement_modal != null and replacement_modal.is_open()

func _make_reserve_candidates(reserve: Array[String], max_choices: int = 3, random_pick: bool = true) -> Array[String]:
    var pool: Array[String] = reserve.duplicate()
    if random_pick:
        pool = battle_rng.shuffled_strings(pool)
    var result: Array[String] = []
    var limit: int = mini(max_choices, pool.size())
    for i in range(limit):
        result.append(str(pool[i]))
    return result

func _open_death_replacement(actor: YugitoCardActor) -> void:
    if actor == null or not is_instance_valid(actor):
        return
    var reserve: Array[String] = ally_reserve if actor.team_name == "ally" else enemy_reserve
    _open_death_replacement_with_candidates(actor, _make_reserve_candidates(reserve, 3, true))

func _open_tactical_switch_choice(actor: YugitoCardActor) -> void:
    if actor == null or not is_instance_valid(actor):
        return
    var departure_lock: String = _field_departure_lock_reason(actor)
    if not departure_lock.is_empty():
        _battle_log_set("%s ne peut pas quitter le terrain : %s." % [actor.display_name, departure_lock])
        return
    var reserve: Array[String] = _planning_reserve_ids(actor.team_name)
    if reserve.is_empty():
        _battle_log_set("La réserve est vide : aucun échange possible.")
        return
    var forced_id: String = str(forced_reserve_choice.get(actor.team_name, ""))
    var candidates: Array[String] = []
    if not forced_id.is_empty() and reserve.has(forced_id):
        candidates = [forced_id]
    else:
        candidates = _make_reserve_candidates(reserve, 5, false)
    replacement_context = {
        "mode": "switch_plan",
        "actor": actor,
        "team": actor.team_name,
        "candidates": candidates,
        "planning_slot": planning_slot
    }
    replacement_modal.show_choices(
        "ÉCHANGE TACTIQUE — ACTION %d" % planning_slot,
        "Choisis librement la carte de réserve qui remplacera %s. Rien ne se produit avant validation." % actor.display_name,
        candidates
    )
    _battle_log_set("Échange tactique : choisis la carte entrante.")
    _refresh_action_buttons()

func _close_replacement_overlay() -> void:
    replacement_context = {}
    if replacement_modal:
        replacement_modal.hide_modal()
    _refresh_action_buttons()


func _on_replacement_timeout_choice(choice_index: int) -> void:
    if replacement_context.is_empty():
        return
    var mode: String = str(replacement_context.get("mode", ""))
    if mode not in ["death", "temari"]:
        return
    var candidates: Array = replacement_context.get("candidates", []) as Array
    if choice_index < 0 or choice_index >= candidates.size():
        return
    var cid: String = str(candidates[choice_index])
    var data: Dictionary = cards_by_id.get(cid, {}) as Dictionary
    _battle_log_set("30 secondes écoulées : %s entre automatiquement sur le terrain." % str(data.get("name", cid)))
    _on_replacement_choice_pressed(choice_index)

func _on_replacement_choice_pressed(choice_index: int) -> void:
    if replacement_context.is_empty():
        return
    _play_sfx("res://assets/audio/ui/pick.mp3", -10.0)
    var candidates: Array[String] = []
    for item in replacement_context.get("candidates", []):
        candidates.append(str(item))
    if choice_index < 0 or choice_index >= candidates.size():
        return
    var mode: String = str(replacement_context.get("mode", "death"))
    var chosen_id: String = str(candidates[choice_index])

    if mode == "tobi_bomb":
        var bomb_target: YugitoCardActor = _find_live_card("enemy", chosen_id)
        if bomb_target != null:
            _place_tobi_bomb("ally", bomb_target)
        _close_replacement_overlay()
        return

    var actor: YugitoCardActor = replacement_context.get("actor") as YugitoCardActor
    if actor == null or not is_instance_valid(actor):
        _close_replacement_overlay()
        return

    if mode == "tobi_prediction_enemy":
        var predicted_enemy: YugitoCardActor = _find_live_card("enemy", chosen_id)
        if predicted_enemy == null:
            _close_replacement_overlay()
            _battle_log_set("Tobi : l'attaquant prédit n'est plus disponible.")
            return
        var ally_candidates: Array[String] = []
        for predicted_ally: YugitoCardActor in _living_cards("ally"):
            ally_candidates.append(predicted_ally.card_id)
        if ally_candidates.is_empty():
            _close_replacement_overlay()
            return
        replacement_context = {
            "mode":"tobi_prediction_ally_modal",
            "actor":actor,
            "action_id":str(replacement_context.get("action_id","special")),
            "planning_slot":int(replacement_context.get("planning_slot",planning_slot)),
            "enemy_uid":predicted_enemy.battle_uid,
            "enemy_id":predicted_enemy.card_id,
            "candidates":ally_candidates
        }
        replacement_modal.show_choices("TOBI — PRÉDICTION 2/2", "Qui sera la cible de la prochaine attaque de %s ?" % predicted_enemy.display_name, ally_candidates)
        _battle_log_set("TOBI : choisis maintenant la cible alliée prédite.")
        return

    if mode == "tobi_prediction_ally_modal":
        var predicted_enemy2: YugitoCardActor = _resolve_actor_uid(int(replacement_context.get("enemy_uid",0)))
        var predicted_ally2: YugitoCardActor = _find_live_card("ally", chosen_id)
        var stored_action_id: String = str(replacement_context.get("action_id","special"))
        var stored_slot: int = int(replacement_context.get("planning_slot",planning_slot))
        if predicted_enemy2 == null or predicted_ally2 == null:
            _close_replacement_overlay()
            _battle_log_set("Tobi : prédiction annulée, une carte n'est plus disponible.")
            return
        planning_slot = stored_slot
        _store_planned_action(actor, predicted_enemy2, stored_action_id, {"prediction_ally_uid":predicted_ally2.battle_uid, "prediction_ally_id":predicted_ally2.card_id})
        _close_replacement_overlay()
        return
    var chosen_data: Dictionary = cards_by_id.get(chosen_id, {}) as Dictionary
    var chosen_name: String = str(chosen_data.get("name", chosen_id))

    if mode == "ao_tracker_plan":
        _store_planned_action(actor, null, "special", {"tracker_id":chosen_id})
        _close_replacement_overlay()
        _battle_log_set("Ao a mémorisé secrètement la prochaine entrée ennemie.")
        return
    if mode == "byakugan_tracker_plan":
        var target_uid: int = int(replacement_context.get("target_uid", 0))
        var target_actor: YugitoCardActor = _resolve_actor_uid(target_uid)
        var action_id: String = str(replacement_context.get("action_id", "special"))
        var special_id: String = str(replacement_context.get("special_id", actor.card_id))
        if target_actor == null or not is_instance_valid(target_actor) or target_actor.defeated:
            _close_replacement_overlay()
            _battle_log_set("Byakugan : la cible offensive n'est plus disponible, action annulée.")
            return
        _store_planned_action(actor, target_actor, action_id, {"tracker_id":chosen_id})
        _close_replacement_overlay()
        _battle_log_set("%s a verrouillé secrètement %s pour la prochaine entrée adverse." % [str((cards_by_id.get(special_id,{}) as Dictionary).get("name", actor.display_name)), chosen_name])
        return
    if mode == "orochimaru_grave_plan":
        _store_planned_action(actor, null, "special", {"grave_card_id":chosen_id})
        _close_replacement_overlay()
        _battle_log_set("Orochimaru a choisi le corps à réincarner.")
        return

    if mode == "switch_plan":
        var descriptor: Dictionary = {
            "kind": "switch",
            "source_uid": actor.battle_uid,
            "source_id": actor.card_id,
            "source_team": actor.team_name,
            "source_slot": actor.seed_index_value(),
            "outgoing_id": actor.card_id,
            "outgoing_name": actor.display_name,
            "incoming_id": chosen_id,
            "incoming_name": chosen_name
        }
        var slot_to_fill: int = int(replacement_context.get("planning_slot", planning_slot))
        if slot_to_fill == 1:
            action1_plan = descriptor
            planning_slot = 2
        else:
            action2_plan = descriptor
        current_action = ""
        _battle_log_set("Action %d préparée : %s → %s. Rien ne part avant validation." % [slot_to_fill, actor.display_name, chosen_name])
        _close_replacement_overlay()
        _refresh_plan_ui()
        _refresh_action_buttons()
        return

    # Grande rafale de Temari : remplacement NORMAL, sans cimetière. Le Ninja
    # soufflé a déjà rejoint la réserve avec son état complet ; le choix remplit
    # exactement son ancien slot puis la résolution A1/A2 reprend.
    if mode == "temari":
        var temari_reserve: Array[String] = ally_reserve if actor.team_name == "ally" else enemy_reserve
        if not temari_reserve.has(chosen_id):
            _battle_log_set("Cette carte n'est plus disponible dans la réserve.")
            return
        temari_reserve.erase(chosen_id)
        var blown_name: String = actor.display_name
        _close_replacement_overlay()
        _replace_actor(actor, chosen_id, false)
        _battle_log_set("%s est soufflé en réserve • %s prend exactement le même emplacement." % [blown_name, chosen_name])
        _refresh_reserve_labels()
        _update_team_status()
        return

    # Remplacement après K.O. : seules les cartes effectivement proposées sont légales.
    var reserve: Array[String] = ally_reserve if actor.team_name == "ally" else enemy_reserve
    if not reserve.has(chosen_id):
        _battle_log_set("Cette carte n'est plus disponible dans la réserve.")
        return
    reserve.erase(chosen_id)
    var old_name: String = actor.display_name
    _close_replacement_overlay()
    _replace_actor(actor, chosen_id, true)
    _battle_log_set("%s rejoint le cimetière • %s prend exactement le même emplacement." % [old_name, chosen_name])
    _refresh_reserve_labels()
    _update_team_status()

func _manual_reserve_exchange() -> void:
    if resolving_action or _replacement_overlay_active():
        return
    if selected_actor == null or selected_actor.team_name != "ally" or selected_actor.defeated:
        _battle_log_set("Sélectionne une carte alliée avant l'échange réserve.")
        return
    if ally_reserve.is_empty():
        _battle_log_set("La réserve alliée est vide.")
        return
    _open_tactical_switch_choice(selected_actor)

func _try_scheduled_switch_on_death(actor: YugitoCardActor) -> bool:
    # Classic : si le Ninja qui tombe devait effectuer un Switch A2 déjà armé,
    # la carte programmée entre IMMÉDIATEMENT à sa mort et remplace le tirage
    # aléatoire de remplacement. L'A2 est consommée même si son entrée échoue.
    if actor == null or not is_instance_valid(actor):
        return false
    var pending: Dictionary = delayed_action2 if actor.team_name == "ally" else ai_delayed_action2
    if pending.is_empty() or str(pending.get("kind", "")) != "switch":
        return false
    var pending_outgoing: String = str(pending.get("outgoing_id", pending.get("source_id", "")))
    if pending_outgoing != actor.card_id:
        return false

    # L'ordre est consommé avant toute vérification, comme GameEngine PC.
    if actor.team_name == "ally":
        delayed_action2 = {}
    else:
        ai_delayed_action2 = {}

    var reserve: Array[String] = ally_reserve if actor.team_name == "ally" else enemy_reserve
    var incoming_id: String = str(pending.get("incoming_id", ""))
    var forced_id: String = str(forced_reserve_choice.get(actor.team_name, ""))
    if not forced_id.is_empty() and reserve.has(forced_id):
        incoming_id = forced_id
    if incoming_id.is_empty() or not reserve.has(incoming_id):
        _battle_log_append("  •  Switch A2 d'urgence perdu : carte entrante indisponible")
        return false

    reserve.erase(incoming_id)
    var incoming_name: String = str((cards_by_id.get(incoming_id,{}) as Dictionary).get("name",incoming_id))
    _battle_log_append("  •  SWITCH A2 D'URGENCE : %s entre immédiatement" % incoming_name)
    _replace_actor(actor, incoming_id, true, false)
    _refresh_reserve_labels()
    _update_team_status()
    return true

func _schedule_death_replacement_dispatch(delay: float = 0.06) -> void:
    if death_replacement_dispatch_scheduled:
        return
    death_replacement_dispatch_scheduled = true
    var timer: SceneTreeTimer = get_tree().create_timer(maxf(0.01, delay))
    timer.timeout.connect(_dispatch_next_death_replacement)

func _queue_death_replacement(actor: YugitoCardActor) -> void:
    if actor == null or not is_instance_valid(actor) or not actor.defeated:
        return
    var uid: int = actor.battle_uid
    if uid <= 0:
        return
    if not pending_death_replacement_uids.has(uid):
        pending_death_replacement_uids.append(uid)
    resolution_waiting_replacement = true
    _schedule_death_replacement_dispatch()

func _dispatch_next_death_replacement() -> void:
    death_replacement_dispatch_scheduled = false
    if _replacement_overlay_active():
        return
    while not pending_death_replacement_uids.is_empty():
        var uid: int = pending_death_replacement_uids.pop_front()
        var actor: YugitoCardActor = _resolve_actor_uid(uid)
        if actor == null or not is_instance_valid(actor) or not actor.defeated:
            continue
        if bool(actor.status_tags.get("replacement_counted", false)):
            continue
        resolution_waiting_replacement = true
        _replace_defeated_actor(actor)
        return
    # Tous les K.O. issus de la même résolution ont été traités : seulement
    # maintenant la file A2/A1 peut reprendre.
    resolution_waiting_replacement = false
    if not resolution_step_running:
        _run_next_resolution_step()

func _replace_defeated_actor(actor: YugitoCardActor) -> void:
    if actor == null or not is_instance_valid(actor) or not actor.defeated:
        return
    if bool(actor.status_tags.get("replacement_counted", false)):
        return
    actor.status_tags["replacement_counted"] = true

    var reserve: Array[String] = ally_reserve if actor.team_name == "ally" else enemy_reserve
    var graveyard: Array[String] = ally_graveyard if actor.team_name == "ally" else enemy_graveyard
    if not graveyard.has(actor.card_id):
        graveyard.append(actor.card_id)
    ally_cemetery_count = ally_graveyard.size()
    enemy_cemetery_count = enemy_graveyard.size()

    if reserve.is_empty():
        _battle_log_append("  •  Réserve vide : emplacement laissé vacant.")
        _retire_actor(actor)
        _update_team_status()
        _check_victory_state()
        _resume_resolution_after_replacement()
        return

    # Avant le tirage de remplacement : un Switch A2 déjà programmé sur ce
    # Ninja devient le remplacement d'urgence exact du moteur PC.
    if _try_scheduled_switch_on_death(actor):
        return

    var forced_id: String = str(forced_reserve_choice.get(actor.team_name, ""))
    var candidates: Array[String] = [forced_id] if (not forced_id.is_empty() and reserve.has(forced_id)) else _make_reserve_candidates(reserve, 3, true)
    if actor.team_name == "ally":
        # Comme le client PC : le Ninja mort quitte visuellement le terrain et un
        # écran dédié bloque toute autre interaction jusqu'au choix.
        actor.visible = false
        _refresh_reserve_labels()
        _update_team_status()
        _open_death_replacement_with_candidates(actor, candidates)
        return

    # IA : même tirage aléatoire de 3 max, puis choix du meilleur parmi l'offre.
    var new_id: String = _ai_choose_replacement_candidate(candidates)
    if new_id.is_empty():
        _retire_actor(actor)
        _update_team_status()
        return
    reserve.erase(new_id)
    var old_name: String = actor.display_name
    var new_name: String = str((cards_by_id[new_id] as Dictionary).get("name", new_id))
    _replace_actor(actor, new_id, true)
    _battle_log_set("%s rejoint le cimetière • IA choisit %s parmi %d proposition(s)." % [old_name, new_name, candidates.size()])
    _refresh_reserve_labels()
    _update_team_status()

func _ai_choose_replacement_candidate(candidates: Array[String]) -> String:
    var best_id: String = ""
    var best_score: float = -1.0
    for cid in candidates:
        var data: Dictionary = cards_by_id.get(cid, {}) as Dictionary
        var score: float = float(data.get("stars", 0.0)) * 100000.0
        score += float(int(data.get("hp", 0)) + int(data.get("taijutsu", 0)) + int(data.get("ninjutsu", 0)) + int(data.get("genjutsu", 0)))
        if score > best_score:
            best_score = score
            best_id = cid
    return best_id

func _open_death_replacement_with_candidates(actor: YugitoCardActor, candidates: Array[String]) -> void:
    if candidates.is_empty():
        return
    replacement_context = {
        "mode": "death",
        "actor": actor,
        "team": actor.team_name,
        "candidates": candidates
    }
    replacement_modal.show_choices(
        "REMPLACEMENT OBLIGATOIRE",
        "%s est tombé • 3 cartes maximum tirées au hasard • choisis le Ninja qui prend exactement son emplacement" % actor.display_name,
        candidates,
        true
    )
    _battle_log_set("REMPLACEMENT OBLIGATOIRE — le duel est suspendu jusqu'à ton choix.")
    _refresh_action_buttons()

func _cleanup_context_links_for_departure(actor: YugitoCardActor, preserve_target_links: bool = false) -> void:
    if actor == null or not is_instance_valid(actor):
        return
    # P26R2 : les états personnels et les verrous reçus ne disparaissent JAMAIS
    # parce que la cible va en réserve. Un départ volontaire est interdit pour
    # Ombres/Prison/Scellé/Jashin ; Grande Rafale de Temari est l'exception et
    # doit sauvegarder le lien dans l'instance pour qu'il reprenne au retour.
    # En revanche, si l'acteur qui part est la SOURCE d'un lien dépendant de sa
    # présence, ses cibles terrain sont libérées.
    if actor.card_id == "shikamaru":
        _clear_shadow_stuns_from(actor)
    if not preserve_target_links:
        actor.status_tags.erase("shadow_source")
        actor.status_tags.erase("shadow_source_uid")
        actor.status_tags.erase("shadow_turns")
        actor.status_tags.erase("shadow_turns_skip_tick")

    # Transfert d'Ino : cesse si Ino OU le vrai corps quitte le terrain.
    if actor.card_id == "ino" and actor.status_tags.has("ino_target_uid"):
        _end_ino_possession(actor, "Transfert interrompu : Ino quitte le terrain.")
    var possessor: YugitoCardActor = _ino_possessor(actor)
    if possessor != null:
        _end_ino_possession(possessor, "Transfert interrompu : le corps contrôlé quitte le terrain.")

    # Une cible expulsée par Temari conserve Prison/Jashin. Le Scellement de
    # Kushina n'est jamais nettoyé ici : c'est un état personnel temporisé.
    if not preserve_target_links:
        actor.status_tags.erase("kisame_prisoned_by_uid")
        actor.status_tags.erase("doom_turns")
        actor.status_tags.erase("doom_source_team")
        actor.status_tags.erase("doom_source_uid")

    # Départ d'une source Kisame/Hidan : nettoyer toutes les cibles encore terrain.
    for linked: YugitoCardActor in card_actors:
        if linked == null or not is_instance_valid(linked) or linked == actor or linked.defeated:
            continue
        var changed: bool = false
        if int(linked.status_tags.get("kisame_prisoned_by_uid", 0)) == actor.battle_uid:
            linked.status_tags.erase("kisame_prisoned_by_uid")
            changed = true
        if int(linked.status_tags.get("doom_source_uid", 0)) == actor.battle_uid:
            linked.status_tags.erase("doom_turns")
            linked.status_tags.erase("doom_source_team")
            linked.status_tags.erase("doom_source_uid")
            changed = true
        if int(linked.status_tags.get("shadow_source_uid", 0)) == actor.battle_uid:
            linked.status_tags.erase("shadow_source")
            linked.status_tags.erase("shadow_source_uid")
            linked.status_tags.erase("shadow_turns")
            linked.status_tags.erase("shadow_turns_skip_tick")
            linked.status_tags.erase("shadow_fresh_application")
            changed = true
        if changed:
            linked.refresh_status_badges()
    actor.refresh_status_badges()
    _refresh_persistent_status_links()

func _replace_actor(actor: YugitoCardActor, new_id: String, from_death: bool, reactive: bool = false) -> void:
    if actor == null or not is_instance_valid(actor) or not cards_by_id.has(new_id):
        return
    var old_anchor: Vector2 = actor.anchor_position
    var old_seed: int = actor.seed_index_value()
    var old_team: String = actor.team_name
    var outgoing_id: String = actor.card_id
    if str(forced_reserve_choice.get(old_team, "")) == new_id:
        forced_reserve_choice[old_team] = ""
        for tracker_actor: YugitoCardActor in _living_cards(_opponent_team(old_team)):
            tracker_actor.status_tags.erase("tracker_armed")
            tracker_actor.status_tags.erase("ao_tracker_target")
            tracker_actor.status_tags.erase("byakugan_tracker_target")
            tracker_actor.refresh_status_badges()
    var yamato_relay: bool = reactive and outgoing_id == "yamato"
    var state_store: Dictionary = ally_reserve_states if old_team == "ally" else enemy_reserve_states

    # Les liens qui exigent la présence sur le terrain cessent AVANT la sauvegarde
    # de l'instance (même ordre que _cleanup_links_to() dans le moteur PC).
    _cleanup_context_links_for_departure(actor)
    # Une synergie est un bonus de terrain : elle disparaît en réserve en conservant
    # le pourcentage de PV actuel, exactement comme le client PC.
    actor.set_synergy_bonus(0.0)

    # Switch volontaire : l'instance sortante garde PV, bouclier, cooldowns,
    # buffs/debuffs et états personnels dans la réserve, comme le moteur PC.
    if not from_death:
        state_store[outgoing_id] = actor.export_state()
    else:
        state_store.erase(outgoing_id)

    var incoming_state: Dictionary = {}
    if state_store.has(new_id):
        incoming_state = (state_store[new_id] as Dictionary).duplicate(true)
        state_store.erase(new_id)

    _cancel_plans_for_actor(actor)
    if selected_actor == actor:
        selected_actor = null
    card_actors.erase(actor)
    actor.queue_free()

    var delay: float = 0.16 if from_death else 0.08
    var timer: SceneTreeTimer = get_tree().create_timer(delay)
    timer.timeout.connect(_spawn_replacement_card.bind(new_id, old_anchor, old_seed, old_team, incoming_state, reactive, yamato_relay, from_death))

func _spawn_replacement_card(card_id: String, anchor: Vector2, seed_index: int, team_name: String, saved_state: Dictionary = {}, reactive: bool = false, yamato_relay: bool = false, from_death: bool = false) -> void:
    _spawn_card(card_id, anchor, seed_index, team_name)
    var newest: YugitoCardActor = card_actors[card_actors.size() - 1]
    if not saved_state.is_empty():
        newest.import_state(saved_state)
    # Espion souterrain PC : Zetsu punit UNIQUEMENT le Switch immédiat A1,
    # jamais le remplacement K.O. ni le Switch A2 réactif.
    if not from_death and not reactive and _find_live_card(_opponent_team(team_name),"zetsu") != null:
        newest.apply_disable(2,"zetsu_switch_a1")
        newest.status_tags["zetsu_switch_stun"] = 2
        newest.status_tags["zetsu_switch_stun_skip_tick"] = true
    newest.reactive_entry_guard = reactive and (card_id in ["itachi", "sasuke", "kakashi"] or yamato_relay)
    if reactive:
        newest.status_tags["reactive_entry_cycle"] = turn_counter
    else:
        newest.status_tags.erase("reactive_entry_cycle")
        newest.status_tags.erase("yamato_counter_gift")
    # Classic arme Haku à chaque vraie entrée depuis la réserve (Switch A1,
    # Switch A2 ou remplacement K.O.). La garde ne sera testée que contre A2.
    if card_id == "haku":
        newest.status_tags["haku_entry_guard"] = true
    if yamato_relay:
        newest.status_tags["yamato_counter_gift"] = true
    newest.play_entry_fx()
    if bool(makibishi_active.get(team_name,false)) and not newest.defeated:
        var maki_damage: int = maxi(1,int(round(float(newest.max_hp) * 0.07)))
        _deal_fixed_status_damage(newest,maki_damage,"MAKIBISHI TENTEN",null,true,false)
        if newest.defeated:
            _refresh_selection_panel()
            _refresh_action_buttons()
            _update_team_status()
            return
    if team_name == "ally":
        for card_actor in card_actors:
            card_actor.set_selected(card_actor == newest)
        selected_actor = newest
    _refresh_selection_panel()
    _refresh_action_buttons()
    _update_team_status()
    _resume_resolution_after_replacement()

func _retire_actor(actor: YugitoCardActor) -> void:
    _cancel_plans_for_actor(actor)
    if selected_actor == actor:
        selected_actor = null
    card_actors.erase(actor)
    actor.queue_free()

func _cancel_plans_for_actor(actor: YugitoCardActor) -> void:
    # Seuls les choix PAS ENCORE VALIDÉS sont annulables ici. Une A2 déjà armée
    # reste obligatoirement en file jusqu'à la prochaine validation adverse :
    # elle y sera consommée même si source/cible est devenue illégale.
    if _descriptor_has_actor(action1_plan, actor):
        action1_plan = {}
    if _descriptor_has_actor(action2_plan, actor):
        action2_plan = {}
    if _descriptor_has_actor(free_action_plan, actor):
        free_action_plan = {}
    _refresh_plan_ui()

func _descriptor_has_actor(descriptor: Dictionary, actor: YugitoCardActor) -> bool:
    if descriptor.is_empty() or actor == null or not is_instance_valid(actor):
        return false
    var uid: int = actor.battle_uid
    if uid > 0 and (int(descriptor.get("source_uid", 0)) == uid or int(descriptor.get("target_uid", 0)) == uid):
        return true
    # Les descripteurs virtuels du cas A1 Switch -> A2 entrant n'ont pas encore
    # d'UID ; l'identité unique de carte assure leur suivi.
    var source_match: bool = str(descriptor.get("source_id", "")) == actor.card_id and str(descriptor.get("source_team", actor.team_name)) == actor.team_name
    var target_match: bool = str(descriptor.get("target_id", "")) == actor.card_id and str(descriptor.get("target_team", actor.team_name)) == actor.team_name
    return source_match or target_match

func _refresh_field_effect_labels() -> void:
    if enemy_field_effect_label != null:
        enemy_field_effect_label.text = "⚠ MAKIBISHI • 7% PV MAX À CHAQUE ENTRÉE" if bool(makibishi_active.get("enemy", false)) else ""
    if ally_field_effect_label != null:
        ally_field_effect_label.text = "⚠ MAKIBISHI • 7% PV MAX À CHAQUE ENTRÉE" if bool(makibishi_active.get("ally", false)) else ""

func _refresh_reserve_labels() -> void:
    ally_cemetery_count = ally_graveyard.size()
    enemy_cemetery_count = enemy_graveyard.size()
    if ally_reserve_count_label:
        ally_reserve_count_label.text = str(ally_reserve.size())
    if enemy_reserve_count_label:
        enemy_reserve_count_label.text = str(enemy_reserve.size())
    if ally_cemetery_value_label:
        ally_cemetery_value_label.text = str(ally_cemetery_count)
    if enemy_cemetery_value_label:
        enemy_cemetery_value_label.text = str(enemy_cemetery_count)
    if top_reserve_status_label:
        top_reserve_status_label.text = "RÉSERVE  %d" % enemy_reserve.size()
    if bottom_reserve_status_label:
        bottom_reserve_status_label.text = "RÉSERVE  %d" % ally_reserve.size()
    if top_cemetery_status_label:
        top_cemetery_status_label.text = "CIMETIÈRE  %d" % enemy_cemetery_count
    if bottom_cemetery_status_label:
        bottom_cemetery_status_label.text = "CIMETIÈRE  %d" % ally_cemetery_count

func _descriptor_text(descriptor: Dictionary) -> String:
    if descriptor.is_empty():
        return ""
    var kind: String = str(descriptor.get("kind", "attack"))
    if kind == "switch":
        return "%s ↔ %s" % [str(descriptor.get("outgoing_name", "Ninja")), str(descriptor.get("incoming_name", "Réserve"))]
    var source: YugitoCardActor = _resolve_descriptor_source(descriptor)
    var target: YugitoCardActor = null
    var source_name: String = str(descriptor.get("source_id", "Ninja"))
    if source != null:
        source_name = source.display_name
        target = _resolve_descriptor_target(descriptor, source.team_name)
    else:
        var sd: Dictionary = cards_by_id.get(str(descriptor.get("source_id", "")), {}) as Dictionary
        source_name = str(sd.get("name", source_name))
    var action_id: String = str(descriptor.get("action_id", ""))
    if int(descriptor.get("target_slot", -1)) < 0:
        if action_id == "special":
            var special_name: String = str((cards_by_id.get(str(descriptor.get("source_id", "")), {}) as Dictionary).get("special_name", "SPÉCIALE"))
            return "%s • %s" % [source_name, special_name]
        return "%s • %s → DIRECT" % [source_name, _action_display_name(action_id)]
    var target_name: String = str(descriptor.get("target_id", "Cible"))
    if target != null:
        target_name = target.display_name
    else:
        var td: Dictionary = cards_by_id.get(str(descriptor.get("target_id", "")), {}) as Dictionary
        target_name = str(td.get("name", target_name))
    return "%s • %s → %s" % [source_name, _action_display_name(action_id), target_name]

func _refresh_plan_ui() -> void:
    _refresh_action_markers()
    if timeline_free_subtitle:
        timeline_free_subtitle.text = "Hiraishin : attaque normale gratuite" if free_action_plan.is_empty() else _descriptor_text(free_action_plan)
    if timeline_free_button:
        var minato_present: bool = _find_live_card("ally", "minato") != null or not free_action_plan.is_empty()
        timeline_free_button.visible = minato_present
        if cancel_free_button:
            cancel_free_button.visible = minato_present
            cancel_free_button.disabled = free_action_plan.is_empty() and not free_action_mode
    if timeline_a1_subtitle:
        timeline_a1_subtitle.text = "Clique ici pour préparer A1" if action1_plan.is_empty() else _descriptor_text(action1_plan)
    if timeline_a2_subtitle:
        if not action2_plan.is_empty():
            timeline_a2_subtitle.text = _descriptor_text(action2_plan)
        elif not delayed_action2.is_empty():
            timeline_a2_subtitle.text = "EN ATTENTE • " + _descriptor_text(delayed_action2)
        else:
            timeline_a2_subtitle.text = "Se déclenche à la validation suivante"
    if timeline_a1_button:
        timeline_a1_button.modulate = Color(1.08, 1.08, 1.08, 1.0) if planning_slot == 1 else Color(0.78, 0.84, 0.90, 1.0)
    if timeline_a2_button:
        timeline_a2_button.modulate = Color(1.08, 1.08, 1.08, 1.0) if planning_slot == 2 else Color(0.78, 0.84, 0.90, 1.0)
    if cancel_a1_button:
        cancel_a1_button.disabled = action1_plan.is_empty()
    if cancel_a2_button:
        cancel_a2_button.disabled = action2_plan.is_empty()
    if action_status_label:
        action_status_label.text = "Préparation : ACTION %d" % planning_slot if current_action == "" else "A%d : %s — choisis une cible" % [planning_slot, _action_display_name(current_action)]
    if validate_button:
        validate_button.disabled = resolving_action or ai_thinking or current_turn_team != "ally" or _replacement_overlay_active()

func _phase_timer_should_run() -> bool:
    return not duel_finished and phase_timer_running and current_turn_team == "ally" and not resolving_action and not ai_thinking and not _replacement_overlay_active()

func _reset_phase_timer() -> void:
    phase_timer_seconds = PHASE_TIMER_LIMIT
    phase_timer_running = true
    phase_timer_expired_once = false
    _refresh_phase_timer_label()
    _animate_phase_timer_from_center()

func _stop_phase_timer() -> void:
    phase_timer_running = false

func _tick_phase_timer(delta: float) -> void:
    if not _phase_timer_should_run():
        return
    phase_timer_seconds = maxf(0.0, phase_timer_seconds - delta)
    _refresh_phase_timer_label()
    if phase_timer_seconds <= 0.0 and not phase_timer_expired_once:
        phase_timer_expired_once = true
        phase_timer_running = false
        _on_phase_timer_expired()

func _refresh_phase_timer_label() -> void:
    if phase_timer_label == null:
        return
    var shown: int = maxi(0, ceili(phase_timer_seconds))
    phase_timer_label.text = "%02d s" % shown

func _animate_phase_timer_from_center() -> void:
    if phase_timer_root == null:
        return
    var target := Vector2(765, 13)
    phase_timer_root.position = Vector2(800.0 - phase_timer_root.size.x * 0.5, 450.0 - phase_timer_root.size.y * 0.5)
    var tween := create_tween()
    tween.set_trans(Tween.TRANS_CUBIC)
    tween.set_ease(Tween.EASE_OUT)
    tween.tween_property(phase_timer_root, "position", target, 0.58)

func _on_phase_timer_expired() -> void:
    if duel_finished or current_turn_team != "ally" or resolving_action or ai_thinking or _replacement_overlay_active():
        return
    _battle_log_set("30 secondes écoulées : validation / fin du tour automatique.")
    current_action = ""
    _commit_player_plan(true)

func _refresh_turn_labels() -> void:
    if turn_title_label:
        turn_title_label.text = "TOUR %d   •   %s" % [turn_counter,IdentityManager.display_name().to_upper()]
    if turn_capsule_label:
        turn_capsule_label.text = "T%d" % turn_counter

func _refresh_synergies() -> void:
    for team_name: String in ["ally", "enemy"]:
        var living: Array[YugitoCardActor] = _living_cards(team_name)
        var ids: Array[String] = []
        for actor: YugitoCardActor in living:
            ids.append(actor.card_id)
        for actor: YugitoCardActor in living:
            actor.set_synergy_bonus(SynergyDB.bonus_for(actor.card_id, ids))
    for actor: YugitoCardActor in card_actors:
        if actor.defeated:
            actor.set_synergy_bonus(0.0)

func _update_team_status() -> void:
    _refresh_field_effect_labels()
    _refresh_synergies()
    if top_hp_label:
        top_hp_label.text = "PV %d / %d" % [enemy_player_hp, PLAYER_HP_MAX]
    if bottom_hp_label:
        bottom_hp_label.text = "PV %d / %d" % [ally_player_hp, PLAYER_HP_MAX]
    if top_field_status_label:
        top_field_status_label.text = "TERRAIN  %d/3" % _living_cards("enemy").size()
    if bottom_field_status_label:
        bottom_field_status_label.text = "TERRAIN  %d/3" % _living_cards("ally").size()
    _refresh_reserve_labels()

func _refresh_selection_panel() -> void:
    if selection_title_label == null or selection_subtitle_label == null or selection_stats_label == null:
        return
    if selected_actor == null or not is_instance_valid(selected_actor):
        if inspect_button != null:
            inspect_button.disabled = true
        selection_title_label.text = "AUCUN NINJA SÉLECTIONNÉ"
        selection_title_label.add_theme_color_override("font_color", Color("9db2c8"))
        selection_subtitle_label.text = "Clique sur une carte du terrain"
        selection_stats_label.text = "Sélection GPU • règles PC synchronisées"
        return
    if inspect_button != null:
        inspect_button.disabled = false
    # P20 : le panneau latéral suit lui aussi l'identité VISUELLE Classic.
    # Clone de Gengetsu et Transfert d'Ino ne doivent pas conserver un titre/
    # élément/PV qui contredisent ce que le joueur voit sur la carte.
    var visual_actor: YugitoCardActor = selected_actor
    var visual_title: String = selected_actor.display_name
    var visual_element: String = selected_actor.element_name
    var visual_hp: int = selected_actor.hp
    var visual_max_hp: int = selected_actor.max_hp
    if selected_actor.card_id == "gengetsu" and bool(selected_actor.status_tags.get("gengetsu_clone_active", false)):
        visual_title = "Clone de Gengetsu"
    elif selected_actor.card_id == "ino":
        var controlled_body: YugitoCardActor = _ino_controlled_body(selected_actor)
        if controlled_body != null:
            visual_actor = controlled_body
            visual_title = controlled_body.display_name
            visual_element = controlled_body.element_name
            visual_hp = controlled_body.hp
            visual_max_hp = controlled_body.max_hp
    selection_title_label.text = visual_title.to_upper()
    selection_title_label.add_theme_color_override("font_color", Color("f2f6fa"))
    var team_label: String = "ALLIÉ" if selected_actor.team_name == "ally" else "ENNEMI"
    var state_parts: Array[String] = []
    if selected_actor.shield > 0:
        state_parts.append("BOUCLIER %d" % selected_actor.shield)
    if selected_actor.disabled_turns > 0:
        state_parts.append("STUN %dT" % selected_actor.disabled_turns)
    if selected_actor.special_cooldown > 0:
        state_parts.append("SPÉ %dT" % selected_actor.special_cooldown)
    if int(selected_actor.status_tags.get("rooted_turns", 0)) > 0:
        state_parts.append("ENRACINÉ")
    var synergy: String = selected_actor.synergy_label()
    if not synergy.is_empty():
        state_parts.append("SYNERGIE %s" % synergy)
    var suffix: String = "" if state_parts.is_empty() else " • " + " / ".join(state_parts)
    selection_subtitle_label.text = "%d/%d PV • %s • %s%s" % [visual_hp, visual_max_hp, visual_element.to_upper(), team_label, suffix]
    selection_stats_label.text = "TAI %d • NIN %d • GEN %d" % [_actor_effective_stat(visual_actor,"taijutsu"), _actor_effective_stat(visual_actor,"ninjutsu"), _actor_effective_stat(visual_actor,"genjutsu")]

func _refresh_action_buttons() -> void:
    var overlay: bool = _replacement_overlay_active()
    for key in action_buttons.keys():
        var btn: Button = action_buttons[key] as Button
        if btn == null:
            continue
        var accent: Color = btn.get_meta("accent_color") as Color
        var enabled: bool = selected_actor != null and is_instance_valid(selected_actor) and selected_actor.team_name == "ally" and not selected_actor.defeated and not resolving_action and not overlay and _actor_can_act(selected_actor)
        if key == "reserve":
            enabled = selected_actor != null and is_instance_valid(selected_actor) and selected_actor.team_name == "ally" and not selected_actor.defeated and not resolving_action and not overlay and not ally_reserve.is_empty() and _can_leave_field_voluntarily(selected_actor)
        elif key == "special" and enabled:
            enabled = _actor_special_available(selected_actor)
        btn.disabled = not enabled
        var base := StyleBoxFlat.new()
        base.bg_color = Color(0.030, 0.050, 0.077, 0.94)
        base.border_color = Color(accent.r, accent.g, accent.b, 0.50)
        base.set_border_width_all(1)
        base.set_corner_radius_all(9)
        if key == current_action:
            base.bg_color = Color(accent.r * 0.22, accent.g * 0.22, accent.b * 0.22, 1.0)
            base.border_color = Color(1.0, 0.88, 0.40, 0.92)
        btn.add_theme_stylebox_override("normal", base)
    if copy_action_button != null:
        var copy_visible: bool = selected_actor != null and is_instance_valid(selected_actor) and selected_actor.card_id == "kakashi" and not str(selected_actor.status_tags.get("copied_special_id", "")).is_empty()
        copy_action_button.visible = copy_visible
        if copy_visible:
            var copy_name: String = str(selected_actor.status_tags.get("copied_special_name", "Spéciale copiée"))
            copy_action_button.text = "COPIE : %s" % copy_name.to_upper()
            copy_action_button.disabled = resolving_action or overlay or not _actor_copied_special_available(selected_actor)
    if timeline_free_button != null:
        var minato_actor: YugitoCardActor = _find_live_card("ally", "minato")
        timeline_free_button.visible = minato_actor != null or not free_action_plan.is_empty()
        if timeline_free_button.visible:
            timeline_free_button.disabled = resolving_action or overlay or ai_thinking or current_turn_team != "ally" or (minato_actor != null and (bool(minato_actor.status_tags.get("minato_free_used_cycle", false)) or not _actor_can_act(minato_actor))) or not free_action_plan.is_empty()
    if direct_attack_button != null:
        var direct_style: String = current_action.trim_prefix("free_")
        direct_attack_button.disabled = resolving_action or overlay or ai_thinking or current_turn_team != "ally" or selected_actor == null or not is_instance_valid(selected_actor) or selected_actor.team_name != "ally" or selected_actor.defeated or direct_style not in ["taijutsu", "ninjutsu", "genjutsu"] or not _living_cards("enemy").is_empty()
    _refresh_plan_ui()

func _status_bar(rect: Rect2, who: String, accent: Color, active: bool) -> void:
    _panel(rect, Color(0.027, 0.050, 0.078, 0.96), Color(0.26, 0.42, 0.58, 0.30), 6)
    var stripe := ColorRect.new()
    stripe.position = rect.position
    stripe.size = Vector2(8, rect.size.y)
    stripe.color = accent
    stripe.mouse_filter = Control.MOUSE_FILTER_IGNORE
    add_child(stripe)
    _label(who, Rect2(rect.position + Vector2(28, 7), Vector2(130, 26)), 13, Color("f2f6fa"), HORIZONTAL_ALIGNMENT_LEFT, true)
    var hp_lbl: Label = _label("PV 4000 / 4000", Rect2(rect.position + Vector2(160, 7), Vector2(190, 26)), 13, Color("edf3f8"), HORIZONTAL_ALIGNMENT_LEFT, true)
    var reserve_lbl: Label = _label("RÉSERVE  5", Rect2(rect.position + Vector2(650, 7), Vector2(110, 26)), 9, Color("8da2b8"), HORIZONTAL_ALIGNMENT_CENTER, true)
    var field_lbl: Label = _label("TERRAIN  3/3", Rect2(rect.position + Vector2(775, 7), Vector2(130, 26)), 9, Color("a7bdd2"), HORIZONTAL_ALIGNMENT_CENTER, true)
    var cemetery_lbl: Label = _label("CIMETIÈRE  0", Rect2(rect.position + Vector2(915, 7), Vector2(120, 26)), 9, Color("8da2b8"), HORIZONTAL_ALIGNMENT_CENTER, true)
    if who == "IA":
        top_hp_label = hp_lbl
        top_reserve_status_label = reserve_lbl
        top_field_status_label = field_lbl
        top_cemetery_status_label = cemetery_lbl
    else:
        bottom_hp_label = hp_lbl
        bottom_reserve_status_label = reserve_lbl
        bottom_field_status_label = field_lbl
        bottom_cemetery_status_label = cemetery_lbl
    if active:
        _capsule(Rect2(rect.position + Vector2(rect.size.x - 92, 8), Vector2(72, 24)), "ACTIF", accent)

func _reserve_box(pos: Vector2, title: String, count: String, accent: Color) -> Label:
    _panel(Rect2(pos, Vector2(112, 158)), Color(0.025, 0.049, 0.077, 0.78), Color(accent.r, accent.g, accent.b, 0.48), 12, 6, Color(0,0,0,0.22), Vector2(0,4))
    _label(title, Rect2(pos + Vector2(10, 20), Vector2(92, 22)), 10, Color("b8c7d6"), HORIZONTAL_ALIGNMENT_CENTER, true)
    _panel(Rect2(pos + Vector2(27, 58), Vector2(58, 72)), Color(0.035, 0.083, 0.132, 0.94), Color(accent.r, accent.g, accent.b, 0.58), 7)
    _label("?", Rect2(pos + Vector2(27, 72), Vector2(58, 34)), 24, Color("92b2d1"), HORIZONTAL_ALIGNMENT_CENTER, true)
    return _label(count, Rect2(pos + Vector2(27, 132), Vector2(58, 18)), 9, Color("748da5"), HORIZONTAL_ALIGNMENT_CENTER, false)

func _cemetery_box(pos: Vector2) -> Label:
    _panel(Rect2(pos, Vector2(112, 158)), Color(0.035, 0.042, 0.056, 0.78), Color(0.50, 0.42, 0.46, 0.42), 12)
    _label("CIMETIÈRE", Rect2(pos + Vector2(8, 38), Vector2(96, 20)), 9, Color("a7949c"), HORIZONTAL_ALIGNMENT_CENTER, true)
    var value: Label = _label("0", Rect2(pos + Vector2(8, 68), Vector2(96, 34)), 18, Color("d7cbd0"), HORIZONTAL_ALIGNMENT_CENTER, true)
    _label("cartes", Rect2(pos + Vector2(8, 101), Vector2(96, 18)), 8, Color("756c73"), HORIZONTAL_ALIGNMENT_CENTER, false)
    return value

func _timeline_free_step_button(rect: Rect2, number: String, title: String, accent: Color) -> Button:
    var btn := Button.new()
    btn.position = rect.position
    btn.size = rect.size
    btn.text = ""
    btn.flat = true
    btn.focus_mode = Control.FOCUS_ALL
    btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
    var normal := StyleBoxFlat.new()
    normal.bg_color = Color(0.054, 0.047, 0.025, 0.90)
    normal.border_color = Color(accent.r, accent.g, accent.b, 0.48)
    normal.set_border_width_all(1)
    normal.set_corner_radius_all(10)
    var hover := normal.duplicate() as StyleBoxFlat
    hover.border_color = Color(accent.r, accent.g, accent.b, 0.90)
    btn.add_theme_stylebox_override("normal", normal)
    btn.add_theme_stylebox_override("hover", hover)
    btn.add_theme_stylebox_override("pressed", hover)
    add_child(btn)
    var bubble := _panel_in(btn, Rect2(8, 7, 31, 28), Color(accent.r, accent.g, accent.b, 0.13), Color(accent.r, accent.g, accent.b, 0.74), 8)
    _label_in(bubble, number, Rect2(0, 0, 31, 28), 9, accent.lightened(0.12), HORIZONTAL_ALIGNMENT_CENTER, true)
    _label_in(btn, title, Rect2(47, 3, 173, 18), 8, accent.lightened(0.12), HORIZONTAL_ALIGNMENT_LEFT, true)
    return btn

func _timeline_step_button(rect: Rect2, number: String, title: String, accent: Color, slot: int) -> Button:
    var btn := Button.new()
    btn.position = rect.position
    btn.size = rect.size
    btn.text = ""
    btn.flat = true
    btn.focus_mode = Control.FOCUS_ALL
    btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
    var normal := StyleBoxFlat.new()
    normal.bg_color = Color(0.030, 0.054, 0.085, 0.86)
    normal.border_color = Color(accent.r, accent.g, accent.b, 0.36)
    normal.set_border_width_all(1)
    normal.set_corner_radius_all(10)
    var hover := normal.duplicate() as StyleBoxFlat
    hover.border_color = Color(accent.r, accent.g, accent.b, 0.78)
    hover.bg_color = Color(0.038, 0.067, 0.102, 0.96)
    btn.add_theme_stylebox_override("normal", normal)
    btn.add_theme_stylebox_override("hover", hover)
    btn.add_theme_stylebox_override("pressed", hover)
    add_child(btn)
    var bubble := _panel_in(btn, Rect2(9, 10, 36, 36), Color(accent.r, accent.g, accent.b, 0.13), Color(accent.r, accent.g, accent.b, 0.74), 9)
    _label_in(bubble, number, Rect2(0, 0, 36, 36), 12, accent.lightened(0.12), HORIZONTAL_ALIGNMENT_CENTER, true)
    _label_in(btn, title, Rect2(55, 7, 194, 22), 9, accent.lightened(0.12), HORIZONTAL_ALIGNMENT_LEFT, true)
    btn.tooltip_text = "%s • emplacement de planification" % title
    btn.pressed.connect(_set_planning_slot.bind(slot))
    return btn

func _mini_cancel_button(rect: Rect2, callback: Callable) -> Button:
    var btn := _action_button(rect, "↩", Color("e76872"), false)
    btn.add_theme_font_size_override("font_size", 14)
    btn.tooltip_text = "Annuler cet emplacement"
    btn.pressed.connect(callback)
    return btn

func _action_button(rect: Rect2, text_value: String, accent: Color, strong: bool) -> Button:
    var btn := Button.new()
    btn.position = rect.position
    btn.size = rect.size
    btn.text = text_value
    btn.flat = true
    btn.focus_mode = Control.FOCUS_ALL
    btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
    btn.add_theme_font_size_override("font_size", 13 if strong else 11)
    btn.add_theme_color_override("font_color", Color("f3f6f9") if strong else Color("c3cfda"))
    btn.add_theme_color_override("font_hover_color", Color("ffffff"))
    btn.add_theme_color_override("font_pressed_color", Color("ffffff"))
    var normal := StyleBoxFlat.new()
    normal.bg_color = Color(0.015,0.034,0.055,0.58) if strong else Color(0.010,0.028,0.048,0.48)
    normal.border_color = Color(accent.r, accent.g, accent.b, 0.58 if strong else 0.34)
    normal.set_border_width_all(1)
    normal.set_corner_radius_all(9)
    var hover := normal.duplicate() as StyleBoxFlat
    hover.bg_color = hover.bg_color.lerp(Color(accent.r, accent.g, accent.b, 0.24), 0.64)
    hover.border_color = Color(accent.r, accent.g, accent.b, 0.86)
    var disabled := normal.duplicate() as StyleBoxFlat
    disabled.bg_color = Color(0.16,0.18,0.20,0.14)
    disabled.border_color = Color(0.40, 0.48, 0.56, 0.22)
    btn.add_theme_stylebox_override("normal", normal)
    btn.add_theme_stylebox_override("hover", hover)
    btn.add_theme_stylebox_override("pressed", hover)
    btn.add_theme_stylebox_override("disabled", disabled)
    btn.add_theme_stylebox_override("focus", hover)
    var stripe := ColorRect.new()
    stripe.position = Vector2(8, 10)
    stripe.size = Vector2(3, rect.size.y - 20)
    stripe.color = Color(accent.r, accent.g, accent.b, 0.9)
    stripe.mouse_filter = Control.MOUSE_FILTER_IGNORE
    btn.add_child(stripe)
    add_child(btn)
    btn.set_meta("accent_color", accent)
    if not text_value.strip_edges().is_empty():
        btn.tooltip_text = text_value.strip_edges()
    return btn

func _capsule(rect: Rect2, text_value: String, accent: Color) -> void:
    _panel(rect, Color(accent.r * 0.12, accent.g * 0.12, accent.b * 0.12, 0.78), Color(accent.r, accent.g, accent.b, 0.38), int(rect.size.y / 2.0))
    _label(text_value, rect, 8, accent.lightened(0.14), HORIZONTAL_ALIGNMENT_CENTER, true)

func _logo(pos: Vector2, side: float) -> void:
    var logo := TextureRect.new()
    logo.position = pos
    logo.size = Vector2(side, side)
    logo.texture = AssetCache.texture("res://assets/ui/YUGITO.png")
    logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
    logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
    logo.mouse_filter = Control.MOUSE_FILTER_IGNORE
    logo.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
    add_child(logo)

func _panel(rect: Rect2, bg: Color, border: Color, radius: int, shadow_size: int = 0, shadow_color: Color = Color(0,0,0,0), shadow_offset: Vector2 = Vector2.ZERO) -> Panel:
    var panel := Panel.new()
    panel.position = rect.position
    panel.size = rect.size
    panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
    var style := StyleBoxFlat.new()
    var panel_bg: Color = bg
    var panel_border: Color = border
    if bg.a > 0.45 and bg.r < 0.25 and bg.g < 0.30 and bg.b < 0.38:
        panel_bg = Color(0.006,0.018,0.034,minf(0.68,maxf(0.42,bg.a*0.56)))
        panel_border = Color(border.r,border.g,border.b,maxf(0.30,minf(0.68,border.a+0.16)))
    style.bg_color = panel_bg
    style.border_color = panel_border
    style.set_border_width_all(1)
    style.set_corner_radius_all(radius)
    if shadow_size > 0:
        style.shadow_size = shadow_size
        style.shadow_color = shadow_color
        style.shadow_offset = shadow_offset
    panel.add_theme_stylebox_override("panel", style)
    add_child(panel)
    return panel

func _panel_in(parent: Control, rect: Rect2, bg: Color, border: Color, radius: int) -> Panel:
    var panel := Panel.new()
    panel.position = rect.position
    panel.size = rect.size
    panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
    var style := StyleBoxFlat.new()
    var panel_bg: Color = bg
    var panel_border: Color = border
    if bg.a > 0.45 and bg.r < 0.25 and bg.g < 0.30 and bg.b < 0.38:
        panel_bg = Color(0.006,0.018,0.034,minf(0.68,maxf(0.42,bg.a*0.56)))
        panel_border = Color(border.r,border.g,border.b,maxf(0.30,minf(0.68,border.a+0.16)))
    style.bg_color = panel_bg
    style.border_color = panel_border
    style.set_border_width_all(1)
    style.set_corner_radius_all(radius)
    style.shadow_color = Color(0,0,0,0.16)
    style.shadow_size = 4
    style.shadow_offset = Vector2(0,2)
    panel.add_theme_stylebox_override("panel", style)
    parent.add_child(panel)
    return panel

func _label(text_value: String, rect: Rect2, font_size: int, color: Color, align: HorizontalAlignment, bold: bool) -> Label:
    var label := Label.new()
    label.text = text_value
    label.position = rect.position
    label.size = rect.size
    label.horizontal_alignment = align
    label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    label.add_theme_font_size_override("font_size", font_size)
    label.add_theme_color_override("font_color", color)
    label.mouse_filter = Control.MOUSE_FILTER_IGNORE
    if bold:
        label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.42))
        label.add_theme_constant_override("shadow_offset_x", 1)
        label.add_theme_constant_override("shadow_offset_y", 1)
    add_child(label)
    return label

func _label_in(parent: Control, text_value: String, rect: Rect2, font_size: int, color: Color, align: HorizontalAlignment, bold: bool) -> Label:
    var label := Label.new()
    label.text = text_value
    label.position = rect.position
    label.size = rect.size
    label.horizontal_alignment = align
    label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    label.clip_text = true
    label.add_theme_font_size_override("font_size", font_size)
    label.add_theme_color_override("font_color", color)
    label.mouse_filter = Control.MOUSE_FILTER_IGNORE
    if bold:
        label.add_theme_color_override("font_shadow_color", Color(0,0,0,0.4))
        label.add_theme_constant_override("shadow_offset_x", 1)
        label.add_theme_constant_override("shadow_offset_y", 1)
    parent.add_child(label)
    return label
