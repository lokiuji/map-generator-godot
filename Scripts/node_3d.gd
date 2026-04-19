extends Node3D

const CHUNK_SIZE = 120.0
const RENDER_DISTANCE = 4

@export var player: Node3D
@export var terrain_material: Material

var active_chunks = {}
var current_player_chunk = Vector2(1000000, 1000000)
var is_first_spawn = true 

var global_noise: FastNoiseLite
var moisture_noise: FastNoiseLite
var mountain_noise: FastNoiseLite

# --- ЗМІННА ДЛЯ ПРОЦЕДУРНОЇ ТРАВИ ---
var procedural_grass_mesh: Mesh

# --- КАРТА З ПРОКРУТКОЮ ---
var map_canvas: CanvasLayer
var map_rect: TextureRect
var map_size = 400
var map_zoom = 15.0
var map_offset = Vector2.ZERO 
var is_dragging_map = false

func _ready():
	_setup_noises()
	
	# ГЕНЕРУЄМО 3D-СІТКУ ТРАВИ КОДОМ! Ніяких зовнішніх файлів!
	procedural_grass_mesh = _build_grass_mesh()
	
	if not player: player = get_node_or_null("Player")
	_setup_map_ui()
	
	if player:
		player.process_mode = Node.PROCESS_MODE_DISABLED 
		current_player_chunk = Vector2(floor(player.global_position.x / CHUNK_SIZE), floor(player.global_position.z / CHUNK_SIZE))
		update_chunks(current_player_chunk)

func _setup_noises():
	global_noise = FastNoiseLite.new()
	global_noise.seed = 1234
	global_noise.frequency = 0.005
	
	moisture_noise = FastNoiseLite.new()
	moisture_noise.seed = 9999
	moisture_noise.frequency = 0.003
	
	mountain_noise = FastNoiseLite.new()
	mountain_noise.seed = 3333
	mountain_noise.frequency = 0.001 

# --- МАГІЯ: СТВОРЕННЯ МЕШУ ТРАВИ З НУЛЯ ---
func _build_grass_mesh() -> Mesh:
	var st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var w = 0.4 # Ширина травинки
	var h = 0.8 # Висота травинки
	
	# Площина 1 (Спереду/Ззаду)
	st.set_uv(Vector2(0, 1)); st.add_vertex(Vector3(-w, 0, 0))
	st.set_uv(Vector2(1, 1)); st.add_vertex(Vector3(w, 0, 0))
	st.set_uv(Vector2(1, 0)); st.add_vertex(Vector3(w, h, 0))
	st.set_uv(Vector2(0, 1)); st.add_vertex(Vector3(-w, 0, 0))
	st.set_uv(Vector2(1, 0)); st.add_vertex(Vector3(w, h, 0))
	st.set_uv(Vector2(0, 0)); st.add_vertex(Vector3(-w, h, 0))
	
	# Площина 2 (Зліва/Справа) - Перехрестя
	st.set_uv(Vector2(0, 1)); st.add_vertex(Vector3(0, 0, -w))
	st.set_uv(Vector2(1, 1)); st.add_vertex(Vector3(0, 0, w))
	st.set_uv(Vector2(1, 0)); st.add_vertex(Vector3(0, h, w))
	st.set_uv(Vector2(0, 1)); st.add_vertex(Vector3(0, 0, -w))
	st.set_uv(Vector2(1, 0)); st.add_vertex(Vector3(0, h, w))
	st.set_uv(Vector2(0, 0)); st.add_vertex(Vector3(0, h, -w))
	
	st.generate_normals()
	return st.commit()

# --- ЛОГІКА ІНТЕРФЕЙСУ КАРТИ ---
func _setup_map_ui():
	map_canvas = CanvasLayer.new()
	map_canvas.visible = false
	map_rect = TextureRect.new()
	map_rect.custom_minimum_size = Vector2(600, 600)
	map_rect.set_anchors_preset(Control.PRESET_CENTER)
	map_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	map_rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	map_rect.gui_input.connect(_on_map_gui_input)
	map_canvas.add_child(map_rect)
	add_child(map_canvas)

func _unhandled_input(event):
	if event is InputEventKey and event.pressed and event.keycode == KEY_M:
		map_canvas.visible = !map_canvas.visible
		if map_canvas.visible:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
			map_offset = Vector2(player.global_position.x, player.global_position.z)
			_generate_map_texture()
		else:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _on_map_gui_input(event):
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_RIGHT:
			is_dragging_map = event.pressed
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			var scale = map_rect.size.x / map_size
			var dx = (event.position.x / scale - map_size/2.0) * map_zoom
			var dy = (event.position.y / scale - map_size/2.0) * map_zoom
			_teleport_player(Vector3(map_offset.x + dx, 350.0, map_offset.y + dy))

	if event is InputEventMouseMotion and is_dragging_map:
		var scale = map_rect.size.x / map_size
		map_offset.x -= event.relative.x / scale * map_zoom
		map_offset.y -= event.relative.y / scale * map_zoom
		_generate_map_texture()

