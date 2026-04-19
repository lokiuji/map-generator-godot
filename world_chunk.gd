extends Node3D
class_name WorldChunk

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

signal chunk_ready(chunk_node)

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
	if mmi and player_ref:
		var dist = global_position.distance_to(player_ref.global_position)
		mmi.visible = dist < 160.0

# --- СПІЛЬНА ФУНКЦІЯ ВИСОТИ ---
func _get_h(nx: float, nz: float) -> float:
	var h_raw = noise.get_noise_2d(nx, nz)
	var c_raw = continent.get_noise_2d(nx, nz) 
	if c_raw < -0.2: 
		return lerp(-40.0, 2.8, (c_raw + 1.0) / 0.8)
	
	var m_raw = mountain.get_noise_2d(nx, nz)
	var inland_blend = smoothstep(-0.2, 0.1, c_raw)
	var base_h = (h_raw + 1.0) / 2.0
	var terrain_h = pow(base_h, 1.5) * 35.0
	var mount_h = smoothstep(0.1, 0.8, m_raw) * inland_blend * 200.0
	return 2.8 + (terrain_h + mount_h) * inland_blend

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
			var moist = moisture.get_noise_2d(world_x, world_z)

			st.set_color(Color(moist, 0, 0))
			st.set_uv(Vector2(float(x) / resolution, float(z) / resolution))
			st.add_vertex(Vector3(x * step, py, z * step))
			if py < 2.9: needs_water = true
			
			# === ІДЕАЛЬНА ЛОГІКА ТРАВИ (БЕЗ ЛИСИН І ПОЛЬОТІВ) ===
			if x < resolution and z < resolution:
				var h00 = py 
				var h10 = _get_h(world_x + step, world_z)
				var h01 = _get_h(world_x, world_z + step)
				var h11 = _get_h(world_x + step, world_z + step)
				
				var cell_cont = continent.get_noise_2d(world_x, world_z)
				
				if cell_cont > -0.2 and moist > -0.15:
					# ВДВІЧІ МЕНШЕ ТРАВИ: було 12 (144 кущі), тепер 8 (64 кущі)
					var density = 8 
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
							
							if g_py > 3.2 and g_py < 40.0: 
								var pos = Vector3(gx - offset_x, g_py, gz - offset_z)
								
								# ПРОПОРЦІЙНИЙ МАСШТАБ: Робимо кущі значно вужчими, щоб текстура не "пливла"
								var s_xz = rng.randf_range(1.5, 2.5) # Було 4.0 - 6.0
								var s_y = rng.randf_range(1.0, 1.5)  # Висота
								
								var basis = Basis().rotated(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s_xz, s_y, s_xz))
								grass_transforms.append(Transform3D(basis, pos))
			
	for z in range(resolution):
		for x in range(resolution):
			var i = x + z * (resolution + 1)
			st.add_index(i); st.add_index(i + 1); st.add_index(i + resolution + 1)
			st.add_index(i + 1); st.add_index(i + resolution + 2); st.add_index(i + resolution + 1)
			
	st.generate_normals()
	call_deferred("_on_thread_finished", {"mesh": st.commit(), "grass": grass_transforms, "has_water": needs_water})

func _on_thread_finished(data: Dictionary):
	thread.wait_to_finish() 
	terrain_mesh_instance.mesh = data["mesh"]
	terrain_mesh_instance.create_trimesh_collision()
	
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
	if thread and thread.is_started(): thread.wait_to_finish()
