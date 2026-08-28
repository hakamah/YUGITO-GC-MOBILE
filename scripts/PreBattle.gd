class_name YugitoPreBattle
extends Control
# P47M.5: Android draft rendered as one cached CanvasItem over one atlas texture.

signal battle_requested
signal cancelled

const MenuCard = preload("res://scripts/MenuCard.gd")
const SynergyDB = preload("res://scripts/SynergyDB.gd")
const HomeVideoBackground = preload("res://scripts/HomeVideoBackground.gd")
const AssetCache = preload("res://scripts/AssetCache.gd")
const DraftCanvas = preload("res://scripts/DraftCanvas.gd")

const DRAFT_SIZE: int = 8
const STARTER_COUNT: int = 3
const MAX_TOTAL_STARS: float = 32.5
const PICK_CAPS: Array[float] = [3.0,3.0,3.5,3.5,4.0,4.0,4.5,4.5,5.0,5.0,4.5,4.5,4.0,4.0,4.0,4.0]
const PICK_RELATIVE: Array[String] = ["first","second","second","first","first","second","second","first","first","second","second","first","first","second","second","first"]
const STAR_LIMITS: Dictionary = {3.0:-1, 3.5:4, 4.0:3, 4.5:2, 5.0:1}
const RPS_BEATS: Dictionary = {"pierre":"ciseaux", "feuille":"pierre", "ciseaux":"feuille"}
const PREBATTLE_TIMER_SECONDS: float = 30.0
const RPS_REVEAL_DELAY: float = 0.42
const AI_PICK_REVEAL_DELAY: float = 0.80

var cards_by_id: Dictionary = {}
var cards: Array[Dictionary] = []
var stage_root: Control
var footer: Label
var title_label: Label

var rps_context: String = "draft"
var rps_player_choice: String = ""
var rps_ai_choice: String = ""
var rps_winner: String = ""

var draft_owner: Dictionary = {}
var ally_draft: Array[String] = []
var enemy_draft: Array[String] = []
var draft_first_team: String = "ally"
var draft_selected_id: String = ""

var ally_starters: Array[String] = []
var enemy_starters: Array[String] = []
var lineup_detail_id: String = ""

var decision_time_left: float = 0.0
var decision_timer_active: bool = false
var decision_context: String = ""
var decision_timer_label: Label
var rps_revealing: bool = false
var ai_reveal_id: String = ""
var last_pick_id: String = ""
var last_pick_team: String = ""

# P47M.5 — Native Canvas Draft.
# Android now scrolls ONE cached CanvasItem made from ONE atlas texture.
# No Button/Label/TextureRect card trees are created while scrolling.
var draft_mobile_scroll: ScrollContainer = null
var draft_mobile_canvas: YugitoDraftCanvas = null
var draft_mobile_saved_scroll: float = 0.0
var draft_mobile_index_by_id: Dictionary = {}
var draft_detail_root: Control = null

# Do not invalidate the whole Canvas/UI 60 times per second for a timer that
# visually changes only once per second.
var decision_timer_last_second: int = -1
var decision_timer_last_urgent: bool = false

func _ready() -> void:
    MobilePlatform.enforce_landscape()
    set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    # P47M.4 : le root ne doit jamais avaler le bouton MENU de l'AppShell.
    mouse_filter = Control.MOUSE_FILTER_PASS
    z_index = 1000

    # Construire l'interface AVANT tout chargement de données : même si une
    # ressource échoue, le joueur ne peut plus tomber sur un écran gris muet.
    _build_shell()
    _build_audio()
    set_process(true)

    _show_prebattle_boot_state("PRÉPARATION DU SHIFUMI…")
    call_deferred("_boot_prebattle_flow")

func _boot_prebattle_flow() -> void:
    _load_cards()
    if cards.is_empty():
        _show_prebattle_error(
            "Impossible de charger les cartes YUGITO.\n"
            + "Retourne au menu puis relance le Solo."
        )
        return
    _begin_rps("draft")

func _show_prebattle_boot_state(message: String) -> void:
    _clear_stage()
    if title_label != null:
        title_label.text = "PRÉPARATION"
    _label(
        stage_root,
        message,
        Rect2(280,250,1000,64),
        28,
        Color("f2f6fa"),
        HORIZONTAL_ALIGNMENT_CENTER,
        true
    )
    _label(
        stage_root,
        "Initialisation du mode Classic…",
        Rect2(380,320,800,36),
        11,
        Color("91a6bb"),
        HORIZONTAL_ALIGNMENT_CENTER,
        false
    )

func _show_prebattle_error(message: String) -> void:
    _clear_stage()
    if title_label != null:
        title_label.text = "ERREUR PRÉ-COMBAT"
    _label(
        stage_root,
        "PRÉ-COMBAT INDISPONIBLE",
        Rect2(280,210,1000,54),
        28,
        Color("ef787e"),
        HORIZONTAL_ALIGNMENT_CENTER,
        true
    )
    _label(
        stage_root,
        message,
        Rect2(360,282,840,100),
        13,
        Color("e8eef5"),
        HORIZONTAL_ALIGNMENT_CENTER,
        false
    )
    var back_btn: Button = _button(
        stage_root,
        Rect2(590,420,380,62),
        "RETOUR AU MENU",
        Color("ef8b91"),
        true
    )
    back_btn.pressed.connect(func() -> void: cancelled.emit())

func _process(delta: float) -> void:
    if not decision_timer_active:
        return
    decision_time_left = maxf(0.0, decision_time_left - delta)
    if is_instance_valid(decision_timer_label):
        var shown_second: int = int(ceil(decision_time_left))
        var urgent: bool = decision_time_left <= 8.0
        if shown_second != decision_timer_last_second:
            decision_timer_last_second = shown_second
            decision_timer_label.text = "%02d" % shown_second
        if urgent != decision_timer_last_urgent:
            decision_timer_last_urgent = urgent
            decision_timer_label.add_theme_color_override("font_color", Color("ef6659") if urgent else Color("f0d25e"))
    if decision_time_left <= 0.0:
        decision_timer_active = false
        _on_prebattle_timeout(decision_context)

func _start_decision_timer(context: String) -> void:
    decision_context = context
    decision_time_left = PREBATTLE_TIMER_SECONDS
    decision_timer_active = true
    decision_timer_last_second = -1
    decision_timer_last_urgent = false

func _stop_decision_timer() -> void:
    decision_timer_active = false
    decision_context = ""
    decision_time_left = 0.0
    decision_timer_last_second = -1
    decision_timer_last_urgent = false

func _timer_badge(parent: Node, rect: Rect2, context: String) -> void:
    _panel(parent, rect, Color(0.98,0.99,1.0,0.10), Color(1.0,0.88,0.55,0.58), 12, 3)
    _label(parent, "TEMPS", Rect2(rect.position + Vector2(10,4), Vector2(rect.size.x-20,14)), 7, Color("91a6bd"), HORIZONTAL_ALIGNMENT_CENTER, true)
    decision_timer_label = _label(parent, "%02d" % int(ceil(decision_time_left if decision_timer_active else PREBATTLE_TIMER_SECONDS)), Rect2(rect.position + Vector2(8,15), Vector2(rect.size.x-16,30)), 20, Color("f0d25e"), HORIZONTAL_ALIGNMENT_CENTER, true)
    if not decision_timer_active or decision_context != context:
        _start_decision_timer(context)
        decision_timer_label.text = "%02d" % int(PREBATTLE_TIMER_SECONDS)

func _on_prebattle_timeout(context: String) -> void:
    if context == "rps" and rps_player_choice.is_empty() and not rps_revealing:
        var choices: Array[String] = ["pierre","feuille","ciseaux"]
        footer.text = "Temps écoulé : choix Shifumi automatique."
        _choose_rps(choices[randi() % choices.size()])
        return
    if context == "draft" and _scheduled_team() == "ally":
        var best_id: String = ""
        var best_score: float = -INF
        for d: Dictionary in cards:
            if not _draft_allowed("ally", d):
                continue
            var score: float = _ai_card_score(d, ally_draft)
            if score > best_score:
                best_score = score
                best_id = str(d.get("id", ""))
        if not best_id.is_empty():
            draft_selected_id = best_id
            footer.text = "Temps écoulé : YUGITO choisit automatiquement %s." % str((cards_by_id.get(best_id,{}) as Dictionary).get("name",best_id))
            _apply_draft_pick("ally", best_id)
        return
    if context == "lineup":
        ally_starters = _ai_choose_starters(ally_draft)
        lineup_detail_id = ally_starters[0] if not ally_starters.is_empty() else ""
        footer.text = "Temps écoulé : les 3 Ninjas de départ ont été sélectionnés automatiquement."
        _confirm_lineup()

