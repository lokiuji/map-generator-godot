extends Node

const WORLD_SIZE: float = 60000.0 
var world_seed: int = 777
var custom_spawn_x: float = 0.0
var custom_spawn_z: float = 0.0
var world_offset: Vector2 = Vector2.ZERO

var elevation_noise = FastNoiseLite.new()
var mountain_noise = FastNoiseLite.new()
var moisture_noise = FastNoiseLite.new()
var continents = [] 
var continent_noise = FastNoiseLite.new()
var chunk_modifications = {}
var rock_detail_noise = FastNoiseLite.new()
var cliff_noise = FastNoiseLite.new() 

var peninsula_noise = FastNoiseLite.new()
var coastline_noise = FastNoiseLite.new()

# === НОВЕ: ГЛОБАЛЬНА МАПА ГІР ===
var mountain_map: Image
const MOUNTAIN_MAP_SIZE = 2048 # 1 піксель = ~29 метрів реального світу
var ocean_mask_texture: ImageTexture

func _ready():
	_setup_noises()
	_generate_continent_layout()
	_bake_mountain_ranges() # Запікаємо гори одразу після створення континентів

func set_seed(new_seed: int, bake_mountains: bool = true):
	world_seed = new_seed
	_setup_noises()
	_generate_continent_layout()
	
	if bake_mountains:
		_bake_mountain_ranges()
		
	_update_water_shader()

func _update_water_shader():
	var noise_tex = NoiseTexture2D.new()
	noise_tex.noise = continent_noise
	noise_tex.width = 2048 
	noise_tex.height = 2048
	noise_tex.seamless = false 
	
	var ocean_mat = load("res://addons/tessarakkt.oceanfft/Ocean.tres")
	if ocean_mat:
		ocean_mat.set_shader_parameter("terrain_heightmap", noise_tex)
		ocean_mat.set_shader_parameter("terrain_scale", 2048.0)

func _get_seamless_noise(noise: FastNoiseLite, x: float, z: float) -> float:
	var angle_x = (x / WORLD_SIZE) * TAU 
	var radius = WORLD_SIZE / TAU
	var nx = cos(angle_x) * radius
	var ny = sin(angle_x) * radius
	return noise.get_noise_3d(nx, ny, z)

func _setup_noises():
	rock_detail_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	rock_detail_noise.seed = world_seed + 1234
	rock_detail_noise.frequency = 0.05 
	rock_detail_noise.fractal_type = FastNoiseLite.FRACTAL_RIDGED
	rock_detail_noise.fractal_octaves = 3
	
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

	continent_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	continent_noise.seed = world_seed + 123
	continent_noise.frequency = 0.000015 
	continent_noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	continent_noise.fractal_octaves = 4
	
	cliff_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	cliff_noise.seed = world_seed + 777
	cliff_noise.frequency = 0.001
	
	# ШУМ ДЛЯ ВЕЛИЧЕЗНИХ ПІВОСТРОВІВ ТА ЗАТОК
	peninsula_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	peninsula_noise.seed = world_seed + 444
	peninsula_noise.frequency = 0.00004 # Дуже низька частота!
	peninsula_noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	peninsula_noise.fractal_octaves = 3

	# ШУМ ДЛЯ РВАНИХ БЕРЕГІВ (ФІОРДИ)
	coastline_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	coastline_noise.seed = world_seed + 555
	coastline_noise.frequency = 0.0003 
	coastline_noise.fractal_type = FastNoiseLite.FRACTAL_RIDGED
	coastline_noise.fractal_octaves = 4

