extends Node

const WORLD_SIZE: float = 60000.0 
var world_seed: int = 777
var custom_spawn_x: float = -1.0
var custom_spawn_z: float = -1.0

var elevation_noise = FastNoiseLite.new()
var mountain_noise = FastNoiseLite.new()
var moisture_noise = FastNoiseLite.new()
var continents = [] 

func _ready():
	_setup_noises()
	_generate_continent_layout()

func set_seed(new_seed: int):
	world_seed = new_seed
	_setup_noises()
	_generate_continent_layout()

func _setup_noises():
	elevation_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	elevation_noise.seed = world_seed
	elevation_noise.frequency = 0.00045 
	elevation_noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	elevation_noise.fractal_octaves = 5
	
	mountain_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	mountain_noise.seed = world_seed + 333
	mountain_noise.frequency = 0.002
	mountain_noise.fractal_type = FastNoiseLite.FRACTAL_RIDGED
	mountain_noise.fractal_octaves = 5

	moisture_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	moisture_noise.seed = world_seed + 999
	moisture_noise.frequency = 0.0005

func _generate_continent_layout():
	continents.clear()
	var rng = RandomNumberGenerator.new()
	rng.seed = world_seed
	var attempts = 0
	
	while continents.size() < 7 and attempts < 200:
		attempts += 1
		var margin = 8000.0
		# ВИПРАВЛЕННЯ ДРЕЙФУ: Центруємо світ навколо нульових координат!
		var pos = Vector2(
			rng.randf_range(-WORLD_SIZE/2.0 + margin, WORLD_SIZE/2.0 - margin),
			rng.randf_range(-WORLD_SIZE/2.0 + margin, WORLD_SIZE/2.0 - margin)
		)
		var radius = rng.randf_range(3500.0, 7500.0)
		var too_close = false
		for c in continents:
			if pos.distance_to(c.pos) < (radius + c.radius + 6000.0):
				too_close = true
				break
		if not too_close: continents.append({"pos": pos, "radius": radius})

func get_falloff(world_x: float, world_z: float) -> float:
	var warp_x = elevation_noise.get_noise_2d(world_x * 0.5, world_z * 0.5) * 800.0
	var warp_z = elevation_noise.get_noise_2d(world_z * 0.5, world_x * 0.5) * 800.0
	var warped_pos = Vector2(world_x + warp_x, world_z + warp_z)
	var min_falloff = 1.0
	for c in continents:
		var dist = warped_pos.distance_to(c.pos)
		var t = clamp(dist / c.radius, 0.0, 1.0)
		var f = pow(t, 3.0) / (pow(t, 3.0) + pow(2.2 - 2.2 * t, 3.0))
		if f < min_falloff: min_falloff = f
	return min_falloff

func get_raw_elevation(x: float, z: float) -> float:
	var e = (elevation_noise.get_noise_2d(x, z) + 1.0) / 2.0
	return clamp(e - get_falloff(x, z), 0.0, 1.0)

func get_biome_data(x: float, z: float) -> Dictionary:
	var e = get_raw_elevation(x, z)
	var m = (moisture_noise.get_noise_2d(x, z) + 1.0) / 2.0
	var b = "ocean"; var c = Color(0.1, 0.3, 0.6); var is_g = false
	if e < 0.35: c = Color(0.1, 0.3, 0.6).lerp(Color(0.15, 0.45, 0.65), e / 0.35)
	elif e < 0.38: b = "beach"; c = Color(0.76, 0.70, 0.50)
	elif e > 0.75: b = "snow"; c = Color(0.9, 0.95, 1.0)
	elif e > 0.65:
		b = "tundra" if m < 0.5 else "taiga"
		c = Color(0.55, 0.65, 0.65) if m < 0.5 else Color(0.40, 0.50, 0.40)
	else:
		if m < 0.35: b = "desert"; c = Color(0.85, 0.70, 0.50)
		elif m < 0.65: b = "grassland"; c = Color(0.20, 0.35, 0.15); is_g = true
		else: b = "forest"; c = Color(0.10, 0.30, 0.05); is_g = true
	return {"elevation": e, "moisture": m, "biome": b, "color": c, "is_grassy": is_g}

func _get_final_height(world_x: float, world_z: float) -> float:
	var e = get_raw_elevation(world_x, world_z)
	if e < 0.35: return 5.0 + (e - 0.35) * 40.0
	var land = pow(e - 0.35, 1.2) * 150.0
	var ridge = smoothstep(0.4, 0.85, e)
	var peaks = mountain_noise.get_noise_2d(world_x, world_z) * 180.0 
	return 5.0 + land + (peaks * ridge)
