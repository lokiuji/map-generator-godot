shader_type spatial;

uniform vec3 rock_color : source_color = vec3(0.35, 0.35, 0.4);
uniform vec3 dirt_color : source_color = vec3(0.40, 0.25, 0.15);
uniform vec3 snow_color : source_color = vec3(0.9, 0.95, 1.0);

uniform float dirt_slope_threshold = 0.35;
uniform float rock_slope_threshold = 0.6;
uniform float blend_amount = 0.08;

varying vec3 world_normal;

void vertex() {
	world_normal = (MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz;
}

void fragment() {
	vec3 biome_color = COLOR.rgb;
	// Читаємо інформацію про сніг, яку згенерував наш шум у скрипті!
	float snow_mask = COLOR.a; 
	
	float slope = dot(normalize(world_normal), vec3(0.0, 1.0, 0.0));
	float steepness = 1.0 - slope; 
	
	float dirt_weight = smoothstep(dirt_slope_threshold - blend_amount, dirt_slope_threshold + blend_amount, steepness);
	float rock_weight = smoothstep(rock_slope_threshold - blend_amount, rock_slope_threshold + blend_amount, steepness);
	
	vec3 slope_color = mix(biome_color, dirt_color, dirt_weight);
	slope_color = mix(slope_color, rock_color, rock_weight);
	
	// На дуже стрімких скелях сніг тримається гірше
	float rock_on_snow = smoothstep(0.8, 0.95, steepness);
	vec3 final_snow = mix(snow_color, rock_color, rock_on_snow * 0.5);
	
	vec3 final_color = mix(slope_color, final_snow, snow_mask);
	
	ALBEDO = final_color;
	ROUGHNESS = 0.8;
}