# ==========================================================
# МАГІЯ DRUNKEN WALK: ЗАПІКАННЯ ГІР
# ==========================================================
func _bake_mountain_ranges():
	print("Запікаємо глобальні гори...")
	mountain_map = Image.create(MOUNTAIN_MAP_SIZE, MOUNTAIN_MAP_SIZE, false, Image.FORMAT_RF)
	var map_scale = WORLD_SIZE / float(MOUNTAIN_MAP_SIZE)
	
	var rng = RandomNumberGenerator.new()
	rng.seed = world_seed + 555
	
	for continent in continents:
		for node in continent.nodes:
			# ГАРАНТОВАНО пускаємо від 2 до 4 мандрівників з КОЖНОЇ кістки
			var num_walkers = rng.randi_range(2, 4)
			for i in range(num_walkers):
				var px_center = (node.pos + Vector2(WORLD_SIZE/2.0, WORLD_SIZE/2.0)) / map_scale
				var start_dir = Vector2.UP.rotated(rng.randf() * TAU)
				
				# Робимо їх стартову силу більшою (до 1.2), щоб вони жили довше
				_simulate_drunken_walker(px_center, start_dir, rng.randf_range(0.8, 1.2), rng)
			
	print("Гори запечені успішно!")

func _simulate_drunken_walker(pos: Vector2, direction: Vector2, strength: float, rng: RandomNumberGenerator):
	if strength < 0.05: return 
	
	var current_pos = pos
	# ЗБІЛЬШИЛИ кількість кроків (було 250) - тепер хребти тягнутимуться далі
	var steps = int(350 * strength) 
	
	for step in range(steps):
		var world_x = (current_pos.x / MOUNTAIN_MAP_SIZE) * WORLD_SIZE - (WORLD_SIZE / 2.0)
		var world_z = (current_pos.y / MOUNTAIN_MAP_SIZE) * WORLD_SIZE - (WORLD_SIZE / 2.0)
		
		# ЗНИЗИЛИ ПОРІГ СМЕРТІ до 0.385. 
		# 0.38 - це лінія води. Тепер гори можуть підходити впритул до пляжів!
		if get_raw_elevation(world_x, world_z) < 0.385:
			return 

		direction = direction.rotated(rng.randf_range(-0.35, 0.35)).normalized()
		current_pos += direction * 2.0 
		
		_draw_soft_mountain(current_pos, strength)
		
		# ЗБІЛЬШИЛИ шанс розгалуження (було 0.05). Гори будуть більш "кущистими"
		if rng.randf() < 0.07: 
			var branch_dir = direction.rotated(rng.randf_range(0.6, 1.2) * (1 if rng.randf() > 0.5 else -1))
			_simulate_drunken_walker(current_pos, branch_dir, strength * 0.7, rng)
			
		# ЗМЕНШИЛИ швидкість згасання (було 0.003). Гори довше залишатимуться високими.
		strength -= 0.002

func _draw_soft_mountain(px_pos: Vector2, strength: float):
	var brush_radius = int(18.0 * strength) # Ширина гори залежить від сили
	if brush_radius < 1: return
	
	var cx = int(px_pos.x)
	var cy = int(px_pos.y)
	
	for x in range(cx - brush_radius, cx + brush_radius + 1):
		for y in range(cy - brush_radius, cy + brush_radius + 1):
			if x >= 0 and x < MOUNTAIN_MAP_SIZE and y >= 0 and y < MOUNTAIN_MAP_SIZE:
				var dist = Vector2(x, y).distance_to(px_pos)
				if dist <= brush_radius:
					# М'який купол (центр найвищий, краї спадають)
					var falloff = smoothstep(float(brush_radius), 0.0, dist)
					var add_h = (falloff * strength) * 0.15 
					var current_h = mountain_map.get_pixel(x, y).r
					# Нашаровуємо гори одна на одну
					mountain_map.set_pixel(x, y, Color(min(1.0, current_h + add_h), 0, 0, 1))

