extends Node

const WORLD_SIZE: float = 60000.0 
var world_seed: int = 777
var custom_spawn_x: float = -999999.0
var custom_spawn_z: float = -999999.0
var world_offset: Vector2 = Vector2.ZERO
var elevation_noise = FastNoiseLite.new()
var mountain_noise = FastNoiseLite.new()
var moisture_noise = FastNoiseLite.new()
var continents = [] 
var continent_noise = FastNoiseLite.new()
var chunk_modifications = {}

func _ready():
	_setup_noises()
	_generate_continent_layout()

func set_seed(new_seed: int):
	world_seed = new_seed
	_setup_noises()
	_generate_continent_layout()

func _get_seamless_noise(noise: FastNoiseLite, x: float, z: float) -> float:
	# Перетворюємо плоску вісь X на коло (Схід та Захід зшиваються разом)
	var angle_x = (x / WORLD_SIZE) * TAU # TAU - це 2 * PI
	var radius = WORLD_SIZE / TAU
	
	# Конвертуємо полярні координати в декартові для 3D простору
	var nx = cos(angle_x) * radius
	var ny = sin(angle_x) * radius
	
	# Читаємо 3D шум. nx та ny відповідають за довготу, а z - за широту
	return noise.get_noise_3d(nx, ny, z)

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

	# НОВИЙ ШУМ ДЛЯ КОНТИНЕНТІВ (як у відео)
	continent_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	continent_noise.seed = world_seed + 123
	continent_noise.frequency = 0.000015 # Дуже низька частота створює величезні материки
	continent_noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	continent_noise.fractal_octaves = 4

func _generate_continent_layout():
	continents.clear()
	var rng = RandomNumberGenerator.new()
	rng.seed = world_seed
	var attempts = 0
	
	# Збільшуємо кількість спроб до 1500, щоб генератор точно знайшов місце для всіх 7
	while continents.size() < 7 and attempts < 1500:
		attempts += 1
		var pos = Vector2(
			rng.randf_range(-WORLD_SIZE/2.0, WORLD_SIZE/2.0),
			rng.randf_range(-WORLD_SIZE/2.0, WORLD_SIZE/2.0)
		)
		
		# Дозволяємо материкам спавнитися трохи ближче до полюсів (0.4 замість 0.35)
		if abs(pos.y) > WORLD_SIZE * 0.4: 
			continue
			
		# Робимо базові радіуси трохи компактнішими, щоб вони влізли на мапу
		var radius = rng.randf_range(5000.0, 9000.0) 
		var too_close = false
		
		for c in continents:
			# Зменшуємо жорсткий буфер між материками з 4000 до 1500 км
			# (Завдяки Domain Warping вони все одно не будуть виглядати злиплими)
			if _get_wrapped_distance(pos, c.pos) < (radius + c.radius + 1500.0):
				too_close = true
				break
				
		if not too_close: continents.append({"pos": pos, "radius": radius})

func get_falloff(world_x: float, world_z: float) -> float:
	# 1. СПОТВОРЕННЯ КООРДИНАТ
	# Зменшуємо силу розриву з 18000 до 12000, щоб материки залишалися масивними
	var warp_strength = 12000.0 
	var warp_x = _get_seamless_noise(continent_noise, world_x, world_z) * warp_strength
	var warp_z = _get_seamless_noise(continent_noise, world_z + 5000.0, world_x - 5000.0) * warp_strength
	
	var warped_pos = Vector2(world_x + warp_x, world_z + warp_z)
	var min_falloff = 1.0 
	
	# 2. ПЕРЕВІРКА ВІДСТАНІ ДО КОНТИНЕНТІВ
	for c in continents:
		var dist = _get_wrapped_distance(warped_pos, c.pos)
		var t = clamp(dist / c.radius, 0.0, 1.0)
		
		# РОЗШИРЮЄМО СУХОДІЛ:
		# Раніше було (0.4, 0.9). 
		# Тепер берег починає спускатися аж на 65% віддаленості від центру (0.65),
		# і повністю йде під воду лише за межами базового радіусу (1.1).
		var f = smoothstep(0.65, 1.1, t)
		
		if f < min_falloff: 
			min_falloff = f
			
	# 3. ДОДАЄМО КРИЖАНІ ПОЛЮСИ
	var polar_dist = abs(world_z) / (WORLD_SIZE / 2.0)
	# Робимо льодовики трохи меншими, щоб дати більше місця океану та землі
	var polar_ocean = smoothstep(0.9, 1.0, polar_dist)
	
	return max(min_falloff, polar_ocean)

func get_raw_elevation(x: float, z: float) -> float:
	var e = (_get_seamless_noise(elevation_noise, x, z) + 1.0) / 2.0
	return clamp(e - get_falloff(x, z), 0.0, 1.0)

