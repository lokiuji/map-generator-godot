shader_type spatial;
render_mode blend_mix, depth_draw_always, specular_toon;

// === КОЛЬОРИ З ТУТОРІАЛУ ===
uniform vec3 albedo : source_color = vec3(0.0, 0.32, 0.43);
uniform vec3 albedo2 : source_color = vec3(0.0, 0.47, 0.76);
uniform vec3 color_deep : source_color = vec3(0.11, 0.29, 0.33);
uniform vec3 color_shallow : source_color = vec3(0.0, 0.47, 0.76);
uniform vec3 edge_color : source_color = vec3(1.0, 1.0, 1.0); // Піна

uniform float metallic : hint_range(0.0, 1.0) = 0.0;
uniform float roughness : hint_range(0.0, 1.0) = 0.02;

// === ТЕКСТУРИ ХВИЛЬ ===
uniform sampler2D wave; // Шум для висоти (Vertex)
uniform sampler2D texture_normal; // Нормалі 1
uniform sampler2D texture_normal2; // Нормалі 2

uniform vec2 wave_direction = vec2(2.0, 0.0);
uniform vec2 wave_direction2 = vec2(0.0, 1.0);
uniform float time_scale : hint_range(0.0, 0.2, 0.005) = 0.025;
uniform float noise_scale = 10.0;
uniform float height_scale = 0.6; // Висота фізичних хвиль

// === ПАРАМЕТРИ ГЛИБИНИ (Beer's Law) ===
uniform float beers_law = 0.5; // Наскільки швидко вода темнішає
uniform float depth_offset = -0.1;
uniform float edge_scale = 0.3; // Ширина піни біля берега

uniform sampler2D DEPTH_TEXTURE : hint_depth_texture, filter_linear_mipmap;

varying vec3 world_pos;

// Функція Френеля для відблисків під кутом
float fresnel(float amount, vec3 normal, vec3 view) {
	return pow((1.0 - clamp(dot(normalize(normal), normalize(view)), 0.0, 1.0)), amount);
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	
	// Зчитуємо маску біомів (1.0 = Океан, 0.0 = Берег/Озеро)
	float wave_mask = COLOR.r;
	
	// Фізично піднімаємо полігони води (Генерація хвиль)
	float height = texture(wave, world_pos.xz / noise_scale + TIME * time_scale).r;
	
	// МНОЖИМО НА МАСКУ! 
	// Тепер на березі (де mask = 0.0) висота хвиль дорівнюватиме 0. Вода буде ідеально рівною.
	VERTEX.y += height * height_scale * wave_mask;
}

void fragment() {
	// === 1. ТОЧНА МАТЕМАТИКА ГЛИБИНИ ===
	float depth_tex = textureLod(DEPTH_TEXTURE, SCREEN_UV, 0.0).r;
	vec4 ndc = vec4(SCREEN_UV * 2.0 - 1.0, depth_tex, 1.0);
	vec4 view_pos = INV_PROJECTION_MATRIX * ndc;
	view_pos.xyz /= view_pos.w;
	float water_depth = max(0.0, VERTEX.z - view_pos.z);

	// === 2. ЗАКОН БЕРА (Beer's Law) ===
	float depth_blend = exp((water_depth + depth_offset) * -beers_law);
	depth_blend = clamp(1.0 - depth_blend, 0.0, 1.0);	
	float depth_blend_power = clamp(pow(depth_blend, 2.5), 0.0, 1.0);

	vec3 screen_color = mix(color_shallow, color_deep, depth_blend_power);
	
	// === 3. ДВІ КАРТИ НОРМАЛЕЙ (Схрещені хвилі) ===
	vec2 time = (TIME * wave_direction) * time_scale; 
	vec2 time2 = (TIME * wave_direction2) * time_scale; 
	// Додав * 0.05, щоб дрібні текстури не розтягувались на весь світ
	vec3 normal_blend = mix(
		texture(texture_normal, world_pos.xz * 0.05 + time).rgb, 
		texture(texture_normal2, world_pos.xz * 0.05 + time2).rgb, 
		0.5
	);
	
	// === 4. ФРЕНЕЛЬ ТА ПІНА ===
	float fres = fresnel(5.0, NORMAL, VIEW);
	vec3 surface_color = mix(albedo, albedo2, fres);
	
	float z_depth = edge_scale - depth_blend;
	float z_foam = step(z_depth, 0.0);
	vec3 depth_color_adj = mix(edge_color, screen_color, z_foam);
	
	// === ФІНАЛЬНИЙ ВИВІД ===
	ALBEDO = clamp(surface_color + depth_color_adj, vec3(0.0), vec3(1.0));
	METALLIC = metallic;
	ROUGHNESS = roughness;
	NORMAL_MAP = normal_blend;
	
	// РОБИМО ПРОЗОРІСТЬ: На мілині вода прозора (0.4), на глибині густа (0.95)
	ALPHA = mix(0.4, 0.95, depth_blend_power);
}