// Terrain: summer ground colour (from vertex colours) blended with snow
// driven by the authoritative coverage texture.
shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

#include "res://shaders/common.gdshaderinc"

uniform float sparkle_strength = 0.9;

varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float c = wo_cov(wpos.xz);
	// A thin snow layer lifts the surface slightly once ground is well covered.
	VERTEX.y += smoothstep(0.35, 1.0, c) * 0.12;
}

void fragment() {
	vec3 wn = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	vec2 xz = wpos.xz;

	// ---- summer ground
	vec3 base = wo_lin(COLOR.rgb);
	float n_big = wo_fbm(xz * 0.035);
	float n_mid = wo_fbm(xz * 0.22);
	float n_fine = wo_noise(xz * 3.1);
	vec3 summer = base * (0.86 + 0.22 * n_mid + 0.08 * n_big);
	summer += vec3(0.012, 0.010, -0.004) * (n_big - 0.5);
	summer *= 0.95 + 0.08 * n_fine;
	// Slight darkening in creases for depth.
	summer *= mix(0.86, 1.0, smoothstep(0.55, 0.95, wn.y));

	// ---- snow
	float c = wo_cov_warped(xz);
	float m = wo_snow_mask(c, xz);
	vec3 snow = wo_snow_color(wn, xz);
	// Soft drift ripples tilt the snow normal a little.
	float rx = wo_noise(xz * 0.6 + vec2(0.3, 0.0)) - wo_noise(xz * 0.6 - vec2(0.3, 0.0));
	float rz = wo_noise(xz * 0.6 + vec2(0.0, 0.3)) - wo_noise(xz * 0.6 - vec2(0.0, 0.3));
	vec3 sn = normalize(wn + vec3(rx, 0.0, rz) * 0.35);
	snow *= 0.97 + 0.05 * sn.y;
	// Cool rim along the snow edge reads clearly from far away.
	float edge = m * (1.0 - m) * 4.0;

	vec3 col = mix(summer, snow, m);
	col = mix(col, wo_lin(vec3(0.82, 0.90, 1.0)), edge * 0.25);
	ALBEDO = col;
	ROUGHNESS = mix(0.93, 0.72, m);
	SPECULAR = mix(0.18, 0.42, m);
	NORMAL = normalize(mix(NORMAL, (VIEW_MATRIX * vec4(sn, 0.0)).xyz, m));

	// ---- sparkles: tiny view-dependent glints on fully covered snow
	vec2 cell = floor(xz * 5.0);
	float h = wo_hash(cell);
	vec3 vw = normalize((INV_VIEW_MATRIX * vec4(VIEW, 0.0)).xyz);
	float glint = pow(max(0.0, sin(h * 91.0 + dot(vw, vec3(9.0, 5.0, 7.0)) * 2.4)), 48.0) * step(0.93, h);
	EMISSION = vec3(1.0, 0.98, 0.94) * glint * m * sparkle_strength;

	// ---- thaw sense
	float tg = wo_thaw_glow(xz) * (1.0 - m);
	EMISSION += vec3(1.0, 0.52, 0.16) * tg * 0.8;
}
