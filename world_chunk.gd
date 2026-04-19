extends Node3D
class_name WorldChunk

var chunk_pos: Vector2
var chunk_size: float
var resolution: int

var thread: Thread
var terrain_mesh_instance: MeshInstance3D

var grass_mesh: Mesh
# ПЕРЕКОНАЙСЯ, ЩО ЦЕЙ ШЛЯХ ПРАВИЛЬНИЙ ДЛЯ ТВОГО МАТЕРІАЛУ ТРАВИ
var grass_material = preload("res://Materials/grass_mat.tres") 

var noise: FastNoiseLite
var moisture: FastNoiseLite
var mountain: FastNoiseLite

signal chunk_ready(chunk_node)

func start_generation(pos: Vector2, size: float, res: int, material: Material, g_noise: FastNoiseLite, g_moist: FastNoiseLite, g_mount: FastNoiseLite, g_mesh: Mesh):
	chunk_pos = pos
	chunk_size = size
	resolution = res
	noise = g_noise 
	moisture = g_moist 
	mountain = g_mount
	grass_mesh = g_mesh # Приймаємо процедурну траву
	
	terrain_mesh_instance = MeshInstance3D.new()
	terrain_mesh_instance.material_override = material
	add_child(terrain_mesh_instance)
	
	thread = Thread.new()
	thread.start(_build_terrain_data_in_thread)

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
			
			var raw_h = noise.get_noise_2d(world_x, world_z)
			var m_raw = mountain.get_noise_2d(world_x, world_z)
			var moist = moisture.get_noise_2d(world_x, world_z)
			
			# --- ПЛАВНА МАТЕМАТИКА ВИСОТИ (Жодних обривів!) ---
			var base_h = (raw_h + 1.0) / 2.0 # від 0.0 до 1.0
			
			# pow() робить долини дуже плавними (для пляжів), а пагорби крутими
			var py = pow(base_h, 1.5) * 20.0 
			
			# Гори виростають тільки з високих пагорбів, тому обривів біля води не буде
			if m_raw > 0.0:
				var m_mult = smoothstep(0.0, 0.8, m_raw)
				py += m_mult * base_h * 180.0 
			
			st.set_color(Color(moist, 0, 0))
			st.set_uv(Vector2(float(x) / resolution, float(z) / resolution))
			st.add_vertex(Vector3(x * step, py, z * step))
			
			# Вода малюється, якщо є плавна низина
			if py < 2.8 and moist > -0.2: 
				needs_water = true
			
			# --- ЛОГІКА ТРАВИ ---
			if x < resolution and z < resolution:
				for i in range(12): # 12 травинок на квадрат = дуже густий ліс
					var gx = world_x + rng.randf() * step
					var gz = world_z + rng.randf() * step
					
					var g_raw = noise.get_noise_2d(gx, gz)
					var gm_raw = mountain.get_noise_2d(gx, gz)
					var g_moist = moisture.get_noise_2d(gx, gz)
					
					var g_base = (g_raw + 1.0) / 2.0
					var g_py = pow(g_base, 1.5) * 20.0
					if gm_raw > 0.0: g_py += smoothstep(0.0, 0.8, gm_raw) * g_base * 180.0
					
					# Саджаємо тільки вище води і там де волого
					if g_py > 3.0 and g_py < 35.0 and g_moist > 0.0: 
						var pos = Vector3(gx - offset_x, g_py, gz - offset_z)
						var basis = Basis().rotated(Vector3.UP, rng.randf() * TAU)
						basis = basis.scaled(Vector3.ONE * rng.randf_range(0.8, 1.5))
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
	var array_mesh = st.commit()
	
	call_deferred("_on_thread_finished", {"mesh": array_mesh, "grass": grass_transforms, "has_water": needs_water})

func _on_thread_finished(data: Dictionary):
	thread.wait_to_finish() 
	terrain_mesh_instance.mesh = data["mesh"]
	terrain_mesh_instance.create_trimesh_collision()
	
	# --- ФІКС ТРАВИ: ДОДАЛИ mmi.multimesh = mm ---
	if grass_mesh and data["grass"].size() > 0:
		var mmi = MultiMeshInstance3D.new()
		var mm = MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = grass_mesh
		mm.instance_count = data["grass"].size() 
		
		mmi.multimesh = mm # <--- ОСЬ ЦЕЙ МАГІЧНИЙ РЯДОК!
		mmi.material_override = grass_material 
		
		for i in range(data["grass"].size()):
			mm.set_instance_transform(i, data["grass"][i])
		add_child(mmi)
		
	if data["has_water"]:
		var water_mesh = PlaneMesh.new()
		water_mesh.size = Vector2(chunk_size, chunk_size)
		var water_instance = MeshInstance3D.new()
		water_instance.mesh = water_mesh
		water_instance.material_override = load("res://Materials/water_pro.gdshader") 
		water_instance.position = Vector3(chunk_size / 2.0, 2.8, chunk_size / 2.0) 
		add_child(water_instance)
	
	chunk_ready.emit(self)

func _exit_tree():
	if thread and thread.is_started():
		thread.wait_to_finish()
