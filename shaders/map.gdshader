// Overview map: shaded relief tinted green or white by live coverage.
shader_type canvas_item;

#include "res://shaders/common.gdshaderinc"

uniform sampler2D relief : filter_linear;

void fragment() {
	vec2 xz = UV * 512.0 - 256.0;
	vec4 r = texture(relief, UV);
	float c = wo_cov(xz);
	float m = smoothstep(0.35, 0.95, c);
	vec3 summer = r.rgb;
	vec3 winter = mix(vec3(0.80, 0.87, 0.96), vec3(0.98, 0.99, 1.0), r.a);
	vec3 col = mix(summer, winter, m);
	COLOR = vec4(col, 1.0);
}