func _load_cards() -> void:
    cards.clear()
    cards_by_id.clear()
    var f: FileAccess = FileAccess.open("res://data/cards.json", FileAccess.READ)
    if f == null:
        push_error("PreBattle: cards.json introuvable")
        return
    var parsed: Variant = JSON.parse_string(f.get_as_text())
    if parsed is Array:
        for raw: Variant in parsed:
            if raw is Dictionary:
                var d: Dictionary = raw as Dictionary
                var cid: String = str(d.get("id", ""))
                if not cid.is_empty():
                    cards_by_id[cid] = d
                    cards.append(d)
    cards.sort_custom(_sort_prebattle_cards)
    draft_mobile_index_by_id.clear()
    for i: int in range(cards.size()):
        draft_mobile_index_by_id[str(cards[i].get("id",""))] = i

func _sort_prebattle_cards(a: Dictionary, b: Dictionary) -> bool:
    var sa: float = float(a.get("stars", 0.0))
    var sb: float = float(b.get("stars", 0.0))
    if not is_equal_approx(sa, sb):
        return sa < sb
    return str(a.get("name", "")) < str(b.get("name", ""))

func _build_audio() -> void:
    # P45 — le morceau de sélection est géré par l'Autoload persistant.
    AudioManager.play_music("res://assets/audio/music/selection.mp3",-8.0)

func _play_pick(volume_db: float = -9.0) -> void:
    AudioManager.play_sfx("res://assets/audio/ui/pick.mp3",volume_db)

func _build_shell() -> void:
    # P47M.3 — la vidéo est déjà dessinée par AppShell derrière PreBattle.
    # On évite ainsi un deuxième décodeur Theora et le flash/écran gris.
    var header: Panel = _glass_surface(self, Rect2(22,16,1556,66), 20, 0.10, 0.44, 10)
    header.z_index = 30
    _logo_in_panel(header, Vector2(22,13),38)
    _label(header,"YUGITO",Rect2(72,8,160,42),26,Color("ffffff"),HORIZONTAL_ALIGNMENT_LEFT,true)
    _label(header,"PRÉPARATION DU COMBAT",Rect2(224,13,280,20),8,Color("f3f9fd"),HORIZONTAL_ALIGNMENT_LEFT,true)
    title_label = _label(header,"SHIFUMI",Rect2(540,8,470,42),20,Color("ffffff"),HORIZONTAL_ALIGNMENT_CENTER,true)
    var cancel_btn: Button = _button(header, Rect2(1392,12,138,40), "ANNULER", Color("f3a9b5"), false)
    cancel_btn.pressed.connect(func() -> void: cancelled.emit())

    var body: Panel = _glass_surface(self, Rect2(22,96,1556,748), 24, 0.085, 0.42, 14)
    body.z_index = 10
    _apply_screen_frost(body, 1.65, 0.055)
    stage_root = Control.new()
    stage_root.position = Vector2(22,96)
    stage_root.size = Vector2(1556,748)
    stage_root.visible = true
    stage_root.z_index = 20
    stage_root.mouse_filter = Control.MOUSE_FILTER_PASS
    add_child(stage_root)

    var foot: Panel = _glass_surface(self, Rect2(22,856,1556,30), 12, 0.08, 0.26, 3)
    foot.z_index = 30
    footer = _label(foot,"Shifumi → Draft → 3 Ninjas → Shifumi → Combat",Rect2(14,3,1510,24),8,Color("f4f9fc"),HORIZONTAL_ALIGNMENT_LEFT,false)

func _glass_surface(parent: Node, rect: Rect2, radius: int = 18, fill_alpha: float = 0.08, border_alpha: float = 0.34, shadow_size: int = 6) -> Panel:
    var p := Panel.new()
    p.position = rect.position
    p.size = rect.size
    p.mouse_filter = Control.MOUSE_FILTER_IGNORE
    var st := StyleBoxFlat.new()
    st.bg_color = Color(0.010,0.024,0.042,maxf(0.40,fill_alpha))
    st.border_color = Color(0.78,0.90,1.0,maxf(0.32,border_alpha))
    st.set_border_width_all(1)
    st.set_corner_radius_all(radius)
    st.shadow_color = Color(0,0,0,0.18)
    st.shadow_size = shadow_size
    st.shadow_offset = Vector2(0,4)
    p.add_theme_stylebox_override("panel",st)
    parent.add_child(p)
    return p

func _apply_screen_frost(panel: Control, lod: float = 1.65, frost: float = 0.055) -> void:
    if MobilePlatform.is_android():
        var mobile_tint := ColorRect.new()
        mobile_tint.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
        mobile_tint.mouse_filter = Control.MOUSE_FILTER_IGNORE
        mobile_tint.color = Color(0.010,0.024,0.042,0.44)
        panel.add_child(mobile_tint)
        return
    var blur := ColorRect.new()
    blur.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    blur.mouse_filter = Control.MOUSE_FILTER_IGNORE
    var mat := ShaderMaterial.new()
    var sh := Shader.new()
    sh.code = """
shader_type canvas_item;
uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_linear_mipmap;
uniform float lod = 1.65;
uniform float frost = 0.055;
void fragment() {
    vec4 c = textureLod(screen_texture, SCREEN_UV, lod);
    c.rgb = mix(c.rgb, vec3(0.010,0.024,0.042), 0.54 + frost);
    COLOR = vec4(c.rgb, 0.92);
}
"""
    mat.shader = sh
    mat.set_shader_parameter("lod",lod)
    mat.set_shader_parameter("frost",frost)
    blur.material = mat
    panel.add_child(blur)

func _logo_in_panel(parent: Node, pos: Vector2, side: float) -> void:
    var logo := TextureRect.new()
    logo.position = pos
    logo.size = Vector2(side,side)
    logo.texture = AssetCache.texture("res://assets/ui/YUGITO.png")
    logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
    logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
    logo.mouse_filter = Control.MOUSE_FILTER_IGNORE
    parent.add_child(logo)

func _clear_stage() -> void:
    draft_mobile_scroll = null
    draft_mobile_canvas = null
    draft_detail_root = null
    for child: Node in stage_root.get_children():
        stage_root.remove_child(child)
        child.queue_free()

func _begin_rps(context: String) -> void:
    rps_context = context
    rps_player_choice = ""
    rps_ai_choice = ""
    rps_winner = ""
    rps_revealing = false
    _stop_decision_timer()
    _draw_rps()

