// Farm crops. Each plant grows and ripens over the first minutes of play;
// once your snow reaches its field it wilts, droops, flattens and turns
// brown under a dusting of white. Driven by the shared coverage texture.
//   UV  = plant base (x, z)   UV2 = (random phase, base height)
//   COLOR.rgb = ripe colour   COLOR.a = height fraction along the plant
shader_type spatial;
render_mode cull_disabled, diffuse_lambert_wrap, specular_disabled;

#include "res://shaders/common.gdshaderinc"

uniform float grow_seconds = 420.0;

varying float v_dead;
varying float v_t;
varying float v_snow;
varying float v_grow;

void vertex() {
	vec2 base = UV;
	float phase = UV2.x;
	vec3 b3 = vec3(base.x, UV2.y, base.y);
	vec3 rel = VERTEX - b3;
	float t = COLOR.a;
	float c = wo_cov_smooth(base);
	float dead = smoothstep(0.08, 0.6, c);
	float grow = clamp(0.3 + (TIME + phase * 60.0) / grow_seconds, 0.3, 1.0);
	// Growing plants stretch up; frozen ones slump to a fraction of their height.
	rel.y *= grow * mix(1.0, 0.28, dead);
	rel.xz *= mix(0.55 + 0.45 * grow, 1.25, dead);
	// Wilting tips flop over to one side.
	vec2 droop = vec2(cos(phase * 6.283), sin(phase * 6.283));
	rel.xz += droop * t * t * dead * 0.55 * grow;
	// Living plants sway in the breeze.
	float sway = sin(TIME * 1.6 + base.x * 0.4 + base.y * 0.3 + phase * 2.0) * 0.07 * t * (1.0 - dead);
	rel.x += sway + wo_wind.x * 0.05 * t * (1.0 - dead);
	rel.z += sway * 0.6 + wo_wind.y * 0.05 * t * (1.0 - dead);
	VERTEX = b3 + rel;
	NORMAL = vec3(0.0, 1.0, 0.0);
	v_dead = dead;
	v_t = t;
	v_snow = wo_snow_mask(c, base);
	v_grow = grow;
}

void fragment() {
	vec3 ripe = wo_lin(COLOR.rgb);
	vec3 young = wo_lin(vec3(0.36, 0.62, 0.24));
	vec3 col = mix(young, ripe, smoothstep(0.45, 1.0, v_grow));
	col *= 0.75 + 0.25 * v_t;
	vec3 dead_c = wo_lin(vec3(0.40, 0.31, 0.21)) * (0.8 + 0.2 * v_t);
	col = mix(col, dead_c, v_dead * 0.9);
	vec3 snow = wo_lin(vec3(0.93, 0.95, 1.0));
	col = mix(col, snow, v_snow * (0.3 + 0.6 * v_t));
	ALBEDO = col;
	ROUGHNESS = 0.9;
}
