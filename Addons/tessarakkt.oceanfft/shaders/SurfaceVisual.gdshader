shader_type spatial;
render_mode world_vertex_coords, depth_draw_always, cull_disabled;


#include "OceanCommon.gdshaderinc"

// --- КАУСТИКА ---
uniform sampler2D caustic_texture : hint_default_black, repeat_enable;
uniform float caustic_scale = 0.2;
uniform float caustic_strength = 1.5;
uniform vec2 caustic_speed = vec2(0.05, 0.03);

// --- НАЛАШТУВАННЯ ЛОКАЛЬНОЇ МАПИ (Скан з камери) ---
uniform sampler2D terrain_heightmap;
uniform float local_map_size = 8000.0; // Збільшено до розмірів MapCamera!
uniform float min_terrain_height = -200.0; // Синхронізація зі сканером
uniform float max_terrain_height = 400.0;
uniform vec3 player_position;

// Sun specular highlight
uniform float specular_strength = 1.0;
uniform float specular_power = 1500.0;

// ALPHA will begin decreasing to 0.0 after view_distance_max * view_fade_start
uniform float view_fade_start = 0.95;

// Colors & Depth Blend (3-ЕТАПНИЙ ГРАДІЄНТ)
uniform vec4 deep_color:source_color = vec4(0.004, 0.016, 0.047, 1.0);
uniform vec4 mid_color:source_color = vec4(0.0, 0.3, 0.7, 1.0); // НОВИЙ: Колір середньої глибини
uniform vec4 shallow_color:source_color = vec4(0.0, 0.73, 0.99, 1.0);

uniform float depth_blend_max = 80.0;
uniform float depth_blend_power = 1.2;
// Де саме знаходиться проміжний колір (0.5 - рівно посередині)
uniform float mid_blend_position = 0.5;


group_uniforms ShorelineFoam;
/******************************************************************************/
// НОВИЙ БЛОК: Налаштування піни біля берега
uniform float shoreline_foam_cutoff = 1.5; // Як далеко від берега (за глибиною) малювати піну
uniform float shoreline_foam_intensity = 1.5; // Насиченість берегової піни
uniform vec4 shoreline_foam_color:source_color = vec4(1.0, 1.0, 1.0, 1.0);


group_uniforms Fresnel;
/******************************************************************************/
uniform float fresnel_offset = 0.02;
uniform float fresnel_strength = 0.0;
uniform float fresnel_power = 5.0;
uniform float fresnel_exposure = 0.03;
uniform vec4 fresnel_sky_color:source_color = vec4(1.6f, 4.8f, 6.4f, 1.0);


group_uniforms PhysicallyBasedRendering;
/******************************************************************************/
uniform float pbr_specular_strength = 0.1;
uniform float pbr_specular_offset = 0.1;
uniform float pbr_metallic_strength = 0.0;


group_uniforms Refraction;
/******************************************************************************/
uniform float refraction_factor_min = 0.0;
uniform float refraction_factor_max = 0.025;
uniform float refraction_depth_factor = 0.05; // Змінено для кращого ефекту на мілині


group_uniforms SubSurfaceScattering;
/******************************************************************************/
uniform float sss_backlight_strength = 0.0125;
uniform float sss_backlight_fov = 10.0;
uniform float sss_backlight_depth = 15.0;
uniform float sss_upwelling = 0.075;
uniform vec4 sss_color:source_color = vec4(0, 0.729412, 0.988235, 1);


group_uniforms Whitecaps;
/******************************************************************************/
uniform float foam_jacobian_limit = 0.5;
uniform float foam_coverage = 0.1;
uniform float foam_mix_strength = 1.0;
uniform float foam_diffuse_strength = 1.0;
uniform vec4 foam_diffuse_color:source_color = vec4(0.91764706373215, 0.96862745285034, 1.0, 1.0);
uniform sampler2D foam_texture : hint_default_white;


