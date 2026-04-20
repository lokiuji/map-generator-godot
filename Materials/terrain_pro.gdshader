shader_type spatial;

// === КОЛЬОРИ ІДЕАЛЬНО ЗІСТИКОВАНІ З ТРАВОЮ ===
// Базовий колір землі тепер ТОЧНО дорівнює color_bottom з трави!
uniform vec3 color_grass : source_color = vec3(0.12, 0.28, 0.08);
uniform vec3 color_forest : source_color = vec3(0.08, 0.20, 0.05);

uniform vec3 color_sand : source_color = vec3(0.76, 0.70, 0.50);
uniform vec3 color_rock : source_color = vec3(0.45, 0.45, 0.45);
uniform vec3 color_snow : source_color = vec3(0.95, 0.95, 0.95);

varying float v_height;
varying float v_moisture;

void vertex() {
	v_height = (MODEL_MATRIX * vec4(VERTEX, 1.0)).y;
	v_moisture = COLOR.r; 
}

void fragment() {
	// Рахуємо крутизну схилу (чим ближче до 1.0, тим плоскіша земля)
	float slope = NORMAL.y; 
	
	vec3 color;
	if (v_moisture < -0.15) {
		color = color_sand; 
	} else {
		// Трава росте там, де не занадто круто (slope > 0.7)
		color = mix(color_grass, color_forest, smoothstep(-0.15, 0.5, v_moisture));
	}

	// Якщо схил крутий (slope < 0.65) — це скеля, незалежно від висоти!
	if (slope < 0.65) {
		color = mix(color_rock, color, smoothstep(0.5, 0.65, slope));
	}
	
	// Сніг залишаємо тільки на дуже великій висоті
	if (v_height > 120.0) {
		color = mix(color, color_snow, smoothstep(120.0, 160.0, v_height));
	}
	
	ALBEDO = color;
}