shader_type spatial;
render_mode diffuse_toon;

uniform vec3 color_sand : source_color = vec3(0.8, 0.7, 0.4);
uniform vec3 color_grass : source_color = vec3(0.2, 0.5, 0.15);
uniform vec3 color_rock : source_color = vec3(0.4, 0.4, 0.4);
uniform vec3 color_snow : source_color = vec3(0.9, 0.9, 0.95);

// Змінна, куди ми запишемо реальну висоту кожної точки землі
varying float world_y;

void vertex() {
	// Отримуємо глобальну висоту (вісь Y) для цього шматочка землі
	world_y = (MODEL_MATRIX * vec4(VERTEX, 1.0)).y;
}

void fragment() {
	vec3 final_color;
	
	// Розподіл кольорів за висотою
	if (world_y < 2.0) {
		final_color = color_sand; // Дно і пляж
	} else if (world_y < 12.0) {
		// Плавний перехід від піску до трави на висоті 2-3 метри
		float blend = smoothstep(2.0, 3.0, world_y);
		final_color = mix(color_sand, color_grass, blend);
	} else if (world_y < 20.0) {
		// Перехід від трави до скель
		float blend = smoothstep(11.0, 14.0, world_y);
		final_color = mix(color_grass, color_rock, blend);
	} else {
		// Засніжені вершини гір
		float blend = smoothstep(19.0, 22.0, world_y);
		final_color = mix(color_rock, color_snow, blend);
	}
	
	ALBEDO = final_color;
	ROUGHNESS = 0.9; // Земля не має блищати
}