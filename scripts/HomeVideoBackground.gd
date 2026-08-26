class_name YugitoHomeVideoBackground
extends VideoStreamPlayer

func _ready() -> void:
    set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    mouse_filter = Control.MOUSE_FILTER_IGNORE
    expand = true
    autoplay = true
    loop = true
    var path: String = "res://assets/video/home_bg_mobile.ogv" if MobilePlatform.is_android() else "res://assets/video/home_bg.ogv"
    stream = load(path) as VideoStream
    if stream == null and path != "res://assets/video/home_bg.ogv":
        stream = load("res://assets/video/home_bg.ogv") as VideoStream
    if stream != null and not is_playing():
        play()
