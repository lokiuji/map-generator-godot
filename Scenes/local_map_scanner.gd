extends Node3D

@export var player_node: Node3D # Не забудь перетягнути сюди гравця в Інспекторі!
@onready var map_camera = $HeightmapViewport/MapCamera
@onready var heightmap_viewport = $HeightmapViewport

# Завантажуємо наш файл матеріалу океану
@onready var ocean_material = preload("res://addons/tessarakkt.oceanfft/Ocean.tres")

func _ready():
	if ocean_material and heightmap_viewport:
		# 1. Беремо живу текстуру з нашого Viewport'а
		var vp_tex = heightmap_viewport.get_texture()
		
		# 2. Передаємо її прямо в шейдер океану!
		ocean_material.set_shader_parameter("terrain_heightmap", vp_tex)
		
		# 3. Синхронізуємо масштаб (розмір камери сканера)
		ocean_material.set_shader_parameter("local_map_size", 1000.0)

func _process(_delta):
	if player_node:
		# Камера сканера завжди висить на 500 м над гравцем
		map_camera.global_position = Vector3(
			player_node.global_position.x, 
			500.0, 
			player_node.global_position.z
		)
		
		# Передаємо координати гравця в шейдер води, щоб мапа рухалась разом з ним
		if ocean_material:
			ocean_material.set_shader_parameter("player_position", player_node.global_position)
