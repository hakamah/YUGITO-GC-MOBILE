class_name YugitoMenuCard
extends Button

const AssetCache = preload("res://scripts/AssetCache.gd")

var card_id: String = ""
var data: Dictionary = {}
var accent: Color = Color("7c94ad")
var selected_state: bool = false
var muted_state: bool = false
var status_text: String = ""
var card_size: Vector2 = Vector2(230, 361)
# Même proportion que la carte de combat Godot (252 × 396).
const COMBAT_CARD_H_PER_W: float = 396.0 / 252.0
var _style_normal: StyleBoxFlat
var _style_hover: StyleBoxFlat
var _name_fs: int = 11
var _hp_fs: int = 9
var _info_fs: int = 8
var _elem_fs: int = 7
var _status_fs: int = 6
var _stat_code_fs: int = 7
var _stat_value_fs: int = 10

func setup(card_data: Dictionary, size_value: Vector2 = Vector2(230, 286), selected_value: bool = false, muted_value: bool = false, status_value: String = "") -> void:
    data = card_data
    card_id = str(data.get("id", ""))
    # P43 : les écrans catalogue/draft peuvent demander une carte plus haute
    # que le ratio combat afin de laisser respirer stats/passif/spéciale.
    var requested_w: float = maxf(150.0, size_value.x)
    var requested_h: float = size_value.y if size_value.y > 0.0 else round(requested_w * COMBAT_CARD_H_PER_W)
    card_size = Vector2(requested_w, maxf(requested_h, round(requested_w * 1.42)))
    selected_state = selected_value
    muted_state = muted_value
    status_text = status_value
    custom_minimum_size = card_size
    size = card_size
    text = ""
    flat = true
    focus_mode = Control.FOCUS_ALL
    mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
    clip_contents = false
    accent = _element_color(str(data.get("element", "")))
    var roles: Array = data.get("roles", []) as Array
    tooltip_text = "%s • %s★ • %s\n%s\nSpéciale : %s" % [
        str(data.get("name","Ninja")),
        str(data.get("stars","")),
        str(data.get("element","")),
        " • ".join(roles),
        str(data.get("special_name","—"))
    ]
    _build()

func _build() -> void:
    for child: Node in get_children():
        child.queue_free()
    _style_normal = StyleBoxFlat.new()
    _style_normal.bg_color = Color(0.96, 0.985, 1.0, 0.10)
    _style_normal.border_color = Color("fff0a0") if selected_state else Color(accent.r, accent.g, accent.b, 0.60 if not muted_state else 0.26)
    _style_normal.set_border_width_all(3 if selected_state else 1)
    _style_normal.set_corner_radius_all(12)
    _style_normal.shadow_color = Color(0, 0, 0, 0.18)
    _style_normal.shadow_size = 7 if selected_state else 4
    _style_normal.shadow_offset = Vector2(0, 4)
    _style_hover = _style_normal.duplicate() as StyleBoxFlat
    _style_hover.border_color = Color("ffe47a") if selected_state else Color(accent.r, accent.g, accent.b, 0.94)
    _style_hover.bg_color = Color(1.0, 1.0, 1.0, 0.18)
    add_theme_stylebox_override("normal", _style_normal)
    add_theme_stylebox_override("hover", _style_hover)
    add_theme_stylebox_override("pressed", _style_hover)
    add_theme_stylebox_override("focus", _style_hover)

    var w: float = card_size.x
    var h: float = card_size.y
    var mobile_text: bool = MobilePlatform.is_android()
    _name_fs = 12 if mobile_text else 11
    _hp_fs = 10 if mobile_text else 9
    _info_fs = 9 if mobile_text else 8
    _elem_fs = 8 if mobile_text else 7
    _status_fs = 7 if mobile_text else 6
    _stat_code_fs = 8 if mobile_text else 7
    _stat_value_fs = 11 if mobile_text else 10
    var header_h: float = 31.0
    var footer_h: float = 91.0
    var art_h: float = h - header_h - footer_h - 12.0

    var header: Panel = _panel(self, Rect2(5, 5, w - 10, header_h), Color(0.96,0.985,1.0,0.11), Color(accent.r,accent.g,accent.b,0.35), 8)
    _label(header, str(data.get("name", card_id)), Rect2(9, 0, w - 91, header_h), _name_fs, Color("f1f5f9"), HORIZONTAL_ALIGNMENT_LEFT, true)
    _label(header, "%d PV" % int(data.get("hp",0)), Rect2(w - 92, 0, 72, header_h), _hp_fs, Color("b8c7d5"), HORIZONTAL_ALIGNMENT_RIGHT, true)

    var art_clip: Panel = _panel(self, Rect2(6, header_h + 8, w - 12, art_h), Color(0.94,0.97,1.0,0.06), Color(1,1,1,0.05), 8)
    art_clip.clip_contents = true
    var art: TextureRect = TextureRect.new()
    art.position = Vector2.ZERO
    art.size = art_clip.size
    art.texture = AssetCache.texture("res://assets/cards/%s_field.png" % card_id)
    art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
    art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
    art.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
    art.mouse_filter = Control.MOUSE_FILTER_IGNORE
    art.modulate = Color(1,1,1,0.38 if muted_state else 1.0)
    art_clip.add_child(art)
    var shade: ColorRect = ColorRect.new()
    shade.position = Vector2(0, art_h - 40)
    shade.size = Vector2(w - 12, 40)
    shade.color = Color(0.01,0.02,0.04,0.30)
    shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
    art_clip.add_child(shade)

    var star_box: Panel = _panel(self, Rect2(13, header_h + 15, 48, 22), Color(0.06,0.05,0.014,0.92), Color("d6ae3d"), 6)
    _label(star_box, "%s★" % _stars_text(float(data.get("stars",0.0))), Rect2(2,0,44,22), _info_fs, Color("ffe477"), HORIZONTAL_ALIGNMENT_CENTER, true)
    var elem_box: Panel = _panel(self, Rect2(w - 51, header_h + art_h - 22, 38, 24), Color(0.02,0.04,0.065,0.94), accent, 7)
    _label(elem_box, str(data.get("element","")).to_upper(), Rect2(2,0,34,24), _elem_fs, accent.lightened(0.13), HORIZONTAL_ALIGNMENT_CENTER, true)

    var footer_y: float = header_h + art_h + 10.0
    var footer: Panel = _panel(self, Rect2(6, footer_y, w - 12, footer_h - 6), Color(0.96,0.985,1.0,0.10), Color(1,1,1,0.06), 8)
    var chip_w: float = (w - 30.0) / 3.0
    _stat_chip(footer, Rect2(5, 5, chip_w, 34), "TAI", int(data.get("taijutsu",0)), Color("ef6b5d"))
    _stat_chip(footer, Rect2(10 + chip_w, 5, chip_w, 34), "NIN", int(data.get("ninjutsu",0)), Color("56aef0"))
    _stat_chip(footer, Rect2(15 + chip_w * 2.0, 5, chip_w, 34), "GEN", int(data.get("genjutsu",0)), Color("b983ed"))
    _label(footer, "PASSIF • " + str(data.get("passive_name","—")), Rect2(7, 42, w - 28, 17), _info_fs, Color("64d5a3"), HORIZONTAL_ALIGNMENT_LEFT, true)
    _label(footer, "SPÉ • " + str(data.get("special_name","—")), Rect2(7, 59, w - 28, 17), _info_fs, Color("e3be54"), HORIZONTAL_ALIGNMENT_LEFT, true)

    if selected_state:
        var sel: Panel = _panel(self, Rect2(w - 91, 10, 76, 22), Color(0.08,0.065,0.015,0.96), Color("f0d25e"), 7)
        _label(sel, "✓ CHOISI", Rect2(2,0,72,22), 7, Color("ffe77d"), HORIZONTAL_ALIGNMENT_CENTER, true)
    elif not status_text.is_empty():
        var tag: Panel = _panel(self, Rect2(12, h - 24, w - 24, 18), Color(0.96,0.985,1.0,0.10), Color(accent.r,accent.g,accent.b,0.28), 6)
        _label(tag, status_text, Rect2(3,0,w - 30,18), _status_fs, Color("8ea5ba") if muted_state else accent.lightened(0.10), HORIZONTAL_ALIGNMENT_CENTER, true)

