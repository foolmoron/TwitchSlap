class_name RotateParent
extends Node

@export_range(-720.0, 720.0, 1.0, "or_greater", "or_less")
var speed_rad := 360.0

@onready var parent: Node = get_parent()

func _process(delta: float) -> void:
	parent.rotate(deg_to_rad(speed_rad) * delta)
