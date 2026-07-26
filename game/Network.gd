extends Node

const TUBE_CONTEXT = preload("res://game/tube_context.tres")

signal lobby_updated(player_count: int, ready_count: int)
signal session_failed(message: String)
signal game_starting

var enet_peer := ENetMultiplayerPeer.new()
var tube_client := TubeClient.new()
var tube_enabled := true
var turn_enabled := false: set = set_turn_enabled

var new_offline := OfflineMultiplayerPeer.new()
var new_http_client := HTTPRequest.new()

var PORT = 9999
var IP_ADDRESS = '127.0.0.1'
const TURN_API_URL = "https://api.androodev.com/turn"

var players_ready: Dictionary = {}
var _start_generation := 0
var session_connected := false

func _ready() -> void:
	new_http_client.request_completed.connect(_on_request_completed)
	get_tree().root.add_child.call_deferred(new_http_client)

	if tube_enabled:
		tube_client.context = TUBE_CONTEXT
		tube_client.multiplayer_root_node = get_tree().root
		tube_client.session_created.connect(_on_session_opened)
		tube_client.session_joined.connect(_on_session_opened)
		tube_client.error_raised.connect(_on_tube_error)
		get_tree().root.add_child.call_deferred(tube_client)

	await get_tree().create_timer(0).timeout
	if turn_enabled:
		set_turn_enabled(true)

func tube_create() -> String:
	_connect_multiplayer_signals()
	session_connected = false
	tube_client.create_session()
	players_ready.clear()
	players_ready[1] = false
	_emit_lobby_updated()
	return tube_client.session_id

func tube_join(session_id: String):
	_connect_multiplayer_signals()
	session_connected = false
	players_ready.clear()
	tube_client.join_session(session_id)

func _connect_multiplayer_signals() -> void:
	if not multiplayer.peer_connected.is_connected(add_player):
		multiplayer.peer_connected.connect(add_player)
	if not multiplayer.peer_disconnected.is_connected(remove_player):
		multiplayer.peer_disconnected.connect(remove_player)
	if not multiplayer.connected_to_server.is_connected(on_connected_to_server):
		multiplayer.connected_to_server.connect(on_connected_to_server)

func start_server():
	enet_peer.create_server(PORT)
	multiplayer.multiplayer_peer = enet_peer
	multiplayer.peer_connected.connect(add_player)
	multiplayer.peer_disconnected.connect(remove_player)

func join_server():
	enet_peer.create_client(IP_ADDRESS, PORT)
	multiplayer.peer_connected.connect(add_player)
	multiplayer.peer_disconnected.connect(remove_player)
	multiplayer.connected_to_server.connect(on_connected_to_server)
	multiplayer.multiplayer_peer = enet_peer

func on_connected_to_server():
	add_player(multiplayer.get_unique_id())

func add_player(peer_id: int):
	if peer_id == 1 and multiplayer.multiplayer_peer is ENetMultiplayerPeer:
		return
	if multiplayer.is_server():
		players_ready[peer_id] = false
		_broadcast_lobby()

func remove_player(peer_id):
	if peer_id == 1:
		leave_server()
		return
	if multiplayer.is_server():
		players_ready.erase(peer_id)
		_cancel_pending_start()
		_broadcast_lobby()

func set_local_ready(is_ready: bool) -> void:
	if not session_connected:
		return
	var peer_id := multiplayer.get_unique_id()
	if multiplayer.is_server():
		_set_player_ready(peer_id, is_ready)
	else:
		if multiplayer.multiplayer_peer.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED:
			return
		_submit_ready.rpc_id(1, is_ready)

@rpc("any_peer", "call_remote", "reliable")
func _submit_ready(is_ready: bool) -> void:
	if not multiplayer.is_server():
		return
	_set_player_ready(multiplayer.get_remote_sender_id(), is_ready)

func _set_player_ready(peer_id: int, is_ready: bool) -> void:
	if not players_ready.has(peer_id):
		players_ready[peer_id] = false
	if players_ready[peer_id] == is_ready:
		return
	players_ready[peer_id] = is_ready
	_cancel_pending_start()
	_broadcast_lobby()
	if not players_ready.is_empty() and _ready_count() == players_ready.size():
		_begin_start_countdown()

func _ready_count() -> int:
	var count := 0
	for is_ready in players_ready.values():
		if is_ready:
			count += 1
	return count

func _broadcast_lobby() -> void:
	var total := players_ready.size()
	var ready := _ready_count()
	_receive_lobby.rpc(total, ready)

@rpc("authority", "call_local", "reliable")
func _receive_lobby(player_count: int, ready_count: int) -> void:
	lobby_updated.emit(player_count, ready_count)

func _emit_lobby_updated() -> void:
	lobby_updated.emit(players_ready.size(), _ready_count())

func _cancel_pending_start() -> void:
	_start_generation += 1

func _begin_start_countdown() -> void:
	_start_generation += 1
	var generation := _start_generation
	await get_tree().create_timer(2.0).timeout
	if generation != _start_generation:
		return
	if _ready_count() != players_ready.size():
		return
	_start_game.rpc()

@rpc("authority", "call_local", "reliable")
func _start_game() -> void:
	game_starting.emit()

func _on_session_opened() -> void:
	session_connected = true
	if multiplayer.is_server():
		players_ready[1] = false
		_broadcast_lobby()

func _on_tube_error(_code: int, message: String) -> void:
	if tube_client.state == TubeClient.State.IDLE or tube_client.state == TubeClient.State.JOINING_SESSION:
		session_connected = false
	session_failed.emit(message)

func leave_server():
	session_connected = false
	if tube_enabled:
		tube_client.leave_session()

	multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = null
	clean_up_signals()
	get_tree().reload_current_scene()
	
func clean_up_signals():
	if multiplayer.peer_connected.is_connected(add_player):
		multiplayer.peer_connected.disconnect(add_player)
	if multiplayer.peer_disconnected.is_connected(remove_player):
		multiplayer.peer_disconnected.disconnect(remove_player)
	if multiplayer.connected_to_server.is_connected(on_connected_to_server):
		multiplayer.connected_to_server.disconnect(on_connected_to_server)

func _exit_tree() -> void:
	if tube_enabled:
		tube_client.leave_session()

var temp_ice: Dictionary

func _on_request_completed(result, response_code, _headers, body):
	if result != HTTPRequest.RESULT_SUCCESS or response_code < 200 or response_code >= 300:
		push_warning("TURN request failed (result: %s, HTTP: %s)" % [result, response_code])
		return

	var parsed_response = JSON.parse_string(body.get_string_from_utf8())
	if not parsed_response is Dictionary:
		push_warning("TURN request returned invalid JSON")
		return
	var response: Dictionary = parsed_response

	if response.has("iceServers"):
		temp_ice = response["iceServers"][1]
		tube_client.context.turn_servers.append(temp_ice)
		prints("DEBUG", tube_client.context.turn_servers)

func set_turn_enabled(is_enabled: bool):
	tube_client.context.turn_servers.clear()
	if is_enabled and temp_ice:
		tube_client.context.turn_servers.append(temp_ice)
	elif is_enabled:
		var turn_url := TURN_API_URL
		if OS.get_name() == "Web":
			turn_url = str(JavaScriptBridge.eval("window.location.origin")) + "/turn"
		new_http_client.request(turn_url)
