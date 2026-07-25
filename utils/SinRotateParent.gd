class_name SinRotateParent
extends Node


@export_range(0.0, 360.0, 1.0, "or_greater", "or_less") var amp := 30.0
@export_range(0.0, 10.0, 0.1, "or_greater", "or_less") var period := 1.5
@export_range(0.0, 360.0, 1.0, "or_greater", "or_less") var amp2 := 12.0
@export_range(0.0, 10.0, 0.1, "or_greater", "or_less") var period2 := 7.0

@onready var parent = get_parent()
@onready var rot_initial := parent.rotation as float

var time := 0.0

func _process(delta: float) -> void:
	time += delta
	parent.rotation = rot_initial + deg_to_rad(amp) * sin(time * TAU / period) + deg_to_rad(amp2) * sin(time * TAU / period2)
