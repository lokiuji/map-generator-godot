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
var continent_noise: FastNoiseLite 

var procedural_grass_mesh: Mesh

var map_canvas: CanvasLayer
var map_rect: TextureRect
var map_size = 400
var map_zoom = 18.0 
var map_offset = Vector2.ZERO 
var is_dragging_map = false

func _ready():
	_setup_noises()
	
	# === МАГІЯ: Збираємо 3 площини для текстури прямо тут ===
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
	global_noise.frequency = 0.008
	
	moisture_noise = FastNoiseLite.new()
	moisture_noise.seed = 9999
	moisture_noise.frequency = 0.003
	
	mountain_noise = FastNoiseLite.new()
	mountain_noise.seed = 3333
	mountain_noise.frequency = 0.001
	
	continent_noise = FastNoiseLite.new()
	continent_noise.seed = 7777
	# РОБИМО КОНТИНЕНТИ ВЕЛИЧЕЗНИМИ (Менше води, більше суші)
	continent_noise.frequency = 0.0003 

func _setup_map_ui():
	map_canvas = CanvasLayer.new()
	map_canvas.visible = false
	map_canvas.layer = 100
	
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
			
			var h_raw = global_noise.get_noise_2d(wx, wz)
			var c_raw = continent_noise.get_noise_2d(wx, wz)
			var m_raw = mountain_noise.get_noise_2d(wx, wz)
			var moist = moisture_noise.get_noise_2d(wx, wz)
			
			var py = 0.0
			# Зсуваємо поріг води до -0.2 (Тепер суші буде 65%!)
			if c_raw < -0.2: 
				py = lerp(-40.0, 2.8, (c_raw + 1.0) / 0.8)
			else:
				# ПЛАВНИЙ ПЕРЕХІД КАРТИ
				var inland_blend = smoothstep(-0.2, 0.1, c_raw)
				var base_h = (h_raw + 1.0) / 2.0
				var terrain_h = pow(base_h, 1.5) * 35.0
				var mount_h = smoothstep(0.1, 0.8, m_raw) * inland_blend * 200.0
				py = 2.8 + (terrain_h + mount_h) * inland_blend
			
			var col = Color(0.1, 0.4, 0.1) 
			if py < 2.8: col = Color(0.1, 0.3, 0.6) 
			elif py > 130.0: col = Color.WHITE 
			elif py > 45.0: col = Color.GRAY 
			elif moist < -0.15: col = Color(0.8, 0.7, 0.3) 
			
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
	
	chunk.start_generation(chunk_pos, CHUNK_SIZE, 16, terrain_material, 
		global_noise, moisture_noise, mountain_noise, continent_noise, procedural_grass_mesh, player)

func _on_chunk_ready(chunk: Node3D):
	if is_first_spawn and chunk.chunk_pos == current_player_chunk:
		is_first_spawn = false
		if player:
			player.global_position.y = 250.0 
			player.process_mode = Node.PROCESS_MODE_INHERIT

func _build_grass_mesh() -> Mesh:
	var st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	
	var w = 0.5 # Ширина площини
	var h = 1.0 # Висота площини
	
	# Функція, яка малює одну площину під заданим кутом
	var add_quad = func(rot_y: float):
		var t = Transform3D().rotated(Vector3.UP, rot_y)
		var v1 = t * Vector3(-w, 0, 0); var uv1 = Vector2(0, 1)
		var v2 = t * Vector3(w, 0, 0);  var uv2 = Vector2(1, 1)
		var v3 = t * Vector3(w, h, 0);  var uv3 = Vector2(1, 0)
		var v4 = t * Vector3(-w, h, 0); var uv4 = Vector2(0, 0)

		st.set_uv(uv1); st.add_vertex(v1)
		st.set_uv(uv2); st.add_vertex(v2)
		st.set_uv(uv3); st.add_vertex(v3)
		st.set_uv(uv1); st.add_vertex(v1)
		st.set_uv(uv3); st.add_vertex(v3)
		st.set_uv(uv4); st.add_vertex(v4)
	
	# Додаємо 3 площини з кроком у 60 градусів
	add_quad.call(0.0)
	add_quad.call(PI / 3.0)       # 60 градусів
	add_quad.call(PI * 2.0 / 3.0) # 120 градусів

	st.generate_normals()
	return st.commit()
