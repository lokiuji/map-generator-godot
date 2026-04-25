extends Node3D
class_name WorldChunk

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

		if dist > 150.0 and has_collision:
			if static_body_ref:
				static_body_ref.queue_free()
				static_body_ref = null
			has_collision = false

# НОВА ЛОГІКА КУТАСТИХ ГІР
func _get_h(world_x: float, world_z: float) -> float:
	var b_data = Global.get_biome_data(world_x, world_z)
	var e = b_data["elevation"]
	
	var base_height = 0.0
	if e < 0.4:
		# Океан (все що нижче 0.4)
		base_height = (e - 0.4) * 80.0 
	else:
		# Суша
		var land_e = e - 0.4
		var plains = land_e * 200.0 # Пологі рівнини та ліси
		
		# Маска гір: починаємо піднімати гострі скелі там, де висота більша за 0.55
		var mount_mask = smoothstep(0.55, 0.85, e)
		
		# Отримуємо гострі хребти з нашого RIDGED шуму
		var sharp_peaks = Global.mountain_noise.get_noise_2d(world_x, world_z) * 1200.0
		
		base_height = plains + (sharp_peaks * mount_mask)
		
	var micro = Global.detail_noise.get_noise_2d(world_x, world_z) * 5.0
	return 5.0 + base_height + micro

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
			var b_data = Global.get_biome_data(world_x, world_z)
			
			var exact_normal = _get_normal(world_x, world_z)
			st.set_normal(exact_normal)
			
			var vert_color = b_data["color"]
			var e = b_data["elevation"]
			var snow_weight = 0.0
			if e > 0.7: snow_weight = clamp((e - 0.7) / 0.1, 0.0, 1.0)
			vert_color.a = snow_weight
			
			st.set_color(vert_color)
			st.set_uv(Vector2(float(x) / resolution, float(z) / resolution))
			st.add_vertex(Vector3(x * step, py, z * step))
			
			if py < 4.9: needs_water = true
			
			if x < resolution and z < resolution:
				var h00 = py 
				var h10 = _get_h(world_x + step, world_z)
				var h01 = _get_h(world_x, world_z + step)
				var h11 = _get_h(world_x + step, world_z + step)
				
				if py > 5.5 and b_data["is_grassy"]:
					var cell_normal = _get_normal(world_x + step/2.0, world_z + step/2.0)
					if (1.0 - cell_normal.dot(Vector3.UP)) < 0.25: 
						var density = 5
						for gx_idx in range(density):
							for gz_idx in range(density):
								var local_x = (gx_idx + rng.randf()) / float(density)
								var local_z = (gz_idx + rng.randf()) / float(density)
								var grass_x = world_x + local_x * step
								var grass_z = world_z + local_z * step
								
								var g_py = 0.0
								if local_x + local_z <= 1.0: 
									g_py = h00 + local_x * (h10 - h00) + local_z * (h01 - h00)
								else:
									var nx = 1.0 - local_x
									var nz = 1.0 - local_z
									g_py = h11 + nx * (h01 - h11) + nz * (h10 - h11)
									
								g_py -= 0.1 
								if g_py > 5.5 and e < 0.65: 
									var pos = Vector3(grass_x - offset_x, g_py, grass_z - offset_z)
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
				var depth = _get_h(world_wx, world_wz)
				var wave_mask = smoothstep(5.0, -20.0, depth)
				w_st.set_color(Color(wave_mask, 0, 0))
				w_st.set_uv(Vector2(float(wx) / w_res, float(wz) / w_res))
				w_st.add_vertex(Vector3(wx * w_step, 4.8, wz * w_step))
				
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
	
	# === ФІКС ПРОВАЛЮВАННЯ: СТВОРЮЄМО КОЛІЗІЮ МИТТЄВО ДЛЯ ГРАВЦЯ ===
	if player_ref and global_position.distance_to(player_ref.global_position) < 150.0:
		_create_collision_now()
	
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

func _create_collision_now():
	if not has_collision and terrain_mesh_instance.mesh != null:
		terrain_mesh_instance.create_trimesh_collision()
		has_collision = true
		for child in terrain_mesh_instance.get_children():
			if child is StaticBody3D:
				static_body_ref = child
				break

func _exit_tree():
	if thread and thread.is_started(): thread.wait_to_finish()