func _generate_continent_layout():
	continents.clear()
	var rng = RandomNumberGenerator.new()
	rng.seed = world_seed
	var attempts = 0
	
	var target_continents = 9 
	
	while continents.size() < target_continents and attempts < 4000:
		attempts += 1
		
		# КОНТИНЕНТИ ЗНОВУ СПАВНЯТЬСЯ ПО ВСІЙ МАПІ
		var base_pos = Vector2(
			rng.randf_range(-WORLD_SIZE/2.0, WORLD_SIZE/2.0),
			rng.randf_range(-WORLD_SIZE/2.0, WORLD_SIZE/2.0)
		)
		
		var num_nodes = rng.randi_range(2, 5)
		var nodes = []
		var current_pos = base_pos
		
		for i in range(num_nodes):
			var r = rng.randf_range(2500.0, 5000.0) 
			nodes.append({"pos": current_pos, "radius": r})
			
			var angle = rng.randf() * TAU
			var step_dist = rng.randf_range(r * 0.7, r * 1.3)
			current_pos += Vector2(cos(angle), sin(angle)) * step_dist
			
		var too_close = false
		for c in continents:
			for old_node in c.nodes:
				for new_node in nodes:
					var safe_dist = new_node.radius + old_node.radius + 1200.0
					if _get_wrapped_distance(new_node.pos, old_node.pos) < safe_dist:
						too_close = true
						break
				if too_close: break
			if too_close: break
				
		if not too_close: 
			continents.append({"base_pos": base_pos, "nodes": nodes}) 

func get_falloff(world_x: float, world_z: float) -> float:
	var p_noise = _get_seamless_noise(peninsula_noise, world_x, world_z)
	var c_noise = _get_seamless_noise(coastline_noise, world_x, world_z)

	var min_falloff = 1.0 
	var warped_pos = Vector2(world_x, world_z)
	
	for c in continents:
		var min_t_for_continent = 1.0
		
		for node in c.nodes:
			var dist = _get_wrapped_distance(warped_pos, node.pos)
			var t = dist / node.radius
			if t < min_t_for_continent: 
				min_t_for_continent = t
				
		var edge_mask = smoothstep(0.2, 0.7, min_t_for_continent)
		var shape_modifier = ((p_noise * 0.5) + (c_noise * 0.15)) * edge_mask
		
		var t_final = clamp(min_t_for_continent + shape_modifier, 0.0, 1.0)
		
		# === РОЗШИРЕННЯ СУШІ ===
		# Раніше було smoothstep(0.65, 0.95). 
		# Зсуваючи ці значення вище, ми робимо сушу ширшою, а океани вужчими.
		var f = smoothstep(0.75, 1.0, t_final)
		
		if f < min_falloff: 
			min_falloff = f
			
	var polar_dist = abs(world_z) / (WORLD_SIZE / 2.0)
	var polar_ocean = smoothstep(0.88, 1.0, polar_dist) # Льодовики теж трохи відсунули
	
	return max(min_falloff, polar_ocean)

func get_raw_elevation(x: float, z: float) -> float:
	var e = (_get_seamless_noise(elevation_noise, x, z) + 1.0) / 2.0
	return clamp(e - get_falloff(x, z), 0.0, 1.0)

# ==========================================================
# 1. ВИПРАВЛЕНА МАСКА (БІЛІНІЙНА ІНТЕРПОЛЯЦІЯ ДЛЯ ГЛАДКИХ СХИЛІВ)
# ==========================================================
func get_mountain_mask(world_x: float, world_z: float) -> float:
	if not mountain_map: return 0.0
	
	var safe_x = wrapf(world_x, -WORLD_SIZE/2.0, WORLD_SIZE/2.0)
	var safe_z = wrapf(world_z, -WORLD_SIZE/2.0, WORLD_SIZE/2.0)
	
	# Точні координати з плаваючою комою
	var px_x = ((safe_x + WORLD_SIZE/2.0) / WORLD_SIZE) * (MOUNTAIN_MAP_SIZE - 1)
	var px_y = ((safe_z + WORLD_SIZE/2.0) / WORLD_SIZE) * (MOUNTAIN_MAP_SIZE - 1)
	
	# Знаходимо 4 сусідні пікселі для згладжування
	var x0 = int(floor(px_x))
	var y0 = int(floor(px_y))
	var x1 = clampi(x0 + 1, 0, MOUNTAIN_MAP_SIZE - 1)
	var y1 = clampi(y0 + 1, 0, MOUNTAIN_MAP_SIZE - 1)
	
	x0 = clampi(x0, 0, MOUNTAIN_MAP_SIZE - 1)
	y0 = clampi(y0, 0, MOUNTAIN_MAP_SIZE - 1)
	
	# Частки для інтерполяції
	var tx = px_x - float(x0)
	var ty = px_y - float(y0)
	
	# Зчитуємо 4 пікселі
	var c00 = mountain_map.get_pixel(x0, y0).r
	var c10 = mountain_map.get_pixel(x1, y0).r
	var c01 = mountain_map.get_pixel(x0, y1).r
	var c11 = mountain_map.get_pixel(x1, y1).r
	
	# Змішуємо їх плавно! Ніяких більше "Майнкрафт" блоків.
	var top = lerp(c00, c10, tx)
	var bottom = lerp(c01, c11, tx)
	
	return lerp(top, bottom, ty)


