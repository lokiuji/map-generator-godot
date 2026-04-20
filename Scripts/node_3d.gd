extends Node3D

const CHUNK_SIZE = 120.0
const RENDER_DISTANCE = 3

@onready var player = get_tree().get_first_node_in_group("player")
@export var terrain_material: Material

var active_chunks = {}
var current_player_chunk = Vector2(1000000, 1000000)
var is_first_spawn = true 

var global_noise: FastNoiseLite
var moisture_noise: FastNoiseLite
var mountain_noise: FastNoiseLite
var continent_noise: FastNoiseLite 

var procedural_grass_mesh: Mesh

var chunk_database = {}
# Приклад того, як це працюватиме:
# func save_building(chunk_pos: Vector2, building_data: Dictionary):
#     # Перетворюємо візуальну позицію на логічну (від 0 до 50)
#     var logic_x = wrapi(int(chunk_pos.x), 0, 50)
#     var logic_y = wrapi(int(chunk_pos.y), 0, 50)
#     var logic_pos = Vector2(logic_x, logic_y)
#     
#     if not chunk_database.has(logic_pos):
#         chunk_database[logic_pos] = []
#     chunk_database[logic_pos].append(building_data)

func _ready():
	_setup_noises()
	
	procedural_grass_mesh = _build_grass_mesh()
	
	if player:
		player.process_mode = Node.PROCESS_MODE_DISABLED 
		
		# === 2. ФІКС СПАВНУ: КИДАЄМО ГРАВЦЯ В ЦЕНТР СВІТУ ===
		# Центр світу 6000x6000 - це точка (3000, 3000). 
		# Висоту ставимо 400, щоб точно впасти на гору, а не під неї.
		player.global_position = _find_valid_spawn_point()
		current_player_chunk = Vector2(floor(player.global_position.x / CHUNK_SIZE), floor(player.global_position.z / CHUNK_SIZE))
		update_chunks(current_player_chunk)
	else:
		push_error("ГРАВЦЯ НЕ ЗНАЙДЕНО! Перевір, чи є він у групі 'player'")
		
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
	
	var r = 0.45 
	var h = 1.0  
	
	var p1 = Vector3(0, 0, r)
	var p2 = Vector3(r * 0.866, 0, -r * 0.5) 
	var p3 = Vector3(-r * 0.866, 0, -r * 0.5) 
	
	# ФУНКЦІЯ З ФЛІПОМ (змінено порядок вершин v2 та v3 для кожної грані)
	var add_flipped_quad = func(a: Vector3, b: Vector3):
		var v1 = a;               var uv1 = Vector2(0, 1)
		var v2 = b;               var uv2 = Vector2(1, 1)
		var v3 = b + Vector3(0,h,0); var uv3 = Vector2(1, 0)
		var v4 = a + Vector3(0,h,0); var uv4 = Vector2(0, 0)

		# Порядок змінено на v1-v3-v2 та v1-v4-v3, щоб "вивернути" площину
		st.set_uv(uv1); st.add_vertex(v1)
		st.set_uv(uv3); st.add_vertex(v3)
		st.set_uv(uv2); st.add_vertex(v2)
		
		st.set_uv(uv1); st.add_vertex(v1)
		st.set_uv(uv4); st.add_vertex(v4)
		st.set_uv(uv3); st.add_vertex(v3)
	
	# Будуємо стінки трикутника
	add_flipped_quad.call(p1, p2)
	add_flipped_quad.call(p2, p3)
	add_flipped_quad.call(p3, p1)

	st.generate_normals()
	return st.commit()
func _find_valid_spawn_point() -> Vector3:
	var rng = RandomNumberGenerator.new()
	rng.randomize()
	var center = 6000.0 / 2.0
	
	# Шукаємо підходяще місце (максимум 100 спроб, щоб гра не зависла)
	for i in range(100):
		# Беремо випадкові координати не надто близько до краю світу
		var rx = rng.randf_range(1000.0, 5000.0)
		var rz = rng.randf_range(1000.0, 5000.0)
		
		# Застосовуємо ту саму радіальну маску океану, що й для генерації землі
		var dist = Vector2(rx, rz).distance_to(Vector2(center, center))
		var edge_falloff = 1.0 - smoothstep(center * 0.7, center * 0.98, dist)
		
		var cont_val =continent_noise.get_noise_2d(rx, rz)
		cont_val = lerp(-1.0, cont_val, edge_falloff)
		
		# ПЕРЕВІРКА БІОМУ: Якщо значення від 0.0 до 0.15 - це пляж або пологий берег!
		if cont_val >= 0.0 and cont_val <= 0.15:
			print("Знайдено безпечний спавн: X:", rx, " Z:", rz)
			return Vector3(rx, 400.0, rz)
			
	# Якщо за 100 спроб нічого не знайшли (майже нереально), кидаємо в центр
	return Vector3(center, 400.0, center)
