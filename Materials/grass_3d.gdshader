shader_type spatial;
render_mode cull_disabled, diffuse_toon;

uniform sampler2D grass_tex : source_color;
uniform vec3 color_top : source_color = vec3(0.45, 0.85, 0.25);
uniform vec3 color_bottom : source_color = vec3(0.10, 0.40, 0.15);

varying float v_y_gradient;

void vertex() {
	v_y_gradient = clamp(VERTEX.y / 1.5, 0.0, 1.0);
}

void fragment() {
	vec4 tex = texture(grass_tex, UV);
	if (tex.a < 0.5) { discard; } // Це гарантовано покаже траву
	
	vec3 base_color = mix(color_bottom, color_top, v_y_gradient);
	ALBEDO = tex.rgb * base_color;
	ALPHA = tex.a;
	ALPHA_SCISSOR_THRESHOLD = 0.5; // Відсікає прозорий фон картинки
}