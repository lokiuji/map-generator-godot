shader_type spatial;

// ambient_light_disabled - МАГІЯ! Godot більше не буде світити на траву синім небом.
// diffuse_toon - робить перехід між світлом і тінню різким (ААА-стилізація)
render_mode depth_draw_opaque, diffuse_toon, ambient_light_disabled;

// Текстура тепер використовується ТІЛЬКИ для форми (Альфа-каналу)
uniform sampler2D alpha_texture : filter_nearest; 
// Текстура шуму для вітру (обов'язково увімкни Seamless у налаштуваннях!)
uniform sampler2D wind_noise : repeat_enable; 

// === 3 КОЛЬОРИ З ВІДЕО ===
uniform vec3 color_bottom : source_color = vec3(0.12, 0.28, 0.08); // Темний (під колір землі)
uniform vec3 color_top : source_color = vec3(0.25, 0.42, 0.12);    // Яскраво-зелений
uniform vec3 color_wind : source_color = vec3(0.40, 0.60, 0.20);   // Сонячний відблиск на вітрі

uniform float wind_speed = 0.5;
uniform float wind_strength = 0.3;

uniform float fade_start = 120.0; 
uniform float fade_end = 150.0;   

varying vec3 world_pos;
varying float wind_val;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	
	// Зменшення вдалині (щоб не було різких меж рендеру)
	float dist = distance(world_pos, CAMERA_POSITION_WORLD);
	float scale = 1.0 - smoothstep(fade_start, fade_end, dist);
	VERTEX *= scale; 
	
	// Отримуємо значення шуму для вітру і плям світла
	vec2 noise_uv = (world_pos.xz * 0.02) + (vec2(1.0, 0.5) * TIME * wind_speed);
	wind_val = texture(wind_noise, noise_uv).r;
	
	// Гнемо траву
	float height_factor = max(0.0, VERTEX.y); 
	VERTEX.x += wind_val * wind_strength * height_factor * scale;
	VERTEX.z += wind_val * wind_strength * 0.5 * height_factor * scale;
}

void fragment() {
	// 1. ФОРМА: Вирізаємо травинку, ігноруючи її реальний колір
	vec4 tex = texture(alpha_texture, UV);
	ALPHA = tex.a;
	ALPHA_SCISSOR_THRESHOLD = 0.5; 
	
	// 2. КОЛІР: Міксуємо 3 кольори (як казав автор відео)
	vec3 base_color = mix(color_bottom, color_top, UV.y);
	// На верхівках трави (UV.y) з'являються світлі плями від вітру (wind_val)
	vec3 final_color = mix(base_color, color_wind, wind_val * UV.y * 0.8);
	
	ALBEDO = final_color;
	
	// 3. ЗНИЩУЄМО СИНЮШНІСТЬ ТІНЕЙ:
	// Оскільки ми вимкнули ембієнт неба, тіні були б чорними.
	// Ми додаємо 35% власного світіння, щоб тіні стали тепло-зеленими!
	EMISSION = final_color * 0.35;
	
	SPECULAR = 0.0; 
	METALLIC = 0.0;
	ROUGHNESS = 1.0;
	
	// Нормалі рівно вгору (у світовому просторі)
	NORMAL = (VIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz;
}