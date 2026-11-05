// Soft stylised cumulus puffs. Opaque with dithered fades: no sorting,
// little overdraw. Each puff's surface boils slowly with animated noise,
// anything below the cloud base is pressed flat (a cumulus has a flat grey
// underside), the sunlit top stays bright with a silver lining at the edges,
// and light glows through thin parts.
shader_type spatial;
render_mode diffuse_lambert_wrap, specular_disabled, cull_back, world_vertex_coords;

#include "res://shaders/common.gdshaderinc"

uniform float fade : hint_range(0.0, 1.0) = 1.0;
uniform vec3 tint : source_color = vec3(1.0, 1.0, 1.0);
uniform float darkness = 0.0;
uniform float near_fade = 6.0;
uniform float boil = 1.0;            // how strongly the surface billows
uniform float base_y = -10000.0;     // world height of the flat cloud base
uniform float flash = 0.0;           // lightning inside the cloud
instance uniform float puff_seed = 0.0;
instance uniform float puff_fade = 1.0;

varying float v_base;
varying vec3 v_wpos;

void vertex() {
	float size = length(MODEL_MATRIX[0].xyz);
	// Boiling: two layers of smooth noise drifting over the surface (in the
	// puff's own frame, so the pattern travels with the cloud).
	vec3 lp = (VERTEX - MODEL_MATRIX[3].xyz) / max(size, 0.01);
	vec2 q = lp.xz * 1.4 + vec2(lp.y * 0.9, 0.0);
	float n1 = wo_noise(q + vec2(TIME * 0.32 + puff_seed * 7.3, -TIME * 0.21)) - 0.5;
	float n2 = wo_noise(q * 2.3 + vec2(-TIME * 0.45, TIME * 0.37 + puff_seed * 3.1)) - 0.5;
	VERTEX += NORMAL * (n1 * 0.16 + n2 * 0.07) * size * boil;
	// A flat, slightly lumpy base.
	if (VERTEX.y < base_y) {
		VERTEX.y = base_y - (base_y - VERTEX.y) * 0.22;
		NORMAL = normalize(mix(NORMAL, vec3(0.0, -1.0, 0.0), 0.7));
	}
	v_base = clamp((VERTEX.y - base_y) / max(size * 1.6, 0.01), 0.0, 1.0);
	v_wpos = VERTEX;
}

float bayer4(vec2 p) {
	ivec2 i = ivec2(mod(p, 4.0));
	int idx = i.x + i.y * 4;
	float m[16] = float[16](0.0, 8.0, 2.0, 10.0, 12.0, 4.0, 14.0, 6.0, 3.0, 11.0, 1.0, 9.0, 15.0, 7.0, 13.0, 5.0);
	return (m[idx] + 0.5) / 16.0;
}

void fragment() {
	float cam_d = distance(v_wpos, CAMERA_POSITION_WORLD);
	float vis = fade * puff_fade * smoothstep(near_fade * 0.4, near_fade, cam_d);
	if (vis < bayer4(FRAGCOORD.xy)) {
		discard;
	}
	vec3 col = wo_lin(COLOR.rgb) * tint;
	// The underside is a flatter, cooler grey; the top stays white.
	float under = 1.0 - smoothstep(0.0, 0.55, v_base);
	col = mix(col, col * vec3(0.66, 0.71, 0.82), under * 0.65);
	col = mix(col, col * vec3(0.60, 0.65, 0.78), darkness);
	ALBEDO = col;
	ROUGHNESS = 1.0;
	BACKLIGHT = vec3(0.42) * (1.0 - darkness * 0.5);
	RIM = 0.55;
	RIM_TINT = 0.75;
	// Silver lining on edges seen side-on, strongest on the sunlit top.
	float edge = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	EMISSION = vec3(1.0, 0.98, 0.94) * edge * 0.22 * (1.0 - darkness * 0.7) * (0.4 + 0.6 * v_base);
	// Lightning lights the cloud from inside, brightest low down.
	EMISSION += vec3(0.80, 0.86, 1.0) * flash * (0.6 + 0.8 * under);
}