group_uniforms Internal;
/******************************************************************************/
uniform float vertex_resolution = 256.0;


group_uniforms Internal.WaveDeformModifiers;
/******************************************************************************/
uniform float planetary_curve_strength = 0.000001;
uniform float amplitude_scale_min = 0.25;
uniform float amplitude_scale_max = 1.0;
uniform float amplitude_scale_fade_distance = 12000.0;
uniform float shore_wave_damp_distance = 5.0; // За скільки метрів до дна хвилі починають згасати

uniform sampler2D depth_texture : hint_depth_texture, filter_linear_mipmap;
uniform sampler2D screen_texture : hint_screen_texture, filter_linear_mipmap;


// Uniforms (Без instance для уникнення багу C++)
/******************************************************************************/
uniform float patch_size = 512.0;
uniform float min_lod_morph_distance = 100.0;
uniform float max_lod_morph_distance = 2000.0;


// Varyings
/******************************************************************************/
varying vec3 world_vertex;
varying float jacobian_determinant;
varying float wave_height;
varying float foam_mix_factor;
varying float foam_specular_factor;
varying float v_ground_height; // Висота землі для оптимізації

vec2 lod_morph(float morph_factor, vec2 grid_pos) {
	vec2 fracPart = fract(grid_pos.xy * vertex_resolution * 0.5) * 2.0 / vertex_resolution;
	return fracPart * patch_size * morph_factor;
}


vec3 HDR(vec3 color, float e) {
	return 1.0 - exp(-color * e);
}


void vertex() {
	float linear_dist = length(VERTEX - CAMERA_POSITION_WORLD);
	
	// LOD Morph
	float morph_factor = (clamp(linear_dist, min_lod_morph_distance, max_lod_morph_distance) - min_lod_morph_distance) / (max_lod_morph_distance - min_lod_morph_distance);
	VERTEX.xz -= lod_morph(morph_factor, UV);
	
	// СТВОРЕННЯ domain_warped_uv
	vec2 domain_warped_uv = domain_warp(VERTEX.xz, linear_dist);
	
	// Отримуємо базове зміщення хвиль
	vec3 displacement = get_displacement(domain_warped_uv);
	
	// --- МАГІЯ ЗАТУХАННЯ ХВИЛЬ (Через локальну мапу Viewport) ---
	// 1. Отримуємо UV на локальній мапі
	vec2 map_uv = (VERTEX.xz - player_position.xz) / local_map_size + vec2(0.5);
	
	// 2. Зчитуємо висоту. Дефолт за межами мапи тепер: -100.0
	v_ground_height = -100.0; 
	if (map_uv.x >= 0.0 && map_uv.x <= 1.0 && map_uv.y >= 0.0 && map_uv.y <= 1.0) {
		float norm_h = texture(terrain_heightmap, map_uv).r;
		// Конвертуємо колір назад у метри
		v_ground_height = mix(min_terrain_height, max_terrain_height, norm_h);
	}
	
	// 3. АСИМПТОТИЧНЕ ЗАТУХАННЯ (М'який накат + Сильний відкат)
	if (v_ground_height > 5.5) {
		displacement = vec3(0.0); 
	} else {
		float depth_at_vertex = max(0.0, 5.0 - v_ground_height);
		float linear_damp = clamp(depth_at_vertex / shore_wave_damp_distance, 0.0, 1.0);
		
		// Базове затухання
		float wave_damp_y = pow(linear_damp, 1.5); 
		float wave_damp_xz = pow(linear_damp, 1.2); 
		
		// === ДИНАМІКА НАКАТУ ТА ВІДКАТУ ===
		float horizontal_modifier = 1.0;
		
		if (displacement.y < 0.0) {
			// ВІДКАТ (Впадина): вода відтягується назад. Підсилюємо всмоктування в море.
			horizontal_modifier = mix(2.5, 1.0, linear_damp); 
		} else {
			// НАКАТ (Гребінь): вода суне на берег. 
			// Чим ближче до берега (linear_damp -> 0), тим сильніше ми "гальмуємо" її горизонтальний рух.
			horizontal_modifier = mix(0.3, 1.0, linear_damp); 
		}
		
		displacement.y *= max(0.05, wave_damp_y);
		displacement.xz *= max(0.01, wave_damp_xz * horizontal_modifier);
	}
	// -----------------------------
	
	// Застосовуємо зміщення до сітки
	VERTEX += displacement;
	world_vertex = VERTEX; // Зберігаємо координати для фрагментного шейдера
	
	// Surface Normals & Jacobian
	vec4 nj = get_normals_jacobian(domain_warped_uv, displacement);
	NORMAL = nj.xyz * normal_factor;
	jacobian_determinant = nj.w;
	
	// Wave Amplitude Distance Fade
	float amplitude_fade_range = clamp(linear_dist, 0.0, amplitude_scale_fade_distance) / amplitude_scale_fade_distance;
	VERTEX.y *= mix(amplitude_scale_max, amplitude_scale_min, amplitude_fade_range);
	
	// Planetary Curve
	float curvation = planetary_curve_strength * (pow(abs(domain_warped_uv.x - CAMERA_POSITION_WORLD.x), 2.0) + pow(abs(domain_warped_uv.y - CAMERA_POSITION_WORLD.z), 2.0));
	VERTEX.y -= curvation;
}


