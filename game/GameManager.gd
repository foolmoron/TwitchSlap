extends Node

signal update_count_until_local_player(count: int)
signal on_hit()
signal on_game_over()

var game_over_scene := preload("res://gameover.tscn") as PackedScene

@export_range(1, 999) var player_count := 4
@export_range(0, 999) var player_local_id := 0

@export_range(0, 999) var player_latest_hit := 0:
	set(val):
		player_latest_hit = val
		count_until_local_player = ((player_latest_hit - 1) - player_local_id + player_count) % player_count

var count_until_local_player := 0:
	set(val):
		print("count_until_local_player: %d" % val)
		count_until_local_player = val
		update_count_until_local_player.emit(count_until_local_player)
		if count_until_local_player == 0:
			player_time_remaining = player_time_max

@export_range(0.0, 2.0) var stun_time := 0.0
@export_range(0.0, 2.0) var stun_time_max := 0.5

@export_range(0.0, 2.0) var player_time_remaining := 0.0
@export_range(0.0, 2.0) var player_time_max := 1.2
@export_range(0.0, 2.0) var player_time_min := 0.3

var is_game_over := false

func _ready() -> void:
	player_latest_hit = player_local_id
	await get_tree().create_timer(0).timeout
	player_latest_hit = player_local_id

func _process(delta: float) -> void:
	if count_until_local_player == 0:
		player_time_remaining -= delta
		if player_time_remaining < 0.0:
			do_game_over();
	else:
		player_time_remaining = player_time_max
	if stun_time > 0.0:
		stun_time -= delta

func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			do_hit()
		if event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			player_latest_hit -= 1
			if player_latest_hit < 0:
				player_latest_hit += player_count

func do_hit() -> void:
	if stun_time > 0.0:
		return
	if count_until_local_player != 0:
		do_stun()
		return
	player_latest_hit = player_local_id
	player_time_max = max(player_time_min, player_time_max * 0.85)
	on_hit.emit()

func do_stun() -> void:
	stun_time = stun_time_max

func do_game_over() -> void:
	if is_game_over:
		return
	is_game_over = true
	on_game_over.emit()
	get_tree().change_scene_to_packed(game_over_scene)
