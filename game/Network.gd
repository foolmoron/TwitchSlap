extends Node

const TUBE_CONTEXT = preload("res://game/tube_context.tres")

var enet_peer := ENetMultiplayerPeer.new()
var tube_client := TubeClient.new()
var tube_enabled := true
var turn_enabled := true: set = set_turn_enabled

var new_offline := OfflineMultiplayerPeer.new()
var new_http_client := HTTPRequest.new()

var PORT = 9999
var IP_ADDRESS = '127.0.0.1'

func _ready() -> void:
	new_http_client.request_completed.connect(_on_request_completed)
	get_tree().root.add_child.call_deferred(new_http_client)

	if tube_enabled:
		tube_client.context = TUBE_CONTEXT
		get_tree().root.add_child.call_deferred(tube_client)

	await get_tree().create_timer(0).timeout
	if turn_enabled:
		set_turn_enabled(true)

func tube_create():
	multiplayer.peer_connected.connect(add_player)
	multiplayer.peer_disconnected.connect(remove_player)
	tube_client.create_session()
	add_player(1)

func tube_join(session_id: String):
	multiplayer.peer_connected.connect(add_player)
	multiplayer.peer_disconnected.connect(remove_player)
	multiplayer.connected_to_server.connect(on_connected_to_server)
	tube_client.join_session(session_id)

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
	
	# todo

func remove_player(peer_id):
	if peer_id == 1:
		leave_server()
		return
	
	# todo

func leave_server():
	if tube_enabled:
		tube_client.leave_session()

	multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = null
	clean_up_signals()
	get_tree().reload_current_scene()
	
func clean_up_signals():
	multiplayer.peer_connected.disconnect(add_player)
	multiplayer.peer_disconnected.disconnect(remove_player)
	multiplayer.connected_to_server.disconnect(on_connected_to_server)

func _exit_tree() -> void:
	if tube_enabled:
		tube_client.leave_session()

var temp_ice: Dictionary

func _on_request_completed(_result, _response_code, _headers, body):
	var response: Dictionary = JSON.parse_string(body.get_string_from_utf8())

	if response and response.has("iceServers"):
		temp_ice = response["iceServers"][1]
		tube_client.context.turn_servers.append(temp_ice)
		prints("DEBUG", tube_client.context.turn_servers)

func set_turn_enabled(is_enabled: bool):
	tube_client.context.turn_servers.clear()
	if is_enabled and temp_ice:
		tube_client.context.turn_servers.append(temp_ice)
	elif is_enabled:
		new_http_client.request("https://api.androodev.com/turn")
