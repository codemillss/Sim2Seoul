shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;

// A small shared procedural palette for authored landmarks. Details and
// spacing are visual choices; source envelopes and heights are unchanged.
uniform int surface_kind = 0; // 0 tile, 1 dancheong, 2 lattice, 3 ashlar, 4 brick, 5 glass
uniform vec4 tint : source_color = vec4(0.25, 0.28, 0.29, 1.0);
uniform vec2 origin_xz = vec2(0.0);
uniform vec2 u_axis = vec2(1.0, 0.0);
uniform vec2 v_axis = vec2(0.0, 1.0);
varying vec3 position_world;
varying vec3 normal_world;

void vertex() {
	position_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	normal_world = normalize(MODEL_NORMAL_MATRIX * NORMAL);
}

float line_pattern(float position, float pitch, float width) {
	float distance_to_line = min(fract(position / pitch), 1.0 - fract(position / pitch)) * pitch;
	float aa = max(fwidth(position), 0.001);
	return 1.0 - smoothstep(width - aa, width + aa, distance_to_line);
}

void fragment() {
	vec3 normal = normalize(normal_world);
	vec2 horizontal = position_world.xz - origin_xz;
	float u = dot(horizontal, u_axis);
	float v = dot(horizontal, v_axis);
	vec2 face_tangent = normalize(vec2(-normal.z, normal.x) + vec2(0.00001));
	float side = dot(horizontal, face_tangent);
	float y = position_world.y;
	float detail = 1.0 - smoothstep(55.0, 150.0, distance(CAMERA_POSITION_WORLD, position_world));
	vec3 colour = tint.rgb;
	float roughness = 0.86;
	float metal = 0.0;
	if (surface_kind == 0) {
		// Runoff tiles read as alternating concave/convex grey strips.
		float ribs = cos(u * 26.0);
		float seams = line_pattern(v + y * 0.35, 0.48, 0.018);
		colour *= (0.86 + ribs * 0.15 * detail) * (1.0 - seams * 0.22 * detail);
		roughness = 0.77;
	} else if (surface_kind == 1) {
		float red_band = line_pattern(y, 0.30, 0.045);
		float ochre_band = line_pattern(y + 0.10, 0.30, 0.018);
		float flowers = line_pattern(side, 0.72, 0.10) * line_pattern(y, 0.30, 0.075);
		colour = mix(colour, vec3(0.48, 0.14, 0.10), red_band * 0.80);
		colour = mix(colour, vec3(0.73, 0.57, 0.31), max(ochre_band, flowers * 0.65) * 0.80);
		colour *= 0.93 + sin(side * 6.0) * 0.07;
	} else if (surface_kind == 2) {
		float lattice = max(line_pattern(side, 0.28, 0.018), line_pattern(y, 0.34, 0.018));
		colour = mix(vec3(0.13, 0.15, 0.13), tint.rgb, lattice * 0.90);
	} else if (surface_kind == 3 || surface_kind == 4) {
		float course = surface_kind == 3 ? 0.48 : 0.105;
		float width = surface_kind == 3 ? 1.05 : 0.255;
		float row = floor(y / course);
		float shifted = side + mod(row, 2.0) * width * 0.5;
		float grout_width = surface_kind == 3 ? 0.012 : 0.006;
		float joint = max(line_pattern(y, course, grout_width), line_pattern(shifted, width, grout_width));
		float random = fract(sin(dot(vec2(floor(shifted / width), row), vec2(32.1, 91.7))) * 4527.2);
		colour *= mix(0.91, 1.08, random);
		colour = mix(colour, surface_kind == 3 ? tint.rgb * 0.65 : vec3(0.52, 0.46, 0.38), joint * detail * 0.70);
	} else if (surface_kind == 5) {
		// Opaque blue glass avoids alpha sorting and screen-space reflection
		// artifacts while still showing the canopy's actual curved normals.
		float sky = clamp(normal.y * 0.50 + 0.46 + y * 0.004, 0.0, 1.0);
		colour = mix(tint.rgb * 0.66, vec3(0.56, 0.69, 0.73), sky * 0.70);
		float panes = fract(sin(floor(u / 1.38) * 41.2 + floor(y / 2.4) * 2.7) * 2573.1);
		colour *= mix(0.87, 1.10, panes);
		float frame = max(line_pattern(u, 1.38, 0.028), line_pattern(y, 2.4, 0.024));
		colour = mix(colour, vec3(0.60, 0.66, 0.67), frame * detail * 0.85);
		roughness = 0.30;
		metal = 0.20;
	}
	ALBEDO = colour;
	ROUGHNESS = roughness;
	METALLIC = metal;
	SPECULAR = surface_kind == 5 ? 0.58 : 0.28;
}
