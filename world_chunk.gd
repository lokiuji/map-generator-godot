extends Node3D
class_name WorldChunk

# ПАЛІТРА БІОМІВ (відповідає назвам з вашого Python-скрипта)
const BIOME_COLORS = {
	"ocean": Color(0.10, 0.30, 0.60),
	"beach": Color(0.76, 0.70, 0.50),
	"scorched": Color(0.25, 0.20, 0.20),
	"bare": Color(0.45, 0.40, 0.35),
	"tundra": Color(0.55, 0.65, 0.65),
	"snow": Color(0.90, 0.95, 1.00),
	"temperate_desert": Color(0.75, 0.65, 0.45),
	"shrubland": Color(0.45, 0.55, 0.25),
	"grassland": Color(0.20, 0.35, 0.15),
	"temperate_deciduous_forest": Color(0.15, 0.30, 0.10),
	"temperate_rain_forest": Color(0.10, 0.25, 0.08),
	"subtropical_desert": Color(0.85, 0.70, 0.50),
	"tropical_seasonal_forest": Color(0.30, 0.45, 0.10),
	"tropical_rain_forest": Color(0.10, 0.30, 0.05)
}

# === ШУМИ ДЛЯ МІКРО-РЕЛЬЄФУ (ГІБРИДНИЙ ПІДХІД) ===
var noise_continent = FastNoiseLite.new()
var noise_mountain = FastNoiseLite.new()

func _ready():
	# Налаштовуємо шуми для генерації дрібних деталей (камінців, пагорбів)
	# Частота (frequency) тепер більша, бо це мікро-рельєф, а не цілі материки
	
	noise_continent.noise_type = FastNoiseLite.TYPE_SIMPLEX
	noise_continent.frequency = 0.005 # Робить невеликі горбочки на рівнинах
	noise_continent.seed = Global.world_seed 
	
	noise_mountain.noise_type = FastNoiseLite.TYPE_SIMPLEX
	noise_mountain.frequency = 0.01 # Робить гострі та деталізовані скелі
	noise_mountain.fractal_type = FastNoiseLite.FRACTAL_RIDGED 
	noise_mountain.seed = Global.world_seed + 123
# ==================================================

var chunk_pos: Vector2
var chunk_size: float
var resolution: int
var thread: Thread
var terrain_mesh_instance: MeshInstance3D

var grass_mesh: Mesh
var grass_material = preload("res://Materials/grass_mat.tres") 

var player_ref: Node3D
var mmi: MultiMeshInstance3D 

var has_collision: bool = false
var static_body_ref: StaticBody3D = null

signal chunk_ready(chunk_node)

func start_generation(pos: Vector2, size: float, res: int, material: Material, g_mesh: Mesh, p_player: Node3D):
	chunk_pos = pos
	chunk_size = size
	resolution = res
	grass_mesh = g_mesh
	player_ref = p_player
	
	terrain_mesh_instance = MeshInstance3D.new()
	terrain_mesh_instance.material_override = material
	add_child(terrain_mesh_instance)
	
	thread = Thread.new()
	thread.start(_build_terrain_data_in_thread)

func _process(_delta):
	if player_ref:
		var dist = global_position.distance_to(player_ref.global_position)
		if mmi: mmi.visible = dist < 100.0

		if dist < 80.0 and not has_collision:
			if terrain_mesh_instance.mesh != null:
				terrain_mesh_instance.create_trimesh_collision()
				has_collision = true
				for child in terrain_mesh_instance.get_children():
					if child is StaticBody3D:
						static_body_ref = child
						break
		elif dist > 100.0 and has_collision:
			if static_body_ref:
				static_body_ref.queue_free()
				static_body_ref = null
			has_collision = false

# Зчитує біом для конкретних 3D-координат
func _get_biome_data(world_x: float, world_z: float) -> Dictionary:
	if Global.map_data.is_empty(): return {"elevation": 0.0, "biome": "ocean"}
	
	var gx = clamp(int(round(world_x / Global.tile_size)), 0, Global.map_width - 1)
	var gz = clamp(int(round(world_z / Global.tile_size)), 0, Global.map_height - 1)
	return Global.map_data.get(Vector2(gx, gz), {"elevation": 0.0, "biome": "ocean"})

