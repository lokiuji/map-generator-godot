shader_type spatial;
// depth_draw_opaque дозволяє відкидати правильні тіні на землю крізь "прогризені" дірки
render_mode diffuse_toon, specular_disabled, cull_disabled, depth_draw_opaque;

uniform sampler2D leaf_tex : source_color, filter_nearest;
uniform vec3 color_trunk : source_color = vec3(0.35, 0.2, 0.1);

varying vec3 v_color;
varying float v_height; // Змінна для визначення низу/верху крони

void vertex() {
	v_color = COLOR.rgb;
	if (COLOR.g > 0.5) {
		vec3 local_cam_pos = (inverse(MODEL_MATRIX) * vec4(CAMERA_POSITION_WORLD, 1.0)).xyz;
		vec3 dir_to_cam = normalize(local_cam_pos - VERTEX);
		vec3 up = vec3(0.0, 1.0, 0.0);
		
		vec3 right = normalize(cross(up, dir_to_cam));
		vec3 cam_up = normalize(cross(dir_to_cam, right)); 
		
		// ВИРАХОВУЄМО ВИСОТУ: беремо Y-координату вершини.
		// Відносно центру дерева (який десь на висоті 8.0 - 9.6), рахуємо градієнт від 0.0 (низ) до 1.0 (верх).
		v_height = clamp((VERTEX.y - 6.5) / 5.0, 0.0, 1.0);
		
		VERTEX += right * UV2.x + cam_up * UV2.y;
		
		// Ідеальна куля для освітлення
		vec3 local_normal = normalize(VERTEX - vec3(0.0, 9.6, 0.0));
		NORMAL = normalize((MODELVIEW_MATRIX * vec4(local_normal, 0.0)).xyz);
	}
}

void fragment() {
	if (v_color.g < 0.5) {
		ALBEDO = color_trunk;
	} else {
		vec4 tex = texture(leaf_tex, UV);
		
		// 1. АГРЕСИВНЕ "ПРОГРИЗАННЯ": Збільшили до 0.65.
		// Це виїсть ще більше напівпрозорих країв, утворюючи великі дірки, крізь які видно чорну серцевину.
		if (tex.a < 0.65) { discard; }

		// 2. ПЛАВНИЙ ГРАДІЄНТ ГЛИБИНИ: Більше ніяких сходинок.
		// Гладкий перехід від 30% радіуса (повна темрява) до 90% радіуса (яскравий колір текстури).
		float depth = smoothstep(0.3, 0.9, v_color.r);
		
		// 3. ЗАТЕМНЕННЯ НИЗУ: Використовуємо v_height з vertex().
		// Нижні гілки будуть на 50% темнішими просто через те, що вони внизу.
		float bottom_shadow = mix(0.4, 1.0, v_height);
		
		// Насичений колір тіні (трохи синьо-зелений для атмосфери)
		vec3 deep_shadow_color = tex.rgb * vec3(0.15, 0.25, 0.2); 
		
		// Спочатку застосовуємо глибину, потім додатково затемнюємо низ
		vec3 base_color = mix(deep_shadow_color, tex.rgb, depth);
		ALBEDO = base_color * bottom_shadow;
	}
}

void light() {
	if (v_color.g < 0.5) {
		float NdotL = dot(NORMAL, LIGHT) * 0.5 + 0.5;
		// ДОДАНО ATTENUATION: Це вмикає системні тіні. Тепер стовбур буде в тіні від крони!
		float shade = smoothstep(0.45, 0.55, NdotL) * ATTENUATION;
		DIFFUSE_LIGHT += mix(ALBEDO * 0.2, ALBEDO * LIGHT_COLOR, shade);
	} else {
		float NdotL = dot(NORMAL, LIGHT) * 0.5 + 0.5;
		
		// ДОДАНО ATTENUATION ДЛЯ ЛИСТЯ: Тепер дерево відкидає тінь на себе, на інші дерева і на землю.
		float shade = smoothstep(0.45, 0.55, NdotL * ATTENUATION);
		
		vec3 shadow_color = ALBEDO * 0.3; 
		vec3 lit_color = ALBEDO * LIGHT_COLOR;
		
		DIFFUSE_LIGHT += mix(shadow_color, lit_color, shade);
	}
}