# ==========================================================
# 2. ВИПРАВЛЕНІ БІОМИ (ФАРБУЄМО ТІЛЬКИ СУХОПУТНІ ГОРИ)
# ==========================================================
func get_biome_data(x: float, z: float) -> Dictionary:
	var e = get_raw_elevation(x, z)
	var m = (_get_seamless_noise(moisture_noise, x, z) + 1.0) / 2.0
	
	# Читаємо гори і ВІДСІКАЄМО ЇХ БІЛЯ ОКЕАНУ
	var raw_mountain_mask = get_mountain_mask(x, z)
	var land_mask = smoothstep(0.40, 0.55, e) # 0.0 на пляжі, 1.0 вглибині суші
	var final_mountain_mask = raw_mountain_mask * land_mask
	
	var b = "ocean"
	var c = Color(0.08, 0.25, 0.45)
	var is_g = false
	
	var col_sand = Color(0.55, 0.45, 0.30)
	var col_dirt = Color(0.35, 0.22, 0.12) 
	var col_grassland = Color(0.12, 0.22, 0.08)
	var col_forest = Color(0.06, 0.16, 0.05)
	var col_tundra = Color(0.25, 0.28, 0.22)
	var col_taiga = Color(0.12, 0.20, 0.15)
	var col_snow = Color(0.85, 0.90, 0.95)
	var col_rock = Color(0.25, 0.25, 0.25)
	
	if e < 0.35: 
		c = Color(0.05, 0.15, 0.35).lerp(Color(0.08, 0.25, 0.45), e / 0.35)
	elif e < 0.38: 
		b = "beach"
		c = Color(0.08, 0.25, 0.45).lerp(col_sand, smoothstep(0.35, 0.38, e))
	elif e > 0.70: 
		b = "snow"
		var t = smoothstep(0.70, 0.85, e)
		c = col_tundra.lerp(col_taiga, smoothstep(0.3, 0.7, m)).lerp(col_snow, t)
	else:
		var dry_col = Color(0.65, 0.50, 0.35).lerp(col_sand, smoothstep(0.1, 0.4, m))
		var wet_col = col_grassland.lerp(col_forest, smoothstep(0.4, 0.8, m))
		c = dry_col.lerp(wet_col, smoothstep(0.25, 0.55, m))
		
		var deposition_mask = smoothstep(0.45, 0.38, e)
		c = c.lerp(col_dirt, deposition_mask * 0.7)
		
		var elevation_transition = smoothstep(0.55, 0.70, e)
		c = c.lerp(col_tundra.lerp(col_taiga, smoothstep(0.3, 0.7, m)), elevation_transition)
		
		is_g = m > 0.3 and e < 0.65
		if is_g: b = "grassland" if m < 0.6 else "forest"
		else: b = "desert" if e < 0.55 else "tundra"

	# === ЛОГІКА ПЕРЕФАРБУВАННЯ ЗАПЕЧЕНИХ ГІР ===
	if final_mountain_mask > 0.1:
		var rock_blend = smoothstep(0.1, 0.4, final_mountain_mask)
		c = c.lerp(col_rock, rock_blend)
		if final_mountain_mask > 0.25: is_g = false 
		
	if final_mountain_mask > 0.6:
		var snow_blend = smoothstep(0.6, 0.8, final_mountain_mask)
		c = c.lerp(col_snow, snow_blend)

	return {"elevation": e, "moisture": m, "biome": b, "color": c, "is_grassy": is_g}


