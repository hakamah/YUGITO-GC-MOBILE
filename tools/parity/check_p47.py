from pathlib import Path
import sys

ROOT=Path(__file__).resolve().parents[2]
proj=(ROOT/'project.godot').read_text(encoding='utf-8')
auth=(ROOT/'scripts/AuthManager.gd').read_text(encoding='utf-8')
identity=(ROOT/'scripts/IdentityManager.gd').read_text(encoding='utf-8')
app=(ROOT/'scripts/AppShell.gd').read_text(encoding='utf-8')
main=(ROOT/'scripts/Main.gd').read_text(encoding='utf-8')
contract=(ROOT/'legacy_reference/YUGITO_AUTH_SERVER_1.4.10_CONTRACT.txt').read_text(encoding='utf-8')

checks=[]
def ck(name,cond):
    checks.append((name,bool(cond)))
    print(('[OK] ' if cond else '[FAIL] ')+name)

# Metadata / Autoload
ck('P47+ project lineage','Prototype 47 Google Auth' in proj or 'Prototype 47M Landscape' in proj)
ck('P47 AuthManager autoload','AuthManager="*res://scripts/AuthManager.gd"' in proj)
ck('P47+ AppShell lineage','PROTOTYPE 47 GOOGLE AUTH' in app or 'PROTOTYPE 47M' in app)
ck('P47+ battle lineage','PROTOTYPE 47 GOOGLE AUTH' in main or 'PROTOTYPE 47M LANDSCAPE' in main)

# Exact production server contract
ck('production base URL','https://yugito-auth-server.onrender.com' in auth)
ck('server contract snapshot','YUGITO Auth Server 1.4.10' in contract)
for route in [
    '/api/device/start',
    '/api/device/status',
    '/api/account/me',
    '/api/account/claim-pseudo',
    '/api/account/sync-elo',
    '/api/logout',
    '/health',
]:
    ck('route '+route, route in auth and route in contract)

# Real Device Flow
ck('real HTTPRequest usage','HTTPRequest.new()' in auth and '.request(' in auth)
ck('device start is POST','"device_start"' in auth and 'HTTPClient.METHOD_POST' in auth)
ck('platform sent to server','{"platform": _platform_name()}' in auth)
ck('browser opened from verification URL','OS.shell_open(url)' in auth)
ck('poll timer exists','_poll_timer' in auth and '_poll_device_status' in auth)
ck('server polling interval honored','_poll_timer.wait_time = interval' in auth)
ck('device expiry handled','_device_expires_at' in auth and 'connexion Google a expiré' in auth)
ck('status pending handled','status == "pending"' in auth)
ck('status authenticated handled','status != "authenticated"' in auth and '_complete_auth(token, account)' in auth)

# New account pseudo flow
ck('pseudo required state','IdentityManager.require_pseudo(account)' in auth)
ck('claim pseudo request','/api/account/claim-pseudo' in auth and 'func claim_pseudo' in auth)
ck('recovery payload supported','body["recovery"]' in auth)
ck('pseudo UI exists','func _draw_pseudo_claim' in app and 'VALIDER MON PSEUDO' in app)
ck('pseudo UI calls real auth','AuthManager.claim_pseudo' in app)
ck('server exact edge rule','clean.begins_with("-")' in identity and 'clean.ends_with("_")' in identity)

# Session restore / security
ck('session persisted separately','user://yugito_auth_session.bin' in auth)
ck('session file encrypted','FileAccess.open_encrypted_with_pass' in auth)
ck('device-bound password uses unique id','OS.get_unique_id()' in auth)
ck('session token never in public profile cache','session_token' not in identity)
ck('session restore calls account me','func validate_saved_session' in auth and '/api/account/me' in auth)
ck('invalid 401 clears session','kind == "session_me" and response_code == 401' in auth and '_invalidate_local_session' in auth)
ck('network failure keeps offline profile','IdentityManager.mark_server_unavailable' in auth)
ck('logout clears local session','func logout()' in auth and '_clear_session_file()' in auth)
ck('logout calls server','/api/logout' in auth)

# Cross-device/profile recovery
ck('same account preserves ranked profile','incoming_id == previous_id' in auth)
ck('recovered account preserves ranked profile','incoming_id == recovery_id' in auth)
ck('different account reset protection','if not same_account and ranked_profile.is_empty()' in identity)
ck('server account applied to IdentityManager','IdentityManager.apply_server_account' in auth)
ck('dynamic header still connected','profile_header_status_label.text = "ELO %d' in app)

# Future ELO bridge
ck('sync ELO API exposed','func sync_ranked_profile()' in auth)
ck('sync sends profile payload','IdentityManager.server_profile_payload()' in auth)
ck('rotated session accepted from sync','data.get("session_token", session_token)' in auth)

# Account UI states
ck('real connect button','SE CONNECTER AVEC GOOGLE' in app and 'AuthManager.begin_google_login()' in app)
ck('connecting screen','func _draw_connecting_account' in app and 'RÉOUVRIR GOOGLE' in app)
ck('cancel auth UI','AuthManager.cancel_google_login' in app)
ck('connected screen','func _draw_connected_account' in app)
ck('verify saved session UI','AuthManager.validate_saved_session' in app)
ck('logout UI','DÉCONNECTER' in app and 'AuthManager.logout()' in app)
ck('old placeholder removed','_google_auth_placeholder' not in app)

# No embedded Google secrets
for secret in ['GOOGLE_CLIENT_SECRET','client_secret','AIza']:
    ck('no embedded secret token '+secret, secret not in auth and secret not in app)

fails=[n for n,v in checks if not v]
print(f'\nP47 GOOGLE AUTH: {len(checks)-len(fails)}/{len(checks)}')
if fails:
    print('FAILED:',*fails,sep='\n- ')
    sys.exit(1)
