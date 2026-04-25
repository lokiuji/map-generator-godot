extends Node3D
class_name WorldChunk

# === РОЗМІРИ СВІТУ ===
var WORLD_SIZE_METERS = 0.0

# === ШУМИ ===
var noise_continent = FastNoiseLite.new()
var noise_mountain = FastNoiseLite.new()
var noise_moisture = FastNoiseLite.new() # Для трави/пустель

var chunk_pos: Vector2
var chunk_size: float
var resolution: int
var thread: Thread
var terrain_mesh_instance: MeshInstance3D

var grass_mesh: Mesh
var grass_material = preload("res://Materials/grass_mat.tres") 

var noise: FastNoiseLite
var moisture: FastNoiseLite
var mountain: FastNoiseLite
var continent: FastNoiseLite 

var player_ref: Node3D
var mmi: MultiMeshInstance3D 

var has_collision: bool = false
var static_body_ref: StaticBody3D = null

signal chunk_ready(chunk_node)

func _ready():
	# Зчитуємо 10000.0 метрів з глобального сховища
	WORLD_SIZE_METERS = Global.WORLD_SIZE
	
	# Континенти: використовуємо сід з меню
	noise_continent.noise_type = FastNoiseLite.TYPE_SIMPLEX
	noise_continent.frequency = 0.00045 
	noise_continent.fractal_octaves = 4
	noise_continent.seed = Global.world_seed 

	# Гори: додаємо зміщення до сіда, щоб вони не повторювали форму островів
	noise_mountain.noise_type = FastNoiseLite.TYPE_SIMPLEX
	noise_mountain.frequency = 0.002
	noise_mountain.fractal_type = FastNoiseLite.FRACTAL_RIDGED 
	noise_mountain.fractal_octaves = 5
	noise_mountain.seed = Global.world_seed + 123
	
	# Вологість (для біомів/трави)
	noise_moisture.frequency = 0.0005
	noise_moisture.seed = Global.world_seed + 999

func start_generation(pos: Vector2, size: float, res: int, material: Material, 
	g_noise: FastNoiseLite, g_moist: FastNoiseLite, g_mount: FastNoiseLite, 
	g_cont: FastNoiseLite, g_mesh: Mesh, p_player: Node3D):
	
	chunk_pos = pos
	chunk_size = size
	resolution = res
	noise = g_noise 
	moisture = g_moist 
	mountain = g_mount
	continent = g_cont
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
		
		# 1. ОПТИМІЗАЦІЯ ТРАВИ (залишається як було)
		if mmi:
			mmi.visible = dist < 100.0

		# 2. ОПТИМІЗАЦІЯ ФІЗИКИ (Нове!)
		# Якщо ми близько (в сусідньому чанку) і колізії ще немає — створюємо
		if dist < 80.0 and not has_collision:
			if terrain_mesh_instance.mesh != null:
				terrain_mesh_instance.create_trimesh_collision()
				has_collision = true
				# Знаходимо створений StaticBody3D, щоб потім його видалити
				for child in terrain_mesh_instance.get_children():
					if child is StaticBody3D:
						static_body_ref = child
						break
						
		# Якщо ми відійшли далеко і колізія є — видаляємо її для економії пам'яті
		elif dist > 100.0 and has_collision:
			if static_body_ref:
				static_body_ref.queue_free()
				static_body_ref = null
			has_collision = false

