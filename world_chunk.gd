extends Node3D
class_name WorldChunk
# === РОЗМІРИ СВІТУ ===
const WORLD_CHUNKS = 50
const CHUNK_SIZE = 120.0
const WORLD_SIZE_METERS = WORLD_CHUNKS * CHUNK_SIZE # 6000.0 метрів

# === ШУМИ ===
var noise_continent = FastNoiseLite.new()
var noise_mountain = FastNoiseLite.new()
var noise_moisture = FastNoiseLite.new() # Для трави/пустель (якщо в тебе він був)

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

func _ready():
	# 1. КОНТИНЕНТИ: Частота 0.0005 дає приблизно 5-9 великих об'єктів на 6км
	noise_continent.noise_type = FastNoiseLite.TYPE_SIMPLEX
	noise_continent.frequency = 0.0005 
	noise_continent.fractal_octaves = 4

	# 2. ГОРИ: Робимо їх дуже високими, але рідкісними
	noise_mountain.noise_type = FastNoiseLite.TYPE_SIMPLEX
	noise_mountain.frequency = 0.002
	noise_mountain.fractal_type = FastNoiseLite.FRACTAL_RIDGED # Виправлено друкарську помилку
	noise_mountain.fractal_octaves = 5
	
	# Вологість (для біомів)
	noise_moisture.frequency = 0.0005
	noise_moisture.seed = 999

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
# --- Спільна функція висоти з ЕКСКАВАТОРОМ БІОМІВ ---

