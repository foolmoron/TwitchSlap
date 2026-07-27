extends Node

const BACKGROUND_MUSIC_STREAM: AudioStreamMP3 = preload(
	"res://assets/Pshychedelia_Sketch_Final.mp3"
)

signal update_count_until_local_player(count: int)
signal on_hit(seat_id: int)
signal on_change_state(is_game_over: bool)
signal player_removed(seat_id: int)
signal winner_declared(seat_id: int)

enum State {
	Start,
	Playing,
	GameOver,
	YouWin,
}

@export_range(1, 999) var player_count := 1
@export_range(0, 999) var player_local_id := 0
@export_range(0, 999) var player_latest_hit := 0

var count_until_local_player := 0:
	set(value):
		if count_until_local_player == value:
			return
		count_until_local_player = value
		update_count_until_local_player.emit(value)

@export_range(0.0, 2.0) var stun_time := 0.0
@export_range(0.0, 2.0) var stun_time_max := 0.5
@export_range(0.0, 2.0) var player_time_remaining := 0.0
@export_range(0.0, 2.0) var player_time_max := 2.5
@export_range(0.0, 2.0) var player_time_min := 0.25
@export_range(0.0, 1.0) var time_decay := 0.85

var state := State.Start
var match_id := ""
var seat_by_peer: Dictionary = {}
var peer_by_seat: Dictionary = {}
var seat_order: Array[int] = []
var alive_seats: Array[int] = []
var active_seat := -1
var active_deadline_ms := 0

var background_music := AudioStreamPlayer.new()

var _match_start_ms := 0
var _initial_time_max := 1.2
var _baseline_active := -1
var _baseline_latest := -1
var _baseline_deadline_ms := 0
var _baseline_hits_by_seat: Dictionary = {}
var _confirmed_hits_by_seat: Dictionary = {}
var _hit_events: Array[Dictionary] = []
var _accepted_hit_keys: Dictionary = {}
var _pending_local_timeout := false
var _touch_released := false

func _ready() -> void:
	background_music.name = "BGM"
	background_music.stream = BACKGROUND_MUSIC_STREAM
	add_child(background_music)
	background_music.play()

func configure_match(
		new_match_id: String,
		start_ms: int,
		roster: Dictionary,
		initial_time_max: float,
		first_seat: int,
) -> void:
	match_id = new_match_id
	_match_start_ms = start_ms
	_initial_time_max = initial_time_max
	seat_by_peer = roster.duplicate()
	peer_by_seat.clear()
	seat_order.clear()
	for peer_id in seat_by_peer:
		var seat_id: int = seat_by_peer[peer_id]
		peer_by_seat[seat_id] = peer_id
		seat_order.append(seat_id)
	seat_order.sort()
	alive_seats = seat_order.duplicate()
	_baseline_hits_by_seat.clear()
	for seat_id in seat_order:
		_baseline_hits_by_seat[seat_id] = 0
	_confirmed_hits_by_seat = _baseline_hits_by_seat.duplicate()
	player_count = alive_seats.size()
	player_local_id = seat_by_peer.get(multiplayer.get_unique_id(), -1)
	active_seat = first_seat
	player_latest_hit = _previous_alive(first_seat)
	player_time_max = _initial_time_max
	active_deadline_ms = start_ms + roundi(player_time_max * 1000.0)
	_baseline_active = active_seat
	_baseline_latest = player_latest_hit
	_baseline_deadline_ms = active_deadline_ms
	_hit_events.clear()
	_accepted_hit_keys.clear()
	_pending_local_timeout = false
	_touch_released = false
	stun_time = 0.0
	_update_local_turn()
	change_state(State.Playing)

func shared_now_ms() -> int:
	return Network.shared_now_ms()

func add_hit_event(seat_id: int, sequence: int, timestamp_ms: int) -> void:
	var key := _hit_key(seat_id, sequence)
	for event in _hit_events:
		if event["key"] == key:
			return
	_hit_events.append({
		"key": key,
		"seat": seat_id,
		"sequence": sequence,
		"timestamp": timestamp_ms,
	})
	_reconcile_hits()

func _reconcile_hits() -> void:
	_hit_events.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if a["timestamp"] == b["timestamp"]:
			return a["seat"] < b["seat"]
		return a["timestamp"] < b["timestamp"]
	)

	var replay_alive := seat_order.duplicate()
	for seat_id in seat_order:
		if not alive_seats.has(seat_id):
			replay_alive.erase(seat_id)
	if replay_alive.is_empty():
		return

	var replay_active: int = _baseline_active
	while not replay_alive.has(replay_active):
		replay_active = _next_in(replay_active, replay_alive)
	var replay_latest := _baseline_latest
	var replay_time_max := _initial_time_max
	var replay_deadline := _baseline_deadline_ms
	var accepted: Dictionary = {}
	var confirmed_hits := _baseline_hits_by_seat.duplicate()

	for event in _hit_events:
		var seat_id: int = event["seat"]
		var timestamp_ms: int = event["timestamp"]
		if not replay_alive.has(seat_id):
			continue
		if seat_id != replay_active or timestamp_ms > replay_deadline:
			continue
		accepted[event["key"]] = true
		confirmed_hits[seat_id] = int(confirmed_hits.get(seat_id, 0)) + 1
		replay_latest = seat_id
		if seat_id == replay_alive.min():
			replay_time_max = max(player_time_min, replay_time_max * time_decay)
		replay_active = _next_in(seat_id, replay_alive)
		replay_deadline = timestamp_ms + roundi(replay_time_max * 1000.0)

	var newly_accepted_seats: Array[int] = []
	for event in _hit_events:
		var key: String = event["key"]
		if accepted.has(key) and not _accepted_hit_keys.has(key):
			newly_accepted_seats.append(event["seat"])
	_accepted_hit_keys = accepted
	_confirmed_hits_by_seat = confirmed_hits
	player_latest_hit = replay_latest
	player_time_max = replay_time_max
	active_seat = replay_active
	active_deadline_ms = replay_deadline
	_pending_local_timeout = false
	if state == State.GameOver and alive_seats.has(player_local_id):
		change_state(State.Playing)
	_update_local_turn()
	for seat_id in newly_accepted_seats:
		on_hit.emit(seat_id)