# Обчислює плавну висоту за допомогою білінійної інтерполяції між 4 клітинками JSON
# Обчислює макро-висоту з JSON + мікро-рельєф з шумів
func _get_h(world_x: float, world_z: float) -> float:
	if Global.map_data.is_empty(): return 0.0
	
	# 1. Читаємо базову структуру світу з JSON
	var gx = world_x / Global.tile_size
	var gz = world_z / Global.tile_size
	
	var x0 = clamp(int(floor(gx)), 0, Global.map_width - 1)
	var z0 = clamp(int(floor(gz)), 0, Global.map_height - 1)
	var x1 = clamp(x0 + 1, 0, Global.map_width - 1)
	var z1 = clamp(z0 + 1, 0, Global.map_height - 1)
	
	var tx = gx - floor(gx)
	var tz = gz - floor(gz)
	
	# ФІКС СЕГМЕНТОВАНОСТІ: Згладжуємо переходи (Hermite interpolation)
	tx = tx * tx * (3.0 - 2.0 * tx)
	tz = tz * tz * (3.0 - 2.0 * tz)
	
	var h00 = Global.map_data.get(Vector2(x0, z0), {"elevation": 0.0})["elevation"]
	var h10 = Global.map_data.get(Vector2(x1, z0), {"elevation": 0.0})["elevation"]
	var h01 = Global.map_data.get(Vector2(x0, z1), {"elevation": 0.0})["elevation"]
	var h11 = Global.map_data.get(Vector2(x1, z1), {"elevation": 0.0})["elevation"]
	
	var h0 = lerp(h00, h10, tx)
	var h1 = lerp(h01, h11, tx)
	var json_h = lerp(h0, h1, tz) # Це макро-висота від Python (зазвичай 0.0 - 1.0)
	
	# 2. Будуємо основу рельєфу
	var base_height = 0.0
	if json_h < 0.1:
		base_height = (json_h - 0.1) * 50.0 # Океан
	else:
		# pow робить підніжжя пологими, а вершини крутими
		base_height = pow(json_h - 0.1, 1.3) * 350.0 
		
	# 3. ДОДАЄМО НАШ ФІРМОВИЙ ПРОЦЕДУРНИЙ РЕЛЬЄФ ЗВЕРХУ!
	var micro_noise = noise_continent.get_noise_2d(world_x, world_z) * 6.0
	var mount_noise = max(0.0, noise_mountain.get_noise_2d(world_x, world_z)) * 180.0
	
	# Маска гір: дозволяємо гострим скелям з'являтися ТІЛЬКИ там, де Python згенерував височину
	var mountain_mask = smoothstep(0.4, 0.8, json_h) 
	
	return 2.8 + base_height + micro_noise + (mount_noise * mountain_mask)

func _get_normal(world_x: float, world_z: float) -> Vector3:
	var d = 0.5 
	var h_left = _get_h(world_x - d, world_z)
	var h_right = _get_h(world_x + d, world_z)
	var h_down = _get_h(world_x, world_z - d)
	var h_up = _get_h(world_x, world_z + d)
	return Vector3(h_left - h_right, 2.0 * d, h_down - h_up).normalized()

