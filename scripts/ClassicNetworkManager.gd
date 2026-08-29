extends Node

signal transport_changed(state: String, message: String)
signal rooms_changed
signal room_changed
signal event_received(event: Dictionary)

const BROKER := "wss://broker.emqx.io:8084/mqtt"
const APP_KEY := "YUGITO-V39-MQTT-RELAY-PROTOCOL-2026"
const NS := "yugito/v39-1/8f6f4c1d2e9b"
const LOBBY := NS + "/lobby"
const ROOM := NS + "/room"
const PROTOCOL := 3

var ws: WebSocketPeer = null
var transport_state: String = "offline"
var transport_message: String = ""
var mqtt_connected: bool = false
var _ws_was_open: bool = false
var _client_id: String = ""
var _packet_id: int = 1
var _subscriptions: Dictionary = {}
var _reconnect_at_ms: int = 0
var _last_ping_ms: int = 0

var display_name: String = "Ninja"
var elo: int = 100
var rooms_map: Dictionary = {}

var role: String = ""
var player: int = 0
var room_id: String = ""
var channel: String = ""
var room_topic: String = ""
var room_name: String = ""
var peer_name: String = ""
var peer_elo: int = 100
var connected: bool = false
var match_type: String = "classic"
var private_room: bool = false
var session: String = ""
var host_session: String = ""
var guest_session: String = ""
var chat: Array[Dictionary] = []

var ranked_searching: bool = false
var ranked_search_started_ms: int = 0
var _last_announce_ms: int = 0
var _last_cleanup_ms: int = 0
var _last_heartbeat_ms: int = 0

func _ready() -> void:
    process_mode = Node.PROCESS_MODE_ALWAYS
    _client_id = "yugito-godot-" + _random_hex(8)
    start()

func configure(name_value: String, elo_value: int) -> void:
    display_name = name_value.strip_edges().left(20)
    if display_name.is_empty():
        display_name = "Ninja"
    elo = maxi(0,elo_value)

func start() -> void:
    if ws != null and ws.get_ready_state() in [WebSocketPeer.STATE_CONNECTING,WebSocketPeer.STATE_OPEN]:
        return
    _connect_ws()

func stop() -> void:
    ranked_searching = false
    leave()
    if ws != null:
        ws.close()
    ws = null
    mqtt_connected = false
    _set_transport("offline","")

func _process(_delta: float) -> void:
    var now := Time.get_ticks_msec()

    if ws != null:
        ws.poll()
        var ready := ws.get_ready_state()
        if ready == WebSocketPeer.STATE_OPEN:
            if not _ws_was_open:
                _ws_was_open = true
                _mqtt_connect_packet()
            while ws.get_available_packet_count() > 0:
                _mqtt_receive(ws.get_packet())
        elif ready == WebSocketPeer.STATE_CLOSED:
            if _ws_was_open or mqtt_connected:
                _ws_was_open = false
                mqtt_connected = false
                _set_transport("waiting","Connexion relais perdue")
            if _reconnect_at_ms <= 0:
                _reconnect_at_ms = now + 1800

    if _reconnect_at_ms > 0 and now >= _reconnect_at_ms:
        _reconnect_at_ms = 0
        _connect_ws()

    if mqtt_connected and now - _last_ping_ms >= 15000:
        _last_ping_ms = now
        _ws_send(_mqtt_packet(0xC0,PackedByteArray()))

    if now - _last_cleanup_ms >= 2200:
        _last_cleanup_ms = now
        _cleanup_rooms()
        rooms_changed.emit()

    if role == "host" and not connected and not private_room and mqtt_connected and now - _last_announce_ms >= 8000:
        announce()

    if connected and now - _last_heartbeat_ms >= 2000:
        _last_heartbeat_ms = now
        send({"type":"mobile_ping"})

    if ranked_searching:
        _ranked_tick(now)

func _connect_ws() -> void:
    ws = WebSocketPeer.new()
    ws.supported_protocols = PackedStringArray(["mqtt"])
    _ws_was_open = false
    mqtt_connected = false
    _set_transport("connecting","")
    var err := ws.connect_to_url(BROKER,TLSOptions.client())
    if err != OK:
        _set_transport("waiting","Relais Internet indisponible")
        _reconnect_at_ms = Time.get_ticks_msec() + 1800

