shader_type spatial;
render_mode world_vertex_coords, depth_draw_always, cull_disabled;


#include "OceanCommon.gdshaderinc"


// Sun specular highlight
uniform float specular_strength = 1.0;
uniform float specular_power = 1500.0;

// ALPHA will begin decreasing to 0.0 after view_distance_max * view_fade_start
uniform float view_fade_start = 0.95;

// Colors & Depth Blend (ОНОВЛЕНО ДЛЯ СТИЛІЗОВАНОЇ ВОДИ)
uniform vec4 deep_color:source_color = vec4(0.004f, 0.016f, 0.047f, 1.0);
uniform vec4 shallow_color:source_color = vec4(0, 0.729412, 0.988235, 1);
uniform float depth_blend_max = 15.0; // На якій глибині (в метрах) вода стає повністю "deep_color"
uniform float depth_blend_power = 2.5; // Наскільки різким є перехід кольору


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
//uniform float refraction_distance_power = 1.55;
//uniform float refraction_distance_max = 30000.0;
uniform float refraction_background_brightness = 0.2;
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

// --- НАЛАШТУВАННЯ БЕРЕГОВОГО ЗАТУХАННЯ ---
uniform sampler2D terrain_heightmap : hint_default_black; // Твоя мапа шумів
uniform float terrain_scale = 1000.0; // Масштаб шуму (має співпадати з генерацією землі)
//uniform float terrain_max_height = 100.0; // Максимальна висота гір/землі у твоєму світі
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
	
	// СТВОРЕННЯ domain_warped_uv (Саме цього рядка тобі не вистачало)
	vec2 domain_warped_uv = domain_warp(VERTEX.xz, linear_dist);
	
	// Отримуємо базове зміщення хвиль
	vec3 displacement = get_displacement(domain_warped_uv);
	
	// --- МАГІЯ ЗАТУХАННЯ ХВИЛЬ (Синхронізована з GDScript) ---
	// 1. Зчитуємо базовий шум (e), який формує континенти
	vec2 noise_uv = VERTEX.xz / terrain_scale; 
	float e = texture(terrain_heightmap, noise_uv).r; // Це твій get_raw_elevation
	
	// 2. Рахуємо висоту дна за ТВОЄЮ формулою з _get_final_height
	// Якщо e < 0.35 (це під водою), рахуємо реальне дно. 
	// Якщо e >= 0.35 (це суша), нам байдуже на гори, просто ставимо висоту 5.0 (рівень води)
	float ground_height = 5.0; 
	if (e < 0.35) {
		ground_height = 5.0 + (e - 0.35) * 40.0;
	}
	
	// 3. Рахуємо глибину від поверхні (вона у нас локально на 0.0, але світ глобально зміщений)
	float water_surface_height = 5.0; // Твоя базова висота води
	float depth_at_vertex = water_surface_height - ground_height; 
	
	// 4. Створюємо множник затухання.
	// shore_wave_damp_distance - це глибина (в метрах), на якій хвиля вже має повну силу.
	float wave_damp = smoothstep(0.0, shore_wave_damp_distance, depth_at_vertex);
	wave_damp = max(0.15, wave_damp); 
	
	displacement.y *= wave_damp;
	
	// 5. Придавлюємо хвилі по висоті
	displacement.y *= wave_damp;
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
	// Fresnel
	float fresnel_factor = clamp(pow(abs(1.0 - dot(NORMAL, normalize(VIEW))), fresnel_power), -1.0, 1.0);
	float fresnel = fresnel_factor * fresnel_strength + fresnel_offset;
	
	// РОЗРАХУНОК РЕАЛЬНОЇ ГЛИБИНИ ВОДИ (Товщина шару води)
	float depth = texture(depth_texture, SCREEN_UV).r;
	vec3 ndc = vec3(SCREEN_UV * 2.0 - 1.0, depth);
	vec4 view = INV_PROJECTION_MATRIX * vec4(ndc, 1.0);
	view.xyz /= view.w;
	
	float linear_depth = -view.z; // Глибина до дна
	float water_depth = -VERTEX.z; // Глибина до поверхні води
	float depth_difference = max(0.0, linear_depth - water_depth); // Фактична товщина води!
	
	float linear_dist = length(world_vertex - CAMERA_POSITION_WORLD);
	
	// 6. ПОЛІНОМІАЛЬНИЙ СПУСК ТА ГРАДІЄНТ КОЛЬОРУ
	// Використовуємо pow() для різкого переходу (графік поліному)
	float depth_blend_factor = clamp(depth_difference / depth_blend_max, 0.0, 1.0);
	depth_blend_factor = pow(depth_blend_factor, depth_blend_power); 
	
	// Отримуємо зображення дна (рефракція)
	float refraction_factor = clamp(depth_difference * refraction_depth_factor, refraction_factor_min, refraction_factor_max);
	vec2 refracted_uv = SCREEN_UV - NORMAL.xz * refraction_factor;
	vec3 refracted_bg = textureLod(screen_texture, refracted_uv, 0.0).rgb;
	
	// 4. ЛАЗУРНИЙ ПЕРЕЛИВ (без ефекту брудного скла)
	// Спочатку змішуємо колір мілини та глибини
	vec3 base_water_color = mix(shallow_color.rgb, deep_color.rgb, depth_blend_factor);
	
	// Визначаємо, наскільки вода перекриває дно. Навіть на нулі вона має 40% кольору
	float opacity_blend = clamp(depth_difference * 0.5, 0.4, 1.0); 
	
	// Фінальний колір води (дно + лазур + відбиття)
	vec3 water_color = mix(refracted_bg, base_water_color, opacity_blend) * (1.0 - fresnel);
	
	// Fresnel Shading (Додаємо небо)
	vec3 sky = fresnel_sky_color.rgb * fresnel;
	vec3 water = water_color * fresnel_sky_color.rgb;
	water_color = HDR(sky + water, fresnel_exposure);
	
	// Баранці (Оригінальний код)
	float base_foam_mix = clamp((-jacobian_determinant + foam_jacobian_limit) * foam_coverage, 0.0, 1.0);
	base_foam_mix = (base_foam_mix * base_foam_mix) * foam_mix_strength;
	
	// БЕРЕГОВА ПІНА (Shoreline Foam)
	float shore_noise = texture(foam_texture, world_vertex.xz * 0.05 + vec2(TIME * 0.03, TIME * 0.015)).r;
	float shore_mask = smoothstep(shoreline_foam_cutoff, 0.0, depth_difference);
	shore_mask = smoothstep(0.4, 0.7, shore_mask * shore_noise * shoreline_foam_intensity);
	
	// Змішуємо всі типи піни
	foam_mix_factor = clamp(base_foam_mix + shore_mask, 0.0, 1.0);
	vec3 base_foam_tex = texture(foam_texture, world_vertex.xz * uv_scale).rgb;
	vec3 final_foam_color = mix(base_foam_tex, shoreline_foam_color.rgb, shore_mask);

	ALBEDO = mix(water_color, final_foam_color, foam_mix_factor);
	foam_specular_factor = (1.0 - foam_mix_factor);
	
	// СПРАВЖНЯ ПРОЗОРІСТЬ (Depth Alpha)
	// Використовуємо поліноміальний фактор, щоб прозорість зникала красивіше
	float depth_alpha = smoothstep(0.0, depth_blend_max * 0.5, depth_difference);
	
	// ВАЖЛИВО: Піна має залишатися непрозорою, навіть на нульовій глибині
	float final_water_alpha = max(depth_alpha, foam_mix_factor);
	
	// Distance Fade (затухання океану вдалині на горизонті)
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