func _stat_chip(parent: Node, rect: Rect2, code: String, value: int, color: Color) -> void:
    var p: Panel = _panel(parent, rect, Color(0.96,0.985,1.0,0.09), Color(color.r,color.g,color.b,0.44), 6)
    _label(p, code, Rect2(1,0,rect.size.x-2,13), _stat_code_fs, color.lightened(0.12), HORIZONTAL_ALIGNMENT_CENTER, true)
    _label(p, str(value), Rect2(1,12,rect.size.x-2,20), _stat_value_fs, Color("f3f6fa"), HORIZONTAL_ALIGNMENT_CENTER, true)

func _panel(parent: Node, rect: Rect2, bg: Color, border: Color, radius: int) -> Panel:
    var p: Panel = Panel.new()
    p.position = rect.position
    p.size = rect.size
    p.mouse_filter = Control.MOUSE_FILTER_IGNORE
    var s: StyleBoxFlat = StyleBoxFlat.new()
    s.bg_color = bg
    s.border_color = border
    s.set_border_width_all(1)
    s.set_corner_radius_all(radius)
    p.add_theme_stylebox_override("panel", s)
    parent.add_child(p)
    return p

func _label(parent: Node, value: String, rect: Rect2, font_size: int, color: Color, align: HorizontalAlignment, bold: bool) -> Label:
    var l: Label = Label.new()
    l.text = value
    l.position = rect.position
    l.size = rect.size
    l.horizontal_alignment = align
    l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    l.clip_text = true
    l.add_theme_font_size_override("font_size", font_size)
    l.add_theme_color_override("font_color", color)
    l.mouse_filter = Control.MOUSE_FILTER_IGNORE
    if bold:
        l.add_theme_color_override("font_shadow_color", Color(0,0,0,0.40))
        l.add_theme_constant_override("shadow_offset_x",1)
        l.add_theme_constant_override("shadow_offset_y",1)
    parent.add_child(l)
    return l

func _stars_text(value: float) -> String:
    if is_equal_approx(value, floorf(value)):
        return "%d" % int(value)
    return "%.1f" % value

func _element_color(element: String) -> Color:
    match element.to_lower():
        "feu": return Color("ef6256")
        "vent": return Color("63d596")
        "foudre": return Color("c09aff")
        "terre": return Color("c79b6b")
        "eau": return Color("55b6f2")
        "tous": return Color("f3d46d")
        _: return Color("7c94ad")
