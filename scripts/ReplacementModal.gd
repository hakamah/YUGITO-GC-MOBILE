class_name YugitoReplacementModal
extends CanvasLayer

const AssetCache = preload("res://scripts/AssetCache.gd")

signal choice_selected(index: int)
signal cancelled
signal timeout_choice(index: int)

var _root: Control
var _window: Panel
var _title: Label
var _subtitle: Label
var _hint: Label
var _choice_buttons: Array[Button] = []
var _choice_images: Array[TextureRect] = []
var _choice_names: Array[Label] = []
var _choice_meta: Array[Label] = []
var _choice_passive: Array[Label] = []
var _choice_choose: Array[Label] = []
var _cards: Dictionary = {}
var _candidate_ids: Array[String] = []
const REPLACEMENT_TIMEOUT_SECONDS := 30.0
var _timeout_enabled: bool = false
var _timeout_remaining: float = 0.0
var _timer_label: Label

func setup(card_data: Dictionary) -> void:
    _cards = card_data
    layer = 100

    _root = Control.new()
    _root.position = Vector2.ZERO
    _root.size = Vector2(1600, 900)
    _root.mouse_filter = Control.MOUSE_FILTER_STOP
    _root.z_index = 20000
    _root.visible = false
    add_child(_root)

    var dim := ColorRect.new()
    dim.position = Vector2.ZERO
    dim.size = Vector2(1600, 900)
    dim.color = Color(0.004, 0.010, 0.020, 0.56)
    dim.mouse_filter = Control.MOUSE_FILTER_STOP
    _root.add_child(dim)

    _window = Panel.new()
    _window.position = Vector2(145, 62)
    _window.size = Vector2(1310, 776)
    _window.mouse_filter = Control.MOUSE_FILTER_STOP
    var ws := StyleBoxFlat.new()
    ws.bg_color = Color(0.008, 0.022, 0.038, 0.82)
    ws.border_color = Color(1.0, 1.0, 1.0, 0.52)
    ws.set_border_width_all(2)
    ws.set_corner_radius_all(22)
    ws.shadow_color = Color(0, 0, 0, 0.24)
    ws.shadow_size = 18
    ws.shadow_offset = Vector2(0, 8)
    _window.add_theme_stylebox_override("panel", ws)
    _root.add_child(_window)

    _title = _make_label(_window, "REMPLACEMENT OBLIGATOIRE", Rect2(40, 26, 1230, 46), 29, Color("f3f6fa"), HORIZONTAL_ALIGNMENT_CENTER, true)
    _subtitle = _make_label(_window, "", Rect2(70, 78, 1170, 34), 13, Color("79d8ad"), HORIZONTAL_ALIGNMENT_CENTER, true)
    _hint = _make_label(_window, "Les cartes non choisies restent dans la réserve. Le remplaçant arrive avec son état de réserve.", Rect2(120, 716, 1070, 30), 10, Color("8ea2b8"), HORIZONTAL_ALIGNMENT_CENTER, false)
    _timer_label = _make_label(_window, "", Rect2(1130, 22, 120, 48), 25, Color("ffd34f"), HORIZONTAL_ALIGNMENT_CENTER, true)
    _timer_label.visible = false

    for i in range(5):
        var btn := Button.new()
        btn.position = Vector2(0, 132)
        btn.size = Vector2(220, 550)
        btn.text = ""
        btn.flat = true
        btn.focus_mode = Control.FOCUS_ALL
        btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
        var normal := StyleBoxFlat.new()
        normal.bg_color = Color(0.010, 0.028, 0.048, 0.72)
        normal.border_color = Color(1.0, 1.0, 1.0, 0.38)
        normal.set_border_width_all(1)
        normal.set_corner_radius_all(14)
        normal.shadow_color = Color(0,0,0,0.14)
        normal.shadow_size = 7
        normal.shadow_offset = Vector2(0,4)
        var hover := normal.duplicate() as StyleBoxFlat
        hover.bg_color = Color(0.028, 0.060, 0.090, 0.84)
        hover.border_color = Color(0.75, 0.91, 1.0, 0.86)
        hover.shadow_size = 11
        var pressed := hover.duplicate() as StyleBoxFlat
        pressed.bg_color = Color(0.92, 0.97, 1.0, 0.20)
        btn.add_theme_stylebox_override("normal", normal)
        btn.add_theme_stylebox_override("hover", hover)
        btn.add_theme_stylebox_override("pressed", pressed)
        btn.add_theme_stylebox_override("focus", hover)
        btn.pressed.connect(_emit_choice.bind(i))
        _window.add_child(btn)
        _choice_buttons.append(btn)

        var name_label := _make_label(btn, "NINJA", Rect2(12, 12, 196, 34), 14, Color("f2f6fa"), HORIZONTAL_ALIGNMENT_CENTER, true)
        _choice_names.append(name_label)

        var image := TextureRect.new()
        image.position = Vector2(12, 54)
        image.size = Vector2(196, 294)
        image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
        image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
        image.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
        image.mouse_filter = Control.MOUSE_FILTER_IGNORE
        btn.add_child(image)
        _choice_images.append(image)

        var meta := _make_label(btn, "", Rect2(12, 356, 196, 72), 10, Color("cbd7e3"), HORIZONTAL_ALIGNMENT_CENTER, true)
        meta.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
        _choice_meta.append(meta)

        var passive := _make_label(btn, "", Rect2(14, 426, 192, 58), 9, Color("8ea3b7"), HORIZONTAL_ALIGNMENT_CENTER, false)
        passive.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
        _choice_passive.append(passive)

        var choose := _make_label(btn, "CHOISIR CE NINJA", Rect2(18, 501, 184, 34), 11, Color("6fe1aa"), HORIZONTAL_ALIGNMENT_CENTER, true)
        choose.mouse_filter = Control.MOUSE_FILTER_IGNORE
        _choice_choose.append(choose)
        btn.visible = false

