shader_type canvas_item;

uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_nearest;

void fragment() {
	vec4 color = texture(screen_texture, SCREEN_UV);
	float lum = dot(color.rgb, vec3(0.299, 0.587, 0.114));
	COLOR = vec4(vec3(lum), color.a);
}