# ==========================================================
# 3. ВИПРАВЛЕНА ВИСОТА (ГЛАДКА ТА ОБМЕЖЕНА СУШЕЮ)
# ==========================================================

# ==========================================================
# ВИСОТА ТА РЕЛЬЄФ
# ==========================================================

func _get_final_height(world_x: float, world_z: float) -> float:
	var safe_x = wrapf(world_x, -100000.0, 100000.0)
	var safe_z = wrapf(world_z, -100000.0, 100000.0)
	
	var e = get_raw_elevation(safe_x, safe_z)
	
	if e < 0.35: 
		var dist_from_shore = 1.0 - (e / 0.35)
		var cliff_val = (_get_seamless_noise(cliff_noise, safe_x, safe_z) + 1.0) / 2.0
		var drop_factor = pow(dist_from_shore, lerp(4.0, 0.3, cliff_val))
		return lerp(5.0, -200.0, drop_factor)
	
	var land = pow(e - 0.35, 1.2) * 150.0
	
	var m_mask = get_mountain_mask(safe_x, safe_z)
	var land_mask = smoothstep(0.40, 0.55, e) 
	m_mask *= land_mask 
	
	var detail_noise = _get_seamless_noise(mountain_noise, safe_x, safe_z)
	var rocky_mask = m_mask + (detail_noise * m_mask * 0.4) 
	var massive_mountains = max(0.0, rocky_mask) * 800.0 
	
	var erosion = smoothstep(0.3, 0.7, _get_seamless_noise(moisture_noise, safe_x * 1.5, safe_z * 1.5))
	massive_mountains -= (massive_mountains * erosion * 0.25)
	
	return 5.0 + land + massive_mountains

func _get_wrapped_distance(p1: Vector2, p2: Vector2) -> float:
	var dx = abs(p1.x - p2.x)
	var dy = abs(p1.y - p2.y)
	if dx > WORLD_SIZE / 2.0: dx = WORLD_SIZE - dx
	if dy > WORLD_SIZE / 2.0: dy = WORLD_SIZE - dy
	return Vector2(dx, dy).length()

func get_absolute_chunk_id(p_world_offset: Vector2, local_chunk_pos: Vector2, chunk_size: float) -> Vector2:
	var half_world = WORLD_SIZE / 2.0
	var real_x = p_world_offset.x + (local_chunk_pos.x * chunk_size)
	var real_z = p_world_offset.y + (local_chunk_pos.y * chunk_size)
	var wrapped_x = fposmod(real_x + half_world, WORLD_SIZE) - half_world
	var wrapped_z = fposmod(real_z + half_world, WORLD_SIZE) - half_world
	return (Vector2(wrapped_x, wrapped_z) / chunk_size).round()

func bake_ocean_mask(ocean_material: ShaderMaterial):
	var mask_size = 512 
	var img = Image.create(mask_size, mask_size, false, Image.FORMAT_R8)
	var half_world = WORLD_SIZE / 2.0
	
	for x in range(mask_size):
		for y in range(mask_size):
			var world_x = lerp(-half_world, half_world, float(x) / mask_size)
			var world_z = lerp(-half_world, half_world, float(y) / mask_size)
			var elevation = get_raw_elevation(world_x, world_z)
			var mask_value = smoothstep(0.20, 0.40, elevation)
			img.set_pixel(x, y, Color(mask_value, mask_value, mask_value))
			
	ocean_mask_texture = ImageTexture.create_from_image(img)
	if ocean_material:
		ocean_material.set_shader_parameter("terrain_noise_map", ocean_mask_texture)
