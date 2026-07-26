extends Label

@export var is_win := false

@onready var parent := get_parent()

func _ready():
	GameManager.on_change_state.connect(func(state: GameManager.State):
		if (state == GameManager.State.GameOver && !is_win) || (state == GameManager.State.YouWin && is_win):
			parent.add_child(self)
			$CountLabel.text = "After %d Slaps" % GameManager.player_slaps
		elif self.is_inside_tree():
			parent.remove_child(self)
	)
	parent.remove_child.call_deferred(self)
