extends Control

var main_scene := preload("res://main.tscn")
var session_id := ""
var in_lobby := false

@onready var intro: VBoxContainer = $Intro
@onready var start_label: Label = $Intro/StartLabel
@onready var session_label: Label = $Intro/SessionLabel
@onready var lobby: VBoxContainer = $Lobby
@onready var players_label: Label = $Lobby/PlayersLabel
@onready var qr_code: QRCodeRect = $Lobby/QRCodeRect
@onready var status_label: Label = $Lobby/StatusLabel

func _ready() -> void:
	session_id = _get_requested_session()
	if session_id.is_empty():
		start_label.text = "TAP TO HOST GAME"
		session_label.visible = false
	else:
		start_label.text = "TAP TO JOIN SESSION"
		session_label.text = session_id
		session_label.visible = true
	lobby.visible = false
	Network.lobby_updated.connect(_on_lobby_updated)
	Network.session_failed.connect(_on_session_failed)
	Network.game_starting.connect(_on_game_starting)

func _input(event: InputEvent) -> void:
	var is_press: bool = (event is InputEventScreenTouch and event.pressed) or (event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed)
	var is_release: bool = (event is InputEventScreenTouch and not event.pressed) or (event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed)
	if not in_lobby and is_press:
		_open_lobby()
		get_viewport().set_input_as_handled()
	elif in_lobby and is_press:
		if Network.session_connected:
			Network.set_local_ready(true)
	elif in_lobby and is_release:
		if Network.session_connected:
			Network.set_local_ready(false)

func _open_lobby() -> void:
	in_lobby = true
	_request_web_permissions()
	intro.visible = false
	lobby.visible = true
	if session_id.is_empty():
		session_id = Network.tube_create()
		print("Join session link: %s" % _get_join_url(session_id))
	else:
		Network.tube_join(session_id)
	var join_url := _get_join_url(session_id)
	qr_code.data = join_url
	status_label.text = "Connecting..."

func _get_requested_session() -> String:
	if OS.get_name() != "Web":
		return ""
	return str(JavaScriptBridge.eval("new URLSearchParams(window.location.search).get('session') || ''")).strip_edges().to_upper()

func _get_join_url(id: String) -> String:
	if OS.get_name() != "Web":
		return "https://example.com/?session=" + id
	var base_url := str(JavaScriptBridge.eval("window.location.origin + window.location.pathname"))
	return base_url + "?session=" + id.uri_encode()

func _request_web_permissions() -> void:
	if OS.get_name() != "Web":
		return
	JavaScriptBridge.eval("""
		(() => {
			const fullscreenTarget = document.documentElement;
			const requestFullscreen =
				fullscreenTarget.requestFullscreen ||
				fullscreenTarget.webkitRequestFullscreen;
			if (!document.fullscreenElement &&
				!document.webkitFullscreenElement &&
				requestFullscreen) {
				const fullscreenRequest = requestFullscreen.call(fullscreenTarget);
				if (fullscreenRequest && fullscreenRequest.catch)
					fullscreenRequest.catch((error) =>
						console.warn('TwitchSlap fullscreen request:', error));
			}
		})();
		(async () => {
			try {
				if (typeof DeviceMotionEvent !== 'undefined' &&
					typeof DeviceMotionEvent.requestPermission === 'function')
					await DeviceMotionEvent.requestPermission();
				if (typeof DeviceOrientationEvent !== 'undefined' &&
					typeof DeviceOrientationEvent.requestPermission === 'function')
					await DeviceOrientationEvent.requestPermission();
				if ('wakeLock' in navigator)
					window.twitchSlapWakeLock = await navigator.wakeLock.request('screen');
			} catch (error) {
				console.warn('TwitchSlap permission request:', error);
			}
		})();
	""")

func _on_lobby_updated(player_count: int, ready_count: int) -> void:
	players_label.text = "Players ready: %d/%d" % [ready_count, player_count]
	if player_count > 0 and ready_count == player_count:
		status_label.text = "Everyone is ready! Starting..."
	else:
		status_label.text = "Hold your thumb on the screen to ready!"

func _on_session_failed(message: String) -> void:
	status_label.text = "Could not connect: " + message

func _on_game_starting() -> void:
	GameManager.change_state(GameManager.State.Playing)
	get_tree().change_scene_to_packed(main_scene)
