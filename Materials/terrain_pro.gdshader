shader_type spatial;

uniform vec3 rock_color : source_color = vec3(0.35, 0.35, 0.4);
uniform vec3 dirt_color : source_color = vec3(0.40, 0.25, 0.15);
uniform vec3 snow_color : source_color = vec3(0.9, 0.95, 1.0);

uniform float dirt_slope_threshold = 0.35; // Збільшено для чіткості
uniform float rock_slope_threshold = 0.6;  // Збільшено для чіткості
uniform float blend_amount = 0.08;         // Зменшено вдвічі для меншого градієнта

uniform float snow_height_start = 150.0;
uniform float snow_height_full = 180.0;

varying vec3 world_normal;
varying float world_y;

void vertex() {
	world_normal = (MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz;
	// Передаємо висоту вершини у фрагментний процесор
	world_y = (MODEL_MATRIX * vec4(VERTEX, 1.0)).y;
}

void fragment() {
	vec3 biome_color = COLOR.rgb;
	float slope = dot(normalize(world_normal), vec3(0.0, 1.0, 0.0));
	float steepness = 1.0 - slope; 
	
	// Розрахунок масок нахилу
	float dirt_weight = smoothstep(dirt_slope_threshold - blend_amount, dirt_slope_threshold + blend_amount, steepness);
	float rock_weight = smoothstep(rock_slope_threshold - blend_amount, rock_slope_threshold + blend_amount, steepness);
	
	// Розрахунок маски снігу за висотою
	float snow_mask = smoothstep(snow_height_start, snow_height_full, world_y);
	
	// 1. Базове змішування за нахилом (Трава -> Земля -> Скеля)
	vec3 slope_color = mix(biome_color, dirt_color, dirt_weight);
	slope_color = mix(slope_color, rock_color, rock_weight);
	
	// 2. Накладання снігу
	// На великій висоті ми замінюємо все (і траву, і скелі) на сніг, 
	// але скелі можуть трохи "проступати", якщо вони дуже круті
	float rock_on_snow = smoothstep(0.8, 0.95, steepness); // Тільки на дуже стрімких обривах сніг не тримається
	vec3 final_snow = mix(snow_color, rock_color, rock_on_snow * 0.5);
	
	vec3 final_color = mix(slope_color, final_snow, snow_mask);
	
	ALBEDO = final_color;
	ROUGHNESS = 0.8;
}