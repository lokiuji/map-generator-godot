extends Node3D

const CHUNK_SIZE = 120.0
const RENDER_DISTANCE = 4 
const HEIGHT_SCALE = 150.0
const WATER_LEVEL = -20.0

@export var biomes: Array[BiomeData]
@export var leaf_texture: Texture2D 
@export var grass_texture: Texture2D 

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
var shared_low_poly_tree: CylinderMesh # СПІЛЬНИЙ МЕШ ДЛЯ LOD (Рятує FPS!)

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
	shared_low_poly_tree = CylinderMesh.new()
	shared_low_poly_tree.radial_segments = 4 # Дуже низькополігонально
	shared_low_poly_tree.rings = 1
	shared_low_poly_tree.bottom_radius = 0.5
	shared_low_poly_tree.top_radius = 0.0 # Робимо конус
	shared_low_poly_tree.height = 8.0
	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color(0.2, 0.4, 0.2) # Темно-зелений колір
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

	# --- ОПТИМІЗОВАНА ЛОГІКА СПАВНУ РОСЛИН ---
	if resolution >= 16: 
		var tree_count = 0 # <--- ДОДАЄМО ЛІЧИЛЬНИК ДЕРЕВ
		
		for i in range(5000): 
			var lx = randf_range(0, CHUNK_SIZE)
			var lz = randf_range(0, CHUNK_SIZE)
			var gx = offset_x + lx
			var gz = offset_z + lz
			var raw_py = height_noise.get_noise_2d(gx, gz) * HEIGHT_SCALE
			
			var blended_data = get_blended_biome_data(gx, gz, raw_py)
			var exact_py = raw_py * blended_data.h_mult
			var b_data = get_biome_at(gx, gz, raw_py)
			
			if b_data != null:
				if exact_py > WATER_LEVEL + 3.0 and exact_py < HEIGHT_SCALE * 0.7:
					var pos = Vector3(gx, exact_py, gz)
					var r = randf()
					var target_type = ""
					var scale = 1.0
					var y_offset = 0.0
					
					if r < b_data.grass_chance:
						target_type = "grass"
						scale = randf_range(2.0, 3.5) 
					elif r < b_data.grass_chance + b_data.flower_chance:
						target_type = "flowers"
						scale = randf_range(1.5, 2.0)
					elif r < b_data.grass_chance + b_data.flower_chance + b_data.mushroom_chance:
						target_type = "mushrooms"
						scale = randf_range(1.5, 2.5)
					elif r < b_data.grass_chance + b_data.flower_chance + b_data.mushroom_chance + b_data.tree_chance:
						# --- ЖОРСТКИЙ ЛІМІТ ДЕРЕВ ---
						if tree_count >= 35: # Максимум 35 дерев на чанк!
							continue
						tree_count += 1
						# ----------------------------
						target_type = "trees"
						scale = randf_range(0.8, 1.4)
						y_offset = -0.2
						
					if target_type != "":
						var available_meshes = biome_meshes[b_data.biome_name][target_type]
						if available_meshes.size() > 0:
							var selected_mesh = available_meshes[randi() % available_meshes.size()]
							
							if not veg_transforms.has(selected_mesh):
								veg_transforms[selected_mesh] = []
								veg_types[selected_mesh] = target_type
								
							var basis = Basis().rotated(Vector3.UP, randf() * TAU)
							basis = basis.scaled(Vector3(scale, scale, scale))
							veg_transforms[selected_mesh].append(Transform3D(basis, pos + Vector3(0, y_offset, 0)))

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

	var container = Node3D.new()
	add_child(container)

	var land = MeshInstance3D.new()
	land.mesh = data.mesh
	land.material_override = shared_terrain_material 
	if col: land.create_trimesh_collision()
	container.add_child(land)

	if data.needs_water:
		var water = MeshInstance3D.new()
		var w_mesh = PlaneMesh.new()
		w_mesh.size = Vector2(CHUNK_SIZE, CHUNK_SIZE)
		w_mesh.subdivide_width = 40 
		w_mesh.subdivide_depth = 40
		water.mesh = w_mesh
		water.global_position = Vector3(chunk_pos.x * CHUNK_SIZE + CHUNK_SIZE/2.0, WATER_LEVEL, chunk_pos.y * CHUNK_SIZE + CHUNK_SIZE/2.0)
		water.material_override = shared_water_material
		container.add_child(water)

	for mesh in data.v_trans.keys():
		var transforms = data.v_trans[mesh]
		var type = data.v_types[mesh]
		
		if transforms.size() > 0:
			var mmi = MultiMeshInstance3D.new()
			var mm = MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.instance_count = transforms.size()
			mm.mesh = mesh
			
			for i in range(transforms.size()):
				mm.set_instance_transform(i, transforms[i])
			mmi.multimesh = mm
			
			# ЧИСТИЙ БЛОК: Ніякого material_override, тільки LOD і тіні
			if type == "grass" or type == "flowers" or type == "mushrooms":
				mmi.visibility_range_end = 60.0 
				mmi.visibility_range_end_margin = 5.0
				mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF 
				
			elif type == "trees":
				mmi.visibility_range_end = 70.0 
				mmi.visibility_range_end_margin = 10.0
				mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
				_add_low_poly_trees(container, transforms)
				
			mmi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
			container.add_child(mmi)

	active_chunks[chunk_pos] = {"node": container, "res": res}

# --- ОПТИМІЗОВАНИЙ LOD ДЕРЕВ ---
func _add_low_poly_trees(container, transforms):
	var mmi_low = MultiMeshInstance3D.new()
	var mm_low = MultiMesh.new()
	mm_low.transform_format = MultiMesh.TRANSFORM_3D
	mm_low.instance_count = transforms.size()
	
	# ВИКОРИСТОВУЄМО СПІЛЬНИЙ МЕШ З ПАМ'ЯТІ (БЕЗ ВИТОКІВ!)
	mm_low.mesh = shared_low_poly_tree 
	
	for i in range(transforms.size()):
		mm_low.set_instance_transform(i, transforms[i])
	
	mmi_low.multimesh = mm_low
	mmi_low.visibility_range_begin = 70.0 
	mmi_low.visibility_range_begin_margin = 10.0
	mmi_low.visibility_range_end = 350.0 
	mmi_low.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	mmi_low.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF # Дальні дерева не кидають тінь
	
	container.add_child(mmi_low)


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
	if target_biome == null:
		var center_h = height_noise.get_noise_2d(0, 0) * HEIGHT_SCALE
		return Vector3(0, max(center_h, WATER_LEVEL) + 5.0, 0)
		
	var radius = 0.0
	for i in range(3000):
		var angle = randf() * TAU
		var rx = cos(angle) * radius
		var rz = sin(angle) * radius
		radius += 15.0 
		
		var h = height_noise.get_noise_2d(rx, rz) * HEIGHT_SCALE
		var found_biome = get_biome_at(rx, rz, h)
		
		if found_biome == target_biome:
			var spawn_y = max(h, WATER_LEVEL + target_biome.water_level_offset) + 5.0
			return Vector3(rx, spawn_y, rz)
			
	var fallback_h = height_noise.get_noise_2d(0, 0) * HEIGHT_SCALE
	return Vector3(0, max(fallback_h, WATER_LEVEL) + 5.0, 0)

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

	if has_node("Player"): $Player.global_position = spawn_pos

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
