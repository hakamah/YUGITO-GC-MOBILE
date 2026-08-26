from pathlib import Path
import subprocess, sys, zipfile

ROOT=Path(__file__).resolve().parents[2]
proj=(ROOT/'project.godot').read_text(encoding='utf-8')
mobile=(ROOT/'scripts/MobilePlatform.gd').read_text(encoding='utf-8')
app=(ROOT/'scripts/AppShell.gd').read_text(encoding='utf-8')
pre=(ROOT/'scripts/PreBattle.gd').read_text(encoding='utf-8')
main=(ROOT/'scripts/Main.gd').read_text(encoding='utf-8')
card=(ROOT/'scripts/MenuCard.gd').read_text(encoding='utf-8')
video=(ROOT/'scripts/HomeVideoBackground.gd').read_text(encoding='utf-8')
exp=(ROOT/'export_presets.cfg').read_text(encoding='utf-8')

checks=[]
def ck(name,cond):
    checks.append((name,bool(cond)))
    print(('[OK] ' if cond else '[FAIL] ')+name)

ck('GC Mobile project name','YUGITO GC Mobile - Prototype 47M Landscape' in proj)
ck('dedicated user dir','config/custom_user_dir_name="YUGITO_GC_Mobile"' in proj)
ck('MobilePlatform autoload','MobilePlatform="*res://scripts/MobilePlatform.gd"' in proj)
ck('project handheld sensor landscape','window/handheld/orientation=4' in proj)
ck('runtime sensor landscape','SCREEN_SENSOR_LANDSCAPE' in mobile)
ck('orientation feature guard','FEATURE_ORIENTATION' in mobile)
ck('no runtime portrait orientation','SCREEN_PORTRAIT' not in mobile and 'SCREEN_SENSOR_PORTRAIT' not in mobile)
ck('AppShell enforces landscape','MobilePlatform.enforce_landscape()' in app)
ck('PreBattle enforces landscape','MobilePlatform.enforce_landscape()' in pre)
ck('Battle enforces landscape','MobilePlatform.enforce_landscape()' in main)
ck('Android back supported','NOTIFICATION_WM_GO_BACK_REQUEST' in mobile and '_on_mobile_back_requested' in app)

ck('touch to mouse enabled','pointing/emulate_mouse_from_touch=true' in proj)
ck('mouse to touch enabled','pointing/emulate_touch_from_mouse=true' in proj)
ck('hover sound disabled on touch','if not MobilePlatform.is_touch()' in app)
ck('touch target helper','recommended_touch_height' in mobile and 'MobilePlatform.recommended_touch_height' in pre)

ck('Collection is 3 columns','collection_grid.columns = 3' in app)
ck('Deck is 3 columns','deck_grid.columns = 3' in app)
ck('Collection mobile cards enlarged','Vector2(300, 430) if MobilePlatform.is_android()' in app)
ck('Deck mobile cards enlarged','Vector2(286, 420) if MobilePlatform.is_android()' in app)
ck('Collection mobile search taller','44 if MobilePlatform.is_android() else 38' in app)
ck('role filter touch rows enlarged','36.0 if MobilePlatform.is_android() else 34.0' in app)

ck('Draft fixed at 3 columns','grid.columns = 3' in pre)
ck('Draft Android cards 240x360','Vector2(240, 360) if MobilePlatform.is_android()' in pre)
ck('Lineup Android max 3 columns','MobilePlatform.recommended_card_columns(4)' in pre)
ck('Lineup Android cards 300x430','Vector2(300, 430) if MobilePlatform.is_android()' in pre)
ck('Draft scroll horizontal disabled',pre.count('SCROLL_MODE_DISABLED') >= 2)

ck('Combat fiche finger target','32 if MobilePlatform.is_android() else 23' in main)
ck('Battle stays same 1600x900 canvas','window/size/viewport_width=1600' in proj and 'window/size/viewport_height=900' in proj)
ck('aspect keep avoids crop','window/stretch/aspect="keep"' in proj)

ck('mobile video chosen on Android','home_bg_mobile.ogv' in video and 'MobilePlatform.is_android()' in video)
ck('mobile video asset exists',(ROOT/'assets/video/home_bg_mobile.ogv').exists())
ck('desktop video retained',(ROOT/'assets/video/home_bg.ogv').exists())

for icon in [
    'yugito_gc_launcher_512.png',
    'yugito_gc_foreground_432.png',
    'yugito_gc_background_432.png'
]:
    ck('icon '+icon,(ROOT/'assets/export/android_gc'/icon).exists())

ck('Android preset exists','name="Android YUGITO GC"' in exp)
ck('new Android package','package/unique_name="com.hakamah.yugitogc"' in exp)
ck('does not overwrite old mobile','com.hakamah.yugitomobile' not in exp)
ck('APK label','package/name="YUGITO GC"' in exp)
ck('internet permission','permissions/internet=true' in exp)
ck('immersive Android','screen/immersive_mode=true' in exp)
ck('ARM64 enabled','architectures/arm64-v8a=true' in exp)
ck('ARMv7 enabled','architectures/armeabi-v7a=true' in exp)
ck('new adaptive foreground','launcher_icons/adaptive_foreground_432x432="res://assets/export/android_gc/yugito_gc_foreground_432.png"' in exp)
ck('new adaptive background','launcher_icons/adaptive_background_432x432="res://assets/export/android_gc/yugito_gc_background_432.png"' in exp)

ck('build helper Linux',(ROOT/'tools/build_android_gc.sh').exists())
ck('build helper Windows',(ROOT/'tools/build_android_gc.cmd').exists())
ck('GitHub CI fallback',(ROOT/'.github/workflows/build-yugito-gc-android.yml').exists())
ck('adaptive legacy audit',(ROOT/'legacy_reference/YUGITO_MOBILE_1.7.12_ADAPTIVE_AUDIT.txt').exists())

# ffprobe dimensions / FPS where available.
ffprobe=subprocess.run([
    'ffprobe','-v','error','-select_streams','v:0',
    '-show_entries','stream=width,height,r_frame_rate',
    '-of','default=noprint_wrappers=1',
    str(ROOT/'assets/video/home_bg_mobile.ogv')
],capture_output=True,text=True)
ck('mobile video probe succeeds',ffprobe.returncode==0)
if ffprobe.returncode==0:
    ck('mobile video 1600x900','width=1600' in ffprobe.stdout and 'height=900' in ffprobe.stdout)
    ck('mobile video 15 FPS','r_frame_rate=15/1' in ffprobe.stdout)

fails=[n for n,v in checks if not v]
print(f'\nP47M GC MOBILE LANDSCAPE: {len(checks)-len(fails)}/{len(checks)}')
if fails:
    print('FAILED:',*fails,sep='\n- ')
    sys.exit(1)
