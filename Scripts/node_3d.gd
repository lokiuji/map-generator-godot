extends Node3D

var chunk_scene = preload("res://world_chunk.tscn")

const CHUNK_SIZE = 120.0
const RENDER_DISTANCE = 4
const HEIGHT_SCALE = 150.0
const WATER_LEVEL = -20.0

@export var biomes: Array[BiomeData]
@export var leaf_texture: Texture2D 
@export var grass_texture: Texture2D 
@export var billboard_tree_texture: Texture2D

var height_noise = FastNoiseLite.new()
var temperature_noise = FastNoiseLite.new()
var moisture_noise = FastNoiseLite.new()

var active_chunks = {}
var loading_chunks = {}
var chunk_cache = {}
var current_player_chunk = Vector2()

var shared_water_material: ShaderMaterial
var shared_terrain_material: ShaderMaterial 

var biome_meshes = {} 
var procedural_tree_mesh: ArrayMesh
var shared_low_poly_tree: QuadMesh

var biome_dropdown: OptionButton

func _ready():
	height_noise.noise_type = FastNoiseLite.TYPE_PERLIN
	height_noise.seed = 777
	height_noise.fractal_octaves = 4
	height_noise.frequency = 0.002

	temperature_noise.noise_type = FastNoiseLite.TYPE_PERLIN
	temperature_noise.seed = 888
	temperature_noise.frequency = 0.001

	moisture_noise.noise_type = FastNoiseLite.TYPE_PERLIN
	moisture_noise.seed = 999
	moisture_noise.frequency = 0.001

	_setup_materials()
	_generate_anime_tree_mesh()
	_create_shared_lod_mesh() # Створюємо LOD меш один раз!
	_setup_biome_meshes() 
	_create_biome_ui()

	var spawn_pos = find_spawn_point(biomes[0] if biomes.size() > 0 else null)
	if has_node("Player"):
		$Player.global_position = spawn_pos
	
	current_player_chunk = Vector2(floor(spawn_pos.x / CHUNK_SIZE), floor(spawn_pos.z / CHUNK_SIZE))
	update_chunks(current_player_chunk)

func _process(_delta):
	if not has_node("Player"): return
	var p_x = floor($Player.global_position.x / CHUNK_SIZE)
	var p_z = floor($Player.global_position.z / CHUNK_SIZE)
	var player_chunk = Vector2(p_x, p_z)
	
	if player_chunk != current_player_chunk:
		current_player_chunk = player_chunk
		update_chunks(current_player_chunk)

# ==========================================
# РОЗПАКОВКА ТА ГЕНЕРАЦІЯ МЕШІВ
# ==========================================
func _create_shared_lod_mesh():
	shared_low_poly_tree = QuadMesh.new()
	shared_low_poly_tree.size = Vector2(12.0, 16.0) # Оптимальний розмір
	shared_low_poly_tree.center_offset = Vector3(0, 8.0, 0) 

	var mat = StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR # Scissor - найшвидший
	mat.alpha_scissor_threshold = 0.5
	mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_OPAQUE_ONLY # ВИПРАВЛЯЄ ПРОСВІЧУВАННЯ
	
	if billboard_tree_texture:
		mat.albedo_texture = billboard_tree_texture
	
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
	mat.billboard_keep_scale = true
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_PER_VERTEX # Рятує FPS на слабких картах
	
	shared_low_poly_tree.material = mat
		
	# НОВЕ: Дерево завжди стоїть рівно відносно землі, повертається тільки по осі Y!
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y 
	mat.billboard_keep_scale = true 
	mat.roughness = 1.0 
	mat.specular = 0.0

	shared_low_poly_tree.material = mat
	
func _setup_biome_meshes():
	for b in biomes:
		if b == null: continue
		biome_meshes[b.biome_name] = {
			"grass": _extract_mesh_array(b.grass_scenes),
			"flowers": _extract_mesh_array(b.flower_scenes),
			"mushrooms": _extract_mesh_array(b.mushroom_scenes),
			"trees": _extract_mesh_array(b.tree_scenes)
		}
		
		# --- ПОВНИЙ КОНТРОЛЬ НАШОГО ДЕРЕВА ---
		# Воно додається в масив дерев ТІЛЬКИ якщо ти поставив галочку в біомі
		if "use_procedural_tree" in b and b.use_procedural_tree == true:
			if procedural_tree_mesh != null:
				biome_meshes[b.biome_name]["trees"].append(procedural_tree_mesh)

