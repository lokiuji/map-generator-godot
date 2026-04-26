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
var s_body_ref: StaticBody3D = null
var water_ref: MeshInstance3D = null
var is_cancelled: bool = false 

signal chunk_ready(chunk_node)

# Ця функція запобігає крашам: чекаємо завершення потоку перед видаленням
func _exit_tree():
	is_cancelled = true
	if task_id != -1:
		WorkerThreadPool.wait_for_task_completion(task_id)
		task_id = -1

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

func set_lod(new_res: int, use_grass: bool, g_mesh: Mesh):
	if resolution == new_res or not is_ready: return
	is_ready = false 
	resolution = new_res
	grass_mesh = g_mesh if use_grass else null
	task_id = WorkerThreadPool.add_task(_build_terrain_data_in_thread, true)

func _process(_delta):
	if player_ref and is_ready and mmi:
		var p_pos_2d = Vector2(player_ref.global_position.x, player_ref.global_position.z)
		var c_pos_2d = Vector2(global_position.x + chunk_size/2.0, global_position.z + chunk_size/2.0)
		
		# Збільшуємо радіус видимості трави до 300 метрів, щоб вона не зникала перед очима
		mmi.visible = p_pos_2d.distance_to(c_pos_2d) < 300.0

func _get_normal(world_x: float, world_z: float) -> Vector3:
	var d = 0.5 
	var h_l = Global._get_final_height(world_x - d, world_z)
	var h_r = Global._get_final_height(world_x + d, world_z)
	var h_d = Global._get_final_height(world_x, world_z - d)
	var h_u = Global._get_final_height(world_x, world_z + d)
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
		if is_cancelled: return
		
		for x in range(resolution + 1):
			var local_x = x * step
			var local_z = z * step
			
			var wx = offset_x + local_x
			var wz = offset_z + local_z
			var py = Global._get_final_height(wx, wz)
			var b_data = Global.get_biome_data(wx, wz)
			
			st.set_normal(_get_normal(wx, wz))
			var col = b_data["color"]
			col.a = smoothstep(100.0, 130.0, py) 
			st.set_color(col)
			st.set_uv(Vector2(float(x)/resolution, float(z)/resolution))
			st.add_vertex(Vector3(local_x, py, local_z))
			if py < 4.9: needs_water = true
			
			if grass_mesh != null and py > 4.5 and b_data["is_grassy"]:
				if _get_normal(wx, wz).dot(Vector3.UP) > 0.6:
					var u = rng.randf()
					var v = rng.randf()
					var exact_wx = offset_x + local_x + (u * step * 0.5)
					var exact_wz = offset_z + local_z + (v * step * 0.5)
					var exact_y = Global._get_final_height(exact_wx, exact_wz)
					var g_pos = Vector3(exact_wx - offset_x, exact_y - 0.1, exact_wz - offset_z)
					var g_basis = Basis().rotated(Vector3.UP, rng.randf() * TAU).scaled(Vector3(1.5, rng.randf_range(0.8, 1.2), 1.5))
					grass_transforms.append(Transform3D(g_basis, g_pos))

	for z in range(resolution):
		for x in range(resolution):
			var i = x + z * (resolution + 1)
			st.add_index(i)
			st.add_index(i + 1)
			st.add_index(i + resolution + 1)
			st.add_index(i + 1)
			st.add_index(i + resolution + 2)
			st.add_index(i + resolution + 1)
	
	var final_mesh = st.commit()
	var col_shape = ConcavePolygonShape3D.new()
	col_shape.set_faces(final_mesh.get_faces())
	
	var water_data = null
	if needs_water:
		var w_st = SurfaceTool.new()
		w_st.begin(Mesh.PRIMITIVE_TRIANGLES)
		for wz in range(11):
			if is_cancelled: return
			for wx in range(11):
				var local_wx = wx * (chunk_size/10.0)
				var local_wz = wz * (chunk_size/10.0)
				var depth = Global._get_final_height(offset_x + local_wx, offset_z + local_wz)
				w_st.set_color(Color(smoothstep(5.0, -10.0, depth), 0, 0))
				w_st.set_uv(Vector2(float(wx) / 10.0, float(wz) / 10.0))
				w_st.add_vertex(Vector3(local_wx, 4.8, local_wz))
		for wz in range(10):
			for wx in range(10):
				var w_i = wx + wz * 11
				w_st.add_index(w_i)
				w_st.add_index(w_i + 1)
				w_st.add_index(w_i + 11)
				w_st.add_index(w_i + 1)
				w_st.add_index(w_i + 12)
				w_st.add_index(w_i + 11)
		w_st.generate_normals()
		w_st.generate_tangents()
		water_data = w_st.commit()

	# КРИТИЧНИЙ РЯДОК: Повертаємо геометрію в гру
	call_deferred("_on_thread_finished", {"mesh": final_mesh, "shape": col_shape, "grass": grass_transforms, "water": water_data})

func _on_thread_finished(data: Dictionary):
	if task_id != -1: 
		WorkerThreadPool.wait_for_task_completion(task_id)
		task_id = -1
		
	if is_cancelled:
		return
		
	if data.is_empty(): return
	
	terrain_mesh_instance.mesh = data["mesh"]
	
	var new_s_body = null
	if data.get("shape"):
		new_s_body = StaticBody3D.new()
		var c_node = CollisionShape3D.new()
		c_node.shape = data["shape"]
		new_s_body.add_child(c_node)
		terrain_mesh_instance.add_child(new_s_body)
		
	var new_mmi = null
	if grass_mesh and data["grass"].size() > 0:
		new_mmi = MultiMeshInstance3D.new()
		var mm = MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = grass_mesh
		mm.instance_count = data["grass"].size()
		new_mmi.multimesh = mm
		new_mmi.material_override = grass_material
		for i in range(data["grass"].size()): mm.set_instance_transform(i, data["grass"][i])
		add_child(new_mmi)
		
	var new_water = null
	if data["water"]:
		new_water = MeshInstance3D.new()
		new_water.mesh = data["water"]
		new_water.material_override = load("res://Materials/water_mat.tres")
		add_child(new_water)
		
	if s_body_ref: s_body_ref.queue_free()
	if mmi: mmi.queue_free()
	if water_ref: water_ref.queue_free()
	
	s_body_ref = new_s_body
	mmi = new_mmi
	water_ref = new_water
	
	is_ready = true
	chunk_ready.emit(self)

func cancel_and_free():
	is_cancelled = true
	hide()
	queue_free()