func _draw_rps() -> void:
    _clear_stage()
    title_label.text = "SHIFUMI"
    var subtitle: String = "Le gagnant obtient le premier choix du draft." if rps_context == "draft" else "Le gagnant joue le premier tour du duel."
    _label(stage_root,"SHIFUMI",Rect2(230,34,1100,48),34,Color("f2f6fa"),HORIZONTAL_ALIGNMENT_CENTER,true)
    _label(stage_root,subtitle,Rect2(330,82,900,30),12,Color("93a9bd"),HORIZONTAL_ALIGNMENT_CENTER,false)
    _timer_badge(stage_root, Rect2(1430,28,92,54), "rps")

    if rps_player_choice.is_empty():
        _label(stage_root,"CHOISIS TON SIGNE",Rect2(420,132,724,30),15,Color("e8eef5"),HORIZONTAL_ALIGNMENT_CENTER,true)
        var choices: Array[Dictionary] = [
            {"id":"pierre","label":"PIERRE","sub":"bat Ciseaux","accent":Color("ef6659")},
            {"id":"feuille","label":"FEUILLE","sub":"bat Pierre","accent":Color("55d58b")},
            {"id":"ciseaux","label":"CISEAUX","sub":"bat Feuille","accent":Color("58aff0")}
        ]
        var x: float = 248.0
        for item: Dictionary in choices:
            var accent: Color = item.get("accent", Color.WHITE) as Color
            var card_panel: Panel = _panel(stage_root,Rect2(x,190,326,350),Color(0.019,0.040,0.066,0.96),Color(accent.r,accent.g,accent.b,0.58),22,10)
            _label(card_panel,str(item.get("label","")),Rect2(20,62,286,54),30,Color("f3f7fa"),HORIZONTAL_ALIGNMENT_CENTER,true)
            _label(card_panel,str(item.get("sub","")),Rect2(20,126,286,28),11,accent.lightened(0.12),HORIZONTAL_ALIGNMENT_CENTER,false)
            _label(card_panel,"CHOIX SECRET",Rect2(20,184,286,24),8,Color("7e94a8"),HORIZONTAL_ALIGNMENT_CENTER,true)
            var b: Button = _button(card_panel,Rect2(38,244,250,66),"CHOISIR",accent,true)
            b.pressed.connect(_choose_rps.bind(str(item.get("id",""))))
            _animate_rps_choice_card(card_panel, x)
            x += 370.0
        footer.text = "30 secondes • L'IA choisit en même temps • La révélation se fait après ton verrouillage."
        return

    if rps_revealing:
        _draw_rps_wait()
        return

    _stop_decision_timer()
    var ally_accent: Color = Color("55d58b")
    var enemy_accent: Color = Color("e85c66")
    var ally_panel: Panel = _result_card(Rect2(312,190,380,300),"TOI",rps_player_choice,ally_accent)
    var enemy_panel: Panel = _result_card(Rect2(872,190,380,300),"IA",rps_ai_choice,enemy_accent)
    _label(stage_root,"VS",Rect2(705,300,154,52),28,Color("73869a"),HORIZONTAL_ALIGNMENT_CENTER,true)
    _animate_result_panel(ally_panel, Vector2(-80,0))
    _animate_result_panel(enemy_panel, Vector2(80,0))
    var result_text: String = "ÉGALITÉ" if rps_winner == "tie" else ("VICTOIRE" if rps_winner == "ally" else "DÉFAITE")
    var result_color: Color = Color("e5be4f") if rps_winner == "tie" else (ally_accent if rps_winner == "ally" else enemy_accent)
    _label(stage_root,result_text,Rect2(430,528,704,48),30,result_color,HORIZONTAL_ALIGNMENT_CENTER,true)
    var continue_btn: Button = _button(stage_root,Rect2(590,606,384,60),"REJOUER" if rps_winner == "tie" else "CONTINUER",result_color,true)
    if rps_winner == "tie":
        continue_btn.pressed.connect(func() -> void: _begin_rps(rps_context))
    else:
        continue_btn.pressed.connect(_continue_after_rps)
    footer.text = "Choix révélés simultanément • %s" % result_text

func _draw_rps_wait() -> void:
    _label(stage_root,"CHOIX VERROUILLÉ",Rect2(360,150,844,34),18,Color("f0d25e"),HORIZONTAL_ALIGNMENT_CENTER,true)
    var ally_panel: Panel = _result_card(Rect2(312,220,380,280),"TOI",rps_player_choice,Color("55d58b"))
    var enemy_panel: Panel = _panel(stage_root,Rect2(872,220,380,280),Color(0.018,0.036,0.060,0.96),Color(0.35,0.45,0.56,0.50),18,8)
    _label(enemy_panel,"IA",Rect2(22,34,336,32),17,Color("e85c66"),HORIZONTAL_ALIGNMENT_CENTER,true)
    _label(enemy_panel,"•••",Rect2(22,108,336,56),34,Color("8fa6bb"),HORIZONTAL_ALIGNMENT_CENTER,true)
    _label(enemy_panel,"RÉVÉLATION…",Rect2(22,178,336,28),10,Color("70869a"),HORIZONTAL_ALIGNMENT_CENTER,true)
    _label(stage_root,"VS",Rect2(705,316,154,52),28,Color("73869a"),HORIZONTAL_ALIGNMENT_CENTER,true)
    _animate_result_panel(ally_panel, Vector2(-60,0))
    var tw: Tween = enemy_panel.create_tween().set_loops(2)
    tw.tween_property(enemy_panel,"modulate:a",0.45,0.16)
    tw.tween_property(enemy_panel,"modulate:a",1.0,0.16)

func _animate_rps_choice_card(panel: Control, target_x: float) -> void:
    panel.position.y += 24.0
    panel.modulate.a = 0.0
    var tw: Tween = panel.create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
    tw.tween_property(panel,"position:y",190.0,0.30)
    tw.parallel().tween_property(panel,"modulate:a",1.0,0.24)

func _animate_result_panel(panel: Control, offset: Vector2) -> void:
    var target: Vector2 = panel.position
    panel.position += offset
    panel.modulate.a = 0.0
    var tw: Tween = panel.create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
    tw.tween_property(panel,"position",target,0.34)
    tw.parallel().tween_property(panel,"modulate:a",1.0,0.24)

func _result_card(rect: Rect2, who: String, choice: String, accent: Color) -> Panel:
    var p: Panel = _panel(stage_root,rect,Color(0.020,0.042,0.068,0.94),Color(accent.r,accent.g,accent.b,0.50),18,8)
    _label(p,who,Rect2(22,34,rect.size.x-44,32),17,accent.lightened(0.12),HORIZONTAL_ALIGNMENT_CENTER,true)
    _label(p,choice.to_upper(),Rect2(22,105,rect.size.x-44,52),30,Color("f4f7fb"),HORIZONTAL_ALIGNMENT_CENTER,true)
    return p

func _choose_rps(choice: String) -> void:
    if not rps_player_choice.is_empty() or rps_revealing:
        return
    _play_pick()
    _stop_decision_timer()
    rps_player_choice = choice
    var choices: Array[String] = ["pierre","feuille","ciseaux"]
    rps_ai_choice = choices[randi() % choices.size()]
    rps_revealing = true
    _draw_rps()
    var timer: SceneTreeTimer = get_tree().create_timer(RPS_REVEAL_DELAY)
    timer.timeout.connect(_finish_rps_reveal)

func _finish_rps_reveal() -> void:
    if not rps_revealing:
        return
    if rps_player_choice == rps_ai_choice:
        rps_winner = "tie"
    elif str(RPS_BEATS.get(rps_player_choice,"")) == rps_ai_choice:
        rps_winner = "ally"
    else:
        rps_winner = "enemy"
    rps_revealing = false
    _draw_rps()

func _continue_after_rps() -> void:
    if rps_winner not in ["ally", "enemy"]:
        return
    if rps_context == "draft":
        draft_first_team = rps_winner
        _begin_draft()
    else:
        GameSession.configure_match(ally_draft, enemy_draft, ally_starters, enemy_starters, rps_winner, draft_first_team)
        battle_requested.emit()

func _begin_draft() -> void:
    draft_owner.clear()
    ally_draft.clear()
    draft_mobile_saved_scroll = 0.0
    enemy_draft.clear()
    draft_selected_id = ""
    for d: Dictionary in cards:
        draft_owner[str(d.get("id",""))] = ""
    ai_reveal_id = ""
    last_pick_id = ""
    last_pick_team = ""
    _stop_decision_timer()
    _draw_draft()
    _maybe_ai_draft()

func _draft_pick_index() -> int:
    return ally_draft.size() + enemy_draft.size()

func _scheduled_team() -> String:
    var idx: int = _draft_pick_index()
    if idx >= PICK_RELATIVE.size():
        return ""
    var first: String = draft_first_team
    var second: String = "enemy" if first == "ally" else "ally"
    return first if PICK_RELATIVE[idx] == "first" else second

func _draft_cap() -> float:
    var idx: int = _draft_pick_index()
    var cap: float = 3.0
    for i: int in range(mini(PICK_CAPS.size(), idx + 1)):
        cap = maxf(cap, PICK_CAPS[i])
    return cap

func _draft_round() -> int:
    var idx: int = _draft_pick_index()
    if idx <= 2: return 1
    if idx <= 6: return 2
    if idx <= 10: return 3
    if idx <= 14: return 4
    return 5

func _draft_deck(team: String) -> Array[String]:
    return ally_draft if team == "ally" else enemy_draft

func _draft_total(team: String) -> float:
    var total: float = 0.0
    for cid: String in _draft_deck(team):
        var data: Dictionary = cards_by_id.get(cid,{}) as Dictionary
        total += float(data.get("stars",0.0))
    return total

func _star_count(team: String, stars_value: float) -> int:
    var count: int = 0
    for cid: String in _draft_deck(team):
        var data: Dictionary = cards_by_id.get(cid,{}) as Dictionary
        if is_equal_approx(float(data.get("stars",0.0)),stars_value):
            count += 1
    return count

