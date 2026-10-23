// Ground-hugging projections built from a flat grid: targeting previews,
// storm footprints, frost-pulse rings, wind arrows. Vertices are snapped to
// the terrain using the global height texture.
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_mix, world_vertex_coords;

#include "res://shaders/common.gdshaderinc"

uniform int mode = 0;          // 0 disc, 1 ring, 2 strip with chevrons, 3 footprint, 4 arrow trail
uniform vec4 color : source_color = vec4(0.75, 0.92, 1.0, 0.5);
uniform float lift = 0.25;
uniform float ring_width = 0.06;
uniform float intensity = 1.0;
uniform float scroll_speed = 1.0;

varying vec2 luv;

void vertex() {
	float h = wo_surface_height(VERTEX.xz);
	VERTEX.y = h + lift;
	luv = UV;
}

void fragment() {
	vec2 p = luv * 2.0 - 1.0;
	float a = 0.0;
	if (mode == 0) {
		float r = length(p);
		float rim = smoothstep(1.0 - ring_width * 1.5, 1.0 - ring_width * 0.5, r) * (1.0 - smoothstep(1.0 - ring_width * 0.3, 1.0, r));
		float fill = (1.0 - smoothstep(0.85, 1.0, r)) * 0.22;
		float sweep = 0.5 + 0.5 * sin(atan(p.y, p.x) * 6.0 - TIME * 2.0);
		a = rim * (0.75 + 0.25 * sweep) + fill;
	} else if (mode == 1) {
		float r = length(p);
		a = smoothstep(1.0 - ring_width, 1.0 - ring_width * 0.4, r) * (1.0 - smoothstep(1.0 - ring_width * 0.2, 1.0, r));
		a += (1.0 - smoothstep(0.0, 1.0, r)) * 0.0;
	} else if (mode == 2) {
		float side = abs(p.x);
		float border = smoothstep(0.82, 0.92, side) * (1.0 - smoothstep(0.95, 1.0, side));
		float chev = fract(luv.y * 6.0 - abs(p.x) * 0.6 - TIME * scroll_speed);
		float chevron = smoothstep(0.0, 0.08, chev) * (1.0 - smoothstep(0.18, 0.3, chev)) * (1.0 - smoothstep(0.7, 0.9, side));
		float ends = smoothstep(0.0, 0.05, luv.y) * (1.0 - smoothstep(0.92, 1.0, luv.y));
		a = (border * 0.8 + chevron * 0.6 + 0.08) * ends;
	} else if (mode == 3) {
		float r = length(p);
		a = (1.0 - smoothstep(0.55, 1.0, r)) * 0.5;
	} else {
		float side = abs(p.x);
		float chev = fract(luv.y * 10.0 - side * 0.8 - TIME * scroll_speed);
		a = smoothstep(0.0, 0.1, chev) * (1.0 - smoothstep(0.2, 0.35, chev)) * (1.0 - smoothstep(0.5, 1.0, side));
		a *= smoothstep(0.0, 0.1, luv.y) * (1.0 - smoothstep(0.85, 1.0, luv.y));
	}
	ALBEDO = color.rgb;
	ALPHA = clamp(a * color.a * intensity, 0.0, 1.0);
}
