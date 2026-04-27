shader_type spatial;
render_mode depth_draw_opaque;

uniform sampler2D alpha_texture : filter_nearest;
uniform sampler2D wind_noise : repeat_enable; 

uniform float wind_speed = 0.5;
uniform float wind_strength = 0.3;

uniform float fade_start = 120.0; 
uniform float fade_end = 150.0;
varying float wind_val;

void vertex() {
	vec3 world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float dist = distance(world_pos, CAMERA_POSITION_WORLD);
	float scale = 1.0 - smoothstep(fade_start, fade_end, dist);
	VERTEX *= scale;
	
	vec2 noise_uv = (world_pos.xz * 0.02) + (vec2(1.0, 0.5) * TIME * wind_speed);
	wind_val = texture(wind_noise, noise_uv).r;
	
	float height_factor = max(0.0, VERTEX.y); 
	VERTEX.x += wind_val * wind_strength * height_factor * scale;
	VERTEX.z += wind_val * wind_strength * 0.5 * height_factor * scale;
}

void fragment() {
	// 1. Читаємо текстуру (якщо вона тут є, трава не буде білим квадратом)
	vec4 tex = texture(alpha_texture, UV);
	ALPHA = tex.a;
	ALPHA_SCISSOR_THRESHOLD = 0.5; 
	
	// 2. COLOR.rgb - це колір біому, який передає world_chunk.gd
	float tip_mask = pow(1.0 - UV.y, 3.0); 
	vec3 base_color = mix(COLOR.rgb, COLOR.rgb * 1.8, tip_mask);
	vec3 final_color = mix(base_color, COLOR.rgb * 2.2, wind_val * tip_mask * 0.5);
	
	ALBEDO = clamp(final_color, vec3(0.0), vec3(1.0));
	
	// Налаштування матеріалу
	ROUGHNESS = 0.8;
	SPECULAR = 0.1;
	
	// 3. Форсуємо нормалі вгору для правильного освітлення
	vec3 up_normal = (VIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz;
	NORMAL = normalize(mix(NORMAL, up_normal, 0.9));
}

// 4. Додаємо штучну глибоку тінь (баг, який ми перетворили на фічу)
void light() {
	float NdotL = dot(NORMAL, LIGHT);
	float fake_shadow = smoothstep(0.0, 0.15, NdotL);
	float final_shadow = min(fake_shadow, ATTENUATION);
	
	vec3 shadow_color = ALBEDO * 0.25;
	DIFFUSE_LIGHT += mix(shadow_color, ALBEDO * LIGHT_COLOR, final_shadow);
}