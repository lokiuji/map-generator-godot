extends Node3D

const CHUNK_SIZE = 50.0   # ПОВЕРНУТО ДО 50
const RENDER_DISTANCE = 7 

@onready var player = get_tree().get_first_node_in_group("player")
@export var terrain_material: Material

var active_chunks = {}
var chunk_spawn_queue: Array[Vector2] = []
var current_player_chunk = Vector2(1000000, 1000000)

var is_world_loading = true 
var target_spawn_pos = Vector3.ZERO
var procedural_grass_mesh: Mesh

func _ready():
	procedural_grass_mesh = _build_grass_mesh()
	
	if player:
		# 1. ПОВНІСТЮ ВИМИКАЄМО ГРАВЦЯ НА СТАРТІ
		player.process_mode = Node.PROCESS_MODE_DISABLED
		player.visible = false
		
		# 2. Визначаємо, де він має бути
		target_spawn_pos = _find_valid_spawn_point()
		current_player_chunk = Vector2(floor(target_spawn_pos.x / CHUNK_SIZE), floor(target_spawn_pos.z / CHUNK_SIZE))
		
		# 3. Запускаємо генерацію світу навколо цієї точки
		update_chunks(current_player_chunk)

func _find_valid_spawn_point() -> Vector3:
	if Global.custom_spawn_x >= 0.0: return Vector3(Global.custom_spawn_x, 800.0, Global.custom_spawn_z)
	var rng = RandomNumberGenerator.new()
	rng.seed = Global.world_seed 
	for i in range(100):
		var rx = rng.randf_range(1000.0, Global.WORLD_SIZE - 1000.0)
		var rz = rng.randf_range(1000.0, Global.WORLD_SIZE - 1000.0)
		if Global.get_biome_data(rx, rz)["elevation"] > 0.45: return Vector3(rx, 800.0, rz)
	return Vector3(Global.WORLD_SIZE/2, 800, Global.WORLD_SIZE/2)

func _process(_delta):
	# Якщо світ завантажився, оновлюємо чанки відносно позиції гравця
	if not is_world_loading and player:
		var new_chunk = Vector2(floor(player.global_position.x / CHUNK_SIZE), floor(player.global_position.z / CHUNK_SIZE))
		if new_chunk != current_player_chunk:
			current_player_chunk = new_chunk
			update_chunks(current_player_chunk)

	# СУВОРЕ ОБМЕЖЕННЯ: генеруємо графіку лише для 1 чанку за кадр
	if chunk_spawn_queue.size() > 0: 
		spawn_chunk(chunk_spawn_queue.pop_front())

func update_chunks(center: Vector2):
	var desired = []
	for x in range(-RENDER_DISTANCE, RENDER_DISTANCE+1):
		for z in range(-RENDER_DISTANCE, RENDER_DISTANCE+1):
			if Vector2(x,z).length() <= RENDER_DISTANCE: desired.append(center + Vector2(x,z))
	for p in active_chunks.keys():
		if not desired.has(p):
			active_chunks[p].queue_free()
			active_chunks.erase(p)
	for p in desired:
		if not active_chunks.has(p) and not chunk_spawn_queue.has(p): chunk_spawn_queue.append(p)
	chunk_spawn_queue.sort_custom(func(a,b): return a.distance_squared_to(center) < b.distance_squared_to(center))

func spawn_chunk(p: Vector2):
	var c = Node3D.new()
	c.set_script(preload("res://world_chunk.gd"))
	c.global_position = Vector3(p.x * CHUNK_SIZE, 0, p.y * CHUNK_SIZE)
	c.chunk_ready.connect(_on_chunk_ready)
	add_child(c)
	active_chunks[p] = c
	c.start_generation(p, CHUNK_SIZE, 16, terrain_material, procedural_grass_mesh, player)

func _on_chunk_ready(chunk: Node3D):
	if is_world_loading and chunk.chunk_pos == current_player_chunk:
		is_world_loading = false
		if player:
			var sy = chunk._get_h(target_spawn_pos.x, target_spawn_pos.z)
			
			# ОЧІКУВАННЯ ФІЗИКИ: даємо рушію 2 кадри на побудову колізії
			await get_tree().physics_frame
			await get_tree().physics_frame
			
			# Ставимо гравця трохи вище землі (наприклад, +3.0) щоб він впевнено приземлився
			player.global_position = Vector3(target_spawn_pos.x, sy + 3.0, target_spawn_pos.z)
			if player.has_method("set_velocity"): player.set_velocity(Vector3.ZERO)
			
			player.visible = true
			player.process_mode = Node.PROCESS_MODE_INHERIT

func _build_grass_mesh() -> Mesh:
	var st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var r = 0.45; var h = 1.0  
	var p1 = Vector3(0, 0, r); var p2 = Vector3(r * 0.866, 0, -r * 0.5); var p3 = Vector3(-r * 0.866, 0, -r * 0.5) 
	var add_flipped_quad = func(a: Vector3, b: Vector3):
		var v1 = a; var uv1 = Vector2(0, 1); var v2 = b; var uv2 = Vector2(1, 1)
		var v3 = b + Vector3(0, h, 0); var uv3 = Vector2(1, 0); var v4 = a + Vector3(0, h, 0); var uv4 = Vector2(0, 0)
		st.set_uv(uv1); st.add_vertex(v1); st.set_uv(uv3); st.add_vertex(v3); st.set_uv(uv2); st.add_vertex(v2)
		st.set_uv(uv1); st.add_vertex(v1); st.set_uv(uv4); st.add_vertex(v4); st.set_uv(uv3); st.add_vertex(v3)
	add_flipped_quad.call(p1, p2); add_flipped_quad.call(p2, p3); add_flipped_quad.call(p3, p1)
	st.generate_normals()
	return st.commit()
