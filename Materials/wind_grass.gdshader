shader_type spatial;
render_mode cull_disabled, depth_draw_opaque, depth_prepass_alpha;

uniform sampler2D albedo_texture : source_color;
uniform float wind_speed = 1.5;
uniform float wind_strength = 0.2;

varying vec3 v_world_normal;

void vertex() {
	vec3 world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float wind = sin(world_pos.x * 0.5 + TIME * wind_speed) * sin(world_pos.z * 0.5 + TIME * wind_speed * 0.8);
	VERTEX.x += wind * wind_strength * max(0.0, VERTEX.y);
	VERTEX.z += wind * wind_strength * max(0.0, VERTEX.y) * 0.5;
	
	// Зберігаємо світову нормаль землі, яку ми передали зі скрипта
	v_world_normal = INSTANCE_CUSTOM.xyz;
}

void fragment() {
	vec4 tex = texture(albedo_texture, UV);
	float brightness = dot(tex.rgb, vec3(0.299, 0.587, 0.114));
	
	// Безпечний діапазон (0.8 - 1.1), який не перетворить траву на пересвічений лайм
	vec3 tip_color = mix(COLOR.rgb * 0.8, COLOR.rgb * 1.1, brightness);
	
	// Самий корінь (UV.y = 1.0) буде 100% чистим кольором землі.
	vec3 final_color = mix(tip_color, COLOR.rgb, UV.y);
	
	ALBEDO = final_color;
	ALPHA = tex.a;
	ALPHA_SCISSOR_THRESHOLD = 0.5;
	
	ROUGHNESS = 0.8;
	SPECULAR = 0.0;
	
	// ВИПРАВЛЕНО ОСВІТЛЕННЯ:
	// Тепер кущ освітлюється сонцем ІДЕНТИЧНО до того клаптика землі, з якого росте.
	NORMAL = (VIEW_MATRIX * vec4(v_world_normal, 0.0)).xyz;
}