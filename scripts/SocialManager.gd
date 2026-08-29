class_name YugitoSocialManager
extends Node

signal data_changed
signal conversation_changed(peer_id: String)
signal invite_received(invite: Dictionary)
signal transport_state_changed(connected: bool, message: String)

const SAVE_PATH := "user://yugito_social_v2.json"
const LEGACY_SAVE_PATH := "user://yugito_social_v1.json"
const INVITE_TTL_SECONDS := 300
const MAX_MESSAGES_PER_THREAD := 250
const PROTOCOL := "yugito/classic/social/v1"

var transport_connected: bool = false
var transport_message: String = "Relais social non connecté."

var friends: Dictionary = {}
var incoming_requests: Dictionary = {}
var outgoing_requests: Dictionary = {}
var conversations: Dictionary = {}
var muted: Dictionary = {}
var blocked: Dictionary = {}
var pending_invites: Array[Dictionary] = []
var selected_peer_id: String = ""
var read_state: Dictionary = {}
var typing_state: Dictionary = {}

func _ready() -> void:
    _load()

func set_transport_state(connected: bool, message: String) -> void:
    transport_connected = connected
    transport_message = message
    transport_state_changed.emit(connected, message)
    data_changed.emit()

func social_protocol() -> String:
    return PROTOCOL

func can_network() -> bool:
    return transport_connected

func total_unread() -> int:
    var total := 0
    for peer_id: Variant in conversations.keys():
        total += unread_count(str(peer_id))
    return total

func unread_count(peer_id: String) -> int:
    var last_read: int = int(read_state.get(peer_id,0))
    var count := 0
    for raw: Variant in conversations.get(peer_id,[]) as Array:
        var msg: Dictionary = raw as Dictionary
        if str(msg.get("from","")) == "peer" and int(msg.get("ts",0)) > last_read:
            count += 1
    return count

func mark_thread_read(peer_id: String) -> void:
    var thread: Array = conversations.get(peer_id,[]) as Array
    var latest := int(Time.get_unix_time_from_system())
    if not thread.is_empty():
        latest = int((thread[-1] as Dictionary).get("ts",latest))
    read_state[peer_id] = latest
    _save()
    data_changed.emit()

func last_message_preview(peer_id: String) -> String:
    var thread: Array = conversations.get(peer_id,[]) as Array
    if thread.is_empty():
        return "Aucune conversation"
    var msg: Dictionary = thread[-1] as Dictionary
    var value := ("Toi : " if str(msg.get("from","")) == "me" else "") + str(msg.get("text",""))
    return value.substr(0,41) + "…" if value.length() > 44 else value

func is_typing(peer_id: String) -> bool:
    return bool(typing_state.get(peer_id,false))

func set_typing(peer_id: String, active: bool) -> void:
    typing_state[peer_id] = active
    conversation_changed.emit(peer_id)

func friend_list() -> Array[Dictionary]:
    var result: Array[Dictionary] = []
    for key: Variant in friends.keys():
        var peer_id := str(key)
        var row: Dictionary = (friends[key] as Dictionary).duplicate(true)
        row["id"] = peer_id
        row["unread"] = unread_count(peer_id)
        row["preview"] = last_message_preview(peer_id)
        result.append(row)
    result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
        var au := int(a.get("unread",0))
        var bu := int(b.get("unread",0))
        if au != bu:
            return au > bu
        var rank := {"online":0,"in_game":1,"offline":2}
        var ar: int = int(rank.get(str(a.get("status","offline")),2))
        var br: int = int(rank.get(str(b.get("status","offline")),2))
        if ar != br:
            return ar < br
        return str(a.get("pseudo","")).to_lower() < str(b.get("pseudo","")).to_lower()
    )
    return result

func incoming_list() -> Array[Dictionary]:
    return _dict_rows(incoming_requests)

func outgoing_list() -> Array[Dictionary]:
    return _dict_rows(outgoing_requests)

func _dict_rows(source: Dictionary) -> Array[Dictionary]:
    var result: Array[Dictionary] = []
    for key: Variant in source.keys():
        var row: Dictionary = (source[key] as Dictionary).duplicate(true)
        row["id"] = str(key)
        result.append(row)
    result.sort_custom(func(a: Dictionary,b: Dictionary) -> bool:
        return str(a.get("pseudo","")).to_lower() < str(b.get("pseudo","")).to_lower()
    )
    return result

