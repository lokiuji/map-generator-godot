shader_type spatial;
render_mode depth_draw_opaque, cull_disabled;

uniform sampler2D alpha_texture : filter_nearest;
uniform sampler2D wind_noise : repeat_enable; 
uniform sampler2D terrain_color_texture : source_color, filter_linear_mipmap, repeat_enable;

group_uniforms Wind;
uniform float wind_speed = 0.5;
uniform float wind_strength = 0.3; // Відхилення вершин (діє тільки зблизька)
uniform float wind_brightness_mult = 0.4; // Світлові хвилі (діють всюди)

group_uniforms LOD_System;
uniform float anim_distance = 25.0; // Дистанція, де фізичний рух плавно зупиняється
uniform float density_drop_distance = 50.0; // Дистанція, після якої трава починає рідшати
uniform float min_density = 0.15; // Скільки трави залишається на горизонті (0.15 = 15%)
uniform float fade_start = 120.0; 
uniform float fade_end = 150.0;

group_uniforms Terrain_Sync;
uniform float terrain_uv_scale = 0.2;
uniform float biome_tint_strength = 0.8;
uniform float global_brightness : hint_range(0.5, 3.0, 0.1) = 1.2; 
uniform float water_level = 4.8; 

varying float wind_val;
varying vec3 world_pos_var;
varying float v_grass_mask;
varying float v_camera_dist;
varying float v_anim_weight;

vec2 hash2(vec2 p) {
	return fract(sin(vec2(dot(p, vec2(127.1, 311.7)), dot(p, vec2(269.5, 183.3)))) * 43758.5453);
}

float noise2(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float res = mix(
		mix(dot(hash2(i + vec2(0.0, 0.0)), f - vec2(0.0, 0.0)), dot(hash2(i + vec2(1.0, 0.0)), f - vec2(1.0, 0.0)), f.x),
		mix(dot(hash2(i + vec2(0.0, 1.0)), f - vec2(0.0, 1.0)), dot(hash2(i + vec2(1.0, 1.0)), f - vec2(1.0, 1.0)), f.x), f.y);
	return res * 0.5 + 0.5; 
}

float get_outcropping_mask(vec2 pos) {
	float v = 0.0; float a = 0.5;
	vec2 p = pos * 0.03; 
	for (int i = 0; i < 3; i++) {
		v += a * noise2(p);
		p = p * 2.0 + vec2(12.3, 4.5);
		a *= 0.5;
	}
	return v; 
}

void get_material_weights(vec3 w_pos, vec3 w_norm, out float cliff, out float pebble, out float sand, out float dirt, out float grass) {
	float steepness = 1.0 - dot(w_norm, vec3(0.0, 1.0, 0.0));
	float outcropping = get_outcropping_mask(w_pos.xz);
	
	float rock_steep = smoothstep(0.60, 0.61, steepness);
	float rock_noise = smoothstep(0.75, 0.76, outcropping);
	cliff = clamp(rock_steep + rock_noise, 0.0, 1.0);
	
	float pebble_steep = smoothstep(0.50, 0.51, steepness);
	float pebble_noise = smoothstep(0.65, 0.66, outcropping);
	float total_pebble = clamp(pebble_steep + pebble_noise, 0.0, 1.0);
	
	float dirt_steep = smoothstep(0.40, 0.41, steepness);
	float dirt_noise = smoothstep(0.55, 0.56, outcropping);
	float total_dirt = clamp(dirt_steep + dirt_noise, 0.0, 1.0);
	
	float sand_area = 1.0 - smoothstep(water_level - 1.0, water_level + 4.0, w_pos.y);

	sand   = clamp(sand_area, 0.0, 1.0);
	cliff  = clamp(cliff - sand, 0.0, 1.0); 
	pebble = clamp(total_pebble - cliff - sand, 0.0, 1.0);
	dirt   = clamp(total_dirt - cliff - sand - pebble, 0.0, 1.0);
	grass  = clamp(1.0 - cliff - sand - pebble - dirt, 0.0, 1.0); 
}

