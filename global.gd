extends Node

const WORLD_SIZE: float = 10000.0 
var world_seed: int = 777
var custom_spawn_x: float = -1.0
var custom_spawn_z: float = -1.0

# === ОПТИМІЗАЦІЯ: 2D Масив замість словника ===
var map_grid = [] 
var map_width: int = 0
var map_height: int = 0
var tile_size: float = 100.0 

func _ready():
	_load_map_from_json("res://region.json")

func _load_map_from_json(path: String):
	if not FileAccess.file_exists(path):
		push_error("Файл карти не знайдено: " + path)
		return
		
	var file = FileAccess.open(path, FileAccess.READ)
	var json = JSON.new()
	var error = json.parse(file.get_as_text())
	
	if error == OK:
		var data = json.get_data()
		if data.has("tiles"):
			# 1. Знаходимо розміри мапи
			for tile in data["tiles"]:
				if tile["x"] > map_width: map_width = int(tile["x"])
				if tile["y"] > map_height: map_height = int(tile["y"])
			map_width += 1
			map_height += 1
			
			# 2. Створюємо пусту сітку для максимальної швидкодії
			map_grid.resize(map_width)
			for x in range(map_width):
				var col = []
				col.resize(map_height)
				for z in range(map_height):
					col[z] = {"elevation": 0.0, "biome": "ocean"}
				map_grid[x] = col
				
			# 3. Заповнюємо сітку даними
			for tile in data["tiles"]:
				# ФІКС ФІОЛЕТОВОГО КОЛЬОРУ: "Tropical Forest" -> "tropical_forest"
				var raw_biome = str(tile["biome"]).to_lower().replace(" ", "_")
				tile["biome"] = raw_biome
				map_grid[int(tile["x"])][int(tile["y"])] = tile
				
			print("JSON Мапу успішно завантажено! Розмір: ", map_width, "x", map_height)
	else:
		push_error("Помилка парсингу JSON файлу!")
