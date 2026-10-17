shader_type spatial;
render_mode cull_disabled, diffuse_burley;

uniform bool individual_blades = false;
varying vec3 tree_position;

void vertex() {
	tree_position = VERTEX;
	float breeze = sin(TIME * 0.85 + VERTEX.y * 1.4 + float(INSTANCE_ID) * 1.7);
	VERTEX.x += breeze * 0.025 * clamp((VERTEX.y - 3.2) * 0.3, 0.0, 1.0);
}

void fragment() {
	float speckle = 0.5 + 0.5 * sin(tree_position.x * 43.0 + tree_position.y * 32.0) * sin(tree_position.z * 39.0 - tree_position.y * 27.0);
	float shade = mix(0.59, 1.06, speckle);
	if (individual_blades) {
		float central_vein = 1.0 - smoothstep(0.008, 0.037, abs(UV.x - 0.5));
		float side_veins = pow(0.5 + 0.5 * cos((UV.y + abs(UV.x - 0.5) * 0.55) * 63.0), 14.0);
		shade = 0.89 + central_vein * 0.18 + side_veins * 0.07;
	}
	ALBEDO = COLOR.rgb * shade;
	BACKLIGHT = COLOR.rgb * 0.14;
	ROUGHNESS = 0.94;
	SPECULAR = 0.13;
	if (!FRONT_FACING) { NORMAL = -NORMAL; }
}