func is_open() -> bool:
    return _root != null and _root.visible

func show_choices(title_text: String, subtitle_text: String, ids: Array[String], enable_timeout: bool = false) -> void:
    if _root == null:
        return
    _candidate_ids = ids.duplicate()
    _timeout_enabled = enable_timeout and not _candidate_ids.is_empty()
    _timeout_remaining = REPLACEMENT_TIMEOUT_SECONDS if _timeout_enabled else 0.0
    _refresh_timer_label()
    _title.text = title_text
    _subtitle.text = subtitle_text

    var count: int = mini(ids.size(), 5)
    var card_w: float = 220.0
    var gap: float = 28.0
    if count <= 3:
        card_w = 280.0
        gap = 55.0
    var total: float = float(count) * card_w + float(maxi(0, count - 1)) * gap
    var start_x: float = (_window.size.x - total) * 0.5

    for i in range(_choice_buttons.size()):
        var btn: Button = _choice_buttons[i]
        if i >= count:
            btn.visible = false
            continue
        var cid: String = ids[i]
        var data: Dictionary = _cards.get(cid, {}) as Dictionary
        btn.position = Vector2(start_x + float(i) * (card_w + gap), 132)
        btn.size = Vector2(card_w, 550)
        btn.visible = true

        _choice_names[i].size.x = card_w - 24.0
        _choice_names[i].text = str(data.get("name", cid))
        _choice_images[i].size.x = card_w - 24.0
        var art_path: String = "res://assets/cards/%s_field.png" % cid
        _choice_images[i].texture = AssetCache.texture(art_path)
        _choice_meta[i].size.x = card_w - 24.0
        _choice_meta[i].text = "%s★   •   %d PV\nTAI %d   •   NIN %d   •   GEN %d\n%s" % [
            _stars_text(float(data.get("stars", 3.0))),
            int(data.get("hp", 0)), int(data.get("taijutsu", 0)), int(data.get("ninjutsu", 0)), int(data.get("genjutsu", 0)),
            str(data.get("element", "")).to_upper()
        ]
        _choice_passive[i].size.x = card_w - 28.0
        _choice_passive[i].text = "PASSIF • %s\nSPÉCIALE • %s" % [
            str(data.get("passive_name", "—")), str(data.get("special_name", "—"))
        ]
        btn.tooltip_text = "Choisir %s comme remplaçant" % str(data.get("name", cid))

    _root.visible = true
    if count > 0:
        _choice_buttons[0].call_deferred("grab_focus")

func hide_modal() -> void:
    if _root:
        _root.visible = false
    _timeout_enabled = false
    _timeout_remaining = 0.0
    _refresh_timer_label()
    _candidate_ids.clear()

func _process(delta: float) -> void:
    if not _timeout_enabled or _root == null or not _root.visible:
        return
    _timeout_remaining = maxf(0.0, _timeout_remaining - delta)
    _refresh_timer_label()
    if _timeout_remaining <= 0.0:
        _timeout_enabled = false
        var best_index := _best_timeout_choice_index()
        if best_index >= 0:
            timeout_choice.emit(best_index)

func _refresh_timer_label() -> void:
    if _timer_label == null:
        return
    _timer_label.visible = _timeout_enabled
    if _timeout_enabled:
        _timer_label.text = "%02d" % int(ceil(_timeout_remaining))

func _best_timeout_choice_index() -> int:
    var best_index: int = -1
    var best_stars: float = -1.0
    var best_total: int = -1
    var best_name: String = ""
    for i in range(_candidate_ids.size()):
        var cid: String = _candidate_ids[i]
        var data: Dictionary = _cards.get(cid, {}) as Dictionary
        var stars: float = float(data.get("stars", 0.0))
        var total: int = int(data.get("hp", 0)) + int(data.get("taijutsu", 0)) + int(data.get("ninjutsu", 0)) + int(data.get("genjutsu", 0))
        var name: String = str(data.get("name", cid))
        if stars > best_stars or (is_equal_approx(stars, best_stars) and (total > best_total or (total == best_total and name > best_name))):
            best_index = i
            best_stars = stars
            best_total = total
            best_name = name
    return best_index

func _emit_choice(index: int) -> void:
    if index < 0 or index >= _candidate_ids.size():
        return
    choice_selected.emit(index)

func _make_label(parent: Control, value: String, rect: Rect2, font_size: int, color: Color, align: HorizontalAlignment, bold: bool) -> Label:
    var label := Label.new()
    label.text = value
    label.position = rect.position
    label.size = rect.size
    label.horizontal_alignment = align
    label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    label.add_theme_font_size_override("font_size", font_size)
    label.add_theme_color_override("font_color", color)
    label.mouse_filter = Control.MOUSE_FILTER_IGNORE
    if bold:
        label.add_theme_color_override("font_shadow_color", Color(0,0,0,0.45))
        label.add_theme_constant_override("shadow_offset_x", 1)
        label.add_theme_constant_override("shadow_offset_y", 1)
    parent.add_child(label)
    return label

func _stars_text(v: float) -> String:
    if is_equal_approx(v, floor(v)):
        return "%d" % int(v)
    return "%.1f" % v
