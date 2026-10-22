extends CharacterBody3D

var camera: Camera3D
var active := false
var speed := 6.0

func _ready() -> void:
	var shape := CapsuleShape3D.new()
	shape.radius = 0.3
	shape.height = 1.8
	var collider := CollisionShape3D.new()
	collider.shape = shape
	collider.position.y = 0.9
	add_child(collider)
	camera = Camera3D.new()
	camera.position.y = 1.62
	camera.fov = 78
	add_child(camera)

func _unhandled_input(event: InputEvent) -> void:
	if active and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and event is InputEventMouseMotion:
		rotate_y(-event.relative.x * 0.0025)
		camera.rotation.x = clampf(camera.rotation.x - event.relative.y * 0.0025, -1.5, 1.5)

func _physics_process(delta: float) -> void:
	if not active:
		return
	var direction := Vector3.ZERO
	if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		if Input.is_physical_key_pressed(KEY_W): direction.z -= 1
		if Input.is_physical_key_pressed(KEY_S): direction.z += 1
		if Input.is_physical_key_pressed(KEY_A): direction.x -= 1
		if Input.is_physical_key_pressed(KEY_D): direction.x += 1
		if Input.is_physical_key_pressed(KEY_SPACE) and is_on_floor(): velocity.y = 7.5
	direction = (transform.basis * direction).normalized()
	velocity.x = direction.x * speed
	velocity.z = direction.z * speed
	if not is_on_floor(): velocity.y -= 22 * delta
	var next := position + Vector3(velocity.x, 0, velocity.z) * delta
	if not get_parent().can_move_to(next):
		velocity.x = 0
		velocity.z = 0
	if not get_parent().can_move_to(position):
		velocity.y = 0
		return
	move_and_slide()
	if position.y < -14:
		get_parent().respawn()
