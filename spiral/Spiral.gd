extends ColorRect

@export_range(-30.0, 30.0, 0.01) var rotation_speed := 0.35
var rot := 0.0

@onready var shader: ShaderMaterial = material as ShaderMaterial
@onready var twist_orig := shader.get_shader_parameter("twist") as float
@onready var thickness_orig := shader.get_shader_parameter("thickness") as float
@onready var spiral_color_orig := shader.get_shader_parameter("spiral_color") as Color
@onready var background_color_orig := shader.get_shader_parameter("background_color") as Color
@onready var time_max_orig := GameManager.player_time_max;

@onready var hue1 := randf()
@onready var hue2 := fmod(hue1 + 120.0/360.0, 1.0)
@onready var spiral_color := Color.from_hsv(hue1, spiral_color_orig.s, spiral_color_orig.v, spiral_color_orig.a)
@onready var background_color2 := Color.from_hsv(hue2, spiral_color_orig.s, spiral_color_orig.v, spiral_color_orig.a)

func _ready() -> void:
	shader.set_shader_parameter("spiral_color", spiral_color)

func _process(delta: float) -> void:
	var progression := max(0.1, (GameManager.player_time_max / time_max_orig)) as float
	var rot_speed = 0.0 if GameManager.count_until_local_player == 0 else rotation_speed
	rot = fmod(rot + rot_speed * pow(1 / progression, 0.5) * delta, TAU)
	shader.set_shader_parameter("rotation", rot)
	shader.set_shader_parameter("drain", 1.0 - (GameManager.player_time_remaining / GameManager.player_time_max))
	shader.set_shader_parameter("twist", twist_orig * progression)
	shader.set_shader_parameter("thickness", thickness_orig * progression)

	var bg := background_color_orig
	if GameManager.state == GameManager.State.GameOver:
		bg = spiral_color
	elif GameManager.count_until_local_player == 0:
		bg = background_color2
	shader.set_shader_parameter("background_color", bg)
