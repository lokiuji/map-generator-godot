extends Control

@onready var map_preview = %MapPreview
@onready var seed_input = %SeedInput
@onready var random_button = %RandomButton
@onready var start_button = %StartButton

var marker_rect: ColorRect 

func _ready():
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	seed_input.text_changed.connect(_on_seed_changed)
	random_button.pressed.connect(_generate_random_seed)
	start_button.pressed.connect(_on_start_pressed)
	map_preview.gui_input.connect(_on_map_gui_input)
	_generate_random_seed()

func _generate_random_seed():
	var new_seed = randi() % 999999
	_update_seed_and_map(new_seed)

func _update_seed_and_map(new_seed: int):
	Global.set_seed(new_seed)
	seed_input.text = str(new_seed)
	# Скидаємо на наші нові маркери-запобіжники
	Global.custom_spawn_x = -999999.0
	Global.custom_spawn_z = -999999.0
	if marker_rect:
		marker_rect.queue_free()
		marker_rect = null
	_draw_preview()

func _on_seed_changed(new_text: String):
	if new_text.is_valid_int():
		_update_seed_and_map(new_text.to_int())

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
			
			# ВИПРАВЛЕНО: Зсуваємо клік у діапазон від -30000 до 30000
			Global.custom_spawn_x = (px * Global.WORLD_SIZE) - (Global.WORLD_SIZE / 2.0)
			Global.custom_spawn_z = (py * Global.WORLD_SIZE) - (Global.WORLD_SIZE / 2.0)
			
			if not marker_rect:
				marker_rect = ColorRect.new()
				marker_rect.color = Color.RED
				marker_rect.size = Vector2(8, 8)
				map_preview.add_child(marker_rect)
			
			marker_rect.position = event.position - marker_rect.size / 2.0

func _draw_preview():
	var map_res = 150 
	var img = Image.create(map_res, map_res, false, Image.FORMAT_RGB8)
	
	for x in range(map_res):
		for y in range(map_res):
			# ВИПРАВЛЕНО: Зсуваємо рендер пікселів, щоб вони відповідали центру
			var world_x = (float(x) / map_res) * Global.WORLD_SIZE - (Global.WORLD_SIZE / 2.0)
			var world_z = (float(y) / map_res) * Global.WORLD_SIZE - (Global.WORLD_SIZE / 2.0)
			
			var b_data = Global.get_biome_data(world_x, world_z)
			var col = b_data["color"]
			
			var e = b_data["elevation"]
			if e > 0.15: col = col.darkened((1.0 - e) * 0.5)
				
			img.set_pixel(x, y, col)
			
	map_preview.texture = ImageTexture.create_from_image(img)
	map_preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED

func _on_start_pressed():
	get_tree().change_scene_to_file("res://node_3d.tscn")
