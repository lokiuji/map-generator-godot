shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

// === ТЕКСТУРИ ===
uniform sampler2D rock_albedo : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D rock_orm : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform sampler2D rock_normal : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D rock_heightmap : hint_default_black, filter_linear_mipmap, repeat_enable;
uniform sampler2D rock_emission : hint_default_black, filter_linear_mipmap, repeat_enable;

// === НАЛАШТУВАННЯ МАПІНГУ ===
uniform float rock_scale = 0.2; 
uniform float heightmap_scale = 1.0; 
uniform bool invert_height = false; // <--- ГАЛОЧКА ДЛЯ ВИПРАВЛЕННЯ "ВПРЕСОВАНОСТІ"
uniform float normal_scale = 1.0;

uniform vec3 dirt_color : source_color = vec3(0.3, 0.2, 0.15);
uniform vec3 snow_color : source_color = vec3(0.9, 0.95, 1.0);
uniform float rock_slope_threshold = 0.5;
uniform float blend_amount = 0.1;

varying vec3 world_pos_var;
varying vec3 world_normal_var;

void vertex() {
	world_pos_var = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal_var = (MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz;
	
	// Рахуємо вагу каменю тільки для вершин
	float slope = dot(normalize(world_normal_var), vec3(0.0, 1.0, 0.0));
	float rock_w = smoothstep(rock_slope_threshold - blend_amount, rock_slope_threshold + blend_amount, 1.0 - slope);

	// Трипланарна матриця (посилена до pow 8.0 для ідеальних стиків)
	vec3 w = abs(world_normal_var);
	w = pow(w, vec3(8.0)); 
	vec3 tri_w = w / (w.x + w.y + w.z);

	// === ФІЗИЧНИЙ РЕЛЬЄФ ===
	if (rock_w > 0.01) {
		float dist = distance(CAMERA_POSITION_WORLD, world_pos_var);
		float disp_fade = smoothstep(60.0, 15.0, dist); 
		
		if (disp_fade > 0.01) {
			vec2 uv_x = world_pos_var.zy * rock_scale;
			vec2 uv_y = world_pos_var.xz * rock_scale;
			vec2 uv_z = world_pos_var.xy * rock_scale;
			
			// КРИТИЧНЕ ВИПРАВЛЕННЯ: textureLod читає ідеальну текстуру у вершинному шейдері!
			float h_x = textureLod(rock_heightmap, uv_x, 0.0).r;
			float h_y = textureLod(rock_heightmap, uv_y, 0.0).r;
			float h_z = textureLod(rock_heightmap, uv_z, 0.0).r;
			
			float h = h_x * tri_w.x + h_y * tri_w.y + h_z * tri_w.z;
			
			// Виправляємо впресованість, якщо потрібно
			if (invert_height) {
				h = 1.0 - h;
			}
			
			VERTEX += NORMAL * (h - 0.5) * heightmap_scale * disp_fade * rock_w;
		}
	}
}

void fragment() {
	vec3 w_pos = world_pos_var;
	float dist = distance(CAMERA_POSITION_WORLD, w_pos);
	
	// === ВИПРАВЛЕННЯ ТРИКУТНИКІВ: Перераховуємо нахил для кожного пікселя окремо ===
	vec3 w_norm = normalize(world_normal_var);
	float slope = dot(w_norm, vec3(0.0, 1.0, 0.0));
	float rock_w = smoothstep(rock_slope_threshold - blend_amount, rock_slope_threshold + blend_amount, 1.0 - slope);

	vec3 w = abs(w_norm);
	w = pow(w, vec3(8.0));
	vec3 tri_w = w / (w.x + w.y + w.z);

	// === ЧИТАННЯ ТЕКСТУР ===
	vec2 uv_x = w_pos.zy * rock_scale;
	vec2 uv_y = w_pos.xz * rock_scale;
	vec2 uv_z = w_pos.xy * rock_scale;

	vec3 alb = texture(rock_albedo, uv_x).rgb * tri_w.x + 
	           texture(rock_albedo, uv_y).rgb * tri_w.y + 
	           texture(rock_albedo, uv_z).rgb * tri_w.z;
	
	vec3 norm = texture(rock_normal, uv_x).rgb * tri_w.x + 
	            texture(rock_normal, uv_y).rgb * tri_w.y + 
	            texture(rock_normal, uv_z).rgb * tri_w.z;
	
	vec3 orm = texture(rock_orm, uv_x).rgb * tri_w.x + 
	           texture(rock_orm, uv_y).rgb * tri_w.y + 
	           texture(rock_orm, uv_z).rgb * tri_w.z;

	vec3 em = texture(rock_emission, uv_x).rgb * tri_w.x + 
	          texture(rock_emission, uv_y).rgb * tri_w.y + 
	          texture(rock_emission, uv_z).rgb * tri_w.z;

	// Змішування біомів (трава -> земля -> камінь)
	float dirt_w = smoothstep(0.3, 0.45, 1.0 - slope);
	vec3 base_col = mix(COLOR.rgb, dirt_color, dirt_w);
	
	ALBEDO = mix(base_col, alb, rock_w);
	ALBEDO = mix(ALBEDO, snow_color, COLOR.a);

	// Нормалі плавно вимикаються вдалині, щоб уникнути мерехтіння
	float normal_fade = smoothstep(150.0, 50.0, dist); 
	vec3 rock_normal_offset = (norm * 2.0 - 1.0) * normal_scale * normal_fade * rock_w;
	NORMAL = (VIEW_MATRIX * vec4(normalize(w_norm + rock_normal_offset), 0.0)).xyz;
	
	// PBR Канали з текстури ORM
	AO = mix(1.0, orm.r, rock_w);        
	ROUGHNESS = mix(0.9, orm.g, rock_w); 
	METALLIC = mix(0.0, orm.b, rock_w);  
	EMISSION = em * rock_w;
}