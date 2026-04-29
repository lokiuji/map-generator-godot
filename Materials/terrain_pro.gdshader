shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

// ==========================================
// 🗂️ КАТЕГОРІЯ 1: СКЕЛІ (Triplanar)
// ==========================================
group_uniforms Rock;
uniform sampler2D rock_albedo : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D rock_normal : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D rock_orm : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform sampler2D rock_heightmap : hint_default_black, filter_linear_mipmap, repeat_enable;
uniform float rock_scale = 0.2;
uniform float rock_height_scale = 1.0;
uniform float rock_normal_scale = 1.0;

// ==========================================
// 🗂️ КАТЕГОРІЯ 2: ДРІБНЕ КАМІННЯ (Галька)
// ==========================================
group_uniforms Pebble;
uniform sampler2D pebble_albedo : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D pebble_normal : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D pebble_orm : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform sampler2D pebble_heightmap : hint_default_black, filter_linear_mipmap, repeat_enable;
uniform float pebble_scale = 0.2;
uniform float pebble_height_scale = 0.5;
uniform float pebble_normal_scale = 1.0;

// ==========================================
// 🗂️ КАТЕГОРІЯ 3: ТРАВА
// ==========================================
group_uniforms Grass;
uniform sampler2D grass_albedo : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D grass_normal : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D grass_orm : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform sampler2D grass_heightmap : hint_default_black, filter_linear_mipmap, repeat_enable;
uniform float grass_scale = 0.2;
uniform float grass_height_scale = 0.2;
uniform float grass_normal_scale = 1.0;

// ==========================================
// 🗂️ КАТЕГОРІЯ 4: ЗЕМЛЯ / БРУД
// ==========================================
group_uniforms Dirt;
uniform sampler2D dirt_albedo : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D dirt_normal : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D dirt_orm : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform sampler2D dirt_heightmap : hint_default_black, filter_linear_mipmap, repeat_enable;
uniform float dirt_scale = 0.2;
uniform float dirt_height_scale = 0.4;
uniform float dirt_normal_scale = 1.0;

// ==========================================
// 🗂️ КАТЕГОРІЯ 5: ПІСОК (Берег)
// ==========================================
group_uniforms Sand;
uniform sampler2D sand_albedo : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D sand_normal : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D sand_orm : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform sampler2D sand_heightmap : hint_default_black, filter_linear_mipmap, repeat_enable;
uniform float sand_scale = 0.2;
uniform float sand_height_scale = 0.2;
uniform float sand_normal_scale = 1.0;

// ==========================================
// 🗂️ КАТЕГОРІЯ 6: ГЛОБАЛЬНІ НАЛАШТУВАННЯ
// ==========================================
group_uniforms Global_Settings;
uniform float water_level = 4.8; // Рівень вашої води
uniform float global_brightness : hint_range(0.5, 3.0, 0.1) = 1.2;
uniform float biome_tint_strength : hint_range(0.0, 2.0, 0.05) = 0.8;
uniform bool invert_height = false; 
uniform vec3 snow_color : source_color = vec3(0.9, 0.95, 1.0);
group_uniforms;

varying vec3 world_pos_var;
varying vec3 world_normal_var;

// --- ОРГАНІЧНИЙ ШУМ ДЛЯ ВИСТУПІВ ---
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

// --- ЖОРСТКІ МАСКИ ТА ГАРАНТОВАНИЙ ПІСОК ---
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
	
	// Пісок покриває дно (нижче рівня води) та утворює пляж на 1 метр вище
	float base_sand_mask = 1.0 - smoothstep(water_level, water_level + 1.0, w_pos.y);

	// Жорсткі пріоритети (Пісок найголовніший)
	sand   = clamp(base_sand_mask, 0.0, 1.0);
	cliff  = clamp(cliff - sand, 0.0, 1.0); 
	pebble = clamp(total_pebble - cliff - sand, 0.0, 1.0);
	dirt   = clamp(total_dirt - cliff - sand - pebble, 0.0, 1.0);
	grass  = clamp(1.0 - cliff - sand - pebble - dirt, 0.0, 1.0); 
}

