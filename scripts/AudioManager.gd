extends Node

signal settings_changed(music_percent: float, sfx_percent: float)

const AssetCache = preload("res://scripts/AssetCache.gd")
const SETTINGS_PATH: String = "user://yugito_audio.json"
const SFX_POOL_SIZE: int = 12

var music_percent: float = 38.0
var sfx_percent: float = 58.0

var _music_player: AudioStreamPlayer
var _music_path: String = ""
var _music_trim_db: float = 0.0
var _music_paused: bool = false

var _sfx_pool: Array[AudioStreamPlayer] = []
var _next_sfx_index: int = 0

func _ready() -> void:
    process_mode = Node.PROCESS_MODE_ALWAYS
    _load_settings()

    _music_player = AudioStreamPlayer.new()
    _music_player.name = "GlobalMusic"
    _music_player.process_mode = Node.PROCESS_MODE_ALWAYS
    add_child(_music_player)

    for i: int in range(SFX_POOL_SIZE):
        var player := AudioStreamPlayer.new()
        player.name = "GlobalSFX%02d" % i
        player.process_mode = Node.PROCESS_MODE_ALWAYS
        add_child(player)
        _sfx_pool.append(player)

func _percent_db(percent: float) -> float:
    if percent <= 0.05:
        return -80.0
    return linear_to_db(clampf(percent,0.0,100.0) / 100.0)

func _music_db() -> float:
    return _percent_db(music_percent) + _music_trim_db

func get_music_percent() -> float:
    return music_percent

func get_sfx_percent() -> float:
    return sfx_percent

func set_music_percent(value: float, persist: bool = true) -> void:
    music_percent = clampf(value,0.0,100.0)
    if _music_player != null:
        _music_player.volume_db = _music_db()
    if persist:
        _save_settings()
    settings_changed.emit(music_percent,sfx_percent)

func set_sfx_percent(value: float, persist: bool = true) -> void:
    sfx_percent = clampf(value,0.0,100.0)
    if persist:
        _save_settings()
    settings_changed.emit(music_percent,sfx_percent)

func play_music(path: String, trim_db: float = 0.0, restart: bool = false) -> void:
    if path.is_empty():
        return
    if _music_player == null:
        return

    # Même morceau : on met seulement à jour son trim / volume.
    if path == _music_path and _music_player.stream != null and not restart:
        _music_trim_db = trim_db
        _music_player.volume_db = _music_db()
        if not _music_player.playing and not _music_paused:
            _music_player.play()
        return

    var stream: AudioStream = AssetCache.audio(path)
    if stream == null:
        push_warning("AudioManager: musique absente: " + path)
        return
    if stream is AudioStreamMP3:
        (stream as AudioStreamMP3).loop = true

    _music_path = path
    _music_trim_db = trim_db
    _music_paused = false
    _music_player.stop()
    _music_player.stream = stream
    _music_player.volume_db = _music_db()
    _music_player.play()

func stop_music() -> void:
    _music_paused = false
    if _music_player != null:
        _music_player.stop()

func pause_music() -> void:
    if _music_player == null or not _music_player.playing:
        return
    _music_player.stream_paused = true
    _music_paused = true

func resume_music() -> void:
    if _music_player == null:
        return
    if _music_player.stream != null:
        _music_player.stream_paused = false
        _music_paused = false
        if not _music_player.playing:
            _music_player.play()

func current_music_path() -> String:
    return _music_path

func play_sfx(path: String, trim_db: float = 0.0, pitch_scale: float = 1.0) -> void:
    if path.is_empty() or sfx_percent <= 0.05 or _sfx_pool.is_empty():
        return
    var stream: AudioStream = AssetCache.audio(path)
    if stream == null:
        return

    var player: AudioStreamPlayer = null
    # Priorité à un lecteur libre.
    for candidate: AudioStreamPlayer in _sfx_pool:
        if not candidate.playing:
            player = candidate
            break
    # Sinon, recyclage circulaire (évite toute allocation pendant le combat).
    if player == null:
        player = _sfx_pool[_next_sfx_index]
        _next_sfx_index = (_next_sfx_index + 1) % _sfx_pool.size()
        player.stop()

    player.stream = stream
    player.volume_db = _percent_db(sfx_percent) + trim_db
    player.pitch_scale = clampf(pitch_scale,0.5,2.0)
    player.play()

func preview_music() -> void:
    play_music("res://assets/audio/music/menu.mp3",0.0,true)

func preview_sfx() -> void:
    play_sfx("res://assets/audio/ui/pick.mp3",-5.0)

func _load_settings() -> void:
    if not FileAccess.file_exists(SETTINGS_PATH):
        return
    var file := FileAccess.open(SETTINGS_PATH,FileAccess.READ)
    if file == null:
        return
    var parsed: Variant = JSON.parse_string(file.get_as_text())
    if parsed is Dictionary:
        music_percent = clampf(float((parsed as Dictionary).get("music",music_percent)),0.0,100.0)
        sfx_percent = clampf(float((parsed as Dictionary).get("sfx",sfx_percent)),0.0,100.0)

func _save_settings() -> void:
    var file := FileAccess.open(SETTINGS_PATH,FileAccess.WRITE)
    if file == null:
        return
    file.store_string(JSON.stringify({
        "music":music_percent,
        "sfx":sfx_percent
    }))
