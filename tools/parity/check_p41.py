from pathlib import Path
import sys
ROOT=Path(__file__).resolve().parents[2]
app=(ROOT/'scripts/AppShell.gd').read_text(encoding='utf-8')
main=(ROOT/'scripts/Main.gd').read_text(encoding='utf-8')
pre=(ROOT/'scripts/PreBattle.gd').read_text(encoding='utf-8')
anim=(ROOT/'scripts/AnimatedHomeBackground.gd').read_text(encoding='utf-8')
frames=sorted((ROOT/'assets/ui/home_animated').glob('frame_*.webp'))
checks=[]
def ck(n,c):
    checks.append((n,bool(c))); print(('[OK] ' if c else '[FAIL] ')+n)
ck('33 animated home frames',len(frames)==33)
ck('10 FPS animation','FRAME_TIME: float = 0.10' in anim)
ck('delta based GIF sequence','_accumulator += delta' in anim)
ck('asset cache used for GIF frames','AssetCache.texture(path)' in anim)
ck('home background fills viewport','set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)' in app)
ck('central glass approximately 70 percent','Rect2(238, 112, 1124, 676)' in app)
ck('glass alpha transparent','style.bg_color = Color(0.025, 0.050, 0.080, 0.70)' in app)
ck('glass highlight and vignette','vignette_shader.code' in app and 'shine.color' in app)
ck('modern featured menu cards','func _modern_home_card' in app and 'SOLO VS IA' in app and 'MULTIJOUEUR' in app)
ck('collection/deck/guide/options exposed','COLLECTION' in app and 'CRÉE TON DECK' in app and 'GUIDE' in app and 'PARAMÈTRES' in app)
ck('modern home mouse/focus','btn.focus_mode = Control.FOCUS_ALL' in app)
ck('glass DA extended battle','BUILD 41 • MODERN GLASS' in main)
ck('glass DA extended prebattle','s.bg_color = Color(0.026,0.054,0.084,0.74)' in pre)
ck('P41 metadata app','PROTOTYPE 41 MODERN GLASS HOME' in app)
ck('P41 metadata main','PROTOTYPE 41 MODERN GLASS HOME' in main)
fails=[n for n,v in checks if not v]
print(f'\nP41: {len(checks)-len(fails)}/{len(checks)}')
if fails:
    print('FAILED:',*fails,sep='\n- ');sys.exit(1)
