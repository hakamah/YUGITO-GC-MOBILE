class_name YugitoAssetCache
extends RefCounted

static var _textures: Dictionary = {}
static var _audio: Dictionary = {}

static func texture(path: String) -> Texture2D:
    if path.is_empty():
        return null
    if not _textures.has(path):
        _textures[path] = load(path) as Texture2D
    return _textures[path] as Texture2D

static func audio(path: String) -> AudioStream:
    if path.is_empty():
        return null
    if not _audio.has(path):
        _audio[path] = load(path) as AudioStream
    return _audio[path] as AudioStream

static func texture_cache_size() -> int:
    return _textures.size()

static func audio_cache_size() -> int:
    return _audio.size()
