extends CanvasLayer

@onready var map_texture: TextureRect = %MapTexture

var is_generated = false

func _ready(): visible = false

func _input(event):
	if event is InputEventKey and event.pressed and event.keycode == KEY_M:
		visible = !visible
		if visible:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
			if not is_generated:
				_draw_map()
				is_generated = true
		else:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _draw_map():
	var res = 250
	var img = Image.create(res, res, false, Image.FORMAT_RGB8)
	for x in range(res):
		for y in range(res):
			var b = Global.get_biome_data((float(x)/res)*Global.WORLD_SIZE, (float(y)/res)*Global.WORLD_SIZE)
			var col = b["color"]
			if b["elevation"] > 0.4: col = col.darkened((b["elevation"] - 0.4) * 0.7)
			img.set_pixel(x, y, col)
			
	# ВИПРАВЛЕНО: Використовуємо правильну назву змінної та правильний клас ImageTexture
	map_texture.texture = ImageTexture.create_from_image(img)
