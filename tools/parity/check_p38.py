from pathlib import Path
import sys
ROOT=Path(__file__).resolve().parents[2]
proj=(ROOT/'project.godot').read_text(encoding='utf-8')
app=(ROOT/'scripts/AppShell.gd').read_text(encoding='utf-8')
main=(ROOT/'scripts/Main.gd').read_text(encoding='utf-8')
pre=(ROOT/'scripts/PreBattle.gd').read_text(encoding='utf-8')
card=(ROOT/'scripts/MenuCard.gd').read_text(encoding='utf-8')
modal=(ROOT/'scripts/ReplacementModal.gd').read_text(encoding='utf-8')
checks=[]
def ck(n,c):
 checks.append((n,bool(c))); print(('[OK] ' if c else '[FAIL] ')+n)

# 295 tooltips
ck('295 menu buttons get automatic tooltips','btn.tooltip_text = text_value.strip_edges()' in app)
ck('295 card tooltips contain identity and special','tooltip_text = "%s • %s★ • %s' in card and 'Spéciale : %s' in card)
ck('295 battle action buttons get tooltips','btn.tooltip_text = text_value.strip_edges()' in main)
ck('295 prebattle buttons get tooltips','b.tooltip_text = value.strip_edges()' in pre)
ck('295 replacement choices get tooltips','Choisir %s comme remplaçant' in modal)

# 296 feedback hover/click
ck('296 click sound cached','ui_click_stream' in app and 'btn.button_down.connect(_play_ui_sound)' in app)
ck('296 hover feedback exists','func _play_ui_hover()' in app and 'btn.mouse_entered.connect(_play_ui_hover)' in app)
ck('296 hover throttled','ui_hover_cooldown_until' in app and 'now + 90' in app)
ck('296 no repeated UI load in click handler','func _play_ui_sound()' in app and 'var stream: AudioStream = ui_click_stream' in app)

# 297-298 modals
ck('297 replacement root blocks pointer','_root.mouse_filter = Control.MOUSE_FILTER_STOP' in modal)
ck('297 replacement modal elevated','_root.z_index = 20000' in modal)
ck('297 prebattle modal veil blocks pointer','veil.mouse_filter = Control.MOUSE_FILTER_STOP' in pre)
ck('297 prebattle modal elevated','veil.z_index = 20000' in pre)
ck('298 modal content rendered above underlying UI', modal.find('_root.z_index = 20000') >= 0 and pre.find('veil.z_index = 20000') >= 0)

# 299 focus
ck('299 AppShell buttons keyboard/gamepad focus','btn.focus_mode = Control.FOCUS_ALL' in app)
ck('299 battle buttons keyboard/gamepad focus','btn.focus_mode = Control.FOCUS_ALL' in main)
ck('299 prebattle buttons keyboard/gamepad focus','b.focus_mode = Control.FOCUS_ALL' in pre)
ck('299 menu cards keyboard/gamepad focus','focus_mode = Control.FOCUS_ALL' in card)
ck('299 replacement first choice grabs focus','call_deferred("grab_focus")' in modal)

# 300-301 responsive safe canvas
ck('300 base virtual canvas 1600x900','window/size/viewport_width=1600' in proj and 'window/size/viewport_height=900' in proj)
ck('300 uniform aspect safe scaling','window/stretch/aspect="keep"' in proj)
ck('300 low-resolution minimum declared','window/size/min_width=960' in proj and 'window/size/min_height=540' in proj)
ck('301 canvas_items stretch retained','window/stretch/mode="canvas_items"' in proj)
ck('301 responsive config protects fixed-coordinate UI','window/stretch/aspect="keep"' in proj and 'window/stretch/mode="canvas_items"' in proj)
ck('P38 metadata project','Prototype 38 Ergonomy Responsive Lock' in proj)
ck('P38 metadata AppShell','PROTOTYPE 38 ERGONOMY RESPONSIVE LOCK' in app)
ck('P38 metadata Main','PROTOTYPE 38 ERGONOMY RESPONSIVE LOCK' in main)

fails=[n for n,v in checks if not v]
print(f'\nP38: {len(checks)-len(fails)}/{len(checks)}')
if fails:
 print('FAILED:',*fails,sep='\n- ');sys.exit(1)