func _set_transport(state_value: String, message: String) -> void:
    transport_state = state_value
    transport_message = message
    transport_changed.emit(state_value,message)

func _mqtt_connect_packet() -> void:
    var body := PackedByteArray()
    body.append_array(_mqtt_string("MQTT"))
    body.append(4)
    body.append(2)
    body.append_array(_u16(30))
    body.append_array(_mqtt_string(_client_id))
    _ws_send(_mqtt_packet(0x10,body))

func _ws_send(bytes: PackedByteArray) -> bool:
    if ws == null or ws.get_ready_state() != WebSocketPeer.STATE_OPEN:
        return false
    return ws.send(bytes) == OK

func _mqtt_packet(first: int, body: PackedByteArray) -> PackedByteArray:
    var out := PackedByteArray([first & 0xFF])
    out.append_array(_remaining_length(body.size()))
    out.append_array(body)
    return out

func _remaining_length(value: int) -> PackedByteArray:
    var n := value
    var out := PackedByteArray()
    while true:
        var digit := n % 128
        n = n / 128
        if n > 0:
            digit |= 128
        out.append(digit)
        if n <= 0:
            break
    return out

func _u16(value: int) -> PackedByteArray:
    return PackedByteArray([(value >> 8) & 255,value & 255])

func _mqtt_string(value: String) -> PackedByteArray:
    var b := value.to_utf8_buffer()
    var out := _u16(b.size())
    out.append_array(b)
    return out

func _next_packet_id() -> int:
    var current := _packet_id
    _packet_id += 1
    if _packet_id > 65535:
        _packet_id = 1
    return current

func subscribe(topic: String, qos: int = 1) -> void:
    _subscriptions[topic] = 1 if qos > 0 else 0
    if mqtt_connected:
        _mqtt_subscribe_now(topic,qos)

func _mqtt_subscribe_now(topic: String, qos: int = 1) -> void:
    var body := _u16(_next_packet_id())
    body.append_array(_mqtt_string(topic))
    body.append(1 if qos > 0 else 0)
    _ws_send(_mqtt_packet(0x82,body))

func publish(topic: String, payload: PackedByteArray, retain: bool = false, qos: int = 1) -> bool:
    if not mqtt_connected:
        return false
    var first := 0x30 | (1 if retain else 0)
    var body := _mqtt_string(topic)
    if qos > 0:
        first |= 2
        body.append_array(_u16(_next_packet_id()))
    body.append_array(payload)
    return _ws_send(_mqtt_packet(first,body))

func publish_text(topic: String, payload: String, retain: bool = false, qos: int = 1) -> bool:
    return publish(topic,payload.to_utf8_buffer(),retain,qos)

func _mqtt_receive(packet: PackedByteArray) -> void:
    var pos := 0
    while pos < packet.size():
        var first := int(packet[pos]); pos += 1
        var multiplier := 1
        var remaining := 0
        while pos < packet.size():
            var digit := int(packet[pos]); pos += 1
            remaining += (digit & 127) * multiplier
            multiplier *= 128
            if (digit & 128) == 0:
                break
        if pos + remaining > packet.size():
            return
        var body := packet.slice(pos,pos+remaining)
        pos += remaining
        _mqtt_handle(first,body)

func _mqtt_handle(first: int, body: PackedByteArray) -> void:
    var packet_type := first >> 4
    if packet_type == 2:
        if body.size() >= 2 and int(body[1]) == 0:
            mqtt_connected = true
            _last_ping_ms = Time.get_ticks_msec()
            for topic: Variant in _subscriptions.keys():
                _mqtt_subscribe_now(str(topic),int(_subscriptions[topic]))
            subscribe(LOBBY + "/+",1)
            if not room_topic.is_empty():
                subscribe(room_topic,1)
            _set_transport("connected","")
            if role == "host" and not connected and not private_room:
                announce()
            elif role == "client" and not connected and not room_topic.is_empty():
                _room_send({"kind":"join_request","display_name":display_name,"platform":"android"})
        return

    if packet_type != 3 or body.size() < 2:
        return

    var topic_len := (int(body[0]) << 8) | int(body[1])
    var p := 2
    if p + topic_len > body.size():
        return
    var topic := body.slice(p,p+topic_len).get_string_from_utf8(); p += topic_len
    var qos := (first >> 1) & 3
    var packet_id := 0
    if qos > 0:
        if p + 2 > body.size():
            return
        packet_id = (int(body[p]) << 8) | int(body[p+1]); p += 2
    var payload := body.slice(p,body.size())
    if qos == 1:
        _ws_send(_mqtt_packet(0x40,_u16(packet_id)))
    _on_mqtt_message(topic,payload)

