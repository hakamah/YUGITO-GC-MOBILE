from pathlib import Path
import sys
ROOT=Path(__file__).resolve().parents[2]
app=(ROOT/'scripts/AppShell.gd').read_text(encoding='utf-8')
video=(ROOT/'scripts/HomeVideoBackground.gd').read_text(encoding='utf-8')
main=(ROOT/'scripts/Main.gd').read_text(encoding='utf-8')
ogv=ROOT/'assets/video/home_bg.ogv'
checks=[]
def ck(name, cond):
    checks.append((name,bool(cond))); print(('[OK] ' if cond else '[FAIL] ')+name)

ck('Full HD native video asset exists', ogv.exists() and ogv.stat().st_size > 5_000_000)
ck('Godot VideoStreamPlayer used', 'extends VideoStreamPlayer' in video)
ck('OGV stream loaded', 'res://assets/video/home_bg.ogv' in video)
ck('video autoplay and loops', 'autoplay = true' in video and 'loop = true' in video)
ck('video fills home viewport', 'set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)' in video and 'expand = true' in video)
ck('home uses video background', 'YugitoHomeVideoBackground' in app and 'HomeVideoBackground.new()' in app)
ck('no global dark overlay on home', 'var wash :=' not in app[app.find('func _show_home'):app.find('func _show_play')])
ck('frosted glass samples screen', 'hint_screen_texture' in app and 'SCREEN_UV' in app)
ck('glass blur uses mip LOD', 'textureLod(screen_texture, SCREEN_UV, lod)' in app)
ck('frost only local to glass', 'glass.add_child(blur_layer)' in app and 'glass.add_child(frost)' in app)
ck('labels not blurred', 'blur_layer.material = blur_mat' in app and '_label_in(home_overlay, "YUGITO"' in app)
ck('old 540x294 frame sequence removed', not (ROOT/'assets/ui/home_animated').exists())
ck('old AnimatedHomeBackground removed', not (ROOT/'scripts/AnimatedHomeBackground.gd').exists())
ck('P41.2 app metadata', 'PROTOTYPE 41.2 FULL HD VIDEO GLASS' in app)
ck('P41.2 battle metadata', 'PROTOTYPE 41.2 FULL HD VIDEO GLASS' in main)

failed=[n for n,v in checks if not v]
print(f'\nP41.2: {len(checks)-len(failed)}/{len(checks)}')
if failed:
    print('FAILED:',*failed,sep='\n- ')
    sys.exit(1)