func _extract_mesh_array(scenes: Array[PackedScene]) -> Array[Mesh]:
	var meshes: Array[Mesh] = []
	for s in scenes:
		if s:
			var instance = s.instantiate()
			var m = _find_first_mesh(instance)
			if m: meshes.append(m)
			instance.queue_free()
	return meshes

func _find_first_mesh(node: Node) -> Mesh:
	if node is MeshInstance3D: return node.mesh
	for child in node.get_children():
		var found = _find_first_mesh(child)
		if found: return found
	return null

func _generate_anime_tree_mesh():
	procedural_tree_mesh = ArrayMesh.new()
	var st = SurfaceTool.new()
	
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var trunk_h = 8.0
	var trunk_r = 0.5
	for i in range(6):
		var a1 = (float(i)/6.0) * TAU
		var a2 = (float(i+1)/6.0) * TAU
		var p1 = Vector3(cos(a1)*trunk_r, 0, sin(a1)*trunk_r)
		var p2 = Vector3(cos(a2)*trunk_r, 0, sin(a2)*trunk_r)
		var p3 = Vector3(cos(a1)*trunk_r*0.4, trunk_h, sin(a1)*trunk_r*0.4)
		var p4 = Vector3(cos(a2)*trunk_r*0.4, trunk_h, sin(a2)*trunk_r*0.4)
		
		st.set_color(Color(0.35, 0.2, 0.1)) 
		var norm = (p1+p2).normalized()
		st.set_normal(norm); st.add_vertex(p1)
		st.set_normal(norm); st.add_vertex(p2)
		st.set_normal(norm); st.add_vertex(p3)
		st.set_normal(norm); st.add_vertex(p2)
		st.set_normal(norm); st.add_vertex(p4)
		st.set_normal(norm); st.add_vertex(p3)
	st.commit(procedural_tree_mesh)

	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var canopy_center = Vector3(0, trunk_h * 1.2, 0) 
	var leaf_count = 60
	for j in range(leaf_count): 
		var dir = Vector3(randf_range(-1,1), randf_range(0.0, 1.0), randf_range(-1,1)).normalized()
		var dist_factor = randf()
		var pos = canopy_center + dir * (1.5 + dist_factor * 3.5)
		var s = randf_range(3.5, 5.5)
		
		st.set_color(Color(dist_factor, 1.0, 0.0)) 
		var norm = (pos - canopy_center).normalized()
		st.set_normal(norm)
		
		st.set_uv(Vector2(0,0)); st.set_uv2(Vector2(-s, s));  st.add_vertex(pos)
		st.set_uv(Vector2(1,0)); st.set_uv2(Vector2(s, s));   st.add_vertex(pos)
		st.set_uv(Vector2(1,1)); st.set_uv2(Vector2(s, -s));  st.add_vertex(pos)
		st.set_uv(Vector2(0,0)); st.set_uv2(Vector2(-s, s));  st.add_vertex(pos)
		st.set_uv(Vector2(1,1)); st.set_uv2(Vector2(s, -s));  st.add_vertex(pos)
		st.set_uv(Vector2(0,1)); st.set_uv2(Vector2(-s, -s)); st.add_vertex(pos)
	st.commit(procedural_tree_mesh)
	
	var anime_mat = ShaderMaterial.new()
	anime_mat.shader = preload("res://Materials/tree_anime.gdshader")
	if leaf_texture:
		anime_mat.set_shader_parameter("leaf_tex", leaf_texture)
		
	procedural_tree_mesh.surface_set_material(0, anime_mat)
	procedural_tree_mesh.surface_set_material(1, anime_mat)


# ==========================================
# ГЕНЕРАЦІЯ ЧАНКІВ ТА LOD
# ==========================================
func get_lod_info(dist: float) -> Dictionary:
	if dist <= 1.5: return {"res": 32, "col": true}
	if dist <= 4.0: return {"res": 16, "col": false}
	if dist <= 8.0: return {"res": 8, "col": false}
	return {"res": 4, "col": false}

