extends Node

const TUBE_CONTEXT = preload("res://game/tube_context.tres")
const TURN_API_URL = "https://api.androodev.com/turn"
const MIN_PLAYERS := 2
const CLOCK_SAMPLES := 3
const MAX_FUTURE_MS := 250

signal lobby_updated(player_count: int, ready_count: int)
signal session_failed(message: String)
signal game_starting

var enet_peer := ENetMultiplayerPeer.new()
var tube_client := TubeClient.new()
var tube_enabled := true
var new_http_client := HTTPRequest.new()

var PORT = 9999
var IP_ADDRESS = "127.0.0.1"
var players_ready: Dictionary = {}
var session_connected := false

var match_id := ""
var seat_by_peer: Dictionary = {}
var _start_generation := 0
var _local_hit_sequence := 0
var _seen_hit_sequences: Dictionary = {}
var _clock_offsets: Dictionary = {1: 0}
var _best_rtt: Dictionary = {1: 0}
var _smoothed_rtt: Dictionary = {1: 100.0}
var _rtt_jitter: Dictionary = {1: 0.0}
var _client_host_offset_ms := 0
var _winner_sent := false

func _ready() -> void:
	new_http_client.timeout = 10.0
	get_tree().root.add_child.call_deferred(new_http_client)
	if tube_enabled:
		tube_client.context = TUBE_CONTEXT
		tube_client.multiplayer_root_node = get_tree().root
		tube_client.peer_signaling_timeout = 5.0
		tube_client.peer_signaling_max_attempts = 6
		tube_client.session_created.connect(_on_session_opened)
		tube_client.session_joined.connect(_on_session_opened)
		tube_client.peer_refused.connect(_on_peer_refused)
		tube_client.session_left.connect(_on_session_left)
		tube_client.error_raised.connect(_on_tube_error)
		get_tree().root.add_child.call_deferred(tube_client)
	await get_tree().create_timer(0).timeout

func prepare_turn() -> bool:
	tube_client.context.turn_servers.clear()
	var request_error := new_http_client.request(TURN_API_URL)
	if request_error != OK:
		push_warning("TURN request could not start: %s" % error_string(request_error))
		return false

	var completed: Array = await new_http_client.request_completed
	var result: int = completed[0]
	var response_code: int = completed[1]
	var body: PackedByteArray = completed[3]
	if result != HTTPRequest.RESULT_SUCCESS:
		push_warning("TURN request failed: %s" % _http_result_string(result))
		return false
	if response_code < 200 or response_code >= 300:
		push_warning("TURN request returned HTTP %d" % response_code)
		return false

	var parsed_response = JSON.parse_string(body.get_string_from_utf8())
	if not parsed_response is Dictionary:
		push_warning("TURN request returned invalid JSON")
		return false
	var response: Dictionary = parsed_response
	if not response.get("iceServers") is Array:
		push_warning("TURN response is missing an iceServers array")
		return false

	var seen_servers: Dictionary = {}
	for server_value in response["iceServers"]:
		if not server_value is Dictionary:
			continue
		var server: Dictionary = server_value
		var turn_urls := _validated_turn_urls(server.get("urls"))
		var username := str(server.get("username", ""))
		var credential := str(server.get("credential", ""))
		if turn_urls.is_empty() or username.is_empty() or credential.is_empty():
			continue
		var signature := "%s|%s" % [str(turn_urls), username]
		if seen_servers.has(signature):
			continue
		seen_servers[signature] = true
		tube_client.context.turn_servers.append({
			"urls": turn_urls[0] if turn_urls.size() == 1 else turn_urls,
			"username": username,
			"credential": credential,
		})

	if tube_client.context.turn_servers.is_empty():
		push_warning("TURN response contained no valid authenticated TURN servers")
		return false
	print("TURN ready: loaded %d relay server configuration(s)" % tube_client.context.turn_servers.size())
	return true

