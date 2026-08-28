class_name YugitoCardActor
extends Node2D

const AssetCache = preload("res://scripts/AssetCache.gd")

signal selection_requested(actor)

var anchor_position: Vector2 = Vector2.ZERO
var phase_x: float = 0.0
var phase_y: float = 0.0
var period_x: float = 60.0
var period_y: float = 72.0
var period_x2: float = 91.0
var period_y2: float = 107.0
var amplitude_x: float = 3.8
var amplitude_y: float = 2.6
var drift_time: float = 0.0
var selected: bool = false
var hover: bool = false
var defeated: bool = false
var base_scale: float = 0.738
var visual_scale: float = 0.86
var target_scale: float = 0.86
var card_id: String = ""
var battle_uid: int = 0
var synergy_bonus_pct: float = 0.0
var definition_max_hp: int = 0
var base_max_hp: int = 0
var display_name: String = ""
var stars: float = 3.0
var passive_name: String = ""
var special_name: String = ""
var special_style: String = ""
var hp: int = 0
var max_hp: int = 0
var taijutsu: int = 0
var ninjutsu: int = 0
var genjutsu: int = 0
var element_name: String = ""
var team_name: String = "ally"
var shield: int = 0
var special_used: bool = false
var special_cooldown: int = 0
var disabled_turns: int = 0
var kankuro_decoy_used: bool = false
var kankuro_defense_active: bool = false
var reactive_entry_guard: bool = false
var status_tags: Dictionary = {}
var stat_buffs: Dictionary = {"taijutsu": 0, "ninjutsu": 0, "genjutsu": 0}
var timed_modifiers: Array[Dictionary] = []

var _card_view: Control
var _click_area: Area2D
var _frame_style: StyleBoxFlat
var _inner_edge_style: StyleBoxFlat
var _header_style: StyleBoxFlat
var _glass_material: ShaderMaterial
var _accent: Color = Color("6ea8d9")
var _selected_label: Label
var _hp_label: Label
var _spawn_progress: float = 0.0
var _spawn_from: float = 20.0
var _seed_index: int = 0
var _hover_amount: float = 0.0
var _selection_amount: float = 0.0
var _status_badge_root: Control
var _status_refresh_elapsed: float = 0.0
const STATUS_POLL_INTERVAL: float = 0.16
var _last_status_signature: String = ""
var _status_fx_root: Control
var _last_status_visual_signature: String = ""
var _art_back_rect: TextureRect
var _art_full_rect: TextureRect
var _name_label: Label
var _stars_label_node: Label
var _element_label_node: Label
var _stat_value_labels: Dictionary = {}
var _last_dynamic_identity_key: String = ""

const CARD_W: float = 252.0
const CARD_H: float = 396.0
const HEADER_H: float = 38.0
const HEADER_GAP: float = 7.0
const ART_BOX_W: float = 234.0
const ART_BOX_H: float = 290.0

func _assign_definition_state(data: Dictionary, seed_index: int, team_value: String) -> void:
    _seed_index = seed_index
    card_id = str(data.get("id", "card"))
    display_name = str(data.get("name", "Ninja"))
    stars = float(data.get("stars", 3.0))
    passive_name = str(data.get("passive_name", ""))
    special_name = str(data.get("special_name", ""))
    special_style = str(data.get("special_style", ""))
    hp = int(data.get("hp", 0))
    definition_max_hp = hp
    base_max_hp = hp
    max_hp = hp
    taijutsu = int(data.get("taijutsu", 0))
    ninjutsu = int(data.get("ninjutsu", 0))
    genjutsu = int(data.get("genjutsu", 0))
    element_name = str(data.get("element", "vent")).to_lower()
    team_name = team_value
    shield = 0
    special_used = false
    special_cooldown = 0
    disabled_turns = 0
    kankuro_decoy_used = false
    kankuro_defense_active = false
    reactive_entry_guard = false
    synergy_bonus_pct = 0.0
    defeated = false
    status_tags = {}
    stat_buffs = {"taijutsu": 0, "ninjutsu": 0, "genjutsu": 0}
    timed_modifiers = []
    _accent = _element_color(element_name)
    # États initiaux confirmés par le moteur PC Classic.
    if card_id == "obito": status_tags["obito_intangible"] = true
    if card_id == "zabuza": status_tags["zabuza_untargetable"] = true
    if card_id == "gengetsu": status_tags["gengetsu_untargetable"] = true
    if card_id == "konan": status_tags["konan_untargetable"] = true
    if card_id == "zetsu": status_tags["zetsu_hidden"] = false
    if card_id == "tobi": status_tags["tobi_intangible"] = false
    if card_id == "kakuzu": status_tags["kakuzu_revivals_left"] = 2
    if card_id == "rock_lee": status_tags["rock_lee_boosts_left"] = 2
    if card_id == "kiba": status_tags["kiba_first_tai"] = true

func setup_logic_only(data: Dictionary, seed_index: int, team_value: String = "ally") -> void:
    # Instance sans rendu, utilisée uniquement pour prévisualiser la carte qui
    # entrera après un Switch A1 et autoriser sa vraie Action 2 comme sur PC.
    _assign_definition_state(data, seed_index, team_value)

func setup(data: Dictionary, anchor: Vector2, seed_index: int, team_value: String = "ally") -> void:
    _assign_definition_state(data, seed_index, team_value)
    anchor_position = anchor
    position = anchor_position

    var s: float = float(seed_index + 1)
    phase_x = fmod(0.87 * s + 0.31, TAU)
    phase_y = fmod(1.41 * s + 0.74, TAU)
    period_x = 50.0 + fmod(11.0 * s, 17.0)
    period_y = 58.0 + fmod(13.0 * s, 21.0)
    period_x2 = 81.0 + fmod(17.0 * s, 25.0)
    period_y2 = 96.0 + fmod(19.0 * s, 29.0)
    amplitude_x = 3.0 + fmod(0.23 * s, 0.70)
    amplitude_y = 1.9 + fmod(0.19 * s, 0.52)

    _card_view = _build_card(data)
    add_child(_card_view)
    _card_view.position = Vector2(-CARD_W * 0.5, -CARD_H * 0.5)

    _click_area = Area2D.new()
    _click_area.input_pickable = true
    add_child(_click_area)
    var shape: CollisionShape2D = CollisionShape2D.new()
    var rect: RectangleShape2D = RectangleShape2D.new()
    var total_h: float = CARD_H + HEADER_H + HEADER_GAP
    rect.size = Vector2(CARD_W, total_h)
    shape.position = Vector2(0.0, -(HEADER_H + HEADER_GAP) * 0.5)
    shape.shape = rect
    _click_area.add_child(shape)
    _click_area.input_event.connect(_on_input_event)
    _click_area.mouse_entered.connect(_on_mouse_entered)
    _click_area.mouse_exited.connect(_on_mouse_exited)

    scale = Vector2.ONE * (base_scale * 0.965)
    target_scale = base_scale
    visual_scale = base_scale * 0.965
    modulate.a = 0.0
    _spawn_from = -18.0 if seed_index < 3 else 18.0

    var tween: Tween = create_tween()
    tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
    tween.tween_interval(float(seed_index % 3) * 0.055)
    tween.tween_property(self, "_spawn_progress", 1.0, 0.58).set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_OUT)

func set_selected(value: bool) -> void:
    if defeated:
        selected = false
        return
    selected = value
    if MobilePlatform.is_android():
        _apply_mobile_selection_visual()

func _apply_mobile_selection_visual() -> void:
    # Mobile : pas de perspective/hover/shader recalculés chaque frame.
    # Le clic garde néanmoins un feedback clair et immédiat.
    var selected_scale: float = base_scale * (1.04 if selected else 1.0)
    scale = Vector2.ONE * selected_scale
    rotation = 0.0
    if _frame_style:
        _frame_style.border_color = Color("f3d36a") if selected else _accent.darkened(0.16)
        _frame_style.shadow_color = Color(0,0,0,0.50 if selected else 0.38)
        _frame_style.shadow_size = 8 if selected else 5
        _frame_style.shadow_offset = Vector2(0,5)
    if _inner_edge_style:
        _inner_edge_style.border_color = Color(1.0,0.90,0.52,0.72) if selected else Color(1,1,1,0.10)
    if _header_style:
        _header_style.border_color = Color(1.0,0.86,0.39,0.82) if selected else Color(_accent.r,_accent.g,_accent.b,0.42)
        _header_style.shadow_size = 6 if selected else 4
    if _selected_label:
        _selected_label.visible = selected
        _selected_label.modulate.a = 1.0 if selected else 0.0

func apply_damage(amount: int) -> int:
    if defeated:
        return 0
    var before: int = hp
    hp = maxi(0, hp - maxi(0, amount))
    _refresh_hp_label()
    if hp <= 0:
        _mark_defeated()
    return before - hp

func _mark_defeated() -> void:
    defeated = true
    selected = false
    hover = false
    if _click_area:
        _click_area.input_pickable = false
    var tween: Tween = create_tween()
    tween.tween_property(self, "modulate", Color(0.62, 0.62, 0.70, 0.42), 0.35).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
    tween.parallel().tween_property(self, "scale", Vector2.ONE * (base_scale * 0.80), 0.35).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

func _refresh_hp_label() -> void:
    if _hp_label:
        _hp_label.text = "%d PV" % hp if shield <= 0 else "%d +%d" % [hp, shield]
        if hp <= max_hp / 3:
            _hp_label.add_theme_color_override("font_color", Color("ffd2d2"))
        elif shield > 0:
            _hp_label.add_theme_color_override("font_color", Color("9fd5ff"))
        else:
            _hp_label.add_theme_color_override("font_color", Color("eff5fb"))

