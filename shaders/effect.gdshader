// Weather visual effects on procedural geometry (no textures):
// mode 0 frost-front curtain, 1 vortex spiral, 2 beacon column, 3 wind streak, 4 funnel.
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_mix;

#include "res://shaders/common.gdshaderinc"

uniform int mode = 0;
uniform vec4 color : source_color = vec4(0.9, 0.96, 1.0, 0.8);
uniform float fade = 1.0;
uniform float speed = 1.0;
uniform bool follow_terrain = false;
uniform float terrain_lift = 0.0;
uniform float height_scale = 1.0;

varying vec2 luv;

void vertex() {
	luv = UV;
	if (follow_terrain) {
		vec3 w = (MODEL_MATRIX * vec4(VERTEX.x, 0.0, VERTEX.z, 1.0)).xyz;
		float h = wo_surface_height(w.xz) + terrain_lift;
		float local_y = VERTEX.y * height_scale;
		vec3 world = vec3(w.x, h + local_y, w.z);
		VERTEX = (inverse(MODEL_MATRIX) * vec4(world, 1.0)).xyz;
	}
}

void fragment() {
	float a = 0.0;
	vec3 col = color.rgb;
	if (mode == 0) {
		// Frost-front curtain: dense at the ground, wispy at the top, shimmering edge.
		float n = wo_fbm(vec2(luv.x * 7.0 + TIME * 0.4, luv.y * 3.0 - TIME * 1.6 * speed));
		float body = (1.0 - smoothstep(0.1, 0.95, luv.y + n * 0.35));
		float sides = smoothstep(0.0, 0.12, luv.x) * (1.0 - smoothstep(0.88, 1.0, luv.x));
		float shimmer = pow(n, 3.0) * 1.4;
		a = body * sides * (0.55 + shimmer);
		col = mix(col, vec3(1.0), shimmer * 0.5);
	} else if (mode == 1) {
		float along = luv.x;
		float across = abs(luv.y * 2.0 - 1.0);
		float n = wo_fbm(vec2(along * 9.0 - TIME * 0.5 * speed, luv.y * 2.0));
		a = (1.0 - smoothstep(0.3, 1.0, across)) * smoothstep(0.0, 0.12, along) * (1.0 - smoothstep(0.75, 1.0, along));
		a *= 0.45 + 0.75 * n;
	} else if (mode == 2) {
		float pulse = 0.65 + 0.35 * sin(TIME * 3.0 + luv.y * 6.0);
		a = (1.0 - luv.y) * (1.0 - luv.y) * pulse;
		float stripes = 0.6 + 0.4 * sin(luv.x * 40.0 + TIME * 2.0);
		a *= stripes;
	} else if (mode == 3) {
		// Wind streak ribbon: uv.y runs along the gust, uv.x across it.
		float n = wo_noise(vec2(luv.x * 1.5, luv.y * 3.0));
		float streak = fract(luv.y * 2.0 - TIME * speed + n * 0.3);
		float s = smoothstep(0.0, 0.2, streak) * (1.0 - smoothstep(0.35, 0.6, streak));
		float across = abs(luv.x * 2.0 - 1.0);
		a = s * (1.0 - smoothstep(0.2, 1.0, across));
		a *= smoothstep(0.0, 0.08, luv.y) * (1.0 - smoothstep(0.85, 1.0, luv.y));
	} else {
		float n = wo_fbm(vec2(luv.x * 8.0 + luv.y * 3.0 - TIME * speed, luv.y * 4.0));
		a = (0.25 + 0.75 * n) * smoothstep(0.0, 0.25, luv.y) * (1.0 - smoothstep(0.75, 1.0, luv.y));
	}
	ALBEDO = col;
	ALPHA = clamp(a * color.a * fade, 0.0, 1.0);
}
