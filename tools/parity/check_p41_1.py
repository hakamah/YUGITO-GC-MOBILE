from pathlib import Path
import sys
ROOT=Path(__file__).resolve().parents[2]
app=(ROOT/'scripts/AppShell.gd').read_text(encoding='utf-8')
anim=(ROOT/'scripts/AnimatedHomeBackground.gd').read_text(encoding='utf-8')
frames=list((ROOT/'assets/ui/home_animated').glob('frame_*.webp'))
checks=[]
def ck(n,c):
    checks.append((n,bool(c))); print(('[OK] ' if c else '[FAIL] ')+n)

ck('GIF remains 33 frames',len(frames)==33)
ck('background has no global dark wash','var wash :=' not in app and 'flat_bg' not in app[app.find('func _show_home'):app.find('func _show_play')])
ck('logo outside glass','_logo_in(home_overlay, Vector2(588, 42), 66)' in app)
ck('frosted panel centered','Rect2(308, 150, 984, 626)' in app)
ck('glass is bright transparent','glass_style.bg_color = Color(0.90, 0.95, 1.00, 0.09)' in app)
ck('blurred duplicate background exists','var blur_bg: YugitoAnimatedHomeBackground' in app)
ck('blur shader uses multi sample','TEXTURE_PIXEL_SIZE * blur_px' in app and 'texture(TEXTURE, UV + vec2(px.x,0.0))' in app)
ck('blur duplicate aligned to screen','blur_bg.position = -glass_rect.position' in app and 'blur_bg.size = Vector2(1600,900)' in app)
ck('blur duplicate does not auto fill parent','blur_bg.use_full_rect = false' in app and 'var use_full_rect: bool = true' in anim)
ck('frost veil is light not dark','frost.color = Color(0.92,0.97,1.0,0.055)' in app)
ck('two-column simple menu','SOLO' in app and 'MULTIJOUEUR' in app and 'CRÉER UN DECK' in app)
ck('bottom Discord Audio Quitter','DISCORD' in app and 'AUDIO' in app and 'QUITTER' in app)
ck('button text remains crisp','_label_in(btn, title' in app and '_label_in(btn, subtitle' in app)
ck('button glass alpha light','normal.bg_color = Color(0.95,0.98,1.0,0.075)' in app)
ck('hover brightens glass','hover.bg_color = Color(1.0,1.0,1.0,0.14)' in app)
ck('P41.1 metadata','PROTOTYPE 41.1 TRUE FROSTED GLASS' in app)

failed=[n for n,v in checks if not v]
print(f'\nP41.1: {len(checks)-len(failed)}/{len(checks)}')
if failed:
    print('FAILED:',*failed,sep='\n- ')
    raise SystemExit(1)
