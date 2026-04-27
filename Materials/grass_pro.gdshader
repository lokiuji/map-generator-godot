shader_type spatial;
// ПРИБРАЛИ ambient_light_disabled! Тепер трава коректно реагує на сонце та небо
render_mode depth_draw_opaque, diffuse_toon;

uniform sampler2D alpha_texture : filter_nearest; 
uniform sampler2D wind_noise : repeat_enable; 

// Вистав тут свої улюблені кольори (або налаштуй в Інспекторі)
uniform vec3 color_bottom : source_color = vec3(0.12, 0.28, 0.08); 
uniform vec3 color_top : source_color = vec3(0.25, 0.42, 0.12);    
uniform vec3 color_wind : source_color = vec3(0.40, 0.60, 0.20);   

uniform float wind_speed = 0.5;
uniform float wind_strength = 0.3;

uniform float fade_start = 120.0; 
uniform float fade_end = 150.0;   

varying vec3 world_pos;
varying float wind_val;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	
	float dist = distance(world_pos, CAMERA_POSITION_WORLD);
	float scale = 1.0 - smoothstep(fade_start, fade_end, dist);
	VERTEX *= scale; 
	
	vec2 noise_uv = (world_pos.xz * 0.02) + (vec2(1.0, 0.5) * TIME * wind_speed);
	wind_val = texture(wind_noise, noise_uv).r;
	
	float height_factor = max(0.0, VERTEX.y); 
	VERTEX.x += wind_val * wind_strength * height_factor * scale;
	VERTEX.z += wind_val * wind_strength * 0.5 * height_factor * scale;
}

void fragment() {
	vec4 tex = texture(alpha_texture, UV);
	ALPHA = tex.a;
	ALPHA_SCISSOR_THRESHOLD = 0.5; 
	
	// Ступінь 3.0 означає, що перехід нелінійний. 
	// Низ і середина трави будуть дуже близькими до кольору поверхні (COLOR.rgb), 
	// і лише верхня третина почне різко ставати яскраво-зеленою.
	float tip_mask = pow(1.0 - UV.y, 3.0); 
	
	vec3 base_color = mix(COLOR.rgb, COLOR.rgb * 1.8, tip_mask);
	
	// Вітер також виділяє лише найвищі кінчики
	vec3 final_color = mix(base_color, COLOR.rgb * 2.2, wind_val * tip_mask * 0.5);
	
	ALBEDO = clamp(final_color, vec3(0.0), vec3(1.0));
	
	// ПРИБРАЛИ EMISSION! Трава більше не світиться у темряві
	SPECULAR = 0.0; 
	METALLIC = 0.0;
	ROUGHNESS = 1.0;
	
	// Форсуємо нормалі вгору, щоб трава освітлювалась як плоска земля
	vec3 up_normal = (VIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz;
	NORMAL = normalize(mix(NORMAL, up_normal, 0.9));
}
void light() {
	// 1. Рахуємо кут падіння сонячних променів на травинку
	float NdotL = dot(NORMAL, LIGHT);
	
	// 2. ІМІТАЦІЯ БАГУ (Штучна тінь):
	// Створюємо дуже різкий перехід від світла до тіні (toon shading).
	// Це дасть той самий контрастний об'єм, який ви бачили на краях екрану.
	float fake_shadow = smoothstep(0.0, 0.15, NdotL);
	
	// 3. Змішуємо нашу фейкову тінь з реальними тінями (ATTENUATION).
	// Тепер, навіть якщо реальна тінь у центрі екрану зникне, 
	// fake_shadow гарантовано залишить травинку наполовину затіненою!
	float final_shadow = min(fake_shadow, ATTENUATION);
	
	// 4. Налаштовуємо колір самої тіні
	// Множимо на 0.25, щоб тінь була глибокою, але не чорною (зберігала колір біому)
	vec3 shadow_color = ALBEDO * 0.25; 
	
	// 5. Застосовуємо освітлення: змішуємо темну та світлу сторони
	DIFFUSE_LIGHT += mix(shadow_color, ALBEDO * LIGHT_COLOR, final_shadow);
}