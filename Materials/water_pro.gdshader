shader_type spatial;
render_mode specular_toon;

uniform vec3 water_color : source_color = vec3(0.1, 0.4, 0.5);
uniform vec3 deep_color : source_color = vec3(0.0, 0.1, 0.2);
uniform float foam_range = 0.4;
uniform sampler2D depth_texture : hint_depth_texture, filter_nearest;

void fragment() {
	float depth_raw = texture(depth_texture, SCREEN_UV).r;
	vec3 ndc = vec3(SCREEN_UV * 2.0 - 1.0, depth_raw);
	vec4 view = INV_PROJECTION_MATRIX * vec4(ndc, 1.0);
	view.xyz /= view.w;
	float depth_linear = -view.z;
	
	float diff = depth_linear - VERTEX.z;
	
	// Піна біля берега
	if (diff < foam_range) {
		ALBEDO = vec3(1.0);
	} else {
		float depth_blend = clamp(diff / 10.0, 0.0, 1.0);
		ALBEDO = mix(water_color, deep_color, depth_blend);
	}
	ALPHA = 0.9;
	ROUGHNESS = 0.1;
}