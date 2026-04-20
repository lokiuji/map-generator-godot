extends CanvasLayer

@onready var map_texture: TextureRect = %MapTexture
@onready var player_marker: ColorRect = %PlayerMarker
@onready var player = get_tree().get_first_node_in_group("player")

const WORLD_SIZE = 6000.0 
const MAP_RES = 250 

var noise_continent = FastNoiseLite.new()

func _ready():
	if not map_texture or not player_marker:
		push_error("ПОМИЛКА: Вузли мапи не знайдені! Перевір ієрархію в MapUI.tscn")
		return
	noise_continent.noise_type = FastNoiseLite.TYPE_SIMPLEX
	noise_continent.frequency = 0.0005 
	noise_continent.seed = 777
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
			# Якщо мапа закрилася на "M" - ХОВАЄМО мишку і повертаємо камеру
			Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

	if visible and event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			_teleport_to_map_point(event.position)

func _generate_map_image():
	var img = Image.create(MAP_RES, MAP_RES, false, Image.FORMAT_RGB8)
	var center = WORLD_SIZE / 2.0 # Центр мапи
	
	for y in range(MAP_RES):
		for x in range(MAP_RES):
			var wx = (float(x) / MAP_RES) * WORLD_SIZE
			var wz = (float(y) / MAP_RES) * WORLD_SIZE
			
			# === ФІКС: ДОДАЄМО РАДІАЛЬНУ МАСКУ НА UI МАПУ ===
			var dist_from_center = Vector2(wx, wz).distance_to(Vector2(center, center))
			var edge_falloff = 1.0 - smoothstep(center * 0.7, center * 0.98, dist_from_center)
			
			var v = noise_continent.get_noise_2d(wx, wz)
			v = lerp(-1.0, v, edge_falloff) # Топимо береги, як у 3D світі
			
			var col = Color.DARK_BLUE 
			if v > -0.15: col = Color.CORNFLOWER_BLUE 
			if v > 0.0: col = Color.PALE_GOLDENROD 
			if v > 0.03: col = Color.FOREST_GREEN 
			if v > 0.35: col = Color.SLATE_GRAY 
			
			img.set_pixel(x, y, col)
	
	map_texture.texture = ImageTexture.create_from_image(img)

func _teleport_to_map_point(_mouse_pos):
	# Беремо координати мишки ЛОКАЛЬНО всередині самої картинки мапи!
	var local_mouse = map_texture.get_local_mouse_position()
	
	# Перевіряємо, чи клікнули ми саме по картинці (а не повз неї)
	if local_mouse.x >= 0 and local_mouse.x <= map_texture.size.x and \
	   local_mouse.y >= 0 and local_mouse.y <= map_texture.size.y:
		
		# Рахуємо відсоток кліку (від 0.0 до 1.0)
		var percent_x = local_mouse.x / map_texture.size.x
		var percent_y = local_mouse.y / map_texture.size.y
		
		# Переводимо у світові координати
		var target_x = percent_x * WORLD_SIZE
		var target_z = percent_y * WORLD_SIZE
		
		if player:
			player.global_position = Vector3(target_x, 400.0, target_z)
			visible = false
			Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

func _process(_delta):
	if not visible or not player or map_texture == null or player_marker == null:
		return
		
	# Знаходимо відсоток позиції гравця у світі (від 0.0 до 1.0)
	var percent_x = wrapf(player.global_position.x, 0.0, WORLD_SIZE) / WORLD_SIZE
	var percent_z = wrapf(player.global_position.z, 0.0, WORLD_SIZE) / WORLD_SIZE
	
	# Ставимо маркер ЛОКАЛЬНО відносно картинки мапи
	player_marker.position = Vector2(
		percent_x * map_texture.size.x,
		percent_z * map_texture.size.y
	) - (player_marker.size / 2.0)
