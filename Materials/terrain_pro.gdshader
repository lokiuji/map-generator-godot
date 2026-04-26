shader_type spatial;

uniform vec3 rock_color : source_color = vec3(0.35, 0.35, 0.4);
uniform vec3 dirt_color : source_color = vec3(0.40, 0.25, 0.15);
uniform vec3 snow_color : source_color = vec3(0.9, 0.95, 1.0);

uniform float dirt_slope_threshold = 0.35;
uniform float rock_slope_threshold = 0.6;
uniform float blend_amount = 0.08;

varying vec3 world_normal;

void vertex() {
	world_normal = (MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz;
}

void fragment() {
	// Отримуємо глобальні координати пікселя
	vec3 world_pos = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float snow_mask = COLOR.a; 
	
	// --- ВІДСТАНЬ ДО КАМЕРИ ---
	// dist - це дистанція від камери до поточного шматка землі.
	float dist = distance(CAMERA_POSITION_WORLD, world_pos);
	
	// lod_fade буде 0.0 зблизька (шуму не видно) і плавно стане 1.0 після 200 метрів
	float lod_fade = smoothstep(120.0, 200.0, dist);
	
	// --- АНІМАЦІЯ ВІТРУ ТА ЛАНДШАФТУ ---
	// М'які хвилі вітру (без сіток і різких переходів)
	float wind_speed = 1.5;
	float wind = sin(world_pos.x * 0.08 + TIME * wind_speed) * sin(world_pos.z * 0.08 + TIME * wind_speed * 0.8);
	
	// Плями ландшафту: додає природну нерівномірність (світліші/темніші ділянки поля)
	float ground_tex = sin(world_pos.x * 0.15) * cos(world_pos.z * 0.15);
	
	// Комбінуємо хвилі і множимо на lod_fade (так ми приховуємо цей ефект перед камерою)
	float wind_shadows = ((wind * 0.04) + (ground_tex * 0.03)) * lod_fade;
	
	// Застосовуємо цей рух ТІЛЬКИ до трав'яних біомів (маскуємо сніг)
	vec3 biome_color = COLOR.rgb + (wind_shadows * (1.0 - snow_mask));
	
	// --- Стандартний розрахунок схилів ---
	float slope = dot(normalize(world_normal), vec3(0.0, 1.0, 0.0));
	float steepness = 1.0 - slope;
	
	float dirt_weight = smoothstep(dirt_slope_threshold - blend_amount, dirt_slope_threshold + blend_amount, steepness);
	float rock_weight = smoothstep(rock_slope_threshold - blend_amount, rock_slope_threshold + blend_amount, steepness);
	
	vec3 slope_color = mix(biome_color, dirt_color, dirt_weight);
	slope_color = mix(slope_color, rock_color, rock_weight);
	
	float rock_on_snow = smoothstep(0.8, 0.95, steepness);
	vec3 final_snow = mix(snow_color, rock_color, rock_on_snow * 0.5);
	
	vec3 final_color = mix(slope_color, final_snow, snow_mask);
	
	ALBEDO = final_color;
	ROUGHNESS = 0.8;
}