func get_friend(peer_id: String) -> Dictionary:
    return (friends.get(peer_id,{}) as Dictionary).duplicate(true)

func get_messages(peer_id: String) -> Array[Dictionary]:
    var raw: Array = conversations.get(peer_id,[]) as Array
    var result: Array[Dictionary] = []
    for item: Variant in raw:
        result.append((item as Dictionary).duplicate(true))
    return result

func is_muted(peer_id: String) -> bool:
    return bool(muted.get(peer_id,false))

func is_blocked(peer_id: String) -> bool:
    return bool(blocked.get(peer_id,false))

func request_friend_by_pseudo(pseudo: String) -> Dictionary:
    var clean := pseudo.strip_edges()
    if clean.length() < 3:
        return {"ok":false,"message":"Entre un pseudo YUGITO valide."}
    if not transport_connected:
        return {"ok":false,"message":"Le relais social YUGITO n'est pas encore connecté dans Godot."}
    return {"ok":false,"message":"Transport social prêt côté UI, en attente du bridge réseau."}

func accept_request(peer_id: String) -> Dictionary:
    if not incoming_requests.has(peer_id):
        return {"ok":false,"message":"Demande introuvable."}
    var row: Dictionary = incoming_requests[peer_id] as Dictionary
    incoming_requests.erase(peer_id)
    row["status"] = str(row.get("status","offline"))
    friends[peer_id] = row
    _save()
    data_changed.emit()
    return {"ok":true,"message":"%s est maintenant dans tes amis." % str(row.get("pseudo",peer_id))}

func refuse_request(peer_id: String) -> void:
    incoming_requests.erase(peer_id)
    _save()
    data_changed.emit()

func remove_friend(peer_id: String) -> void:
    friends.erase(peer_id)
    selected_peer_id = "" if selected_peer_id == peer_id else selected_peer_id
    _save()
    data_changed.emit()

func toggle_mute(peer_id: String) -> bool:
    var state := not bool(muted.get(peer_id,false))
    muted[peer_id] = state
    _save()
    data_changed.emit()
    return state

func toggle_block(peer_id: String) -> bool:
    var state := not bool(blocked.get(peer_id,false))
    blocked[peer_id] = state
    if state:
        muted[peer_id] = true
    _save()
    data_changed.emit()
    return state

func send_message(peer_id: String, text_value: String) -> Dictionary:
    var clean := text_value.strip_edges()
    if clean.is_empty():
        return {"ok":false,"message":"Message vide."}
    if clean.length() > 500:
        return {"ok":false,"message":"500 caractères maximum par message."}
    if is_blocked(peer_id):
        return {"ok":false,"message":"Ce joueur est bloqué."}
    if not friends.has(peer_id):
        return {"ok":false,"message":"Les messages privés sont réservés aux amis."}
    if not transport_connected:
        return {"ok":false,"message":"Le relais social YUGITO n'est pas encore connecté dans Godot."}
    return {"ok":false,"message":"Messagerie prête côté UI, en attente du bridge réseau."}

func receive_message(peer_id: String, pseudo: String, text_value: String, timestamp: int = 0) -> void:
    if is_blocked(peer_id):
        return
    if timestamp <= 0:
        timestamp = int(Time.get_unix_time_from_system())
    var thread: Array = conversations.get(peer_id,[]) as Array
    thread.append({
        "from":"peer",
        "pseudo":pseudo,
        "text":text_value,
        "ts":timestamp,
        "delivery":"received"
    })
    while thread.size() > MAX_MESSAGES_PER_THREAD:
        thread.remove_at(0)
    conversations[peer_id] = thread
    _save()
    conversation_changed.emit(peer_id)
    data_changed.emit()

func append_sent_message(peer_id: String, text_value: String, timestamp: int = 0) -> void:
    if timestamp <= 0:
        timestamp = int(Time.get_unix_time_from_system())
    var thread: Array = conversations.get(peer_id,[]) as Array
    thread.append({
        "from":"me",
        "text":text_value,
        "ts":timestamp,
        "delivery":"sent"
    })
    while thread.size() > MAX_MESSAGES_PER_THREAD:
        thread.remove_at(0)
    conversations[peer_id] = thread
    _save()
    conversation_changed.emit(peer_id)
    data_changed.emit()

