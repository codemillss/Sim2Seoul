shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;

// Stylized metre-scale exterior treatment, not a surveyed Seoul facade.
// No texture/UV requirements, transparency, extra surfaces or window geometry.
uniform vec4 wall_tint : source_color = vec4(0.72, 0.72, 0.68, 1.0);
uniform vec4 glass_tint : source_color = vec4(0.19, 0.29, 0.33, 1.0);
uniform float floor_height_m = 3.3;
uniform float bay_width_m = 2.5;
uniform float curtain_wall = 0.0;
instance uniform vec2 height_limits_m = vec2(0.0, 9.0);
instance uniform float facade_seed = 0.0;

varying vec3 position_world;
varying vec3 normal_world;

void vertex() {
	position_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	normal_world = normalize(MODEL_NORMAL_MATRIX * NORMAL);
}

float rectangle(vec2 point, vec2 lower, vec2 upper) {
	vec2 aa = max(fwidth(point), vec2(0.001));
	vec2 a = smoothstep(lower - aa, lower + aa, point);
	vec2 b = vec2(1.0) - smoothstep(upper - aa, upper + aa, point);
	return a.x * a.y * b.x * b.y;
}

float cell_hash(vec2 cell) {
	return fract(sin(dot(cell, vec2(12.9898, 78.233)) + facade_seed * 0.37) * 43758.5453);
}

void fragment() {
	vec3 face = normalize(normal_world);
	float wall = 1.0 - smoothstep(0.45, 0.8, abs(face.y));
	// A face-local horizontal axis maintains metre-sized bays on diagonal walls.
	vec2 tangent = normalize(vec2(-face.z, face.x) + vec2(0.000001));
	float horizontal_m = dot(position_world.xz, tangent) + facade_seed * 0.19;
	float height_m = max(position_world.y - height_limits_m.x, 0.0);
	float building_height_m = max(height_limits_m.y - height_limits_m.x, 1.0);
	vec2 cells = vec2(horizontal_m / bay_width_m, height_m / floor_height_m);
	vec2 grid = fract(cells);
	float detail = 1.0 - smoothstep(95.0, 185.0, distance(CAMERA_POSITION_WORLD, position_world));

	vec3 plaster = wall_tint.rgb;
	// Darker base and roof make the volume readable at street and skyline level.
	float ground_floor = 1.0 - smoothstep(3.15, 3.40, height_m);
	plaster *= mix(1.0, 0.68, ground_floor);
	float top_trim = smoothstep(building_height_m - 0.45, building_height_m - 0.15, height_m);
	plaster *= mix(1.0, 0.69, top_trim);
	float floor_edge_m = min(grid.y, 1.0 - grid.y) * floor_height_m;
	float floor_band = 1.0 - smoothstep(0.045, 0.105, floor_edge_m);
	plaster *= 1.0 - floor_band * 0.16 * detail;

	vec2 pane_low = mix(vec2(0.21, 0.24), vec2(0.075, 0.14), curtain_wall);
	vec2 pane_high = mix(vec2(0.80, 0.81), vec2(0.925, 0.88), curtain_wall);
	float window = rectangle(grid, pane_low, pane_high);
	window *= smoothstep(3.35, 3.55, height_m);
	window *= 1.0 - smoothstep(building_height_m - 0.65, building_height_m - 0.35, height_m);
	float choice = cell_hash(floor(cells));
	vec3 glass = glass_tint.rgb * mix(0.76, 1.20, choice);
	// A restrained cool reflection stripe and sparse warm panes, without emission.
	glass += vec3(0.06, 0.075, 0.075) * smoothstep(0.28, 0.84, grid.y);
	glass = mix(glass, vec3(0.47, 0.43, 0.32), step(0.94, choice) * 0.38);
	float mullion = 1.0 - smoothstep(0.018, 0.043, abs(grid.x - 0.50));
	glass *= 1.0 - mullion * mix(0.32, 0.17, curtain_wall);
	vec3 facade = mix(plaster, glass, window * detail);

	// Ground-floor glazing suggests street frontage without invented shop names.
	float frontage_bays = rectangle(vec2(fract(horizontal_m / 3.2), height_m / 3.2), vec2(0.10, 0.13), vec2(0.90, 0.83));
	float frontage = frontage_bays * ground_floor * detail;
	facade = mix(facade, glass_tint.rgb * 0.68, frontage);
	float sill = 1.0 - smoothstep(0.035, 0.09, abs(grid.y - pane_low.y) * floor_height_m);
	facade = mix(facade, wall_tint.rgb * 0.85, sill * window * detail * 0.35);

	vec3 roof = wall_tint.rgb * 0.48;
	ALBEDO = mix(roof, facade, wall);
	ROUGHNESS = mix(0.88, 0.38, max(window, frontage) * wall * detail);
	METALLIC = max(window, frontage) * wall * detail * 0.12;
	SPECULAR = 0.40;
}