func effective_stat(style: String, defender_stars: float = -1.0) -> int:
    if card_id == "gengetsu" and bool(status_tags.get("gengetsu_clone_active", false)):
        return 0
    if style not in ["taijutsu", "ninjutsu", "genjutsu"]:
        return 0
    # Transfert d'Ino : elle combat avec les stats actuelles du corps contrôlé.
    if card_id == "ino" and status_tags.has("possession_stats"):
        var possession: Dictionary = status_tags.get("possession_stats", {}) as Dictionary
        return maxi(0, int(possession.get(style, 0)))
    var base_value: int = 0
    match style:
        "taijutsu": base_value = taijutsu
        "ninjutsu": base_value = ninjutsu
        "genjutsu": base_value = genjutsu
    var value: int = base_value + int(round(float(base_value) * synergy_bonus_pct))
    value += int(stat_buffs.get(style, 0))
    for mod in timed_modifiers:
        if str(mod.get("style", "")) == style:
            value += int(mod.get("delta", 0))
    if card_id == "naruto" and hp * 2 < max_hp and style in ["taijutsu", "ninjutsu"]:
        value += 350
    if card_id == "shikamaru" and style == "genjutsu" and defender_stars > stars:
        value += 150
    if card_id == "rock_lee" and style == "taijutsu" and int(status_tags.get("rock_lee_boosts_left", 0)) > 0:
        value += 150
    if card_id == "kiba" and style == "taijutsu" and bool(status_tags.get("kiba_first_tai", false)):
        value += 150
    if card_id == "sarutobi" and status_tags.has("previous_attack_style") and str(status_tags.get("previous_attack_style", "")) != style:
        value += 100
    if card_id == "karui" and int(status_tags.get("karui_electric_turns", 0)) > 0:
        value += 300
    if card_id == "anko" and bool(status_tags.get("anko_curse_used", false)):
        value += int(round(float(base_value) * 0.10))
    if card_id == "kimimaro" and bool(status_tags.get("kimimaro_fury", false)):
        value = int(round(float(value) * 1.15))
    if int(status_tags.get("shizune_paralysis_turns", 0)) > 0:
        value = int(round(float(value) * 0.50))
    return maxi(0, value)

func set_synergy_bonus(pct: float) -> void:
    var next_pct: float = maxf(0.0, pct)
    if absf(next_pct - synergy_bonus_pct) < 0.0001:
        return
    var old_max: int = maxi(1, max_hp)
    var ratio: float = float(hp) / float(old_max) if hp > 0 else 0.0
    synergy_bonus_pct = next_pct
    # PC : la synergie est calculée UNIQUEMENT depuis les PV imprimés de la
    # carte. Les +PV permanents (Rin/Jûgo) ou temporaires (Karui) s'ajoutent
    # ensuite et ne doivent pas amplifier le pourcentage de synergie.
    if bool(status_tags.get("gengetsu_clone_active", false)):
        max_hp = 4800
    else:
        var synergy_hp: int = int(round(float(definition_max_hp) * synergy_bonus_pct))
        max_hp = maxi(1, base_max_hp + synergy_hp)
    if hp > 0:
        hp = clampi(int(round(ratio * float(max_hp))), 1, max_hp)
    _refresh_hp_label()

func synergy_label() -> String:
    if synergy_bonus_pct >= 0.199:
        return "+20 %"
    if synergy_bonus_pct >= 0.149:
        return "+15 %"
    if synergy_bonus_pct >= 0.124:
        return "+12,5 %"
    return ""

func add_timed_modifier(style: String, delta: int, turns: int, key: String) -> void:
    if style not in ["taijutsu", "ninjutsu", "genjutsu"] or turns <= 0:
        return
    for mod in timed_modifiers:
        if str(mod.get("key", "")) == key and str(mod.get("style", "")) == style:
            mod["delta"] = delta
            mod["turns"] = turns
            mod["skip_tick"] = true
            return
    timed_modifiers.append({"style":style, "delta":delta, "turns":turns, "key":key, "skip_tick":true})

func clear_negative_timed_modifiers() -> void:
    var kept: Array[Dictionary] = []
    for mod in timed_modifiers:
        if int(mod.get("delta", 0)) >= 0:
            kept.append(mod)
    timed_modifiers = kept

func can_act() -> bool:
    if defeated:
        return false
    # Classic : Madara ignore tous les contrôles incapacitants, y compris le
    # scellement. Killer Bee ne peut pas perdre son tour, mais le SCELLÉ
    # Uzumaki reste une exception explicite qui le bloque.
    if card_id == "madara":
        return true
    if int(status_tags.get("sealed_turns", 0)) > 0:
        return false
    if card_id == "killer_bee":
        return true
    if disabled_turns > 0:
        return false
    if int(status_tags.get("kisame_prisoned_by_uid", 0)) > 0:
        return false
    # Possession des ombres est un verrou indépendant du STUN générique.
    # Cela permet de la briser sans effacer un autre étourdissement actif.
    if int(status_tags.get("shadow_turns", 0)) > 0:
        return false
    if int(status_tags.get("possessed_by_uid", 0)) > 0:
        return false
    return true

func can_use_style(style: String) -> bool:
    if not can_act():
        return false
    if style not in ["taijutsu", "ninjutsu", "genjutsu"]:
        return false
    return int(status_tags.get("blocked_%s_turns" % style, 0)) <= 0

func special_available() -> bool:
    if defeated or special_name.is_empty():
        return false
    if not can_act():
        return false
    if int(status_tags.get("special_block_turns", 0)) > 0 and card_id != "killer_bee":
        return false
    if special_cooldown > 0:
        return false
    if card_id == "ino" and int(status_tags.get("ino_target_uid", 0)) > 0:
        return false
    if card_id == "gengetsu" and bool(status_tags.get("gengetsu_clone_active", false)):
        return false
    if card_id == "mu" and bool(status_tags.get("mu_division_used", false)):
        return false
    return not special_used

func consume_special() -> void:
    if card_id == "ino":
        # PC : après utilisation, T 1/3 immédiatement ; le compteur descend au
        # début des tours suivants et la technique revient au 3e tour suivant.
        special_cooldown = 3
        status_tags.erase("cooldown_skip_tick")
    elif card_id == "karin":
        # PC : l'utilisation a lieu après le tick de début de tour ; le premier
        # cran de recharge est donc consommé au PROCHAIN tour de Karin.
        special_cooldown = 3
        status_tags.erase("cooldown_skip_tick")
    elif card_id in ["shikamaru", "konohamaru"]:
        # Même règle Classic : 4 -> 3 au prochain tour, puis disponible au 4e.
        special_cooldown = 4
        status_tags.erase("cooldown_skip_tick")
    elif card_id == "gengetsu":
        # La recharge de 4 tours ne commence qu'après le retour de la forme clone.
        special_used = true
    elif card_id == "chojuro":
        # Hiramekarei peut être rechargé par le stock, comme dans le PC.
        special_used = false
    else:
        special_used = true
    refresh_status_badges()

func apply_disable(turns: int, source_key: String = "") -> void:
    if turns <= 0:
        return
    disabled_turns = maxi(disabled_turns, turns)
    status_tags["disable_skip_tick"] = true
    if not source_key.is_empty():
        status_tags["disable_source"] = source_key

func tick_own_turn() -> void:
    if disabled_turns > 0:
        if bool(status_tags.get("disable_skip_tick", false)):
            status_tags.erase("disable_skip_tick")
        else:
            disabled_turns -= 1
            if disabled_turns <= 0:
                status_tags.erase("disable_source")
    if special_cooldown > 0:
        if bool(status_tags.get("cooldown_skip_tick", false)):
            status_tags.erase("cooldown_skip_tick")
        else:
            special_cooldown -= 1

    var next_mods: Array[Dictionary] = []
    for mod in timed_modifiers:
        var copy: Dictionary = mod.duplicate()
        if bool(copy.get("skip_tick", false)):
            copy.erase("skip_tick")
        else:
            copy["turns"] = maxi(0, int(copy.get("turns", 0)) - 1)
        if int(copy.get("turns", 0)) > 0:
            next_mods.append(copy)
    timed_modifiers = next_mods

    for key: String in ["blocked_taijutsu_turns", "blocked_ninjutsu_turns", "blocked_genjutsu_turns", "special_block_turns"]:
        if status_tags.has(key):
            var skip_key_status: String = "%s_skip_tick" % key
            if bool(status_tags.get(skip_key_status, false)):
                status_tags.erase(skip_key_status)
            else:
                var remaining: int = maxi(0, int(status_tags.get(key, 0)) - 1)
                if remaining <= 0:
                    status_tags.erase(key)
                else:
                    status_tags[key] = remaining

    for key in ["rooted_turns", "sai_prison", "shadow_turns", "zetsu_switch_stun"]:
        if status_tags.has(key):
            var skip_key: String = "%s_skip_tick" % key
            if bool(status_tags.get(skip_key, false)):
                status_tags.erase(skip_key)
                if key == "shadow_turns":
                    status_tags.erase("shadow_fresh_application")
                continue
            var left: int = maxi(0, int(status_tags.get(key, 0)) - 1)
            if left <= 0:
                status_tags.erase(key)
                if key == "shadow_turns":
                    status_tags.erase("shadow_source")
                    status_tags.erase("shadow_source_uid")
            else:
                status_tags[key] = left

    # P16 : la durée du Transfert d'Ino est gérée par Main à la FIN du tour
    # d'Ino afin de pouvoir nettoyer atomiquement les deux extrémités du lien.

    for timed_key: String in ["sealed_turns", "haku_ice_prison_turns", "konohamaru_sexy_turns", "shizune_paralysis_turns", "karui_electric_turns", "anko_poison_turns"]:
        if status_tags.has(timed_key):
            var skip_timed: String = "%s_skip_tick" % timed_key
            if bool(status_tags.get(skip_timed, false)):
                status_tags.erase(skip_timed)
            else:
                var tleft: int = maxi(0, int(status_tags.get(timed_key, 0)) - 1)
                if tleft <= 0:
                    status_tags.erase(timed_key)
                else:
                    status_tags[timed_key] = tleft

    if card_id == "karui" and not status_tags.has("karui_electric_turns") and int(status_tags.get("karui_hp_bonus",0)) > 0:
        var karui_bonus_hp: int = int(status_tags.get("karui_hp_bonus",0))
        status_tags.erase("karui_hp_bonus")
        base_max_hp = maxi(1,base_max_hp-karui_bonus_hp)
        max_hp = maxi(1,max_hp-karui_bonus_hp)
        hp = mini(hp,max_hp)
        _refresh_hp_label()

    # Les verrous Sharingan de Sasuke ne se décomptent PAS aux tours de Sasuke :
    # ils durent trois tours complets de la carte qui a déclenché l'immunité.
    # Main.gd les décrémente donc à la fin du tour de l'équipe source.
    refresh_status_badges()

