extends Node

const WORLD_SIZE: float = 10000.0 
var world_seed: int = 777
var custom_spawn_x: float = -1.0
var custom_spawn_z: float = -1.0

# === НОВІ ЗМІННІ ДЛЯ PYTHON JSON МАПИ ===
var map_data: Dictionary = {}
var map_width: int = 0
var map_height: int = 0
# 1 клітинка з Python (1 тайл) буде дорівнювати 100 метрам у 3D світі
var tile_size: float = 100.0 

func _ready():
	_load_map_from_json("res://region.json")

func _load_map_from_json(path: String):
	if not FileAccess.file_exists(path):
		push_error("Файл карти не знайдено: " + path + ". Згенеруйте його в Python!")
		return
		
	var file = FileAccess.open(path, FileAccess.READ)
	var json = JSON.new()
	var error = json.parse(file.get_as_text())
	
	if error == OK:
		var data = json.get_data()
		if data.has("tiles"):
			for tile in data["tiles"]:
				var pos = Vector2(tile["x"], tile["y"])
				map_data[pos] = tile
				
				# Знаходимо максимальні розміри сітки
				if tile["x"] > map_width: map_width = int(tile["x"])
				if tile["y"] > map_height: map_height = int(tile["y"])
				
			map_width += 1
			map_height += 1
			print("JSON Мапу успішно завантажено! Роздільна здатність: ", map_width, "x", map_height)
	else:
		push_error("Помилка парсингу JSON файлу!")
