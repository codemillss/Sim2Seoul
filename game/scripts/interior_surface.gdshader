shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

// Authored metre-scale materials; these are not scanned historic finishes.
uniform vec4 base_color : source_color = vec4(0.7, 0.7, 0.65, 1.0);
uniform int surface_kind : hint_range(0, 3) = 0;
uniform float surface_scale : hint_range(0.1, 4.0) = 1.0;
varying vec3 metre_position;
varying vec3 world_normal;

float hash21(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise21(vec2 p) {
	vec2 i = floor(p);
	vec2 t = fract(p);
	t = t * t * (3.0 - 2.0 * t);
	return mix(mix(hash21(i), hash21(i + vec2(1.0, 0.0)), t.x),
		mix(hash21(i + vec2(0.0, 1.0)), hash21(i + vec2(1.0)), t.x), t.y);
}

// The derivative smooths joints as they become subpixel at a distance.
float joint(vec2 p, vec2 module, float width) {
	vec2 d = min(mod(p, module), module - mod(p, module));
	vec2 aa = max(fwidth(p), vec2(0.0005));
	vec2 edge = smoothstep(vec2(width) - aa, vec2(width) + aa, d);
	return min(edge.x, edge.y);
}

vec2 finish(vec2 p) {
	float tone = 1.0;
	float rough = 0.85;
	if (surface_kind == 0) {
		float tile = hash21(floor(p / 0.6));
		float grain = noise21(p * 65.0) - 0.5;
		float edge = joint(p, vec2(0.6), 0.003);
		float fine_visibility = 1.0 - smoothstep(0.01, 0.05, max(fwidth(p.x), fwidth(p.y)));
		tone = mix(0.74, 0.96 + tile * 0.065 + grain * 0.075 * fine_visibility, edge);
		rough = mix(0.94, 0.61, edge);
	} else if (surface_kind == 1) {
		vec2 plank = floor(p / vec2(0.18, 2.4));
		vec2 staggered = p + vec2(0.0, mod(plank.x, 2.0) * 1.2);
		float edge = joint(staggered, vec2(0.18, 2.4), 0.0015);
		float wave = noise21(vec2(p.x * 7.0, p.y * 0.6));
		float fine_visibility = 1.0 - smoothstep(0.003, 0.02, max(fwidth(p.x), fwidth(p.y)));
		float grain = sin(p.x * 490.0 + wave * 12.0) * 0.025 * fine_visibility;
		tone = mix(0.65, 0.93 + hash21(plank) * 0.12 + (wave - 0.5) * 0.10 + grain, edge);
		rough = 0.64;
	} else if (surface_kind == 2) {
		tone = 0.98 + (noise21(p * 9.0) - 0.5) * 0.035;
		rough = 0.91;
	} else {
		float visibility = 1.0 - smoothstep(0.001, 0.009, max(fwidth(p.x), fwidth(p.y)));
		float weave = sin(p.x * 1400.0) * sin(p.y * 1400.0);
		tone = 0.97 + weave * 0.035 * visibility;
		rough = 0.96;
	}
	return vec2(tone, rough);
}

void vertex() {
	metre_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz * surface_scale;
	world_normal = normalize(MODEL_NORMAL_MATRIX * NORMAL);
}

void fragment() {
	vec3 weight = pow(abs(normalize(world_normal)), vec3(6.0));
	weight /= max(weight.x + weight.y + weight.z, 0.0001);
	vec2 value = finish(metre_position.zy) * weight.x
		+ finish(metre_position.xz) * weight.y
		+ finish(metre_position.xy) * weight.z;
	ALBEDO = base_color.rgb * value.x;
	ROUGHNESS = value.y;
	METALLIC = 0.0;
}