func _draft_allowed(team: String, data: Dictionary) -> bool:
    var cid: String = str(data.get("id",""))
    if not str(draft_owner.get(cid, "")).is_empty():
        return false
    var stars_value: float = float(data.get("stars",0.0))
    if stars_value > _draft_cap() + 0.001:
        return false
    if _draft_total(team) + stars_value > MAX_TOTAL_STARS + 0.001:
        return false
    var limit: int = int(STAR_LIMITS.get(stars_value,-1))
    if limit >= 0 and _star_count(team, stars_value) >= limit:
        return false
    return _draft_deck(team).size() < DRAFT_SIZE

func _draft_lock_reason(team: String, data: Dictionary) -> String:
    var cid: String = str(data.get("id",""))
    var owner: String = str(draft_owner.get(cid,""))
    if owner == "ally": return "DÉJÀ DANS TON DECK"
    if owner == "enemy": return "CHOISI PAR L'ADVERSAIRE"
    var stars_value: float = float(data.get("stars",0.0))
    if stars_value > _draft_cap() + 0.001: return "PALIER %.1f★ NON DÉBLOQUÉ" % stars_value
    if _draft_total(team) + stars_value > MAX_TOTAL_STARS + 0.001: return "DÉPASSERAIT 32,5★"
    var limit: int = int(STAR_LIMITS.get(stars_value,-1))
    if limit >= 0 and _star_count(team,stars_value) >= limit: return "QUOTA %.1f★ ATTEINT" % stars_value
    if _draft_deck(team).size() >= DRAFT_SIZE: return "DECK COMPLET"
    return "DISPONIBLE"

func _draw_pick_history(team: String, rect: Rect2, title: String, accent: Color) -> void:
    _panel(stage_root,rect,Color(0.012,0.027,0.045,0.97),Color(accent.r,accent.g,accent.b,0.45),14,5)
    _label(stage_root,title,Rect2(rect.position+Vector2(12,10),Vector2(rect.size.x-24,28)),12,accent,HORIZONTAL_ALIGNMENT_CENTER,true)
    var deck: Array[String] = _draft_deck(team)
    _label(stage_root,"%d/8 • %.1f/32,5★" % [deck.size(),_draft_total(team)],Rect2(rect.position+Vector2(10,38),Vector2(rect.size.x-20,22)),8,Color("8fa6bb"),HORIZONTAL_ALIGNMENT_CENTER,true)
    var y: float = rect.position.y + 70.0
    for i: int in range(DRAFT_SIZE):
        var row_bg: Color = Color(0.020,0.041,0.064,0.92)
        var row_border: Color = Color(accent.r,accent.g,accent.b,0.34)
        _panel(stage_root,Rect2(rect.position.x+10,y,rect.size.x-20,60),row_bg,row_border,9)
        if i < deck.size():
            var cid: String = deck[i]
            var d: Dictionary = cards_by_id.get(cid,{}) as Dictionary
            var art: TextureRect = TextureRect.new()
            art.position = Vector2(rect.position.x+16,y+5)
            art.size = Vector2(40,50)
            art.texture = _draft_atlas_art(cid)
            art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
            art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
            art.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
            art.mouse_filter = Control.MOUSE_FILTER_IGNORE
            stage_root.add_child(art)
            _label(stage_root,"%d. %s" % [i+1,str(d.get("name",cid))],Rect2(rect.position.x+62,y+7,rect.size.x-78,25),8,Color("edf3f8"),HORIZONTAL_ALIGNMENT_LEFT,true)
            _label(stage_root,"%s★ • %s" % [_stars_text(float(d.get("stars",0.0))),str(d.get("element",""))],Rect2(rect.position.x+62,y+31,rect.size.x-78,20),7,_element_color(str(d.get("element",""))),HORIZONTAL_ALIGNMENT_LEFT,true)
            if cid == last_pick_id:
                _label(stage_root,"NOUVEAU",Rect2(rect.position.x+110,y+37,rect.size.x-126,16),6,Color("f0d25e"),HORIZONTAL_ALIGNMENT_RIGHT,true)
        else:
            _label(stage_root,"CHOIX %d" % (i+1),Rect2(rect.position.x+20,y+16,rect.size.x-40,24),8,Color("4f6477"),HORIZONTAL_ALIGNMENT_CENTER,true)
        y += 67.0

func _draw_draft_rules_bar(active: String) -> void:
    var accent: Color = Color("55d58b") if active == "ally" else Color("e85c66")
    _panel(stage_root,Rect2(236,88,1092,58),Color(0.018,0.036,0.057,0.98),Color(accent.r,accent.g,accent.b,0.40),12)
    _label(stage_root,"PALIER DÉBLOQUÉ  ≤ %.1f★" % _draft_cap(),Rect2(250,96,228,22),9,accent,HORIZONTAL_ALIGNMENT_LEFT,true)
    _label(stage_root,"BUDGET  %.1f / 32,5★" % _draft_total(active),Rect2(478,96,190,22),9,Color("e8eef5"),HORIZONTAL_ALIGNMENT_LEFT,true)
    _label(stage_root,"3,5★ %d/4   •   4★ %d/3   •   4,5★ %d/2   •   5★ %d/1" % [_star_count(active,3.5),_star_count(active,4.0),_star_count(active,4.5),_star_count(active,5.0)],Rect2(668,96,518,22),8,Color("91a6bb"),HORIZONTAL_ALIGNMENT_LEFT,true)
    _label(stage_root,"Une rareté débloquée reste disponible jusqu'à la fin.",Rect2(250,119,820,18),7,Color("70879b"),HORIZONTAL_ALIGNMENT_LEFT,false)
    if active == "ally":
        _timer_badge(stage_root,Rect2(1218,92,96,48),"draft")

func _draw_draft() -> void:
    _clear_stage()
    title_label.text = "DRAFT CLASSIC"
    var active: String = _scheduled_team()
    var active_name: String = "À TOI" if active == "ally" else "À L'ADVERSAIRE"
    _label(stage_root,"DRAFT CLASSIC",Rect2(236,14,1092,34),24,Color("f3f7fa"),HORIZONTAL_ALIGNMENT_CENTER,true)
    _label(stage_root,"PICK %d/16  •  TOUR %d  •  %s" % [_draft_pick_index()+1,_draft_round(),active_name],Rect2(236,49,1092,26),11,Color("f0d25e") if active == "ally" else Color("e85c66"),HORIZONTAL_ALIGNMENT_CENTER,true)

    _draw_pick_history("ally",Rect2(14,14,208,708),"TES CHOIX",Color("55d58b"))
    _draw_pick_history("enemy",Rect2(1342,14,208,708),"CHOIX ADVERSAIRE",Color("e85c66"))
    _draw_draft_rules_bar(active)

    _panel(stage_root,Rect2(236,158,786,564),Color(0.014,0.030,0.050,0.92),Color(0.27,0.44,0.60,0.30),14)
    var scroll: ScrollContainer = ScrollContainer.new()
    scroll.position = Vector2(246,168)
    scroll.size = Vector2(766,544)
    scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
    scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
    # Let Godot's native C++ touch scrolling / inertia do the work.
    scroll.scroll_deadzone = 10
    scroll.follow_focus = false
    stage_root.add_child(scroll)

    if MobilePlatform.is_android():
        # P47M.5: a single cached atlas-backed CanvasItem.
        _build_mobile_native_canvas(scroll, active)
    else:
        var grid: GridContainer = GridContainer.new()
        grid.columns = 3
        grid.add_theme_constant_override("h_separation",8)
        grid.add_theme_constant_override("v_separation",10)
        scroll.add_child(grid)
        for data: Dictionary in cards:
            grid.add_child(_draft_card(data, active))

    _draw_draft_detail(Rect2(1034,158,294,564), active)
    if not ai_reveal_id.is_empty():
        _draw_ai_pick_reveal(ai_reveal_id)
    elif active == "enemy":
        _label(stage_root,"L'ADVERSAIRE RÉFLÉCHIT…",Rect2(450,675,358,28),9,Color("e85c66"),HORIZONTAL_ALIGNMENT_CENTER,true)
    footer.text = "Centre : glisse directement sur les cartes pour défiler • Molette compatible • Tap pour prévisualiser • CONFIRMER pour drafter."

