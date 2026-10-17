shader_type spatial;
render_mode cull_disabled, diffuse_burley;

uniform bool individual_blades = true;
varying vec3 tree_position;

void vertex() {
	tree_position = VERTEX;
	float breeze = sin(TIME * 0.85 + VERTEX.y * 1.4 + float(INSTANCE_ID) * 1.7);
	VERTEX.x += breeze * 0.025 * clamp((VERTEX.y - 3.2) * 0.3, 0.0, 1.0);
}

float hash3(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.yzx + 33.33);
	return fract((p.x + p.y) * p.z);
}
float noise3(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash3(i), hash3(i+vec3(1,0,0)), f.x), mix(hash3(i+vec3(0,1,0)), hash3(i+vec3(1,1,0)), f.x), f.y), mix(mix(hash3(i+vec3(0,0,1)), hash3(i+vec3(1,0,1)), f.x), mix(hash3(i+vec3(0,1,1)), hash3(i+vec3(1,1,1)), f.x), f.y), f.z);
}
void fragment() {
	float speckle = noise3(tree_position * 9.7);
	float shade = mix(0.64, 1.08, smoothstep(0.18, 0.85, speckle));
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
