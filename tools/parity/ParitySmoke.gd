extends SceneTree

const CardActor = preload("res://scripts/CardActor.gd")
const ParityRNG = preload("res://scripts/ParityRNG.gd")

func _fail(message: String) -> void:
    push_error("[PARITY FAIL] " + message)
    quit(1)

func _require(condition: bool, message: String) -> void:
    if not condition:
        _fail(message)

func _card_by_id(card_id: String) -> Dictionary:
    var raw: String = FileAccess.get_file_as_string("res://data/cards.json")
    var parsed: Variant = JSON.parse_string(raw)
    if not (parsed is Array):
        return {}
    for item: Variant in parsed:
        if item is Dictionary and str((item as Dictionary).get("id", "")) == card_id:
            return (item as Dictionary).duplicate(true)
    return {}

func _initialize() -> void:
    print("YUGITO 09 / P15 — Godot parity smoke")

    var rng = ParityRNG.new()
    rng.configure(true, 1)
    var expected: Array[int] = [1015568748, 1586005467, 2165703038, 3027450565, 217083232]
    for value: int in expected:
        var got: int = int(round(rng.randf() * 4294967296.0))
        _require(got == value, "RNG portable diverge : %d != %d" % [got, value])
    print("[OK] RNG déterministe portable")

    var rin_data: Dictionary = _card_by_id("rin")
    _require(not rin_data.is_empty(), "Rin absente de cards.json")
    var rin = CardActor.new()
    rin.setup_logic_only(rin_data, 3, "ally")
    rin.base_max_hp += 1000
    rin.max_hp += 1000
    rin.hp = rin.max_hp - 333
    rin.stat_buffs["ninjutsu"] = 300
    rin.status_tags["rin_isobu_active"] = true
    rin.add_shield(222)
    rin.set_synergy_bonus(0.20)
    var expected_max: int = rin.base_max_hp + int(round(float(rin.definition_max_hp) * 0.20))
    _require(rin.max_hp == expected_max, "Synergie Rin amplifie à tort les +PV permanents")

    var saved: Dictionary = rin.export_state()
    var rin_back = CardActor.new()
    rin_back.setup_logic_only(rin_data, 3, "ally")
    rin_back.import_state(saved)
    _require(rin_back.definition_max_hp == rin.definition_max_hp, "definition_max_hp perdu")
    _require(rin_back.base_max_hp == rin.base_max_hp, "base_max_hp perdu")
    _require(rin_back.max_hp == rin.max_hp, "max_hp perdu")
    _require(rin_back.hp == rin.hp and rin_back.shield == rin.shield, "PV/bouclier perdus")
    _require(int(rin_back.stat_buffs.get("ninjutsu", 0)) == 300, "buff permanent perdu")
    _require(bool(rin_back.status_tags.get("rin_isobu_active", false)), "transformation Rin perdue")
    print("[OK] état complet terrain -> réserve -> terrain")

    var gen_data: Dictionary = _card_by_id("gengetsu")
    _require(not gen_data.is_empty(), "Gengetsu absent de cards.json")
    var gen = CardActor.new()
    gen.setup_logic_only(gen_data, 0, "ally")
    gen.status_tags["gengetsu_clone_active"] = true
    gen.max_hp = 4800
    gen.hp = 3600
    gen.set_synergy_bonus(0.20)
    _require(gen.max_hp == 4800, "la synergie modifie le clone 4800 PV")
    print("[OK] clone Gengetsu stable sous recalcul de synergie")

    print("ALL GODOT PARITY SMOKES PASSED")
    quit(0)