func set_hp(value: int) -> void:
    hp = clampi(value, 0, max_hp)
    defeated = hp <= 0
    _refresh_hp_label()

func heal(amount: int) -> int:
    if defeated or amount <= 0:
        return 0
    var before: int = hp
    hp = mini(max_hp, hp + amount)
    _refresh_hp_label()
    return hp - before

func add_shield(amount: int) -> void:
    shield += maxi(0, amount)
    _refresh_hp_label()

func export_state() -> Dictionary:
    # Schéma explicite : contrairement au P14, les mutations permanentes de PV
    # max (Rin / Jûgo / Karui) et les stats de base ne peuvent plus disparaître
    # lors d'un aller-retour terrain -> réserve -> terrain.
    return {
        "state_schema": 2,
        "hp": hp,
        "definition_max_hp": definition_max_hp,
        "base_max_hp": base_max_hp,
        "max_hp": max_hp,
        "taijutsu": taijutsu,
        "ninjutsu": ninjutsu,
        "genjutsu": genjutsu,
        "element_name": element_name,
        "shield": shield,
        "special_used": special_used,
        "special_cooldown": special_cooldown,
        "disabled_turns": disabled_turns,
        "kankuro_decoy_used": kankuro_decoy_used,
        "kankuro_defense_active": kankuro_defense_active,
        "reactive_entry_guard": reactive_entry_guard,
        "synergy_bonus_pct": synergy_bonus_pct,
        "status_tags": status_tags.duplicate(true),
        "stat_buffs": stat_buffs.duplicate(true),
        "timed_modifiers": timed_modifiers.duplicate(true)
    }

func import_state(state: Dictionary) -> void:
    if state.is_empty():
        return
    # Compatibilité avec les sauvegardes P14 : chaque nouvelle clé possède un
    # fallback vers les données de définition déjà chargées.
    definition_max_hp = maxi(1, int(state.get("definition_max_hp", definition_max_hp)))
    base_max_hp = maxi(1, int(state.get("base_max_hp", base_max_hp)))
    max_hp = maxi(1, int(state.get("max_hp", base_max_hp)))
    taijutsu = int(state.get("taijutsu", taijutsu))
    ninjutsu = int(state.get("ninjutsu", ninjutsu))
    genjutsu = int(state.get("genjutsu", genjutsu))
    element_name = str(state.get("element_name", element_name))
    synergy_bonus_pct = maxf(0.0, float(state.get("synergy_bonus_pct", 0.0)))
    hp = clampi(int(state.get("hp", hp)), 0, max_hp)
    shield = maxi(0, int(state.get("shield", 0)))
    special_used = bool(state.get("special_used", false))
    special_cooldown = maxi(0, int(state.get("special_cooldown", 0)))
    disabled_turns = maxi(0, int(state.get("disabled_turns", 0)))
    kankuro_decoy_used = bool(state.get("kankuro_decoy_used", false))
    kankuro_defense_active = bool(state.get("kankuro_defense_active", false))
    reactive_entry_guard = bool(state.get("reactive_entry_guard", false))
    status_tags = (state.get("status_tags", {}) as Dictionary).duplicate(true)
    stat_buffs = (state.get("stat_buffs", stat_buffs) as Dictionary).duplicate(true)
    timed_modifiers.clear()
    for mod in state.get("timed_modifiers", []):
        if mod is Dictionary:
            timed_modifiers.append((mod as Dictionary).duplicate(true))
    defeated = hp <= 0
    _accent = _element_color(element_name)
    _refresh_hp_label()

func _process(delta: float) -> void:
    drift_time += delta
    _status_refresh_elapsed += delta

    if MobilePlatform.is_android():
        # Les états n'ont pas besoin d'être reconstruits à 6 fois/seconde.
        if _status_refresh_elapsed >= 0.40:
            _status_refresh_elapsed = 0.0
            refresh_dynamic_identity()
            refresh_status_badges()
            refresh_status_visuals()

        # On conserve uniquement l'animation d'arrivée, puis la carte reste
        # parfaitement fixe : zéro sin(), perspective souris, shadow animation
        # ou paramètre shader à recalculer 60 fois/seconde × 6 cartes.
        if defeated:
            return
        if _spawn_progress < 0.999:
            var spawn_y_mobile: float = lerpf(_spawn_from, 0.0, _smoothstep01(_spawn_progress))
            position = anchor_position + Vector2(0.0, spawn_y_mobile)
            modulate.a = _smoothstep01(_spawn_progress)
        else:
            position = anchor_position
            modulate.a = 1.0
        return

    # Desktop conserve toutes les animations visuelles P42/P43.
    if _status_refresh_elapsed >= STATUS_POLL_INTERVAL:
        _status_refresh_elapsed = 0.0
        refresh_dynamic_identity()
        refresh_status_badges()
        refresh_status_visuals()
    if _status_fx_root and _status_fx_root.get_child_count() > 0:
        var pulse: float = 0.90 + 0.10 * (0.5 + 0.5 * sin(drift_time * 5.5))
        _status_fx_root.modulate = Color(1,1,1,pulse)

    var x: float = (
        sin(TAU * drift_time / period_x + phase_x) * amplitude_x * 0.76
        + sin(TAU * drift_time / period_x2 + phase_y * 0.73) * amplitude_x * 0.24
    )
    var y: float = (
        sin(TAU * drift_time / period_y + phase_y) * amplitude_y * 0.78
        + sin(TAU * drift_time / period_y2 + phase_x * 1.17) * amplitude_y * 0.22
    )

    var hover_target: float = 1.0 if hover and not defeated else 0.0
    var select_target: float = 1.0 if selected and not defeated else 0.0
    var hover_response: float = 1.0 - exp(-7.0 * delta)
    var selection_response: float = 1.0 - exp(-8.5 * delta)
    _hover_amount = lerpf(_hover_amount, hover_target, hover_response)
    _selection_amount = lerpf(_selection_amount, select_target, selection_response)

    var hover_lift: float = -5.5 * _hover_amount
    var selected_lift: float = -1.8 * _selection_amount
    var spawn_y: float = lerpf(_spawn_from, 0.0, _smoothstep01(_spawn_progress))
    position = anchor_position + Vector2(x, y + hover_lift + selected_lift + spawn_y)
    if not defeated:
        modulate.a = _smoothstep01(_spawn_progress)

    var mouse_local: Vector2 = to_local(get_global_mouse_position())
    var mouse_x: float = clampf(mouse_local.x / (CARD_W * 0.5), -1.0, 1.0)
    var mouse_y: float = clampf(mouse_local.y / (CARD_H * 0.5), -1.0, 1.0)

    var target_rot: float = mouse_x * deg_to_rad(0.82) * _hover_amount
    var rot_response: float = 1.0 - exp(-10.0 * delta)
    rotation = lerp_angle(rotation, target_rot, rot_response)

    var scale_mul: float = 1.0 + 0.026 * _hover_amount + 0.040 * _selection_amount
    target_scale = base_scale * scale_mul
    var scale_response: float = 1.0 - exp(-10.5 * delta)
    visual_scale = lerpf(visual_scale, target_scale, scale_response)
    var perspective_x: float = 1.0 + absf(mouse_x) * 0.0025 * _hover_amount
    var perspective_y: float = 1.0 - mouse_y * 0.0035 * _hover_amount
    scale = Vector2(visual_scale * perspective_x, visual_scale * perspective_y)

    var base_border: Color = _accent.darkened(0.16)
    var hover_border: Color = _accent.lightened(0.20)
    var selected_border: Color = Color("f3d36a")
    var border: Color = base_border.lerp(hover_border, _hover_amount)
    border = border.lerp(selected_border, _selection_amount)
    if _frame_style:
        _frame_style.border_color = border
        var energy: float = maxf(_hover_amount, _selection_amount)
        _frame_style.shadow_color = Color(0.0, 0.0, 0.0, lerpf(0.44, 0.64, energy))
        _frame_style.shadow_size = int(round(lerpf(7.0, 13.0, energy)))
        _frame_style.shadow_offset = Vector2(0.0, lerpf(5.0, 8.0, energy))
    if _inner_edge_style:
        var inner_idle: Color = Color(1.0, 1.0, 1.0, 0.10)
        var inner_hover: Color = Color(0.82, 0.93, 1.0, 0.24)
        var inner_selected: Color = Color(1.0, 0.90, 0.52, 0.72)
        var inner_color: Color = inner_idle.lerp(inner_hover, _hover_amount)
        _inner_edge_style.border_color = inner_color.lerp(inner_selected, _selection_amount)
    if _header_style:
        _header_style.border_color = Color(_accent.r, _accent.g, _accent.b, 0.42 + 0.30 * _hover_amount).lerp(Color(1.0, 0.86, 0.39, 0.82), _selection_amount)
        _header_style.shadow_size = int(round(lerpf(5.0, 9.0, maxf(_hover_amount, _selection_amount))))
    if _selected_label:
        _selected_label.modulate.a = _selection_amount
        _selected_label.visible = _selection_amount > 0.015

    if _glass_material:
        var pointer: Vector2 = Vector2(
            clampf((mouse_local.x + CARD_W * 0.5) / CARD_W, 0.0, 1.0),
            clampf((mouse_local.y + CARD_H * 0.5) / CARD_H, 0.0, 1.0)
        )
        _glass_material.set_shader_parameter("hover_amount", _hover_amount)
        _glass_material.set_shader_parameter("selected_amount", _selection_amount)
        _glass_material.set_shader_parameter("pointer_uv", pointer)
        _glass_material.set_shader_parameter("accent_color", _accent)

