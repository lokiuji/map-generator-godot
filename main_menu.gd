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
			Global.custom_spawn_x = px * Global.WORLD_SIZE
			Global.custom_spawn_z = py * Global.WORLD_SIZE
			
			if not marker_rect:
				marker_rect = ColorRect.new()
				marker_rect.color = Color.RED
				marker_rect.size = Vector2(8, 8)
				map_preview.add_child(marker_rect)
			
			marker_rect.position = event.position - marker_rect.size / 2.0

func _draw_preview():
	var res = 150 
	var img = Image.create(res, res, false, Image.FORMAT_RGB8)
	var center = Global.WORLD_SIZE / 2.0
	
	for y in range(res):
		for x in range(res):
			var wx = (float(x) / res) * Global.WORLD_SIZE
			var wz = (float(y) / res) * Global.WORLD_SIZE
			
			var dist = Vector2(wx, wz).distance_to(Vector2(center, center))
			var edge_falloff = smoothstep(center * 0.7, center * 0.98, dist)
			
			var v = noise.get_noise_2d(wx, wz)
			v = v - edge_falloff * 2.0
			
			var col = Color.DARK_BLUE
			if v > -0.05: col = Color.CORNFLOWER_BLUE
			if v > 0.0: col = Color.PALE_GOLDENROD
			if v > 0.03: col = Color.FOREST_GREEN
			if v > 0.35: col = Color.SLATE_GRAY
			img.set_pixel(x, y, col)
			
	map_preview.texture = ImageTexture.create_from_image(img)

func _on_start_pressed():
	get_tree().change_scene_to_file("res://node_3d.tscn")
