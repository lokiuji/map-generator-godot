shader_type spatial;
render_mode cull_disabled, depth_draw_opaque;

uniform sampler2D albedo_texture : source_color;
uniform float wind_speed = 1.5;
uniform float wind_strength = 0.2;

void vertex() {
	vec3 world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float wind = sin(world_pos.x * 0.5 + TIME * wind_speed) * sin(world_pos.z * 0.5 + TIME * wind_speed * 0.8);
	VERTEX.x += wind * wind_strength * max(0.0, VERTEX.y);
	VERTEX.z += wind * wind_strength * max(0.0, VERTEX.y) * 0.5;
}

void fragment() {
	vec4 tex = texture(albedo_texture, UV);
	
	// Обчислюємо чорно-білу яскравість текстури трави
	float grayscale = dot(tex.rgb, vec3(0.299, 0.587, 0.114));
	
	// Змішуємо яскравість текстури з кольором біому (COLOR.rgb)
	// Множник 2.0 повертає насиченість, щоб трава виглядала соковитою
	vec3 final_color = grayscale * COLOR.rgb * 2.0; 
	
	ALBEDO = final_color;
	ALPHA = tex.a;
	ALPHA_SCISSOR_THRESHOLD = 0.5;
}