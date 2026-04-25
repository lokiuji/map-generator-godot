extends Node

const WORLD_SIZE: float = 50000.0 # ЗБІЛЬШЕНО В 5 РАЗІВ!
var world_seed: int = 777
var custom_spawn_x: float = -1.0
var custom_spawn_z: float = -1.0

var elevation_noise = FastNoiseLite.new()
var moisture_noise = FastNoiseLite.new()
var detail_noise = FastNoiseLite.new()
var mountain_noise = FastNoiseLite.new() # НОВИЙ: Для кутастих скель

func _ready():
	_setup_noises()

func set_seed(new_seed: int):
	world_seed = new_seed
	_setup_noises()

func _setup_noises():
	# 1. Макро-рельєф: створює гігантські плями, які стануть континентами
	elevation_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	elevation_noise.seed = world_seed
	elevation_noise.frequency = 0.00006 # Дуже низька частота для величезних материків
	elevation_noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	elevation_noise.fractal_octaves = 5
	
	# 2. КУТАСТІ ГОРИ: Ridged шум утворює гострі хребти (як Карпати чи Альпи)
	mountain_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	mountain_noise.seed = world_seed + 333
	mountain_noise.frequency = 0.0005
	mountain_noise.fractal_type = FastNoiseLite.FRACTAL_RIDGED # Головний секрет кутастості!
	mountain_noise.fractal_octaves = 6
	
	detail_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	detail_noise.seed = world_seed + 123
	detail_noise.frequency = 0.005
	
	moisture_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	moisture_noise.seed = world_seed + 999
	moisture_noise.frequency = 0.0002

func get_raw_elevation(x: float, z: float) -> float:
	var e = (elevation_noise.get_noise_2d(x, z) + 1.0) / 2.0
	
	# Краї світу плавно йдуть під воду
	var center = WORLD_SIZE / 2.0
	var dist = Vector2(x, z).distance_to(Vector2(center, center))
	var edge_falloff = smoothstep(center * 0.7, center, dist)
	
	return clamp(e - edge_falloff, 0.0, 1.0)

func get_biome_data(x: float, z: float) -> Dictionary:
	var e = get_raw_elevation(x, z)
	var m = (moisture_noise.get_noise_2d(x, z) + 1.0) / 2.0
	
	var biome_name = "ocean"
	var color = Color(0.1, 0.3, 0.6)
	var is_grassy = false
	
	# ПІДНЯТО РІВЕНЬ ОКЕАНУ ДО 0.4! 
	# Тепер 40% світу - це вода. Це розриває сушу на окремі континенти.
	if e < 0.4: 
		biome_name = "ocean"
		color = Color(0.10, 0.30, 0.60).lerp(Color(0.2, 0.5, 0.7), e / 0.4)
	elif e < 0.42:
		biome_name = "beach"
		color = Color(0.76, 0.70, 0.50)
	elif e > 0.8:
		biome_name = "snow"
		color = Color(0.9, 0.95, 1.0)
	elif e > 0.65:
		biome_name = "tundra" if m < 0.5 else "taiga"
		color = Color(0.55, 0.65, 0.65) if m < 0.5 else Color(0.40, 0.50, 0.40)
	else:
		if m < 0.35:
			biome_name = "desert"
			color = Color(0.85, 0.70, 0.50)
		elif m < 0.65:
			biome_name = "grassland"
			color = Color(0.20, 0.35, 0.15)
			is_grassy = true
		else:
			biome_name = "forest"
			color = Color(0.10, 0.30, 0.05)
			is_grassy = true
			
	return {"elevation": e, "moisture": m, "biome": biome_name, "color": color, "is_grassy": is_grassy}
