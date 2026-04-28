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
uniform float grass_height_scale = 0.3;
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
uniform float global_brightness : hint_range(0.5, 3.0, 0.1) = 1.0; // Освітлення всього ландшафту
uniform float biome_tint_strength : hint_range(0.0, 1.0, 0.05) = 0.3; // Сила фарбування текстур біомом
uniform bool invert_height = false; 
uniform vec3 snow_color : source_color = vec3(0.9, 0.95, 1.0);
group_uniforms; // Закриваємо групи

varying vec3 world_pos_var;
varying vec3 world_normal_var;

// --- ФУНКЦІЯ ОСТРІВЦІВ КАМЕНЮ ---
float get_outcropping_mask(vec2 pos) {
	float n = sin(pos.x * 0.05) * cos(pos.y * 0.05) * 0.5 + 0.5;
	n += sin(pos.x * 0.15 + 1.2) * cos(pos.y * 0.15 - 0.5) * 0.25;
	// ЖОРСТКІШІ УМОВИ: Було 0.65-0.8. Тепер 0.75-0.9 (Виступи стали рідкісними)
	return smoothstep(0.75, 0.9, n); 
}

// --- ЖОРСТКІШІ УМОВИ ДЛЯ РЕЛЬЄФУ ---
void get_material_weights(vec3 w_pos, vec3 w_norm, out float cliff, out float pebble, out float sand, out float dirt, out float grass) {
	float steepness = 1.0 - dot(w_norm, vec3(0.0, 1.0, 0.0));
	
	// Скелі тепер ТІЛЬКИ на дуже крутих горах (Було 0.45. Стало 0.55)
	cliff = smoothstep(0.55, 0.75, steepness);
	
	// Галька/Каміння з'являється біля скель (0.4 - 0.55) та зрідка на рівнинах
	float outcropping = get_outcropping_mask(w_pos.xz);
	pebble = outcropping * smoothstep(0.05, 0.3, steepness); 
	pebble += smoothstep(0.4, 0.55, steepness) * (1.0 - cliff);
	pebble = clamp(pebble, 0.0, 1.0);
	
	// Пісок виключно біля самої води
	sand = 1.0 - smoothstep(4.5, 5.5, w_pos.y);
	sand *= (1.0 - cliff) * (1.0 - pebble); 
	
	// Бруд слугує переходом між травою і каменем (0.25 - 0.4)
	dirt = smoothstep(0.25, 0.4, steepness) * (1.0 - cliff) * (1.0 - pebble);
	
	// Трава заповнює всі пологі ділянки
	grass = 1.0 - clamp(cliff + pebble + sand + dirt, 0.0, 1.0);
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

	// --- 1. СКЕЛІ ---
	vec2 r_x = w_pos.zy * rock_scale; vec2 r_y = w_pos.xz * rock_scale; vec2 r_z = w_pos.xy * rock_scale;
	vec3 cliff_alb = texture(rock_albedo, r_x).rgb * tri_w.x + texture(rock_albedo, r_y).rgb * tri_w.y + texture(rock_albedo, r_z).rgb * tri_w.z;
	vec3 cliff_nrm = texture(rock_normal, r_x).rgb * tri_w.x + texture(rock_normal, r_y).rgb * tri_w.y + texture(rock_normal, r_z).rgb * tri_w.z;
	vec3 cliff_orm = texture(rock_orm, r_x).rgb * tri_w.x + texture(rock_orm, r_y).rgb * tri_w.y + texture(rock_orm, r_z).rgb * tri_w.z;

	// --- 2. ЧИТАННЯ ТЕКСТУР РІВНИН ---
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

	// --- 3. ВПЛИВ БІОМУ ТА ОСВІТЛЕННЯ (Виправлено) ---
	// Замість множення використовуємо mix, щоб зберегти красу самих текстур!
	p_alb = mix(p_alb, COLOR.rgb, biome_tint_strength);
	g_alb = mix(g_alb, COLOR.rgb, biome_tint_strength);
	d_alb = mix(d_alb, COLOR.rgb, biome_tint_strength);
	s_alb = mix(s_alb, COLOR.rgb, biome_tint_strength);

	// --- 4. ЗМІШУВАННЯ ---
	vec3 final_albedo = cliff_alb * w_cliff + p_alb * w_pebble + g_alb * w_grass + d_alb * w_dirt + s_alb * w_sand;
	vec3 final_normal = cliff_nrm * w_cliff + p_nrm * w_pebble + g_nrm * w_grass + d_nrm * w_dirt + s_nrm * w_sand;
	vec3 final_orm    = cliff_orm * w_cliff + p_orm_tex * w_pebble + g_orm_tex * w_grass + d_orm_tex * w_dirt + s_orm_tex * w_sand;

	// Сніг на вершинах
	final_albedo = mix(final_albedo, snow_color, COLOR.a);

	// --- 5. ФІНАЛЬНИЙ ВИВІД ---
	ALBEDO = clamp(final_albedo * global_brightness, 0.0, 1.0);

	float normal_fade = smoothstep(150.0, 50.0, dist); 
	float current_normal_scale = rock_normal_scale * w_cliff + pebble_normal_scale * w_pebble + grass_normal_scale * w_grass + dirt_normal_scale * w_dirt + sand_normal_scale * w_sand;
	
	vec3 normal_offset = (final_normal * 2.0 - 1.0) * current_normal_scale * normal_fade;
	NORMAL = (VIEW_MATRIX * vec4(normalize(w_norm + normal_offset), 0.0)).xyz;
	
	AO = final_orm.r;        
	ROUGHNESS = final_orm.g; 
	METALLIC = final_orm.b;  
}