extends Node3D
class_name WorldChunk

var chunk_pos: Vector2
var chunk_size: float
var resolution: int
var moisture: FastNoiseLite

var thread: Thread
var terrain_mesh_instance: MeshInstance3D

var grass_scene = preload("res://Assets/QuaterniusNature/glTF/Grass_Common_Short.gltf")
var grass_mesh: Mesh
var grass_material = preload("res://Materials/grass_mat.tres") 

# НОВЕ: Змінна для безпечного шуму
var noise: FastNoiseLite

signal chunk_ready(chunk_node)

func start_generation(pos: Vector2, size: float, res: int, material: Material, global_noise: FastNoiseLite, global_moist: FastNoiseLite):
	chunk_pos = pos
	chunk_size = size
	resolution = res
	
	# Отримуємо готовий шум
	noise = global_noise 
	moisture = global_moist # Зберігаємо вологість
	
	if grass_scene and not grass_mesh:
		var instance = grass_scene.instantiate()
		grass_mesh = instance.get_child(0).mesh
		instance.queue_free()
	
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
	
	for z in range(resolution + 1):
		for x in range(resolution + 1):
			var world_x = offset_x + x * step
			var world_z = offset_z + z * step
			
			# Тепер це працюватиме ідеально, бо шум згенеровано правильно!
			var py = noise.get_noise_2d(world_x, world_z) * 20.0
			
			st.set_uv(Vector2(float(x) / resolution, float(z) / resolution))
			st.add_vertex(Vector3(x * step, py, z * step))
			
			if x < resolution and z < resolution:
				for i in range(12):
					var gx = world_x + rng.randf() * step
					var gz = world_z + rng.randf() * step
					
					var g_py = noise.get_noise_2d(gx, gz) * 30.0 # Висота
					var g_moist = moisture.get_noise_2d(gx, gz) # Вологість (від -1 до 1)
					
					# ПРАВИЛА БІОМІВ:
					# 1. Вище 2.0 (не у воді)
					# 2. Нижче 12.0 (не на скелях)
					# 3. Вологість > 0.1 (тільки у вологих зонах!)
					if g_py > 2.0 and g_py < 12.0 and g_moist > 0.1: 
						var pos = Vector3(gx - offset_x, g_py, gz - offset_z)
						var basis = Basis().rotated(Vector3.UP, rng.randf() * TAU)
						basis = basis.scaled(Vector3.ONE * rng.randf_range(0.8, 1.5))
						grass_transforms.append(Transform3D(basis, pos))
					
					if g_py > 1.0: 
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
	
	call_deferred("_on_thread_finished", {"mesh": array_mesh, "grass": grass_transforms})

func _on_thread_finished(data: Dictionary):
	thread.wait_to_finish() 
	
	terrain_mesh_instance.mesh = data["mesh"]
	terrain_mesh_instance.create_trimesh_collision()
	
	if grass_mesh and data["grass"].size() > 0:
		var mmi = MultiMeshInstance3D.new()
		var mm = MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.instance_count = data["grass"].size()
		mm.mesh = grass_mesh
		mmi.material_override = grass_material 
		
		for i in range(data["grass"].size()):
			mm.set_instance_transform(i, data["grass"][i])
			
		add_child(mmi)
	
	chunk_ready.emit(self)
# --- ЗАХИСТ ВІД КРАШІВ ---
# Ця функція спрацьовує, коли Світовий Менеджер вирішує видалити цей чанк (бо гравець втік далеко)
func _exit_tree():
	# Якщо потік ще працює, ми наказуємо рушію дочекатися його завершення, 
	# і тільки ПОТІМ видаляти змінні та сам чанк із пам'яті.
	if thread and thread.is_started():
		thread.wait_to_finish()