func _on_input_event(_viewport: Node, event: InputEvent, _shape_idx: int) -> void:
    # Android : ne dépend pas uniquement de l'émulation souris du système.
    # Certains appareils / chemins Godot envoient directement ScreenTouch.
    if event is InputEventScreenTouch and event.pressed:
        selection_requested.emit(self)
        return
    if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
        selection_requested.emit(self)

func _on_mouse_entered() -> void:
    if MobilePlatform.is_android():
        return
    if not defeated:
        hover = true

func _on_mouse_exited() -> void:
    if MobilePlatform.is_android():
        return
    hover = false

func _build_card(data: Dictionary) -> Control:
    var root: Control = Control.new()
    root.custom_minimum_size = Vector2(CARD_W, CARD_H)
    root.size = Vector2(CARD_W, CARD_H)
    root.mouse_filter = Control.MOUSE_FILTER_IGNORE
    root.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR

    # Header externe : aucune partie du portrait n'est masquée.
    var header: Panel = Panel.new()
    header.position = Vector2(0.0, -(HEADER_H + HEADER_GAP))
    header.size = Vector2(CARD_W, HEADER_H)
    header.mouse_filter = Control.MOUSE_FILTER_IGNORE
    header.z_index = 18
    _header_style = StyleBoxFlat.new()
    _header_style.bg_color = Color(0.018, 0.033, 0.053, 0.95)
    _header_style.border_color = Color(_accent.r, _accent.g, _accent.b, 0.44)
    _header_style.set_border_width_all(1)
    _header_style.set_corner_radius_all(10)
    _header_style.shadow_color = Color(0.0, 0.0, 0.0, 0.40)
    _header_style.shadow_size = 5
    _header_style.shadow_offset = Vector2(0, 3)
    header.add_theme_stylebox_override("panel", _header_style)
    root.add_child(header)

    var header_accent: ColorRect = ColorRect.new()
    header_accent.position = Vector2(8, 8)
    header_accent.size = Vector2(3, 22)
    header_accent.color = Color(_accent.r, _accent.g, _accent.b, 0.92)
    header_accent.mouse_filter = Control.MOUSE_FILTER_IGNORE
    header.add_child(header_accent)
    _name_label = _label(header, display_name, Rect2(18, 3, 154, 32), 13, Color("f4f7fb"), HORIZONTAL_ALIGNMENT_LEFT, true)
    var hp_panel: Panel = _pill(header, Rect2(176, 6, 68, 26), Color(0.055, 0.083, 0.112, 0.96), Color(0.43, 0.58, 0.70, 0.42), 7)
    _hp_label = _label(hp_panel, "%d PV" % hp, Rect2(4, 1, 60, 24), 10, Color("eff5fb"), HORIZONTAL_ALIGNMENT_CENTER, true)

    var frame: Panel = Panel.new()
    frame.position = Vector2.ZERO
    frame.size = Vector2(CARD_W, CARD_H)
    frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
    _frame_style = StyleBoxFlat.new()
    _frame_style.bg_color = Color("07101a")
    _frame_style.border_color = _accent.darkened(0.16)
    _frame_style.set_border_width_all(2)
    _frame_style.set_corner_radius_all(14)
    _frame_style.shadow_color = Color(0, 0, 0, 0.44)
    _frame_style.shadow_size = 8
    _frame_style.shadow_offset = Vector2(0, 5)
    frame.add_theme_stylebox_override("panel", _frame_style)
    root.add_child(frame)

    var inner: Panel = Panel.new()
    inner.position = Vector2(5, 5)
    inner.size = Vector2(CARD_W - 10.0, CARD_H - 10.0)
    inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
    inner.z_index = 12
    _inner_edge_style = StyleBoxFlat.new()
    _inner_edge_style.bg_color = Color(0, 0, 0, 0)
    _inner_edge_style.border_color = Color(1, 1, 1, 0.10)
    _inner_edge_style.set_border_width_all(1)
    _inner_edge_style.set_corner_radius_all(11)
    inner.add_theme_stylebox_override("panel", _inner_edge_style)
    root.add_child(inner)

    # Grande fenêtre d'art verticale. Le fond remplit la fenêtre, mais l'image
    # originale est aussi affichée en entier au premier plan : plus de crop forcé.
    var art_clip: Panel = Panel.new()
    art_clip.position = Vector2(9, 9)
    art_clip.size = Vector2(ART_BOX_W, ART_BOX_H)
    art_clip.clip_contents = true
    art_clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
    var art_clip_style: StyleBoxFlat = StyleBoxFlat.new()
    art_clip_style.bg_color = Color(0.010, 0.018, 0.028, 0.55)
    art_clip_style.set_corner_radius_all(9)
    art_clip.add_theme_stylebox_override("panel", art_clip_style)
    root.add_child(art_clip)

    var art_path: String = "res://assets/cards/%s_field.png" % card_id
    var art_texture: Texture2D = load(art_path) as Texture2D

    _art_back_rect = TextureRect.new()
    _art_back_rect.position = Vector2(-7, -7)
    _art_back_rect.size = Vector2(ART_BOX_W + 14, ART_BOX_H + 14)
    _art_back_rect.texture = art_texture
    _art_back_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
    _art_back_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
    _art_back_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
    _art_back_rect.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
    _art_back_rect.modulate = Color(0.28, 0.36, 0.46, 0.62)
    art_clip.add_child(_art_back_rect)

    var art_dim: ColorRect = ColorRect.new()
    art_dim.position = Vector2.ZERO
    art_dim.size = Vector2(ART_BOX_W, ART_BOX_H)
    art_dim.color = Color(0.01, 0.02, 0.04, 0.20)
    art_dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
    art_clip.add_child(art_dim)

    _art_full_rect = TextureRect.new()
    _art_full_rect.position = Vector2.ZERO
    _art_full_rect.size = Vector2(ART_BOX_W, ART_BOX_H)
    _art_full_rect.texture = art_texture
    _art_full_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
    _art_full_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
    _art_full_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
    _art_full_rect.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
    art_clip.add_child(_art_full_rect)

    var art_shade: ColorRect = ColorRect.new()
    art_shade.position = Vector2(0, ART_BOX_H - 49)
    art_shade.size = Vector2(ART_BOX_W, 49)
    art_shade.color = Color(0.012, 0.028, 0.047, 0.42)
    art_shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
    art_clip.add_child(art_shade)

    var stars_panel: Panel = _pill(root, Rect2(15, 14, 51, 23), Color(0.052, 0.043, 0.014, 0.92), Color("d9b33f"), 6)
    _stars_label_node = _label(stars_panel, "%s ★" % _stars_label(float(data.get("stars", 3.0))), Rect2(3, 0, 45, 22), 10, Color("ffe076"), HORIZONTAL_ALIGNMENT_CENTER, true)

    var elem_panel: Panel = _pill(root, Rect2(180, 232, 43, 31), Color(0.020, 0.041, 0.067, 0.86), _accent, 8)
    _element_label_node = _label(elem_panel, _element_kanji(element_name), Rect2(0, -1, 43, 30), 19, _accent.lightened(0.17), HORIZONTAL_ALIGNMENT_CENTER, true)

    var footer: Panel = Panel.new()
    footer.position = Vector2(9, 278)
    footer.size = Vector2(226, 87)
    footer.mouse_filter = Control.MOUSE_FILTER_IGNORE
    var fs: StyleBoxFlat = StyleBoxFlat.new()
    fs.bg_color = Color(0.020, 0.039, 0.064, 0.965)
    fs.border_color = Color(1, 1, 1, 0.085)
    fs.set_border_width_all(1)
    fs.set_corner_radius_all(10)
    footer.add_theme_stylebox_override("panel", fs)
    root.add_child(footer)

    _stat_value_labels["taijutsu"] = _stat_chip(footer, Rect2(7, 7, 68, 40), "TAI", taijutsu, Color("ef6b5d"))
    _stat_value_labels["ninjutsu"] = _stat_chip(footer, Rect2(79, 7, 68, 40), "NIN", ninjutsu, Color("56aef0"))
    _stat_value_labels["genjutsu"] = _stat_chip(footer, Rect2(151, 7, 68, 40), "GEN", genjutsu, Color("b983ed"))

    var passive_name: String = str(data.get("passive_name", "PASSIF"))
    _label(footer, "PASSIF", Rect2(9, 52, 40, 22), 8, Color("62d7a2"), HORIZONTAL_ALIGNMENT_LEFT, true)
    _label(footer, passive_name, Rect2(48, 52, 166, 22), 9, Color("cbd7e3"), HORIZONTAL_ALIGNMENT_LEFT, true)

    var accent_bar: ColorRect = ColorRect.new()
    accent_bar.position = Vector2(24, CARD_H - 7.0)
    accent_bar.size = Vector2(CARD_W - 48.0, 2)
    accent_bar.color = Color(_accent.r, _accent.g, _accent.b, 0.88)
    accent_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
    root.add_child(accent_bar)

    var glass: TextureRect = TextureRect.new()
    glass.position = Vector2(3, 3)
    glass.size = Vector2(CARD_W - 6.0, CARD_H - 6.0)
    glass.texture = AssetCache.texture("res://assets/ui/card_glass_field.png")
    glass.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
    glass.stretch_mode = TextureRect.STRETCH_SCALE
    glass.mouse_filter = Control.MOUSE_FILTER_IGNORE
    glass.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
    glass.modulate = Color(1, 1, 1, 0.30)
    glass.z_index = 13
    root.add_child(glass)

    var sheen: ColorRect = ColorRect.new()
    sheen.position = Vector2(4, 4)
    sheen.size = Vector2(CARD_W - 8.0, CARD_H - 8.0)
    sheen.mouse_filter = Control.MOUSE_FILTER_IGNORE
    sheen.z_index = 14
    if MobilePlatform.is_android():
        # Le shader original utilise TIME et force un rendu animé permanent
        # pour chacune des six cartes. Sur mobile : reflet statique.
        sheen.color = Color(0.86,0.94,1.0,0.018)
        _glass_material = null
    else:
        _glass_material = ShaderMaterial.new()
        var shader: Shader = Shader.new()
        shader.code = """
shader_type canvas_item;
render_mode unshaded;
uniform float hover_amount = 0.0;
uniform float selected_amount = 0.0;
uniform vec2 pointer_uv = vec2(0.5, 0.5);
uniform vec4 accent_color : source_color = vec4(0.35, 0.70, 1.0, 1.0);
void fragment() {
    vec2 uv = UV;
    float time = TIME * 0.055;
    float edge_x = 1.0 - smoothstep(0.0, 0.055, min(uv.x, 1.0 - uv.x));
    float edge_y = 1.0 - smoothstep(0.0, 0.055, min(uv.y, 1.0 - uv.y));
    float fresnel = max(edge_x, edge_y);
    float diag = uv.x + uv.y * 0.52;
    float sweep_center = 0.30 + 0.12 * sin(time);
    float broad = 1.0 - smoothstep(0.0, 0.24, abs(diag - sweep_center));
    float fine = 1.0 - smoothstep(0.0, 0.050, abs(diag - (sweep_center + 0.14)));
    vec2 d = uv - pointer_uv;
    d.x *= 0.72;
    float cursor_light = exp(-dot(d, d) * 22.0) * hover_amount;
    float top_haze = pow(1.0 - uv.y, 2.4);
    float idle = broad * 0.010 + fine * 0.006 + top_haze * 0.008 + fresnel * 0.009;
    float active = broad * 0.026 * hover_amount + cursor_light * 0.050;
    float selected = fresnel * 0.028 * selected_amount + fine * 0.016 * selected_amount;
    vec3 cold = vec3(0.78, 0.91, 1.0);
    vec3 tint = mix(cold, accent_color.rgb, 0.20 + selected_amount * 0.18);
    COLOR = vec4(tint, idle + active + selected);
}
"""
        _glass_material.shader = shader
        sheen.material = _glass_material
    root.add_child(sheen)

    _selected_label = _label(root, "SÉLECTIONNÉ", Rect2(70, 341, 104, 18), 8, Color("ffe487"), HORIZONTAL_ALIGNMENT_CENTER, true)
    _selected_label.visible = false
    _selected_label.modulate.a = 0.0
    _selected_label.z_index = 20

    _status_fx_root = Control.new()
    _status_fx_root.position = Vector2.ZERO
    _status_fx_root.size = Vector2(CARD_W, CARD_H)
    _status_fx_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
    _status_fx_root.z_index = 26
    root.add_child(_status_fx_root)

    _status_badge_root = Control.new()
    _status_badge_root.position = Vector2(8, 48)
    _status_badge_root.size = Vector2(CARD_W - 16.0, 132)
    _status_badge_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
    _status_badge_root.z_index = 28
    root.add_child(_status_badge_root)
    refresh_status_badges()
    refresh_dynamic_identity()
    refresh_status_visuals()

    return root

