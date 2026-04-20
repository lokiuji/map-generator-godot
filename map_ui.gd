extends CanvasLayer

@onready var map_texture_rect = $Panel/MapTexture
@onready var player_marker = $Panel/MapTexture/PlayerMarker
@onready var player = get_tree().get_first_node_in_group("player")

const WORLD_SIZE = 6000.0 
const MAP_RES = 250 

var noise_continent = FastNoiseLite.new()

func _ready():
	noise_continent.noise_type = FastNoiseLite.TYPE_SIMPLEX
	noise_continent.frequency = 0.0005 
	noise_continent.seed = 777
	
	visible = false 

func _input(event):
	if event.is_action_pressed("ui_map"):
		visible = !visible
		if visible:
			_generate_map_image()
			Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE if visible else Input.MOUSE_MODE_CAPTURED)

	if visible and event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			_teleport_to_map_point(event.position)

func _generate_map_image():
	var img = Image.create(MAP_RES, MAP_RES, false, Image.FORMAT_RGB8)
	
	for y in range(MAP_RES):
		for x in range(MAP_RES):
			var wx = (float(x) / MAP_RES) * WORLD_SIZE
			var wz = (float(y) / MAP_RES) * WORLD_SIZE
			
			var v = noise_continent.get_noise_2d(wx, wz)
			
			var col = Color.DARK_BLUE 
			if v > -0.15: col = Color.CORNFLOWER_BLUE 
			if v > 0.0: col = Color.PALE_GOLDENROD 
			if v > 0.1: col = Color.FOREST_GREEN 
			if v > 0.35: col = Color.SLATE_GRAY 
			
			img.set_pixel(x, y, col)
	
	map_texture_rect.texture = ImageTexture.create_from_image(img)

func _teleport_to_map_point(mouse_pos):
	var rect = map_texture_rect.get_global_rect()
	if rect.has_point(mouse_pos):
		var local_coord = (mouse_pos - rect.position) / rect.size
		var target_x = local_coord.x * WORLD_SIZE
		var target_z = local_coord.y * WORLD_SIZE
		
		if player:
			player.global_position = Vector3(target_x, 150.0, target_z)
			visible = false
			Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

func _process(_delta):
	if visible and player:
		var px = (player.global_position.x / WORLD_SIZE) * map_texture_rect.size.x
		var pz = (player.global_position.z / WORLD_SIZE) * map_texture_rect.size.y
		player_marker.position = Vector2(px, pz) - (player_marker.size / 2.0)
