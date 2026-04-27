shader_type spatial;

// ЗАМІСТЬ ТЕКСТУРИ - НАЛАШТУВАННЯ ПРОЦЕДУРНОГО КАМЕНЮ
uniform vec3 rock_color_dark : source_color = vec3(0.12, 0.12, 0.15); // Темні западини
uniform vec3 rock_color_light : source_color = vec3(0.35, 0.35, 0.38); // Світлі виступи
uniform float rock_scale = 0.5; // Розмір каменю

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

// 3D Value Noise
float noise3(vec3 x) {
	vec3 i = floor(x);
	vec3 f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash3(i + vec3(0,0,0)), hash3(i + vec3(1,0,0)), f.x),
				   mix(hash3(i + vec3(0,1,0)), hash3(i + vec3(1,1,0)), f.x), f.y),
			   mix(mix(hash3(i + vec3(0,0,1)), hash3(i + vec3(1,0,1)), f.x),
				   mix(hash3(i + vec3(0,1,1)), hash3(i + vec3(1,1,1)), f.x), f.y), f.z);
}

// Процедурний камінь (Ridged FBM)
float fbm_rock(vec3 p, int octaves) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 5; i++) {
		if (i >= octaves) break; // LOD: перериваємо цикл, якщо далеко
		float n = noise3(p);
		n = 1.0 - abs(n * 2.0 - 1.0); // Робимо гострі "хребти"
		v += a * (n * n); 
		p = p * 2.5 + vec3(12.3, 4.5, 6.7);
		a *= 0.4;
	}
	return v;
}
// ----------------------------------------

void vertex() {
	world_normal = (MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz;
	world_pos_var = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

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
	
	// === ПРОЦЕДУРНИЙ КАМІНЬ ТА LOD СИСТЕМА ===
	vec3 procedural_rock = rock_color_dark;
	vec3 final_world_normal = world_normal;
	
	// ОПТИМІЗАЦІЯ: Рахуємо камінь ТІЛЬКИ на схилах (rock_weight > 0.05)
	if (rock_weight > 0.05) {
		int octaves = 5;
		float bump_strength = 20.0; // Сила викривлення тіней (об'єму)
		
		// LOD СИСТЕМА (залежить від відстані до камери)
		if (dist > 150.0) {
			octaves = 1;
			bump_strength = 0.0; // Вдалині тіні від мікротріщин не потрібні
		} else if (dist > 70.0) {
			octaves = 3;
			bump_strength = 8.0;
		}
	vec3 domain_warp(vec3 p) {
	float amp = 1.2;
    // Викривляємо координати, щоб прибрати "математичну" правильність
	vec3 offset = vec3(
		noise3(p + vec3(0.0, 1.0, 5.2)),
		noise3(p + vec3(1.3, 0.0, 1.3)),
		noise3(p + vec3(4.5, 2.1, 0.0))
	) * amp;
	return p + offset;
}
		vec3 rock_uv = world_pos * rock_scale;
		float rock_val = fbm_rock(rock_uv, octaves);
		// МАГІЯ БЕЗШОВНОСТІ ТА ОРГАНІКИ:
		// 1. Викривляємо координати (Domain Warping)
		vec3 warped_uv = domain_warp(world_pos * rock_scale);
		// 2. Рахуємо шум вже по викривленим координатам
		float rock_val = fbm_rock(warped_uv, octaves);
    
    procedural_rock = mix(rock_color_dark, rock_color_light, clamp(rock_val * 1.5, 0.0, 1.0));
		// Фарбуємо: міксуємо темний камінь (тріщини) зі світлим (виступи)
		procedural_rock = mix(rock_color_dark, rock_color_light, clamp(rock_val * 1.5, 0.0, 1.0));
		
		// ГЕНЕРУЄМО ОБ'ЄМ З КОДУ (Математична карта нормалей)
		if (bump_strength > 0.0) {
			vec2 e = vec2(0.05, 0.0);
			// Зміщуємось на 5см в різні боки, щоб "намацати" форму рельєфу
			float dx = fbm_rock(rock_uv + e.xyy, octaves) - rock_val;
			float dy = fbm_rock(rock_uv + e.yxy, octaves) - rock_val;
			float dz = fbm_rock(rock_uv + e.yyx, octaves) - rock_val;
			
			vec3 detail_normal = vec3(-dx, -dy, -dz) * bump_strength;
			vec3 rock_bump_normal = normalize(world_normal + detail_normal);
			
			// Плавно змішуємо нормаль каменю з нормальною землі
			final_world_normal = normalize(mix(world_normal, rock_bump_normal, rock_weight));
		}
	}
	
	// Конвертуємо світову нормаль назад у View Space для системи освітлення Godot
	NORMAL = (VIEW_MATRIX * vec4(final_world_normal, 0.0)).xyz;
	// =========================================
	
	// --- ІЛЮЗІЯ ТРАВИ ТА ВІТЕР ---
	float wind_speed = 1.5;
	float wind = sin(world_pos.x * 0.08 + TIME * wind_speed) * sin(world_pos.z * 0.08 + TIME * wind_speed * 0.8);
	float ground_tex = sin(world_pos.x * 0.15) * cos(world_pos.z * 0.15);
	
	float micro_grass = noise(world_pos.xz * 3.0);
	float fake_grass_boost = (0.15 + micro_grass * 0.08) * lod_fade * is_grass;
	
	float wind_shadows = 1.0 + (((wind * 0.04) + (ground_tex * 0.03)) * lod_fade * is_grass);
	vec3 biome_color = clamp((COLOR.rgb * wind_shadows) + (COLOR.rgb * fake_grass_boost), vec3(0.0), vec3(1.0));
	
	// Фінальне змішування кольорів
	vec3 slope_color = mix(biome_color, dirt_color, dirt_weight);
	slope_color = mix(slope_color, procedural_rock, rock_weight); 
	
	float rock_on_snow = smoothstep(0.8, 0.95, steepness);
	vec3 final_snow = mix(snow_color, procedural_rock, rock_on_snow * 0.5);
	
	ALBEDO = mix(slope_color, final_snow, snow_mask);
	ROUGHNESS = 0.85;
}
