shader_type spatial;
render_mode cull_disabled, diffuse_toon;

uniform vec3 color_bottom : source_color = vec3(0.05, 0.25, 0.05);
uniform vec3 color_top : source_color = vec3(0.3, 0.6, 0.15);
uniform sampler2D color_noise; // Сюди покладемо FastNoiseLite для "плям" на полі
uniform float noise_scale = 20.0;
uniform float wind_speed = 1.5;
uniform float wind_strength = 0.2;

varying vec3 world_pos;

void vertex() {
	// Отримуємо глобальні координати для синхронного вітру
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	
	// Хвилі вітру, що перекочуються по всьому полю
	float wind = sin(world_pos.x * 0.5 + TIME * wind_speed) * sin(world_pos.z * 0.5 + TIME * wind_speed * 0.8);
	
	// Чим вище точка травинки (VERTEX.y), тим сильніше вона гнеться
	float height_factor = max(0.0, VERTEX.y);
	VERTEX.x += wind * wind_strength * height_factor;
	VERTEX.z += wind * wind_strength * height_factor * 0.5;
}

void fragment() {
	// Беремо значення шуму, щоб трава мала різні відтінки зеленого
	float noise = texture(color_noise, world_pos.xz / noise_scale).r;
	
	// Робимо плавний градієнт від корінців до верхівки
	// (У моделі StayAtHomeDev зазвичай UV.y йде знизу вгору. Якщо трава раптом темна зверху — зміни UV.y на (1.0 - UV.y))
	vec3 base_color = mix(color_bottom, color_top, UV.y);
	
	// Додаємо плями світлішої/темнішої трави
	ALBEDO = mix(base_color, base_color * 1.3, noise * 0.5);
	ROUGHNESS = 0.8;
	
	// МАГІЯ З ВІДЕО: Фікс нормалей. Тепер трава не має чорних тіней на задній стороні!
	if (!FRONT_FACING) {
		NORMAL = -NORMAL;
	}
}