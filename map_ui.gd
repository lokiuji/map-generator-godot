extends CanvasLayer

@onready var map_texture: TextureRect = %MapTexture
@onready var player_marker: ColorRect = %PlayerMarker
@onready var player = get_tree().get_first_node_in_group("player")

const MAP_RES = 250 

var noise_continent = FastNoiseLite.new()

func _ready():
	if not map_texture or not player_marker:
		push_error("ПОМИЛКА: Вузли мапи не знайдені! Перевір ієрархію в MapUI.tscn")
		return
	
	noise_continent.noise_type = FastNoiseLite.TYPE_SIMPLEX
	# ФІКС: Частота ТЕПЕР ІДЕАЛЬНО ЗБІГАЄТЬСЯ З world_chunk.gd (було 0.0005)
	noise_continent.frequency = 0.00045 
	noise_continent.seed = Global.world_seed
	noise_continent.fractal_octaves = 4
	
	map_texture.custom_minimum_size = Vector2(600, 600)
	map_texture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	map_texture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	visible = false 

func _input(event):
	if event.is_action_pressed("ui_map"):
		visible = !visible
		if visible:
			_generate_map_image()
			Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE if visible else Input.MOUSE_MODE_CAPTURED)
		else:
			Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

	if visible and event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			_teleport_to_map_point(event.position)

func _generate_map_image():
	var img = Image.create(MAP_RES, MAP_RES, false, Image.FORMAT_RGB8)
	var center = Global.WORLD_SIZE / 2.0
	
	for y in range(MAP_RES):
		for x in range(MAP_RES):
			var wx = (float(x) / MAP_RES) * Global.WORLD_SIZE
			var wz = (float(y) / MAP_RES) * Global.WORLD_SIZE
			
			var dist_from_center = Vector2(wx, wz).distance_to(Vector2(center, center))
			
			# Ті самі нові формули, що й у 3D світі
			var edge_falloff = smoothstep(center * 0.7, center * 0.98, dist_from_center)
			
			var v = noise_continent.get_noise_2d(wx, wz)
			v = v - edge_falloff * 2.0 # Ось ця зміна ключова!
			
			var col = Color.DARK_BLUE 
			if v > -0.05: col = Color.CORNFLOWER_BLUE # Мілководдя
			if v > 0.0: col = Color.PALE_GOLDENROD # Пляж
			if v > 0.03: col = Color.FOREST_GREEN # Трава
			if v > 0.35: col = Color.SLATE_GRAY # Гори 
			
			img.set_pixel(x, y, col)
	
	map_texture.texture = ImageTexture.create_from_image(img)

func _teleport_to_map_point(_mouse_pos):
	var local_mouse = map_texture.get_local_mouse_position()
	
	var s = min(map_texture.size.x, map_texture.size.y)
	var offset_x = (map_texture.size.x - s) / 2.0
	var offset_y = (map_texture.size.y - s) / 2.0
	
	var img_x = local_mouse.x - offset_x
	var img_y = local_mouse.y - offset_y
	
	if img_x >= 0 and img_x <= s and img_y >= 0 and img_y <= s:
		var percent_x = img_x / s
		var percent_y = img_y / s
		
		var target_x = percent_x * Global.WORLD_SIZE
		var target_z = percent_y * Global.WORLD_SIZE
		
		if player:
			# Кидаємо гравця з висоти, щоб він не опинився під землею
			player.global_position = Vector3(target_x, 400.0, target_z)
			# Скидаємо вертикальну швидкість, щоб він плавно падав на новий чанк
			player.velocity.y = 0.0 
			visible = false
			Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

func _process(_delta):
	if not visible or not player or map_texture == null or player_marker == null:
		return
		
	var percent_x = wrapf(player.global_position.x, 0.0, Global.WORLD_SIZE) / Global.WORLD_SIZE
	var percent_z = wrapf(player.global_position.z, 0.0, Global.WORLD_SIZE) / Global.WORLD_SIZE
	
	var s = min(map_texture.size.x, map_texture.size.y)
	var offset_x = (map_texture.size.x - s) / 2.0
	var offset_y = (map_texture.size.y - s) / 2.0
	
	# ФІКС: Використовуємо глобальну позицію для маркера, щоб він не з'їжджав
	# залежно від того, як розташований TextureRect у сцені
	var tex_global = map_texture.global_position
	player_marker.global_position = tex_global + Vector2(
		offset_x + (percent_x * s),
		offset_y + (percent_z * s)
	) - (player_marker.size / 2.0)
