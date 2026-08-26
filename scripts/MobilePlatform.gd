extends Node

signal back_requested
signal landscape_confirmed

const VIRTUAL_SIZE: Vector2i = Vector2i(1600, 900)

var android: bool = false
var touchscreen: bool = false

func _ready() -> void:
    android = OS.get_name() == "Android"
    touchscreen = DisplayServer.has_feature(DisplayServer.FEATURE_TOUCHSCREEN)
    process_mode = Node.PROCESS_MODE_ALWAYS
    if android:
        _lock_landscape()
        DisplayServer.screen_set_keep_on(true)
        landscape_confirmed.emit()

func is_android() -> bool:
    return android

func is_touch() -> bool:
    return touchscreen or android

func _lock_landscape() -> void:
    if not android:
        return
    if DisplayServer.has_feature(DisplayServer.FEATURE_ORIENTATION):
        DisplayServer.screen_set_orientation(DisplayServer.SCREEN_SENSOR_LANDSCAPE)

func enforce_landscape() -> void:
    _lock_landscape()

func recommended_card_columns(default_columns: int) -> int:
    if android:
        return mini(default_columns, 3)
    return default_columns

func recommended_touch_height(base_height: float) -> float:
    if android:
        return maxf(base_height, 36.0)
    return base_height

func _notification(what: int) -> void:
    if what == NOTIFICATION_WM_GO_BACK_REQUEST and android:
        back_requested.emit()
