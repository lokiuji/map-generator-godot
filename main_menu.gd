extends Control

@onready var map_preview = %MapPreview
@onready var seed_input = %SeedInput
@onready var random_button = %RandomButton
@onready var start_button = %StartButton

var noise = FastNoiseLite.new()
var marker_rect: ColorRect # Маркер спавну, який ми створимо з коду

func _ready():
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	noise.frequency = 0.00045 
	noise.fractal_octaves = 4

	seed_input.text_changed.connect(_on_seed_changed)
	random_button.pressed.connect(_generate_random_seed)
	start_button.pressed.connect(_on_start_pressed)
	
	# ДОДАНО: Слухаємо кліки по прев'ю мапи
	map_preview.gui_input.connect(_on_map_gui_input)
	
	_generate_random_seed() 

func _generate_random_seed():
	var new_seed = randi() % 999999
	_update_seed_and_map(new_seed)

func _update_seed_and_map(new_seed: int):
	Global.world_seed = new_seed
	noise.seed = new_seed
	seed_input.text = str(new_seed)
	_draw_preview()
	
	# Скидаємо вибір спавну при зміні карти
	Global.custom_spawn_x = -1.0
	if marker_rect:
		marker_rect.queue_free()
		marker_rect = null

func _on_seed_changed(new_text: String):
	if new_text.is_valid_int():
		_update_seed_and_map(new_text.to_int())

# ДОДАНО: Обробка кліку та встановлення точки спавну
func _on_map_gui_input(event: InputEvent):
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var s = min(map_preview.size.x, map_preview.size.y)
		var offset_x = (map_preview.size.x - s) / 2.0
		var offset_y = (map_preview.size.y - s) / 2.0
		
		var img_x = event.position.x - offset_x
		var img_y = event.position.y - offset_y
		
		if img_x >= 0 and img_x <= s and img_y >= 0 and img_y <= s:
			var px = img_x / s
			var py = img_y / s
			
			# ТЕПЕР МИ МНОЖИМО ВІДСОТОК НА РЕАЛЬНУ ШИРИНУ PYTHON МАПИ
			Global.custom_spawn_x = px * (Global.map_width * Global.tile_size)
			Global.custom_spawn_z = py * (Global.map_height * Global.tile_size)
			
			if not marker_rect:
				marker_rect = ColorRect.new()
			
			if not marker_rect:
				marker_rect = ColorRect.new()
				marker_rect.color = Color.RED
				marker_rect.size = Vector2(8, 8)
				map_preview.add_child(marker_rect)
			
			marker_rect.position = event.position - marker_rect.size / 2.0

func _draw_preview():
	if Global.map_data.is_empty():
		return
		
	# Створюємо зображення точнісінько розміром з вашу Python-мапу
	var img = Image.create(Global.map_width, Global.map_height, false, Image.FORMAT_RGB8)
	
	# Використовуємо словник кольорів біомів з вашого world_chunk
	var BIOME_COLORS = {
		"ocean": Color(0.10, 0.30, 0.60),
		"beach": Color(0.76, 0.70, 0.50),
		"scorched": Color(0.25, 0.20, 0.20),
		"bare": Color(0.45, 0.40, 0.35),
		"tundra": Color(0.55, 0.65, 0.65),
		"snow": Color(0.90, 0.95, 1.00),
		"temperate_desert": Color(0.75, 0.65, 0.45),
		"shrubland": Color(0.45, 0.55, 0.25),
		"grassland": Color(0.20, 0.35, 0.15),
		"temperate_deciduous_forest": Color(0.15, 0.30, 0.10),
		"temperate_rain_forest": Color(0.10, 0.25, 0.08),
		"subtropical_desert": Color(0.85, 0.70, 0.50),
		"tropical_seasonal_forest": Color(0.30, 0.45, 0.10),
		"tropical_rain_forest": Color(0.10, 0.30, 0.05)
	}
	
	for key in Global.map_data:
		var tile = Global.map_data[key]
		var biome = tile["biome"]
		var col = BIOME_COLORS.get(biome, Color.MAGENTA)
		
		# Додаємо трохи тіней за висотою для краси
		var elevation = tile["elevation"]
		if elevation > 0.1:
			col = col.darkened(1.0 - elevation)
			
		img.set_pixel(tile["x"], tile["y"], col)
		
	map_preview.texture = ImageTexture.create_from_image(img)
	# Встановлюємо Stretch Mode на Keep Aspect, щоб мапа не була розмитою
	map_preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED

func _on_start_pressed():
	get_tree().change_scene_to_file("res://node_3d.tscn")
