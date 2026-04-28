shader_type spatial;

// ТЕКТУРИ З ВАШОГО rocky.tres
uniform sampler2D rock_albedo : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D rock_orm : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform sampler2D rock_normal : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D rock_heightmap : filter_linear_mipmap, repeat_enable;
uniform sampler2D rock_emission : hint_default_black, filter_linear_mipmap, repeat_enable;

// ПАРАМЕТРИ З rocky.tres
uniform float rock_scale = 0.2; 
uniform float heightmap_scale = 7.5; // Значення з вашого файлу
uniform float normal_scale = 1.0;

uniform vec3 dirt_color : source_color = vec3(0.3, 0.2, 0.15);
uniform vec3 snow_color : source_color = vec3(0.9, 0.95, 1.0);
uniform float rock_slope_threshold = 0.5;
uniform float blend_amount = 0.1;

varying vec3 world_pos_var;
varying vec3 world_normal_var;
varying float v_rock_weight;
varying vec3 tri_weights;

void vertex() {
	world_pos_var = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal_var = (MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz;
	
	float slope = dot(normalize(world_normal_var), vec3(0.0, 1.0, 0.0));
	v_rock_weight = smoothstep(rock_slope_threshold - blend_amount, rock_slope_threshold + blend_amount, 1.0 - slope);

	// Трипланарна вага для безшовності
	tri_weights = abs(world_normal_var);
	tri_weights /= (tri_weights.x + tri_weights.y + tri_weights.z);

	// ГЛИБИНА (Displacement/Heightmap)
	if (v_rock_weight > 0.01) {
		float dist = distance(CAMERA_POSITION_WORLD, world_pos_var);
		// Вдавлювання працює тільки зблизька для економії ресурсів
		float disp_fade = smoothstep(60.0, 15.0, dist);
		if (disp_fade > 0.01) {
			// Читаємо висоту з вашої мапи
			float h = texture(rock_heightmap, world_pos_var.xz * rock_scale).r;
			// 7.5 — це дуже велика глибина, тому множимо обережно
			VERTEX += NORMAL * (h - 0.5) * heightmap_scale * 0.1 * disp_fade * v_rock_weight;
		}
	}
}

void fragment() {
	vec3 w_pos = world_pos_var;
	
	// Підготовка трипланарних UV
	vec2 uv_x = w_pos.zy * rock_scale;
	vec2 uv_y = w_pos.xz * rock_scale;
	vec2 uv_z = w_pos.xy * rock_scale;

	// Змішування ALBEDO
	vec3 alb = texture(rock_albedo, uv_x).rgb * tri_weights.x + 
	           texture(rock_albedo, uv_y).rgb * tri_weights.y + 
	           texture(rock_albedo, uv_z).rgb * tri_weights.z;
	
	// Змішування NORMAL
	vec3 norm = texture(rock_normal, uv_x).rgb * tri_weights.x + 
	            texture(rock_normal, uv_y).rgb * tri_weights.y + 
	            texture(rock_normal, uv_z).rgb * tri_weights.z;
	
	// Змішування ORM (Red: AO, Green: Roughness, Blue: Metallic)
	vec3 orm = texture(rock_orm, uv_x).rgb * tri_weights.x + 
	           texture(rock_orm, uv_y).rgb * tri_weights.y + 
	           texture(rock_orm, uv_z).rgb * tri_weights.z;

	// Змішування EMISSION
	vec3 em = texture(rock_emission, uv_x).rgb * tri_weights.x + 
	          texture(rock_emission, uv_y).rgb * tri_weights.y + 
	          texture(rock_emission, uv_z).rgb * tri_weights.z;

	float steepness = 1.0 - dot(normalize(world_normal_var), vec3(0.0, 1.0, 0.0));
	float dirt_w = smoothstep(0.3, 0.45, steepness);

	vec3 base_col = mix(COLOR.rgb, dirt_color, dirt_w);
	
	ALBEDO = mix(base_col, alb, v_rock_weight);
	ALBEDO = mix(ALBEDO, snow_color, COLOR.a);

	// ПРИЗНАЧЕННЯ КАНАЛІВ (згідно з вашим rocky.tres)
	NORMAL = (VIEW_MATRIX * vec4(normalize(world_normal_var + (norm * 2.0 - 1.0) * normal_scale), 0.0)).xyz;
	AO = mix(1.0, orm.r, v_rock_weight);        // AO_texture_channel = 0
	ROUGHNESS = mix(0.9, orm.g, v_rock_weight); // Roughness_texture_channel = 1
	METALLIC = mix(0.0, orm.b, v_rock_weight);  // Metallic_texture_channel = 2
	EMISSION = em * v_rock_weight;
}