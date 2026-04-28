extends MeshInstance3D

func _ready():
	# 1. Генеруємо меш
	mesh = generate_grass_blade()
	
	# 2. АВТОМАТИЧНО ЗБЕРІГАЄМО ЙОГО У ФАЙЛ
	var err = ResourceSaver.save(mesh, "res://high_poly_grass.tres")
	
	# 3. Виводимо повідомлення в консоль, щоб точно знати, що все вийшло
	if err == OK:
		print("УСПІХ! Файл high_poly_grass.tres збережено в папці проєкту!")
	else:
		print("ПОМИЛКА збереження: ", err)

func generate_grass_blade() -> ArrayMesh:
	var st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	
	var segments = 4 
	var width = 0.15 
	var height = 0.8 
	var bend = 0.35  
	
	for i in range(segments + 1):
		var t = float(i) / segments
		var current_width = width * (1.0 - t) 
		var current_height = height * t
		var current_bend = bend * t * t       
		
		st.set_uv(Vector2(0, t))
		st.set_normal(Vector3(0, 1, 0.5).normalized())
		st.add_vertex(Vector3(-current_width/2, current_height, current_bend))
		
		st.set_uv(Vector2(1, t))
		st.set_normal(Vector3(0, 1, 0.5).normalized())
		st.add_vertex(Vector3(current_width/2, current_height, current_bend))
		
	for i in range(segments):
		var lb = i * 2       
		var rb = i * 2 + 1   
		var lt = i * 2 + 2   
		var rt = i * 2 + 3   
		
		st.add_index(lb); st.add_index(rb); st.add_index(lt) 
		st.add_index(rb); st.add_index(rt); st.add_index(lt) 
		
	st.generate_normals()
	return st.commit()
