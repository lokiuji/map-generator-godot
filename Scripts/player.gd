extends CharacterBody3D

const SPEED = 12.0 # Твоя швидкість бігу
var gravity = 35.0 # Наша нова сильна гравітація для відкритого світу
const BOB_FREQ = 0.25
const BOB_AMP = 0.08
@export var water_level = -20.0 # Змінна, яку можна міняти в редакторі

@onready var camera = $Camera3D
@onready var collision = $CollisionShape3D

var look_rot = Vector2.ZERO
var t_bob = 0.0
var fly_mode = false

func _ready():
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	floor_stop_on_slope = true # Забороняє гравцеві ковзати на похилих поверхнях
	
func _input(event):
	if event is InputEventMouseMotion and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
		look_rot.y -= event.relative.x * 0.003
		look_rot.x -= event.relative.y * 0.003
		look_rot.x = clamp(look_rot.x, -1.5, 1.5)
		rotation.y = look_rot.y
		camera.rotation.x = look_rot.x

	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_ESCAPE:
			get_tree().quit()
		if event.keycode == KEY_F:
			fly_mode = !fly_mode
			# ВИПРАВЛЕННЯ: Безпечне перемикання фізики
			collision.set_deferred("disabled", fly_mode)
			
			if not fly_mode:
				# Коли вимикаємо політ, скидаємо інерцію падіння, 
				# щоб не пробити землю на величезній швидкості
				velocity.y = 0.0

func _physics_process(delta):
	var underwater = camera.global_position.y < water_level
	if fly_mode:
		_process_fly_mode(delta)
	else:
		_process_walk_mode(delta, underwater)

func _process_fly_mode(delta):
	var fly_speed = 80.0
	if Input.is_physical_key_pressed(KEY_SHIFT): fly_speed = 250.0
	
	var cam_basis = camera.global_transform.basis
	var dir = Vector3.ZERO
	
	if Input.is_physical_key_pressed(KEY_W): dir -= cam_basis.z
	if Input.is_physical_key_pressed(KEY_S): dir += cam_basis.z
	if Input.is_physical_key_pressed(KEY_A): dir -= cam_basis.x
	if Input.is_physical_key_pressed(KEY_D): dir += cam_basis.x
	if Input.is_physical_key_pressed(KEY_E): dir += Vector3.UP
	if Input.is_physical_key_pressed(KEY_Q): dir -= Vector3.UP
	
	dir = dir.normalized()
	global_position += dir * fly_speed * delta

func _process_walk_mode(delta, underwater):
	var input_dir = Vector2.ZERO
	if Input.is_physical_key_pressed(KEY_W): input_dir.y -= 1
	if Input.is_physical_key_pressed(KEY_S): input_dir.y += 1
	if Input.is_physical_key_pressed(KEY_A): input_dir.x -= 1
	if Input.is_physical_key_pressed(KEY_D): input_dir.x += 1
	input_dir = input_dir.normalized()

	if underwater:
		velocity.y = lerp(velocity.y, -2.0, 2.0 * delta)
		if Input.is_physical_key_pressed(KEY_SPACE):
			velocity.y += 12.0 * delta
	else:
		if not is_on_floor():
			# ПАДАЄМО ШВИДКО (Нова гравітація)
			velocity.y -= gravity * delta 
		if Input.is_physical_key_pressed(KEY_SPACE) and is_on_floor():
			# Оскільки гравітація сильна, стрибок має бути потужнішим
			velocity.y = 14.0 

	var direction = (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	var target_speed = SPEED
	if underwater: target_speed = 4.0
	elif Input.is_physical_key_pressed(KEY_SHIFT): target_speed = 22.0

	var accel = 8.0 if is_on_floor() else (2.0 if underwater else 1.0)

	if direction:
		velocity.x = lerp(velocity.x, direction.x * target_speed, accel * delta)
		velocity.z = lerp(velocity.z, direction.z * target_speed, accel * delta)
	else:
		# МАГІЯ ЖОРСТКОЇ ЗУПИНКИ (світ більше не плаватиме)
		velocity.x = move_toward(velocity.x, 0, SPEED)
		velocity.z = move_toward(velocity.z, 0, SPEED)

	var speed_length = Vector2(velocity.x, velocity.z).length()
	if is_on_floor() and speed_length > 1.0 and not underwater:
		t_bob += delta * speed_length
	else:
		t_bob = lerp(t_bob, 0.0, delta * 5.0)

	camera.position.y = sin(t_bob * BOB_FREQ) * BOB_AMP + 1.7
	camera.position.x = cos(t_bob * BOB_FREQ / 2.0) * BOB_AMP * 1.5

	# ЦЕЙ РЯДОК ФІЗИЧНО РУХАЄ ТЕБЕ (Без нього ти стояв на місці)
	move_and_slide()