func _on_mqtt_message(topic: String, bytes: PackedByteArray) -> void:
    if topic.begins_with(LOBBY + "/"):
        var rid := topic.substr((LOBBY + "/").length())
        if bytes.is_empty():
            rooms_map.erase(rid)
            rooms_changed.emit()
            return
        var parsed := JSON.parse_string(bytes.get_string_from_utf8())
        if typeof(parsed) != TYPE_DICTIONARY:
            return
        var msg: Dictionary = parsed as Dictionary
        if not _valid(msg) or str(msg.get("kind","")) != "room_announce" or int(msg.get("protocol",0)) != PROTOCOL:
            return
        var room_key := str(msg.get("room_id",""))
        if room_key.is_empty():
            return
        rooms_map[room_key] = msg
        _cleanup_rooms()
        rooms_changed.emit()
        return

    if not room_topic.is_empty() and topic == room_topic and not bytes.is_empty():
        var parsed := JSON.parse_string(bytes.get_string_from_utf8())
        if typeof(parsed) != TYPE_DICTIONARY:
            return
        var msg: Dictionary = parsed as Dictionary
        if not _valid(msg) or int(msg.get("protocol",0)) != PROTOCOL or str(msg.get("room_id","")) != room_id:
            return
        _room_message(msg)

func _cleanup_rooms() -> void:
    var now := int(Time.get_unix_time_from_system())
    var remove_ids: Array[String] = []
    for key: Variant in rooms_map.keys():
        var room: Dictionary = rooms_map[key] as Dictionary
        if now - int(room.get("ts",0)) > 28:
            remove_ids.append(str(key))
    for key: String in remove_ids:
        rooms_map.erase(key)

func rooms(type_filter: String = "", pc_only: bool = true) -> Array[Dictionary]:
    _cleanup_rooms()
    var result: Array[Dictionary] = []
    for raw: Variant in rooms_map.values():
        var room: Dictionary = raw as Dictionary
        if str(room.get("status","")) != "waiting" or int(room.get("players",1)) >= 2:
            continue
        if not type_filter.is_empty() and str(room.get("match_type","classic")) != type_filter:
            continue
        if pc_only and str(room.get("platform","pc")) == "android":
            continue
        result.append(room.duplicate(true))
    result.sort_custom(func(a: Dictionary,b: Dictionary) -> bool:
        return str(a.get("name","")).to_lower() < str(b.get("name","")).to_lower()
    )
    return result

func host(type_value: String = "classic", private_value: bool = false) -> String:
    leave()
    session = _random_hex(12)
    role = "host"
    player = 1
    room_id = "YG-" + _random_code(6)
    channel = _random_hex(24)
    room_topic = ROOM + "/" + channel
    room_name = ("Classé " if type_value == "ranked" else "Partie ") + display_name
    match_type = type_value
    private_room = private_value
    subscribe(room_topic,1)
    _last_announce_ms = 0
    if not private_room:
        announce()
    room_changed.emit()
    return room_id

func announce() -> void:
    if room_id.is_empty() or channel.is_empty() or not mqtt_connected:
        return
    _last_announce_ms = Time.get_ticks_msec()
    _pub(LOBBY + "/" + room_id,{
        "kind":"room_announce","protocol":PROTOCOL,"room_id":room_id,
        "name":room_name,"host_name":display_name,"players":2 if connected else 1,
        "max_players":2,"status":"full" if connected else "waiting","channel":channel,
        "match_type":match_type,"elo":elo,"platform":"android",
        "ts":int(Time.get_unix_time_from_system())
    },true)