# P21 — informations secrètes locales. Dans le Solo, `ally` est toujours le
# joueur humain. Une bombe posée par le Tobi ennemi sur nos cartes ne doit donc
# jamais apparaître dans les badges/FX. Inversement, nos propres bombes restent
# visibles sur les cartes adverses afin que le joueur puisse suivre son plan.
func _visible_tobi_bomb_count() -> int:
    if team_name == "enemy":
        return int(status_tags.get("tobi_bombs_ally", 0))
    return 0

func _visible_tobi_prediction_armed() -> bool:
    return team_name == "ally" and bool(status_tags.get("tobi_prediction_armed", false))

func status_lines() -> Array[Dictionary]:
    var rows: Array[Dictionary] = []
    # Les contrôles visuels majeurs (STUN/Ombres/Scellé/Prison/Inciblable/
    # Jashin/Clone/Transfert) sont volontairement absents d'ici : le Classic
    # les dessine UNE SEULE FOIS sur l'illustration, pas en badge + bandeau.
    if synergy_bonus_pct > 0.0:
        rows.append({"text":"SYNERGIE %s" % synergy_label(), "color":Color("63d69b")})
    if shield > 0:
        rows.append({"text":"BOUCLIER +%d" % shield, "color":Color("58aff0")})
    if special_cooldown > 0:
        var total: int = 3 if card_id in ["ino","karin"] else (4 if card_id in ["shikamaru","konohamaru","gengetsu"] else special_cooldown)
        var done: int = maxi(1, total - special_cooldown + 1)
        rows.append({"text":"SPÉ T %d/%d" % [done,total], "color":Color("e2b746")})
    if int(status_tags.get("special_block_turns",0)) > 0:
        rows.append({"text":"SPÉCIALE BLOQUÉE", "color":Color("d16d8f")})
    for style: String in ["taijutsu","ninjutsu","genjutsu"]:
        if int(status_tags.get("blocked_%s_turns" % style,0)) > 0:
            rows.append({"text":"%s BLOQUÉ" % style.substr(0,3).to_upper(), "color":Color("b477c8")})
    if bool(status_tags.get("shino_poisoned",false)):
        rows.append({"text":"POISON SHINO", "color":Color("74cf83")})
    if bool(status_tags.get("hanzo_poisoned",false)):
        rows.append({"text":"POISON SALAMANDRE", "color":Color("8fd168")})
    if int(status_tags.get("anko_poison_turns",0)) > 0:
        rows.append({"text":"POISON ANKO %dT" % int(status_tags.get("anko_poison_turns",0)), "color":Color("8ed07a")})
    if bool(status_tags.get("shizune_poisoned",false)):
        rows.append({"text":"POISON SHIZUNE", "color":Color("7fc98d")})
    if int(status_tags.get("shizune_paralysis_turns",0)) > 0:
        rows.append({"text":"PARALYSÉ 50%% %dT" % int(status_tags.get("shizune_paralysis_turns",0)), "color":Color("d1a56a")})
    if reactive_entry_guard:
        rows.append({"text":"COUNTER-SWITCH PRÊT", "color":Color("f0a34a")})
    if kankuro_defense_active:
        rows.append({"text":"DÉF. MARIONNETTISTE", "color":Color("e2b746")})
    if bool(status_tags.get("sage_mode",false)):
        rows.append({"text":"MODE ERMITE", "color":Color("e7a459")})
    if bool(status_tags.get("rin_isobu_active",false)):
        rows.append({"text":"ISOBU ÉVEILLÉ • +1000 PV", "color":Color("65c8d8")})
    if bool(status_tags.get("kimimaro_fury",false)):
        rows.append({"text":"FURIE +15%%", "color":Color("d66d63")})
    if int(status_tags.get("jugo_stage",0)) > 0:
        rows.append({"text":"MARQUE STADE %d" % int(status_tags.get("jugo_stage",0)), "color":Color("be6a91")})
    if bool(status_tags.get("anko_curse_used",false)):
        rows.append({"text":"MARQUE +10%% ARTS", "color":Color("c36c8e")})
    if bool(status_tags.get("anko_serpent_armed",false)):
        rows.append({"text":"PERMUTATION PRÊTE", "color":Color("78ca9c")})
    if bool(status_tags.get("konan_mine_active",false)):
        rows.append({"text":"TERRAIN MINÉ", "color":Color("d59955")})
    if int(status_tags.get("chojuro_chakra_stock",0)) > 0:
        rows.append({"text":"HIRAMEKAREI +%d" % int(status_tags.get("chojuro_chakra_stock",0)), "color":Color("6eb8df")})
    if status_tags.has("chojuro_last_swing"):
        var swing_badge: int = int(status_tags.get("chojuro_last_swing",0))
        rows.append({"text":"INCERTITUDES %s200" % ("+" if swing_badge >= 0 else "-"), "color":Color("6eb8df")})
    if int(status_tags.get("kakuzu_revivals_left",0)) > 0:
        rows.append({"text":"CŒURS %d" % int(status_tags.get("kakuzu_revivals_left",0)), "color":Color("d76f6f")})
    if bool(status_tags.get("mu_division_used",false)):
        rows.append({"text":"DIVISION • JINTON OFF", "color":Color("a4a9ae")})
    if bool(status_tags.get("haku_entry_guard", false)):
        rows.append({"text":"MIROIRS • GARDE 2/3", "color":Color("80c8ef")})
    if int(status_tags.get("torune_contact_poison", 0)) > 0:
        rows.append({"text":"NANO-POISON %d/T" % int(status_tags.get("torune_contact_poison",0)), "color":Color("6fcf88")})
    if int(status_tags.get("torune_micro_poison", 0)) > 0:
        rows.append({"text":"MICROBIOSE %d/T" % int(status_tags.get("torune_micro_poison",0)), "color":Color("62c981")})
    if bool(status_tags.get("chiyo_puppets_active", false)):
        rows.append({"text":"10 MARIONNETTES • -20%% ALLIÉS", "color":Color("d5a568")})
    if bool(status_tags.get("kabuto_reanimation_used", false)):
        rows.append({"text":"RÉINCARNATION UTILISÉE", "color":Color("9b8fb1")})
    if bool(status_tags.get("kurotsuchi_guard_used", false)) or bool(status_tags.get("kurotsuchi_rescue_used", false)):
        rows.append({"text":"PROTECTION DOTON UTILISÉE", "color":Color("b69a66")})
    if bool(status_tags.get("chiyo_passive_used", false)):
        rows.append({"text":"DERNIER SOIN CHIYO UTILISÉ", "color":Color("d5a568")})
    if int(status_tags.get("gai_gate_count",0)) > 0:
        rows.append({"text":"PORTES GAI ×%d • +%d TAI" % [int(status_tags.get("gai_gate_count",0)),int(status_tags.get("gai_gate_count",0))*250], "color":Color("ef6c5f")})
    if int(status_tags.get("karui_electric_turns",0)) > 0:
        rows.append({"text":"FURIE KARUI +300 • %dT" % int(status_tags.get("karui_electric_turns",0)), "color":Color("d9bb62")})
    if _visible_tobi_prediction_armed():
        rows.append({"text":"PRÉDICTION TOBI ARMÉE", "color":Color("e18c59")})
    if bool(status_tags.get("tracker_armed",false)):
        rows.append({"text":"TRAQUEUR • ENTRÉE FORCÉE", "color":Color("7bc8df")})
    if status_tags.has("ao_tracker_target"):
        rows.append({"text":"BYAKUGAN • ENTRÉE TRAQUÉE", "color":Color("74b8df")})
    if int(status_tags.get("sasori_tai_poison",0)) > 0:
        rows.append({"text":"POISON SASORI • -%d TAI" % int(status_tags.get("sasori_tai_poison",0)), "color":Color("a276a9")})
    var visible_bombs: int = _visible_tobi_bomb_count()
    if visible_bombs > 0:
        rows.append({"text":"BOMBE ×%d" % visible_bombs, "color":Color("e38b55")})
    return rows

