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
var pending_kill: bool = false 
var chunk_world_offset: Vector2
var use_collision: bool = false

signal chunk_ready(chunk_node)

func _exit_tree():
	is_cancelled = true
	if task_id != -1:
		WorkerThreadPool.wait_for_task_completion(task_id)
		task_id = -1

func cancel_and_free():
	is_cancelled = true
	pending_kill = true
	hide() 

func start_generation(pos: Vector2, size: float, res: int, material: Material, g_mesh: Mesh, p_player: Node3D, p_offset: Vector2, p_col: bool = true):
	chunk_pos = pos
	chunk_size = size
	resolution = res
	grass_mesh = g_mesh
	player_ref = p_player
	chunk_world_offset = p_offset
	use_collision = p_col
	
	terrain_mesh_instance = MeshInstance3D.new()
	terrain_mesh_instance.material_override = material
	add_child(terrain_mesh_instance)
	task_id = WorkerThreadPool.add_task(_build_terrain_data_in_thread, true)

func set_lod(new_res: int, use_grass: bool, g_mesh: Mesh, p_col: bool = true):
	if resolution == new_res and use_collision == p_col: return
	if not is_ready or pending_kill: return
	is_ready = false 
	resolution = new_res
	grass_mesh = g_mesh if use_grass else null
	use_collision = p_col
	task_id = WorkerThreadPool.add_task(_build_terrain_data_in_thread, true)

func _process(_delta):
	if pending_kill:
		if task_id == -1 or WorkerThreadPool.is_task_completed(task_id):
			if task_id != -1:
				WorkerThreadPool.wait_for_task_completion(task_id)
				task_id = -1
			queue_free()
		return

	if player_ref and is_ready and mmi:
		var p_pos_2d = Vector2(player_ref.global_position.x, player_ref.global_position.z)
		var c_pos_2d = Vector2(global_position.x, global_position.z)
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
	rng.seed = hash(str(chunk_pos) + str(chunk_world_offset))
	
	var grass_data = [] 
	var needs_water = false
	
	for z in range(resolution + 1):
		if is_cancelled: return
		for x in range(resolution + 1):
			if is_cancelled: return 
			
			var local_x = x * step - (chunk_size / 2.0)
			var local_z = z * step - (chunk_size / 2.0)
			
			var wx = offset_x + local_x + chunk_world_offset.x
			var wz = offset_z + local_z + chunk_world_offset.y
			var py = Global._get_final_height(wx, wz)
			var b_data = Global.get_biome_data(wx, wz)
			
			st.set_normal(_get_normal(wx, wz))
			var col = b_data["color"]
			col.a = smoothstep(100.0, 130.0, py) 
			st.set_color(col)
			
			var is_g = 1.0 if b_data["is_grassy"] else 0.0
			st.set_uv(Vector2(is_g, 0.0))
			
			st.add_vertex(Vector3(local_x, py, local_z))
			if py < 4.9: needs_water = true
			
	for z in range(resolution):
		for x in range(resolution):
			var i = x + z * (resolution + 1)
			st.add_index(i)
			st.add_index(i + 1)
			st.add_index(i + resolution + 1)
			st.add_index(i + 1)
			st.add_index(i + resolution + 2)
			st.add_index(i + resolution + 1)
			
	if grass_mesh != null:
		var grass_density = 0.4 
		var num_grass = int(chunk_size * chunk_size * grass_density)
		for i in range(num_grass):
			if is_cancelled: return
			var lx = rng.randf_range(-chunk_size/2.0, chunk_size/2.0)
			var lz = rng.randf_range(-chunk_size/2.0, chunk_size/2.0)
			var wx = offset_x + lx + chunk_world_offset.x
			var wz = offset_z + lz + chunk_world_offset.y
			
			var py = Global._get_final_height(wx, wz)
			var b_data = Global.get_biome_data(wx, wz)
			
			if py > 4.5 and b_data["is_grassy"]:
				var norm = _get_normal(wx, wz)
				if norm.dot(Vector3.UP) > 0.85:
					var g_pos = Vector3(lx, py - 0.1, lz)
					var g_basis = Basis().rotated(Vector3.UP, rng.randf() * TAU).scaled(Vector3(2.5, rng.randf_range(1.5, 2.0), 2.5))
					
					grass_data.append({
						"transform": Transform3D(g_basis, g_pos), 
						"color": b_data["color"],
						"normal": norm # <-- МАГІЯ: Зберігаємо нормаль землі
					})
	
	var final_mesh = st.commit()
	
	var col_shape = null
	if use_collision:
		col_shape = ConcavePolygonShape3D.new()
		col_shape.set_faces(final_mesh.get_faces())
	
	var water_data = null
	if needs_water and resolution > 4:
		var w_st = SurfaceTool.new()
		w_st.begin(Mesh.PRIMITIVE_TRIANGLES)
		for wz in range(11):
			if is_cancelled: return
			for wx in range(11):
				var local_wx = wx * (chunk_size/10.0) - (chunk_size / 2.0)
				var local_wz = wz * (chunk_size/10.0) - (chunk_size / 2.0)
				var depth = Global._get_final_height(offset_x + local_wx + chunk_world_offset.x, offset_z + local_wz + chunk_world_offset.y)
				w_st.set_color(Color(smoothstep(5.0, -10.0, depth), 0, 0))
				w_st.set_uv(Vector2(float(wx) / 10.0, float(wz) / 10.0))
				w_st.add_vertex(Vector3(local_wx, 4.8, local_wz))
		for wz in range(10):
			for wx in range(10):
				var w_i = wx + wz * 11
				w_st.add_index(w_i); w_st.add_index(w_i + 1); w_st.add_index(w_i + 11)
				w_st.add_index(w_i + 1); w_st.add_index(w_i + 12); w_st.add_index(w_i + 11)
		w_st.generate_normals()
		w_st.generate_tangents()
		water_data = w_st.commit()

	if not is_cancelled:
		call_deferred("_on_thread_finished", {"mesh": final_mesh, "shape": col_shape, "grass": grass_data, "water": water_data})

func _on_thread_finished(data: Dictionary):
	if task_id != -1: 
		WorkerThreadPool.wait_for_task_completion(task_id)
		task_id = -1
		
	if is_cancelled: return
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
	if grass_mesh and data.has("grass") and data["grass"].size() > 0:
		new_mmi = MultiMeshInstance3D.new()
		var mm = MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.use_custom_data = true # МАГІЯ: Дозволяємо передачу додаткових даних
		mm.mesh = grass_mesh
		mm.instance_count = data["grass"].size()
		new_mmi.multimesh = mm
		new_mmi.material_override = grass_material
		
		for i in range(data["grass"].size()): 
			mm.set_instance_transform(i, data["grass"][i]["transform"])
			mm.set_instance_color(i, data["grass"][i]["color"])
			
			# Передаємо нормаль землі у відеокарту
			var n = data["grass"][i]["normal"]
			mm.set_instance_custom_data(i, Color(n.x, n.y, n.z, 0.0))
			
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