func invite_private_match(peer_id: String) -> Dictionary:
    if is_blocked(peer_id):
        return {"ok":false,"message":"Ce joueur est bloqué."}
    if not friends.has(peer_id):
        return {"ok":false,"message":"Ce joueur n'est pas dans tes amis."}
    if not transport_connected:
        return {"ok":false,"message":"Le relais social YUGITO n'est pas encore connecté dans Godot."}
    return {"ok":false,"message":"Invitation privée prête côté UI, en attente du bridge réseau."}

func receive_private_invite(invite: Dictionary) -> void:
    var copy := invite.duplicate(true)
    if int(copy.get("expires_at",0)) <= 0:
        copy["expires_at"] = int(Time.get_unix_time_from_system()) + INVITE_TTL_SECONDS
    pending_invites.append(copy)
    _save()
    invite_received.emit(copy)
    data_changed.emit()

func prune_expired_invites() -> void:
    var now := int(Time.get_unix_time_from_system())
    var keep: Array[Dictionary] = []
    for raw: Variant in pending_invites:
        var inv: Dictionary = raw as Dictionary
        if int(inv.get("expires_at",0)) > now:
            keep.append(inv)
    pending_invites = keep
    _save()

func invite_seconds_left(index: int) -> int:
    if index < 0 or index >= pending_invites.size():
        return 0
    var inv: Dictionary = pending_invites[index] as Dictionary
    return maxi(0,int(inv.get("expires_at",0)) - int(Time.get_unix_time_from_system()))

func dismiss_invite(index: int) -> void:
    if index < 0 or index >= pending_invites.size():
        return
    pending_invites.remove_at(index)
    _save()
    data_changed.emit()

func set_friend_presence(peer_id: String, pseudo: String, status: String, elo: int = 100) -> void:
    var row: Dictionary = friends.get(peer_id,{}) as Dictionary
    row["pseudo"] = pseudo
    row["status"] = status
    row["elo"] = elo
    row["last_seen"] = int(Time.get_unix_time_from_system())
    friends[peer_id] = row
    _save()
    data_changed.emit()

func ingest_friend_request(peer_id: String, pseudo: String, elo: int = 100) -> void:
    if blocked.get(peer_id,false):
        return
    incoming_requests[peer_id] = {
        "pseudo":pseudo,
        "elo":elo,
        "status":"offline",
        "received_at":int(Time.get_unix_time_from_system())
    }
    _save()
    data_changed.emit()

func _save() -> void:
    var payload := {
        "version":1,
        "protocol":PROTOCOL,
        "friends":friends,
        "incoming_requests":incoming_requests,
        "outgoing_requests":outgoing_requests,
        "conversations":conversations,
        "muted":muted,
        "blocked":blocked,
        "pending_invites":pending_invites,
        "read_state":read_state
    }
    var file := FileAccess.open(SAVE_PATH,FileAccess.WRITE)
    if file:
        file.store_string(JSON.stringify(payload))

func _load() -> void:
    var path := SAVE_PATH if FileAccess.file_exists(SAVE_PATH) else LEGACY_SAVE_PATH
    if not FileAccess.file_exists(path):
        return
    var file := FileAccess.open(path,FileAccess.READ)
    if file == null:
        return
    var parsed: Variant = JSON.parse_string(file.get_as_text())
    if typeof(parsed) != TYPE_DICTIONARY:
        return
    var data: Dictionary = parsed as Dictionary
    friends = data.get("friends",{}) as Dictionary
    incoming_requests = data.get("incoming_requests",{}) as Dictionary
    outgoing_requests = data.get("outgoing_requests",{}) as Dictionary
    conversations = data.get("conversations",{}) as Dictionary
    muted = data.get("muted",{}) as Dictionary
    blocked = data.get("blocked",{}) as Dictionary
    pending_invites = data.get("pending_invites",[]) as Array
    read_state = data.get("read_state",{}) as Dictionary
    prune_expired_invites()
