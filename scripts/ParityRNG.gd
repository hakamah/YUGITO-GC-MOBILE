class_name YugitoParityRNG
extends RefCounted

# RNG de combat avec deux modes :
# - normal : RandomNumberGenerator Godot randomisé ;
# - parité : LCG 32 bits portable, reproduisible bit pour bit dans le harness Python.
# Le mode parité ne change donc pas le RNG joueur normal ; il sert uniquement aux
# scénarios automatiques PC <-> Godot demandés dans la feuille de route.

var deterministic: bool = false
var _state: int = 1
var _normal: RandomNumberGenerator = RandomNumberGenerator.new()

func configure(use_deterministic: bool, seed_value: int = 1) -> void:
    deterministic = use_deterministic
    if deterministic:
        _state = int(seed_value) & 0xffffffff
        if _state == 0:
            _state = 0x6d2b79f5
    else:
        _normal.randomize()

func _next_u32() -> int:
    _state = int((1664525 * _state + 1013904223) & 0xffffffff)
    return _state

func randf() -> float:
    if deterministic:
        return float(_next_u32()) / 4294967296.0
    return _normal.randf()

func randi_range(min_value: int, max_value: int) -> int:
    if max_value <= min_value:
        return min_value
    if deterministic:
        var span: int = max_value - min_value + 1
        return min_value + int(_next_u32() % span)
    return _normal.randi_range(min_value, max_value)

func shuffled_strings(values: Array[String]) -> Array[String]:
    var result: Array[String] = values.duplicate()
    for i: int in range(result.size() - 1, 0, -1):
        var j: int = randi_range(0, i)
        var tmp: String = result[i]
        result[i] = result[j]
        result[j] = tmp
    return result
