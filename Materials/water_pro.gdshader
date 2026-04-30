shader_type spatial;
render_mode blend_mix, depth_draw_always, specular_toon;

// ==========================================
// МЕНЮ НАЛАШТУВАНЬ
// ==========================================
group_uniforms Colors;
uniform vec3 col_lake : source_color = vec3(0.05, 0.6, 0.85);
uniform vec3 col_ocean : source_color = vec3(0.01, 0.1, 0.3);
uniform vec3 foam_color : source_color = vec3(1.0, 1.0, 1.0);
uniform vec3 toon_dark : source_color = vec3(0.0, 0.1, 0.2);

group_uniforms Deep_Ocean;
uniform float ocean_amplitude : hint_range(0.0, 5.0) = 1.0;
uniform float ocean_chaos_strength : hint_range(0.0, 5.0) = 1.5; 
uniform float ocean_chaos_scale : hint_range(0.01, 0.5) = 0.05; 
uniform vec4 wave_1 = vec4(1.0, 0.4, 0.4, 25.0); 
uniform vec4 wave_2 = vec4(-0.7, 0.7, 0.3, 12.0);
uniform vec4 wave_3 = vec4(0.2, -0.9, 0.2, 5.0);

group_uniforms Coastal_Physics;
// Shoaling: Наскільки хвиля "виростає" і загострюється перед ударом об берег
uniform float shoaling_power : hint_range(0.0, 5.0) = 2.0; 
uniform float shore_wave_height : hint_range(0.0, 3.0) = 0.5; 
uniform float shore_roll_distance : hint_range(0.0, 5.0) = 1.5; 
uniform float shore_speed : hint_range(0.01, 5.0) = 0.25; 
// 0.2 означає: 20% часу хвиля агресивно накочується (Run-up), 80% - повільно відступає (Backwash)
uniform float shore_in_out_ratio : hint_range(0.1, 0.9) = 0.2; 
uniform vec2 shore_push_dir = vec2(1.0, 0.5); 

group_uniforms Foam_and_Wetness;
uniform float foam_sharpness : hint_range(0.01, 0.2) = 0.08; 
uniform float interference_foam : hint_range(0.0, 2.0) = 1.0; // Сила піни при зіткненні накату і відкату
uniform float wet_sand_darkness : hint_range(0.0, 1.0) = 0.8; 

group_uniforms Technical;
uniform sampler2D DEPTH_TEXTURE : hint_depth_texture, filter_linear_mipmap;
group_uniforms;

varying vec3 world_pos_var;
varying float v_ocean_depth;
varying float v_wave_height;
varying vec3 v_gerstner_normal;
varying float v_dist;
varying float v_dist_phase; 

// --- ШУМИ ---
vec2 random(vec2 uv) {
	uv = vec2(dot(uv, vec2(127.1, 311.7)), dot(uv, vec2(269.5, 183.3)));
	return -1.0 + 2.0 * fract(sin(uv) * 43758.5453123);
}

float noise(vec2 uv) {
	vec2 i = floor(uv); vec2 f = fract(uv);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(dot(random(i + vec2(0.0, 0.0)), f - vec2(0.0, 0.0)),
	               dot(random(i + vec2(1.0, 0.0)), f - vec2(1.0, 0.0)), u.x),
	           mix(dot(random(i + vec2(0.0, 1.0)), f - vec2(0.0, 1.0)),
	               dot(random(i + vec2(1.0, 1.0)), f - vec2(1.0, 1.0)), u.x), u.y);
}

float fbm(vec2 uv) {
	float val = 0.0; float amp = 0.5;
	for(int i = 0; i < 4; i++) {
		val += amp * noise(uv); uv *= 2.0; amp *= 0.5;
	}
	return val * 0.5 + 0.5;
}

// --- ФІЗИКА НАКАТУ (Run-up) ТА ВІДСТУПУ (Backwash) ---
float get_surge(float p, float ratio) {
	// Агресивний швидкий накат (передня стінка)
	float run_up = smoothstep(0.0, ratio, p);
	// Повільне гравітаційє стікання
	float backwash = 1.0 - smoothstep(ratio, 1.0, p);
	return mix(run_up, backwash, step(ratio, p));
}

// --- ГЕРСТНЕР ---
vec3 gerstner_wave(vec4 wave, vec3 p, float chaos, inout vec3 tangent, inout vec3 binormal) {
	float steepness = wave.z;
	float wavelength = wave.w;
	float k = 2.0 * 3.14159265 / max(wavelength, 0.001);
	float c = sqrt(9.8 / k);
	
	vec2 d = normalize(wave.xy);
	float f = k * (dot(d, p.xz) - c * TIME) + chaos;
	float a = steepness / k;

	tangent += vec3(-d.x * d.x * (steepness * sin(f)), d.x * (steepness * cos(f)), -d.x * d.y * (steepness * sin(f)));
	binormal += vec3(-d.x * d.y * (steepness * sin(f)), d.y * (steepness * cos(f)), -d.y * d.y * (steepness * sin(f)));
	
	return vec3(d.x * (a * cos(f)), a * sin(f), d.y * (a * cos(f)));
}

