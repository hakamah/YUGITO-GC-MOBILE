class_name YugitoDraftCanvas
extends Control
# P47M.5 — Native Canvas Draft.
# One atlas texture + one cached CanvasItem for the whole 70-card catalog.
# The ScrollContainer moves this surface natively; no card Nodes are created
# or destroyed while the user scrolls.

signal card_tapped(card_id: String)

const DRAFT_ATLAS: Texture2D = preload("res://assets/ui/draft_catalog_mobile.png")

const COLUMNS: int = 3
const CARD_SIZE: Vector2 = Vector2(240.0, 306.0)
const H_GAP: float = 8.0
const V_GAP: float = 10.0
const ROW_HEIGHT: float = 316.0
const CONTENT_SIZE: Vector2 = Vector2(736.0, 7574.0)
const TAP_DEADZONE: float = 12.0

var _cards: Array[Dictionary] = []
var _owner_by_id: Dictionary = {}
var _available_by_id: Dictionary = {}
var _interactive_by_id: Dictionary = {}
var _reason_by_id: Dictionary = {}
var _selected_id: String = ""

var _touch_down: bool = false
var _touch_start: Vector2 = Vector2.ZERO
var _touch_moved: bool = false

func _ready() -> void:
    custom_minimum_size = CONTENT_SIZE
    size = CONTENT_SIZE
    mouse_filter = Control.MOUSE_FILTER_PASS
    focus_mode = Control.FOCUS_NONE

func configure(
    card_data: Array[Dictionary],
    owner_by_id: Dictionary,
    available_by_id: Dictionary,
    interactive_by_id: Dictionary,
    reason_by_id: Dictionary,
    selected_id: String
) -> void:
    _cards = card_data
    _owner_by_id = owner_by_id
    _available_by_id = available_by_id
    _interactive_by_id = interactive_by_id
    _reason_by_id = reason_by_id
    _selected_id = selected_id
    custom_minimum_size = CONTENT_SIZE
    size = CONTENT_SIZE
    queue_redraw()

func set_selected(card_id: String) -> void:
    if _selected_id == card_id:
        return
    _selected_id = card_id
    queue_redraw()

func _draw() -> void:
    # Static catalog = ONE texture draw command.
    draw_texture(DRAFT_ATLAS, Vector2.ZERO)

    # Dynamic overlays are rebuilt only when draft state/selection changes.
    # During scrolling these commands remain cached and the ScrollContainer
    # only moves this CanvasItem.
    var font: Font = ThemeDB.fallback_font
    for index: int in range(_cards.size()):
        var data: Dictionary = _cards[index]
        var cid: String = str(data.get("id", ""))
        var rect: Rect2 = _card_rect(index)
        var owner: String = str(_owner_by_id.get(cid, ""))
        var available: bool = bool(_available_by_id.get(cid, false))
        var reason: String = str(_reason_by_id.get(cid, ""))

        if not owner.is_empty() or not available:
            draw_rect(rect, Color(0.002, 0.008, 0.014, 0.58), true)

        if cid == _selected_id:
            draw_rect(rect.grow(-2.0), Color("fff0a0"), false, 3.0)

        # "DISPONIBLE" is baked into the atlas. Only lock/owner reasons need
        # dynamic text, which further reduces per-frame canvas commands.
        if not reason.is_empty() and reason != "DISPONIBLE":
            var reason_bg := Rect2(rect.position + Vector2(88.0, 249.0), Vector2(140.0, 20.0))
            draw_rect(reason_bg, Color(0.008, 0.018, 0.030, 0.86), true)
            draw_string(
                font,
                rect.position + Vector2(94.0, 263.0),
                _compact_reason(reason),
                HORIZONTAL_ALIGNMENT_RIGHT,
                128.0,
                7,
                Color("a3b2bf")
            )

