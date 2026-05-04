shader_type canvas_item;
uniform sampler2D depth_texture : hint_depth_texture, repeat_disable, filter_nearest;

// Ці значення мають збігатися з налаштуваннями MapCamera
uniform float cam_height = 500.0; // Висота камери над нулем
uniform float max_terrain_height = 150.0; // Максимальна висота гір у грі

void fragment() {
    float depth = texture(depth_texture, SCREEN_UV).x;
    
    // Конвертуємо буфер глибини в реальні метри
    vec3 ndc = vec3(SCREEN_UV * 2.0 - 1.0, depth);
    vec4 view = INV_PROJECTION_MATRIX * vec4(ndc, 1.0);
    view.xyz /= view.w;
    float linear_depth = -view.z;
    
    // Рахуємо реальну висоту землі (від 0.0)
    float world_height = cam_height - linear_depth;
    
    // Нормалізуємо висоту в колір (від 0.0 до 1.0), де 1.0 - це найвища гора
    COLOR = vec4(world_height / max_terrain_height, 0.0, 0.0, 1.0);
}