func _validated_turn_urls(urls_value: Variant) -> Array[String]:
	var candidates: Array = []
	if urls_value is String:
		candidates.append(urls_value)
	elif urls_value is Array or urls_value is PackedStringArray:
		candidates.assign(urls_value)
	var valid_urls: Array[String] = []
	for candidate in candidates:
		var url := str(candidate).strip_edges()
		if url.begins_with("turn:") or url.begins_with("turns:"):
			valid_urls.append(url)
	return valid_urls

func _http_result_string(result: int) -> String:
	if result == HTTPRequest.RESULT_TIMEOUT:
		return "request timed out"
	return "result %d" % result

func tube_create() -> String:
	_connect_multiplayer_signals()
	session_connected = false
	tube_client.create_session()
	players_ready.clear()
	players_ready[1] = false
	_emit_lobby_updated()
	return tube_client.session_id

func tube_join(session_id: String) -> void:
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

func start_server() -> void:
	enet_peer.create_server(PORT)
	multiplayer.multiplayer_peer = enet_peer
	_connect_multiplayer_signals()

func join_server() -> void:
	enet_peer.create_client(IP_ADDRESS, PORT)
	_connect_multiplayer_signals()
	multiplayer.multiplayer_peer = enet_peer

func on_connected_to_server() -> void:
	add_player(multiplayer.get_unique_id())

func add_player(peer_id: int) -> void:
	if peer_id == 1 and multiplayer.multiplayer_peer is ENetMultiplayerPeer:
		return
	if multiplayer.is_server() and match_id.is_empty():
		players_ready[peer_id] = false
		_cancel_pending_start()
		_broadcast_lobby()

func remove_player(peer_id: int) -> void:
	if peer_id == 1 and not multiplayer.is_server():
		session_connected = false
		session_failed.emit("Host disconnected. Refresh the page to restart.")
		return
	if not multiplayer.is_server():
		return
	players_ready.erase(peer_id)
	_cancel_pending_start()
	if match_id.is_empty():
		_broadcast_lobby()
	elif seat_by_peer.has(peer_id):
		_host_remove_seat(seat_by_peer[peer_id], shared_now_ms())

func set_local_ready(is_ready: bool) -> void:
	if not session_connected or not match_id.is_empty():
		return
	var peer_id := multiplayer.get_unique_id()
	if multiplayer.is_server():
		_set_player_ready(peer_id, is_ready)
	elif multiplayer.multiplayer_peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED:
		_submit_ready.rpc_id(1, is_ready)

@rpc("any_peer", "call_remote", "reliable")
func _submit_ready(is_ready: bool) -> void:
	if multiplayer.is_server() and match_id.is_empty():
		_set_player_ready(multiplayer.get_remote_sender_id(), is_ready)

func _set_player_ready(peer_id: int, is_ready: bool) -> void:
	if not players_ready.has(peer_id):
		return
	if players_ready[peer_id] == is_ready:
		return
	players_ready[peer_id] = is_ready
	_cancel_pending_start()
	_broadcast_lobby()
	if players_ready.size() >= MIN_PLAYERS and _ready_count() == players_ready.size():
		_begin_start_countdown()

func _ready_count() -> int:
	var count := 0
	for is_ready in players_ready.values():
		if is_ready:
			count += 1
	return count

func _broadcast_lobby() -> void:
	_receive_lobby.rpc(players_ready.size(), _ready_count())

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
	for _sample in CLOCK_SAMPLES:
		_send_clock_probes()
		await get_tree().create_timer(0.1).timeout
	await get_tree().create_timer(1.7).timeout
	if generation != _start_generation:
		return
	if players_ready.size() < MIN_PLAYERS or _ready_count() != players_ready.size():
		return
	tube_client.refuse_new_connections = true
	var peer_ids: Array[int] = []
	for peer_id in players_ready:
		if peer_id != 1:
			peer_ids.append(peer_id)
	peer_ids.sort()
	peer_ids.push_front(1)
	seat_by_peer.clear()
	for seat_id in peer_ids.size():
		seat_by_peer[peer_ids[seat_id]] = seat_id
	match_id = "%d-%d" % [unix_now_ms(), randi()]
	_start_game.rpc(match_id, unix_now_ms(), seat_by_peer, GameManager.player_time_max, 0)

