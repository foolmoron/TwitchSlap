shader_type canvas_item;

uniform vec4 background_color : source_color = vec4(0.035, 0.008, 0.12, 1.0);
uniform vec4 spiral_color : source_color = vec4(0.95, 0.08, 0.55, 1.0);
uniform vec4 border_color : source_color = vec4(0.0, 0.0, 0.0, 1.0);

uniform float rotation_speed : hint_range(-30.0, 30.0, 0.1) = 0.35;
uniform float arms : hint_range(1.0, 12.0, 1.0) = 5.0;
uniform float twist : hint_range(1.0, 200.0, 1) = 9.0;
uniform float softness : hint_range(0.01, 0.49, 0.01) = 0.18;
uniform float thickness : hint_range(0.01, 1.0, 0.01) = 0.1;
uniform float border_thickness : hint_range(0.0, 0.5, 0.01) = 0.1;
uniform float scale : hint_range(0.25, 4.0, 0.01) = 1.0;
uniform float drain : hint_range(0.0, 1.0, 0.01) = 0.0;

void fragment() {
	// Keep a full-screen ColorRect circular at any viewport aspect ratio.
	float aspect_ratio = SCREEN_PIXEL_SIZE.y / SCREEN_PIXEL_SIZE.x;
	vec2 uv = (UV - 0.5) * vec2(aspect_ratio, 1.0) * scale;

	float radius = length(uv);
	float angle = atan(uv.y, uv.x);
	float phase = angle * arms - radius * twist - TIME * rotation_speed * arms;

	// Draw a wider black mask underneath each spiral arm.
	float wave = 0.5 + 0.5 * cos(phase);
	float arm_edge = 1.0 - thickness;
	float spiral_mask = smoothstep(arm_edge - softness, arm_edge + softness, wave);
	float border_edge = arm_edge - border_thickness;
	float border_mask = smoothstep(border_edge - softness, border_edge + softness, wave);

	// Draining arms
	float arm_radius = length(vec2(aspect_ratio, 1.0) * 0.5 * scale) * (1.0 - drain);
	float arm_offset = mod(phase + PI, 2.0 * PI) - PI;
	float arm_cutoff = arm_radius - arm_radius * arm_radius * twist * arm_offset / (arms * arms + arm_radius * arm_radius * twist * twist);

	float border_drain = max(0.0, min(1.0, drain * 0.998));
	float border_radius = length(vec2(aspect_ratio, 1.0) * 0.5 * scale) * (1.0 - border_drain);
	float border_cutoff = border_radius - border_radius * border_radius * twist * arm_offset / (arms * arms + border_radius * border_radius * twist * twist);

	border_mask *= 1.0 - step(border_cutoff, radius);
	spiral_mask *= 1.0 - step(arm_cutoff, radius);

	vec4 color = mix(background_color, border_color, border_mask);
	color = mix(color, spiral_color, spiral_mask);
	COLOR = color;
}
