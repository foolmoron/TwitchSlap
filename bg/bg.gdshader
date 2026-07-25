shader_type canvas_item;

uniform vec4 color_a : source_color = vec4(0.035, 0.008, 0.12, 1.0);
uniform vec4 color_b : source_color = vec4(0.95, 0.08, 0.55, 1.0);
uniform vec4 color_c : source_color = vec4(0.05, 0.75, 1.0, 1.0);

uniform float rotation_speed : hint_range(-30.0, 30.0, 0.1) = 0.35;
uniform float arms : hint_range(1.0, 12.0, 1.0) = 5.0;
uniform float twist : hint_range(1.0, 200.0, 1) = 9.0;
uniform float softness : hint_range(0.01, 0.49, 0.01) = 0.18;
uniform float thickness : hint_range(0.01, 1.0, 0.01) = 0.1;
uniform float scale : hint_range(0.25, 4.0, 0.01) = 1.0;

void fragment() {
	// Keep a full-screen ColorRect circular at any viewport aspect ratio.
	float aspect_ratio = SCREEN_PIXEL_SIZE.y / SCREEN_PIXEL_SIZE.x;
	vec2 uv = (UV - 0.5) * vec2(aspect_ratio, 1.0) * scale;

	float radius = length(uv);
	float angle = atan(uv.y, uv.x);
	float phase = angle * arms - radius * twist - TIME * rotation_speed * arms;

	// Rounded bands form the spiral arms.
	float wave = 0.5 + 0.5 * cos(phase);
	float spiral = smoothstep((1.0-thickness) - softness, (1.0-thickness) + softness, wave);
	vec3 spiral_color = mix(color_b.rgb, color_c.rgb, 0.5 + 0.5 * sin(phase * 0.5));
	vec3 color = mix(color_a.rgb, spiral_color, spiral);

	COLOR = vec4(color, 1.0);
}
