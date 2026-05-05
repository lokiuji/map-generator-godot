shader_type spatial;
render_mode unshaded, depth_test_disabled, cull_disabled, depth_draw_never;

uniform sampler2D depth_texture : hint_depth_texture, repeat_disable, filter_nearest;

uniform float cam_height = 500.0; 
uniform float min_terrain_height = -100.0;
uniform float max_terrain_height = 400.0;

// ЗНАЧЕННЯ ТВОЄЇ КАМЕРИ (Мають співпадати з налаштуваннями MapCamera)
uniform float cam_near = 0.05;
uniform float cam_far = 2000.0;

void vertex() {
	POSITION = vec4(VERTEX.xy * 2.0, 0.0, 1.0);
}

void fragment() {
	float depth = texture(depth_texture, SCREEN_UV).x;
	
	// Якщо чанку немає (небо) - це глибоке дно (-100м)
	if (depth >= 0.99999) {
		ALBEDO = vec3(0.0); 
	} else {
		// ПРАВИЛЬНА математика для Orthogonal камери!
		// Просто змішуємо дистанцію між Near і Far площинами
		float linear_depth = mix(cam_near, cam_far, depth);
		
		// Рахуємо реальну висоту
		float world_height = cam_height - linear_depth;
		float normalized_height = clamp((world_height - min_terrain_height) / (max_terrain_height - min_terrain_height), 0.0, 1.0);
		
		ALBEDO = vec3(normalized_height);
	}
}