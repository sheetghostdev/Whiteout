// Soft stylised clouds. Opaque with dithered fades: no sorting, little overdraw.
shader_type spatial;
render_mode diffuse_lambert_wrap, specular_disabled, cull_back;

#include "res://shaders/common.gdshaderinc"

uniform float fade : hint_range(0.0, 1.0) = 1.0;
uniform vec3 tint : source_color = vec3(1.0, 1.0, 1.0);
uniform float darkness = 0.0;
uniform float near_fade = 6.0;

varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	// Gentle billowing.
	float b = sin(TIME * 0.7 + VERTEX.x * 3.0 + VERTEX.z * 2.0) * 0.025;
	VERTEX += NORMAL * b;
}

float bayer4(vec2 p) {
	ivec2 i = ivec2(mod(p, 4.0));
	int idx = i.x + i.y * 4;
	float m[16] = float[16](0.0, 8.0, 2.0, 10.0, 12.0, 4.0, 14.0, 6.0, 3.0, 11.0, 1.0, 9.0, 15.0, 7.0, 13.0, 5.0);
	return (m[idx] + 0.5) / 16.0;
}

void fragment() {
	float cam_d = distance(wpos, CAMERA_POSITION_WORLD);
	float vis = fade * smoothstep(near_fade * 0.4, near_fade, cam_d);
	if (vis < bayer4(FRAGCOORD.xy)) {
		discard;
	}
	vec3 col = wo_lin(COLOR.rgb) * tint;
	col = mix(col, col * vec3(0.62, 0.68, 0.80), darkness);
	ALBEDO = col;
	ROUGHNESS = 1.0;
	BACKLIGHT = vec3(0.35);
	RIM = 0.4;
	RIM_TINT = 0.6;
}
