extends Node3D

const CHUNK_SIZE = 50.0
const RENDER_DISTANCE = 14 

@onready var player = get_tree().get_first_node_in_group("player")
@export var terrain_material: Material

var active_chunks = {}
var chunk_spawn_queue: Array[Vector2] = []
var lod_update_queue: Array[Node3D] = [] 

var current_player_chunk = Vector2(1000000, 1000000)
var is_world_loading = true 
var target_spawn_pos = Vector3.ZERO
var procedural_grass_mesh: Mesh

var chunks_building: int = 0
const MAX_CONCURRENT_CHUNKS = 8 # Збільшено, щоб чанки не змушували чекати
var frame_counter = 0

func _ready():
	procedural_grass_mesh = _build_grass_mesh()
	if player:
		player.set_physics_process(false)
		target_spawn_pos = _find_valid_spawn_point()
		player.global_position = target_spawn_pos 
		current_player_chunk = Vector2(floor(target_spawn_pos.x / CHUNK_SIZE), floor(target_spawn_pos.z / CHUNK_SIZE))
		update_chunks()

func _find_valid_spawn_point() -> Vector3:
	var rng = RandomNumberGenerator.new()
	rng.seed = Global.world_seed 
	var start_pos = Vector2(Global.WORLD_SIZE/2, Global.WORLD_SIZE/2)
	if Global.continents.size() > 0: start_pos = Global.continents[0].pos
	for i in range(200):
		var rx = start_pos.x + rng.randf_range(-2000, 2000)
		var rz = start_pos.y + rng.randf_range(-2000, 2000)
		if Global.get_raw_elevation(rx, rz) > 0.5: 
			return Vector3(rx, 800.0, rz)
	return Vector3(start_pos.x, 800.0, start_pos.y)

func _process(_delta):
	if not is_world_loading and player:
		var p_pos = Vector2(player.global_position.x / CHUNK_SIZE, player.global_position.z / CHUNK_SIZE)
		var new_chunk = p_pos.floor()
		if new_chunk != current_player_chunk:
			current_player_chunk = new_chunk
			update_chunks()
			
		# ВИПРАВЛЕННЯ: Постійна перевірка LOD, навіть коли гравець стоїть
		_check_lods_continuously()

	if chunks_building < MAX_CONCURRENT_CHUNKS:
		if chunk_spawn_queue.size() > 0:
			spawn_chunk(chunk_spawn_queue.pop_front())
		elif lod_update_queue.size() > 0:
			var c = lod_update_queue.pop_front()
			if is_instance_valid(c) and c.is_ready:
				var dist = c.chunk_pos.distance_to(current_player_chunk)
				var lod = get_lod_for_distance(dist)
				if c.resolution != lod["res"]:
					chunks_building += 1
					c.set_lod(lod["res"], lod["grass"], procedural_grass_mesh)

func _check_lods_continuously():
	frame_counter += 1
	if frame_counter % 15 != 0: return # Перевіряємо не кожен кадр, щоб економити CPU
	for p in active_chunks.keys():
		var chunk = active_chunks[p]
		if not is_instance_valid(chunk) or not chunk.is_ready: continue
		var dist = p.distance_to(current_player_chunk)
		var lod = get_lod_for_distance(dist)
		if chunk.resolution != lod["res"] and not lod_update_queue.has(chunk):
			lod_update_queue.append(chunk)
	lod_update_queue.sort_custom(func(a, b): return a.chunk_pos.distance_to(current_player_chunk) < b.chunk_pos.distance_to(current_player_chunk))

func get_lod_for_distance(dist: float) -> Dictionary:
	# Якість 25 зробить землю дуже плавною і детальною (крок полігону 2 метри)
	if dist <= 4.0: return {"res": 25, "grass": true}  
	if dist <= 8.0: return {"res": 10, "grass": false} 
	return {"res": 5, "grass": false}                  

func update_chunks():
	if not player: return
	var center_chunk = current_player_chunk
	var desired = []
	for x in range(-RENDER_DISTANCE, RENDER_DISTANCE + 1):
		for z in range(-RENDER_DISTANCE, RENDER_DISTANCE + 1):
			var chunk_p = center_chunk + Vector2(x, z)
			if chunk_p.distance_to(center_chunk) <= RENDER_DISTANCE:
				desired.append(chunk_p)
	
	for p in active_chunks.keys():
		if not desired.has(p):
			var chunk = active_chunks[p]
			if not chunk.is_ready: chunks_building -= 1
			if chunk.has_method("cancel_and_free"): chunk.cancel_and_free()
			else: chunk.queue_free()
			active_chunks.erase(p)
			lod_update_queue.erase(chunk)
			
	for p in desired:
		if not active_chunks.has(p) and not chunk_spawn_queue.has(p): 
			chunk_spawn_queue.append(p)
	
	chunk_spawn_queue.sort_custom(func(a, b): return a.distance_to(center_chunk) < b.distance_to(center_chunk))

func spawn_chunk(p: Vector2):
	chunks_building += 1
	var c = Node3D.new()
	c.set_script(preload("res://world_chunk.gd"))
	c.position = Vector3(p.x * CHUNK_SIZE, 0, p.y * CHUNK_SIZE)
	c.chunk_ready.connect(_on_chunk_ready)
	add_child(c)
	active_chunks[p] = c
	var dist = p.distance_to(current_player_chunk)
	var lod = get_lod_for_distance(dist)
	var target_grass = procedural_grass_mesh if lod["grass"] else null
	c.start_generation(p, CHUNK_SIZE, lod["res"], terrain_material, target_grass, player)

func _on_chunk_ready(chunk: Node3D):
	if chunks_building > 0: chunks_building -= 1
	if is_world_loading:
		if chunk.chunk_pos.distance_to(current_player_chunk) < 0.1:
			_drop_player()

func _drop_player():
	is_world_loading = false
	var sy = Global._get_final_height(player.global_position.x, player.global_position.z)
	player.global_position.y = sy + 3.0
	if player.has_method("set_velocity"): player.set_velocity(Vector3.ZERO)
	player.set_physics_process(true)
	player.visible = true

func teleport_player(world_pos_2d: Vector2):
	if not player: return
	is_world_loading = true
	player.set_physics_process(false)
	target_spawn_pos = Vector3(world_pos_2d.x, 800.0, world_pos_2d.y)
	player.global_position = target_spawn_pos
	current_player_chunk = (Vector2(target_spawn_pos.x, target_spawn_pos.z) / CHUNK_SIZE).floor()
	chunk_spawn_queue.clear()
	lod_update_queue.clear()
	update_chunks()
	if active_chunks.has(current_player_chunk) and active_chunks[current_player_chunk].is_ready:
		_drop_player()

func _build_grass_mesh() -> Mesh:
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
