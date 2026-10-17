shader_type spatial;
render_mode diffuse_burley;

void fragment() {
	float grain = sin(UV.x * 210.0 + sin(UV.y * 3.9) * 2.4);
	float split = smoothstep(0.60, 0.96, grain);
	float mottling = 0.5 + 0.5 * sin(UV.x * 39.0 + UV.y * 9.1) * sin(UV.y * 3.7 - UV.x * 21.0);
	ALBEDO = COLOR.rgb * mix(0.62, 1.09, mottling) * (1.0 - split * 0.28);
	ROUGHNESS = 0.97;
	SPECULAR = 0.12;
}
