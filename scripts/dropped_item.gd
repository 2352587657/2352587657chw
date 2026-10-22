extends CharacterBody3D
const Items = preload("res://scripts/item_store.gd")
## One physical stack, not one body per item. Suspends physics in unloaded chunks.
var kind := 0
var count := 1
var cooldown := 1.2
var age := 0.0
var visual: MeshInstance3D
var caption: Label3D
var resting := false

func _ready() -> void:
	collision_layer = 0
	collision_mask = 1
	add_to_group("dropped_items")
	var collider := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 0.12
	collider.shape = sphere
	add_child(collider)
	visual = MeshInstance3D.new()
	var cube := BoxMesh.new()
	cube.size = Vector3.ONE * 0.22
	visual.mesh = cube
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Items.COLORS[kind]
	visual.material_override = mat
	add_child(visual)
	caption = Label3D.new()
	caption.text = Items.NAMES[kind] + " ×" + str(count)
	caption.position.y = 0.38
	caption.font_size = 24
	caption.pixel_size = 0.004
	caption.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	caption.visibility_range_end = 12
	add_child(caption)

func _physics_process(delta: float) -> void:
	var game := get_parent()
	if not game.started or not game.player.active: return
	age += delta
	cooldown = maxf(0, cooldown - delta)
	if not game.world.position_ready(position): return
	if not resting:
		velocity.y -= 15 * delta
		move_and_slide()
		if is_on_floor():
			velocity = Vector3.ZERO
			resting = true
	else:
		# A mined support wakes the dropped stack without permanent rigid-body simulation.
		if game.world.get_kind(Vector3i((position - Vector3.UP * 0.2).floor())) < 0: resting = false
	position.x = clampf(position.x, -63.7, 63.7)
	position.z = clampf(position.z, -63.7, 63.7)
	if position.y < -13:
		position = Vector3(0.5, game.world.height_at(0, 9) + 2, 9.5)
		velocity = Vector3.ZERO
	visual.rotation.y += delta * 0.7
	if cooldown > 0 or position.distance_to(game.player.position + Vector3.UP * 0.7) > 1.65: return
	var query := PhysicsRayQueryParameters3D.create(position, game.player.position + Vector3.UP * 0.7, 1)
	if not get_world_3d().direct_space_state.intersect_ray(query).is_empty(): return
	var remainder: int = game.bag.add(kind, count)
	if remainder != count:
		game.notice("拾取 " + Items.NAMES[kind] + " ×" + str(count - remainder))
		count = remainder
		caption.text = Items.NAMES[kind] + " ×" + str(count)
		game.refresh_inventory()
	if count == 0:
		set_physics_process(false)
		queue_free()
