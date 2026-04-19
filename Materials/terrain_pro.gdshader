shader_type spatial;
varying float v_height;
varying float v_moisture;

void vertex() {
	v_height = (MODEL_MATRIX * vec4(VERTEX, 1.0)).y;
	v_moisture = COLOR.r; 
}

void fragment() {
	vec3 color;
	
	vec3 color_sand = vec3(0.8, 0.7, 0.4);
	vec3 color_grass = vec3(0.3, 0.5, 0.15);
	vec3 color_forest = vec3(0.1, 0.3, 0.1);
	vec3 color_rock = vec3(0.4, 0.4, 0.4);
	vec3 color_snow = vec3(0.9, 0.9, 0.95);

	if (v_moisture < -0.15) {
		color = color_sand; 
	} else {
		color = mix(color_grass, color_forest, smoothstep(-0.15, 0.4, v_moisture));
	}

	if (v_height < 3.0) {
		color = mix(color_sand, color, smoothstep(2.0, 3.0, v_height));
	} else if (v_height > 40.0) { // Каміння починається аж на 40 метрах!
		color = mix(color, color_rock, smoothstep(40.0, 60.0, v_height));
		color = mix(color, color_snow, smoothstep(120.0, 150.0, v_height)); // Сніг тільки на вершинах гір
	}
	
	ALBEDO = color;
	ROUGHNESS = 0.9;
}