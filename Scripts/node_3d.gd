extends Node3D

const CHUNK_SIZE = 50.0   
const RENDER_DISTANCE = 7 

@onready var player = get_tree().get_first_node_in_group("player")
@export var terrain_material: Material

var active_chunks = {}
var chunk_spawn_queue: Array[Vector2] = []
var current_player_chunk = Vector2(1000000, 1000000)
var is_first_spawn = true 

var procedural_grass_mesh: Mesh

func _ready():
	procedural_grass_mesh = _build_grass_mesh()
	
	if player:
		player.process_mode = Node.PROCESS_MODE_DISABLED 
		player.global_position = _find_valid_spawn_point()
		current_player_chunk = Vector2(
			floor(player.global_position.x / CHUNK_SIZE), 
			floor(player.global_position.z / CHUNK_SIZE)
		)
		update_chunks(current_player_chunk)

func _find_valid_spawn_point() -> Vector3:
	if Global.custom_spawn_x >= 0.0:
		return Vector3(Global.custom_spawn_x, 400.0, Global.custom_spawn_z)
		
	var rng = RandomNumberGenerator.new()
	rng.seed = Global.world_seed 
	
	for i in range(150):
		var rx = rng.randf_range(1000.0, Global.WORLD_SIZE - 1000.0)
		var rz = rng.randf_range(1000.0, Global.WORLD_SIZE - 1000.0)
		
		var b_data = Global.get_biome_data(rx, rz)
		if b_data["biome"] == "beach" or b_data["biome"] == "grassland":
			return Vector3(rx, 400.0, rz)
			
	return Vector3(Global.WORLD_SIZE / 2.0, 400.0, Global.WORLD_SIZE / 2.0) 

func _process(_delta):
	if player:
		var px = floor(player.global_position.x / CHUNK_SIZE)
		var pz = floor(player.global_position.z / CHUNK_SIZE)
		var new_chunk = Vector2(px, pz)
		if new_chunk != current_player_chunk:
			current_player_chunk = new_chunk
			update_chunks(current_player_chunk)

	for i in range(2):
		if chunk_spawn_queue.size() > 0:
			var chunk_to_spawn = chunk_spawn_queue.pop_front()
			spawn_chunk(chunk_to_spawn)

func update_chunks(center_chunk: Vector2):
	var desired_chunks = []
	for x in range(-RENDER_DISTANCE, RENDER_DISTANCE + 1):
		for z in range(-RENDER_DISTANCE, RENDER_DISTANCE + 1):
			if Vector2(x, z).length() <= RENDER_DISTANCE: 
				desired_chunks.append(center_chunk + Vector2(x, z))
				
	var chunks_to_remove = []
	for chunk_pos in active_chunks.keys():
		if not desired_chunks.has(chunk_pos): 
			chunks_to_remove.append(chunk_pos)
			
	for chunk_pos in chunks_to_remove:
		active_chunks[chunk_pos].queue_free()
		active_chunks.erase(chunk_pos)
		
	for chunk_pos in desired_chunks:
		if not active_chunks.has(chunk_pos) and not chunk_spawn_queue.has(chunk_pos): 
			chunk_spawn_queue.append(chunk_pos)
			
	var sort_by_distance = func(a: Vector2, b: Vector2) -> bool:
		return a.distance_squared_to(center_chunk) < b.distance_squared_to(center_chunk)
		
	chunk_spawn_queue.sort_custom(sort_by_distance)

func spawn_chunk(chunk_pos: Vector2):
	var chunk = Node3D.new()
	chunk.set_script(preload("res://world_chunk.gd"))
	chunk.name = "Chunk_%d_%d" % [chunk_pos.x, chunk_pos.y]
	chunk.global_position = Vector3(chunk_pos.x * CHUNK_SIZE, 0, chunk_pos.y * CHUNK_SIZE)
	chunk.chunk_ready.connect(_on_chunk_ready) 
	add_child(chunk)
	active_chunks[chunk_pos] = chunk
	chunk.start_generation(chunk_pos, CHUNK_SIZE, 16, terrain_material, procedural_grass_mesh, player)

# Scripts/node_3d.gd

func _on_chunk_ready(chunk: Node3D):
	if is_first_spawn and chunk.chunk_pos == current_player_chunk:
		is_first_spawn = false
		if player:
			# Примушуємо чанк створити фізику ПРЯМО ЗАРАЗ
			chunk._create_collision_now()
			
			var spawn_y = chunk._get_h(player.global_position.x, player.global_position.z)
			
			# Підкидаємо гравця на 15 метрів вгору. Він впаде на тверду землю.
			player.global_position.y = spawn_y + 15.0 
			
			# Даємо рушію 2 фізичні кадри, щоб активувати колізію
			await get_tree().physics_frame
			await get_tree().physics_frame
			
			player.process_mode = Node.PROCESS_MODE_INHERIT

func _build_grass_mesh() -> Mesh:
	var st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var r = 0.45; var h = 1.0  
	var p1 = Vector3(0, 0, r); var p2 = Vector3(r * 0.866, 0, -r * 0.5); var p3 = Vector3(-r * 0.866, 0, -r * 0.5) 
	var add_flipped_quad = func(a: Vector3, b: Vector3):
		var v1 = a; var uv1 = Vector2(0, 1)
		var v2 = b; var uv2 = Vector2(1, 1)
		var v3 = b + Vector3(0, h, 0); var uv3 = Vector2(1, 0)
		var v4 = a + Vector3(0, h, 0); var uv4 = Vector2(0, 0)
		st.set_uv(uv1); st.add_vertex(v1)
		st.set_uv(uv3); st.add_vertex(v3)
		st.set_uv(uv2); st.add_vertex(v2)
		st.set_uv(uv1); st.add_vertex(v1)
		st.set_uv(uv4); st.add_vertex(v4)
		st.set_uv(uv3); st.add_vertex(v3)
	add_flipped_quad.call(p1, p2)
	add_flipped_quad.call(p2, p3)
	add_flipped_quad.call(p3, p1)
	st.generate_normals()
	return st.commit()
