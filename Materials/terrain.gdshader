shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_toon, specular_toon;

uniform vec3 color_sand : source_color = vec3(0.85, 0.75, 0.55);
uniform vec3 color_rock : source_color = vec3(0.45, 0.45, 0.50);
uniform vec3 color_snow : source_color = vec3(0.95, 0.95, 0.98);

uniform float water_level = -20.0;
uniform sampler2D terrain_noise;

varying float v_height;
varying vec3 v_world_pos;
varying vec3 v_color; // <--- Ловимо колір з вершини

void vertex() {
	v_height = VERTEX.y;
	v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_color = COLOR.rgb; // <--- Забираємо колір біома з генератора
}

void fragment() {
	// Основний колір (переданий з біома), а акцентний робимо на 40% темнішим автоматично!
	vec3 color_main = v_color;
	vec3 color_accent = color_main * 0.6; 
	
	float noise_val = texture(terrain_noise, v_world_pos.xz * 0.01).r;
	float h = v_height + (noise_val * 12.0 - 6.0);

	float mask_sand = smoothstep(water_level + 1.0, water_level + 6.0, h); 
	float mask_rock = smoothstep(20.0, 26.0, h); 
	float mask_snow = smoothstep(40.0, 45.0, h); 

	vec3 biome_color = mix(color_accent, color_main, clamp((v_height + 20.0) / 40.0 + noise_val, 0.0, 1.0));

	vec3 albedo = mix(color_sand, biome_color, mask_sand);
	albedo = mix(albedo, color_rock, mask_rock);
	albedo = mix(albedo, color_snow, mask_snow);

	ALBEDO = albedo;
	ROUGHNESS = 0.9;
}

void light() {
	float NdotL = dot(NORMAL, LIGHT);
	float toon_shade = smoothstep(0.0, 0.05, NdotL);
	vec3 shadow_color = ALBEDO * vec3(0.3, 0.3, 0.4); 
	DIFFUSE_LIGHT += mix(shadow_color, ALBEDO * LIGHT_COLOR * ATTENUATION, toon_shade);
}