func get_biome_data(x: float, z: float) -> Dictionary:
	var e = get_raw_elevation(x, z)
	var m = (_get_seamless_noise(moisture_noise, x, z) + 1.0) / 2.0
	
	var b = "ocean"
	var c = Color(0.08, 0.25, 0.45)
	var is_g = false
	
	# ЗАДАЄМО НАТУРАЛЬНІ ТА ТЕМНІШІ КОЛЬОРИ БІОМІВ
	# Ці кольори тепер слугуватимуть "корінням" для трави
	var col_sand = Color(0.55, 0.45, 0.30)
	var col_desert = Color(0.65, 0.50, 0.35)
	var col_grassland = Color(0.12, 0.22, 0.08) # Натуральний темно-зелений
	var col_forest = Color(0.06, 0.16, 0.05)    # Глибокий хвойний/лісовий
	var col_tundra = Color(0.25, 0.28, 0.22)    # Холодний сіро-зелений
	var col_taiga = Color(0.12, 0.20, 0.15)     # Темно-сіро-зелений (смереки)
	var col_snow = Color(0.85, 0.90, 0.95)
	
	if e < 0.35: 
		# Плавний перехід глибини океану
		c = Color(0.05, 0.15, 0.35).lerp(Color(0.08, 0.25, 0.45), e / 0.35)
	elif e < 0.38: 
		b = "beach"
		# Плавний перехід від води до піску
		var t = smoothstep(0.35, 0.38, e)
		c = Color(0.08, 0.25, 0.45).lerp(col_sand, t)
	elif e > 0.70: 
		b = "snow"
		# Плавний перехід до снігу на вершинах гір
		var t = smoothstep(0.70, 0.85, e)
		var base_cold = col_tundra.lerp(col_taiga, smoothstep(0.3, 0.7, m))
		c = base_cold.lerp(col_snow, t)
	else:
		# МАГІЯ ГРАДІЄНТІВ: Плавне змішування біомів за вологостю
		
		# 1. Формуємо сухий градієнт (від пустелі до сухого піску)
		var dry_col = col_desert.lerp(col_sand, smoothstep(0.1, 0.4, m))
		
		# 2. Формуємо вологий градієнт (від поля до густого лісу)
		var wet_col = col_grassland.lerp(col_forest, smoothstep(0.4, 0.8, m))
		
		# 3. Змішуємо суху та вологу зони у надширокий градієнт
		c = dry_col.lerp(wet_col, smoothstep(0.25, 0.55, m))
		
		# 4. Якщо висота наближається до гір (0.55 - 0.70), домішуємо холодні кольори
		var elevation_transition = smoothstep(0.55, 0.70, e)
		var cold_col = col_tundra.lerp(col_taiga, smoothstep(0.3, 0.7, m))
		c = c.lerp(cold_col, elevation_transition)
		
		# Визначаємо, чи садити тут траву
		is_g = m > 0.3 and e < 0.65
		if is_g: b = "grassland" if m < 0.6 else "forest"
		else: b = "desert" if e < 0.55 else "tundra"

	return {"elevation": e, "moisture": m, "biome": b, "color": c, "is_grassy": is_g}
func _get_final_height(world_x: float, world_z: float) -> float:
	var e = get_raw_elevation(world_x, world_z)
	if e < 0.35: return 5.0 + (e - 0.35) * 40.0
	
	var land = pow(e - 0.35, 1.2) * 150.0
	var ridge = smoothstep(0.4, 0.85, e)
	# Зверни увагу, тут теж застосовуємо _get_seamless_noise для гір!
	var peaks = _get_seamless_noise(mountain_noise, world_x, world_z) * 180.0 
	
	return 5.0 + land + (peaks * ridge)

func _get_wrapped_distance(p1: Vector2, p2: Vector2) -> float:
	var dx = abs(p1.x - p2.x)
	var dy = abs(p1.y - p2.y)
	# Якщо відстань більша за половину світу — значить коротший шлях йде через "край" карти
	if dx > WORLD_SIZE / 2.0: dx = WORLD_SIZE - dx
	if dy > WORLD_SIZE / 2.0: dy = WORLD_SIZE - dy
	return Vector2(dx, dy).length()

func get_absolute_chunk_id(p_world_offset: Vector2, local_chunk_pos: Vector2, chunk_size: float) -> Vector2:
	var half_world = WORLD_SIZE / 2.0
	
	# Справжні координати у світі (використовуємо p_world_offset)
	var real_x = p_world_offset.x + (local_chunk_pos.x * chunk_size)
	var real_z = p_world_offset.y + (local_chunk_pos.y * chunk_size)
	
	var wrapped_x = fposmod(real_x + half_world, WORLD_SIZE) - half_world
	var wrapped_z = fposmod(real_z + half_world, WORLD_SIZE) - half_world
	
	return (Vector2(wrapped_x, wrapped_z) / chunk_size).round()