void vertex() {
	world_pos_var = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_ocean_depth = COLOR.r; 
	v_dist = distance(CAMERA_POSITION_WORLD, world_pos_var);

	vec3 grid_point = world_pos_var;
	vec3 tangent = vec3(1.0, 0.0, 0.0);
	vec3 binormal = vec3(0.0, 0.0, 1.0);
	vec3 p = grid_point;
	
	// 1. SHOALING (Трансформація на мілководді)
	// Хвиля відчуває дно. Маска активна лише в перехідній зоні (глибина 0.05 - 0.4)
	float shoal_zone = smoothstep(0.4, 0.15, v_ocean_depth) * smoothstep(0.0, 0.1, v_ocean_depth);
	float local_shoaling = 1.0 + (shoal_zone * shoaling_power);
	
	float chaos_val = fbm(grid_point.xz * ocean_chaos_scale) * ocean_chaos_strength * v_ocean_depth;
	float steepness_fade = mix(0.0, 1.0, smoothstep(0.0, 0.3, v_ocean_depth));
	
	// Застосовуємо ефект Shoaling до гостроти хвиль: перед руйнуванням вони стають дуже крутими
	vec4 w1 = wave_1; w1.z *= steepness_fade * ocean_amplitude * local_shoaling;
	vec4 w2 = wave_2; w2.z *= steepness_fade * ocean_amplitude * local_shoaling;
	vec4 w3 = wave_3; w3.z *= steepness_fade * ocean_amplitude * local_shoaling;
	
	p += gerstner_wave(w1, grid_point, chaos_val, tangent, binormal);
	p += gerstner_wave(w2, grid_point, chaos_val, tangent, binormal);
	p += gerstner_wave(w3, grid_point, chaos_val, tangent, binormal);

	// Висота також збільшується в зоні Shoaling
	vec3 deep_offset = (p - grid_point) * local_shoaling; 

	// 2. БЕРЕГ: ФІЗИКА НАКОЧУВАННЯ
	float shore_noise = fbm(world_pos_var.xz * 2.0) * 0.5;
	v_dist_phase = v_ocean_depth * 10.0 + shore_noise;
	
	float phase_time = TIME * shore_speed;
	float p1 = fract(v_dist_phase + phase_time);
	float p2 = fract(v_dist_phase + phase_time + 0.5); 
	
	float surge1 = get_surge(p1, shore_in_out_ratio);
	float surge2 = get_surge(p2, shore_in_out_ratio);
	
	float total_surge = max(surge1, surge2); 
	
	vec2 push_dir = normalize(shore_push_dir);
	vec3 shore_offset = vec3(
		push_dir.x * total_surge * shore_roll_distance, 
		total_surge * shore_wave_height, 
		push_dir.y * total_surge * shore_roll_distance
	);
	
	// Змішування відкритого океану і берегової логіки
	float shore_blend = 1.0 - smoothstep(0.0, 0.2, v_ocean_depth);
	vec3 final_offset = mix(deep_offset, shore_offset, shore_blend);
	
	VERTEX += final_offset;
	v_wave_height = final_offset.y;
	v_gerstner_normal = normalize(cross(binormal, tangent));
}