func remove_player(seat_id: int, _timestamp_ms: int) -> void:
	if not alive_seats.has(seat_id):
		return
	_reconcile_hits()
	alive_seats.erase(seat_id)
	player_count = alive_seats.size()
	player_removed.emit(seat_id)
	if seat_id == player_local_id:
		change_state(State.GameOver)
	if alive_seats.is_empty():
		active_seat = -1
		return
	if seat_id == active_seat:
		active_seat = _next_in(seat_id, alive_seats)
		active_deadline_ms = shared_now_ms() + roundi(player_time_max * 1000.0)
	player_latest_hit = _previous_in(active_seat, alive_seats)
	_initial_time_max = player_time_max
	_baseline_active = active_seat
	_baseline_latest = player_latest_hit
	_baseline_deadline_ms = active_deadline_ms
	_baseline_hits_by_seat = _confirmed_hits_by_seat.duplicate()
	_hit_events.clear()
	_accepted_hit_keys.clear()
	_update_local_turn()

func declare_winner(seat_id: int) -> void:
	active_seat = -1
	if seat_id == player_local_id:
		change_state(State.YouWin)
	elif state != State.GameOver:
		change_state(State.GameOver)
	winner_declared.emit(seat_id)

func can_confirm_timeout(seat_id: int, deadline_ms: int) -> bool:
	return (
		state != State.YouWin
		and alive_seats.has(seat_id)
		and active_seat == seat_id
		and active_deadline_ms == deadline_ms
		and shared_now_ms() >= deadline_ms
	)

func get_player_confirmed_hits_count() -> int:
	return int(_confirmed_hits_by_seat.get(player_local_id, 0))

func _process(delta: float) -> void:
	if _touch_released:
		stun_time = stun_time_max
	elif is_stunned():
		stun_time = maxf(0.0, stun_time - delta)
	if state != State.Playing or active_seat < 0:
		return
	player_time_remaining = maxf(0.0, float(active_deadline_ms - shared_now_ms()) / 1000.0)
	if player_time_remaining <= 0.0 and not _pending_local_timeout:
		_pending_local_timeout = true
		if active_seat == player_local_id:
			change_state(State.GameOver)
			Network.report_local_timeout(active_deadline_ms)
		elif multiplayer.is_server():
			# The host is the final authority on every turn timeout. Do not rely
			# solely on the active client, which may disconnect or lose its RPC
			# after displaying Game Over.
			Network.confirm_host_timeout(active_seat, active_deadline_ms)

func _input(event: InputEvent) -> void:
	if state != State.Playing:
		return
	if event is InputEventScreenTouch:
		_touch_released = not event.pressed
		return
	if OS.get_name() != "Web":
		var pressed: bool = event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed
		if pressed:
			do_hit()

func do_hit() -> void:
	if is_stunned():
		return
	if active_seat != player_local_id:
		do_stun()
		return
	Network.send_local_hit()

func do_stun() -> void:
	stun_time = stun_time_max

func is_stunned() -> bool:
	return stun_time > 0.0

func _update_local_turn() -> void:
	if player_local_id < 0 or not alive_seats.has(player_local_id) or active_seat < 0:
		count_until_local_player = -1
		return
	var count := 0
	var seat_id := active_seat
	while seat_id != player_local_id and count <= alive_seats.size():
		seat_id = _next_in(seat_id, alive_seats)
		count += 1
	count_until_local_player = count

func _next_in(seat_id: int, seats: Array[int]) -> int:
	if seats.is_empty():
		return -1
	var index := seat_order.find(seat_id)
	for offset in range(1, seat_order.size() + 1):
		var candidate: int = seat_order[(index + offset) % seat_order.size()]
		if seats.has(candidate):
			return candidate
	return seats[0]

func _previous_in(seat_id: int, seats: Array[int]) -> int:
	if seats.is_empty():
		return -1
	var index := seat_order.find(seat_id)
	for offset in range(1, seat_order.size() + 1):
		var candidate: int = seat_order[posmod(index - offset, seat_order.size())]
		if seats.has(candidate):
			return candidate
	return seats[0]

func _previous_alive(seat_id: int) -> int:
	return _previous_in(seat_id, alive_seats)

func _hit_key(seat_id: int, sequence: int) -> String:
	return "%d:%d" % [seat_id, sequence]

func change_state(state_new: State) -> void:
	if state == state_new:
		return
	state = state_new
	on_change_state.emit(state_new)