func refresh_status_badges() -> void:
    if _status_badge_root == null:
        return
    var rows: Array[Dictionary] = status_lines()
    var sig_parts: Array[String] = []
    for row: Dictionary in rows:
        sig_parts.append(str(row.get("text","")))
    var signature: String = "|".join(sig_parts)
    if signature == _last_status_signature:
        return
    _last_status_signature = signature
    for child: Node in _status_badge_root.get_children():
        child.queue_free()
    var y: float = 0.0
    var visible_rows: int = mini(5, rows.size())
    if rows.size() > 5:
        visible_rows = 4
    for i: int in range(visible_rows):
        var row: Dictionary = rows[i]
        var c: Color = row.get("color", Color("7c94ad")) as Color
        var badge: Panel = _pill(_status_badge_root, Rect2(0,y,CARD_W-16.0,21), Color(0.012,0.025,0.043,0.92), Color(c.r,c.g,c.b,0.88), 6)
        _label(badge, str(row.get("text","")), Rect2(7,0,CARD_W-30.0,21), 8, c.lightened(0.18), HORIZONTAL_ALIGNMENT_LEFT, true)
        y += 23.0
    if rows.size() > 5:
        var hidden: int = rows.size() - 4
        var more: Panel = _pill(_status_badge_root, Rect2(0,y,CARD_W-16.0,21), Color(0.035,0.040,0.055,0.96), Color("d2b568"), 6)
        _label(more, "+%d AUTRES EFFETS" % hidden, Rect2(7,0,CARD_W-30.0,21), 8, Color("ffe4a0"), HORIZONTAL_ALIGNMENT_LEFT, true)

func _visual_art_id() -> String:
    # P50 Ino : le vrai corps possédé reste logiquement ici, mais visuellement
    # cette case montre le corps astral/intangible d'Ino. La victime elle-même
    # est dessinée sur la case d'Ino via ino_target.
    if int(status_tags.get("possessed_by_uid", 0)) > 0 and ResourceLoader.exists("res://assets/cards/ino_ghost_field.png"):
        return "ino_ghost"
    if card_id == "gengetsu" and bool(status_tags.get("gengetsu_clone_active", false)):
        return "gengetsu_clone"
    if card_id == "naruto" and hp * 2 < maxi(1, max_hp) and ResourceLoader.exists("res://assets/cards/naruto_passif_field.png"):
        return "naruto_passif"
    if card_id == "gai":
        var gates: int = clampi(int(status_tags.get("gai_gate_count", 0)), 0, 3)
        if gates > 0 and ResourceLoader.exists("res://assets/cards/gai_stade%d_field.png" % gates):
            return "gai_stade%d" % gates
    if card_id == "jugo":
        var stage: int = clampi(int(status_tags.get("jugo_stage", 0)), 0, 2)
        if stage > 0 and ResourceLoader.exists("res://assets/cards/jugo_stade%d_field.png" % stage):
            return "jugo_stade%d" % stage
    if card_id == "jiraiya" and bool(status_tags.get("sage_mode", false)) and ResourceLoader.exists("res://assets/cards/jiraiya_sage_field.png"):
        return "jiraiya_sage"
    if card_id == "rin" and bool(status_tags.get("rin_isobu_active", false)) and ResourceLoader.exists("res://assets/cards/rin_isobu_field.png"):
        return "rin_isobu"
    if card_id == "konohamaru" and int(status_tags.get("konohamaru_sexy_turns", 0)) > 0 and ResourceLoader.exists("res://assets/cards/konohamaru_sexy_field.png"):
        return "konohamaru_sexy"
    if card_id == "ino" and not str(status_tags.get("ino_target", "")).is_empty():
        var possessed_id: String = str(status_tags.get("ino_target", ""))
        if ResourceLoader.exists("res://assets/cards/%s_field.png" % possessed_id):
            return possessed_id
    return card_id

func refresh_dynamic_identity() -> void:
    if _art_full_rect == null or _art_back_rect == null:
        return
    var art_id: String = _visual_art_id()
    var visual_name: String = display_name
    var visual_stars: float = stars
    var visual_element: String = element_name
    var visual_tai: int = effective_stat("taijutsu")
    var visual_nin: int = effective_stat("ninjutsu")
    var visual_gen: int = effective_stat("genjutsu")
    if int(status_tags.get("possessed_by_uid", 0)) > 0:
        visual_name = "Ino • Inciblable"
    elif card_id == "gengetsu" and bool(status_tags.get("gengetsu_clone_active", false)):
        visual_name = "Clone de Gengetsu"
        visual_tai = 0
        visual_nin = 0
        visual_gen = 0
    elif card_id == "rin" and bool(status_tags.get("rin_isobu_active", false)):
        visual_name = "Rin • Isobu"
        visual_tai = effective_stat("taijutsu")
        visual_nin = effective_stat("ninjutsu")
        visual_gen = effective_stat("genjutsu")
    elif card_id == "ino" and not str(status_tags.get("ino_target", "")).is_empty():
        visual_name = str(status_tags.get("ino_target_name", "Corps contrôlé"))
        visual_stars = float(status_tags.get("ino_visual_stars", stars))
        visual_element = str(status_tags.get("ino_visual_element", element_name))
        visual_tai = int(status_tags.get("ino_visual_tai", visual_tai))
        visual_nin = int(status_tags.get("ino_visual_nin", visual_nin))
        visual_gen = int(status_tags.get("ino_visual_gen", visual_gen))
    var key: String = "%s|%s|%.1f|%s|%d|%d|%d" % [art_id, visual_name, visual_stars, visual_element, visual_tai, visual_nin, visual_gen]
    if key == _last_dynamic_identity_key:
        return
    _last_dynamic_identity_key = key
    var art_path: String = "res://assets/cards/%s_field.png" % art_id
    if ResourceLoader.exists(art_path):
        var tex: Texture2D = AssetCache.texture(art_path)
        _art_full_rect.texture = tex
        _art_back_rect.texture = tex
    if _name_label:
        _name_label.text = visual_name
    if _stars_label_node:
        _stars_label_node.text = "%s ★" % _stars_label(visual_stars)
    if _element_label_node:
        _element_label_node.text = _element_kanji(visual_element)
        _element_label_node.add_theme_color_override("font_color", _element_color(visual_element).lightened(0.17))
    if _stat_value_labels.has("taijutsu"):
        (_stat_value_labels["taijutsu"] as Label).text = str(visual_tai)
    if _stat_value_labels.has("ninjutsu"):
        (_stat_value_labels["ninjutsu"] as Label).text = str(visual_nin)
    if _stat_value_labels.has("genjutsu"):
        (_stat_value_labels["genjutsu"] as Label).text = str(visual_gen)

func _status_band(text_value: String, y: float, bg: Color, border: Color, font_color: Color, font_size: int = 10) -> void:
    if _status_fx_root == null:
        return
    var panel: Panel = _pill(_status_fx_root, Rect2(12, y, CARD_W - 24.0, 34), bg, border, 8)
    var style: StyleBoxFlat = panel.get_theme_stylebox("panel") as StyleBoxFlat
    if style:
        style.set_border_width_all(3)
        style.shadow_color = Color(border.r, border.g, border.b, 0.26)
        style.shadow_size = 5
    _label(panel, text_value, Rect2(6,0,CARD_W-36.0,34), font_size, font_color, HORIZONTAL_ALIGNMENT_CENTER, true)

func _status_overlay_label(text_value: String, y: float = 86.0) -> void:
    if _status_fx_root == null:
        return
    var width: float = 132.0
    var p: Panel = _pill(_status_fx_root, Rect2((CARD_W-width)*0.5, y, width, 24), Color(0.035,0.07,0.10,0.90), Color("76bce8"), 7)
    var style: StyleBoxFlat = p.get_theme_stylebox("panel") as StyleBoxFlat
    if style:
        style.set_border_width_all(2)
    _label(p, text_value, Rect2(4,0,width-8,24), 8, Color("eaf8ff"), HORIZONTAL_ALIGNMENT_CENTER, true)

func _status_art_tint(color: Color) -> void:
    if _status_fx_root == null:
        return
    var tint := ColorRect.new()
    tint.position = Vector2(9, 9)
    tint.size = Vector2(ART_BOX_W, ART_BOX_H)
    tint.color = color
    tint.mouse_filter = Control.MOUSE_FILTER_IGNORE
    tint.z_index = 0
    _status_fx_root.add_child(tint)

func _status_texture_overlay(path: String, rect: Rect2, tint: Color = Color.WHITE, stretch: int = TextureRect.STRETCH_KEEP_ASPECT_CENTERED) -> void:
    if _status_fx_root == null or not ResourceLoader.exists(path):
        return
    var tr := TextureRect.new()
    tr.position = rect.position
    tr.size = rect.size
    tr.texture = AssetCache.texture(path) as Texture2D
    tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
    tr.stretch_mode = stretch
    tr.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
    tr.modulate = tint
    tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
    tr.z_index = 1
    _status_fx_root.add_child(tr)

func _status_corner_chip(text_value: String, y: float, bg: Color, border: Color, fg: Color) -> void:
    if _status_fx_root == null:
        return
    var width: float = 112.0
    var p: Panel = _pill(_status_fx_root, Rect2(CARD_W-width-10.0, y, width, 24), bg, border, 7)
    var style: StyleBoxFlat = p.get_theme_stylebox("panel") as StyleBoxFlat
    if style:
        style.set_border_width_all(2)
    _label(p, text_value, Rect2(4,0,width-8.0,24), 8, fg, HORIZONTAL_ALIGNMENT_CENTER, true)

