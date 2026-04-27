shader_type spatial;

uniform vec3 rock_color_dark : source_color = vec3(0.05, 0.05, 0.07); 
uniform vec3 rock_color_light : source_color = vec3(0.38, 0.40, 0.42); 

// 1. МАКРО ТРІЩИНИ (Величезні кам'яні масиви)
uniform float rock_macro_scale = 0.05;  
uniform float macro_crack_depth = 4.0;  

// 2. МІКРО ТРІЩИНИ (Окремі камені та потріскана земля)
uniform float rock_micro_scale = 0.4;   
uniform float micro_crack_depth = 1.0;  

uniform vec3 dirt_color : source_color = vec3(0.40, 0.25, 0.15);
uniform vec3 snow_color : source_color = vec3(0.9, 0.95, 1.0);

uniform float dirt_slope_threshold = 0.35;
uniform float rock_slope_threshold = 0.6;
uniform float blend_amount = 0.08;

varying vec3 world_normal;
varying vec3 world_pos_var;
varying float v_rock_weight;

// --- БАЗОВІ ГЕНЕРАТОРИ ---
float hash3(vec3 p) {
	p = fract(p * vec3(123.34, 456.21, 789.92));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y * p.z);
}

vec3 hash3v(vec3 p) {
	vec3 q = vec3(
		dot(p, vec3(127.1, 311.7, 74.7)),
		dot(p, vec3(269.5, 183.3, 246.1)),
		dot(p, vec3(113.5, 271.9, 124.6))
	);
	return fract(sin(q) * 43758.5453123);
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

// --- ВОРОНИЙ ДЛЯ ТРІЩИН ---
float voronoi_edge(vec3 x) {
	vec3 p = floor(x);
	vec3 f = fract(x);
	vec3 mb; vec3 mr;
	float md = 8.0;
	
	for(int k=-1; k<=1; k++)
	for(int j=-1; j<=1; j++)
	for(int i=-1; i<=1; i++) {
		vec3 b = vec3(float(i), float(j), float(k));
		vec3 r = b + hash3v(p + b) - f;
		float d = dot(r, r);
		if(d < md) { md = d; mr = r; mb = b; }
	}
	
	md = 8.0;
	for(int k=-1; k<=1; k++)
	for(int j=-1; j<=1; j++)
	for(int i=-1; i<=1; i++) {
		vec3 b = vec3(float(i), float(j), float(k));
		vec3 r = b + hash3v(p + b) - f;
		if(dot(r - mr, r - mr) > 0.00001) {
			md = min(md, dot(0.5 * (mr + r), normalize(r - mr)));
		}
	}
	return md; 
}

float get_cracks(vec3 p, float scale) {
	vec3 warp = vec3(noise3(p), noise3(p + 12.3), noise3(p + 24.6)) * 0.4;
	float dist_to_edge = voronoi_edge((p + warp) * scale);
	return pow(clamp(1.0 - dist_to_edge * 15.0, 0.0, 1.0), 1.5);
}

// === ФІЗИЧНИЙ ОБ'ЄМ (ОПТИМІЗОВАНО: Тільки для близьких дистанцій) ===
float get_physical_cracks(vec3 pos, float dist) {
	float h = 0.5; 
	
	// Макро-тріщини фізично працюють лише до 50м
	float fade_macro = smoothstep(50.0, 15.0, dist);
	if (fade_macro > 0.01) {
		h -= get_cracks(pos, rock_macro_scale) * macro_crack_depth * fade_macro;
	}
	
	// Мікро-тріщини фізично працюють лише до 8м (впритул)
	float fade_micro = smoothstep(8.0, 2.0, dist);
	if (fade_micro > 0.01) {
		h -= get_cracks(pos, rock_micro_scale) * micro_crack_depth * fade_micro;
	}
	
	return h;
}

// === ВІЗУАЛЬНИЙ ОБ'ЄМ (Для ілюзії тіней на великих відстанях) ===
float get_visual_cracks(vec3 pos, float dist) {
	float h = 0.5;
	
	float fade_macro = smoothstep(150.0, 300.0, dist);
	if (fade_macro < 1.0) h -= get_cracks(pos, rock_macro_scale) * macro_crack_depth * (1.0 - fade_macro);
	
	float fade_micro = smoothstep(50.0, 100.0, dist);
	if (fade_micro < 1.0) {
		h -= get_cracks(pos, rock_micro_scale) * micro_crack_depth * (1.0 - fade_micro);
		h += noise3(pos * 2.0) * 0.15 * (1.0 - fade_micro); // Шорсткість блоків
	}
	
	return h;
}
// ----------------------------------------

void vertex() {
	world_normal = (MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz;
	vec3 world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_pos_var = world_pos;

	float slope = dot(normalize(world_normal), vec3(0.0, 1.0, 0.0));
	float steepness = 1.0 - slope;
	v_rock_weight = smoothstep(rock_slope_threshold - blend_amount, rock_slope_threshold + blend_amount, steepness);

	if (v_rock_weight > 0.01) {
		float dist = distance(CAMERA_POSITION_WORLD, world_pos);
		// ЖОРСТКА ЕКОНОМІЯ: Процесор вершин рахує камінь тільки якщо ми ближче 50 метрів
		if (dist < 50.0) {
			float r_height = get_physical_cracks(world_pos, dist);
			float offset = (r_height - 0.5); 
			VERTEX += NORMAL * offset * v_rock_weight;
		}
	}
}

void fragment() {
	vec3 world_pos = world_pos_var;
	float dist = distance(CAMERA_POSITION_WORLD, world_pos);
	
	float slope = dot(normalize(world_normal), vec3(0.0, 1.0, 0.0));
	float steepness = 1.0 - slope;
	float dirt_weight = smoothstep(dirt_slope_threshold - blend_amount, dirt_slope_threshold + blend_amount, steepness);

	vec3 procedural_rock = rock_color_dark;
	vec3 final_world_normal = world_normal;
	
	if (v_rock_weight > 0.05) {
		// Колір розраховуємо один раз (дешево)
		float macro_c = get_cracks(world_pos, rock_macro_scale);
		float micro_c = get_cracks(world_pos, rock_micro_scale);
		float combined_cracks = max(macro_c, micro_c); 
		
		vec3 base_rock = mix(rock_color_light, rock_color_dark, combined_cracks);
		
		float far_fade = smoothstep(200.0, 400.0, dist);
		procedural_rock = mix(base_rock, mix(rock_color_dark, rock_color_light, 0.4), far_fade);
		
		// Фейкові тіні відключаються на 150 метрах для економії
		float normal_fade = smoothstep(80.0, 150.0, dist);
		if (normal_fade < 1.0) {
			vec2 e = vec2(0.05, 0.0);
			float b_str = 4.0 * (1.0 - normal_fade); 
			
			float current_h = get_visual_cracks(world_pos, dist);
			float dx = get_visual_cracks(world_pos + e.xyy, dist) - current_h;
			float dy = get_visual_cracks(world_pos + e.yxy, dist) - current_h;
			float dz = get_visual_cracks(world_pos + e.yyx, dist) - current_h;
			
			final_world_normal = normalize(world_normal + vec3(-dx, -dy, -dz) * b_str);
		}
	}
	
	NORMAL = (VIEW_MATRIX * vec4(final_world_normal, 0.0)).xyz;
	
	vec3 slope_color = mix(COLOR.rgb, dirt_color, dirt_weight);
	slope_color = mix(slope_color, procedural_rock, v_rock_weight);
	ALBEDO = mix(slope_color, snow_color, COLOR.a);
	ROUGHNESS = 0.85;
}