func _generate_map_texture():
	var img = Image.create(map_size, map_size, false, Image.FORMAT_RGB8)
	for y in range(map_size):
		for x in range(map_size):
			var wx = map_offset.x + (x - map_size/2.0) * map_zoom
			var wz = map_offset.y + (y - map_size/2.0) * map_zoom
			
			var h = global_noise.get_noise_2d(wx, wz)
			var m = moisture_noise.get_noise_2d(wx, wz)
			var mount = mountain_noise.get_noise_2d(wx, wz)
			
			# ТА САМА МАТЕМАТИКА ВИСОТИ ДЛЯ КАРТИ
			var base_h = (h + 1.0) / 2.0
			var py = pow(base_h, 1.5) * 20.0
			if mount > 0.0:
				py += smoothstep(0.0, 0.8, mount) * base_h * 180.0
			
			var col = Color(0.1, 0.4, 0.1) 
			if py < 2.8: col = Color(0.1, 0.3, 0.7) # Вода
			elif py > 100.0: col = Color.WHITE # Сніг
			elif py > 40.0: col = Color.GRAY # Скелі
			elif m < -0.15: col = Color(0.8, 0.7, 0.3) # Пісок
			else:
				var g = clamp(0.5 + m*0.5, 0.2, 0.6)
				col = Color(0.1, g, 0.15)
				
			img.set_pixel(x, y, col)
	
	var p_map_x = (player.global_position.x - map_offset.x) / map_zoom + map_size/2.0
	var p_map_y = (player.global_position.z - map_offset.y) / map_zoom + map_size/2.0
	if p_map_x > 0 and p_map_x < map_size and p_map_y > 0 and p_map_y < map_size:
		img.set_pixel(int(p_map_x), int(p_map_y), Color.RED)
		
	map_rect.texture = ImageTexture.create_from_image(img)

func _teleport_player(target: Vector3):
	map_canvas.visible = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	player.process_mode = Node.PROCESS_MODE_DISABLED
	player.global_position = target
	for c in active_chunks.values(): c.queue_free()
	active_chunks.clear()
	is_first_spawn = true
	current_player_chunk = Vector2(floor(player.global_position.x / CHUNK_SIZE), floor(player.global_position.z / CHUNK_SIZE))
	update_chunks(current_player_chunk)

func _process(_delta):
	if not player: return
	var px = floor(player.global_position.x / CHUNK_SIZE)
	var pz = floor(player.global_position.z / CHUNK_SIZE)
	var new_chunk = Vector2(px, pz)
	
	if new_chunk != current_player_chunk:
		current_player_chunk = new_chunk
		update_chunks(current_player_chunk)

func update_chunks(center_chunk: Vector2):
	var desired_chunks = []
	for x in range(-RENDER_DISTANCE, RENDER_DISTANCE + 1):
		for z in range(-RENDER_DISTANCE, RENDER_DISTANCE + 1):
			if Vector2(x, z).length() <= RENDER_DISTANCE: 
				desired_chunks.append(center_chunk + Vector2(x, z))
				
	var chunks_to_remove = []
	for chunk_pos in active_chunks.keys():
		if not desired_chunks.has(chunk_pos): chunks_to_remove.append(chunk_pos)
			
	for chunk_pos in chunks_to_remove:
		active_chunks[chunk_pos].queue_free()
		active_chunks.erase(chunk_pos)
		
	for chunk_pos in desired_chunks:
		if not active_chunks.has(chunk_pos): spawn_chunk(chunk_pos)

func spawn_chunk(chunk_pos: Vector2):
	var chunk = Node3D.new()
	chunk.set_script(preload("res://world_chunk.gd"))
	chunk.name = "Chunk_%d_%d" % [chunk_pos.x, chunk_pos.y]
	chunk.global_position = Vector3(chunk_pos.x * CHUNK_SIZE, 0, chunk_pos.y * CHUNK_SIZE)
	chunk.chunk_ready.connect(_on_chunk_ready) 
	add_child(chunk)
	active_chunks[chunk_pos] = chunk
	
	# ПЕРЕДАЄМО ГОТОВУ ТРАВУ В ЧАНК
	chunk.start_generation(chunk_pos, CHUNK_SIZE, 16, terrain_material, global_noise, moisture_noise, mountain_noise, procedural_grass_mesh)

func _on_chunk_ready(chunk: Node3D):
	if is_first_spawn and chunk.chunk_pos == current_player_chunk:
		is_first_spawn = false
		if player:
			player.global_position.y = 250.0 
			player.process_mode = Node.PROCESS_MODE_INHERIT
