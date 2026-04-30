shader_type spatial;
render_mode blend_mix, depth_draw_always, specular_toon;

uniform vec3 col_lake : source_color = vec3(0.05, 0.6, 0.85);
uniform vec3 col_ocean : source_color = vec3(0.01, 0.1, 0.3);
uniform vec3 foam_color : source_color = vec3(1.0, 1.0, 1.0);
uniform vec3 toon_dark : source_color = vec3(0.0, 0.1, 0.2);

// ==========================================
// НАЛАШТУВАННЯ ХВИЛЬ
// ==========================================
// Напрямки базових хвиль (відкрите море)
uniform vec4 wave_1 = vec4(1.0, 0.4, 0.4, 25.0);  // dir.x, dir.y, steepness, wavelength
uniform vec4 wave_2 = vec4(-0.7, 0.7, 0.3, 12.0);
uniform vec4 wave_3 = vec4(0.2, -0.9, 0.2, 5.0);

uniform float time_scale = 1.0;
uniform float height_scale = 1.0;
uniform float shore_wave_height = 0.5; // Висота хвиль, які б'ють у берег

uniform sampler2D DEPTH_TEXTURE : hint_depth_texture, filter_linear_mipmap;

varying vec3 world_pos_var;
varying float v_ocean_depth;
varying float v_wave_height;
varying vec3 v_gerstner_normal;
varying float v_dist;

// --- Шум для піни та макро-деталей ---
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

// ==========================================
// ФІЗИКА ХВИЛЬ ГЕРСТНЕРА (ЗІ СТАТТІ + ЗАЛОМЛЕННЯ)
// ==========================================
vec3 gerstner_wave(vec4 wave, vec3 p, float depth_factor, inout vec3 tangent, inout vec3 binormal) {
	float steepness = wave.z;
	float wavelength = wave.w;
	float k = 2.0 * 3.14159265 / max(wavelength, 0.001);
	float c = sqrt(9.8 / k);
	
	// ЗАЛОМЛЕННЯ: Чим ближче до берега (depth_factor -> 0), 
	// тим більше хвиля вирівнюється, щоб бити прямо в берег (умовно vec2(1,0))
	vec2 deep_dir = normalize(wave.xy);
	vec2 shore_dir = normalize(vec2(1.0, 0.1)); // Напрямок "на берег"
	vec2 d = normalize(mix(shore_dir, deep_dir, depth_factor));
	
	float f = k * (dot(d, p.xz) - c * TIME * time_scale);
	float a = steepness / k;

	tangent += vec3(
		-d.x * d.x * (steepness * sin(f)),
		d.x * (steepness * cos(f)),
		-d.x * d.y * (steepness * sin(f))
	);
	
	binormal += vec3(
		-d.x * d.y * (steepness * sin(f)),
		d.y * (steepness * cos(f)),
		-d.y * d.y * (steepness * sin(f))
	);
	
	return vec3(
		d.x * (a * cos(f)),
		a * sin(f),
		d.y * (a * cos(f))
	);
}

void vertex() {
	world_pos_var = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_ocean_depth = COLOR.r; // 0.0 = берег, 1.0 = відкрите море
	v_dist = distance(CAMERA_POSITION_WORLD, world_pos_var);

	vec3 grid_point = world_pos_var;
	vec3 tangent = vec3(1.0, 0.0, 0.0);
	vec3 binormal = vec3(0.0, 0.0, 1.0);
	vec3 p = grid_point;
	
	// Гасіння гостроти на березі
	float steepness_fade = mix(0.1, 1.0, smoothstep(0.0, 0.5, v_ocean_depth));
	
	vec4 w1 = wave_1; w1.z *= steepness_fade;
	vec4 w2 = wave_2; w2.z *= steepness_fade;
	vec4 w3 = wave_3; w3.z *= steepness_fade;
	
	// Передаємо глибину для заломлення напрямку хвиль
	p += gerstner_wave(w1, grid_point, v_ocean_depth, tangent, binormal);
	p += gerstner_wave(w2, grid_point, v_ocean_depth, tangent, binormal);
	p += gerstner_wave(w3, grid_point, v_ocean_depth, tangent, binormal);

	vec3 offset = p - grid_point;
	
	// Адаптивна висота: в океані - високі, на березі - для накочування (shore_wave_height)
	float current_height = mix(shore_wave_height, height_scale, v_ocean_depth);
	offset.y *= current_height;
	
	// ВАЖЛИВО: Запобігаємо виникненню хвиль з-під землі.
	// Якщо ми на самому стику з берегом (v_ocean_depth < 0.05), висота зміщення падає до 0.
	float ground_clearance = smoothstep(0.0, 0.05, v_ocean_depth);
	offset.y *= ground_clearance;
	
	VERTEX += offset;
	v_wave_height = offset.y;
	v_gerstner_normal = normalize(cross(binormal, tangent));
}

