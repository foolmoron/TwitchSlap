class_name RotateParent
extends Node

@export_range(-720.0, 720.0, 1.0, "or_greater", "or_less")
var speed_deg := 360.0

@onready var parent: Node = get_parent()
@onready var parentC: Control = get_parent() as Control

func _process(delta: float) -> void:
	if parentC:
		parentC.rotation = fmod(parentC.rotation + deg_to_rad(speed_deg) * delta, TAU)
	else:
		parent.rotate(deg_to_rad(speed_deg) * delta)
