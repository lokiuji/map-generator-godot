extends Node3D
class_name WorldChunk

const CHUNK_SIZE = 120.0
const WATER_LEVEL = -20.0

var chunk_pos: Vector2
var resolution: int

# Ця функція приймає дані від Головного скрипта і будує 3D світ
func build_from_data(pos: Vector2, res: int, col: bool, data: Dictionary, terrain_mat: Material, water_mat: Material, shared_low_poly_tree: Mesh):
	chunk_pos = pos
	resolution = res

	# 1. СТВОРЮЄМО ЗЕМЛЮ
	var land = MeshInstance3D.new()
	land.mesh = data.mesh
	land.material_override = terrain_mat
	if col: 
		land.create_trimesh_collision()
	add_child(land)

	# 2. СТВОРЮЄМО ВОДУ
	if data.needs_water:
		var water = MeshInstance3D.new()
		var w_mesh = PlaneMesh.new()
		w_mesh.size = Vector2(CHUNK_SIZE, CHUNK_SIZE)
		w_mesh.subdivide_width = 40 
		w_mesh.subdivide_depth = 40
		water.mesh = w_mesh
		water.global_position = Vector3(chunk_pos.x * CHUNK_SIZE + CHUNK_SIZE/2.0, WATER_LEVEL, chunk_pos.y * CHUNK_SIZE + CHUNK_SIZE/2.0)
		water.material_override = water_mat
		add_child(water)

	# 3. СТВОРЮЄМО РОСЛИННІСТЬ ТА LOD
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
			
			# БЛОК 1: Видимість трави
			if type == "grass" or type == "flowers" or type == "mushrooms":
				mmi.visibility_range_end = 80.0 # Трава зникає трохи далі
				mmi.visibility_range_end_margin = 15.0 # Плавне розчинення (Cross-fade)
				mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF 
				
			elif type == "trees":
				# ЄДИНИЙ ПРАВИЛЬНИЙ LOD ДЛЯ ВСІХ ЧАНКІВ
				# 3D дерева видно тільки від 0 до 70 метрів. Далі вони зникають і не їдять FPS.
				mmi.visibility_range_end = 70.0 
				mmi.visibility_range_end_margin = 0.0 # Жорстке відсікання без накладань!
				mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
				mmi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED
				
				_add_low_poly_trees(transforms, shared_low_poly_tree)
					
			add_child(mmi)

func _add_low_poly_trees(transforms: Array, shared_low_poly_tree: Mesh):
	var mmi_low = MultiMeshInstance3D.new()
	var mm_low = MultiMesh.new()
	mm_low.transform_format = MultiMesh.TRANSFORM_3D
	mm_low.instance_count = transforms.size()
	mm_low.mesh = shared_low_poly_tree 
	
	for i in range(transforms.size()):
		mm_low.set_instance_transform(i, transforms[i])
	
	mmi_low.multimesh = mm_low
	# Білборди з'являються рівно там, де зникають 3D дерева
	mmi_low.visibility_range_begin = 70.0 
	mmi_low.visibility_range_begin_margin = 0.0 # Жорстке відсікання! Впритул їх ніколи не буде видно.
	mmi_low.visibility_range_end = 1200.0 
	mmi_low.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF 
	mmi_low.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED
	
	add_child(mmi_low)
