extends Node

signal update_count_until_local_player(count: int)
signal on_hit()

@export_range(1, 999) var player_count := 16
@export_range(0, 999) var player_local_id := 0

@export_range(0, 999) var player_latest_hit := 0:
	set(value):
		player_latest_hit = value
		var count_until_local_player := (player_latest_hit - player_local_id + player_count) % player_count
		update_count_until_local_player.emit(count_until_local_player)

func _ready() -> void:
	await get_tree().create_timer(0).timeout
	player_latest_hit = player_local_id

func do_hit() -> void:
	if player_latest_hit == player_local_id:
		on_hit.emit()
	player_latest_hit -= 1
	if player_latest_hit < 0:
		player_latest_hit += player_count

func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			do_hit()
