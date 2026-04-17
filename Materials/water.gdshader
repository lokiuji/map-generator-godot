shader_type spatial;
render_mode blend_mix, depth_draw_opaque, diffuse_toon, specular_disabled;

uniform vec3 water_color : source_color = vec3(0.15, 0.55, 0.85);
uniform vec3 foam_color : source_color = vec3(0.9, 0.95, 1.0);

varying vec3 v_pos;

void vertex() {
	v_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	// Легке погойдування геометрії
	VERTEX.y += sin(v_pos.x * 1.5 + TIME) * 0.1;
}

void fragment() {
	// Математичні хвилі (перетинаємо синусоїди)
	float wave1 = sin(v_pos.x * 2.0 + TIME * 1.2) * cos(v_pos.z * 2.0 + TIME * 0.8);
	float wave2 = sin(v_pos.x * 3.0 - TIME * 1.5) * cos(v_pos.z * 1.5 + TIME * 1.1);
	float final_wave = wave1 + wave2;

	// Відсікаємо верхівки хвиль, створюючи "піну"
	float foam = smoothstep(0.8, 1.0, final_wave);

	ALBEDO = mix(water_color, foam_color, foam);
	ALPHA = 0.85;
	ROUGHNESS = 0.2;
}