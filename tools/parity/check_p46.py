from pathlib import Path
import sys

ROOT=Path(__file__).resolve().parents[2]
proj=(ROOT/'project.godot').read_text(encoding='utf-8')
identity=(ROOT/'scripts/IdentityManager.gd').read_text(encoding='utf-8')
app=(ROOT/'scripts/AppShell.gd').read_text(encoding='utf-8')
main=(ROOT/'scripts/Main.gd').read_text(encoding='utf-8')
pc=(ROOT/'legacy_reference/app_PC_latest.py').read_text(encoding='utf-8',errors='ignore')

checks=[]
def ck(name,cond):
    checks.append((name,bool(cond)))
    print(('[OK] ' if cond else '[FAIL] ')+name)

# Project / manager
ck('P46+ project lineage','Prototype 46 Identity Profile' in proj or 'Prototype 47 Google Auth' in proj or 'Prototype 47M Landscape' in proj)
ck('IdentityManager autoload','IdentityManager="*res://scripts/IdentityManager.gd"' in proj)
ck('profile cache path','user://yugito_profile_cache.json' in identity)
ck('profile cache contains no session token','session_token' not in identity and '"token"' not in identity)
ck('default ELO matches PC','DEFAULT_ELO: int = 100' in identity)
ck('default player name matches PC fallback','return clean if not clean.is_empty() else "Joueur"' in identity)

# PC profile schema
for field in ['elo','ranked_matches','wins','losses','best_elo','winrate']:
    ck('Identity profile field '+field, f'"{field}"' in identity)
    ck('PC reference profile field '+field, field in pc)
ck('winrate calculation','float(wins) * 100.0' in identity and 'ranked_matches' in identity)
ck('best ELO tracks maximum','best_elo = maxi(best_elo,elo)' in identity)
ck('ranked result updater','func register_ranked_result' in identity)

# Auth state machine, ready for P47
for state in ['google_required','connecting','pseudo_required','connected','offline_cache','error']:
    ck('auth state '+state, state in identity)
ck('server account apply API','func apply_server_account(account: Dictionary' in identity)
ck('server profile apply API','func apply_ranked_profile' in identity)
ck('public multiplayer identity payload','func public_identity_payload' in identity and '"account_id":account_id' in identity)
ck('server ranked payload','func server_profile_payload' in identity)
ck('pseudo validator exists','func validate_pseudo' in identity)
ck('pseudo 3 to 20 rule','clean.length() < 3 or clean.length() > 20' in identity)
ck('pseudo allowed character rule','lettres, chiffres, espaces, - et _' in identity)
ck('PC UI documents same pseudo rule','3 à 20 caractères' in pc and 'lettres, chiffres, espaces, - et _' in pc)

# AppShell profile UI
ck('P46+ AppShell lineage','PROTOTYPE 46 IDENTITY PROFILE' in app or 'PROTOTYPE 47 GOOGLE AUTH' in app or 'PROTOTYPE 47M' in app)
ck('header identity dynamic','IdentityManager.display_name().to_upper()' in app and 'profile_header_name_label' in app)
ck('header ELO dynamic','profile_header_status_label.text = "ELO %d' in app)
ck('header profile clickable','profile_hit.pressed.connect(_show_profile)' in app)
ck('profile screen exists','func _show_profile()' in app and 'PROFIL SHINOBI' in app)
ck('profile ranked matches','PARTIES CLASSÉES' in app)
ck('profile wins losses','VICTOIRES / DÉFAITES' in app)
ck('profile winrate','TAUX DE VICTOIRE' in app)
ck('profile best ELO','MEILLEUR ELO' in app)
ck('account screen exists','func _show_identity_account()' in app and 'COMPTE YUGITO • GOOGLE' in app)
ck('PC/mobile identity message','même identité PC et mobile' in app.lower() or 'windows et android' in app.lower())
ck('Google CTA ready','SE CONNECTER AVEC GOOGLE' in app)
ck('Google auth boundary implemented','AuthManager.begin_google_login()' in app)
ck('profile reacts to manager signal','IdentityManager.profile_changed.connect(_on_identity_profile_changed)' in app)

# Battle identity
ck('P46+ battle lineage','PROTOTYPE 46 IDENTITY PROFILE' in main or 'PROTOTYPE 47 GOOGLE AUTH' in main or 'PROTOTYPE 47M LANDSCAPE' in main)
ck('battle turn title dynamic identity','IdentityManager.display_name().to_upper()' in main)
ck('battle status bar dynamic identity','_status_bar(Rect2(10, 848, 1280, 40), IdentityManager.display_name().to_upper()' in main)
ck('end duel summary dynamic identity','IdentityManager.display_name().to_upper(),ally_player_hp' in main)
ck('hardcoded HAKAMAH removed from AppShell','HAKAMAH' not in app)
ck('hardcoded HAKAMAH removed from Battle','HAKAMAH' not in main)

# Security / cache
ck('cache only non-secret identity fields','"account_id":account_id' in identity and '"email":email' in identity and '"elo":elo' in identity)
ck('clear cache API','func clear_cached_identity' in identity)
ck('safe user path globalize','ProjectSettings.globalize_path(PROFILE_CACHE_PATH)' in identity)
ck('offline cached profile state','AUTH_OFFLINE_CACHE' in identity and 'profil local' in identity.lower())

fails=[n for n,v in checks if not v]
print(f'\nP46 IDENTITY PROFILE: {len(checks)-len(fails)}/{len(checks)}')
if fails:
    print('FAILED:',*fails,sep='\n- ')
    sys.exit(1)