func _gui_input(event: InputEvent) -> void:
    # Important: never call accept_event() here.
    # Events keep bubbling to ScrollContainer, which keeps its native C++
    # touch scrolling, deadzone, velocity and inertia.

    if event is InputEventScreenTouch:
        var touch: InputEventScreenTouch = event as InputEventScreenTouch
        if touch.pressed:
            _touch_down = true
            _touch_start = touch.position
            _touch_moved = false
        else:
            if _touch_down and not _touch_moved:
                _try_emit_card(touch.position)
            _touch_down = false
            _touch_moved = false
        return

    if event is InputEventScreenDrag:
        if _touch_down:
            var drag: InputEventScreenDrag = event as InputEventScreenDrag
            if drag.position.distance_to(_touch_start) >= TAP_DEADZONE:
                _touch_moved = true
        return

    # Useful for Android desktop mode / emulator. Wheel events are deliberately
    # ignored here so ScrollContainer handles them natively.
    if event is InputEventMouseButton:
        var mouse: InputEventMouseButton = event as InputEventMouseButton
        if mouse.button_index != MOUSE_BUTTON_LEFT:
            return
        if mouse.pressed:
            _touch_down = true
            _touch_start = mouse.position
            _touch_moved = false
        else:
            if _touch_down and not _touch_moved:
                _try_emit_card(mouse.position)
            _touch_down = false
            _touch_moved = false
        return

    if event is InputEventMouseMotion and _touch_down:
        var motion: InputEventMouseMotion = event as InputEventMouseMotion
        if motion.position.distance_to(_touch_start) >= TAP_DEADZONE:
            _touch_moved = true

func _try_emit_card(local_pos: Vector2) -> void:
    var index: int = _card_index_at(local_pos)
    if index < 0 or index >= _cards.size():
        return

    var data: Dictionary = _cards[index]
    var cid: String = str(data.get("id", ""))
    if cid.is_empty():
        return
    if not bool(_interactive_by_id.get(cid, false)):
        return

    card_tapped.emit(cid)

func _card_index_at(local_pos: Vector2) -> int:
    if local_pos.x < 0.0 or local_pos.y < 0.0:
        return -1

    var cell_width: float = CARD_SIZE.x + H_GAP
    var column: int = int(floor(local_pos.x / cell_width))
    var row: int = int(floor(local_pos.y / ROW_HEIGHT))
    if column < 0 or column >= COLUMNS or row < 0:
        return -1

    var inside_x: float = local_pos.x - float(column) * cell_width
    var inside_y: float = local_pos.y - float(row) * ROW_HEIGHT
    if inside_x > CARD_SIZE.x or inside_y > CARD_SIZE.y:
        return -1

    return row * COLUMNS + column

func _card_rect(index: int) -> Rect2:
    var row: int = index / COLUMNS
    var column: int = index % COLUMNS
    return Rect2(
        Vector2(
            float(column) * (CARD_SIZE.x + H_GAP),
            float(row) * ROW_HEIGHT
        ),
        CARD_SIZE
    )

func _compact_reason(reason: String) -> String:
    match reason:
        "DÉJÀ DANS TON DECK":
            return "DANS TON DECK"
        "CHOISI PAR L'ADVERSAIRE":
            return "PRIS ADVERSAIRE"
        "DÉPASSERAIT 32,5★":
            return "> 32,5★"
        "DECK COMPLET":
            return "DECK COMPLET"
        _:
            if reason.begins_with("PALIER "):
                return "PALIER BLOQUÉ"
            if reason.begins_with("QUOTA "):
                return "QUOTA ATTEINT"
            return reason

static func card_tile_rect(index: int) -> Rect2:
    var row: int = index / COLUMNS
    var column: int = index % COLUMNS
    return Rect2(
        Vector2(
            float(column) * (CARD_SIZE.x + H_GAP),
            float(row) * ROW_HEIGHT
        ),
        CARD_SIZE
    )

static func card_art_texture(index: int) -> AtlasTexture:
    var tile: Rect2 = card_tile_rect(index)
    var texture := AtlasTexture.new()
    texture.atlas = DRAFT_ATLAS
    texture.region = Rect2(tile.position + Vector2(6.0, 42.0), Vector2(228.0, 205.0))
    return texture
