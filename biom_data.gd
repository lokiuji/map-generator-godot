extends Resource
class_name BiomeData

@export var biome_name: String = "Новий Біом"

@export_group("Кліматичні умови")
@export var temperature_range: Vector2 = Vector2(0.0, 1.0) 
@export var moisture_range: Vector2 = Vector2(0.0, 1.0)    
@export var height_range: Vector2 = Vector2(-20.0, 100.0)  

@export_group("Рельєф")
@export var height_multiplier: float = 1.0 

@export_group("Вода")
@export var water_level_offset: float = 0.0

@export_group("Рослинність")
@export var grass_density: int = 15000
@export var flower_density: int = 1500
@export var tree_density: int = 50 # <--- САМЕ ЦІЄЇ ЗМІННОЇ БРАКУВАЛО РУШІЮ!

@export_group("Кольори")
@export var ground_color_main: Color = Color(0.25, 0.55, 0.20)
@export var ground_color_accent: Color = Color(0.15, 0.35, 0.10)
@export var grass_color_top: Color = Color(0.45, 0.85, 0.25)
@export var grass_color_bottom: Color = Color(0.10, 0.40, 0.15)

@export_group("Моделі Quaternius (.gltf)")
@export var grass_scenes: Array[PackedScene] = []
@export var flower_scenes: Array[PackedScene] = []
@export var mushroom_scenes: Array[PackedScene] = []
@export var tree_scenes: Array[PackedScene] = []

@export_group("Процедурна генерація")
@export var use_procedural_tree: bool = false # Галочка в Інспекторі!

@export_group("Налаштування густоти (шанс спавну 0.0 - 1.0)")
@export var grass_chance: float = 0.80   # 80% що виросте трава
@export var flower_chance: float = 0.05  # 5% для квітів
@export var mushroom_chance: float = 0.02 # 2% для грибів
@export var tree_chance: float = 0.05    # 5% для дерев
