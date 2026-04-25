extends Node3D

const CHUNK_SIZE = 50.0
const RENDER_DISTANCE = 7 

@onready var player = get_tree().get_first_node_in_group("player")
@export var terrain_material: Material

var active_chunks = {}
var chunk_spawn_queue: Array[Vector2] = []
var current_player_chunk = Vector2(1000000, 1000000)

var is_world_loading = true 
var target_spawn_pos = Vector3.ZERO
var procedural_grass_mesh: Mesh

var chunks_building: int = 0
const MAX_CONCURRENT_CHUNKS = 3

func _ready():
	procedural_grass_mesh = _build_grass_mesh()
	if player:
		player.set_physics_process(false)
		target_spawn_pos = _find_valid_spawn_point()
		current_player_chunk = Vector2(floor(target_spawn_pos.x / CHUNK_SIZE), floor(target_spawn_pos.z / CHUNK_SIZE))
		player.global_position = target_spawn_pos 
		update_chunks(current_player_chunk)

func _find_valid_spawn_point() -> Vector3:
	var rng = RandomNumberGenerator.new()
	rng.seed = Global.world_seed 
	for i in range(100):
		var rx = rng.randf_range(1000.0, Global.WORLD_SIZE - 1000.0)
		var rz = rng.randf_range(1000.0, Global.WORLD_SIZE - 1000.0)
		if Global.get_raw_elevation(rx, rz) > 0.45: 
			return Vector3(rx, 800.0, rz)
	return Vector3(Global.WORLD_SIZE/2, 800, Global.WORLD_SIZE/2)

func _process(_delta):
	if not is_world_loading and player:
		var new_chunk = Vector2(floor(player.global_position.x / CHUNK_SIZE), floor(player.global_position.z / CHUNK_SIZE))
		if new_chunk != current_player_chunk:
			current_player_chunk = new_chunk
			update_chunks(current_player_chunk)

	if chunk_spawn_queue.size() > 0 and chunks_building < MAX_CONCURRENT_CHUNKS:
		spawn_chunk(chunk_spawn_queue.pop_front())

func update_chunks(center: Vector2):
	var desired = []
	for x in range(-RENDER_DISTANCE, RENDER_DISTANCE+1):
		for z in range(-RENDER_DISTANCE, RENDER_DISTANCE+1):
			if Vector2(x,z).length() <= RENDER_DISTANCE: desired.append(center + Vector2(x,z))
	
	for p in active_chunks.keys():
		if not desired.has(p):
			var chunk = active_chunks[p]
			if not chunk.is_ready: chunks_building -= 1
			chunk.cancel_and_free()
			active_chunks.erase(p)
			
	for p in desired:
		if not active_chunks.has(p) and not chunk_spawn_queue.has(p): 
			chunk_spawn_queue.append(p)
	chunk_spawn_queue.sort_custom(func(a,b): return a.distance_squared_to(center) < b.distance_squared_to(center))

func spawn_chunk(p: Vector2):
	chunks_building += 1
	var c = Node3D.new()
	c.set_script(preload("res://world_chunk.gd"))
	c.position = Vector3(p.x * CHUNK_SIZE, 0, p.y * CHUNK_SIZE)
	c.chunk_ready.connect(_on_chunk_ready)
	add_child(c)
	active_chunks[p] = c
	c.start_generation(p, CHUNK_SIZE, 16, terrain_material, procedural_grass_mesh, player)

func _on_chunk_ready(chunk: Node3D):
	chunks_building -= 1
	if is_world_loading and chunk.chunk_pos == current_player_chunk:
		is_world_loading = false
		if player:
			var sy = chunk._get_h(target_spawn_pos.x, target_spawn_pos.z)
			await get_tree().physics_frame
			player.global_position = Vector3(target_spawn_pos.x, sy + 3.0, target_spawn_pos.z)
			player.set_physics_process(true)
			player.visible = true

func teleport_player(world_pos_2d: Vector2):
	if not player: return
	is_world_loading = true
	player.set_physics_process(false)
	target_spawn_pos = Vector3(world_pos_2d.x, 800.0, world_pos_2d.y)
	player.global_position = target_spawn_pos
	current_player_chunk = Vector2(floor(target_spawn_pos.x / CHUNK_SIZE), floor(target_spawn_pos.z / CHUNK_SIZE))
	chunk_spawn_queue.clear()
	update_chunks(current_player_chunk)

func _build_grass_mesh() -> Mesh:
	var st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var r = 0.45; var h = 1.0  
	var p1 = Vector3(0, 0, r); var p2 = Vector3(r * 0.866, 0, -r * 0.5); var p3 = Vector3(-r * 0.866, 0, -r * 0.5) 
	
	var add_flipped_quad = func(a: Vector3, b: Vector3):
		var uv1 = Vector2(0, 1); var uv2 = Vector2(1, 1)
		var uv3 = Vector2(1, 0); var uv4 = Vector2(0, 0)
		var v3 = b + Vector3(0, h, 0); var v4 = a + Vector3(0, h, 0)
		
		# Правильне додавання точок разом з UV-координатами
		st.set_uv(uv1); st.add_vertex(a); st.set_uv(uv3); st.add_vertex(v3); st.set_uv(uv2); st.add_vertex(b)
		st.set_uv(uv1); st.add_vertex(a); st.set_uv(uv4); st.add_vertex(v4); st.set_uv(uv3); st.add_vertex(v3)
		
	add_flipped_quad.call(p1, p2)
	add_flipped_quad.call(p2, p3)
	add_flipped_quad.call(p3, p1)
	st.generate_normals()
	return st.commit()