void vertex() {
	world_pos_var = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal_var = (MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz;
	
	float w_cliff, w_pebble, w_sand, w_dirt, w_grass;
	get_material_weights(world_pos_var, normalize(world_normal_var), w_cliff, w_pebble, w_sand, w_dirt, w_grass);

	vec3 w = abs(world_normal_var);
	w = pow(w, vec3(8.0)); 
	vec3 tri_w = w / (w.x + w.y + w.z);

	float dist = distance(CAMERA_POSITION_WORLD, world_pos_var);
	float disp_fade = smoothstep(35.0, 10.0, dist); 
	
	if (disp_fade > 0.01) {
		float h_rock = 0.0;
		if (w_cliff > 0.0) {
			float h_x = textureLod(rock_heightmap, world_pos_var.zy * rock_scale, 0.0).r;
			float h_y = textureLod(rock_heightmap, world_pos_var.xz * rock_scale, 0.0).r;
			float h_z = textureLod(rock_heightmap, world_pos_var.xy * rock_scale, 0.0).r;
			h_rock = (h_x * tri_w.x + h_y * tri_w.y + h_z * tri_w.z - 0.5) * rock_height_scale;
		}

		float h_pebble = (textureLod(pebble_heightmap, world_pos_var.xz * pebble_scale, 0.0).r - 0.5) * pebble_height_scale;
		float h_grass = (textureLod(grass_heightmap, world_pos_var.xz * grass_scale, 0.0).r - 0.5) * grass_height_scale;
		float h_dirt = (textureLod(dirt_heightmap, world_pos_var.xz * dirt_scale, 0.0).r - 0.5) * dirt_height_scale;
		float h_sand = (textureLod(sand_heightmap, world_pos_var.xz * sand_scale, 0.0).r - 0.5) * sand_height_scale;

		float final_disp = (h_rock * w_cliff) + (h_pebble * w_pebble) + (h_grass * w_grass) + (h_dirt * w_dirt) + (h_sand * w_sand);
		if (invert_height) final_disp = -final_disp;
		
		VERTEX += NORMAL * final_disp * disp_fade;
	}
}

void fragment() {
	vec3 w_pos = world_pos_var;
	float dist = distance(CAMERA_POSITION_WORLD, w_pos);
	vec3 w_norm = normalize(world_normal_var);
	
	float w_cliff, w_pebble, w_sand, w_dirt, w_grass;
	get_material_weights(w_pos, w_norm, w_cliff, w_pebble, w_sand, w_dirt, w_grass);

	vec3 w = abs(w_norm);
	w = pow(w, vec3(8.0));
	vec3 tri_w = w / (w.x + w.y + w.z);

	// Трипланарні скелі
	vec2 r_x = w_pos.zy * rock_scale; vec2 r_y = w_pos.xz * rock_scale; vec2 r_z = w_pos.xy * rock_scale;
	vec3 cliff_alb = texture(rock_albedo, r_x).rgb * tri_w.x + texture(rock_albedo, r_y).rgb * tri_w.y + texture(rock_albedo, r_z).rgb * tri_w.z;
	vec3 cliff_nrm = texture(rock_normal, r_x).rgb * tri_w.x + texture(rock_normal, r_y).rgb * tri_w.y + texture(rock_normal, r_z).rgb * tri_w.z;
	vec3 cliff_orm = texture(rock_orm, r_x).rgb * tri_w.x + texture(rock_orm, r_y).rgb * tri_w.y + texture(rock_orm, r_z).rgb * tri_w.z;

	// Рівнинні текстури
	vec2 p_uv = w_pos.xz * pebble_scale;
	vec3 p_alb = texture(pebble_albedo, p_uv).rgb;
	vec3 p_nrm = texture(pebble_normal, p_uv).rgb;
	vec3 p_orm_tex = texture(pebble_orm, p_uv).rgb;

	vec2 g_uv = w_pos.xz * grass_scale;
	vec3 g_alb = texture(grass_albedo, g_uv).rgb;
	vec3 g_nrm = texture(grass_normal, g_uv).rgb;
	vec3 g_orm_tex = texture(grass_orm, g_uv).rgb;

	vec2 d_uv = w_pos.xz * dirt_scale;
	vec3 d_alb = texture(dirt_albedo, d_uv).rgb;
	vec3 d_nrm = texture(dirt_normal, d_uv).rgb;
	vec3 d_orm_tex = texture(dirt_orm, d_uv).rgb;

	vec2 s_uv = w_pos.xz * sand_scale;
	vec3 s_alb = texture(sand_albedo, s_uv).rgb;
	vec3 s_nrm = texture(sand_normal, s_uv).rgb;
	vec3 s_orm_tex = texture(sand_orm, s_uv).rgb;

	// Тонування біомом
	vec3 tint = mix(vec3(1.0), COLOR.rgb, biome_tint_strength);
	p_alb *= tint;
	g_alb *= tint;
	d_alb *= tint;
	s_alb *= tint;

	// Змішування
	vec3 final_albedo = cliff_alb * w_cliff + p_alb * w_pebble + g_alb * w_grass + d_alb * w_dirt + s_alb * w_sand;
	vec3 final_normal = cliff_nrm * w_cliff + p_nrm * w_pebble + g_nrm * w_grass + d_nrm * w_dirt + s_nrm * w_sand;
	vec3 final_orm    = cliff_orm * w_cliff + p_orm_tex * w_pebble + g_orm_tex * w_grass + d_orm_tex * w_dirt + s_orm_tex * w_sand;

	// Сніг на вершинах
	final_albedo = mix(final_albedo, snow_color, COLOR.a);

	// Фінальний вивід (Матова поверхня)
	ALBEDO = clamp(final_albedo * global_brightness, 0.0, 1.0);

	float normal_fade = smoothstep(150.0, 50.0, dist); 
	float current_normal_scale = rock_normal_scale * w_cliff + pebble_normal_scale * w_pebble + grass_normal_scale * w_grass + dirt_normal_scale * w_dirt + sand_normal_scale * w_sand;
	vec3 normal_offset = (final_normal * 2.0 - 1.0) * current_normal_scale * normal_fade;
	NORMAL = (VIEW_MATRIX * vec4(normalize(w_norm + normal_offset), 0.0)).xyz;
	
	SPECULAR = 0.02; // Жодних відблисків неба
	AO = final_orm.r; 
	ROUGHNESS = clamp(final_orm.g, 0.75, 1.0); // Матова суха поверхня
	METALLIC = 0.0; 
}