func _draw_ai_pick_reveal(cid: String) -> void:
    var data: Dictionary = cards_by_id.get(cid,{}) as Dictionary
    if data.is_empty(): return
    var veil: ColorRect = ColorRect.new()
    veil.position = Vector2(236,158)
    veil.size = Vector2(786,564)
    veil.color = Color(0.003,0.008,0.015,0.82)
    veil.mouse_filter = Control.MOUSE_FILTER_STOP
    veil.z_index = 20000
    stage_root.add_child(veil)
    var p: Panel = _panel(stage_root,Rect2(420,232,420,390),Color(0.020,0.040,0.064,0.99),Color(0.91,0.36,0.40,0.65),18,10)
    _label(p,"L'ADVERSAIRE CHOISIT",Rect2(20,18,380,28),12,Color("e85c66"),HORIZONTAL_ALIGNMENT_CENTER,true)
    var art: TextureRect = TextureRect.new()
    art.position = Vector2(50,58)
    art.size = Vector2(320,218)
    art.texture = _draft_atlas_art(cid)
    art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
    art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
    art.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
    p.add_child(art)
    _label(p,str(data.get("name",cid)),Rect2(24,290,372,38),20,Color("f4f7fb"),HORIZONTAL_ALIGNMENT_CENTER,true)
    _label(p,"%s★  •  %s" % [_stars_text(float(data.get("stars",0.0))),str(data.get("element","")).to_upper()],Rect2(24,330,372,24),9,_element_color(str(data.get("element",""))),HORIZONTAL_ALIGNMENT_CENTER,true)
    _animate_result_panel(p,Vector2(0,34))

func _build_mobile_native_canvas(scroll: ScrollContainer, active: String) -> void:
    draft_mobile_scroll = scroll

    var available_by_id: Dictionary = {}
    var interactive_by_id: Dictionary = {}
    var reason_by_id: Dictionary = {}

    for data: Dictionary in cards:
        var cid: String = str(data.get("id",""))
        var available: bool = _draft_allowed(active, data) if not active.is_empty() else false
        available_by_id[cid] = available
        interactive_by_id[cid] = (
            active == "ally"
            and available
            and str(draft_owner.get(cid,"")).is_empty()
        )
        reason_by_id[cid] = _draft_lock_reason(active, data)

    var canvas: YugitoDraftCanvas = DraftCanvas.new()
    canvas.configure(
        cards,
        draft_owner,
        available_by_id,
        interactive_by_id,
        reason_by_id,
        draft_selected_id
    )
    canvas.card_tapped.connect(_on_draft_card_pressed)
    scroll.add_child(canvas)
    draft_mobile_canvas = canvas

    # Restore only when a draft screen is rebuilt after a pick.
    # During the actual drag there is no GDScript scroll assignment at all.
    call_deferred("_restore_mobile_draft_scroll")

func _restore_mobile_draft_scroll() -> void:
    if not is_instance_valid(draft_mobile_scroll):
        return
    draft_mobile_scroll.scroll_vertical = int(maxf(0.0, draft_mobile_saved_scroll))

func _capture_mobile_draft_scroll() -> void:
    if not MobilePlatform.is_android():
        return
    if is_instance_valid(draft_mobile_scroll):
        draft_mobile_saved_scroll = float(draft_mobile_scroll.scroll_vertical)

func _draft_atlas_art(cid: String) -> Texture2D:
    if not MobilePlatform.is_android():
        return AssetCache.texture("res://assets/cards/%s_field.png" % cid)
    var index: int = int(draft_mobile_index_by_id.get(cid, -1))
    if index < 0:
        return AssetCache.texture("res://assets/cards/%s_field.png" % cid)
    return DraftCanvas.card_art_texture(index)

func _draft_card(data: Dictionary, active: String) -> Button:
    var cid: String = str(data.get("id", ""))
    var owner: String = str(draft_owner.get(cid, ""))
    var allowed: bool = _draft_allowed(active, data) if not active.is_empty() else false
    var muted: bool = not owner.is_empty() or not allowed
    var tag: String = _draft_lock_reason(active, data)
    var card: YugitoMenuCard = MenuCard.new()
    var mobile_size: Vector2 = Vector2(240, 360) if MobilePlatform.is_android() else Vector2(228, 350)
    card.setup(data, mobile_size, cid == draft_selected_id, muted, tag)
    card.disabled = active != "ally" or not owner.is_empty() or not allowed
    card.pressed.connect(_on_draft_card_pressed.bind(cid))
    return card

func _on_draft_card_pressed(cid: String) -> void:
    if _scheduled_team() != "ally":
        return
    _play_pick()
    draft_selected_id = cid

    if MobilePlatform.is_android():
        if is_instance_valid(draft_mobile_canvas):
            draft_mobile_canvas.set_selected(cid)
        _open_mobile_draft_sheet(cid)
    else:
        _draw_draft()

func _open_mobile_draft_sheet(cid: String) -> void:
    var data: Dictionary = cards_by_id.get(cid,{}) as Dictionary
    if data.is_empty():
        return
    if is_instance_valid(draft_detail_root):
        var old_parent: Node = draft_detail_root.get_parent()
        if old_parent != null:
            old_parent.remove_child(draft_detail_root)
        draft_detail_root.queue_free()

    # P48.1 MOBILE — vraie fiche plein écran lisible au doigt.
    # On évite le grand bandeau recadré : l'illustration conserve maintenant
    # tout son cadrage et les informations principales sont séparées en blocs.
    var root := Control.new()
    root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    root.mouse_filter = Control.MOUSE_FILTER_STOP
    root.z_index = 26000
    stage_root.add_child(root)
    draft_detail_root = root

    var dim := ColorRect.new()
    dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    dim.color = Color(0.002,0.006,0.012,0.88)
    dim.mouse_filter = Control.MOUSE_FILTER_STOP
    root.add_child(dim)

    var win: Panel = _panel(root,Rect2(45,30,1510,840),Color(0.012,0.025,0.042,0.995),Color(0.42,0.68,0.86,0.72),20,12)
    _label(win,"FICHE NINJA — DRAFT",Rect2(28,16,720,46),27,Color("f4f8fb"),HORIZONTAL_ALIGNMENT_LEFT,true)
    var close: Button = _button(win,Rect2(1320,14,155,50),"FERMER",Color("8cb9d8"),false)
    close.pressed.connect(_close_mobile_draft_sheet.bind(root))

    var accent: Color = _element_color(str(data.get("element","")))
    var cid_local: String = str(data.get("id",""))

    # Illustration complète, sans crop. C'est volontairement un grand bloc.
    var art_panel: Panel = _panel(win,Rect2(28,78,560,410),Color(0.006,0.014,0.024,0.98),Color(accent.r,accent.g,accent.b,0.58),14,4)
    art_panel.clip_contents = true
    var art := TextureRect.new()
    art.position = Vector2(8,8)
    art.size = Vector2(544,394)
    art.texture = _draft_atlas_art(cid_local)
    art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
    art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
    art.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
    art.mouse_filter = Control.MOUSE_FILTER_IGNORE
    art_panel.add_child(art)

    _label(win,str(data.get("name",cid_local)),Rect2(28,496,390,42),24,Color("f4f8fb"),HORIZONTAL_ALIGNMENT_LEFT,true)
    _label(win,"%s★  •  %s" % [_stars_text(float(data.get("stars",0.0))),str(data.get("element","")).to_upper()],Rect2(410,500,178,34),14,accent.lightened(0.14),HORIZONTAL_ALIGNMENT_RIGHT,true)

    # Stats : 4 vraies cases très visibles au lieu d'une petite ligne.
    var stat_defs: Array[Dictionary] = [
        {"k":"PV","v":int(data.get("hp",0))},
        {"k":"TAI","v":int(data.get("taijutsu",0))},
        {"k":"NIN","v":int(data.get("ninjutsu",0))},
        {"k":"GEN","v":int(data.get("genjutsu",0))}
    ]
    for i: int in range(stat_defs.size()):
        var sx: float = 28.0 + float(i) * 140.0
        _panel(win,Rect2(sx,548,130,92),Color(0.025,0.050,0.076,0.92),Color(accent.r,accent.g,accent.b,0.35),10)
        _label(win,str(stat_defs[i]["k"]),Rect2(sx,556,130,24),12,Color("93a9bd"),HORIZONTAL_ALIGNMENT_CENTER,true)
        _label(win,str(stat_defs[i]["v"]),Rect2(sx,579,130,48),24,Color("f6fbff"),HORIZONTAL_ALIGNMENT_CENTER,true)

    # Texte à droite : taille réellement pensée pour un téléphone paysage.
    var info_panel: Panel = _panel(win,Rect2(610,78,865,562),Color(0.008,0.020,0.034,0.88),Color(1,1,1,0.11),14)
    var info_scroll := ScrollContainer.new()
    info_scroll.position = Vector2(18,18)
    info_scroll.size = Vector2(829,526)
    info_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
    info_panel.add_child(info_scroll)
    var rich := RichTextLabel.new()
    rich.custom_minimum_size = Vector2(800,560)
    rich.bbcode_enabled = true
    rich.fit_content = true
    rich.scroll_active = false
    rich.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    rich.add_theme_font_size_override("normal_font_size",15)
    rich.add_theme_font_size_override("bold_font_size",17)
    rich.add_theme_color_override("default_color",Color("d4e0e9"))
    rich.text = "[color=#61d6a2][font_size=19][b]PASSIF — %s[/b][/font_size][/color]\n%s\n\n[color=#e4bf51][font_size=19][b]TECHNIQUE SPÉCIALE — %s[/b][/font_size][/color]\n%s\n\n[color=#58aff0][font_size=19][b]SYNERGIES[/b][/font_size][/color]\n%s" % [
        str(data.get("passive_name","—")), str(data.get("passive","—")),
        str(data.get("special_name","—")), str(data.get("special","—")),
        SynergyDB.description(cid_local, cards_by_id)
    ]
    info_scroll.add_child(rich)

    var reason: String = _draft_lock_reason("ally",data)
    _label(win,reason,Rect2(28,652,1447,30),14,Color("55d58b") if reason == "DISPONIBLE" else Color("e85c66"),HORIZONTAL_ALIGNMENT_CENTER,true)

    # Bouton demandé au moins x3 : 156 px de haut au lieu de 52.
    var add: Button = _button(win,Rect2(180,688,1150,156),"AJOUTER À L'ÉQUIPE",Color("55d58b"),true)
    add.add_theme_font_size_override("font_size",28)
    add.disabled = _scheduled_team() != "ally" or not _draft_allowed("ally",data)
    add.pressed.connect(_confirm_draft_pick)