# --- Спільна функція висоти з ЕКСКАВАТОРОМ БІОМІВ ---
func _get_h(world_x: float, world_z: float) -> float:
	var logic_x = wrapf(world_x, 0.0, WORLD_SIZE_METERS)
	var logic_z = wrapf(world_z, 0.0, WORLD_SIZE_METERS)

	var center = WORLD_SIZE_METERS / 2.0
	var dist_from_center = Vector2(logic_x, logic_z).distance_to(Vector2(center, center))
	
	# МАСКА КРАЇВ: Тепер вона починає топити землю лише біля самого кордону (від 70% радіуса)
	# Це дозволить континентам генеруватися вільно і не бути єдиною плямою по центру
	var edge_falloff = smoothstep(center * 0.7, center * 0.98, dist_from_center)

	var cont_val = noise_continent.get_noise_2d(logic_x, logic_z)
	# Віднімаємо значення маски на краях, щоб змусити там згенеруватися океан
	cont_val = cont_val - edge_falloff * 2.0 

	var base_height = 0.0
	if cont_val < 0.0:
		base_height = cont_val * 40.0 # Глибина океану
	else:
		# ФІКС БЕРЕГІВ: pow(cont_val, 1.4) робить пляжі дуже пологими, а материк плавно піднімається
		base_height = pow(cont_val, 1.4) * 130.0

	var mount_val = noise_mountain.get_noise_2d(logic_x, logic_z)
	
	# ФІКС БУРУЛЬОК ТА ПРОВАЛІВ: Відкидаємо від'ємні значення (гори йдуть лише вгору)
	mount_val = max(0.0, mount_val)

	# Маска гір робить їх більш природними і лише в глибині суші
	var mountain_mask = smoothstep(0.1, 0.4, cont_val)
	var final_mountain_height = mount_val * 400.0 * mountain_mask 

	return 2.8 + base_height + final_mountain_height
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
	
	# === ГЕНЕРАЦІЯ ЗЕМЛІ ТА ТРАВИ ===
	for z in range(resolution + 1):
		for x in range(resolution + 1):
			var world_x = offset_x + x * step
			var world_z = offset_z + z * step
			
			var logic_x = wrapf(world_x, 0.0, WORLD_SIZE_METERS)
			var logic_z = wrapf(world_z, 0.0, WORLD_SIZE_METERS)
			
			var py = _get_h(world_x, world_z)
			var moist = moisture.get_noise_2d(logic_x, logic_z)
			var cell_cont = continent.get_noise_2d(logic_x, logic_z)

			st.set_color(Color(moist, 0, 0))
			st.set_uv(Vector2(float(x) / resolution, float(z) / resolution))
			st.add_vertex(Vector3(x * step, py, z * step))
			if py < 2.9: needs_water = true
			
			if x < resolution and z < resolution:
				var h00 = py 
				var h10 = _get_h(world_x + step, world_z)
				var h01 = _get_h(world_x, world_z + step)
				var h11 = _get_h(world_x + step, world_z + step)
				
				if py > 0.3 and moist > -0.3:
					var density = 5
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
							if g_py > 3.2 and g_py < 180.0: 
								var pos = Vector3(gx - offset_x, g_py, gz - offset_z)
								var s_xz = rng.randf_range(1.5, 2.5) 
								var s_y = rng.randf_range(1.0, 1.5)  
								var basis = Basis().rotated(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s_xz, s_y, s_xz))
								grass_transforms.append(Transform3D(basis, pos))
			
	for z in range(resolution):
		for x in range(resolution):
			var i = x + z * (resolution + 1)
			st.add_index(i)
			st.add_index(i + 1)
			st.add_index(i + resolution + 1)
			st.add_index(i + 1)
			st.add_index(i + resolution + 2)
			st.add_index(i + resolution + 1)
	st.generate_normals()
	
	# === НОВЕ: ГЕНЕРАЦІЯ "РОЗУМНОЇ" ВОДИ ===
	var water_mesh_data = null
	if needs_water:
		var w_st = SurfaceTool.new()
		w_st.begin(Mesh.PRIMITIVE_TRIANGLES)
		var w_res = 15 # Деталізація сітки води
		var w_step = chunk_size / w_res
		
		for wz in range(w_res + 1):
			for wx in range(w_res + 1):
				var world_wx = offset_x + wx * w_step
				var world_wz = offset_z + wz * w_step
				
				var logic_wx = wrapf(world_wx, 0.0, WORLD_SIZE_METERS)
				var logic_wz = wrapf(world_wz, 0.0, WORLD_SIZE_METERS)
				
				# 1. Читаємо шум континентів у цій точці
				var w_c_raw = continent.get_noise_2d(logic_wx, logic_wz)
				
				# 2. МАСКА БІОМІВ
				var wave_mask = smoothstep(-0.10, -0.30, w_c_raw)
				
				# 3. Записуємо маску в червоний канал кольору вершини (COLOR.r)
				w_st.set_color(Color(wave_mask, 0, 0))
				w_st.set_uv(Vector2(float(wx) / w_res, float(wz) / w_res))
				# Вода генерується вже в правильних координатах чанка
				w_st.add_vertex(Vector3(wx * w_step, 2.8, wz * w_step))
				
		for wz in range(w_res):
			for wx in range(w_res):
				var i = wx + wz * (w_res + 1)
				w_st.add_index(i)
				w_st.add_index(i + 1)
				w_st.add_index(i + w_res + 1)
				w_st.add_index(i + 1)
				w_st.add_index(i + w_res + 2)
				w_st.add_index(i + w_res + 1)
		w_st.generate_normals()
		water_mesh_data = w_st.commit()

	call_deferred("_on_thread_finished", {"mesh": st.commit(), "grass": grass_transforms, "has_water": needs_water, "water_mesh": water_mesh_data})

func _on_thread_finished(data: Dictionary):
	thread.wait_to_finish() 
	terrain_mesh_instance.mesh = data["mesh"]
	#terrain_mesh_instance.create_trimesh_collision()
	
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
		
	# === ВСТАНОВЛЮЄМО НАШУ НОВУ ВОДУ ===
	if data["has_water"] and data["water_mesh"] != null:
		var water_instance = MeshInstance3D.new()
		water_instance.mesh = data["water_mesh"]
		water_instance.material_override = load("res://Materials/water_mat.tres")
		# Позиція (0,0,0), бо ми згенерували вершини в точних координатах вище
		water_instance.position = Vector3.ZERO 
		add_child(water_instance)
	
	chunk_ready.emit(self)

func _exit_tree():
	if thread and thread.is_started(): thread.wait_to_finish()
