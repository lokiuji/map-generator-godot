extends Control

# === ЗМІННІ ІНТЕРФЕЙСУ ===
@onready var map_preview = %MapPreview
@onready var seed_input = %SeedInput
@onready var random_button = %RandomButton
@onready var start_button = %StartButton

var marker_rect: ColorRect # Маркер точки спавну

func _ready():
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

	seed_input.text_changed.connect(_on_seed_changed)
	random_button.pressed.connect(_generate_random_seed)
	start_button.pressed.connect(_on_start_pressed)
	
	# Слухаємо кліки по мапі
	map_preview.gui_input.connect(_on_map_gui_input)
	
	# Одразу малюємо мапу, бо Global вже прочитав її з JSON
	_draw_preview()

func _generate_random_seed():
	var new_seed = randi() % 999999
	_update_seed_and_map(new_seed)

func _update_seed_and_map(new_seed: int):
	Global.world_seed = new_seed
	seed_input.text = str(new_seed)
	
	# Скидаємо вибір точки спавну при оновленні меню
	Global.custom_spawn_x = -1.0
	if marker_rect:
		marker_rect.queue_free()
		marker_rect = null

func _on_seed_changed(new_text: String):
	if new_text.is_valid_int():
		_update_seed_and_map(new_text.to_int())

func _on_map_gui_input(event: InputEvent):
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if Global.map_width == 0: return # Якщо мапа не завантажилась, не реагуємо
		
		var s = min(map_preview.size.x, map_preview.size.y)
		var offset_x = (map_preview.size.x - s) / 2.0
		var offset_y = (map_preview.size.y - s) / 2.0
		
		var img_x = event.position.x - offset_x
		var img_y = event.position.y - offset_y
		
		if img_x >= 0 and img_x <= s and img_y >= 0 and img_y <= s:
			var px = img_x / s
			var py = img_y / s
			
			# Переводимо координати кліку в реальні масштаби світу
			Global.custom_spawn_x = px * (Global.map_width * Global.tile_size)
			Global.custom_spawn_z = py * (Global.map_height * Global.tile_size)
			
			# Малюємо маркер
			if not marker_rect:
				marker_rect = ColorRect.new()
				marker_rect.color = Color.RED
				marker_rect.size = Vector2(8, 8)
				map_preview.add_child(marker_rect)
			
			marker_rect.position = event.position - marker_rect.size / 2.0

func _draw_preview():
	if Global.map_width == 0: return
	
	var img = Image.create(Global.map_width, Global.map_height, false, Image.FORMAT_RGB8)
	
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
	
	for x in range(Global.map_width):
		for y in range(Global.map_height):
			# === ОСЬ ТУТ БУЛА ПОМИЛКА З КВАДРАТНОЮ ДУЖКОЮ ===
			var tile = Global.map_grid[x][y]
			var biome = tile["biome"]
			var col = BIOME_COLORS.get(biome, Color.MAGENTA)
			
			# Тіні для рельєфу гір на карті
			var elevation = float(tile["elevation"])
			if elevation > 0.1:
				col = col.darkened(1.0 - elevation)
				
			img.set_pixel(x, y, col)
			
	map_preview.texture = ImageTexture.create_from_image(img)
	map_preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED

func _on_start_pressed():
	get_tree().change_scene_to_file("res://node_3d.tscn")