func force_refresh_status_visuals() -> void:
    # P31.1 : invalide volontairement le cache d'overlay. Nécessaire après
    # certaines résolutions A2 asynchrones sur mobile (Ombres de Shikamaru).
    _last_status_visual_signature = ""
    refresh_status_visuals()

func refresh_status_visuals() -> void:
    if _status_fx_root == null:
        return
    var untargetable: bool = is_untargetable()
    var shadow: int = int(status_tags.get("shadow_turns", 0))
    var sealed: int = int(status_tags.get("sealed_turns", 0))
    var rooted: int = int(status_tags.get("rooted_turns", 0))
    var ice: int = int(status_tags.get("haku_ice_prison_turns", 0))
    var sai: int = int(status_tags.get("sai_prison", 0))
    var water_prison: bool = int(status_tags.get("kisame_prisoned_by_uid", 0)) > 0
    var clone_turns: int = int(status_tags.get("gengetsu_clone_turns", 0)) if bool(status_tags.get("gengetsu_clone_active", false)) else 0
    var doom: int = int(status_tags.get("doom_turns", 0))
    var possessed: bool = int(status_tags.get("possessed_by_uid", 0)) > 0
    var ino_active: bool = card_id == "ino" and not str(status_tags.get("ino_target", "")).is_empty()
    var bombs: int = _visible_tobi_bomb_count()
    var sexy: int = int(status_tags.get("konohamaru_sexy_turns", 0))
    var hidden_shield: int = int(status_tags.get("kurenai_hidden_shield", 0))
    var special_protection: bool = bool(status_tags.get("special_protection", false))
    var signature_values: Array[String] = [
        str(untargetable), str(disabled_turns), str(shadow), str(sealed), str(rooted), str(ice), str(water_prison),
        str(clone_turns), str(doom), str(possessed), str(ino_active), str(bombs), str(shield), str(sexy),
        str(hidden_shield), str(special_protection), str(reactive_entry_guard), str(kankuro_defense_active),
        str(status_tags.get("kakuzu_revivals_left",0)), str(status_tags.get("mu_division_used",false)),
        str(status_tags.get("chojuro_chakra_stock",0)), str(_visible_tobi_prediction_armed()),
        str(status_tags.get("sage_mode",false)), str(status_tags.get("rin_isobu_active",false)),
        str(status_tags.get("kimimaro_fury",false)), str(status_tags.get("jugo_stage",0)),
        str(status_tags.get("gai_gate_count",0)), str(status_tags.get("yamato_counter_gift",false)),
        str(status_tags.get("kurotsuchi_guard_used",false)), str(status_tags.get("kurotsuchi_rescue_used",false))
    ]
    var sig: String = "|".join(signature_values)
    if sig == _last_status_visual_signature:
        return
    _last_status_visual_signature = sig
    for child: Node in _status_fx_root.get_children():
        child.queue_free()

    # Transparence de l'illustration elle-même : le badge ne suffit pas pour
    # comprendre qu'une carte est réellement inciblable / hors de son corps.
    if _art_full_rect:
        if ino_active:
            _art_full_rect.modulate = Color(1,1,1,0.34)
        elif untargetable:
            _art_full_rect.modulate = Color(0.82,0.94,1.0,0.46)
        else:
            _art_full_rect.modulate = Color.WHITE
    if _art_back_rect:
        _art_back_rect.modulate = Color(0.34,0.42,0.52,0.40 if untargetable or ino_active else 0.62)

    # Brouillards / prisons : le Classic colore toute la fenêtre d'art. Ces
    # voiles donnent immédiatement la nature de l'état avant même de lire.
    if shadow > 0:
        _status_art_tint(Color(0.015,0.012,0.024,0.46))
    elif disabled_turns > 0:
        _status_art_tint(Color(0.34,0.10,0.43,0.19))
    if ice > 0:
        _status_art_tint(Color(0.12,0.55,0.80,0.22))
    elif water_prison:
        _status_art_tint(Color(0.04,0.35,0.62,0.22))
    elif sai > 0:
        _status_art_tint(Color(0.20,0.24,0.30,0.22))
    if rooted > 0:
        _status_art_tint(Color(0.34,0.43,0.12,0.17))
    if sealed > 0:
        _status_art_tint(Color(0.58,0.42,0.04,0.13))

    # P33 : c'est le corps d'origine d'Ino qui reste blanc/inciblable pendant
    # que son esprit contrôle la cible. La cible possédée garde son rendu normal.
    if ino_active:
        _status_texture_overlay("res://assets/cards/ino_white_overlay_field.png", Rect2(0,0,CARD_W,CARD_H), Color(1,1,1,0.88), TextureRect.STRETCH_SCALE)
        _status_texture_overlay("res://assets/cards/ino_ghost_field.png", Rect2(9,9,ART_BOX_W,ART_BOX_H), Color(1,1,1,0.88), TextureRect.STRETCH_KEEP_ASPECT_CENTERED)

    # P21 — placement Classic : les états n'empilent plus six bandeaux
    # successifs. Chaque famille possède une position fixe sur la carte, comme
    # `_draw_card_status_fx` dans le client Tkinter.
    if untargetable:
        var untargetable_text: String = "INCIBLABLE"
        if card_id == "obito": untargetable_text = "KAMUI"
        elif card_id == "zabuza": untargetable_text = "BRUME"
        elif card_id == "gengetsu": untargetable_text = "PALOURDE"
        elif card_id == "tobi": untargetable_text = "INTANGIBLE"
        elif card_id == "zetsu": untargetable_text = "SOUS TERRE"
        elif card_id == "asuma": untargetable_text = "FUMÉE"
        elif card_id == "konan": untargetable_text = "ORIGAMI"
        _status_overlay_label(untargetable_text, 84.0)

    # Sexy Jutsu : ~29 % de la hauteur, comme Tkinter.
    if sexy > 0:
        _status_band("SEXY JUTSU %dT" % sexy, CARD_H * 0.29, Color(0.36,0.09,0.31,0.96), Color("ff9be9"), Color("ffe4fa"), 9)

    # Clone : ~37 %, compte à rebours très visible.
    if clone_turns > 0:
        _status_band("CLONE EXPLOSIF • EXPLOSION %dT" % clone_turns, CARD_H * 0.37, Color(0.19,0.09,0.05,0.97), Color("ff9b4a"), Color("fff0cc"), 9)

    # Scellé : ~30 %.
    if sealed > 0:
        _status_band("SCELLÉ %dT" % sealed, CARD_H * 0.30, Color(0.23,0.18,0.03,0.97), Color("ffd85a"), Color("fff1a6"), 9)

    # Un seul bandeau de contrôle à ~38 %. Ombres > prison/glace > STUN.
    var disabled_visual: bool = disabled_turns > 0 or shadow > 0 or ice > 0 or water_prison or sai > 0
    if disabled_visual:
        var control_text: String = "STUN %dT" % maxi(1, disabled_turns)
        var control_bg: Color = Color(0.16,0.085,0.19,0.97)
        var control_border: Color = Color("d37cff")
        var control_fg: Color = Color("f1ccff")
        if shadow > 0:
            control_text = "OMBRE DES NARA • %dT" % shadow
            control_bg = Color(0.006,0.007,0.010,0.98)
            control_border = Color("45484f")
            control_fg = Color("f4f4f4")
        elif ice > 0:
            control_text = "GLACE %dT" % ice
            control_bg = Color(0.03,0.16,0.26,0.97)
            control_border = Color("78d3ff")
            control_fg = Color("e6f8ff")
        elif water_prison:
            control_text = "PRISON AQUEUSE • KISAME"
            control_bg = Color(0.02,0.13,0.23,0.97)
            control_border = Color("56bdf4")
            control_fg = Color("e4f7ff")
        elif sai > 0:
            control_text = "PRISON %dT" % sai
            control_bg = Color(0.08,0.10,0.13,0.97)
            control_border = Color("9dacbd")
            control_fg = Color("eef3f7")
        _status_band(control_text, CARD_H * 0.38, control_bg, control_border, control_fg, 9)

    # Enraciné n'existe pas dans l'ancien helper Tkinter mais la roadmap le
    # demande explicitement : position fixe sous le bandeau de contrôle.
    if rooted > 0:
        _status_band("ENRACINÉ %dT" % rooted, CARD_H * 0.50, Color(0.12,0.16,0.055,0.96), Color("9fc65f"), Color("efffc8"), 9)

    # Ino : le voile blanc fait l'essentiel ; un seul bandeau fixe confirme
    # l'état au lieu de dupliquer plusieurs badges.
    if possessed:
        _status_band("CORPS D'INO • INCIBLABLE", CARD_H * 0.38, Color(0.93,0.93,0.97,0.96), Color("9b75b7"), Color("5b3a73"), 9)
    elif ino_active:
        _status_band("SOUS CONTRÔLE INO", CARD_H * 0.38, Color(0.30,0.20,0.28,0.90), Color("f3b6d5"), Color("fff1f8"), 9)

    # Jashin près du bas, exactement comme la carte Tkinter.
    if doom > 0:
        _status_band("JASHIN %dT" % doom, CARD_H - 92.0, Color(0.27,0.035,0.035,0.97), Color("ff6767"), Color("ffe4e4"), 9)

    # Boucliers : vraie lecture de protection autour de toute la carte.
    if shield > 0 or hidden_shield > 0:
        var shield_color: Color = Color("5ebdff") if shield > 0 else Color("b9a6ff")
        var shield_frame: Panel = _pill(_status_fx_root, Rect2(4,4,CARD_W-8.0,CARD_H-8.0), Color(0,0,0,0), shield_color, 12)
        var ss: StyleBoxFlat = shield_frame.get_theme_stylebox("panel") as StyleBoxFlat
        if ss:
            ss.set_border_width_all(4)
            ss.shadow_color = Color(shield_color.r, shield_color.g, shield_color.b, 0.34)
            ss.shadow_size = 7
        if hidden_shield > 0:
            _status_corner_chip("BOUCLIER CACHÉ", CARD_H-34.0, Color(0.10,0.07,0.18,0.96), Color("b9a6ff"), Color("e7ddff"))
    if special_protection:
        _status_corner_chip("SPÉ PROTÉGÉE", 68.0, Color(0.10,0.07,0.18,0.96), Color("d0b4ff"), Color("f1e6ff"))
    if reactive_entry_guard:
        _status_corner_chip("COUNTER-SWITCH", 40.0, Color(0.23,0.11,0.025,0.97), Color("f0a34a"), Color("ffe0a5"))
    if bool(status_tags.get("yamato_counter_gift", false)):
        _status_corner_chip("DON YAMATO • COUNTER", 96.0, Color(0.10,0.18,0.08,0.97), Color("8fc36a"), Color("e9ffd6"))
    if bool(status_tags.get("kurotsuchi_guard_used", false)) or bool(status_tags.get("kurotsuchi_rescue_used", false)):
        _status_corner_chip("DOTON • PROTECTION UTILISÉE", 124.0, Color(0.18,0.14,0.07,0.97), Color("b69a66"), Color("fff0c4"))
    if kankuro_defense_active:
        _status_corner_chip("DÉF. MARIONNETTE", 68.0, Color(0.21,0.15,0.03,0.97), Color("e2b746"), Color("fff0a8"))
    if int(status_tags.get("kakuzu_revivals_left",0)) > 0:
        _status_corner_chip("♥ ×%d" % int(status_tags.get("kakuzu_revivals_left",0)), 40.0, Color(0.22,0.035,0.045,0.97), Color("e67979"), Color("ffd6d6"))
    if bool(status_tags.get("mu_division_used",false)):
        _status_corner_chip("JINTON OFF", 68.0, Color(0.13,0.14,0.16,0.97), Color("a4a9ae"), Color("eceff2"))
    if int(status_tags.get("chojuro_chakra_stock",0)) > 0:
        _status_corner_chip("HIRAMEKAREI +%d" % int(status_tags.get("chojuro_chakra_stock",0)), 40.0, Color(0.03,0.14,0.22,0.97), Color("6eb8df"), Color("dff5ff"))
    if _visible_tobi_prediction_armed():
        _status_corner_chip("PRÉDICTION ARMÉE", CARD_H-62.0, Color(0.22,0.08,0.025,0.97), Color("e18c59"), Color("ffe0bd"))

    # Transformations/passifs de forme : le Classic les rend immédiatement
    # reconnaissables. Quand aucun artwork alternatif n'existe (Rin/Isobu),
    # le marqueur reste volontairement très visible plutôt que d'inventer une image.
    if bool(status_tags.get("rin_isobu_active",false)):
        _status_corner_chip("ISOBU ÉVEILLÉ", CARD_H-62.0, Color(0.025,0.18,0.22,0.98), Color("65c8d8"), Color("e8fcff"))
    if bool(status_tags.get("sage_mode",false)):
        _status_corner_chip("MODE ERMITE", CARD_H-90.0, Color(0.22,0.12,0.025,0.98), Color("e7a459"), Color("fff0c4"))
    if int(status_tags.get("gai_gate_count",0)) > 0:
        _status_corner_chip("PORTES ×%d" % int(status_tags.get("gai_gate_count",0)), CARD_H-90.0, Color(0.25,0.035,0.025,0.98), Color("ef6c5f"), Color("ffe0d9"))
    if int(status_tags.get("jugo_stage",0)) > 0:
        _status_corner_chip("STADE %d" % int(status_tags.get("jugo_stage",0)), CARD_H-118.0, Color(0.21,0.05,0.16,0.98), Color("be6a91"), Color("ffe0f2"))

    if bombs > 0:
        # Petites bombes empilées, lecture instantanée ×1..×5 comme le Classic.
        for i: int in range(mini(5, bombs)):
            var bomb: Panel = _pill(_status_fx_root, Rect2(CARD_W-34.0, 104.0 + float(i)*27.0, 25, 22), Color(0.22,0.08,0.025,0.98), Color("ff9a52"), 8)
            var bstyle: StyleBoxFlat = bomb.get_theme_stylebox("panel") as StyleBoxFlat
            if bstyle: bstyle.set_border_width_all(2)
            _label(bomb, "●", Rect2(1,0,23,22), 10, Color("ffe0bd"), HORIZONTAL_ALIGNMENT_CENTER, true)