func _close_mobile_draft_sheet(root: Control) -> void:
    if is_instance_valid(root):
        root.queue_free()
    draft_detail_root = null

func _draw_draft_detail(rect: Rect2, active: String) -> void:
    if is_instance_valid(draft_detail_root):
        var old_parent: Node = draft_detail_root.get_parent()
        if old_parent != null:
            old_parent.remove_child(draft_detail_root)
        draft_detail_root.queue_free()

    var root: Control = Control.new()
    root.position = rect.position
    root.size = rect.size
    root.mouse_filter = Control.MOUSE_FILTER_PASS
    stage_root.add_child(root)
    draft_detail_root = root

    _panel(root,Rect2(0,0,rect.size.x,rect.size.y),Color(0.018,0.038,0.062,0.96),Color(0.30,0.49,0.65,0.40),14,0)
    _label(root,"APERÇU / CONFIRMATION",Rect2(14,12,rect.size.x-28,26),11,Color("63d9a6"),HORIZONTAL_ALIGNMENT_CENTER,true)
    var data: Dictionary = cards_by_id.get(draft_selected_id,{}) as Dictionary
    if data.is_empty():
        _label(root,"AUCUN NINJA",Rect2(18,112,rect.size.x-36,34),16,Color("eef4f9"),HORIZONTAL_ALIGNMENT_CENTER,true)
        _rich(root,"1. Clique une carte du pool.\n\n2. Lis sa fiche.\n\n3. Confirme seulement quand tu es sûr.\n\nLes cartes illégales indiquent maintenant POURQUOI elles sont bloquées.",Rect2(24,166,rect.size.x-48,230),9,Color("8fa6bb"))
        return
    _card_detail(root,data,Rect2(12,52,rect.size.x-24,430))
    var reason: String = _draft_lock_reason("ally",data)
    _label(root,reason,Rect2(16,486,rect.size.x-32,20),7,Color("55d58b") if reason == "DISPONIBLE" else Color("e85c66"),HORIZONTAL_ALIGNMENT_CENTER,true)
    var confirm: Button = _button(root,Rect2(18,514,rect.size.x-36,38),"CONFIRMER",Color("55d58b"),true)
    confirm.disabled = active != "ally" or not _draft_allowed("ally",data)
    confirm.pressed.connect(_confirm_draft_pick)

func _confirm_draft_pick() -> void:
    if _scheduled_team() != "ally" or draft_selected_id.is_empty():
        return
    var data: Dictionary = cards_by_id.get(draft_selected_id,{}) as Dictionary
    if not _draft_allowed("ally", data):
        return
    _play_pick(-7.0)
    _apply_draft_pick("ally",draft_selected_id)

func _apply_draft_pick(team: String, cid: String) -> void:
    _capture_mobile_draft_scroll()
    var data: Dictionary = cards_by_id.get(cid,{}) as Dictionary
    if data.is_empty() or team != _scheduled_team() or not _draft_allowed(team, data):
        return
    draft_owner[cid] = team
    _draft_deck(team).append(cid)
    last_pick_id = cid
    last_pick_team = team
    draft_selected_id = ""
    if team == "ally": _stop_decision_timer()
    if team == "enemy": ai_reveal_id = ""
    if team == "enemy":
        _play_pick(-16.0)
    if ally_draft.size() >= DRAFT_SIZE and enemy_draft.size() >= DRAFT_SIZE:
        _begin_lineup()
        return
    _draw_draft()
    _maybe_ai_draft()

func _maybe_ai_draft() -> void:
    if _scheduled_team() != "enemy":
        return
    var timer: SceneTreeTimer = get_tree().create_timer(0.45)
    timer.timeout.connect(_ai_draft_pick)

func _ai_draft_pick() -> void:
    if _scheduled_team() != "enemy" or not ai_reveal_id.is_empty():
        return
    var best_id: String = ""
    var best_score: float = -INF
    for d: Dictionary in cards:
        if not _draft_allowed("enemy",d):
            continue
        var score: float = _ai_card_score(d, enemy_draft)
        if score > best_score:
            best_score = score
            best_id = str(d.get("id", ""))
    if not best_id.is_empty():
        ai_reveal_id = best_id
        _draw_draft()
        var reveal_timer: SceneTreeTimer = get_tree().create_timer(AI_PICK_REVEAL_DELAY)
        reveal_timer.timeout.connect(_commit_ai_reveal)

func _commit_ai_reveal() -> void:
    var cid: String = ai_reveal_id
    if cid.is_empty() or _scheduled_team() != "enemy":
        ai_reveal_id = ""
        return
    _apply_draft_pick("enemy",cid)

func _ai_card_score(d: Dictionary, deck: Array[String]) -> float:
    var stats: Array[int] = [int(d.get("taijutsu", 0)), int(d.get("ninjutsu", 0)), int(d.get("genjutsu", 0))]
    stats.sort()
    var score: float = float(d.get("hp",0))*0.36 + float(stats[2]) + float(stats[0]+stats[1]+stats[2])*0.20 + float(d.get("stars",0))*42.0
    var roles: Array = d.get("roles",[]) as Array
    var covered: Dictionary = {}
    var elements: Dictionary = {}
    for cid: String in deck:
        var x: Dictionary = cards_by_id.get(cid,{}) as Dictionary
        elements[str(x.get("element", ""))] = true
        for r: Variant in (x.get("roles",[]) as Array):
            covered[str(r)] = true
    for r: Variant in roles:
        if not covered.has(str(r)):
            score += 48.0
    if not elements.has(str(d.get("element",""))):
        score += 36.0
    if roles.has("SUSTAIN") or roles.has("TANK"):
        score += 28.0
    if roles.has("COUNTER") or roles.has("CONTROLE"):
        score += 24.0
    # L'IA valorise aussi les futures synergies du deck.
    var simulated: Array[String] = deck.duplicate()
    simulated.append(str(d.get("id","")))
    var syn: float = SynergyDB.bonus_for(str(d.get("id","")), simulated)
    score += syn * 520.0
    score += randf_range(0.0,18.0)
    return score