func update_chunks(center_chunk: Vector2):
	for x in range(-RENDER_DISTANCE, RENDER_DISTANCE + 1):
		for z in range(-RENDER_DISTANCE, RENDER_DISTANCE + 1):
			var chunk_pos = center_chunk + Vector2(x, z)
			var dist = chunk_pos.distance_to(center_chunk)

			if dist > RENDER_DISTANCE: continue

			var lod = get_lod_info(dist)
			var needs_update = false

			if not active_chunks.has(chunk_pos): needs_update = true
			elif active_chunks[chunk_pos].res != lod.res: needs_update = true

			if needs_update and not loading_chunks.has(chunk_pos):
				if chunk_cache.has(chunk_pos) and chunk_cache[chunk_pos].has(lod.res):
					_spawn_chunk_in_world(chunk_pos, chunk_cache[chunk_pos][lod.res], lod.res, lod.col)
				else:
					loading_chunks[chunk_pos] = true
					WorkerThreadPool.add_task(_thread_generate_chunk.bind(chunk_pos, lod.res, lod.col))

	var chunks_to_remove = []
	for c_pos in active_chunks.keys():
		if c_pos.distance_to(center_chunk) > RENDER_DISTANCE + 1.0:
			chunks_to_remove.append(c_pos)

	for c_pos in chunks_to_remove:
		active_chunks[c_pos].node.queue_free()
		active_chunks.erase(c_pos)

func _thread_generate_chunk(chunk_pos: Vector2, resolution: int, needs_collision: bool):
	var data = _build_chunk_data(chunk_pos, resolution)
	call_deferred("_on_chunk_generated", chunk_pos, data, resolution, needs_collision)

