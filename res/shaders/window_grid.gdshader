shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

// Procedural building facade: concrete panels + a grid of windows.
// Random cells become emissive ("lit") at night. No flat colored cubes.

uniform vec3 wall_color : source_color = vec3(0.55, 0.54, 0.52);
uniform vec3 wall_color_b : source_color = vec3(0.42, 0.41, 0.40);
uniform vec3 glass_color : source_color = vec3(0.09, 0.12, 0.16);
uniform vec3 frame_color : source_color = vec3(0.20, 0.20, 0.22);
uniform vec3 lit_color : source_color = vec3(1.0, 0.82, 0.48);

uniform vec2 windows = vec2(4.0, 6.0);
uniform float window_w : hint_range(0.05, 0.95) = 0.52;
uniform float window_h : hint_range(0.05, 0.95) = 0.55;
uniform float frame_thickness : hint_range(0.0, 0.3) = 0.07;
uniform float night : hint_range(0.0, 1.0) = 0.0;
uniform float lit_ratio : hint_range(0.0, 1.0) = 0.55;
uniform float seed = 3.0;
uniform float grime : hint_range(0.0, 1.0) = 0.35;
uniform sampler2D wall_texture : source_color, hint_default_white, filter_linear_mipmap, repeat_enable;
uniform float wall_texture_mix : hint_range(0.0, 1.0) = 0.0;
uniform vec3 wall_uv_scale = vec3(2.0, 2.0, 1.0);

// "highp" per-variable modifiers (documented GDShader syntax): mobile GPUs may
// otherwise run this hash at mediump, which speckles large facades.
float hash21(vec2 p) {
	highp vec2 q = fract(p * vec2(233.34, 851.73));
	q += dot(q, q + 23.45);
	return fract(q.x * q.y);
}

float noise21(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash21(i);
	float b = hash21(i + vec2(1.0, 0.0));
	float c = hash21(i + vec2(0.0, 1.0));
	float d = hash21(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

void fragment() {
	vec2 grid_uv = UV * windows;
	vec2 cell = floor(grid_uv);
	vec2 f = fract(grid_uv);

	// window rectangle mask
	vec2 half_size = vec2(window_w, window_h) * 0.5;
	vec2 d = abs(f - 0.5);
	float win = step(d.x, half_size.x) * step(d.y, half_size.y);

	// frame ring around the window
	vec2 outer = half_size + vec2(frame_thickness);
	float outer_mask = step(d.x, outer.x) * step(d.y, outer.y);
	float frame = clamp(outer_mask - win, 0.0, 1.0);

	// per-cell randomness
	float r = hash21(cell + vec2(seed, seed * 1.7));
	float is_lit = step(1.0 - lit_ratio, r) * night;
	float flick = 0.85 + 0.15 * sin(TIME * (0.5 + r) + r * 20.0);

	// concrete panel variation
	float band = step(0.5, fract(UV.y * windows.y * 0.5));
	float n = noise21(UV * vec2(26.0, 40.0) + seed);
	vec3 panel = mix(wall_color, wall_color_b, band * 0.45 + n * 0.35);
	panel *= 1.0 - grime * 0.45 * noise21(UV * vec2(4.0, 9.0) + seed * 3.1);

	vec3 tex = texture(wall_texture, UV * wall_uv_scale.xy).rgb;
	panel = mix(panel, panel * tex * 1.6, wall_texture_mix);

	// glass has a soft vertical gradient (sky reflection feel)
	vec3 glass = glass_color + vec3(0.10, 0.13, 0.18) * (1.0 - f.y);
	glass = mix(glass, lit_color * 0.75, is_lit);

	vec3 albedo = panel;
	albedo = mix(albedo, frame_color, frame);
	albedo = mix(albedo, glass, win);

	ALBEDO = albedo;
	METALLIC = win * 0.55;
	ROUGHNESS = mix(0.85 - grime * 0.1, 0.12, win);
	SPECULAR = mix(0.35, 0.85, win);
	EMISSION = lit_color * is_lit * win * flick * 2.2;
}
