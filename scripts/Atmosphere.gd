class_name YugitoAtmosphere
extends Node2D

var motes: Array[Dictionary] = []
var streaks: Array[Dictionary] = []
var t: float = 0.0
var _redraw_accumulator: float = 0.0
const REDRAW_STEP: float = 1.0 / 60.0

func _ready() -> void:
    z_index = -5
    var rng: RandomNumberGenerator = RandomNumberGenerator.new()
    rng.seed = 0x59475549544F03
    for i in range(46):
        var side_mix: float = rng.randf()
        motes.append({
            "p": Vector2(rng.randf_range(205.0, 1125.0), rng.randf_range(145.0, 780.0)),
            "r": rng.randf_range(0.55, 1.75),
            "a": rng.randf_range(0.025, 0.085),
            "s": rng.randf_range(2.0, 7.0),
            "ph": rng.randf_range(0.0, TAU),
            "mix": side_mix,
        })
    for i in range(9):
        streaks.append({
            "phase": rng.randf(),
            "speed": rng.randf_range(0.018, 0.038),
            "lane": rng.randf_range(-9.0, 9.0),
            "alpha": rng.randf_range(0.025, 0.065),
        })
    queue_redraw()

func _process(delta: float) -> void:
    # Animation time remains delta-based, so 60/120/144 Hz have the same speed.
    t += delta
    _redraw_accumulator += delta
    if _redraw_accumulator >= REDRAW_STEP:
        _redraw_accumulator = fmod(_redraw_accumulator, REDRAW_STEP)
        queue_redraw()

func _draw() -> void:
    var center: Vector2 = Vector2(660.0, 458.0)

    # Respiration centrale très sombre / premium, jamais une grosse tache blanche.
    for i in range(8, 0, -1):
        var radius: float = 62.0 + float(i) * 42.0
        var pulse: float = 0.92 + 0.08 * sin(t * 0.19 + float(i) * 0.41)
        var alpha: float = (0.003 + float(9 - i) * 0.0019) * pulse
        draw_circle(center, radius, Color(0.12, 0.42, 0.78, alpha))

    # Deux anneaux presque fantômes donnent une profondeur au milieu du duel.
    var ring_pulse: float = 0.5 + 0.5 * sin(t * 0.30)
    draw_arc(center, 82.0 + ring_pulse * 3.0, 0.0, TAU, 96, Color(0.38, 0.73, 1.0, 0.045), 1.0, true)
    draw_arc(center, 126.0 - ring_pulse * 4.0, 0.0, TAU, 128, Color(0.56, 0.37, 0.92, 0.026), 1.0, true)

    # Ligne d'énergie centrale : plusieurs couches très transparentes.
    draw_line(Vector2(225, 458), Vector2(1115, 458), Color(0.24, 0.62, 1.0, 0.026), 13.0, true)
    draw_line(Vector2(225, 458), Vector2(1115, 458), Color(0.42, 0.76, 1.0, 0.060), 3.0, true)
    draw_line(Vector2(225, 458), Vector2(1115, 458), Color(0.82, 0.94, 1.0, 0.13), 1.0, true)

    # Minuscules filaments qui traversent lentement le centre.
    for s in streaks:
        var phase: float = fmod(float(s["phase"]) + t * float(s["speed"]), 1.0)
        var sx: float = lerpf(245.0, 1090.0, phase)
        var sy: float = 458.0 + float(s["lane"]) + sin(phase * TAU * 1.7) * 3.0
        var length: float = 22.0 + 16.0 * sin(phase * PI)
        draw_line(Vector2(sx - length, sy), Vector2(sx, sy), Color(0.57, 0.84, 1.0, float(s["alpha"]) * sin(phase * PI)), 1.0, true)

    # Motes chakra : bleu/froid en haut, plus chaud et vert discret vers le bas.
    for m in motes:
        var p: Vector2 = m["p"]
        var phase_value: float = float(m["ph"])
        var sway: Vector2 = Vector2(
            sin(t * 0.15 + phase_value) * float(m["s"]),
            cos(t * 0.11 + phase_value * 1.37) * float(m["s"]) * 0.55
        )
        var mix_value: float = float(m["mix"])
        var cold: Color = Color(0.55, 0.82, 1.0, float(m["a"]))
        var warm: Color = Color(0.45, 0.94, 0.69, float(m["a"]) * 0.72)
        draw_circle(p + sway, float(m["r"]), cold.lerp(warm, mix_value * 0.55))