func _build_chunk_data(chunk_pos: Vector2, resolution: int) -> Dictionary:
	var st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(0)

	var step = CHUNK_SIZE / float(resolution)
	var offset_x = chunk_pos.x * CHUNK_SIZE
	var offset_z = chunk_pos.y * CHUNK_SIZE

	var has_low_land = false 
	var veg_transforms = {} 
	var veg_types = {}

	for z in range(resolution + 1):
		for x in range(resolution + 1):
			var gx = offset_x + (x * step)
			var gz = offset_z + (z * step)
			var raw_py = height_noise.get_noise_2d(gx, gz) * HEIGHT_SCALE

			if raw_py < WATER_LEVEL + 2.0: has_low_land = true 

			var biome_data = get_blended_biome_data(gx, gz, raw_py)
			var py = raw_py * biome_data.h_mult 
			
			var v_color = biome_data.color
			if py < WATER_LEVEL + 5.0: v_color = Color("d4c39e")

			st.set_color(v_color)
			st.add_vertex(Vector3(gx, py, gz))

	for z in range(resolution):
		for x in range(resolution):
			var i = x + z * (resolution + 1)
			st.add_index(i); st.add_index(i + 1); st.add_index(i + resolution + 1)
			st.add_index(i + 1); st.add_index(i + resolution + 2); st.add_index(i + resolution + 1)

	st.generate_normals()

	st.generate_normals()

	# --- ФІКС ТЕЛЕПОРТАЦІЇ: Локальний рандом для чанка ---
	var chunk_rng = RandomNumberGenerator.new()
	chunk_rng.seed = hash(str(chunk_pos)) # Дерева тепер назавжди прив'язані до координат!

	# --- РОЗУМНА ЛОГІКА СПАВНУ ТА LOD ---
	var is_distant = resolution < 32 # Тільки найближчий чанк (res 32) має 3D дерева
	var spawn_attempts = 100 if is_distant else 2000 # Різко зменшуємо кількість спроб для дальніх
	var max_trees = 25 if is_distant else 35 # Далеко ліс трохи рідший для оптимізації
	
	var tree_count = 0
	
	for i in range(spawn_attempts): 
		# ВИКОРИСТОВУЄМО chunk_rng ЗАМІСТЬ randf() !!!
		var lx = chunk_rng.randf_range(0, CHUNK_SIZE)
		var lz = chunk_rng.randf_range(0, CHUNK_SIZE)
		var gx = offset_x + lx
		var gz = offset_z + lz
		var raw_py = height_noise.get_noise_2d(gx, gz) * HEIGHT_SCALE
		
		var blended_data = get_blended_biome_data(gx, gz, raw_py)
		var exact_py = raw_py * blended_data.h_mult
		var b_data = get_biome_at(gx, gz, raw_py)
		
		if b_data != null:
			if exact_py > WATER_LEVEL + 3.0 and exact_py < HEIGHT_SCALE * 0.7:
				var pos = Vector3(gx, exact_py, gz)
				var r = chunk_rng.randf()
				var target_type = ""
				var scale = 1.0
				var y_offset = 0.0
				
				# Трава і квіти НЕ спавняться на дальніх чанках взагалі
				if r < b_data.grass_chance and not is_distant:
					target_type = "grass"
					scale = chunk_rng.randf_range(0.8, 1.4) 
				elif r < b_data.grass_chance + b_data.flower_chance and not is_distant:
					target_type = "flowers"
					scale = chunk_rng.randf_range(1.5, 2.0)
				elif r < b_data.grass_chance + b_data.flower_chance + b_data.mushroom_chance and not is_distant:
					target_type = "mushrooms"
					scale = chunk_rng.randf_range(1.5, 2.5)
				elif r < b_data.grass_chance + b_data.flower_chance + b_data.mushroom_chance + b_data.tree_chance:
					if tree_count >= max_trees: 
						continue
					tree_count += 1
					target_type = "trees"
					scale = chunk_rng.randf_range(0.8, 1.4)
					y_offset = -0.2
					
				if target_type != "":
					var available_meshes = biome_meshes[b_data.biome_name][target_type]
					if available_meshes.size() > 0:
						var selected_mesh = available_meshes[chunk_rng.randi() % available_meshes.size()]
						
						# --- СУПЕР ФІКС FPS ---
						# Якщо це дальній чанк, ми підміняємо важку 3D-модель на нашу 2D-площину!
						# Відеокарта більше не буде вантажити справжні дерева на горизонті.
						if is_distant and target_type == "trees":
							selected_mesh = shared_low_poly_tree
						# ----------------------
						
						if not veg_transforms.has(selected_mesh):
							veg_transforms[selected_mesh] = []
							veg_types[selected_mesh] = target_type
							
						var basis = Basis().rotated(Vector3.UP, chunk_rng.randf() * TAU)
						basis = basis.scaled(Vector3(scale, scale, scale))
						veg_transforms[selected_mesh].append(Transform3D(basis, pos + Vector3(0, y_offset, 0)))
		
	return {"mesh": st.commit(), "needs_water": has_low_land, "v_trans": veg_transforms, "v_types": veg_types}
	return {"mesh": st.commit(), "needs_water": has_low_land, "v_trans": veg_transforms, "v_types": veg_types}

func _on_chunk_generated(chunk_pos: Vector2, data: Dictionary, res: int, col: bool):
	if not chunk_cache.has(chunk_pos): chunk_cache[chunk_pos] = {}
	chunk_cache[chunk_pos][res] = data
	_spawn_chunk_in_world(chunk_pos, data, res, col)

func _spawn_chunk_in_world(chunk_pos: Vector2, data: Dictionary, res: int, col: bool):
	if loading_chunks.has(chunk_pos): loading_chunks.erase(chunk_pos)
	if active_chunks.has(chunk_pos):
		if active_chunks[chunk_pos].res == res: return
		active_chunks[chunk_pos].node.queue_free()

	# МАГІЯ МОДУЛЬНОСТІ: Створюємо Чанк і передаємо йому дані
	var chunk_instance = chunk_scene.instantiate()
	add_child(chunk_instance)
	chunk_instance.build_from_data(chunk_pos, res, col, data, shared_terrain_material, shared_water_material, shared_low_poly_tree)

	active_chunks[chunk_pos] = {"node": chunk_instance, "res": res}
	chunk_instance.build_from_data(chunk_pos, res, col, data, shared_terrain_material, shared_water_material, shared_low_poly_tree)

	active_chunks[chunk_pos] = {"node": chunk_instance, "res": res}

	# --- РОЗМОРОЗКА ЗАТРИМКОЮ ---
	if chunk_pos == current_player_chunk and col and has_node("Player"):
		# Чекаємо 2 кадри, щоб колізія точно "встала" в пам'ять
		await get_tree().process_frame
		await get_tree().process_frame
		$Player.process_mode = Node.PROCESS_MODE_INHERIT
		# Якщо в тебе в player.gd є змінна velocity, скинь її в нуль:
		if "velocity" in $Player: $Player.velocity = Vector3.ZERO
