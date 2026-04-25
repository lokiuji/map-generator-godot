extends Node3D
class_name WorldChunk

var is_ready: bool = false
var chunk_pos: Vector2
var chunk_size: float
var resolution: int
var task_id: int = -1
var terrain_mesh_instance: MeshInstance3D

var grass_mesh: Mesh
var grass_material = preload("res://Materials/grass_mat.tres") 

var player_ref: Node3D
var mmi: MultiMeshInstance3D 
var has_collision: bool = false
var static_body_ref: StaticBody3D = null
var is_cancelled: bool = false 
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
	
	task_id = WorkerThreadPool.add_task(_build_terrain_data_in_thread, true)

func _process(_delta):
	if player_ref and is_ready:
		var dist = global_position.distance_to(player_ref.global_position)
		if mmi: mmi.visible = dist < 100.0

func _get_h(world_x: float, world_z: float) -> float:
	var e = Global.get_raw_elevation(world_x, world_z)
	if e < 0.35: return 5.0 + (e - 0.35) * 40.0
	var land_base = pow(e - 0.35, 1.2) * 150.0
	var ridge_mask = smoothstep(0.4, 0.85, e)
	var peaks = Global.mountain_noise.get_noise_2d(world_x, world_z) * 180.0 
	return 5.0 + land_base + (peaks * ridge_mask)

func _get_normal(world_x: float, world_z: float) -> Vector3:
	var d = 0.5 
	var h_l = _get_h(world_x - d, world_z)
	var h_r = _get_h(world_x + d, world_z)
	var h_d = _get_h(world_x, world_z - d)
	var h_u = _get_h(world_x, world_z + d)
	return Vector3(h_l - h_r, 2.0 * d, h_d - h_u).normalized()

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
		if is_cancelled: 
			call_deferred("_on_thread_finished", {})
			return
		for x in range(resolution + 1):
			var wx = offset_x + x * step
			var wz = offset_z + z * step
			var py = _get_h(wx, wz)
			var b_data = Global.get_biome_data(wx, wz)
			
			st.set_normal(_get_normal(wx, wz))
			var col = b_data["color"]
			
			# ДОДАЄМО ЦЕ: Обчислюємо сніг залежно від висоти гір!
			# Якщо висота (py) менша за 100 - снігу нема (0.0).
			# Якщо висота від 100 до 130 - сніг плавно з'являється.
			col.a = smoothstep(100.0, 130.0, py) 
			
			st.set_color(col)
			st.set_uv(Vector2(float(x)/resolution, float(z)/resolution))
			st.set_color(col)
			st.set_uv(Vector2(float(x)/resolution, float(z)/resolution))
			st.add_vertex(Vector3(x * step, py, z * step))
			if py < 4.9: needs_water = true
			
			if x < resolution and z < resolution and py > 5.5 and b_data["is_grassy"]:
				var cell_n = _get_normal(wx + step/2.0, wz + step/2.0)
				# 0.85 = спавн тільки на відносно плоских поверхнях
				if cell_n.dot(Vector3.UP) > 0.85:
					
					# 1. Беремо висоту 4 кутів конкретної клітинки мешу
					var h00 = py
					var h10 = _get_h(wx + step, wz)
					var h01 = _get_h(wx, wz + step)
					var h11 = _get_h(wx + step, wz + step)
					
					for i in range(8): # Кількість травинок
						# Генеруємо нормалізовані координати всередині клітинки (від 0 до 1)
						var u = rng.randf()
						var v = rng.randf()
						# 2. Вираховуємо ТОЧНУ висоту на поверхні утворених трикутників
						var exact_y = 0.0
						if u + v <= 1.0:
							# Трава потрапила на перший трикутник клітинки
							exact_y = h00 + (h10 - h00) * u + (h01 - h00) * v
						else:
							# Трава потрапила на другий трикутник клітинки
							exact_y = h11 + (h01 - h11) * (1.0 - u) + (h10 - h11) * (1.0 - v)
						# Додаємо мінімальний зсув (-0.1), просто щоб корінь точно ввійшов у текстуру землі
						var g_pos = Vector3(x * step + (u * step), exact_y - 0.1, z * step + (v * step))
						var g_basis = Basis().rotated(Vector3.UP, rng.randf() * TAU).scaled(Vector3(1.5, rng.randf_range(0.8, 1.2), 1.5))
						grass_transforms.append(Transform3D(g_basis, g_pos))

	for z in range(resolution):
		for x in range(resolution):
			var i = x + z * (resolution + 1)
			st.add_index(i); st.add_index(i + 1); st.add_index(i + resolution + 1)
			st.add_index(i + 1); st.add_index(i + resolution + 2); st.add_index(i + resolution + 1)
	
	var final_mesh = st.commit()
	var col_shape = ConcavePolygonShape3D.new()
	col_shape.set_faces(final_mesh.get_faces())
	
	var water_data = null
	if needs_water:
		var w_st = SurfaceTool.new()
		w_st.begin(Mesh.PRIMITIVE_TRIANGLES)
		for wz in range(11):
			if is_cancelled: 
				call_deferred("_on_thread_finished", {})
				return
			for wx in range(11):
				var depth = _get_h(offset_x + wx*(chunk_size/10.0), offset_z + wz*(chunk_size/10.0))
				w_st.set_color(Color(smoothstep(5.0, -10.0, depth), 0, 0))
				
				# ДОДАЄМО ЦЕЙ РЯДОК: Задаємо правильні UV-координати для поверхні води
				w_st.set_uv(Vector2(float(wx) / 10.0, float(wz) / 10.0))
				
				w_st.add_vertex(Vector3(wx*(chunk_size/10.0), 4.8, wz*(chunk_size/10.0)))
		for wz in range(10):
			for wx in range(10):
				var w_i = wx + wz * 11
				w_st.add_index(w_i); w_st.add_index(w_i + 1); w_st.add_index(w_i + 11)
				w_st.add_index(w_i + 1); w_st.add_index(w_i + 12); w_st.add_index(w_i + 11)
				
		# ДОДАЙ ОСЬ ЦІ ДВА РЯДКИ:
		w_st.generate_normals()
		w_st.generate_tangents()
		
		water_data = w_st.commit()

	call_deferred("_on_thread_finished", {"mesh": final_mesh, "shape": col_shape, "grass": grass_transforms, "water": water_data})

func _on_thread_finished(data: Dictionary):
	if task_id != -1: 
		WorkerThreadPool.wait_for_task_completion(task_id)
		task_id = -1
	if is_cancelled:
		queue_free()
		return
	
	if data.is_empty(): return
	
	terrain_mesh_instance.mesh = data["mesh"]
	var s_body = StaticBody3D.new()
	var c_node = CollisionShape3D.new()
	c_node.shape = data["shape"]
	s_body.add_child(c_node)
	terrain_mesh_instance.add_child(s_body)
	
	if grass_mesh and data["grass"].size() > 0:
		mmi = MultiMeshInstance3D.new()
		var mm = MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = grass_mesh
		mm.instance_count = data["grass"].size()
		mmi.multimesh = mm
		mmi.material_override = grass_material
		for i in range(data["grass"].size()): mm.set_instance_transform(i, data["grass"][i])
		add_child(mmi)
	
	if data["water"]:
		var w_inst = MeshInstance3D.new()
		w_inst.mesh = data["water"]
		w_inst.material_override = load("res://Materials/water_mat.tres")
		add_child(w_inst)
	
	is_ready = true
	chunk_ready.emit(self)

func cancel_and_free():
	is_cancelled = true
	hide()
