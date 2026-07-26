extends Node

signal hit_detected

# Minimum acceleration needed for a hit, in m/s²; typically 3.0–15.0.
const ACCEL_THRESHOLD := 2.5
# Minimum estimated travel needed for a hit, in meters; typically 0.005–0.05.
const DISTANCE_THRESHOLD := 0.009
# Time at rest before the same direction can hit again, in seconds; typically 0.1–0.5.
const REST_TIME := 0.10
# Maximum direction dot product treated as a reversal, unitless; range -1.0–1.0.
const REVERSE_DOT_THRESHOLD := 0.75
# Maximum acceleration considered at rest, in m/s²; typically 0.5–2.5.
const REST_ACCEL_THRESHOLD := 0.75
# Maximum motion-event interval used for integration, in seconds; typically 0.02–0.1.
const MAX_SAMPLE_TIME := 0.05

var _is_web := false

func _ready() -> void:
	_is_web = OS.get_name() == "Web"
	if not _is_web:
		return

	var values := [
		ACCEL_THRESHOLD,
		DISTANCE_THRESHOLD,
		REST_TIME,
		REVERSE_DOT_THRESHOLD,
		REST_ACCEL_THRESHOLD,
		MAX_SAMPLE_TIME,
	]
	JavaScriptBridge.eval("""
		(() => {
			if (window.__twitchSlapMotion) return;

			const state = window.__twitchSlapMotion = {
				didHit: false,
				listening: false,
				armed: true,
				restTime: 0,
				velocity: { x: 0, y: 0, z: 0 },
				distance: { x: 0, y: 0, z: 0 },
				direction: null,
				gravity: { x: 0, y: 0, z: 0 },
			};

			const ACCEL_THRESHOLD = %s;
			const DISTANCE_THRESHOLD = %s;
			const REST_TIME = %s;
			const REVERSE_DOT_THRESHOLD = %s;
			const REST_ACCEL_THRESHOLD = %s;
			const MAX_SAMPLE_TIME = %s;

			const clearMovement = () => {
				state.velocity.x = state.velocity.y = state.velocity.z = 0;
				state.distance.x = state.distance.y = state.distance.z = 0;
			};

			const onMotion = (event) => {
				let source = event.acceleration;
				let x;
				let y;
				let z;

				if (source && source.x != null) {
					x = source.x || 0;
					y = source.y || 0;
					z = source.z || 0;
				} else {
					// Some browsers only expose acceleration including gravity.
					source = event.accelerationIncludingGravity;
					if (!source || source.x == null) return;
					const smoothing = 0.82;
					state.gravity.x = smoothing * state.gravity.x + (1 - smoothing) * (source.x || 0);
					state.gravity.y = smoothing * state.gravity.y + (1 - smoothing) * (source.y || 0);
					state.gravity.z = smoothing * state.gravity.z + (1 - smoothing) * (source.z || 0);
					x = (source.x || 0) - state.gravity.x;
					y = (source.y || 0) - state.gravity.y;
					z = (source.z || 0) - state.gravity.z;
				}

				const dt = Math.min(MAX_SAMPLE_TIME, Math.max(0.001, (event.interval || 16) / 1000));
				const magnitude = Math.hypot(x, y, z);

				if (magnitude <= REST_ACCEL_THRESHOLD) {
					state.restTime += dt;
					state.velocity.x *= 0.55;
					state.velocity.y *= 0.55;
					state.velocity.z *= 0.55;
					if (state.restTime >= REST_TIME) {
						state.armed = true;
						state.direction = null;
						clearMovement();
					}
					return;
				}

				state.restTime = 0;
				if (magnitude < ACCEL_THRESHOLD) return;

				const direction = { x: x / magnitude, y: y / magnitude, z: z / magnitude };
				if (state.direction) {
					const dot = direction.x * state.direction.x
						+ direction.y * state.direction.y
						+ direction.z * state.direction.z;
					if (dot <= REVERSE_DOT_THRESHOLD) {
						// A shake back in a genuinely new direction is a new motion.
						state.armed = true;
						clearMovement();
					}
				}

				state.velocity.x += x * dt;
				state.velocity.y += y * dt;
				state.velocity.z += z * dt;
				state.distance.x += state.velocity.x * dt;
				state.distance.y += state.velocity.y * dt;
				state.distance.z += state.velocity.z * dt;

				if (state.armed && Math.hypot(
					state.distance.x, state.distance.y, state.distance.z
				) >= DISTANCE_THRESHOLD) {
					state.didHit = true;
					state.armed = false;
					state.direction = direction;
					clearMovement();
				}
			};

			const startListening = () => {
				if (state.listening) return;
				window.addEventListener("devicemotion", onMotion, { passive: true });
				state.listening = true;
			};

			const requestAndStart = () => {
				if (typeof DeviceMotionEvent !== "undefined"
					&& typeof DeviceMotionEvent.requestPermission === "function") {
					DeviceMotionEvent.requestPermission().then((permission) => {
						if (permission === "granted") startListening();
					}).catch(() => {});
				} else {
					startListening();
				}
			};

			// iOS requires the permission request to occur during a user gesture.
			window.addEventListener("pointerdown", requestAndStart, { once: true, passive: true });
			startListening();
		})();
	""" % values)


func _process(_delta: float) -> void:
	if not _is_web:
		return

	var did_hit = JavaScriptBridge.eval("""
		(() => {
			const motion = window.__twitchSlapMotion;
			if (!motion) return false;
			const didHit = motion.didHit;
			motion.didHit = false;
			return didHit;
		})()
	""")
	if did_hit == true:
		hit_detected.emit()
		if GameManager.state == GameManager.State.Playing:
			GameManager.do_hit()
