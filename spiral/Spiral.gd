extends ColorRect

@export_range(-30.0, 30.0, 0.01) var rotation_speed := 0.35
var rot := 0.0

@onready var shader: ShaderMaterial = material as ShaderMaterial

func _process(delta: float) -> void:
	var rot_speed = 0.0 if GameManager.count_until_local_player == 0 else rotation_speed
	rot = fmod(rot + rot_speed * delta, TAU)
	shader.set_shader_parameter("rotation", rot)
	shader.set_shader_parameter("drain", 1.0 - (GameManager.player_time_remaining / GameManager.player_time_max))