# ==========================================
# БІОМИ, UI ТА МАТЕРІАЛИ (Без змін)
# ==========================================
func get_biome_at(x: float, z: float, h: float) -> BiomeData:
	var temp = (temperature_noise.get_noise_2d(x, z) + 1.0) / 2.0
	var moist = (moisture_noise.get_noise_2d(x, z) + 1.0) / 2.0
	var best_biome: BiomeData = null
	var best_score: float = 999.0 
	
	for b in biomes:
		if b == null: continue
		if h < b.height_range.x or h > b.height_range.y: continue
			
		var t_diff = max(0.0, max(b.temperature_range.x - temp, temp - b.temperature_range.y))
		var m_diff = max(0.0, max(b.moisture_range.x - moist, moist - b.moisture_range.y))
		var score = t_diff + m_diff
		
		if score < best_score:
			best_score = score
			best_biome = b
	return best_biome

func get_blended_biome_data(x: float, z: float, h: float) -> Dictionary:
	var temp = (temperature_noise.get_noise_2d(x, z) + 1.0) / 2.0
	var moist = (moisture_noise.get_noise_2d(x, z) + 1.0) / 2.0
	var blended_h_mult = 0.0
	var blended_color = Color(0, 0, 0)
	var total_weight = 0.0
	
	for b in biomes:
		if b == null: continue
		var t_diff = max(0.0, max(b.temperature_range.x - temp, temp - b.temperature_range.y))
		var m_diff = max(0.0, max(b.moisture_range.x - moist, moist - b.moisture_range.y))
		var dist = t_diff + m_diff
		var weight = smoothstep(0.0, 1.0, clamp(1.0 - (dist / 0.15), 0.0, 1.0)) 
		
		if weight > 0.0:
			blended_h_mult += b.height_multiplier * weight
			blended_color += b.ground_color_main * weight
			total_weight += weight
			
	if total_weight <= 0.001:
		var fallback = biomes[0] if biomes.size() > 0 else null
		if fallback: return {"h_mult": fallback.height_multiplier, "color": fallback.ground_color_main}
		return {"h_mult": 1.0, "color": Color(0.25, 0.55, 0.2)}
		
	return {"h_mult": blended_h_mult / total_weight, "color": blended_color / total_weight}

func find_spawn_point(target_biome: BiomeData) -> Vector3:
	var radius = 0.0
	for i in range(3000):
		var angle = randf() * TAU
		var rx = cos(angle) * radius
		var rz = sin(angle) * radius
		radius += 15.0 
		
		var raw_h = height_noise.get_noise_2d(rx, rz) * HEIGHT_SCALE
		var b_data = get_biome_at(rx, rz, raw_h)
		
		if b_data == target_biome or target_biome == null:
			# ВАЖЛИВО: Отримуємо реальну висоту з урахуванням множника біома
			var blended = get_blended_biome_data(rx, rz, raw_h)
			var real_y = raw_h * blended.h_mult
			
			var spawn_y = max(real_y, WATER_LEVEL) + 2.0 # +2 метри для безпеки
			return Vector3(rx, spawn_y, rz)
			
	return Vector3(0, 50, 0) # Фоллбек

func _create_biome_ui():
	var canvas = CanvasLayer.new()
	add_child(canvas)
	var panel = PanelContainer.new()
	panel.position = Vector2(20, 20)
	canvas.add_child(panel)
	var vbox = VBoxContainer.new()
	panel.add_child(vbox)

	biome_dropdown = OptionButton.new()
	for b in biomes:
		if b != null: biome_dropdown.add_item(b.biome_name)
	vbox.add_child(biome_dropdown)

	var btn = Button.new()
	btn.text = "Телепортуватись"
	btn.pressed.connect(_on_teleport_pressed)
	vbox.add_child(btn)

