// Window panes, lanterns and the lighthouse lamp. Each pane's UV.x picks a
// texel of the `warmth` texture: one per building (a fire lit inside) plus
// one per town (street lamps lit). Panes look like dark glass in summer and
// glow with a flickering firelight once a fire burns behind them.
shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

#include "res://shaders/common.gdshaderinc"

uniform sampler2D warmth : filter_nearest, repeat_disable;
uniform vec3 lit_color : source_color = vec3(1.0, 0.70, 0.34);
uniform vec3 glass_color : source_color = vec3(0.24, 0.32, 0.42);

void fragment() {
	float w = texture(warmth, vec2(UV.x, 0.5)).r;
	// Each pane flickers on its own (UV.y is a per-pane random phase).
	float flicker = 0.86 + 0.1 * sin(TIME * 3.1 + UV.y * 37.0) + 0.04 * sin(TIME * 7.3 + UV.y * 91.0);
	vec3 glass = wo_lin(glass_color);
	vec3 lit = wo_lin(lit_color);
	ALBEDO = mix(glass, lit * 0.55, w);
	EMISSION = lit * w * 2.2 * flicker;
	ROUGHNESS = mix(0.12, 0.5, w);
	SPECULAR = 0.6;
}
