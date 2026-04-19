extends Node3D

const CHUNK_SIZE = 120.0
const RENDER_DISTANCE = 4

@export var player: Node3D
@export var terrain_material: Material

var active_chunks = {}
var current_player_chunk = Vector2(1000000, 1000000)
var is_first_spawn = true 

# НОВЕ: Глобальний генератор шуму для всього світу
var global_noise: FastNoiseLite
var moisture_noise: FastNoiseLite # НОВЕ: Шум вологості

func _ready():
	# Шум висоти (Гори/Долини)
	global_noise = FastNoiseLite.new()
	global_noise.seed = 1234
	global_noise.frequency = 0.005 # Зробив гори ширшими
	global_noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	
	# Шум вологості (Ліс/Пустеля)
	moisture_noise = FastNoiseLite.new()
	moisture_noise.seed = 9999 # ІНШИЙ СІД!
	moisture_noise.frequency = 0.003 # Біоми величезні
	
	# Створюємо шум БЕЗПЕЧНО в головному потоці
	global_noise = FastNoiseLite.new()
	global_noise.seed = 1234
	global_noise.frequency = 0.01
	global_noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	
	if not player: player = get_node_or_null("Player")
	
	if player:
		player.process_mode = Node.PROCESS_MODE_DISABLED 
		
		# --- ОСЬ ВИПРАВЛЕННЯ ---
		# Записуємо реальну позицію ДО того, як малювати світ, щоб _process не збожеволів
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
			var dist = Vector2(x, z).length()
			if dist <= RENDER_DISTANCE: desired_chunks.append(center_chunk + Vector2(x, z))
				
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
	
	# НОВЕ: Передаємо global_noise у чанк
	chunk.start_generation(chunk_pos, CHUNK_SIZE, 16, terrain_material, global_noise, moisture_noise)

func _on_chunk_ready(chunk: Node3D):
	if is_first_spawn and chunk.chunk_pos == current_player_chunk:
		is_first_spawn = false
		if player:
			player.global_position.y = 100.0 
			player.process_mode = Node.PROCESS_MODE_INHERIT