void fragment() {
	// ЖОРСТКА ОПТИМІЗАЦІЯ: не малювати воду, якщо вона під землею!
	// ЗБІЛЬШИВ ЗАПАС ДО 6.0: Це дозволяє воді "зайти" в пісок, щоб ми мали місце для м'якого розмиття краю!
	if (v_ground_height > 6.0) {
		discard;
	}
	
	// Fresnel
	float fresnel_factor = clamp(pow(abs(1.0 - dot(NORMAL, normalize(VIEW))), fresnel_power), -1.0, 1.0);
	float fresnel = fresnel_factor * fresnel_strength + fresnel_offset;
	
	// РОЗРАХУНОК РЕАЛЬНОЇ ГЛИБИНИ ВОДИ
	// 1. КООРДИНАТИ ТА ГЛИБИНА
	float depth_raw = texture(depth_texture, SCREEN_UV).r;
	vec3 ndc = vec3(SCREEN_UV * 2.0 - 1.0, depth_raw);
	vec4 view = INV_PROJECTION_MATRIX * vec4(ndc, 1.0);
	view.xyz /= view.w;
	
	float linear_depth = -view.z; 
	float water_depth = -VERTEX.z; 
	float depth_difference = max(0.0, linear_depth - water_depth);
	
	// Світові координати дна та стабільна вертикальна глибина
	vec4 world_ground_pos = INV_VIEW_MATRIX * vec4(view.xyz, 1.0);
	float vertical_depth = max(0.0, world_vertex.y - world_ground_pos.y);
	
	// Рефракція
	float refraction_factor = clamp(depth_difference * refraction_depth_factor, refraction_factor_min, refraction_factor_max);
	vec2 refracted_uv = SCREEN_UV - NORMAL.xz * refraction_factor;
	vec3 refracted_bg = textureLod(screen_texture, refracted_uv, 0.0).rgb;
	
	// ========================================================
	// === КАУСТИКА (ЖОРСТКО НА ДНІ) ===
	// ========================================================
	vec3 world_normal = (INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz;
	
	// ВИКОРИСТОВУЄМО world_ground_pos (координати піску)
	vec2 base_caustic_uv = world_ground_pos.xz * caustic_scale;
	vec2 distorted_uv = base_caustic_uv + (world_normal.xz * 2.5);
	
	float caustic_r = texture(caustic_texture, distorted_uv + vec2(0.005, 0.0)).r;
	float caustic_g = texture(caustic_texture, distorted_uv).g;
	float caustic_b = texture(caustic_texture, distorted_uv - vec2(0.005, 0.0)).b;
	vec3 caustic_color = vec3(caustic_r, caustic_g, caustic_b) * caustic_strength;
	
	// Сонячні зайчики від хвиль
	float light_focus = smoothstep(0.8, 1.0, world_normal.y);
	caustic_color += caustic_color * light_focus * 1.5;
	
	// Каустика зникає на глибині більше 15 метрів (залежить від вертикалі)
	float caustic_fade = smoothstep(15.0, 0.0, vertical_depth);
	vec3 lit_bottom = refracted_bg + (caustic_color * caustic_fade);

	// ========================================================
	// === ОБ'ЄМНЕ ПОГЛИНАННЯ ТА IN-SCATTERING ===
	// ========================================================
	vec3 absorption_coeff = vec3(1.2, 0.5, 0.1); 
	vec3 transmittance = exp(-absorption_coeff * vertical_depth);
	vec3 underwater_scene = lit_bottom * transmittance;
	
	float volume_blend = clamp(vertical_depth / depth_blend_max, 0.0, 1.0);
	volume_blend = pow(volume_blend, depth_blend_power);
	
	float t1 = clamp(volume_blend / mid_blend_position, 0.0, 1.0);
	float t2 = clamp((volume_blend - mid_blend_position) / (1.0 - mid_blend_position), 0.0, 1.0);
	vec3 water_volume_color = mix(mix(shallow_color.rgb, mid_color.rgb, t1), deep_color.rgb, t2);
	
	// Базовий колір води до застосування неба та HDR
	vec3 base_water_color = underwater_scene + (water_volume_color * (1.0 - transmittance));

	// HDR Корекція та Небо
	float sky_brightness = max(fresnel_sky_color.r, max(fresnel_sky_color.g, fresnel_sky_color.b));
	vec3 sky = fresnel_sky_color.rgb * fresnel;
	vec3 water = base_water_color * sky_brightness;
	
	// ЗАСТОСОВУЄМО HDR ДО ВОДИ
	vec3 final_water_color = HDR(sky + water, fresnel_exposure);

	// ========================================================
	// === ФЕЙКОВІ ПРОМЕНІ СВІТЛА (GOD RAYS 2.0 - ОБ'ЄМНІ) ===
	// ========================================================
	// 1. Беремо 3D-центр товщі води. Це дасть ефект паралаксу (справжнього об'єму)
	vec3 ray_pos = mix(world_vertex, world_ground_pos.xyz, 0.5);
	
	// 2. Рух променів
	vec2 ray_uv = ray_pos.xz * (caustic_scale * 0.3) + vec2(TIME * 0.02);
	
	// 3. Зчитуємо шум
	float ray_noise = texture(caustic_texture, ray_uv).r;
	
	// 4. МАГІЯ ВИДИМОСТІ: smoothstep створює шалений контраст.
	// Відсікаємо все тьмяне (від 0.0 до 0.6), залишаємо лише яскраві "лазерні" пучки.
	ray_noise = smoothstep(0.6, 0.95, ray_noise);
	
	// 5. Сила залежить від товщі води. На мілині їх нема, на глибині - вони потужні.
	float ray_volume_mask = clamp(vertical_depth * 0.15, 0.0, 1.0);
	
	// 6. Формуємо промені (Множник 5.0 - щоб вони світилися як неонові стовпи)
	vec3 god_rays = shallow_color.rgb * ray_noise * ray_volume_mask * 5.0;
	
	// ВАЖЛИВО: Додаємо промені ПІСЛЯ HDR! Інакше функція HDR знову стисне їхню яскравість у нуль.
	final_water_color += god_rays;

	// ========================================================
	// === ПІНА ТА ФІНАЛЬНИЙ ALBEDO ===
	// ========================================================
	float base_foam_mix = clamp((-jacobian_determinant + foam_jacobian_limit) * foam_coverage, 0.0, 1.0);
	base_foam_mix = (base_foam_mix * base_foam_mix) * foam_mix_strength;
	
	// БЕРЕГОВА ПІНА
	float shore_noise = texture(foam_texture, world_vertex.xz * 0.05 + vec2(TIME * 0.03, TIME * 0.015)).r;
	float shore_mask = smoothstep(shoreline_foam_cutoff, 0.0, depth_difference);
	shore_mask = smoothstep(0.4, 0.7, shore_mask * shore_noise * shoreline_foam_intensity);
	
	// Змішуємо всі типи піни
	foam_mix_factor = clamp(base_foam_mix + shore_mask, 0.0, 1.0);
	vec3 base_foam_tex = texture(foam_texture, world_vertex.xz * uv_scale).rgb;
	vec3 final_foam_color = mix(base_foam_tex, shoreline_foam_color.rgb, shore_mask);

	// Фінальний вивід кольору
	ALBEDO = mix(final_water_color, final_foam_color, foam_mix_factor);
	foam_specular_factor = (1.0 - foam_mix_factor);
	
	// СПРАВЖНЯ ПРОЗОРІСТЬ (Depth Alpha)
	float depth_alpha = smoothstep(0.0, depth_blend_max * 0.5, depth_difference);
	
	// === НОВЕ: М'ЯКИЙ КРАЙ БЕРЕГА ===
	float edge_fade = smoothstep(0.0, 0.4, depth_difference);
	
	// Піна плавно розчиняється в піску на останніх 40 сантиметрах.
	float final_water_alpha = max(depth_alpha, foam_mix_factor) * edge_fade;
	
	// Distance Fade (затухання океану вдалині на горизонті)
	float linear_dist = length(world_vertex - CAMERA_POSITION_WORLD);
	float fade_start = view_distance_max * view_fade_start;
	float dist_alpha = 1.0 - (clamp(linear_dist, fade_start, view_distance_max) - fade_start) / (view_distance_max - fade_start);
	
	// Застосовуємо альфу
	ALPHA = final_water_alpha * dist_alpha;
	
	// Misc. PBR Settings
	ROUGHNESS = foam_mix_factor + 0.02;
	METALLIC = pbr_metallic_strength * foam_specular_factor;
	SPECULAR = pbr_specular_strength * foam_specular_factor * fresnel_factor + pbr_specular_offset;
	
	wave_height = world_vertex.y;
}


void light() {
	vec3 half_vector = normalize(LIGHT + VIEW);
	
	// Specular
	float spec = clamp(pow(dot(NORMAL, half_vector), specular_power), 0.0, 1.0) * specular_strength;
	SPECULAR_LIGHT += (LIGHT_COLOR * ALBEDO * ATTENUATION / PI) * clamp(dot(NORMAL, half_vector), 0.0, 1.0) * foam_specular_factor;
	SPECULAR_LIGHT += LIGHT_COLOR * ATTENUATION * spec * foam_specular_factor;
	
	// Sub Surface Scattering
	vec3 sss_sun_light = sss_color.rgb * ATTENUATION;
	
	float sss = sss_backlight_strength * max(0.0, wave_height + sss_backlight_depth) * pow(max(0.0, dot(-LIGHT, VIEW)), 4.0);
	sss *= pow(0.5 - 0.5 * dot(-LIGHT, half_vector), 3.0);
	sss *= sss_backlight_fov * pow(max(0.0, dot(VIEW, half_vector)) , 2.0);
	vec3 sss_result = sss * sss_sun_light;
	
	sss_result += sss_upwelling * max(0.0, dot(LIGHT, half_vector)) * sss_sun_light;
	SPECULAR_LIGHT += sss_result * foam_specular_factor;
	
	// Foam Lighting (Тепер освітлює і берегову піну теж)
	DIFFUSE_LIGHT += foam_diffuse_strength * foam_mix_factor * foam_diffuse_color.rgb * ATTENUATION;
}