func play_intercept_fx() -> void:
    if defeated:
        return
    var tw: Tween = create_tween()
    tw.tween_property(self, "scale", Vector2(visual_scale, visual_scale) * 1.08, 0.13).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
    tw.tween_property(self, "scale", Vector2(visual_scale, visual_scale), 0.20).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
    if _frame_style:
        var old: Color = _frame_style.border_color
        _frame_style.border_color = Color("ffd75f")
        var fw: Tween = create_tween()
        fw.tween_interval(0.18)
        fw.tween_property(_frame_style, "border_color", old, 0.35)

func is_untargetable() -> bool:
    if defeated:
        return false
    if card_id == "obito" and bool(status_tags.get("obito_intangible",false)): return true
    if card_id == "zetsu" and bool(status_tags.get("zetsu_hidden",false)): return true
    if card_id == "tobi" and bool(status_tags.get("tobi_intangible",false)): return true
    if card_id == "zabuza" and bool(status_tags.get("zabuza_untargetable",false)): return true
    if card_id == "gengetsu" and bool(status_tags.get("gengetsu_untargetable",false)) and not bool(status_tags.get("gengetsu_clone_active",false)): return true
    if card_id == "konan" and bool(status_tags.get("konan_untargetable",false)): return true
    if card_id == "asuma" and int(status_tags.get("asuma_smoke_turns",0)) > 0: return true
    if card_id == "ino" and status_tags.has("ino_target"): return true
    # P33 : le corps adverse possédé reste ciblable.
    return false

func seed_index_value() -> int:
    return _seed_index

func play_entry_fx() -> void:
    modulate = Color(1, 1, 1, 0.0)
    scale = Vector2.ONE * (base_scale * 0.88)
    var tw: Tween = create_tween()
    tw.tween_property(self, "modulate", Color(1,1,1,1), 0.30).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
    tw.parallel().tween_property(self, "scale", Vector2.ONE * base_scale, 0.34).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func play_cast_fx(accent: Color) -> void:
    if defeated:
        return
    var tw: Tween = create_tween()
    tw.tween_property(self, "scale", scale * 1.055, 0.14).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
    tw.tween_property(self, "scale", Vector2(visual_scale, visual_scale), 0.20).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
    if _frame_style:
        var old_border: Color = _frame_style.border_color
        _frame_style.border_color = accent.lightened(0.28)
        var ft: Tween = create_tween()
        ft.tween_interval(0.16)
        ft.tween_property(_frame_style, "border_color", old_border, 0.30).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)

func play_hit_fx(accent: Color) -> void:
    if _frame_style:
        var old_color: Color = _frame_style.bg_color
        _frame_style.bg_color = old_color.lerp(accent, 0.18)
        var tw: Tween = create_tween()
        tw.tween_property(_frame_style, "bg_color", old_color, 0.22).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
    var shake: Tween = create_tween()
    shake.tween_property(self, "position", anchor_position + Vector2(4, 0), 0.06).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
    shake.tween_property(self, "position", anchor_position + Vector2(-3, 0), 0.06).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
    shake.tween_property(self, "position", anchor_position, 0.08).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

func _stat_chip(parent: Control, rect: Rect2, code: String, value: int, color: Color) -> Label:
    var p: Panel = _pill(parent, rect, Color(0.039, 0.061, 0.091, 0.94), Color(color.r, color.g, color.b, 0.55), 7)
    _label(p, code, Rect2(3, 0, rect.size.x - 6.0, 15), 8, color.lightened(0.12), HORIZONTAL_ALIGNMENT_CENTER, true)
    return _label(p, str(value), Rect2(3, 15, rect.size.x - 6.0, 21), 12, Color("f2f6fa"), HORIZONTAL_ALIGNMENT_CENTER, true)

func _pill(parent: Control, rect: Rect2, bg: Color, border: Color, radius: int) -> Panel:
    var p: Panel = Panel.new()
    p.position = rect.position
    p.size = rect.size
    p.mouse_filter = Control.MOUSE_FILTER_IGNORE
    var s: StyleBoxFlat = StyleBoxFlat.new()
    s.bg_color = bg
    s.border_color = border
    s.set_border_width_all(1)
    s.set_corner_radius_all(radius)
    p.add_theme_stylebox_override("panel", s)
    parent.add_child(p)
    return p

func _label(parent: Control, text_value: String, rect: Rect2, font_size: int, color: Color, align: HorizontalAlignment, bold: bool) -> Label:
    var label: Label = Label.new()
    label.text = text_value
    label.position = rect.position
    label.size = rect.size
    label.horizontal_alignment = align
    label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    label.clip_text = true
    label.mouse_filter = Control.MOUSE_FILTER_IGNORE
    label.add_theme_font_size_override("font_size", font_size)
    label.add_theme_color_override("font_color", color)
    if bold:
        label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.38))
        label.add_theme_constant_override("shadow_offset_x", 1)
        label.add_theme_constant_override("shadow_offset_y", 1)
    parent.add_child(label)
    return label

func _smoothstep01(v: float) -> float:
    var x: float = clampf(v, 0.0, 1.0)
    return x * x * (3.0 - 2.0 * x)

func _stars_label(v: float) -> String:
    if is_equal_approx(v, floor(v)):
        return "%d" % int(v)
    return "%.1f" % v

func _element_kanji(element: String) -> String:
    match element:
        "feu": return "火"
        "vent": return "風"
        "foudre": return "雷"
        "terre": return "土"
        "eau": return "水"
        _ : return "•"

func _element_color(element: String) -> Color:
    match element:
        "feu": return Color("ef6256")
        "vent": return Color("63d596")
        "foudre": return Color("c09aff")
        "terre": return Color("c79b6b")
        "eau": return Color("55b6f2")
        _ : return Color("7c94ad")
