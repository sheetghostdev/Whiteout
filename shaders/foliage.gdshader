// Grass and flowers (MultiMesh). Each instance looks up the coverage under
// its root and sinks beneath the snow exactly where the ground turns white.
shader_type spatial;
render_mode cull_disabled, diffuse_lambert_wrap, specular_disabled;

#include "res://shaders/common.gdshaderinc"

uniform bool is_flower = false;
uniform vec3 petal_a : source_color = vec3(1.0, 0.86, 0.25);
uniform vec3 petal_b : source_color = vec3(0.98, 0.98, 0.95);
uniform vec3 petal_c : source_color = vec3(0.96, 0.62, 0.78);
uniform vec3 petal_d : source_color = vec3(0.74, 0.62, 0.95);
uniform float fade_start = 60.0;
uniform float fade_end = 80.0;

varying float bury;
varying float tint;
varying float kind;
varying vec3 wpos;

void vertex() {
	vec3 origin = MODEL_MATRIX[3].xyz;
	float c = wo_cov_warped(origin.xz);
	bury = wo_snow_mask(c, origin.xz);
	tint = INSTANCE_CUSTOM.x;
	kind = INSTANCE_CUSTOM.y;
	float h = VERTEX.y;
	// Wind sway, damped as the grass is buried.
	float sway = sin(TIME * 1.7 + origin.x * 0.21 + origin.z * 0.17) * 0.6 + sin(TIME * 3.1 + origin.x * 0.7) * 0.25;
	vec2 wind = (vec2(0.5, 0.3) + wo_wind * 0.08) * sway * h * h * 0.5 * (1.0 - bury);
	VERTEX.xz += wind;
	// Sink into the snow layer; fully buried blades collapse to nothing.
	float keep = 1.0 - smoothstep(0.25, 0.9, bury);
	VERTEX.y = mix(-0.15, VERTEX.y, keep);
	VERTEX.xz *= mix(0.4, 1.0, keep);
	// Distance fade by shrinking - avoids alpha sorting cost.
	float d = distance(origin, CAMERA_POSITION_WORLD);
	float f = 1.0 - smoothstep(fade_start, fade_end, d);
	VERTEX *= f;
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec3 col = wo_lin(COLOR.rgb);
	if (is_flower && COLOR.a > 0.9) {
		vec3 p = petal_a;
		if (kind > 0.75) { p = petal_d; } else if (kind > 0.5) { p = petal_c; } else if (kind > 0.25) { p = petal_b; }
		col = p;
	} else {
		col *= 0.85 + tint * 0.3;
		col = mix(col, col * vec3(1.08, 1.04, 0.8), clamp(tint - 0.6, 0.0, 1.0));
	}
	// Frosted tips as snow builds up around the clump.
	col = mix(col, wo_lin(vec3(0.9, 0.94, 1.0)), bury * 0.55 * COLOR.a);
	ALBEDO = col;
	ROUGHNESS = 0.9;
	BACKLIGHT = vec3(0.06, 0.09, 0.02) * (1.0 - bury);
}