func _on_teleport_pressed():
	if biomes.is_empty(): return
	var target = biomes[biome_dropdown.selected]
	var spawn_pos = find_spawn_point(target)

	if has_node("Player"): 
		$Player.global_position = spawn_pos
		$Player.process_mode = Node.PROCESS_MODE_DISABLED # Заморозка при телепорті
	
	current_player_chunk = Vector2(floor(spawn_pos.x / CHUNK_SIZE), floor(spawn_pos.z / CHUNK_SIZE))
	update_chunks(current_player_chunk)
	for c in active_chunks.values(): c.node.queue_free()
	active_chunks.clear()
	loading_chunks.clear()
	chunk_cache.clear() 

	current_player_chunk = Vector2(floor(spawn_pos.x / CHUNK_SIZE), floor(spawn_pos.z / CHUNK_SIZE))
	update_chunks(current_player_chunk)

func _input(event):
	if event is InputEventKey and event.pressed and event.keycode == KEY_TAB:
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED: Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		else: Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _setup_materials():
	shared_terrain_material = ShaderMaterial.new()
	var t_shader = Shader.new()
	t_shader.code = """
	shader_type spatial;
	render_mode diffuse_burley, specular_schlick_ggx;
	varying vec3 world_pos;
	float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453123); }
	void vertex() { world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
	void fragment() {
		float dist = distance(world_pos, CAMERA_POSITION_WORLD);
		vec3 base_color = COLOR.rgb;
		bool is_sand = (base_color.r > 0.7 && base_color.b < 0.7);
		float noise = hash(world_pos.xz * 25.0); 
		float detail = is_sand ? mix(0.92, 1.08, noise) : mix(0.98, 1.02, noise);
		float lod_factor = 1.0 - smoothstep(30.0, 100.0, dist);
		ALBEDO = base_color * mix(1.0, detail, lod_factor);
		ROUGHNESS = is_sand ? 0.85 : 0.95; 		
		SPECULAR = 0.0; 
	}
	"""
	shared_terrain_material.shader = t_shader

	shared_water_material = ShaderMaterial.new()
	var w_shader = Shader.new()
	w_shader.code = """
	shader_type spatial;
	render_mode specular_schlick_ggx, cull_disabled;
	uniform vec3 color_deep : source_color = vec3(0.01, 0.15, 0.45);
	uniform vec3 color_shallow : source_color = vec3(0.1, 0.7, 0.8);
	uniform vec3 color_foam : source_color = vec3(1.0, 1.0, 1.0);
	uniform float metallic = 0.9;
	uniform sampler2D wave_noise;
	varying vec2 world_pos;
	varying float wave_height; 
	void vertex() {
		world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xz;
		float time = TIME * 0.5; 
		float wave1 = sin(world_pos.x * 0.015 + time) * 0.8;
		float wave2 = cos(world_pos.y * 0.02 + time * 1.2) * 0.6;
		float wave3 = sin((world_pos.x + world_pos.y) * 0.03 - time * 0.8) * 0.4;
		wave_height = wave1 + wave2 + wave3; 
		VERTEX.y += wave_height; 
	}
	void fragment() {
		vec2 uv1 = world_pos * 0.01 + vec2(TIME * 0.01, 0.0);
		vec2 uv2 = world_pos * 0.01 + vec2(0.0, TIME * 0.01);
		vec3 raw_normal = mix(texture(wave_noise, uv1).rgb, texture(wave_noise, uv2).rgb, 0.5);
		vec3 final_normal = mix(vec3(0.5, 0.5, 1.0), raw_normal, 0.5);
		float foam = smoothstep(0.0, 0.5, wave_height) * texture(wave_noise, world_pos * 0.08).r * 2.0;
		ALBEDO = mix(color_deep, color_foam, clamp(foam, 0.0, 1.0));
		METALLIC = metallic;
		ROUGHNESS = 0.05;
		NORMAL_MAP = final_normal;
		ALPHA = 0.95;
	}
	"""
	shared_water_material.shader = w_shader
	var wave_noise = FastNoiseLite.new()
	wave_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	var wave_tex = NoiseTexture2D.new()
	wave_tex.noise = wave_noise
	wave_tex.seamless = true
	wave_tex.as_normal_map = true 
	shared_water_material.set_shader_parameter("wave_noise", wave_tex)
