shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;

// Metre-scale, irregular rubble masonry. This is authored surface detail,
// not a texture photograph or a claim about the dimensions of real stones.
uniform vec4 stone_tint : source_color = vec4(0.54, 0.53, 0.48, 1.0);
uniform vec4 mortar_tint : source_color = vec4(0.28, 0.28, 0.25, 1.0);
uniform float top_height_m = 2.0;
uniform bool coping_only = false;
varying vec3 position_world;
varying vec3 normal_world;

void vertex() {
	position_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	normal_world = normalize(MODEL_NORMAL_MATRIX * NORMAL);
}

vec2 stone_hash(vec2 cell) {
	return fract(sin(vec2(dot(cell, vec2(127.1, 311.7)), dot(cell, vec2(269.5, 183.3)))) * 43758.5453);
}

void fragment() {
	vec3 face = normalize(normal_world);
	vec2 tangent = normalize(vec2(-face.z, face.x) + vec2(0.00001));
	float along = dot(position_world.xz, tangent);
	float level = position_world.y;
	// Jittered, staggered stone centres give unequal polygonal blocks rather
	// than the regular rectangles of brickwork. No texture/UV seam can crawl.
	vec2 stone_point = vec2(along / 0.72, level / 0.34);
	vec2 cell = floor(stone_point);
	float nearest = 100.0;
	float second = 100.0;
	vec2 nearest_cell = vec2(0.0);
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 neighbor = cell + vec2(float(x), float(y));
			vec2 jitter = stone_hash(neighbor);
			float stagger = mod(neighbor.y, 2.0) * 0.38;
			vec2 centre = neighbor + vec2(0.25 + jitter.x * 0.50 + stagger, 0.30 + jitter.y * 0.40);
			vec2 delta = stone_point - centre;
			float dist = dot(delta, delta);
			if (dist < nearest) {
				second = nearest;
				nearest = dist;
				nearest_cell = neighbor;
			} else {
				second = min(second, dist);
			}
		}
	}
	float edge = (sqrt(second) - sqrt(nearest)) * 0.34;
	float aa = max(fwidth(edge), 0.001);
	float joint = 1.0 - smoothstep(0.008 - aa, 0.023 + aa, edge);
	float colour_pick = stone_hash(nearest_cell).x;
	vec3 block = stone_tint.rgb * mix(0.76, 1.24, colour_pick);
	block = mix(block, vec3(0.60, 0.54, 0.43), step(0.86, colour_pick) * 0.23);
	float grain = sin(dot(position_world, vec3(38.2, 73.4, 45.7))) * sin(dot(position_world, vec3(91.3, 29.1, 62.9)));
	float near_detail = 1.0 - smoothstep(20.0, 65.0, distance(CAMERA_POSITION_WORLD, position_world));
	block *= 1.0 + grain * 0.055 * near_detail;
	vec3 masonry = mix(block, mortar_tint.rgb, joint * 0.86);
	// A soot-dark tiled top contrasts strongly with the varied grey masonry.
	float tile_line = abs(sin((position_world.x + position_world.z) * 14.0));
	float tile_groove = 1.0 - smoothstep(0.07, 0.20, tile_line);
	vec3 tile = mix(vec3(0.19, 0.22, 0.23), vec3(0.10, 0.12, 0.13), tile_groove * 0.65);
	float coping = coping_only ? 1.0 : smoothstep(top_height_m - 0.23, top_height_m - 0.18, level);
	ALBEDO = mix(masonry, tile, coping);
	ROUGHNESS = mix(0.97, 0.76, coping);
	SPECULAR = 0.23;
}
