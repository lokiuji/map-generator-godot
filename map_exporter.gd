extends Control

const EXPORT_RES = 4096
const PREVIEW_RES = 512

var preview_texture: TextureRect
var seed_input: LineEdit
var export_btn: Button
var status_label: Label
var seam_offset: Vector2 = Vector2.ZERO

func _ready():
	# 1. БУДУЄМО ІНТЕРФЕЙС ЧЕРЕЗ КОД
	var margin = MarginContainer.new()
	margin.set_anchors_preset(PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_top", 20)
	margin.add_theme_constant_override("margin_left", 20)
	margin.add_theme_constant_override("margin_right", 20)
	margin.add_theme_constant_override("margin_bottom", 20)
	add_child(margin)
	
	var hbox = HBoxContainer.new()
	margin.add_child(hbox)
	
	# Ліва панель (Налаштування)
	var vbox = VBoxContainer.new()
	vbox.custom_minimum_size = Vector2(300, 0)
	hbox.add_child(vbox)
	
	var title_label = Label.new()
	title_label.text = "ГЕНЕРАТОР СВІТУ"
	vbox.add_child(title_label)
	
	var seed_hbox = HBoxContainer.new()
	vbox.add_child(seed_hbox)
	
	seed_input = LineEdit.new()
	seed_input.text = str(Global.world_seed)
	seed_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	seed_input.text_submitted.connect(_on_seed_entered)
	seed_hbox.add_child(seed_input)
	
	var rand_btn = Button.new()
	rand_btn.text = "Випадковий Сід"
	rand_btn.pressed.connect(_on_random_seed)
	seed_hbox.add_child(rand_btn)
	
	export_btn = Button.new()
	export_btn.text = "ЕКСПОРТ (4096x4096)"
	export_btn.custom_minimum_size = Vector2(0, 50)
	export_btn.pressed.connect(_on_export_pressed)
	vbox.add_child(export_btn)
	
	status_label = Label.new()
	status_label.text = "Очікування..."
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(status_label)
	
	# Права панель (Прев'ю)
	preview_texture = TextureRect.new()
	preview_texture.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	preview_texture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	preview_texture.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	hbox.add_child(preview_texture)
	
	# 2. ЗАПУСКАЄМО ПЕРШЕ ПРЕВ'Ю
	_update_preview()

func _on_random_seed():
	var new_seed = randi() % 999999
	seed_input.text = str(new_seed)
	_on_seed_entered(str(new_seed))

func _on_seed_entered(new_text: String):
	if new_text.is_valid_int():
		status_label.text = "Генерую прев'ю..."
		# Оновлюємо сід, але ЗАПІКАЄМО гори для прев'ю (це швидко на 2048)
		Global.set_seed(new_text.to_int(), true) 
		_calculate_optimal_seam()
		_update_preview()

func _update_preview():
	var img = Image.create(PREVIEW_RES, PREVIEW_RES, false, Image.FORMAT_RGB8)
	var step = Global.WORLD_SIZE / float(PREVIEW_RES)
	var half_world = Global.WORLD_SIZE / 2.0
	
	for y in range(PREVIEW_RES):
		for x in range(PREVIEW_RES):
			# x * step йде від 0 до ширини світу. 
			# Додаючи seam_offset, ми кажемо: "Почни малювати з ідеальної координати води"
			var base_x = (x * step) + seam_offset.x
			var base_z = (y * step) + seam_offset.y
			
			var world_x = wrapf(base_x, -half_world, half_world)
			var world_z = wrapf(base_z, -half_world, half_world)
			
			var h = Global.get_raw_elevation(world_x, world_z)
			var m_mask = Global.get_mountain_mask(world_x, world_z)
			
			var col = Color(0.05, 0.15, 0.35) # Океан
			if h > 0.35: col = Color(0.8, 0.7, 0.5) # Берег
			
			# МАЛЮЄМО ГОРИ ТІЛЬКИ НА СУШІ (h > 0.38)
			if h > 0.38: 
				col = Color(0.2, 0.4, 0.15) # Базова суша
				if m_mask > 0.1: col = col.lerp(Color(0.4, 0.4, 0.4), m_mask)
				if m_mask > 0.6: col = col.lerp(Color(1.0, 1.0, 1.0), smoothstep(0.6, 0.8, m_mask))
			img.set_pixel(x, y, col)
			
	preview_texture.texture = ImageTexture.create_from_image(img)
	status_label.text = "Прев'ю готове. Сід: " + str(Global.world_seed)

func _calculate_optimal_seam():
	var checks = 512 # Збільшили точність у 8 разів!
	var step_size = Global.WORLD_SIZE / float(checks)
	var half_w = Global.WORLD_SIZE / 2.0
	
	var best_x = 0.0
	var min_land_x = 999999
	
	# Шукаємо найкращий вертикальний розріз (по осі X)
	for i in range(checks):
		var test_x = -half_w + (step_size * i)
		var land_count = 0
		for j in range(checks):
			var test_z = -half_w + (step_size * j)
			if Global.get_raw_elevation(test_x, test_z) > 0.35:
				land_count += 1
		
		if land_count < min_land_x:
			min_land_x = land_count
			best_x = test_x
		if land_count == 0: 
			break # Знайшли абсолютно чистий океан, зупиняємось!
			
	var best_z = 0.0
	var min_land_z = 999999
	
	# Шукаємо найкращий горизонтальний розріз (по осі Z)
	for j in range(checks):
		var test_z = -half_w + (step_size * j)
		var land_count = 0
		for i in range(checks):
			var test_x = -half_w + (step_size * i)
			if Global.get_raw_elevation(test_x, test_z) > 0.35:
				land_count += 1
				
		if land_count < min_land_z:
			min_land_z = land_count
			best_z = test_z
		if land_count == 0: 
			break
			
	seam_offset = Vector2(best_x, best_z)
	print("Оптимальний зсув знайдено. Перетин суші: по X = ", min_land_x, " точок, по Z = ", min_land_z, " точок.")

func _on_export_pressed():
	export_btn.disabled = true
	status_label.text = "ВИКОНУЄТЬСЯ ЕКСПОРТ...\nПрограма зависне на 10-20 секунд. Не закривай вікно!"
	
	# Чекаємо 1 кадр, щоб UI встиг оновити текст перед тим, як процесор зависне
	await get_tree().process_frame 
	await get_tree().process_frame
	
	var heightmap = Image.create(EXPORT_RES, EXPORT_RES, false, Image.FORMAT_RF)
	var splatmap = Image.create(EXPORT_RES, EXPORT_RES, false, Image.FORMAT_RGB8)
	
	var step = Global.WORLD_SIZE / float(EXPORT_RES)
	var half_world = Global.WORLD_SIZE / 2.0
	
	for y in range(EXPORT_RES):
		for x in range(EXPORT_RES):
			# x * step йде від 0 до ширини світу. 
			# Додаючи seam_offset, ми кажемо: "Почни малювати з ідеальної координати води"
			var base_x = (x * step) + seam_offset.x
			var base_z = (y * step) + seam_offset.y
			
			var world_x = wrapf(base_x, -half_world, half_world)
			var world_z = wrapf(base_z, -half_world, half_world)
			
			var h = Global.get_raw_elevation(world_x, world_z)
			var m_mask = Global.get_mountain_mask(world_x, world_z)
			
			# Експортуємо висоту
			heightmap.set_pixel(x, y, Color(h, h, h, 1.0))
			
			# Експортуємо кольорову мапу
			var col = Color(0.05, 0.15, 0.35) # Океан
			if h > 0.35: col = Color(0.8, 0.7, 0.5) # Берег
			
			# МАЛЮЄМО ГОРИ ТІЛЬКИ НА СУШІ (h > 0.38)
			if h > 0.38: 
				col = Color(0.2, 0.4, 0.15) # Базова суша
				if m_mask > 0.1: col = col.lerp(Color(0.4, 0.4, 0.4), m_mask)
				if m_mask > 0.6: col = col.lerp(Color(1.0, 1.0, 1.0), smoothstep(0.6, 0.8, m_mask))
			splatmap.set_pixel(x, y, col)
			
	heightmap.save_exr("res://world_heightmap.exr")
	splatmap.save_png("res://world_splatmap.png")
	
	status_label.text = "УСПІХ!\nФайли збережено в res://"
	export_btn.disabled = false
