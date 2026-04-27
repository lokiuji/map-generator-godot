shader_type spatial;

uniform vec3 rock_color_dark : source_color = vec3(0.22, 0.22, 0.25); // Зробив трохи світлішим, щоб не було чорним як лава
uniform vec3 rock_color_light : source_color = vec3(0.40, 0.42, 0.45); 
uniform float rock_scale = 0.5; 

uniform vec3 dirt_color : source_color = vec3(0.40, 0.25, 0.15);
uniform vec3 snow_color : source_color = vec3(0.9, 0.95, 1.0);

uniform float dirt_slope_threshold = 0.35;
uniform float rock_slope_threshold = 0.6;
uniform float blend_amount = 0.08;

varying vec3 world_normal;
varying vec3 world_pos_var;

// --- ГЕНЕРАТОРИ 2D ШУМУ (для трави) ---
float hash(vec2 p) {
	p = fract(p * vec2(233.14, 113.16));
	p += dot(p, p + 19.19);
	return fract(p.x * p.y);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x),
			   mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

// --- ГЕНЕРАТОРИ 3D ШУМУ (для каменю) ---
float hash3(vec3 p) {
	p = fract(p * vec3(123.34, 456.21, 789.92));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y * p.z);
}

float noise3(vec3 x) {
	vec3 i = floor(x);
	vec3 f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash3(i + vec3(0,0,0)), hash3(i + vec3(1,0,0)), f.x),
				   mix(hash3(i + vec3(0,1,0)), hash3(i + vec3(1,1,0)), f.x), f.y),
			   mix(mix(hash3(i + vec3(0,0,1)), hash3(i + vec3(1,0,1)), f.x),
				   mix(hash3(i + vec3(0,1,1)), hash3(i + vec3(1,1,1)), f.x), f.y), f.z);
}


vec3 domain_warp(vec3 p) {
	// Сильно зменшено амплітуду (з 1.2 до 0.15), щоб прибрати ефект "завихрення рідини"
	float amp = 0.15;
	vec3 offset = vec3(
		noise3(p + vec3(0.0, 1.0, 5.2)),
		noise3(p + vec3(1.3, 0.0, 1.3)),
		noise3(p + vec3(4.5, 2.1, 0.0))
	) * amp;
	return p + offset;
}
// ----------------------------------------

// Додай цю змінну, щоб передавати вагу каменю з вершин у пікселі
varying float v_rock_weight;

void vertex() {
	world_normal = (MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz;
	vec3 world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_pos_var = world_pos;

	// Рахуємо нахил (steepness) прямо у вершинах
	float slope = dot(normalize(world_normal), vec3(0.0, 1.0, 0.0));
	float steepness = 1.0 - slope;
	v_rock_weight = smoothstep(rock_slope_threshold - blend_amount, rock_slope_threshold + blend_amount, steepness);

	// ЕФЕКТ ВДАВЛЮВАННЯ/ВИТЯГУВАННЯ (Displacement)
	if (v_rock_weight > 0.01) {
		float dist = distance(CAMERA_POSITION_WORLD, world_pos);
		
		// Активуємо ефект лише ПРИ НАБЛИЖЕННІ (наприклад, до 100 метрів)
		float disp_strength = smoothstep(100.0, 20.0, dist); 
		
		if (disp_strength > 0.01) {
			// Отримуємо значення нашого ламаного каменю
			vec3 warped_uv = domain_warp(world_pos * rock_scale);
			float rock_val = fbm_rock(warped_uv, 3); // 3 октави достатньо для вершин
			
			// Математика: 0.5 - це нуль, менше - вдавлюємо, більше - витягуємо
			float offset = (rock_val - 0.4) * 2.5; // Регулюй 2.5 для глибини
			
			// Рухаємо вершину вздовж нормалі
			VERTEX += NORMAL * offset * disp_strength * v_rock_weight;
		}
	}
}

// === ОНОВЛЕНА ФОРМУЛА ТРІЩИН (Стиль Material Maker) ===
float fbm_rock(vec3 p, int octaves) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 5; i++) {
		if (i >= octaves) break; 
		float n = noise3(p);
		
		// Математика гострих тріщин: беремо модуль, перевертаємо і звужуємо через pow()
		n = abs(n * 2.0 - 1.0); 
		n = 1.0 - n; 
		n = pow(n, 2.5); // Чим більша цифра, тим гостріші сколи
		v += a * n; 
		
		p = p * 2.3 + vec3(12.3, 4.5, 6.7);
		p = vec3(p.x * 0.866 - p.z * 0.5, p.y * 1.1, p.x * 0.5 + p.z * 0.866);
		a *= 0.45;
	}
	return clamp(v, 0.0, 1.0);
}