func _get_h(world_x: float, world_z: float) -> float:
	# === 1. МАГІЯ ЗГОРТАННЯ КООРДИНАТ (Wraparound) ===
	# Координати завжди залишаються в межах від 0 до 6000
	var logic_x = wrapf(world_x, 0.0, WORLD_SIZE_METERS)
	var logic_z = wrapf(world_z, 0.0, WORLD_SIZE_METERS)

	# === 2. РАДІАЛЬНА МАСКА (КРАЙ СВІТУ = ОКЕАН) ===
	var center = WORLD_SIZE_METERS / 2.0
	var dist_from_center = Vector2(logic_x, logic_z).distance_to(Vector2(center, center))
	
	# Світ почне тонути в океані, коли гравець пройде 65% шляху від центру до краю
	var edge_falloff = 1.0 - smoothstep(center * 0.65, center * 0.95, dist_from_center)

	# === 3. ФОРМУВАННЯ КОНТИНЕНТІВ ===
	var cont_val = noise_continent.get_noise_2d(logic_x, logic_z)
	
	# Примусово "тягнемо" висоту на дно океану (-1.0) біля країв світу
	cont_val = lerp(-1.0, cont_val, edge_falloff) 
	var base_height = cont_val * 120.0

	# === 4. ГІРСЬКІ ХРЕБТИ ===
	var mount_val = noise_mountain.get_noise_2d(logic_x, logic_z)
	
	# Маска: Гори ростуть ТІЛЬКИ на суші (де cont_val > 0.0).
	var mountain_mask = smoothstep(0.15, 0.45, cont_val)
	# Гори будуть величними: до 500 метрів у висоту
	var final_mountain_height = mount_val * 600.0 * mountain_mask 

	# === 5. ФІНАЛЬНИЙ РЕЛЬЄФ ТА "ЕКСКАВАТОР" ===
	var water_level = 2.8
	var final_y = water_level + base_height + final_mountain_height

	if final_y < water_level:
		# Фізично копаємо глибокі океанські западини (до -40 метрів)
		# Це необхідно для роботи шейдера води з ефектом глибини (Beer's Law)
		var dig = smoothstep(water_level, water_level - 15.0, final_y)
		final_y = lerp(final_y, water_level - 40.0, dig)

	return final_y

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
			var py = _get_h(world_x, world_z)
			var moist = moisture.get_noise_2d(world_x, world_z)
			var cell_cont = continent.get_noise_2d(world_x, world_z)

			st.set_color(Color(moist, 0, 0))
			st.set_uv(Vector2(float(x) / resolution, float(z) / resolution))
			st.add_vertex(Vector3(x * step, py, z * step))
			if py < 2.9: needs_water = true
			
			if x < resolution and z < resolution:
				var h00 = py 
				var h10 = _get_h(world_x + step, world_z)
				var h01 = _get_h(world_x, world_z + step)
				var h11 = _get_h(world_x + step, world_z + step)
				
				if cell_cont > -0.2 and moist > -0.15:
					var density = 11 
					for gx_idx in range(density):
						for gz_idx in range(density):
							var local_x = (gx_idx + rng.randf()) / float(density)
							var local_z = (gz_idx + rng.randf()) / float(density)
							var gx = world_x + local_x * step
							var gz = world_z + local_z * step
							var g_py = 0.0
							
							if local_x + local_z <= 1.0: g_py = h00 + local_x * (h10 - h00) + local_z * (h01 - h00)
							else:
								var nx = 1.0 - local_x; var nz = 1.0 - local_z
								g_py = h11 + nx * (h01 - h11) + nz * (h10 - h11)
								
							g_py -= 0.1 
							if g_py > 3.2 and g_py < 40.0: 
								var pos = Vector3(gx - offset_x, g_py, gz - offset_z)
								var s_xz = rng.randf_range(1.5, 2.5) 
								var s_y = rng.randf_range(1.0, 1.5)  
								var basis = Basis().rotated(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s_xz, s_y, s_xz))
								grass_transforms.append(Transform3D(basis, pos))
			
	for z in range(resolution):
		for x in range(resolution):
			var i = x + z * (resolution + 1)
			st.add_index(i); st.add_index(i + 1); st.add_index(i + resolution + 1)
			st.add_index(i + 1); st.add_index(i + resolution + 2); st.add_index(i + resolution + 1)
	st.generate_normals()
	
	# === НОВЕ: ГЕНЕРАЦІЯ "РОЗУМНОЇ" ВОДИ ===
	var water_mesh_data = null
	if needs_water:
		var w_st = SurfaceTool.new()
		w_st.begin(Mesh.PRIMITIVE_TRIANGLES)
		var w_res = 30 # Деталізація сітки води
		var w_step = chunk_size / w_res
		
		for wz in range(w_res + 1):
			for wx in range(w_res + 1):
				var world_wx = offset_x + wx * w_step
				var world_wz = offset_z + wz * w_step
				
				# 1. Читаємо шум континентів у цій точці
				var w_c_raw = continent.get_noise_2d(world_wx, world_wz)
				
				# 2. МАСКА БІОМІВ: 
				# Якщо c_raw = -0.3 (Глибокий океан) -> wave_mask = 1.0 (Максимальні хвилі)
				# Якщо c_raw = -0.1 (Близько до берега) або більше (Озера) -> wave_mask = 0.0 (Гладка вода)
				var wave_mask = smoothstep(-0.10, -0.30, w_c_raw)
				
				# 3. Записуємо маску в червоний канал кольору вершини (COLOR.r)
				w_st.set_color(Color(wave_mask, 0, 0))
				w_st.set_uv(Vector2(float(wx) / w_res, float(wz) / w_res))
				# Вода генерується вже в правильних координатах чанка, тому без зміщень
				w_st.add_vertex(Vector3(wx * w_step, 2.8, wz * w_step))
				
		for wz in range(w_res):
			for wx in range(w_res):
				var i = wx + wz * (w_res + 1)
				w_st.add_index(i); w_st.add_index(i + 1); w_st.add_index(i + w_res + 1)
				w_st.add_index(i + 1); w_st.add_index(i + w_res + 2); w_st.add_index(i + w_res + 1)
		w_st.generate_normals()
		water_mesh_data = w_st.commit()

	call_deferred("_on_thread_finished", {"mesh": st.commit(), "grass": grass_transforms, "has_water": needs_water, "water_mesh": water_mesh_data})

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