func _begin_lineup() -> void:
    ally_starters.clear()
    enemy_starters = _ai_choose_starters(enemy_draft)
    lineup_detail_id = ally_draft[0] if not ally_draft.is_empty() else ""
    _stop_decision_timer()
    _draw_lineup()

func _draw_lineup() -> void:
    _clear_stage()
    title_label.text = "3 NINJAS DE DÉPART"
    _label(stage_root,"COMPOSE TON ÉQUIPE DE DÉPART",Rect2(28,16,1120,38),24,Color("f2f6fa"),HORIZONTAL_ALIGNMENT_LEFT,true)
    _label(stage_root,"Choisis exactement 3 Ninjas. Les 5 autres restent cachés dans ta réserve.",Rect2(30,52,1040,26),10,Color("90a7bb"),HORIZONTAL_ALIGNMENT_LEFT,false)
    _timer_badge(stage_root,Rect2(1434,20,90,52),"lineup")

    _panel(stage_root,Rect2(24,90,1080,632),Color(0.014,0.030,0.050,0.92),Color(0.27,0.44,0.60,0.30),14)
    _label(stage_root,"TES 8 NINJAS",Rect2(42,100,280,22),10,Color("63d9a6"),HORIZONTAL_ALIGNMENT_LEFT,true)
    var lineup_scroll: ScrollContainer = ScrollContainer.new()
    lineup_scroll.position = Vector2(36,126)
    lineup_scroll.size = Vector2(1056,430)
    lineup_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
    stage_root.add_child(lineup_scroll)
    var grid: GridContainer = GridContainer.new()
    grid.columns = MobilePlatform.recommended_card_columns(4)
    grid.add_theme_constant_override("h_separation",10)
    grid.add_theme_constant_override("v_separation",12)
    lineup_scroll.add_child(grid)
    for cid: String in ally_draft:
        grid.add_child(_lineup_card(cid))

    _label(stage_root,"TES 3 TITULAIRES",Rect2(42,548,500,22),10,Color("f0d25e"),HORIZONTAL_ALIGNMENT_LEFT,true)
    var sx: float = 42.0
    for i: int in range(STARTER_COUNT):
        _panel(stage_root,Rect2(sx,578,230,116),Color(0.020,0.041,0.064,0.94),Color(0.88,0.73,0.29,0.45),10)
        if i < ally_starters.size():
            var cid: String = ally_starters[i]
            var d: Dictionary = cards_by_id.get(cid,{}) as Dictionary
            var art: TextureRect = TextureRect.new()
            art.position = Vector2(sx+7,585)
            art.size = Vector2(76,102)
            art.texture = _draft_atlas_art(cid)
            art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
            art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
            stage_root.add_child(art)
            _label(stage_root,str(d.get("name",cid)),Rect2(sx+92,592,128,42),10,Color("f2f6fa"),HORIZONTAL_ALIGNMENT_LEFT,true)
            _label(stage_root,"%s★" % _stars_text(float(d.get("stars",0.0))),Rect2(sx+92,640,120,20),8,_element_color(str(d.get("element",""))),HORIZONTAL_ALIGNMENT_LEFT,true)
        else:
            _label(stage_root,"EMPLACEMENT %d" % (i+1),Rect2(sx+12,614,206,30),8,Color("51677a"),HORIZONTAL_ALIGNMENT_CENTER,true)
        sx += 244.0

    _panel(stage_root,Rect2(1120,90,416,632),Color(0.018,0.038,0.062,0.96),Color(0.30,0.49,0.65,0.40),14,8)
    _label(stage_root,"ADVERSAIRE",Rect2(1138,104,380,28),13,Color("e85c66"),HORIZONTAL_ALIGNMENT_CENTER,true)
    _label(stage_root,"3 NINJAS SÉLECTIONNÉS",Rect2(1138,136,380,22),8,Color("8fa6bb"),HORIZONTAL_ALIGNMENT_CENTER,true)
    var hx: float = 1152.0
    for i: int in range(3):
        _panel(stage_root,Rect2(hx,172,106,150),Color(0.010,0.021,0.036,0.98),Color(0.37,0.45,0.54,0.40),10)
        _label(stage_root,"?",Rect2(hx+18,202,70,54),28,Color("52677a"),HORIZONTAL_ALIGNMENT_CENTER,true)
        _label(stage_root,"CACHÉ",Rect2(hx+10,267,86,20),7,Color("6f8294"),HORIZONTAL_ALIGNMENT_CENTER,true)
        hx += 118.0
    _label(stage_root,"Les cartes de départ adverses restent secrètes jusqu'au combat.",Rect2(1140,338,376,54),9,Color("8fa6bb"),HORIZONTAL_ALIGNMENT_CENTER,false)
    var detail: Dictionary = cards_by_id.get(lineup_detail_id,{}) as Dictionary
    if not detail.is_empty():
        _label(stage_root,"APERÇU : %s" % str(detail.get("name","")),Rect2(1142,420,372,26),11,Color("f0d25e"),HORIZONTAL_ALIGNMENT_CENTER,true)
        _label(stage_root,"PV %d • TAI %d • NIN %d • GEN %d" % [int(detail.get("hp",0)),int(detail.get("taijutsu",0)),int(detail.get("ninjutsu",0)),int(detail.get("genjutsu",0))],Rect2(1140,450,376,24),8,Color("a8bbcc"),HORIZONTAL_ALIGNMENT_CENTER,true)
        _rich(stage_root,"PASSIF — %s\n%s\n\nSPÉCIALE — %s\n%s" % [str(detail.get("passive_name","—")),str(detail.get("passive","—")),str(detail.get("special_name","—")),str(detail.get("special","—"))],Rect2(1144,484,368,124),8,Color("aabac8"))
    var confirm: Button = _button(stage_root,Rect2(1150,638,356,54),"VALIDER MES 3 (%d/3)" % ally_starters.size(),Color("55d58b"),true)
    confirm.disabled = ally_starters.size() != STARTER_COUNT
    confirm.pressed.connect(_confirm_lineup)
    footer.text = "Contour OR = sélectionné • 30 secondes • L'adversaire ne voit jamais les 5 cartes laissées en réserve."

func _lineup_card(cid: String) -> Button:
    var data: Dictionary = cards_by_id.get(cid,{}) as Dictionary
    var selected: bool = ally_starters.has(cid)
    var card: YugitoMenuCard = MenuCard.new()
    var mobile_size: Vector2 = Vector2(300, 430) if MobilePlatform.is_android() else Vector2(246, 374)
    card.setup(data, mobile_size, selected, false, "✓ NINJA DE DÉPART" if selected else "CLIQUER POUR CHOISIR")
    card.pressed.connect(_on_lineup_card_pressed.bind(cid))
    return card

func _on_lineup_card_pressed(cid: String) -> void:
    _play_pick()
    lineup_detail_id = cid
    if ally_starters.has(cid):
        ally_starters.erase(cid)
    elif ally_starters.size() < STARTER_COUNT:
        ally_starters.append(cid)
    else:
        footer.text = "Tu as déjà choisi 3 Ninjas. Désélectionne-en un avant d'en choisir un autre."
    _draw_lineup()

func _ai_choose_starters(deck: Array[String]) -> Array[String]:
    var pool: Array[String] = deck.duplicate()
    pool.sort_custom(func(a: String, b: String) -> bool:
        return _starter_strength(cards_by_id.get(a,{}) as Dictionary, deck) > _starter_strength(cards_by_id.get(b,{}) as Dictionary, deck)
    )
    var result: Array[String] = []
    for i: int in range(mini(STARTER_COUNT, pool.size())):
        result.append(pool[i])
    return result

func _starter_strength(data: Dictionary, deck: Array[String]) -> float:
    var top: int = maxi(int(data.get("taijutsu", 0)), maxi(int(data.get("ninjutsu", 0)), int(data.get("genjutsu", 0))))
    var total: int = int(data.get("taijutsu", 0)) + int(data.get("ninjutsu", 0)) + int(data.get("genjutsu", 0))
    var score: float = float(data.get("hp", 0))*0.40 + float(top) + float(total)*0.22 + float(data.get("stars", 0.0))*55.0
    var roles: Array = data.get("roles", []) as Array
    if roles.has("SUSTAIN") or roles.has("TANK"): score += 45.0
    if roles.has("COUNTER") or roles.has("CONTROLE"): score += 35.0
    score += SynergyDB.bonus_for(str(data.get("id","")), deck) * 620.0
    return score

