extends CanvasLayer

@onready var panel: Panel = $Panel
@onready var map_texture: TextureRect = %MapTexture
@onready var player_marker: ColorRect = %PlayerMarker
var player: Node3D

func _ready():
	player = get_tree().get_first_node_in_group("player")
	self.hide()
	if map_texture:
		map_texture.gui_input.connect(_on_map_gui_input)
		_generate_map_texture()

func _generate_map_texture():
	var img_size = 256 
	var img = Image.create(img_size, img_size, false, Image.FORMAT_RGB8)
	var step = Global.WORLD_SIZE / img_size
	var start_coord = -Global.WORLD_SIZE / 2.0 # Початкова точка для від'ємних координат

	for y in range(img_size):
		for x in range(img_size):
			var b_data = Global.get_biome_data(start_coord + x * step, start_coord + y * step)
			img.set_pixel(x, y, b_data["color"])
	map_texture.texture = ImageTexture.create_from_image(img)

func _process(_delta):
	if player and visible:
		var map_size = map_texture.size
		# Додаємо половину розміру світу, щоб перенести діапазон з [-30000, 30000] у [0, 60000]
		player_marker.position = Vector2(
			((player.global_position.x + Global.WORLD_SIZE / 2.0) / Global.WORLD_SIZE) * map_size.x,
			((player.global_position.z + Global.WORLD_SIZE / 2.0) / Global.WORLD_SIZE) * map_size.y
		)

func _on_map_gui_input(event):
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var map_size = map_texture.size
		# Повертаємо координати кліку назад у світовий діапазон [-30000, 30000]
		var world_x = (event.position.x / map_size.x) * Global.WORLD_SIZE - (Global.WORLD_SIZE / 2.0)
		var world_z = (event.position.y / map_size.y) * Global.WORLD_SIZE - (Global.WORLD_SIZE / 2.0)
		var world_manager = get_tree().current_scene
		if world_manager.has_method("teleport_player"):
			world_manager.teleport_player(Vector2(world_x, world_z))
			hide()
			Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

func _input(event):
	if event is InputEventKey and event.pressed and event.keycode == KEY_M:
		visible = !visible
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE if visible else Input.MOUSE_MODE_CAPTURED)
