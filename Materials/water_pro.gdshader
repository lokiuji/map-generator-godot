shader_type spatial;
// depth_draw_always гарантує правильне накладання тіней та прозорості
render_mode specular_schlick_ggx, cull_disabled, depth_draw_always;

uniform vec3 color_deep : source_color = vec3(0.05, 0.35, 0.65);
uniform vec3 color_shallow : source_color = vec3(0.2, 0.8, 0.85); 
uniform vec3 color_foam : source_color = vec3(1.0, 1.0, 1.0);
uniform float metallic = 0.8;
uniform float roughness = 0.05;

uniform sampler2D wave_noise;
uniform sampler2D depth_texture : hint_depth_texture, filter_linear_mipmap;

varying vec2 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xz;
	float time = TIME * 0.8;
	
	// Хвилі Герстнера
	float wave1 = sin(world_pos.x * 0.03 + time) * 0.6;
	float wave2 = cos(world_pos.y * 0.04 + time * 1.2) * 0.6;
	
	// Трохи зменшили загальну висоту хвиль, щоб вони менше пробивали берег
	VERTEX.y += (wave1 + wave2) * 0.8; 
}

void fragment() {
	// Точна глибина
	float depth_tex = textureLod(depth_texture, SCREEN_UV, 0.0).r;
	vec4 ndc = vec4(SCREEN_UV * 2.0 - 1.0, depth_tex, 1.0);
	vec4 view_pos = INV_PROJECTION_MATRIX * ndc;
	view_pos.xyz /= view_pos.w;
	float water_depth = max(0.0, VERTEX.z - view_pos.z);

	vec2 uv1 = world_pos * 0.02 + vec2(TIME * 0.015, TIME * 0.01);
	vec2 uv2 = world_pos * 0.02 + vec2(-TIME * 0.01, TIME * 0.015);
	vec3 n1 = texture(wave_noise, uv1).xyz;
	vec3 n2 = texture(wave_noise, uv2).xyz;
	vec3 raw_normal = mix(n1, n2, 0.5);

	float calm_factor = smoothstep(0.0, 2.0, water_depth);
	vec3 final_normal = mix(vec3(0.0, 1.0, 0.0), raw_normal, calm_factor);

	// === 1. ВБИВАЄМО СІТКУ БЕРЕГА ===
	// Вода повністю розчиняється в перших 15 см від землі. 
	// Це робить перетин полігонів невидимим і створює ідеальний зріз!
	float edge_alpha = smoothstep(0.15, 1.0, water_depth);

	// Пульсуюча піна
	float foam_zone = smoothstep(0.2, 1.0, water_depth) * (1.0 - smoothstep(1.0, 3.0, water_depth));
	float wave_pulse = sin(water_depth * 5.0 - TIME * 4.0) * 0.5 + 0.5;
	float foam = foam_zone * wave_pulse;

	// Градієнт мілководдя (тепер він працюватиме, бо ми викопаємо дно!)
	float color_blend = smoothstep(0.0, 8.0, water_depth);
	vec3 water_color = mix(color_shallow, color_deep, color_blend);
	vec3 final_color = mix(water_color, color_foam, foam);

	if (!FRONT_FACING) {
		// ОПТИКА: Вигляд з-під води
		float view_angle = dot(normalize(VIEW), NORMAL);
		float snell = smoothstep(0.3, 0.8, view_angle);
		ALBEDO = mix(color_deep * 0.4, final_color, snell);
		METALLIC = mix(1.0, 0.0, snell);
		ROUGHNESS = mix(0.0, 0.1, snell);
		ALPHA = mix(1.0, 0.5, snell);
		NORMAL_MAP = final_normal * 0.3;
	} else {
		// ЗВИЧАЙНИЙ ВИГЛЯД ЗВЕРХУ
		ALBEDO = final_color;
		METALLIC = metallic;
		ROUGHNESS = roughness;
		NORMAL_MAP = final_normal;
		
		// МАГІЯ: Використовуємо edge_alpha, щоб приховати сітку берега + непрозора піна
		ALPHA = max(edge_alpha * 0.95, foam); 
	}
}