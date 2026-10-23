// Procedural daytime sky: gradient, sun disc with glow, horizon haze and
// soft painted clouds. Static (no TIME) so the radiance map stays cheap.
shader_type sky;

uniform vec3 zenith : source_color = vec3(0.26, 0.50, 0.86);
uniform vec3 horizon : source_color = vec3(0.70, 0.84, 0.96);
uniform vec3 ground : source_color = vec3(0.58, 0.68, 0.74);
uniform vec3 sun_color : source_color = vec3(1.0, 0.92, 0.78);
uniform float cloud_cover = 0.45;
uniform float cloud_offset = 0.0;

float h21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}
float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(h21(i), h21(i + vec2(1, 0)), u.x), mix(h21(i + vec2(0, 1)), h21(i + vec2(1, 1)), u.x), u.y);
}
float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int k = 0; k < 5; k++) {
		v += a * vnoise(p);
		p = p * 2.07 + 13.1;
		a *= 0.5;
	}
	return v;
}

void sky() {
	vec3 d = EYEDIR;
	float h = d.y;
	vec3 col;
	if (h >= 0.0) {
		col = mix(horizon, zenith, pow(h, 0.5));
		// Warm haze near the horizon.
		col = mix(col, vec3(0.86, 0.90, 0.94), exp(-h * 14.0) * 0.45);
	} else {
		col = mix(horizon, ground, smoothstep(0.0, 0.25, -h));
	}
	vec3 sd = LIGHT0_DIRECTION;
	float sdot = max(dot(d, sd), 0.0);
	col += sun_color * (pow(sdot, 6.0) * 0.18 + pow(sdot, 64.0) * 0.35);
	if (!AT_CUBEMAP_PASS) {
		col += sun_color * smoothstep(0.9993, 0.9997, sdot) * 6.0;
	}
	if (h > 0.0) {
		vec2 uv = d.xz / (h + 0.12) * 0.9 + vec2(cloud_offset, 0.0);
		float n = fbm(uv * 1.3);
		float cl = smoothstep(1.0 - cloud_cover, 1.0 - cloud_cover + 0.28, n);
		cl *= smoothstep(0.02, 0.2, h);
		float lit = 0.85 + 0.15 * fbm(uv * 2.6 + 5.0);
		vec3 cc = mix(vec3(0.82, 0.86, 0.92), vec3(1.0), lit) + sun_color * pow(sdot, 4.0) * 0.25;
		col = mix(col, cc, cl * 0.85);
	}
	COLOR = col;
}
