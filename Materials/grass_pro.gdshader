shader_type spatial;
render_mode cull_disabled, diffuse_toon, specular_disabled;

uniform vec3 color_top : source_color = vec3(0.2, 0.5, 0.1);
uniform vec3 color_bottom : source_color = vec3(0.05, 0.1, 0.05);
uniform sampler2D noise_tex : repeat_enable; // Вітер
uniform float wind_speed = 0.5;
uniform float wind_strength = 0.15;

void vertex() {
	vec3 world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float noise = texture(noise_tex, world_pos.xz * 0.05 + TIME * wind_speed).r;
	
	// Гнемо тільки верхівку
	float strength = (1.0 - UV.y) * wind_strength;
	VERTEX.x += cos(TIME + world_pos.x) * strength * noise;
	VERTEX.z += sin(TIME + world_pos.z) * strength * noise;
	
	// Магія нормалей для ідеального затінення
	NORMAL = vec3(0.0, 1.0, 0.0);
}

void fragment() {
	ALBEDO = mix(color_bottom, color_top, 1.0 - UV.y);
	if (!FRONT_FACING) { NORMAL = -NORMAL; }
}