func join_room(room: Dictionary) -> Dictionary:
    leave()
    session = _random_hex(12)
    role = "client"
    player = 2
    room_id = str(room.get("room_id",""))
    channel = str(room.get("channel",room.get("_channel","")))
    room_topic = ROOM + "/" + channel
    room_name = str(room.get("name","Partie YUGITO"))
    peer_name = str(room.get("host_name","Adversaire")).left(20)
    peer_elo = int(room.get("elo",100))
    match_type = str(room.get("match_type","classic"))
    if room_id.is_empty() or channel.is_empty():
        return {"ok":false,"message":"Salon invalide."}
    subscribe(room_topic,1)
    _room_send({"kind":"join_request","display_name":display_name,"platform":"android"})
    room_changed.emit()
    return {"ok":true}

func _room_send(obj: Dictionary) -> bool:
    if room_topic.is_empty():
        return false
    var payload := obj.duplicate(true)
    payload["protocol"] = PROTOCOL
    payload["room_id"] = room_id
    payload["from_session"] = session
    return _pub(room_topic,payload,false)

func _room_message(msg: Dictionary) -> void:
    var source := str(msg.get("from_session",""))
    if source.is_empty() or source == session:
        return
    var kind := str(msg.get("kind",""))

    if kind == "join_request" and role == "host":
        if connected:
            _room_send({"kind":"join_reject","target":source,"reason":"Salon complet"})
            return
        guest_session = source
        peer_name = str(msg.get("display_name","Adversaire")).left(20)
        connected = true
        _room_send({"kind":"join_accept","target":source,"host_session":session,"host_name":display_name})
        if not private_room:
            publish(LOBBY + "/" + room_id,PackedByteArray(),true,1)
        _connected_event()
        return

    if kind == "join_accept" and role == "client" and str(msg.get("target","")) == session:
        host_session = source
        peer_name = str(msg.get("host_name",peer_name)).left(20)
        connected = true
        _connected_event()
        return

    if kind == "join_reject" and role == "client" and str(msg.get("target","")) == session:
        event_received.emit({"type":"error","message":str(msg.get("reason","Salon indisponible"))})
        return

    if kind in ["leave","room_closed"]:
        connected = false
        event_received.emit({"type":"peer_left"})
        room_changed.emit()
        if role == "host" and not private_room:
            announce()
        return

    if kind == "relay" and connected:
        if role == "host" and not guest_session.is_empty() and source != guest_session:
            return
        if role == "client" and not host_session.is_empty() and source != host_session:
            return
        var payload: Variant = msg.get("payload",{})
        if typeof(payload) == TYPE_DICTIONARY:
            var event: Dictionary = (payload as Dictionary).duplicate(true)
            event["_source"] = source
            if str(event.get("type","")) == "chat":
                chat.append({"who":str(event.get("pseudo","Adversaire")),"text":str(event.get("text",""))})
                while chat.size() > 40:
                    chat.remove_at(0)
                room_changed.emit()
            elif str(event.get("type","")) == "ranked_hello":
                peer_elo = maxi(0,int(event.get("elo",100)))
                room_changed.emit()
            event_received.emit(event)

func _connected_event() -> void:
    _last_heartbeat_ms = 0
    event_received.emit({"type":"connected","role":role,"player":player,"peer_name":peer_name})
    send({"type":"mobile_hello","mobile_version":"GC","elo":elo})
    send({"type":"ranked_hello","elo":elo})
    room_changed.emit()

func send(payload: Dictionary) -> bool:
    if not connected:
        return false
    var p := payload.duplicate(true)
    p["platform"] = "android"
    return _room_send({"kind":"relay","player":player,"payload":p})

func send_chat(text_value: String) -> bool:
    var value := text_value.strip_edges().left(180)
    if value.is_empty() or not connected:
        return false
    chat.append({"who":display_name,"text":value})
    while chat.size() > 40:
        chat.remove_at(0)
    send({"type":"chat","text":value,"player":player,"pseudo":display_name})
    room_changed.emit()
    return true

func start_standard() -> void:
    if not connected:
        return
    var seed := 1 + randi() % 2000000000
    send({"type":"start_standard","seed":seed})
    event_received.emit({"type":"start_standard","seed":seed,"local":true})

func start_ranked() -> void:
    leave()
    ranked_searching = true
    ranked_search_started_ms = Time.get_ticks_msec()
    room_changed.emit()

