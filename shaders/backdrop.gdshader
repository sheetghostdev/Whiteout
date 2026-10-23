// Distant mountains outside the playable area. They whiten as the world freezes.
shader_type spatial;
render_mode diffuse_burley, specular_disabled;

#include "res://shaders/common.gdshaderinc"

varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec3 wn = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	float n = wo_fbm(wpos.xz * 0.01);
	vec3 green = wo_lin(mix(vec3(0.22, 0.40, 0.26), vec3(0.30, 0.46, 0.30), n));
	vec3 rock = wo_lin(mix(vec3(0.38, 0.40, 0.46), vec3(0.46, 0.47, 0.52), n));
	vec3 col = mix(green, rock, smoothstep(60.0, 140.0, wpos.y + n * 30.0));
	col = mix(col, rock, smoothstep(0.75, 0.55, wn.y));
	// Snow line descends as the player's world freezes.
	float cap_line = mix(150.0, 10.0, wo_completion);
	float snow = smoothstep(cap_line - 15.0, cap_line + 15.0, wpos.y + n * 30.0) * smoothstep(0.35, 0.65, wn.y);
	col = mix(col, wo_lin(vec3(0.93, 0.95, 1.0)), snow);
	// Extra aerial haze pushes the ranges back so they never compete with the play area.
	float dist = distance(wpos.xz, CAMERA_POSITION_WORLD.xz);
	col = mix(col, wo_lin(vec3(0.62, 0.74, 0.88)), smoothstep(250.0, 1300.0, dist) * 0.55);
	ALBEDO = col;
	ROUGHNESS = 0.95;
}
