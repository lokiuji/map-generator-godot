shader_type spatial;
render_mode cull_disabled, diffuse_toon;

uniform vec3 color_bottom : source_color = vec3(0.2, 0.45, 0.2);
uniform vec3 color_top : source_color = vec3(0.4, 0.7, 0.3);
uniform sampler2D grass_pattern; // Шум для прозорості

varying float layer;
varying vec3 w_pos;

void vertex() {
	layer = INSTANCE_CUSTOM.x; // Висота шару (0.0 до 1.0)
	
	// Висота килима (0.6 метра)
	VERTEX.y += layer * 0.6;
	
	w_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	
	// Вітер гне шари
	float wind = sin(w_pos.x * 2.0 + TIME * 1.5) * 0.1;
	VERTEX.x += wind * layer;
}

void fragment() {
	// Не малюємо траву під водою
	if (w_pos.y < -15.0) discard; 

	// Беремо шум для створення "волосинок"
	float n = texture(grass_pattern, w_pos.xz * 1.5).r;
	
	// Чим вищий шар, тим тонші травинки (більше відкидаємо)
	float threshold = mix(0.1, 0.6, layer);
	if (n < threshold && layer > 0.05) discard;

	ALBEDO = mix(color_bottom, color_top, layer);
}