func _confirm_lineup() -> void:
    if ally_starters.size() != STARTER_COUNT:
        return
    _stop_decision_timer()
    _play_pick(-7.0)
    _begin_rps("start")

func _card_detail(parent: Node, data: Dictionary, rect: Rect2) -> void:
    var cid: String = str(data.get("id",""))
    var accent: Color = _element_color(str(data.get("element","")))
    var art_h: float = 150.0
    var art_panel: Panel = _panel(parent,Rect2(rect.position,Vector2(rect.size.x,art_h)),Color(0.008,0.018,0.030,0.98),Color(accent.r,accent.g,accent.b,0.42),10)
    art_panel.clip_contents = true
    var art: TextureRect = TextureRect.new()
    art.position = Vector2.ZERO
    art.size = art_panel.size
    art.texture = _draft_atlas_art(cid)
    art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
    art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
    art.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
    art.mouse_filter = Control.MOUSE_FILTER_IGNORE
    art_panel.add_child(art)
    var shade: ColorRect = ColorRect.new()
    shade.position = Vector2(0, art_h - 48)
    shade.size = Vector2(rect.size.x,48)
    shade.color = Color(0.01,0.02,0.04,0.60)
    shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
    art_panel.add_child(shade)
    _label(art_panel,str(data.get("name",cid)),Rect2(14,art_h-43,rect.size.x-120,36),16,Color("f2f6fa"),HORIZONTAL_ALIGNMENT_LEFT,true)
    _label(art_panel,"%s★  •  %s" % [_stars_text(float(data.get("stars",0.0))),str(data.get("element","")).to_upper()],Rect2(rect.size.x-128,art_h-42,112,34),9,accent.lightened(0.12),HORIZONTAL_ALIGNMENT_RIGHT,true)

    _label(parent,"PV %d    TAI %d    NIN %d    GEN %d" % [int(data.get("hp",0)),int(data.get("taijutsu",0)),int(data.get("ninjutsu",0)),int(data.get("genjutsu",0))],Rect2(rect.position+Vector2(0,156),Vector2(rect.size.x,24)),9,Color("a8bbcc"),HORIZONTAL_ALIGNMENT_CENTER,true)

    var scroll: ScrollContainer = ScrollContainer.new()
    scroll.position = rect.position + Vector2(0,184)
    scroll.size = Vector2(rect.size.x, rect.size.y - 184)
    scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
    parent.add_child(scroll)
    var rich: RichTextLabel = RichTextLabel.new()
    rich.custom_minimum_size = Vector2(rect.size.x - 16, maxf(350.0, rect.size.y - 184))
    rich.bbcode_enabled = true
    rich.fit_content = true
    rich.scroll_active = false
    rich.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    rich.add_theme_font_size_override("normal_font_size", 9)
    rich.add_theme_color_override("default_color", Color("bdcad6"))
    rich.text = "[color=#61d6a2][b]PASSIF — %s[/b][/color]\n%s\n\n[color=#e4bf51][b]SPÉCIALE — %s[/b][/color]\n%s\n\n[color=#58aff0][b]SYNERGIES[/b][/color]\n%s" % [
        str(data.get("passive_name","—")), str(data.get("passive","—")),
        str(data.get("special_name","—")), str(data.get("special","—")),
        SynergyDB.description(cid, cards_by_id)
    ]
    scroll.add_child(rich)

func _element_color(element: String) -> Color:
    match element.to_lower():
        "feu": return Color("ef6256")
        "vent": return Color("63d596")
        "foudre": return Color("c09aff")
        "terre": return Color("c79b6b")
        "eau": return Color("55b6f2")
        "tous": return Color("f3d46d")
        _: return Color("7c94ad")

func _stars_text(value: float) -> String:
    if is_equal_approx(value, floorf(value)):
        return "%d" % int(value)
    return "%.1f" % value

func _logo(pos: Vector2, side: float) -> void:
    var t: TextureRect = TextureRect.new()
    t.position = pos
    t.size = Vector2(side, side)
    t.texture = AssetCache.texture("res://assets/ui/YUGITO.png")
    t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
    t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
    t.mouse_filter = Control.MOUSE_FILTER_IGNORE
    add_child(t)

func _panel(parent: Node, rect: Rect2, bg: Color, border: Color, radius: int, shadow: int = 0) -> Panel:
    var p: Panel = Panel.new()
    p.position = rect.position
    p.size = rect.size
    p.mouse_filter = Control.MOUSE_FILTER_IGNORE
    var s: StyleBoxFlat = StyleBoxFlat.new()
    var glass_bg: Color = bg
    var glass_border: Color = border
    if bg.a > 0.45:
        glass_bg = Color(0.008,0.022,0.038,minf(0.64,maxf(0.40,bg.a*0.54)))
        glass_border = Color(border.r,border.g,border.b,maxf(0.32,minf(0.72,border.a+0.18)))
    s.bg_color = glass_bg
    s.border_color = glass_border
    s.set_border_width_all(1)
    s.set_corner_radius_all(radius)
    if shadow > 0:
        s.shadow_size = shadow
        s.shadow_color = Color(0,0,0,0.38)
        s.shadow_offset = Vector2(0,4)
    p.add_theme_stylebox_override("panel",s)
    parent.add_child(p)
    return p

func _label(parent: Node, value: String, rect: Rect2, size_px: int, color: Color, align: HorizontalAlignment, bold: bool) -> Label:
    var l: Label = Label.new()
    l.text = value
    l.position = rect.position
    l.size = rect.size
    l.horizontal_alignment = align
    l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    l.clip_text = true
    l.add_theme_font_size_override("font_size", size_px)
    l.add_theme_color_override("font_color", color)
    l.mouse_filter = Control.MOUSE_FILTER_IGNORE
    if bold:
        l.add_theme_color_override("font_shadow_color",Color(0,0,0,0.35))
        l.add_theme_constant_override("shadow_offset_x",1)
        l.add_theme_constant_override("shadow_offset_y",1)
    parent.add_child(l)
    return l

func _rich(parent: Node, value: String, rect: Rect2, size_px: int, color: Color) -> RichTextLabel:
    var r: RichTextLabel = RichTextLabel.new()
    r.text = value
    r.position = rect.position
    r.size = rect.size
    r.fit_content = false
    r.scroll_active = false
    r.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    r.add_theme_font_size_override("normal_font_size", size_px)
    r.add_theme_color_override("default_color", color)
    r.mouse_filter = Control.MOUSE_FILTER_IGNORE
    parent.add_child(r)
    return r

func _button(parent: Node, rect: Rect2, value: String, accent: Color, strong: bool) -> Button:
    var b: Button = Button.new()
    b.position = rect.position
    b.size = Vector2(rect.size.x, MobilePlatform.recommended_touch_height(rect.size.y))
    b.text = value
    b.flat = true
    b.focus_mode = Control.FOCUS_ALL
    b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
    b.add_theme_font_size_override("font_size",14 if strong else 11)
    b.add_theme_color_override("font_color",Color("edf3f8"))
    var s: StyleBoxFlat = StyleBoxFlat.new()
    s.bg_color = Color(0.012,0.030,0.050,0.52)
    s.border_color = Color(accent.r,accent.g,accent.b,0.50)
    s.set_border_width_all(1)
    s.set_corner_radius_all(10)
    var h: StyleBoxFlat = s.duplicate() as StyleBoxFlat
    h.bg_color = Color(0.030,0.060,0.090,0.70)
    h.border_color = Color(accent.r,accent.g,accent.b,0.80)
    var d: StyleBoxFlat = s.duplicate() as StyleBoxFlat
    d.bg_color = Color(0.12,0.15,0.18,0.18)
    d.border_color = Color(0.35,0.42,0.48,0.20)
    b.add_theme_stylebox_override("normal",s)
    b.add_theme_stylebox_override("hover",h)
    b.add_theme_stylebox_override("pressed",h)
    b.add_theme_stylebox_override("focus",h)
    b.add_theme_stylebox_override("disabled",d)
    if not value.strip_edges().is_empty():
        b.tooltip_text = value.strip_edges()
    parent.add_child(b)
    b.button_down.connect(func() -> void: _play_pick(-13.0))
    return b