@rpc("authority", "call_local", "reliable")
func _start_game(
		new_match_id: String,
		start_ms: int,
		roster: Dictionary,
		initial_time_max: float,
		first_seat: int,
) -> void:
	match_id = new_match_id
	seat_by_peer = roster
	GameManager.configure_match(match_id, start_ms, roster, initial_time_max, first_seat)
	game_starting.emit()

func _send_clock_probes() -> void:
	if not multiplayer.is_server():
		return
	var sent_ms := unix_now_ms()
	for peer_id in players_ready:
		if peer_id != 1:
			_clock_probe.rpc_id(peer_id, sent_ms)

@rpc("authority", "call_remote", "reliable")
func _clock_probe(host_sent_ms: int) -> void:
	var received_ms := unix_now_ms()
	_clock_response.rpc_id(1, host_sent_ms, received_ms, unix_now_ms())

@rpc("any_peer", "call_remote", "reliable")
func _clock_response(host_sent_ms: int, client_received_ms: int, client_sent_ms: int) -> void:
	if not multiplayer.is_server():
		return
	var peer_id := multiplayer.get_remote_sender_id()
	var host_received_ms := unix_now_ms()
	var rtt := maxi(0, (host_received_ms - host_sent_ms) - (client_sent_ms - client_received_ms))
	var offset := roundi(((client_received_ms - host_sent_ms) + (client_sent_ms - host_received_ms)) / 2.0)
	if not _best_rtt.has(peer_id) or rtt < int(_best_rtt[peer_id]):
		_best_rtt[peer_id] = rtt
		_clock_offsets[peer_id] = offset
	var previous := float(_smoothed_rtt.get(peer_id, rtt))
	_smoothed_rtt[peer_id] = lerpf(previous, float(rtt), 0.25)
	_rtt_jitter[peer_id] = lerpf(float(_rtt_jitter.get(peer_id, 0.0)), absf(float(rtt) - previous), 0.25)
	_clock_result.rpc_id(peer_id, int(_clock_offsets[peer_id]))

@rpc("authority", "call_remote", "reliable")
func _clock_result(client_minus_host_ms: int) -> void:
	_client_host_offset_ms = client_minus_host_ms

func unix_now_ms() -> int:
	return roundi(Time.get_unix_time_from_system() * 1000.0)

func shared_now_ms() -> int:
	if multiplayer.is_server():
		return unix_now_ms()
	return unix_now_ms() - _client_host_offset_ms

func send_local_hit() -> void:
	if match_id.is_empty() or not GameManager.alive_seats.has(GameManager.player_local_id):
		return
	_local_hit_sequence += 1
	var timestamp_ms := shared_now_ms()
	if multiplayer.is_server():
		_accept_hit(1, _local_hit_sequence, timestamp_ms)
	else:
		_submit_hit.rpc_id(1, match_id, _local_hit_sequence, timestamp_ms)

@rpc("any_peer", "call_remote", "reliable")
func _submit_hit(event_match_id: String, sequence: int, timestamp_ms: int) -> void:
	if not multiplayer.is_server() or event_match_id != match_id:
		return
	var sender_peer := multiplayer.get_remote_sender_id()
	var normalized_ms := timestamp_ms - int(_clock_offsets.get(sender_peer, 0))
	_accept_hit(sender_peer, sequence, normalized_ms)

func _accept_hit(sender_peer: int, sequence: int, timestamp_ms: int) -> void:
	if not seat_by_peer.has(sender_peer) or sequence <= 0:
		return
	var seat_id: int = seat_by_peer[sender_peer]
	if not GameManager.alive_seats.has(seat_id):
		return
	var key := "%d:%d" % [seat_id, sequence]
	if _seen_hit_sequences.has(key):
		return
	if timestamp_ms > shared_now_ms() + MAX_FUTURE_MS:
		return
	_seen_hit_sequences[key] = true
	_receive_hit.rpc(match_id, seat_id, sequence, timestamp_ms)

