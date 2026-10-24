// Trees, bushes, stumps and rocks. Vertex alpha selects material:
// 1 = foliage, 0 = bark, 0.5 = rock. Snow comes from the surrounding
// terrain coverage, so trees are feedback, not separate targets.
shader_type spatial;
render_mode diffuse_lambert_wrap, specular_schlick_ggx;

#include "res://shaders/common.gdshaderinc"

uniform bool per_vertex_snow = false;   // rocks sample under each vertex
uniform bool per_pixel_snow = false;    // buildings: snow follows the ground under every pixel
uniform float sway_amount = 1.0;
uniform bool merged = false;            // far LOD: origin in UV2, hue in UV.x

varying float snow_amt;
varying vec3 wnorm;
varying vec3 wpos;
varying float hue;

void vertex() {
	vec3 origin = MODEL_MATRIX[3].xyz;
	if (merged) {
		origin = vec3(UV2.x, 0.0, UV2.y);
	}
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float c;
	if (per_vertex_snow) {
		c = wo_cov_warped(wpos.xz);
		snow_amt = wo_snow_mask(c, wpos.xz);
	} else {
		// Average the ground around the trunk so the canopy whitens with its surroundings.
		c = (wo_cov(origin.xz) * 2.0 + wo_cov(origin.xz + vec2(2.5, 0.0)) + wo_cov(origin.xz - vec2(2.5, 0.0))
			+ wo_cov(origin.xz + vec2(0.0, 2.5)) + wo_cov(origin.xz - vec2(0.0, 2.5))) / 6.0;
		snow_amt = smoothstep(0.15, 0.95, c);
	}
	hue = merged ? UV.x : INSTANCE_CUSTOM.x;
	wnorm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	if (COLOR.a > 0.75 && !merged) {
		float h = max(VERTEX.y, 0.0);
		float sway = sin(TIME * 1.1 + origin.x * 0.13 + origin.z * 0.11) * 0.04 + sin(TIME * 2.3 + origin.z * 0.4) * 0.015;
		VERTEX.x += sway * h * sway_amount * (1.0 - snow_amt * 0.6);
		VERTEX.z += sway * 0.6 * h * sway_amount * (1.0 - snow_amt * 0.6);
	}
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec3 base = wo_lin(COLOR.rgb);
	float mat = COLOR.a;
	float n = wo_noise(wpos.xz * 1.7 + wpos.y * 1.3);
	if (mat > 0.75) {
		// Foliage: per-instance hue/brightness variation.
		base *= 0.88 + hue * 0.24;
		base = mix(base, base * vec3(1.15, 1.08, 0.7), clamp(hue - 0.75, 0.0, 1.0) * 1.2);
	} else if (mat > 0.25) {
		base *= 0.9 + 0.2 * wo_noise(wpos.xz * 3.0 + wpos.y * 2.0);
	} else {
		base *= 0.85 + 0.25 * wo_noise(vec2(wpos.y * 6.0, atan(wnorm.x, wnorm.z) * 3.0));
	}
	float up = wnorm.y;
	float s = snow_amt;
	if (per_pixel_snow) {
		s = wo_snow_mask(wo_cov_warped(wpos.xz), wpos.xz);
	}
	vec3 snow = mix(wo_lin(vec3(0.80, 0.87, 0.97)), wo_lin(vec3(0.97, 0.98, 1.0)), clamp(up, 0.0, 1.0));
	float cover;
	if (mat > 0.75) {
		// Frost tints the whole canopy; thick snow settles on upward faces.
		// Frost tints the canopy; snow settles on upward faces while
		// undersides keep a darker hint of foliage.
		base = mix(base, mix(base, wo_lin(vec3(0.46, 0.56, 0.58)), 0.6), s * 0.8);
		cover = smoothstep(0.1, 0.5, up + n * 0.35 - 0.3 + s * 0.25) * s;
		cover = max(cover, s * 0.2);
	} else if (mat > 0.25) {
		cover = smoothstep(0.25, 0.6, up + n * 0.3 - 0.1) * s;
	} else {
		cover = smoothstep(0.6, 0.85, up + n * 0.2) * s;
	}
	ALBEDO = mix(base, snow, cover);
	ROUGHNESS = mix(0.85, 0.7, cover);
	SPECULAR = mix(0.2, 0.4, cover);
	if (mat > 0.75) {
		BACKLIGHT = vec3(0.12, 0.18, 0.06) * (1.0 - cover);
	}
}
