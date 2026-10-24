// Shared WHITEOUT shader helpers.
// The world textures are global shader parameters registered by ShaderLib.

global uniform sampler2D wo_height : filter_linear, repeat_disable;
global uniform sampler2D wo_water : filter_linear, repeat_disable;
global uniform sampler2D wo_coverage : filter_linear, repeat_disable;
global uniform float wo_completion;
global uniform vec4 wo_thaw;      // xy = centre (x, z), z = pulse radius, w = strength
global uniform vec2 wo_wind;

const float WO_HALF = 256.0;

// Palette values in this project are authored in sRGB; albedo wants linear.
vec3 wo_lin(vec3 c) {
	return pow(max(c, vec3(0.0)), vec3(2.2));
}

float wo_terrain_height(vec2 xz) {
	return textureLod(wo_height, (xz + WO_HALF + 0.5) / 513.0, 0.0).r;
}

float wo_water_level(vec2 xz) {
	return textureLod(wo_water, (xz + WO_HALF + 0.5) / 513.0, 0.0).r;
}

float wo_surface_height(vec2 xz) {
	return max(wo_terrain_height(xz), wo_water_level(xz));
}

float wo_cov(vec2 xz) {
	return textureLod(wo_coverage, (xz + WO_HALF) / 512.0, 0.0).r;
}

float wo_hash(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float wo_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	float a = wo_hash(i);
	float b = wo_hash(i + vec2(1.0, 0.0));
	float c = wo_hash(i + vec2(0.0, 1.0));
	float d = wo_hash(i + vec2(1.0, 1.0));
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

float wo_fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int k = 0; k < 4; k++) {
		v += a * wo_noise(p);
		p = p * 2.03 + vec2(17.1, 9.2);
		a *= 0.5;
	}
	return v / 0.9375;
}

// Smooth noise sampled on a rotated, offset lattice so no pattern lines up
// with the 1 m coverage grid or the world axes.
float wo_rnoise(vec2 p) {
	return wo_noise(mat2(vec2(0.8, 0.6), vec2(-0.6, 0.8)) * p + vec2(3.7, 1.3));
}

float wo_rfbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	mat2 r = mat2(vec2(0.8, 0.6), vec2(-0.6, 0.8));
	for (int k = 0; k < 4; k++) {
		v += a * wo_noise(p);
		p = r * p * 2.03 + vec2(17.1, 9.2);
		a *= 0.5;
	}
	return v / 0.9375;
}

// Cubic B-spline sampling of the coverage grid (four bilinear taps): the
// 1 m cells blend into smooth, round shapes instead of squares and lines.
float wo_cov_smooth(vec2 xz) {
	vec2 tc = xz + WO_HALF - 0.5;
	vec2 f = fract(tc);
	vec2 i = floor(tc);
	vec2 f2 = f * f;
	vec2 f3 = f2 * f;
	vec2 w0 = (1.0 - f) * (1.0 - f) * (1.0 - f) / 6.0;
	vec2 w1 = (4.0 - 6.0 * f2 + 3.0 * f3) / 6.0;
	vec2 w2 = (1.0 + 3.0 * f + 3.0 * f2 - 3.0 * f3) / 6.0;
	vec2 w3 = f3 / 6.0;
	vec2 g0 = w0 + w1;
	vec2 g1 = w2 + w3;
	vec2 h0 = (w1 / g0) - 1.0 + i + 0.5;
	vec2 h1 = (w3 / g1) + 1.0 + i + 0.5;
	float a = textureLod(wo_coverage, vec2(h0.x, h0.y) / 512.0, 0.0).r;
	float b = textureLod(wo_coverage, vec2(h1.x, h0.y) / 512.0, 0.0).r;
	float c = textureLod(wo_coverage, vec2(h0.x, h1.y) / 512.0, 0.0).r;
	float d = textureLod(wo_coverage, vec2(h1.x, h1.y) / 512.0, 0.0).r;
	return g0.y * (g0.x * a + g1.x * b) + g1.y * (g0.x * c + g1.x * d);
}

// Coverage with an organic wobble along snow edges: a broad meander plus a
// finer ripple, so even a perfectly straight pass never leaves a ruled line.
float wo_cov_warped(vec2 xz) {
	vec2 broad = vec2(wo_rfbm(xz * 0.05), wo_rfbm(xz * 0.05 + 47.3)) - 0.5;
	vec2 mid = vec2(wo_rfbm(xz * 0.16 + 9.1), wo_rfbm(xz * 0.16 + 21.7)) - 0.5;
	vec2 fine = vec2(wo_rnoise(xz * 0.5), wo_rnoise(xz * 0.5 + 31.7)) - 0.5;
	return wo_cov_smooth(xz + broad * 2.8 + mid * 1.4 + fine * 0.7);
}

// Maps coverage 0..1 to a visible snow mask with natural patchy accumulation.
// Coverage >= 0.97 is always fully white, so "looks frozen" == "is frozen".
// Snow edges fade in from nothing with zero slope, so the boundary between
// snow and grass is always a soft, irregular blend - never a drawn line.
float wo_snow_mask(float c, vec2 xz) {
	float s = clamp((c - 0.02) / 0.95, 0.0, 1.0);
	float n = wo_rfbm(xz * 0.18) - 0.5;
	float m = clamp(s + n * 0.3 * s * (1.0 - s) * 4.0, 0.0, 1.0);
	return m * m * (3.0 - 2.0 * m);
}

vec3 wo_snow_color(vec3 world_normal, vec2 xz) {
	float up = clamp(world_normal.y, 0.0, 1.0);
	vec3 shade = mix(wo_lin(vec3(0.80, 0.87, 0.97)), wo_lin(vec3(0.97, 0.98, 1.0)), smoothstep(0.55, 0.98, up));
	float drift = wo_rfbm(xz * 0.045);
	shade *= 0.97 + 0.04 * drift;
	return shade;
}

// Thaw Sense: a warm glow on unfrozen ground near the expanding pulse front.
float wo_thaw_glow(vec2 xz) {
	if (wo_thaw.w <= 0.0) {
		return 0.0;
	}
	float d = distance(xz, wo_thaw.xy);
	float ring = exp(-pow((d - wo_thaw.z) / 9.0, 2.0));
	float inside = step(d, wo_thaw.z);
	return wo_thaw.w * (ring * 1.4 + inside * 0.35);
}
