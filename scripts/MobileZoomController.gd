extends Node
# P52 — Zoom mobile global contrôlé.
# 2 doigts = pinch + déplacement simultané.
# 1 doigt reste entièrement réservé au jeu (cartes, boutons, scroll, etc.).

const MIN_ZOOM: float = 1.0
const MAX_ZOOM: float = 2.0
const ZOOM_EPSILON: float = 0.001

var _touches: Dictionary = {}
var _zoom: float = 1.0
var _offset: Vector2 = Vector2.ZERO

var _pinching: bool = false
var _last_distance: float = 0.0
var _last_center: Vector2 = Vector2.ZERO


func _ready() -> void:
    if not _is_android():
        set_process_input(false)
        return

    set_process_input(true)
    var viewport := get_viewport()
    if viewport != null and not viewport.size_changed.is_connected(_on_viewport_size_changed):
        viewport.size_changed.connect(_on_viewport_size_changed)
    _apply_transform()


func _is_android() -> bool:
    return OS.get_name() == "Android"


func _input(event: InputEvent) -> void:
    if not _is_android():
        return

    if event is InputEventScreenTouch:
        var touch := event as InputEventScreenTouch

        if touch.pressed:
            _touches[touch.index] = touch.position
        else:
            _touches.erase(touch.index)

        if _touches.size() >= 2:
            if not _pinching:
                _begin_pinch()
            # À partir du deuxième doigt, on réserve le geste au zoom.
            get_viewport().set_input_as_handled()
        else:
            _pinching = false
            _last_distance = 0.0

        return

    if event is InputEventScreenDrag:
        var drag := event as InputEventScreenDrag
        _touches[drag.index] = drag.position

        if _touches.size() < 2:
            # Un seul doigt ne déplace JAMAIS le viewport :
            # le jeu conserve son comportement tactile normal.
            return

        if not _pinching:
            _begin_pinch()
            get_viewport().set_input_as_handled()
            return

        _update_pinch()
        get_viewport().set_input_as_handled()


func _begin_pinch() -> void:
    var pair := _first_two_touch_positions()
    if pair.size() < 2:
        return

    var p0: Vector2 = pair[0]
    var p1: Vector2 = pair[1]
    _last_center = (p0 + p1) * 0.5
    _last_distance = maxf(1.0, p0.distance_to(p1))
    _pinching = true


func _update_pinch() -> void:
    var pair := _first_two_touch_positions()
    if pair.size() < 2:
        _pinching = false
        return

    var p0: Vector2 = pair[0]
    var p1: Vector2 = pair[1]
    var center: Vector2 = (p0 + p1) * 0.5
    var distance: float = maxf(1.0, p0.distance_to(p1))

    if _last_distance <= 0.0:
        _last_distance = distance
        _last_center = center
        return

    var old_zoom: float = _zoom
    var ratio: float = distance / _last_distance
    var new_zoom: float = clampf(old_zoom * ratio, MIN_ZOOM, MAX_ZOOM)

    # Le point situé sous le centre des deux doigts reste sous les doigts.
    # Le déplacement des deux doigts produit naturellement le pan.
    var world_focus: Vector2 = (_last_center - _offset) / old_zoom
    _zoom = new_zoom
    _offset = center - world_focus * _zoom

    _clamp_offset()
    _apply_transform()

    _last_center = center
    _last_distance = distance


func _first_two_touch_positions() -> Array[Vector2]:
    var ids: Array = _touches.keys()
    ids.sort()

    var result: Array[Vector2] = []
    for id: Variant in ids:
        if result.size() >= 2:
            break
        result.append(_touches[id] as Vector2)
    return result


func _clamp_offset() -> void:
    var viewport := get_viewport()
    if viewport == null:
        _offset = Vector2.ZERO
        return

    var view_size: Vector2 = viewport.get_visible_rect().size

    # Le contenu logique occupe exactement le viewport Godot (1600x900).
    # À zoom 1 : offset obligatoire = 0.
    # À zoom > 1 : on autorise seulement le déplacement nécessaire pour
    # parcourir le contenu agrandi, sans jamais révéler de vide hors cadre.
    var min_x: float = view_size.x - view_size.x * _zoom
    var min_y: float = view_size.y - view_size.y * _zoom

    _offset.x = clampf(_offset.x, min_x, 0.0)
    _offset.y = clampf(_offset.y, min_y, 0.0)

    if absf(_zoom - MIN_ZOOM) <= ZOOM_EPSILON:
        _zoom = MIN_ZOOM
        _offset = Vector2.ZERO


func _apply_transform() -> void:
    var viewport := get_viewport()
    if viewport == null:
        return

    viewport.canvas_transform = Transform2D(
        Vector2(_zoom, 0.0),
        Vector2(0.0, _zoom),
        _offset
    )


func _on_viewport_size_changed() -> void:
    _clamp_offset()
    _apply_transform()


func reset_zoom() -> void:
    _zoom = MIN_ZOOM
    _offset = Vector2.ZERO
    _pinching = false
    _last_distance = 0.0
    _apply_transform()


func zoom_value() -> float:
    return _zoom
