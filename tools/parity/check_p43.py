from pathlib import Path
import sys
ROOT=Path(__file__).resolve().parents[2]
app=(ROOT/'scripts/AppShell.gd').read_text(encoding='utf-8')
pre=(ROOT/'scripts/PreBattle.gd').read_text(encoding='utf-8')
main=(ROOT/'scripts/Main.gd').read_text(encoding='utf-8')
card=(ROOT/'scripts/MenuCard.gd').read_text(encoding='utf-8')
modal=(ROOT/'scripts/ReplacementModal.gd').read_text(encoding='utf-8')
proj=(ROOT/'project.godot').read_text(encoding='utf-8')
checks=[]
def ck(n,c):
    checks.append((n,bool(c))); print(('[OK] ' if c else '[FAIL] ')+n)

# logo / exports
ck('P43 project metadata','Prototype 43 Dark Glass Readability' in proj)
ck('project icon points to new YUGITO logo','config/icon="res://assets/ui/YUGITO.png"' in proj)
ck('new in-app logo exists',(ROOT/'assets/ui/YUGITO.png').exists())
ck('menu logo replaced',(ROOT/'assets/ui/menu_yugito_logo.png').exists())
ck('Windows ICO ready',(ROOT/'assets/export/yugito.ico').exists() and (ROOT/'YUGITO.ico').exists())
ck('Android icon sizes ready',all((ROOT/f'assets/export/yugito_icon_{s}.png').exists() for s in [48,72,96,144,192,512]))

# menu deliberately untouched
home_start=app.find('func _show_home() -> void:')
home_end=app.find('func _frosted_home_button',home_start)
home=app[home_start:home_end]
ck('home still P41.2 layout','var glass_rect := Rect2(308, 150, 984, 626)' in home and 'SOLO' in home and 'MULTIJOUEUR' in home)
ck('home video architecture retained','home_overlay' in home and 'var video_bg:' not in home)

# larger cards
ck('MenuCard accepts explicit height','var requested_h: float = size_value.y if size_value.y > 0.0' in card)
ck('Collection reduced to 3 columns','collection_grid.columns = 3' in app)
ck('Collection cards enlarged','Vector2(286, 420)' in app)
ck('Deck reduced to 3 columns','deck_grid.columns = 3' in app)
ck('Deck cards enlarged','Vector2(270, 400)' in app)
ck('Draft reduced to 3 columns','grid.columns = 3' in pre)
ck('Draft cards enlarged','Vector2(228, 350)' in pre)
ck('Lineup reduced to 4 columns','grid.columns = 4' in pre)
ck('Lineup cards enlarged','Vector2(246, 374)' in pre)
ck('MenuCard stat font enlarged','Rect2(1,12,rect.size.x-2,20), 10' in card)

# dark glass readability
ck('App internal glass dark','style.bg_color = Color(0.012, 0.025, 0.043, maxf(0.36, fill_alpha))' in app)
ck('App frost darkens video','mix(c.rgb, vec3(0.012,0.026,0.045)' in app)
ck('Collection/Deck internal panels dark','glass_bg = Color(0.010, 0.024, 0.042' in app)
ck('PreBattle shell dark','st.bg_color = Color(0.010,0.024,0.042' in pre)
ck('PreBattle frost dark','mix(c.rgb, vec3(0.010,0.024,0.042)' in pre)
ck('PreBattle buttons dark','s.bg_color = Color(0.012,0.030,0.050,0.52)' in pre)
ck('Battle frost dark','mix(c.rgb, vec3(0.008,0.022,0.038)' in main)
ck('Battle action buttons dark','Color(0.010,0.028,0.048,0.48)' in main)
ck('Replacement modal dark','ws.bg_color = Color(0.008, 0.022, 0.038, 0.82)' in modal)

failed=[n for n,v in checks if not v]
print(f'\nP43 DARK GLASS / CARD SCALE: {len(checks)-len(failed)}/{len(checks)}')
if failed:
    print('FAILED:',*failed,sep='\n- ')
    sys.exit(1)
