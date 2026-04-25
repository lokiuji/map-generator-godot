extends CanvasLayer

@onready var texture_rect = $TextureRect # Переконайся, що ім'я вузла збігається з твоїм деревом!

func _ready():
	visible = false

func _input(event):
	if event.is_action_pressed("map"):
		visible = !visible
		if visible:
			_generate_map_image()
			Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
		else:
			Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

func _generate_map_image():
	var map_res = 200 # Роздільна здатність карти (можна збільшити до 300)
	var img = Image.create(map_res, map_res, false, Image.FORMAT_RGB8)
	
	for x in range(map_res):
		for y in range(map_res):
			# Конвертуємо пікселі карти в координати великого світу
			var world_x = (float(x) / map_res) * Global.WORLD_SIZE
			var world_z = (float(y) / map_res) * Global.WORLD_SIZE
			
			var b_data = Global.get_biome_data(world_x, world_z)
			var col = b_data["color"]
			
			# Додаємо красиві тіні для гір, щоб було видно рельєф
			var e = b_data["elevation"]
			if e > 0.4: col = col.darkened((e - 0.4) * 0.8)
				
			img.set_pixel(x, y, col)
			
	texture_rect.texture = ImageTexture.create_from_image(img)
