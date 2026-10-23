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

// Coverage with a small organic domain warp so the 1 m cells never read as squares.
float wo_cov_warped(vec2 xz) {
	vec2 w = vec2(wo_noise(xz * 0.7), wo_noise(xz * 0.7 + 31.7)) - 0.5;
	return wo_cov(xz + w * 0.9);
}

// Maps coverage 0..1 to a visible snow mask with natural patchy accumulation.
// Coverage >= 0.97 is always fully white, so "looks frozen" == "is frozen".
float wo_snow_mask(float c, vec2 xz) {
	float s = clamp((c - 0.02) / 0.95, 0.0, 1.0);
	float n = wo_fbm(xz * 0.42) * 0.72 + wo_noise(xz * 2.1) * 0.28;
	return smoothstep(n * 0.88, n * 0.88 + 0.12, s);
}

vec3 wo_snow_color(vec3 world_normal, vec2 xz) {
	float up = clamp(world_normal.y, 0.0, 1.0);
	vec3 shade = mix(wo_lin(vec3(0.80, 0.87, 0.97)), wo_lin(vec3(0.97, 0.98, 1.0)), smoothstep(0.55, 0.98, up));
	float drift = wo_fbm(xz * 0.09);
	shade *= 0.955 + 0.06 * drift;
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
