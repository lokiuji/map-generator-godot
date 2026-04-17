extends Node3D

@export var grass_count: int = 2000
# ЗМІНА 1: Тепер ми приймаємо файли .gltf (PackedScene), а не .tres (Mesh)
@export var high_poly_scene: PackedScene
@export var low_poly_scene: PackedScene

var mmi_high: MultiMeshInstance3D
var mmi_low: MultiMeshInstance3D

func _ready():
	if not high_poly_scene:
		print("ПОМИЛКА: Ти забув додати .gltf сцену в Інспектор!")
		return
		
	_setup_grass_multimeshes()
	_generate_grass()

# --- МАГІЯ АВТОМАТИЧНОГО ВИТЯГУВАННЯ МЕШУ З .GLTF ---
func _extract_mesh_from_scene(scene: PackedScene) -> Mesh:
	if not scene: return null
	var instance = scene.instantiate()
	var extracted_mesh = _find_first_mesh(instance)
	instance.queue_free() # Одразу видаляємо тимчасовий об'єкт
	return extracted_mesh

func _find_first_mesh(node: Node) -> Mesh:
	if node is MeshInstance3D:
		return node.mesh
	for child in node.get_children():
		var found = _find_first_mesh(child)
		if found: return found
	return null
# ----------------------------------------------------

func _setup_grass_multimeshes():
	# Витягуємо чисту геометрію з твоїх .gltf файлів
	var high_mesh = _extract_mesh_from_scene(high_poly_scene)
	var low_mesh = _extract_mesh_from_scene(low_poly_scene)
	
	if not high_mesh:
		print("ПОМИЛКА: В цьому .gltf немає 3D-моделі!")
		return

	# 1. LOD 0 (Ближня трава)
	mmi_high = MultiMeshInstance3D.new()
	var mm_high = MultiMesh.new()
	mm_high.transform_format = MultiMesh.TRANSFORM_3D
	mm_high.instance_count = grass_count
	mm_high.mesh = high_mesh
	mmi_high.multimesh = mm_high
	mmi_high.visibility_range_end = 150.0 
	mmi_high.visibility_range_end_margin = 2.0 
	mmi_high.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	add_child(mmi_high)

	# 2. LOD 1 (Дальня трава). Створюємо тільки якщо ти додав другий файл.
	if low_mesh:
		mmi_low = MultiMeshInstance3D.new()
		var mm_low = MultiMesh.new()
		mm_low.transform_format = MultiMesh.TRANSFORM_3D
		mm_low.instance_count = grass_count
		mm_low.mesh = low_mesh
		mmi_low.multimesh = mm_low
		mmi_low.visibility_range_begin = 15.0 
		mmi_low.visibility_range_begin_margin = 2.0 
		mmi_low.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
		add_child(mmi_low)

func _generate_grass():
	for i in range(grass_count):
		var pos = Vector3(randf_range(-25, 25), 0, randf_range(-25, 25)) 
		
		var basis = Basis().rotated(Vector3.UP, randf() * TAU)
		var scale_factor = randf_range(0.8, 1.3) * 5.0
		basis = basis.scaled(Vector3(scale_factor, scale_factor, scale_factor))
		
		var t = Transform3D(basis, pos)
		mmi_high.multimesh.set_instance_transform(i, t)
		if mmi_low:
			mmi_low.multimesh.set_instance_transform(i, t)
