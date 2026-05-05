extends Node3D

@export var player_node: Node3D # Не забудь перевірити, чи прив'язаний сюди гравець в Інспекторі!
@onready var map_camera = $HeightmapViewport/MapCamera
@onready var heightmap_viewport = $HeightmapViewport
@onready var ocean_material = preload("res://addons/tessarakkt.oceanfft/Ocean.tres")

func _ready():
	if ocean_material and heightmap_viewport:
		# Передаємо текстуру висот в шейдер
		var vp_tex = heightmap_viewport.get_texture()
		ocean_material.set_shader_parameter("terrain_heightmap", vp_tex)
		ocean_material.set_shader_parameter("local_map_size", 8000.0)

func _process(_delta):
	# Оновлюємо позицію сканера над гравцем ЩОКАДРУ
	if player_node and ocean_material:
		global_position = Vector3(player_node.global_position.x, 500.0, player_node.global_position.z)
		ocean_material.set_shader_parameter("player_position", global_position)
