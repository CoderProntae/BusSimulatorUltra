shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;
uniform vec3 wall_color : source_color = vec3(0.10, 0.13, 0.17);
uniform vec3 lit_color : source_color = vec3(1.0, 0.62, 0.20);
uniform float night_amount = 0.0;
float hash21(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
void fragment() {
	vec2 grid_uv = UV * vec2(6.0, 12.0);
	vec2 cell = floor(grid_uv);
	vec2 f = fract(grid_uv);
	float frame = step(0.10, f.x) * step(0.10, f.y) * step(f.x, 0.90) * step(f.y, 0.88);
	float lit = step(0.42, hash21(cell));
	vec3 window = mix(vec3(0.025, 0.045, 0.075), lit_color, lit * night_amount);
	ALBEDO = mix(wall_color, window, frame);
	METALLIC = 0.12 * frame;
	ROUGHNESS = mix(0.82, 0.22, frame);
	EMISSION = lit_color * lit * frame * night_amount * 1.4;
}
