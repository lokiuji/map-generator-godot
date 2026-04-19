shader_type spatial;
// Вода має бути прозорою, і ми не рендеримо її задню частину
render_mode depth_draw_opaque, specular_toon, cull_back;

// === КОЛЬОРИ ===
uniform vec3 shallow_color : source_color = vec3(0.15, 0.70, 0.75); // Тропічний бірюзовий
uniform vec3 deep_color : source_color = vec3(0.02, 0.20, 0.45);    // Глибокий синій
uniform vec3 foam_color : source_color = vec3(1.0, 1.0, 1.0);       // Біла піна

// === ПАРАМЕТРИ ===
uniform float wave_speed = 0.4;
uniform float wave_height = 0.6; // Висота хвиль

// === ГЛИБИНА І ПІНА ===
uniform sampler2D depth_texture : hint_depth_texture, filter_nearest;
uniform float depth_fade_distance = 6.0; // Як швидко вода стає темною
uniform float foam_distance = 0.4;       // Товщина лінії піни біля берега

// === ТЕКСТУРА ХВИЛЬ ===
// Сюди в Інспекторі треба буде додати FastNoiseLite!
uniform sampler2D wave_noise : repeat_enable;

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	
	// Рухаємо воду по вертикалі, створюючи плавні хвилі
	float wave = sin(world_pos.x * 0.2 + TIME * wave_speed) * cos(world_pos.z * 0.2 + TIME * wave_speed);
	VERTEX.y += wave * wave_height;
}

void fragment() {
	// === 1. МАТЕМАТИКА ГЛИБИНИ (Depth Buffer) ===
	// Зчитуємо справжню глибину землі під водою
	float raw_depth = texture(depth_texture, SCREEN_UV).r;
	vec3 ndc = vec3(SCREEN_UV * 2.0 - 1.0, raw_depth);
	vec4 view = INV_PROJECTION_MATRIX * vec4(ndc, 1.0);
	view.xyz /= view.w;
	float linear_depth = -view.z;
	
	// Відстань від поверхні води до землі під нею (в метрах)
	float water_depth = max(0.0, linear_depth + VERTEX.z);

	// === 2. КОЛІР ТА ПІНА ===
	// Плавний перехід кольору залежно від глибини
	float depth_blend = smoothstep(0.0, depth_fade_distance, water_depth);
	vec3 base_color = mix(shallow_color, deep_color, depth_blend);

	// Піна біля берега (малюється тільки там, де глибина менша за foam_distance)
	float edge_foam = 1.0 - smoothstep(0.0, foam_distance, water_depth);

	// Додаємо шум на поверхню води (щоб хвилі мали світлі бліки і піну на гребенях)
	vec2 noise_uv = world_pos.xz * 0.04 + TIME * wave_speed * 0.1;
	float noise_val = texture(wave_noise, noise_uv).r;
	
	// Піна на верхівках хвиль
	float crest_foam = smoothstep(0.65, 0.9, noise_val) * 0.4;

	// Об'єднуємо всю піну
	float total_foam = clamp(edge_foam + crest_foam, 0.0, 1.0);

	// === 3. ФІНАЛЬНИЙ ВИВІД ===
	// Застосовуємо кольори (піна перекриває воду)
	ALBEDO = mix(base_color, foam_color, total_foam);
	
	// Прозорість: на мілководді вода на 70% прозора, на глибині або там де піна — 100% непрозора
	ALPHA = mix(0.7, 1.0, clamp(depth_blend + total_foam, 0.0, 1.0));

	ROUGHNESS = 0.15; // Вода майже гладка
	METALLIC = 0.1;
	SPECULAR = 0.8;   // Гарні відблиски сонця
	
	// Легке спотворення нормалей для бліків на хвилях
	NORMAL_MAP = vec3(noise_val * 0.1, 1.0, noise_val * 0.1);
}