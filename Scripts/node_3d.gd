extends Node3D

const CHUNK_SIZE = 50.0
const RENDER_DISTANCE = 24 # Тепер ти бачитимеш світ на 1200 метрів!
const MAX_CONCURRENT_CHUNKS = 4 # Безпечно для потоків

@onready var player = get_tree().get_first_node_in_group("player")
@export var terrain_material: Material
var debug_label: Label
var active_chunks = {}
var chunk_spawn_queue: Array[Vector2] = []
var lod_update_queue: Array[Node3D] = [] 

var current_player_chunk = Vector2(1000000, 1000000)
var is_world_loading = true 
var procedural_grass_mesh: Mesh

var chunks_building: int = 0
var frame_counter = 0

func _ready():
	_ensure_safe_spawn()
	var canvas = CanvasLayer.new()
	debug_label = Label.new()
	debug_label.position = Vector2(20, 20)
	debug_label.add_theme_font_size_override("font_size", 24)
	debug_label.add_theme_color_override("font_outline_color", Color.BLACK)
	debug_label.add_theme_constant_override("outline_size", 5)
	canvas.add_child(debug_label)
	add_child(canvas)

	procedural_grass_mesh = _build_grass_mesh()
	if player:
		player.set_physics_process(false)
		_find_valid_spawn_point() 
		player.global_position = Vector3(0, 800.0, 0) 
		current_player_chunk = Vector2.ZERO
		update_chunks()

func _ensure_safe_spawn():
	var max_attempts = 100
	
	# Перевіряємо висоту в точці спавну гравця. 
	# < 0.38 — це вода і пляжі. Ми хочемо тверду землю.
	while Global.get_raw_elevation(Global.world_offset.x, Global.world_offset.y) < 0.38 and max_attempts > 0:
		# Якщо ми у воді, "прокручуємо" світ на 500 метрів убік
		Global.world_offset.x += 500.0 
		Global.world_offset.y += 500.0
		max_attempts -= 1

func _find_valid_spawn_point():
	if Global.custom_spawn_x != -999999.0:
		Global.world_offset = Vector2(Global.custom_spawn_x, Global.custom_spawn_z)
		return
		
	var rng = RandomNumberGenerator.new()
	rng.seed = Global.world_seed 
	var start_pos = Vector2.ZERO
	if Global.continents.size() > 0: start_pos = Global.continents[0].pos
	for i in range(200):
		var rx = start_pos.x + rng.randf_range(-1500, 1500)
		var rz = start_pos.y + rng.randf_range(-1500, 1500)
		if Global.get_raw_elevation(rx, rz) > 0.5: 
			Global.world_offset = Vector2(rx, rz)
			return
	Global.world_offset = start_pos

func _process(_delta):
	# Оновлюємо показники на екрані
	if player:
		debug_label.text = "FPS: %d\nВисота: %.1f m" % [Engine.get_frames_per_second(), player.global_position.y]

	var active_builds = 0
	for c in active_chunks.values():
		if not c.is_ready and not c.pending_kill:
			active_builds += 1
	chunks_building = active_builds

	if not is_world_loading and player:
		var new_chunk = (Vector2(player.global_position.x, player.global_position.z) / CHUNK_SIZE).round()
		if new_chunk != current_player_chunk:
			current_player_chunk = new_chunk
			_check_origin_shift() 
			update_chunks()
		_check_lods_continuously()

	if chunks_building < MAX_CONCURRENT_CHUNKS:
		# Отримуємо дистанції до найперших завдань у чергах
		var dist_spawn = 9999.0
		var dist_lod = 9999.0
		if chunk_spawn_queue.size() > 0: dist_spawn = chunk_spawn_queue[0].distance_to(current_player_chunk)
		if lod_update_queue.size() > 0: dist_lod = lod_update_queue[0].chunk_pos.distance_to(current_player_chunk)
		
		# ІНТЕЛЕКТУАЛЬНА ЧЕРГА: Завжди обираємо те завдання, яке фізично ближче до гравця!
		if dist_spawn < dist_lod and chunk_spawn_queue.size() > 0:
			spawn_chunk(chunk_spawn_queue.pop_front())
		elif lod_update_queue.size() > 0:
			var c = lod_update_queue.pop_front()
			if is_instance_valid(c) and c.is_ready and not c.pending_kill:
				var lod = get_lod_for_distance(c.chunk_pos.distance_to(current_player_chunk))
				if c.resolution != lod["res"]:
					c.set_lod(lod["res"], lod["grass"], procedural_grass_mesh, lod["col"])

func _check_origin_shift():
	# Зміщуємо світ тільки якщо відійшли аж на 3000 метрів (60 чанків) від центру
	if abs(current_player_chunk.x) > 60 or abs(current_player_chunk.y) > 60:
		var chunk_offset = current_player_chunk
		var shift_2d = chunk_offset * CHUNK_SIZE
		var shift_3d = Vector3(shift_2d.x, 0, shift_2d.y)
		
		Global.world_offset += shift_2d
		player.global_position -= shift_3d
		
		var new_active = {}
		for p in active_chunks.keys():
			var c = active_chunks[p]
			var new_p = p - chunk_offset
			c.chunk_pos = new_p
			c.position -= shift_3d
			new_active[new_p] = c
		active_chunks = new_active
		
		var new_spawn = []
		for p in chunk_spawn_queue: new_spawn.append(p - chunk_offset)
		chunk_spawn_queue = new_spawn
		
		current_player_chunk = Vector2.ZERO

