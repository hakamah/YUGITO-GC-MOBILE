from pathlib import Path
import sys
ROOT=Path(__file__).resolve().parents[2]
app=(ROOT/'scripts/AppShell.gd').read_text(encoding='utf-8')
pre=(ROOT/'scripts/PreBattle.gd').read_text(encoding='utf-8')
main=(ROOT/'scripts/Main.gd').read_text(encoding='utf-8')
modal=(ROOT/'scripts/ReplacementModal.gd').read_text(encoding='utf-8')
card=(ROOT/'scripts/MenuCard.gd').read_text(encoding='utf-8')
proj=(ROOT/'project.godot').read_text(encoding='utf-8')
checks=[]
def ck(n,c):
    checks.append((n,bool(c))); print(('[OK] ' if c else '[FAIL] ')+n)

# Common app shell
ck('P42 project metadata','Prototype 42 Glass UI Unification' in proj)
ck('P42 app metadata','PROTOTYPE 42 GLASS UI UNIFICATION' in app)
ck('shared full HD video in app shell','HomeVideoBackground.new()' in app and 'app_video' in app)
ck('home reuses shared video rather than duplicate','var video_bg:' not in app[app.find('func _show_home'):app.find('func _frosted_home_button')])
ck('glass header','var header: Panel = _glass_surface' in app)
ck('glass content','content_panel = _glass_surface' in app)
ck('screen-space frost on content','_apply_screen_frost(content_panel' in app and 'hint_screen_texture' in app)
ck('glass footer','var footer_glass: Panel = _glass_surface' in app)
ck('screen headings are bright','Color("ffffff")' in app[app.find('func _screen_heading'):app.find('func _show_home')])

# Rubrics AppShell
ck('Jouer retains 3 modes','SOLO VS IA' in app and 'MULTIJOUEUR' in app and 'ENTRAÎNEMENT' in app)
ck('Jouer mode cards use shared glass panel helper','func _mode_card' in app and '_panel_in(screen_root' in app)
ck('Collection uses glass search','_style_glass_line_edit(search)' in app and 'COLLECTION' in app)
ck('Collection detail remains long-form','func _build_collection_detail' in app and 'SYNERGIES' in app)
ck('Deck uses glass search','_on_deck_search_changed' in app and app.count('_style_glass_line_edit(search)') >= 2)
ck('Deck quotas preserved','32.5★' in app and '_deck_star_count(5.0)' in app)
ck('Guide chapter buttons glass styled','bh.bg_color = Color(1,1,1,0.15)' in app and 'CHAPITRES' in app)
ck('Options sliders glass styled','_style_glass_slider(music_slider)' in app and '_style_glass_slider(sfx_slider)' in app)

# Prebattle
ck('PreBattle uses same video','const HomeVideoBackground' in pre and 'HomeVideoBackground.new()' in pre)
ck('PreBattle header glass','var header: Panel = _glass_surface' in pre)
ck('PreBattle body frosted','_apply_screen_frost(body' in pre)
ck('Shifumi still present','CHOISIS TON SIGNE' in pre and 'PIERRE' in pre and 'FEUILLE' in pre and 'CISEAUX' in pre)
ck('Draft still present','draft_owner' in pre and 'ally_draft' in pre and 'enemy_draft' in pre)
ck('Lineup still present','ally_starters' in pre and 'enemy_starters' in pre)
ck('PreBattle buttons now light glass','s.bg_color = Color(0.97,0.99,1.0,0.085)' in pre)

# Cards
ck('MenuCard glass outer frame','_style_normal.bg_color = Color(0.96, 0.985, 1.0, 0.10)' in card)
ck('MenuCard art remains crisp','STRETCH_KEEP_ASPECT_COVERED' in card)
ck('MenuCard texture cache','AssetCache.texture("res://assets/cards/%s_field.png" % card_id)' in card)

# Combat
ck('P42 battle metadata','PROTOTYPE 42 GLASS UI UNIFICATION' in main)
ck('battle uses matching static village art','battle_glass_bg.webp' in main and (ROOT/'assets/ui/battle_glass_bg.webp').exists())
ck('battle arena frosted','var arena_glass: Panel' in main and '_battle_frost_panel(arena_glass' in main)
ck('battle plan frosted','var plan_glass: Panel' in main and '_battle_frost_panel(plan_glass' in main)
ck('battle top HUD frosted','var top_glass: Panel' in main and '_battle_frost_panel(top_glass' in main)
ck('battle action buttons light glass','Color(0.98,0.99,1.0,0.075)' in main)

# Modals
ck('replacement overlay less black','dim.color = Color(0.02, 0.03, 0.05, 0.28)' in modal)
ck('replacement window glass','ws.bg_color = Color(0.96, 0.985, 1.0, 0.12)' in modal)
ck('replacement cards glass','normal.bg_color = Color(0.97, 0.99, 1.0, 0.10)' in modal)

failed=[n for n,v in checks if not v]
print(f'\nP42 VISUAL UNIFICATION: {len(checks)-len(failed)}/{len(checks)}')
if failed:
    print('FAILED:',*failed,sep='\n- ')
    sys.exit(1)
