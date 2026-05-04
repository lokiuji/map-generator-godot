shader_type spatial;
// Вимикаємо освітлення, туман і відсікання
render_mode unshaded, depth_test_disabled, cull_disabled;

uniform sampler2D depth_texture : hint_depth_texture, repeat_disable, filter_nearest;

uniform float cam_height = 500.0; // Висота камери над 0.0
uniform float max_terrain_height = 150.0; // Твоя макс. висота землі (з GDScript)

void vertex() {
	// Розтягуємо QuadMesh на весь екран камери
	POSITION = vec4(VERTEX.xy, 1.0, 1.0);
}

void fragment() {
	float depth = texture(depth_texture, SCREEN_UV).x;
	
	// Конвертуємо глибину в метри
	vec3 ndc = vec3(SCREEN_UV * 2.0 - 1.0, depth);
	vec4 view = INV_PROJECTION_MATRIX * vec4(ndc, 1.0);
	view.xyz /= view.w;
	float linear_depth = -view.z;
	
	// Рахуємо висоту землі (від 0.0)
	float world_height = cam_height - linear_depth;
	
	// Нормалізуємо (0.0 - глибоко, 1.0 - макс. висота)
	float normalized_height = clamp(world_height / max_terrain_height, 0.0, 1.0);
	
	ALBEDO = vec3(normalized_height);
}