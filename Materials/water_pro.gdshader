shader_type spatial;
render_mode blend_mix, depth_draw_always, specular_toon;

// ==========================================
// 🎨 ГЛОБАЛЬНІ НАЛАШТУВАННЯ ТА КОЛЬОРИ
// ==========================================
uniform float water_level = 4.8; 

uniform vec3 col_lake : source_color = vec3(0.05, 0.6, 0.85); 
uniform vec3 col_ocean : source_color = vec3(0.01, 0.1, 0.3); 
uniform vec3 foam_color : source_color = vec3(1.0, 1.0, 1.0);
uniform vec3 toon_dark : source_color = vec3(0.0, 0.1, 0.2);

// ==========================================
// 🌊 ФІЗИКА ТА ПІНА
// ==========================================
uniform sampler2D noise_texture : hint_default_black, filter_linear_mipmap, repeat_enable;
uniform float wave_speed = 0.03;
uniform float wave_scale = 0.05;

// ВИПРАВЛЕНО: Тепер хвилі вищі
uniform float wave_height_total = 2.0; 
// НОВЕ: Налаштування порогу піни. Чим менше значення, тим більше піни на хвилях.
uniform float surface_foam_threshold : hint_range(0.3, 0.9, 0.05) = 0.6; 

uniform sampler2D DEPTH_TEXTURE : hint_depth_texture, filter_linear_mipmap;

varying vec3 world_pos_var;
varying float v_ocean_depth;

void vertex() {
	world_pos_var = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_ocean_depth = COLOR.r; 

	vec2 uv = world_pos_var.xz * wave_scale + (TIME * wave_speed);
	float noise_val = textureLod(noise_texture, uv, 0.0).r;

	// Збільшено мінімальну висоту хвиль біля берега (з 0.2 до 0.35)
	float shore_fade = max(0.35, smoothstep(0.0, 0.5, v_ocean_depth));
	
	// ВИПРАВЛЕНО: Множимо шум на 2.0, щоб "розтягнути" його амплітуду. 
	// Це змусить воду фізично підійматися набагато вище.
	float wave_h = (noise_val * 2.0 - 1.0) * wave_height_total * shore_fade;
	VERTEX.y += wave_h;
}

void fragment() {
	vec2 uv = world_pos_var.xz * wave_scale + (TIME * wave_speed);
	vec3 ns = texture(noise_texture, uv).rgb;

	// --- 1. ГЛИБИНА ВОДИ ---
	float depth_tex = textureLod(DEPTH_TEXTURE, SCREEN_UV, 0.0).r;
	vec4 ndc = vec4(SCREEN_UV * 2.0 - 1.0, depth_tex, 1.0);
	vec4 view_pos = INV_PROJECTION_MATRIX * ndc;
	view_pos.xyz /= view_pos.w;
	float water_depth = max(0.0, VERTEX.z - view_pos.z);

	// --- 2. БАЗОВИЙ КОЛІР ---
	float toon_mask = smoothstep(0.4, 0.5, ns.r); 
	vec3 water_base = mix(toon_dark, col_lake, toon_mask);
	water_base = mix(water_base, col_ocean, v_ocean_depth * 0.7);

	// ==========================================
	// 3. ПІНА (Відкрите море + Берег)
	// ==========================================
	
	// Піна на хвилях (використовуємо новий параметр, щоб ви могли керувати цим з Інспектора)
	float surface_foam = smoothstep(surface_foam_threshold, surface_foam_threshold + 0.1, ns.r);

	// ПОВЕРНУТО З ВАШОГО КОДУ: Синусоїда для потужного накочування на берег
	float wave_pulse = sin(water_depth * 4.0 - TIME * 4.0) * 0.5 + 0.5;
	
	// Зона накочування (біля самого берега)
	float shore_zone = smoothstep(0.0, 0.2, water_depth) * (1.0 - smoothstep(0.5, 2.5, water_depth));
	
	// Змішуємо синусоїду пульсу з шумом FBM, щоб хвиля була рваною (мультяшною) і активною
	float rolling_foam = shore_zone * wave_pulse * smoothstep(0.35, 0.65, ns.r) * 2.5;

	// Абсолютний край: гарантуємо, що самий стик із піском завжди має тонку білу лінію
	float edge_line = step(water_depth, 0.15);

	// Об'єднуємо всю піну
	float total_foam = clamp(surface_foam + rolling_foam + edge_line, 0.0, 1.0);
	vec3 final_color = mix(water_base, foam_color, total_foam);

	// --- 4. НОРМАЛІ ТА ВІДБЛИСКИ ---
	vec3 normal_noise = texture(noise_texture, uv * 2.0).rgb;
	NORMAL = normalize(NORMAL + (normal_noise - 0.5) * 0.5);

	ALBEDO = final_color;
	SPECULAR = 0.5; 
	ROUGHNESS = mix(0.1, 0.9, total_foam); 
	
	// --- 5. ПРОЗОРІСТЬ ---
	float alpha_fade = smoothstep(0.0, 1.5, water_depth);
	ALPHA = mix(0.4, 0.95, alpha_fade); 
	if (total_foam > 0.1) ALPHA = 1.0; 
}