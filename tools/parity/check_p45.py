from pathlib import Path
import sys
ROOT=Path(__file__).resolve().parents[2]
proj=(ROOT/'project.godot').read_text(encoding='utf-8')
audio=(ROOT/'scripts/AudioManager.gd').read_text(encoding='utf-8')
app=(ROOT/'scripts/AppShell.gd').read_text(encoding='utf-8')
pre=(ROOT/'scripts/PreBattle.gd').read_text(encoding='utf-8')
main=(ROOT/'scripts/Main.gd').read_text(encoding='utf-8')
checks=[]
def ck(n,c):
    checks.append((n,bool(c))); print(('[OK] ' if c else '[FAIL] ')+n)

ck('P45+ project lineage','Prototype 45 Global Audio' in proj or 'Prototype 46 Identity Profile' in proj or 'Prototype 47 Google Auth' in proj or 'Prototype 47M Landscape' in proj)
ck('AudioManager autoload','AudioManager="*res://scripts/AudioManager.gd"' in proj)
ck('Audio settings persistent path','user://yugito_audio.json' in audio)
ck('music default retained','music_percent: float = 38.0' in audio)
ck('sfx default retained','sfx_percent: float = 58.0' in audio)
ck('music setter global','func set_music_percent' in audio and '_music_player.volume_db = _music_db()' in audio)
ck('sfx setter global','func set_sfx_percent' in audio)
ck('settings load','func _load_settings' in audio and 'JSON.parse_string' in audio)
ck('settings save','func _save_settings' in audio and 'JSON.stringify' in audio)
ck('music API','func play_music' in audio and 'func stop_music' in audio)
ck('pause resume API','func pause_music' in audio and 'func resume_music' in audio)
ck('global SFX pool','SFX_POOL_SIZE: int = 12' in audio and '_sfx_pool' in audio)
ck('SFX pool recycles','_next_sfx_index' in audio and 'player.stop()' in audio)
ck('AssetCache used globally','AssetCache.audio(path)' in audio)
ck('AppShell has no local AudioStreamPlayer','AudioStreamPlayer' not in app)
ck('PreBattle has no local AudioStreamPlayer','AudioStreamPlayer' not in pre)
ck('Battle has no local AudioStreamPlayer','AudioStreamPlayer' not in main)
ck('AppShell UI SFX global','AudioManager.play_sfx("res://assets/audio/ui/pick.mp3"' in app)
ck('PreBattle pick SFX global','AudioManager.play_sfx("res://assets/audio/ui/pick.mp3",volume_db)' in pre)
ck('Battle SFX global','AudioManager.play_sfx(path,volume_db)' in main)
ck('menu music global','AudioManager.play_music("res://assets/audio/music/menu.mp3",0.0)' in app)
ck('selection music global','AudioManager.play_music("res://assets/audio/music/selection.mp3",-8.0)' in app and 'AudioManager.play_music("res://assets/audio/music/selection.mp3",-8.0)' in pre)
ck('battle music global','AudioManager.play_music("res://assets/audio/music/ingame.mp3",-6.0)' in main)
ck('options music slider reads manager','music_slider.value = AudioManager.get_music_percent()' in app)
ck('options sfx slider reads manager','sfx_slider.value = AudioManager.get_sfx_percent()' in app)
ck('options music writes manager','AudioManager.set_music_percent(music_volume_percent)' in app)
ck('options sfx writes manager','AudioManager.set_sfx_percent(sfx_volume_percent)' in app)
ck('music preview button','AudioManager.preview_music()' in app and 'play_music("res://assets/audio/music/menu.mp3",0.0,true)' in audio)
ck('sfx preview button','AudioManager.preview_sfx()' in app)
ck('P45+ AppShell lineage','PROTOTYPE 45 GLOBAL AUDIO' in app or 'PROTOTYPE 46 IDENTITY PROFILE' in app or 'PROTOTYPE 47 GOOGLE AUTH' in app or 'PROTOTYPE 47M' in app)
ck('P45+ battle lineage','PROTOTYPE 45 GLOBAL AUDIO' in main or 'PROTOTYPE 46 IDENTITY PROFILE' in main or 'PROTOTYPE 47 GOOGLE AUTH' in main or 'PROTOTYPE 47M LANDSCAPE' in main)

# No direct audio load/player allocation should remain outside manager.
for name,text in [('AppShell',app),('PreBattle',pre),('Main',main)]:
    ck(name+' no direct AssetCache.audio','AssetCache.audio(' not in text)
    ck(name+' no AudioStreamPlayer.new','AudioStreamPlayer.new' not in text)

fails=[n for n,v in checks if not v]
print(f'\nP45 GLOBAL AUDIO: {len(checks)-len(fails)}/{len(checks)}')
if fails:
    print('FAILED:',*fails,sep='\n- ')
    sys.exit(1)