void fragment() {
	float depth_tex = textureLod(DEPTH_TEXTURE, SCREEN_UV, 0.0).r;
	vec4 ndc = vec4(SCREEN_UV * 2.0 - 1.0, depth_tex, 1.0);
	vec4 view_pos = INV_PROJECTION_MATRIX * ndc;
	view_pos.xyz /= view_pos.w;
	float water_depth = max(0.0, VERTEX.z - view_pos.z);

	vec3 water_base = mix(col_lake, col_ocean, smoothstep(0.1, 0.8, v_ocean_depth));
	vec3 toon_water = mix(toon_dark, water_base, smoothstep(-0.2, 0.5, v_wave_height));

	// --- 1. ЛОГІКА НАКАТУ І ВІДСТУПУ (ФРАГМЕНТ) ---
	float shore_mask = 1.0 - smoothstep(0.0, 1.5, water_depth); 
	float phase_time = TIME * shore_speed;
	float p1 = fract(v_dist_phase + phase_time);
	float p2 = fract(v_dist_phase + phase_time + 0.5);
	
	float s1 = get_surge(p1, shore_in_out_ratio);
	float s2 = get_surge(p2, shore_in_out_ratio);
	
	float is_w1_top = step(s2, s1);
	float is_w2_top = 1.0 - is_w1_top;
	
	// --- ІНТЕРФЕРЕНЦІЯ (Зіткнення хвиль) ---
	// Якщо одна хвиля швидко набігає (Run-up: 0.0 -> ratio), 
	// а інша повільно стікає (Backwash: 0.7 -> 1.0), їхнє зіткнення створює вибух турбулентності.
	float w1_rush = step(0.0, p1) * step(p1, shore_in_out_ratio);
	float w2_tail = smoothstep(0.7, 1.0, p2);
	float clash1 = w1_rush * w2_tail;
	
	float w2_rush = step(0.0, p2) * step(p2, shore_in_out_ratio);
	float w1_tail = smoothstep(0.7, 1.0, p1);
	float clash2 = w2_rush * w1_tail;
	
	float interference_spike = max(clash1, clash2) * interference_foam;

	// --- ФРОНТОВА ПІНА ТА РУЙНУВАННЯ (Breaking) ---
	float foam1 = smoothstep(0.0, foam_sharpness, p1) * (1.0 - smoothstep(foam_sharpness, shore_in_out_ratio, p1));
	float foam2 = smoothstep(0.0, foam_sharpness, p2) * (1.0 - smoothstep(foam_sharpness, shore_in_out_ratio, p2));
	
	float final_shore_foam = ((foam1 * is_w1_top + foam2 * is_w2_top) + interference_spike) * shore_mask;
	
	// --- МОКРИЙ ПІСОК (Миттєве намокання, повільне висихання) ---
	// p1 від 0 до ratio (Накат): Пісок миттєво стає 100% мокрим (значення 1.0)
	// p1 від ratio до 1.0 (Відкат): Значення плавно падає від 1.0 до 0.0
	float wet1 = step(0.0, p1) * step(p1, shore_in_out_ratio) + (1.0 - smoothstep(shore_in_out_ratio, 1.0, p1)) * step(shore_in_out_ratio, p1);
	float wet2 = step(0.0, p2) * step(p2, shore_in_out_ratio) + (1.0 - smoothstep(shore_in_out_ratio, 1.0, p2)) * step(shore_in_out_ratio, p2);
	
	// Беремо максимальну вологість від обох хвиль
	float total_wetness = max(wet1, wet2);
	float wet_mask = total_wetness * shore_mask;
	vec3 wet_sand = toon_dark * (1.0 - wet_sand_darkness); 

	// --- 2. ПІНА НА ГРЕБЕНЯХ ОКЕАНУ ---
	float wave_steepness = 1.0 - v_gerstner_normal.y; 
	float peak_foam = smoothstep(0.05, 0.15, wave_steepness) * smoothstep(0.3, 0.7, fbm(world_pos_var.xz * 1.5 + TIME));

	float edge_line = step(water_depth, 0.01); 
	float total_foam = clamp(peak_foam + final_shore_foam + edge_line, 0.0, 1.0);

	// Накладаємо мокрий пісок, а потім піну
	vec3 base_with_wetness = mix(toon_water, wet_sand, wet_mask);
	vec3 final_color = mix(base_with_wetness, foam_color, total_foam);

	// --- МІКРОДЕТАЛІ ---
	vec3 base_micro = vec3(fbm(world_pos_var.xz * 2.0), 0.0, fbm(world_pos_var.xz * 2.0 + vec2(10.0)));
	float detail_mask = 1.0 - smoothstep(5.0, 30.0, v_dist);
	vec2 hq_uv1 = world_pos_var.xz * 8.0 + TIME * 0.8;
	vec2 hq_uv2 = world_pos_var.xz * -5.0 + TIME * 0.6;
	vec3 hq_micro = vec3(fbm(hq_uv1), 0.0, fbm(hq_uv2));
	
	vec3 final_micro = mix(base_micro, hq_micro, detail_mask);
	vec3 final_normal = normalize(v_gerstner_normal + (final_micro - 0.5) * mix(0.1, 0.5, detail_mask));
	NORMAL = (VIEW_MATRIX * vec4(final_normal, 0.0)).xyz;

	// --- PBR ТА АЛЬФА ---
	ALBEDO = final_color;
	SPECULAR = mix(0.3, 0.8, detail_mask); 
	ROUGHNESS = mix(mix(0.15, 0.02, detail_mask), 0.9, total_foam);

	float alpha_fade = smoothstep(0.0, 1.5, water_depth);
	// Прозорість базується на вологості. Мокрий пісок робить воду на березі "густішою"
	ALPHA = mix(wet_mask * 0.9, 0.95, alpha_fade); 
	if (total_foam > 0.1) ALPHA = 1.0; 
}