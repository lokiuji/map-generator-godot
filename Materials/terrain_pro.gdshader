void fragment() {
	vec3 color;
	
	vec3 color_sand = vec3(0.76, 0.70, 0.50); 
	// ТОЙ САМИЙ КОЛІР, ЩО Й НИЗ ТРАВИ:
	vec3 color_grass = vec3(0.15, 0.35, 0.1); 
	vec3 color_forest = vec3(0.1, 0.25, 0.08); 
	vec3 color_rock = vec3(0.45, 0.45, 0.45); 
	vec3 color_snow = vec3(0.95, 0.95, 0.95); 

	if (v_moisture < -0.15) {
		color = color_sand; 
	} else {
		// Там де росте трава, земля стає кольору трави
		color = mix(color_grass, color_forest, smoothstep(-0.15, 0.5, v_moisture));
	}

	if (v_height < 3.2) {
		color = mix(color_sand, color, smoothstep(2.5, 3.2, v_height));
	} else if (v_height > 35.0) {
		color = mix(color, color_rock, smoothstep(35.0, 50.0, v_height));
		color = mix(color, color_snow, smoothstep(110.0, 140.0, v_height));
	}
	
	ALBEDO = color;
	ROUGHNESS = 0.95;
}