// ... (domain_warp та vertex залишаються без змін) ...

void fragment() {
	vec3 world_pos = world_pos_var;
	float snow_mask = COLOR.a; 
	float is_grass = UV.x;
	
	float dist = distance(CAMERA_POSITION_WORLD, world_pos);
	float lod_fade = smoothstep(120.0, 150.0, dist);
	
	float slope = dot(normalize(world_normal), vec3(0.0, 1.0, 0.0));
	float steepness = 1.0 - slope;

	float dirt_weight = smoothstep(dirt_slope_threshold - blend_amount, dirt_slope_threshold + blend_amount, steepness);
	float rock_weight = smoothstep(rock_slope_threshold - blend_amount, rock_slope_threshold + blend_amount, steepness);
	
	vec3 procedural_rock = rock_color_dark;
	vec3 final_world_normal = world_normal;
	
	if (rock_weight > 0.05) {
		// АНТИ-АЛІАСИНГ: Плавно розчиняємо шум на відстані від 120 до 200 метрів
		float far_fade = smoothstep(120.0, 200.0, dist);
		
		// Якщо ми дуже далеко (за 200м) - взагалі не рахуємо камінь! Економія FPS + жодного ряботиння.
		if (dist > 200.0) {
			procedural_rock = mix(rock_color_dark, rock_color_light, 0.4); // Суцільний колір
		} else {
			int octaves = 5;
			float bump_strength = 20.0; 
			
			if (dist > 100.0) {
				octaves = 2; // Менше деталей вдалині
				bump_strength = 5.0; 
			} else if (dist > 50.0) {
				octaves = 3;
				bump_strength = 12.0;
			}
			
			vec3 warped_uv = domain_warp(world_pos * rock_scale);
			float rock_val = fbm_rock(warped_uv, octaves);
			
			// Малюємо камінь
			float rock_mask = smoothstep(0.15, 0.45, rock_val);
			vec3 detailed_rock = mix(rock_color_dark, rock_color_light, rock_mask);
			
			// МАГІЯ ЗГЛАДЖУВАННЯ: розмиваємо камінь до суцільного кольору чим далі він від камери
			procedural_rock = mix(detailed_rock, mix(rock_color_dark, rock_color_light, 0.4), far_fade);
			
			// Об'єм розраховуємо тільки якщо камінь не розмитий в нуль
			bump_strength *= (1.0 - far_fade);
			
			if (bump_strength > 0.0) {
				vec2 e = vec2(0.05, 0.0);
				float dx = fbm_rock(warped_uv + e.xyy, octaves) - rock_val;
				float dy = fbm_rock(warped_uv + e.yxy, octaves) - rock_val;
				float dz = fbm_rock(warped_uv + e.yyx, octaves) - rock_val;
				
				vec3 detail_normal = vec3(-dx, -dy, -dz) * bump_strength;
				vec3 rock_bump_normal = normalize(world_normal + detail_normal);
				
				final_world_normal = normalize(mix(world_normal, rock_bump_normal, rock_weight));
			}
		}
	}
	
	NORMAL = (VIEW_MATRIX * vec4(final_world_normal, 0.0)).xyz;
	
	// --- ІЛЮЗІЯ ТРАВИ ТА ВІТЕР ---
	float wind_speed = 1.5;
	float wind = sin(world_pos.x * 0.08 + TIME * wind_speed) * sin(world_pos.z * 0.08 + TIME * wind_speed * 0.8);
	float ground_tex = sin(world_pos.x * 0.15) * cos(world_pos.z * 0.15);
	
	float micro_grass = noise(world_pos.xz * 3.0);
	float fake_grass_boost = (0.15 + micro_grass * 0.08) * lod_fade * is_grass;
	
	float wind_shadows = 1.0 + (((wind * 0.04) + (ground_tex * 0.03)) * lod_fade * is_grass);
	vec3 biome_color = clamp((COLOR.rgb * wind_shadows) + (COLOR.rgb * fake_grass_boost), vec3(0.0), vec3(1.0));
	
	vec3 slope_color = mix(biome_color, dirt_color, dirt_weight);
	slope_color = mix(slope_color, procedural_rock, rock_weight); 
	
	float rock_on_snow = smoothstep(0.8, 0.95, steepness);
	vec3 final_snow = mix(snow_color, procedural_rock, rock_on_snow * 0.5);
	
	ALBEDO = mix(slope_color, final_snow, snow_mask);
	ROUGHNESS = 0.85;
}