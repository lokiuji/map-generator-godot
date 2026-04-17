shader_type spatial;
render_mode cull_disabled, depth_draw_opaque;

uniform sampler2D albedo_texture : source_color;
uniform float wind_speed = 1.5;
uniform float wind_strength = 0.2;

void vertex() {
	// Вітер базується на світових координатах, щоб хвилі йшли по всьому полю
	vec3 world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float wind = sin(world_pos.x * 0.5 + TIME * wind_speed) * sin(world_pos.z * 0.5 + TIME * wind_speed * 0.8);
	
	// Рухаємо тільки верхню частину трави (чим вище VERTEX.y, тим сильніше хитається)
	VERTEX.x += wind * wind_strength * max(0.0, VERTEX.y);
	VERTEX.z += wind * wind_strength * max(0.0, VERTEX.y) * 0.5;
}

void fragment() {
	vec4 tex = texture(albedo_texture, UV);
	// COLOR.rgb зберігає оригінальні кольори Quaternius!
	ALBEDO = tex.rgb * COLOR.rgb; 
	ALPHA = tex.a;
	ALPHA_SCISSOR_THRESHOLD = 0.5;
}