extends CanvasLayer

@onready var panel: Panel = $Panel
@onready var map_texture: TextureRect = %MapTexture
@onready var player_marker: ColorRect = %PlayerMarker
var player: Node3D

func _ready():
	player = get_tree().get_first_node_in_group("player")
	
	# Оскільки CanvasLayer не має власного _gui_input, 
	# ми підключаємо сигнал натискання до самої картинки карти
	if map_texture:
		map_texture.gui_input.connect(_on_map_gui_input)

func _process(_delta):
	# У Godot 4 CanvasLayer має властивість visible
	if player and visible:
		_update_player_marker_position()

func _update_player_marker_position():
	var map_size = map_texture.size
	
	# Обчислюємо нормалізовану позицію гравця
	var norm_x = player.global_position.x / Global.WORLD_SIZE
	var norm_z = player.global_position.z / Global.WORLD_SIZE
	
	# Встановлюємо позицію маркера
	player_marker.position = Vector2(norm_x * map_size.x, norm_z * map_size.y)

# Ця функція тепер викликається, коли ви клікаєте саме по вузлу MapTexture
func _on_map_gui_input(event):
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var click_pos = event.position
		var map_size = map_texture.size
		
		var world_x = (click_pos.x / map_size.x) * Global.WORLD_SIZE
		var world_z = (click_pos.y / map_size.y) * Global.WORLD_SIZE
		
		var world_manager = get_tree().current_scene
		if world_manager.has_method("teleport_player"):
			world_manager.teleport_player(Vector2(world_x, world_z))
			
			self.hide()
			Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
