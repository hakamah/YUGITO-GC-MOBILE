extends Control

const INTRO_PATH: String = "res://assets/video/intro.ogv"
const NEXT_SCENE: String = "res://Main.tscn"
const FAILSAFE_SECONDS: float = 12.0

var _finished: bool = false
var _video: VideoStreamPlayer

func _ready() -> void:
    process_mode = Node.PROCESS_MODE_ALWAYS
    set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    mouse_filter = Control.MOUSE_FILTER_STOP

    var background := ColorRect.new()
    background.color = Color.BLACK
    background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    background.mouse_filter = Control.MOUSE_FILTER_IGNORE
    add_child(background)

    _video = VideoStreamPlayer.new()
    _video.name = "IntroVideo"
    _video.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    _video.expand = true
    _video.loop = false
    _video.volume_db = 0.0
    _video.mouse_filter = Control.MOUSE_FILTER_IGNORE
    _video.stream = load(INTRO_PATH) as VideoStream
    add_child(_video)

    if _video.stream == null:
        push_error("BootIntro: impossible de charger %s" % INTRO_PATH)
        _go_to_main()
        return

    _video.finished.connect(_go_to_main)

    var failsafe := Timer.new()
    failsafe.one_shot = true
    failsafe.wait_time = FAILSAFE_SECONDS
    failsafe.timeout.connect(_go_to_main)
    add_child(failsafe)
    failsafe.start()

    _video.play()

func _go_to_main() -> void:
    if _finished:
        return
    _finished = true
    if is_instance_valid(_video):
        _video.stop()
    get_tree().change_scene_to_file(NEXT_SCENE)