func _build_terrain_data_in_thread():
	var st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var step = chunk_size / resolution
	var offset_x = chunk_pos.x * chunk_size
	var offset_z = chunk_pos.y * chunk_size
	var rng = RandomNumberGenerator.new()
	rng.seed = hash(str(chunk_pos))
	
	var grass_transforms = []
	var needs_water = false
	
	for z in range(resolution + 1):
		for x in range(resolution + 1):
			var world_x = offset_x + x * step
			var world_z = offset_z + z * step
			
			var py = _get_h(world_x, world_z)
			var exact_normal = _get_normal(world_x, world_z)
			st.set_normal(exact_normal)
			
			# Отримуємо біом безпосередньо з Python JSON
			var tile_info = _get_biome_data(world_x, world_z)
			var biome_name = tile_info["biome"]
			
			var vert_color = BIOME_COLORS.get(biome_name, Color.MAGENTA)
			
			# Сніг для шейдера
			var snow_weight = 0.0
			if py > 140.0: snow_weight = clamp((py - 140.0) / 10.0, 0.0, 1.0)
			vert_color.a = snow_weight
			
			st.set_color(vert_color)
			st.set_uv(Vector2(float(x) / resolution, float(z) / resolution))
			st.add_vertex(Vector3(x * step, py, z * step))
			
			if py < 2.9: needs_water = true
			
			if x < resolution and z < resolution:
				var h00 = py 
				var h10 = _get_h(world_x + step, world_z)
				var h01 = _get_h(world_x, world_z + step)
				var h11 = _get_h(world_x + step, world_z + step)
				
				# Трава росте тільки в зелених біомах
				var is_grassy = biome_name in ["grassland", "temperate_deciduous_forest", "temperate_rain_forest", "shrubland"]
				
				if py > 0.3 and is_grassy:
					var density = 5
					var cell_normal = _get_normal(world_x + step/2.0, world_z + step/2.0)
					var cell_steepness = 1.0 - cell_normal.dot(Vector3.UP)
					
					if cell_steepness < 0.25:
						for gx_idx in range(density):
							for gz_idx in range(density):
								var local_x = (gx_idx + rng.randf()) / float(density)
								var local_z = (gz_idx + rng.randf()) / float(density)
								var gx = world_x + local_x * step
								var gz = world_z + local_z * step
								
								var g_py = 0.0
								if local_x + local_z <= 1.0: 
									g_py = h00 + local_x * (h10 - h00) + local_z * (h01 - h00)
								else:
									var nx = 1.0 - local_x
									var nz = 1.0 - local_z
									g_py = h11 + nx * (h01 - h11) + nz * (h10 - h11)
									
								g_py -= 0.1 
								
								if g_py > 4.0 and g_py < 140.0: 
									var pos = Vector3(gx - offset_x, g_py, gz - offset_z)
									var s_xz = rng.randf_range(1.5, 2.5) 
									var s_y = rng.randf_range(1.0, 1.5)  
									var basis = Basis().rotated(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s_xz, s_y, s_xz))
									grass_transforms.append(Transform3D(basis, pos))
			
	for z in range(resolution):
		for x in range(resolution):
			var idx = x + z * (resolution + 1)
			st.add_index(idx)
			st.add_index(idx + 1)
			st.add_index(idx + resolution + 1)
			st.add_index(idx + 1)
			st.add_index(idx + resolution + 2)
			st.add_index(idx + resolution + 1)
	
	var water_mesh_data = null
	if needs_water:
		var w_st = SurfaceTool.new()
		w_st.begin(Mesh.PRIMITIVE_TRIANGLES)
		var w_res = 15
		var w_step = chunk_size / w_res
		
		for wz in range(w_res + 1):
			for wx in range(w_res + 1):
				var world_wx = offset_x + wx * w_step
				var world_wz = offset_z + wz * w_step
				
				# Глибина океану замість старого шуму
				var depth = _get_h(world_wx, world_wz)
				var wave_mask = smoothstep(0.0, -15.0, depth)
				
				w_st.set_color(Color(wave_mask, 0, 0))
				w_st.set_uv(Vector2(float(wx) / w_res, float(wz) / w_res))
				w_st.add_vertex(Vector3(wx * w_step, 2.8, wz * w_step))
				
		for wz in range(w_res):
			for wx in range(w_res):
				var w_idx = wx + wz * (w_res + 1)
				w_st.add_index(w_idx)
				w_st.add_index(w_idx + 1)
				w_st.add_index(w_idx + w_res + 1)
				w_st.add_index(w_idx + 1)
				w_st.add_index(w_idx + w_res + 2)
				w_st.add_index(w_idx + w_res + 1)
		
		w_st.generate_normals()
		water_mesh_data = w_st.commit()

	call_deferred("_on_thread_finished", {"mesh": st.commit(), "grass": grass_transforms, "has_water": needs_water, "water_mesh": water_mesh_data})

func _on_thread_finished(data: Dictionary):
	thread.wait_to_finish() 
	terrain_mesh_instance.mesh = data["mesh"]
	
	if grass_mesh and data["grass"].size() > 0:
		mmi = MultiMeshInstance3D.new() 
		var mm = MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = grass_mesh
		mm.instance_count = data["grass"].size() 
		mmi.multimesh = mm 
		mmi.material_override = grass_material 
		for i in range(data["grass"].size()):
			mm.set_instance_transform(i, data["grass"][i])
		add_child(mmi)
		
	if data["has_water"] and data["water_mesh"] != null:
		var water_instance = MeshInstance3D.new()
		water_instance.mesh = data["water_mesh"]
		water_instance.material_override = load("res://Materials/water_mat.tres")
		water_instance.position = Vector3.ZERO 
		add_child(water_instance)
	
	chunk_ready.emit(self)

func _exit_tree():
	if thread and thread.is_started(): thread.wait_to_finish()
