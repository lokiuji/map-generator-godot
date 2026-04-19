shader_type spatial;
render_mode cull_disabled, diffuse_toon;

// ЗВЕРНИ УВАГУ НА КОЛЬОРИ!
uniform vec3 color_bottom : source_color = vec3(0.15, 0.35, 0.1); 
uniform vec3 color_top : source_color = vec3(0.4, 0.7, 0.2);
uniform sampler2D color_noise; 
uniform float wind_speed = 1.2;
uniform float wind_strength = 0.15;

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float wind = sin(world_pos.x * 0.4 + TIME * wind_speed) * cos(world_pos.z * 0.4 + TIME * wind_speed);
	float height_factor = max(0.0, VERTEX.y); 
	VERTEX.x += wind * wind_strength * height_factor;
	
	// ЛОГІКА З ВІДЕО: Нормалі ідеально вгору. Немає чорних тіней!
	NORMAL = vec3(0.0, 1.0, 0.0);
}

void fragment() {
	float noise = texture(color_noise, world_pos.xz * 0.05).r;
	vec3 final_color = mix(color_bottom, color_top, UV.y);
	
	ALBEDO = mix(final_color, final_color * 1.4, noise * 0.4);
	ROUGHNESS = 0.8;
}