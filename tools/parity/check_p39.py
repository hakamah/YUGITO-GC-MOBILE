from pathlib import Path
import sys
ROOT=Path(__file__).resolve().parents[2]
proj=(ROOT/'project.godot').read_text(encoding='utf-8')
main=(ROOT/'scripts/Main.gd').read_text(encoding='utf-8')
card=(ROOT/'scripts/CardActor.gd').read_text(encoding='utf-8')
atm=(ROOT/'scripts/Atmosphere.gd').read_text(encoding='utf-8')
cache=(ROOT/'scripts/AssetCache.gd').read_text(encoding='utf-8')
checks=[]
def ck(n,c):
    checks.append((n,bool(c))); print(('[OK] ' if c else '[FAIL] ')+n)

ck('302 max fps supports 144 Hz','application/run/max_fps=144' in proj)
ck('302 vsync remains enabled','window/vsync/vsync_mode=1' in proj)
ck('302 atmosphere redraw capped at 60 Hz','REDRAW_STEP: float = 1.0 / 60.0' in atm)
ck('303 card drift time uses delta','drift_time += delta' in card)
ck('303 smoothing uses exponential delta response','1.0 - exp(-7.0 * delta)' in card and '1.0 - exp(-10.5 * delta)' in card)
ck('303 atmosphere animation uses delta','t += delta' in atm)
ck('304 badge signature prevents unchanged rebuild','if signature == _last_status_signature:' in card)
ck('304 status visuals signature prevents unchanged rebuild','if sig == _last_status_visual_signature:' in card)
ck('304 status polling is throttled','STATUS_POLL_INTERVAL: float = 0.16' in card)
ck('305 global texture cache exists','static var _textures: Dictionary = {}' in cache)
ck('305 global audio cache exists','static var _audio: Dictionary = {}' in cache)
ck('305 dynamic card art uses cache','AssetCache.texture(art_path)' in card)
ck('305 battle sfx use cached stream','func _cached_sfx' in main and 'AssetCache.audio(path)' in main)
ck('305 menu assets use cache','AssetCache' in (ROOT/'scripts/AppShell.gd').read_text(encoding='utf-8'))
ck('306 pooled audio players','SFX_POOL_SIZE: int = 8' in main and 'sfx_player_pool' in main)
ck('306 pooled impact FX','IMPACT_POOL_SIZE: int = 10' in main and '_acquire_impact_panel' in main)
ck('306 impact nodes released not freed','_release_impact_panel.bind(ring)' in main and '_release_impact_panel.bind(core)' in main)
ck('P39 metadata project','Prototype 39 Performance Lock' in proj)
ck('P39 metadata main','PROTOTYPE 39 PERFORMANCE LOCK' in main)
fails=[n for n,v in checks if not v]
print(f'\nP39: {len(checks)-len(fails)}/{len(checks)}')
if fails:
    print('FAILED:',*fails,sep='\n- ');sys.exit(1)