func _check_lods_continuously():
	frame_counter += 1
	if frame_counter % 10 != 0: return 
	for p in active_chunks.keys():
		var chunk = active_chunks[p]
		if not is_instance_valid(chunk) or not chunk.is_ready or chunk.pending_kill: continue
		var dist = p.distance_to(current_player_chunk)
		var lod = get_lod_for_distance(dist)
		if chunk.resolution != lod["res"] and not lod_update_queue.has(chunk):
			lod_update_queue.append(chunk)
	lod_update_queue.sort_custom(func(a, b): return a.chunk_pos.distance_to(current_player_chunk) < b.chunk_pos.distance_to(current_player_chunk))

func get_lod_for_distance(dist: float) -> Dictionary:
	# 64 вершин цілком достатньо, всю магію об'єму тепер робить шейдер!
	if dist <= 1.5: return {"res": 64, "grass": true, "col": true} 
	
	if dist <= 3.5: return {"res": 32, "grass": true, "col": true}   
	if dist <= 6.0: return {"res": 16, "grass": true, "col": true}   
	if dist <= 12.0: return {"res": 8, "grass": false, "col": false}
	return {"res": 4, "grass": false, "col": false}

func update_chunks():
	if not player: return
	var desired = []
	for x in range(-RENDER_DISTANCE, RENDER_DISTANCE + 1):
		for z in range(-RENDER_DISTANCE, RENDER_DISTANCE + 1):
			var chunk_p = current_player_chunk + Vector2(x, z)
			if chunk_p.distance_to(current_player_chunk) <= RENDER_DISTANCE: desired.append(chunk_p)
	
	for p in active_chunks.keys():
		if not desired.has(p):
			var chunk = active_chunks[p]
			if not chunk.is_ready and not chunk.pending_kill: chunks_building -= 1
			if chunk.has_method("cancel_and_free"): chunk.cancel_and_free()
			else: chunk.queue_free()
			active_chunks.erase(p)
			lod_update_queue.erase(chunk)
			
	for p in desired:
		if not active_chunks.has(p) and not chunk_spawn_queue.has(p): chunk_spawn_queue.append(p)
	chunk_spawn_queue.sort_custom(func(a, b): return a.distance_to(current_player_chunk) < b.distance_to(current_player_chunk))

func spawn_chunk(p: Vector2):
	chunks_building += 1
	var c = Node3D.new()
	c.set_script(preload("res://Scripts/world_chunk.gd"))
	c.position = Vector3(p.x * CHUNK_SIZE, 0, p.y * CHUNK_SIZE)
	c.chunk_ready.connect(_on_chunk_ready)
	add_child(c)
	active_chunks[p] = c
	var lod = get_lod_for_distance(p.distance_to(current_player_chunk))
	var target_grass = procedural_grass_mesh if lod["grass"] else null
	# Передаємо зміщення світу в генератор
	c.start_generation(p, CHUNK_SIZE, lod["res"], terrain_material, target_grass, player, Global.world_offset, lod["col"])

func _on_chunk_ready(chunk: Node3D):
	if chunks_building > 0: chunks_building -= 1
	if is_world_loading and chunk.chunk_pos.distance_to(current_player_chunk) < 0.1:
		_drop_player()

func _drop_player():
	var sy = Global._get_final_height(Global.world_offset.x, Global.world_offset.y)
	player.global_position = Vector3(0, sy + 5.0, 0)
	player.velocity = Vector3.ZERO
	
	# Jolt Physics потребує трохи більше часу на збірку сітки колізій.
	# Чекаємо 10 кадрів, щоб земля точно стала твердою.
	for i in range(10):
		await get_tree().physics_frame
	
	is_world_loading = false
	player.set_physics_process(true)
	player.visible = true

func teleport_player(world_pos_2d: Vector2):
	if not player: return
	is_world_loading = true
	player.set_physics_process(false)
	
	# Телепорт тепер просто змінює зміщення світу!
	Global.world_offset = world_pos_2d
	player.global_position = Vector3(0, 800.0, 0)
	current_player_chunk = Vector2.ZERO
	
	chunk_spawn_queue.clear()
	lod_update_queue.clear()
	for c in active_chunks.values():
		if c.has_method("cancel_and_free"): c.cancel_and_free()
		else: c.queue_free()
	active_chunks.clear()
	chunks_building = 0
	
	update_chunks()

func _build_grass_mesh() -> Mesh:
	# Твій старий код залишається незмінним
	var st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var r = 0.45; var h = 1.0  
	var p1 = Vector3(0, 0, r); var p2 = Vector3(r*0.866, 0, -r*0.5); var p3 = Vector3(-r*0.866, 0, -r*0.5) 
	var add_f_q = func(a, b):
		var uv1 = Vector2(0, 1); var uv2 = Vector2(1, 1)
		var uv3 = Vector2(1, 0); var uv4 = Vector2(0, 0)
		var v3 = b + Vector3(0, h, 0); var v4 = a + Vector3(0, h, 0)
		st.set_uv(uv1); st.add_vertex(a); st.set_uv(uv3); st.add_vertex(v3); st.set_uv(uv2); st.add_vertex(b)
		st.set_uv(uv1); st.add_vertex(a); st.set_uv(uv4); st.add_vertex(v4); st.set_uv(uv3); st.add_vertex(v3)
	add_f_q.call(p1, p2); add_f_q.call(p2, p3); add_f_q.call(p3, p1)
	st.generate_normals()
	return st.commit()