void fragment() {
	float depth_tex = textureLod(DEPTH_TEXTURE, SCREEN_UV, 0.0).r;
	vec4 ndc = vec4(SCREEN_UV * 2.0 - 1.0, depth_tex, 1.0);
	vec4 view_pos = INV_PROJECTION_MATRIX * ndc;
	view_pos.xyz /= view_pos.w;
	
	// Глибина води від дна до поверхні
	float water_depth = max(0.0, VERTEX.z - view_pos.z);

	// --- КОЛІР ---
	vec3 water_base = mix(col_lake, col_ocean, smoothstep(0.1, 0.8, v_ocean_depth));
	vec3 toon_water = mix(toon_dark, water_base, smoothstep(-0.2, 0.5, v_wave_height));

	// --- 1. ПІНА ФІЗИЧНОГО НАКОЧУВАННЯ (На березі) ---
	float shore_time = TIME * 2.0;
	// Пилкоподібна хвиля: різкий удар в берег (1.0), плавний спад (0.0)
	float wave_front = fract(water_depth * 2.0 - shore_time);
	
	// Формуємо слід: гострий край попереду і плавний слід позаду
	float trail_foam = smoothstep(0.95, 1.0, wave_front) + (pow(wave_front, 4.0) * smoothstep(0.0, 0.95, wave_front));
	
	// Розбиваємо слід шумом
	trail_foam *= smoothstep(0.3, 0.7, fbm(world_pos_var.xz * 3.0));
	
	// Зона берега: малюємо слід ТІЛЬКИ на мілині (від 0.05 до 2.0 метрів глибини)
	float shore_zone = smoothstep(0.05, 0.4, water_depth) * (1.0 - smoothstep(1.0, 2.0, water_depth));
	float final_shore_foam = trail_foam * shore_zone;

	// --- 2. ПІНА НА ГРЕБЕНЯХ ХВИЛЬ (Океан) ---
	// Залежить від загальної висоти хвиль
	float max_h = height_scale; 
	float peak_foam = smoothstep(max_h * 0.4, max_h * 1.0, v_wave_height);
	peak_foam *= smoothstep(0.4, 0.7, fbm(world_pos_var.xz * 1.5 + (TIME * 0.5)));

	// --- 3. АБСОЛЮТНИЙ КРАЙ ---
	float edge_line = step(water_depth, 0.05);
	
	float total_foam = clamp(peak_foam + final_shore_foam + edge_line, 0.0, 1.0);
	vec3 final_color = mix(toon_water, foam_color, total_foam);

	// ==========================================
	// ЕКСТРЕМАЛЬНА ДЕТАЛІЗАЦІЯ ПОВЕРХНІ
	// ==========================================
	vec3 base_micro = vec3(fbm(world_pos_var.xz * 2.0), 0.0, fbm(world_pos_var.xz * 2.0 + vec2(10.0)));
	
	float detail_mask = 1.0 - smoothstep(5.0, 30.0, v_dist);
	vec2 hq_uv1 = world_pos_var.xz * 8.0 + TIME * 0.8;
	vec2 hq_uv2 = world_pos_var.xz * -5.0 + TIME * 0.6;
	vec3 hq_micro = vec3(fbm(hq_uv1), 0.0, fbm(hq_uv2));
	
	vec3 final_micro = mix(base_micro, hq_micro, detail_mask);
	
	// Додаємо деталі до фізичних нормалей Герстнера
	vec3 final_normal = normalize(v_gerstner_normal + (final_micro - 0.5) * mix(0.1, 0.5, detail_mask));
	NORMAL = (VIEW_MATRIX * vec4(final_normal, 0.0)).xyz;

	// --- PBR ТА ПРОЗОРІСТЬ ---
	ALBEDO = final_color;
	SPECULAR = mix(0.3, 0.8, detail_mask); 
	ROUGHNESS = mix(mix(0.15, 0.02, detail_mask), 0.9, total_foam);

	float alpha_fade = smoothstep(0.0, 1.5, water_depth);
	ALPHA = mix(0.4, 0.95, alpha_fade); 
	if (total_foam > 0.1) ALPHA = 1.0;  
}