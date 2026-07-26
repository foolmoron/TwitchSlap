extends Control

@export_group("Placeholder SFX")
@export var hit_sfx: AudioStream
@export var stun_sfx: AudioStream
@export var win_sfx: AudioStream
@export var lose_sfx: AudioStream

@onready var stun_grayscale: ColorRect = $StunGrayscale

var _hit_player := AudioStreamPlayer.new()
var _stun_player := AudioStreamPlayer.new()
var _result_player := AudioStreamPlayer.new()
var _was_stunned := false
var _feedback_generation := 0
var _stun_vibration_generation := 0

func _ready() -> void:
	add_child(_hit_player)
	add_child(_stun_player)
	add_child(_result_player)
	_hit_player.stream = hit_sfx
	_stun_player.stream = stun_sfx
	GameManager.on_hit.connect(_on_hit)
	GameManager.on_change_state.connect(_on_state_changed)

func _process(_delta: float) -> void:
	var stunned: bool = (
		GameManager.state == GameManager.State.Playing
		and GameManager.is_stunned()
	)
	stun_grayscale.visible = stunned
	if stunned and not _was_stunned:
		_start_stun_feedback()
	elif not stunned and _was_stunned:
		_stop_stun_feedback()
	elif stunned and stun_sfx != null and not _stun_player.playing:
		# Keep placeholder stun audio looping even if its imported stream is not.
		_stun_player.play()
	_was_stunned = stunned

func _on_hit() -> void:
	_play_one_shot(_hit_player, hit_sfx)
	_vibrate(120)

func _start_stun_feedback() -> void:
	_play_one_shot(_stun_player, stun_sfx)
	_stun_vibration_generation += 1
	_play_stun_vibration(_stun_vibration_generation)

func _stop_stun_feedback() -> void:
	_stun_vibration_generation += 1
	_stun_player.stop()
	Input.vibrate_handheld(0)

func _on_state_changed(state: GameManager.State) -> void:
	_feedback_generation += 1
	if state != GameManager.State.Playing and _was_stunned:
		_stop_stun_feedback()
		_was_stunned = false
	if state == GameManager.State.YouWin:
		_play_one_shot(_result_player, win_sfx)
		_vibrate(500)
	elif state == GameManager.State.GameOver:
		_play_one_shot(_result_player, lose_sfx)
		_play_lose_vibration(_feedback_generation)
	else:
		_result_player.stop()

func _play_one_shot(player: AudioStreamPlayer, stream: AudioStream) -> void:
	if stream == null:
		return
	player.stream = stream
	player.play()

func _vibrate(duration_ms: int) -> void:
	if duration_ms > 0:
		Input.vibrate_handheld(duration_ms)

func _play_stun_vibration(generation: int) -> void:
	# Web vibration has no intensity control, so short gaps soften the sensation.
	while generation == _stun_vibration_generation and GameManager.is_stunned():
		_vibrate(55)
		await get_tree().create_timer(0.08).timeout

func _play_lose_vibration(generation: int) -> void:
	var pulses := [
		{"duration": 130, "pause": 80},
		{"duration": 100, "pause": 110},
		{"duration": 70, "pause": 140},
		{"duration": 40, "pause": 0},
	]
	for pulse in pulses:
		if generation != _feedback_generation:
			return
		_vibrate(pulse["duration"])
		await get_tree().create_timer(
			float(pulse["duration"] + pulse["pause"]) / 1000.0
		).timeout
