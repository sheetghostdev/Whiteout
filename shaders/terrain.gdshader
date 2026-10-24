// Terrain: summer ground colour (from vertex colours) blended with snow
// driven by the authoritative coverage texture.
shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

#include "res://shaders/common.gdshaderinc"

uniform float sparkle_strength = 0.9;

varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float c = wo_cov_smooth(wpos.xz);
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
	// Snow reaches the waterline but not the sea floor seen through the water.
	float m = wo_snow_mask(c, xz) * smoothstep(-0.9, -0.15, wpos.y);
	vec3 snow = wo_snow_color(wn, xz);
	// Soft, irregular drift undulations tilt the snow normal very slightly.
	float rx = wo_rfbm(xz * 0.12 + vec2(0.6, 0.0)) - wo_rfbm(xz * 0.12 - vec2(0.6, 0.0));
	float rz = wo_rfbm(xz * 0.12 + vec2(0.0, 0.6)) - wo_rfbm(xz * 0.12 - vec2(0.0, 0.6));
	vec3 sn = normalize(wn + vec3(rx, 0.0, rz) * 0.18);
	snow *= 0.97 + 0.05 * sn.y;
	// Faint cool tint where snow is thin.
	float edge = m * (1.0 - m) * 2.0;

	vec3 col = mix(summer, snow, m);
	col = mix(col, wo_lin(vec3(0.82, 0.90, 1.0)), edge * 0.25);
	ALBEDO = col;
	ROUGHNESS = mix(0.93, 0.72, m);
	SPECULAR = mix(0.18, 0.42, m);
	NORMAL = normalize(mix(NORMAL, (VIEW_MATRIX * vec4(sn, 0.0)).xyz, m));

	// ---- sparkles: tiny view-dependent glints on fully covered snow
	vec2 cell = floor(mat2(vec2(0.8, 0.6), vec2(-0.6, 0.8)) * xz * 5.0);
	float h = wo_hash(cell);
	vec3 vw = normalize((INV_VIEW_MATRIX * vec4(VIEW, 0.0)).xyz);
	float glint = pow(max(0.0, sin(h * 91.0 + dot(vw, vec3(9.0, 5.0, 7.0)) * 2.4)), 48.0) * step(0.93, h);
	EMISSION = vec3(1.0, 0.98, 0.94) * glint * m * sparkle_strength;

	// ---- thaw sense
	float tg = wo_thaw_glow(xz) * (1.0 - m);
	EMISSION += vec3(1.0, 0.52, 0.16) * tg * 0.8;

	// ---- late game: the last green ground glows softly so it is easy to spot
	float late = smoothstep(0.8, 0.95, wo_completion);
	float pulse = 0.6 + 0.4 * sin(TIME * 2.2);
	EMISSION += vec3(1.0, 0.62, 0.22) * (1.0 - m) * late * pulse * 0.22;
}
