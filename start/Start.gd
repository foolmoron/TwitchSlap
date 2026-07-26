extends Control

var main_scene := preload("res://main.tscn")

func _input(event: InputEvent) -> void:
	if (event is InputEventScreenTouch and event.pressed) or (event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed):
		var tree = get_tree()
		tree.change_scene_to_packed(main_scene)
		GameManager.change_state(GameManager.State.Playing)