void vertex() {
	world_pos_var = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_camera_dist = distance(world_pos_var, CAMERA_POSITION_WORLD);
	
	// --- LOD 1: ДИНАМІЧНА ЩІЛЬНІСТЬ ---
	// Якщо ми далі за density_drop_distance, щільність плавно падає від 1.0 до min_density
	float current_density = mix(1.0, min_density, smoothstep(density_drop_distance, fade_start, v_camera_dist));
	float instance_hash = hash2(world_pos_var.xz * 100.0).x;
	
	// Якщо випадкове число більше за поточну дозволену щільність - ховаємо травинку
	if (instance_hash > current_density) {
		VERTEX = vec3(0.0);
	}
	
	vec3 terrain_normal = normalize(INSTANCE_CUSTOM.rgb * 2.0 - 1.0);
	float c, p, s, d, g;
	get_material_weights(world_pos_var, terrain_normal, c, p, s, d, g);
	
	float snow = smoothstep(100.0, 130.0, world_pos_var.y);
	v_grass_mask = g * (1.0 - snow);

	float lod_scale = 1.0 - smoothstep(fade_start, fade_end, v_camera_dist);
	float pop_scale = smoothstep(0.01, 0.5, v_grass_mask);
	
	VERTEX *= lod_scale * pop_scale; 

	if (world_pos_var.y < water_level) {
		VERTEX = vec3(0.0);
	}

	// --- ШУМ ВІТРУ ---
	vec2 noise_uv = (world_pos_var.xz * 0.02) + (vec2(1.0, 0.5) * TIME * wind_speed);
	wind_val = texture(wind_noise, noise_uv).r;
	
	// --- LOD 2: АНІМАЦІЯ РУХУ (тільки зблизька) ---
	// Вага анімації падає до 0, коли дистанція досягає anim_distance
	v_anim_weight = 1.0 - smoothstep(anim_distance * 0.7, anim_distance, v_camera_dist);
	
	float height_factor = max(0.0, VERTEX.y); 
	VERTEX.x += wind_val * wind_strength * height_factor * v_anim_weight;
	VERTEX.z += wind_val * wind_strength * 0.5 * height_factor * v_anim_weight;
}

void fragment() {
	if (v_grass_mask < 0.01 || world_pos_var.y < water_level) discard; 

	vec4 tex = texture(alpha_texture, UV);
	ALPHA = tex.a;
	ALPHA_SCISSOR_THRESHOLD = 0.5; 
	
	vec2 ground_uv = world_pos_var.xz * terrain_uv_scale;
	vec3 ground_tex_color = texture(terrain_color_texture, ground_uv).rgb;
	
	vec3 tint = mix(vec3(1.0), COLOR.rgb, biome_tint_strength);
	vec3 actual_ground_color = ground_tex_color * tint;
	
	float tip_mask = pow(1.0 - UV.y, 2.0);
	
	// --- ВИПРАВЛЕННЯ ЗАТЕМНЕННЯ ---
	// Тепер колір розраховується однаково для всіх дистанцій, 
	// коріння залишається у своєму кольорі (* 1.0), а кінчики висвітлюються (* 1.5).
	vec3 base_color = mix(actual_ground_color * 1.0, actual_ground_color * 1.5, tip_mask);
	
	// Світлові відблиски від вітру працюють завжди, незалежно від дистанції
	float wind_shimmer = wind_val * wind_brightness_mult * tip_mask;
	vec3 final_color = base_color + (vec3(1.0) * wind_shimmer);
	
	ALBEDO = clamp(final_color * global_brightness, vec3(0.0), vec3(1.0));
	
	// Трава зблизька ловить більше сонячного світла (блищить), вдалині стає матовою
	ROUGHNESS = mix(0.9, 0.7, v_anim_weight); 
	SPECULAR = mix(0.0, 0.1, v_anim_weight); 
	
	vec3 up_normal = (VIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz;
	NORMAL = normalize(mix(NORMAL, up_normal, 0.9));
}