// Lakes and rivers. Water depth comes from the global height texture, so no
// screen-space reads are needed. Coverage turns the surface into ice.
shader_type spatial;
render_mode blend_mix, depth_draw_always, cull_back, diffuse_burley, specular_schlick_ggx;

#include "res://shaders/common.gdshaderinc"

uniform vec3 shallow_color : source_color = vec3(0.36, 0.80, 0.78);
uniform vec3 deep_color : source_color = vec3(0.06, 0.36, 0.60);
uniform vec3 ice_color : source_color = vec3(0.72, 0.89, 0.95);
uniform float flow_speed = 0.0;
uniform vec2 flow_dir = vec2(0.0, 1.0);

varying vec3 wpos;
varying float ice_v;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float c = wo_cov(wpos.xz);
	ice_v = c;
	float calm = 1.0 - smoothstep(0.2, 0.9, c);
	float wave = sin(wpos.x * 0.35 + TIME * 1.1) * cos(wpos.z * 0.28 + TIME * 0.8);
	VERTEX.y += wave * 0.035 * calm;
}

float ice_cracks(vec2 p) {
	// Cheap cellular pattern: distance to nearest jittered point.
	vec2 i = floor(p);
	vec2 f = fract(p);
	float d1 = 8.0;
	float d2 = 8.0;
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 g = vec2(float(x), float(y));
			vec2 o = vec2(wo_hash(i + g), wo_hash(i + g + 17.3));
			float d = length(g + o - f);
			if (d < d1) { d2 = d1; d1 = d; } else if (d < d2) { d2 = d; }
		}
	}
	return smoothstep(0.0, 0.08, d2 - d1);
}

void fragment() {
	vec2 xz = wpos.xz;
	float ground = wo_terrain_height(xz);
	float depth = max(wpos.y - ground, 0.0);

	// ---- liquid water
	vec2 flow = flow_dir * flow_speed * TIME;
	float n1 = wo_noise(xz * 0.45 + vec2(TIME * 0.12, TIME * 0.07) - flow);
	float n2 = wo_noise(xz * 0.9 - vec2(TIME * 0.09, -TIME * 0.11) - flow * 1.3);
	vec3 wn = normalize(vec3((n1 - 0.5) * 0.35, 1.0, (n2 - 0.5) * 0.35));
	vec3 vw = normalize((INV_VIEW_MATRIX * vec4(VIEW, 0.0)).xyz);
	float fres = pow(1.0 - clamp(dot(vw, wn), 0.0, 1.0), 4.0);
	vec3 water = mix(shallow_color, deep_color, smoothstep(0.2, 3.5, depth));
	water = mix(water, vec3(0.70, 0.84, 0.96), fres * 0.55);
	float foam = (1.0 - smoothstep(0.05, 0.45, depth)) * (0.55 + 0.45 * wo_noise(xz * 2.0 + TIME * 0.3));
	water = mix(water, vec3(0.92, 0.97, 1.0), foam * 0.6);
	float water_alpha = mix(0.55, 0.92, smoothstep(0.1, 2.5, depth));

	// ---- ice
	float c = wo_cov_warped(xz);
	float n = wo_fbm(xz * 0.3) * 0.7 + wo_noise(xz * 1.7) * 0.3;
	float s = clamp((c - 0.02) / 0.95, 0.0, 1.0);
	float ice = smoothstep(n * 0.88, n * 0.88 + 0.1, s);
	float crack = ice_cracks(xz * 0.35);
	vec3 icec = ice_color * (0.92 + 0.12 * wo_fbm(xz * 0.8));
	icec = mix(icec * 0.82, icec, crack);
	// A dusting of snow settles once the whole surface is frozen.
	float dust = smoothstep(0.985, 1.0, c) * smoothstep(0.35, 0.75, wo_fbm(xz * 0.25 + 7.0));
	icec = mix(icec, vec3(0.95, 0.97, 1.0), dust * 0.85);

	vec3 col = mix(water, icec, ice);
	ALBEDO = col;
	ALPHA = mix(water_alpha, 1.0, ice);
	ROUGHNESS = mix(0.06, mix(0.18, 0.75, dust), ice);
	SPECULAR = mix(0.6, 0.45, ice);
	NORMAL = normalize(mix((VIEW_MATRIX * vec4(wn, 0.0)).xyz, NORMAL, ice));
	float tg = wo_thaw_glow(xz) * (1.0 - ice);
	EMISSION = vec3(1.0, 0.52, 0.16) * tg * 0.6;
}
