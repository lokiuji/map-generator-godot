shader_type spatial;

// === ТЕПЕР ЦІ КОЛЬОРИ МОЖНА ЗМІНЮВАТИ В ІНСПЕКТОРІ ===
uniform vec3 color_grass : source_color = vec3(0.25, 0.42, 0.12);
uniform vec3 color_forest : source_color = vec3(0.18, 0.32, 0.08);

uniform vec3 color_sand : source_color = vec3(0.76, 0.70, 0.50);
uniform vec3 color_rock : source_color = vec3(0.45, 0.45, 0.45);
uniform vec3 color_snow : source_color = vec3(0.95, 0.95, 0.95);

varying float v_height;
varying float v_moisture;

void vertex() {
	v_height = (MODEL_MATRIX * vec4(VERTEX, 1.0)).y;
	v_moisture = COLOR.r; 
}

void fragment() {
	vec3 color;

	if (v_moisture < -0.15) {
		color = color_sand; 
	} else {
		color = mix(color_grass, color_forest, smoothstep(-0.15, 0.5, v_moisture));
	}

	if (v_height < 3.2) {
		color = mix(color_sand, color, smoothstep(2.5, 3.2, v_height));
	} else if (v_height > 35.0) {
		color = mix(color, color_rock, smoothstep(35.0, 50.0, v_height));
		color = mix(color, color_snow, smoothstep(110.0, 140.0, v_height));
	}
	
	vec3 world_pos = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float ground_noise = fract(sin(dot(world_pos.xz, vec2(12.9898, 78.233))) * 43758.5453);
	color = mix(color, color * 0.85, ground_noise * 0.15); 
	
	ALBEDO = color;
	ROUGHNESS = 0.95;
	SPECULAR = 0.0; // Вбиваємо відблиски на землі, щоб вона була матовою
}