// Wisps shed by the cloud: small soft puffs that thin out with real
// transparency (they are few and small, so sorting is no problem).
shader_type spatial;
render_mode diffuse_lambert_wrap, specular_disabled, cull_back, depth_draw_never, world_vertex_coords;

#include "res://shaders/common.gdshaderinc"

uniform vec3 tint : source_color = vec3(1.0, 1.0, 1.0);
uniform float darkness = 0.0;
instance uniform float puff_fade = 1.0;

void vertex() {
	float size = length(MODEL_MATRIX[0].xyz);
	vec3 lp = (VERTEX - MODEL_MATRIX[3].xyz) / max(size, 0.01);
	float n = wo_noise(lp.xz * 1.6 + vec2(TIME * 0.5, lp.y)) - 0.5;
	VERTEX += NORMAL * n * 0.25 * size;
}

void fragment() {
	vec3 col = wo_lin(COLOR.rgb) * tint;
	col = mix(col, col * vec3(0.62, 0.67, 0.80), darkness);
	ALBEDO = col;
	ROUGHNESS = 1.0;
	BACKLIGHT = vec3(0.4);
	// Soft edges: thinner where the surface is seen side-on.
	float facing = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	ALPHA = puff_fade * smoothstep(0.0, 0.6, facing) * 0.75;
}