func _ranked_tick(now: int) -> void:
    if not ranked_searching or connected or not role.is_empty():
        return
    var found := rooms("ranked",true)
    if not found.is_empty():
        found.sort_custom(func(a: Dictionary,b: Dictionary) -> bool:
            return absi(int(a.get("elo",100))-elo) < absi(int(b.get("elo",100))-elo)
        )
        ranked_searching = false
        join_room(found[0])
        return
    if now - ranked_search_started_ms >= 1700:
        ranked_searching = false
        host("ranked",false)
        room_changed.emit()

func private_room_info() -> Dictionary:
    if role != "host" or room_id.is_empty() or channel.is_empty():
        return {}
    return {"room_id":room_id,"channel":channel,"room_name":room_name,"host_name":display_name}

func join_private(room_value: String,channel_value: String,name_value: String = "Partie privée",host_value: String = "Adversaire") -> Dictionary:
    leave()
    session = _random_hex(12)
    role = "client"
    player = 2
    room_id = room_value
    channel = channel_value
    room_topic = ROOM + "/" + channel
    room_name = name_value
    peer_name = host_value.left(20)
    match_type = "private"
    private_room = true
    if room_id.is_empty() or channel.is_empty():
        return {"ok":false,"message":"Invitation privée invalide."}
    subscribe(room_topic,1)
    _room_send({"kind":"join_request","display_name":display_name,"platform":"android"})
    room_changed.emit()
    return {"ok":true}

func leave() -> void:
    ranked_searching = false
    if not room_id.is_empty():
        if role == "host":
            if connected:
                _room_send({"kind":"room_closed"})
            if not private_room:
                publish(LOBBY + "/" + room_id,PackedByteArray(),true,1)
        elif role == "client":
            _room_send({"kind":"leave"})
    connected = false
    role = ""
    player = 0
    room_id = ""
    channel = ""
    room_topic = ""
    room_name = ""
    peer_name = ""
    peer_elo = 100
    host_session = ""
    guest_session = ""
    private_room = false
    chat.clear()
    room_changed.emit()

func _pub(topic: String,obj: Dictionary,retain: bool = false) -> bool:
    var signed := _sign(obj)
    return publish_text(topic,JSON.stringify(signed),retain,1)

func _sign(obj: Dictionary) -> Dictionary:
    var body := obj.duplicate(true)
    body.erase("sig")
    body["sig"] = _hmac_hex(APP_KEY,_stable(body))
    return body

func _valid(obj: Dictionary) -> bool:
    if not obj.has("sig"):
        return false
    var sig := str(obj.get("sig",""))
    var body := obj.duplicate(true)
    body.erase("sig")
    return sig == _hmac_hex(APP_KEY,_stable(body))

func _stable(value: Variant) -> String:
    if value == null:
        return "null"
    if typeof(value) == TYPE_DICTIONARY:
        var d: Dictionary = value as Dictionary
        var keys: Array = d.keys()
        keys.sort_custom(func(a: Variant,b: Variant) -> bool: return str(a) < str(b))
        var parts: Array[String] = []
        for key: Variant in keys:
            parts.append(JSON.stringify(str(key)) + ":" + _stable(d[key]))
        return "{" + ",".join(parts) + "}"
    if typeof(value) == TYPE_ARRAY:
        var parts: Array[String] = []
        for item: Variant in value as Array:
            parts.append(_stable(item))
        return "[" + ",".join(parts) + "]"
    return JSON.stringify(value)

func _hmac_hex(key: String,message: String) -> String:
    var ctx := HMACContext.new()
    var err := ctx.start(HashingContext.HASH_SHA256,key.to_utf8_buffer())
    if err != OK:
        return ""
    ctx.update(message.to_utf8_buffer())
    return ctx.finish().hex_encode()

func _random_hex(bytes_count: int) -> String:
    return Crypto.new().generate_random_bytes(bytes_count).hex_encode()

func _random_code(length: int) -> String:
    const CHARS := "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
    var bytes := Crypto.new().generate_random_bytes(length)
    var out := ""
    for i in range(length):
        out += CHARS[int(bytes[i]) % CHARS.length()]
    return out
