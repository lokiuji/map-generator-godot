extends Control

@onready var map_preview = %MapPreview
@onready var seed_input = %SeedInput
@onready var random_button = %RandomButton
@onready var start_button = %StartButton

var noise = FastNoiseLite.new()

func _ready():
	# Робимо мишку видимою для меню
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	
	# Налаштовуємо шум точно так, як у грі
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	noise.frequency = 0.00045 
	noise.fractal_octaves = 4

	# Підключаємо сигнали кнопок
	seed_input.text_changed.connect(_on_seed_changed)
	random_button.pressed.connect(_generate_random_seed)
	start_button.pressed.connect(_on_start_pressed)
	
	_generate_random_seed() 

func _generate_random_seed():
	var new_seed = randi() % 999999
	_update_seed_and_map(new_seed)

func _update_seed_and_map(new_seed: int):
	Global.world_seed = new_seed
	noise.seed = new_seed
	seed_input.text = str(new_seed)
	_draw_preview()

func _on_seed_changed(new_text: String):
	if new_text.is_valid_int():
		Global.world_seed = new_text.to_int()
		noise.seed = Global.world_seed
		_draw_preview()

func _draw_preview():
	var res = 150 # Роздільна здатність прев'ю (для швидкості)
	var img = Image.create(res, res, false, Image.FORMAT_RGB8)
	var center = Global.WORLD_SIZE / 2.0
	
	for y in range(res):
		for x in range(res):
			var wx = (float(x) / res) * Global.WORLD_SIZE
			var wz = (float(y) / res) * Global.WORLD_SIZE
			
			# Радіальна маска (така ж, як у world_chunk.gd)
			var dist = Vector2(wx, wz).distance_to(Vector2(center, center))
			var edge_falloff = smoothstep(center * 0.7, center * 0.98, dist)
			
			var v = noise.get_noise_2d(wx, wz)
			v = v - edge_falloff * 2.0
			
			# Кольори біомів
			var col = Color.DARK_BLUE
			if v > -0.15: col = Color.CORNFLOWER_BLUE
			if v > 0.0: col = Color.PALE_GOLDENROD
			if v > 0.03: col = Color.FOREST_GREEN
			if v > 0.35: col = Color.SLATE_GRAY
			img.set_pixel(x, y, col)
			
	map_preview.texture = ImageTexture.create_from_image(img)

func _on_start_pressed():
	# Змінюємо сцену на основну 3D сцену гри
	get_tree().change_scene_to_file("res://node_3d.tscn")
