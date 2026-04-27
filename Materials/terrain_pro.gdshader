shader_type spatial;

// ЗАМІСТЬ КОЛЬОРУ КАМЕНЮ ТЕПЕР ТЕКСТУРА
uniform sampler2D rock_texture : source_color, filter_linear_mipmap, repeat_enable;
uniform float rock_texture_scale = 0.2; // Налаштовує розмір каменю

uniform vec3 dirt_color : source_color = vec3(0.40, 0.25, 0.15);
uniform vec3 snow_color : source_color = vec3(0.9, 0.95, 1.0);

uniform float dirt_slope_threshold = 0.35;
uniform float rock_slope_threshold = 0.6;
uniform float blend_amount = 0.08;

varying vec3 world_normal;
varying vec3 world_pos_var; // Зберігаємо позицію для трипланарки

void vertex() {
	world_normal = (MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz;
	world_pos_var = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec3 world_pos = world_pos_var;
	float snow_mask = COLOR.a; 
	float is_grass = UV.x;
	
	// ... (тут залишається ваш код ілюзії трави та вітру з попереднього кроку) ...
	float dist = distance(CAMERA_POSITION_WORLD, world_pos);
	float lod_fade = smoothstep(120.0, 150.0, dist);
	float wind_shadows = 1.0; // Спрощено для прикладу
	vec3 biome_color = clamp(COLOR.rgb * wind_shadows, vec3(0.0), vec3(1.0));
	
	float slope = dot(normalize(world_normal), vec3(0.0, 1.0, 0.0));
	float steepness = 1.0 - slope;

	// === ТРИПЛАНАРНЕ ТЕКСТУРУВАННЯ КАМЕНЮ ===
	// 1. Рахуємо вагу змішування для кожної з трьох осей на основі нормалі
	vec3 blend_weights = abs(normalize(world_normal));
	blend_weights = max(blend_weights - 0.2, 0.0); // Робимо переходи різкішими
	blend_weights /= dot(blend_weights, vec3(1.0)); // Нормалізуємо, щоб сума була 1.0
	
	// 2. Беремо текстуру з трьох різних площин (X, Y, Z)
	vec2 uv_x = world_pos.zy * rock_texture_scale;
	vec2 uv_y = world_pos.xz * rock_texture_scale;
	vec2 uv_z = world_pos.xy * rock_texture_scale;
	
	vec3 tex_x = texture(rock_texture, uv_x).rgb;
	vec3 tex_y = texture(rock_texture, uv_y).rgb;
	vec3 tex_z = texture(rock_texture, uv_z).rgb;
	
	// 3. Змішуємо їх разом
	vec3 triplanar_rock = tex_x * blend_weights.x + tex_y * blend_weights.y + tex_z * blend_weights.z;
	// ==========================================

	// Ваги для бруду та каменю
	float dirt_weight = smoothstep(dirt_slope_threshold - blend_amount, dirt_slope_threshold + blend_amount, steepness);
	float rock_weight = smoothstep(rock_slope_threshold - blend_amount, rock_slope_threshold + blend_amount, steepness);
	
	// Змішуємо кольори. Замість rock_color тепер використовуємо нашу трипланарну текстуру!
	vec3 slope_color = mix(biome_color, dirt_color, dirt_weight);
	slope_color = mix(slope_color, triplanar_rock, rock_weight); 
	
	float rock_on_snow = smoothstep(0.8, 0.95, steepness);
	vec3 final_snow = mix(snow_color, triplanar_rock, rock_on_snow * 0.5);
	
	vec3 final_color = mix(slope_color, final_snow, snow_mask);
	
	ALBEDO = final_color;
	ROUGHNESS = 0.8;
}