@rpc("authority", "call_local", "reliable")
func _receive_hit(event_match_id: String, seat_id: int, sequence: int, timestamp_ms: int) -> void:
	if event_match_id == match_id:
		GameManager.add_hit_event(seat_id, sequence, timestamp_ms)

func report_local_timeout(deadline_ms: int) -> void:
	if match_id.is_empty():
		return
	var seat_id := GameManager.player_local_id
	if multiplayer.is_server():
		_wait_to_confirm_timeout(seat_id, deadline_ms)
	else:
		_submit_timeout.rpc_id(1, match_id, deadline_ms)

@rpc("any_peer", "call_remote", "reliable")
func _submit_timeout(event_match_id: String, deadline_ms: int) -> void:
	if not multiplayer.is_server() or event_match_id != match_id:
		return
	var sender_peer := multiplayer.get_remote_sender_id()
	if seat_by_peer.has(sender_peer):
		_wait_to_confirm_timeout(seat_by_peer[sender_peer], deadline_ms)

func _wait_to_confirm_timeout(seat_id: int, deadline_ms: int) -> void:
	if not multiplayer.is_server():
		return
	var peer_id: int = GameManager.peer_by_seat.get(seat_id, 1)
	var grace_ms := clampi(
		roundi(float(_smoothed_rtt.get(peer_id, 100.0)) + float(_rtt_jitter.get(peer_id, 0.0))),
		100,
		1000,
	)
	await get_tree().create_timer(float(grace_ms) / 1000.0).timeout
	if GameManager.can_confirm_timeout(seat_id, deadline_ms):
		_host_remove_seat(seat_id, shared_now_ms())

func _host_remove_seat(seat_id: int, timestamp_ms: int) -> void:
	if not multiplayer.is_server() or not GameManager.alive_seats.has(seat_id):
		return
	_receive_removal.rpc(match_id, seat_id, timestamp_ms)
	var survivors := GameManager.alive_seats.duplicate()
	survivors.erase(seat_id)
	if survivors.size() == 1 and not _winner_sent:
		_winner_sent = true
		_receive_winner.rpc(match_id, survivors[0])

@rpc("authority", "call_local", "reliable")
func _receive_removal(event_match_id: String, seat_id: int, timestamp_ms: int) -> void:
	if event_match_id == match_id:
		GameManager.remove_player(seat_id, timestamp_ms)

@rpc("authority", "call_local", "reliable")
func _receive_winner(event_match_id: String, seat_id: int) -> void:
	if event_match_id == match_id:
		GameManager.declare_winner(seat_id)

func _on_session_opened() -> void:
	session_connected = true
	if multiplayer.is_server():
		players_ready[1] = false
		_broadcast_lobby()

func _on_peer_refused(_peer_id: int) -> void:
	session_failed.emit("Game already started.")

func _on_session_left() -> void:
	session_connected = false
	session_failed.emit("Host disconnected. Refresh the page to restart.")

func _on_tube_error(_code: int, message: String) -> void:
	if tube_client.state == TubeClient.State.IDLE or tube_client.state == TubeClient.State.JOINING_SESSION:
		session_connected = false
	if "refus" in message.to_lower():
		session_failed.emit("Game already started.")
	else:
		session_failed.emit(message)

func leave_server() -> void:
	session_connected = false
	if tube_enabled:
		tube_client.leave_session()
	if multiplayer.multiplayer_peer:
		multiplayer.multiplayer_peer.close()
		multiplayer.multiplayer_peer = null
	clean_up_signals()
	get_tree().reload_current_scene()

func clean_up_signals() -> void:
	if multiplayer.peer_connected.is_connected(add_player):
		multiplayer.peer_connected.disconnect(add_player)
	if multiplayer.peer_disconnected.is_connected(remove_player):
		multiplayer.peer_disconnected.disconnect(remove_player)
	if multiplayer.connected_to_server.is_connected(on_connected_to_server):
		multiplayer.connected_to_server.disconnect(on_connected_to_server)

func _exit_tree() -> void:
	if tube_enabled:
		tube_client.leave_session()
