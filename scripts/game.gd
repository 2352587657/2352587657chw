extends Node3D

const Player = preload("res://scripts/player.gd")
const WORLD_SIZE := 22
var blocks: Dictionary = {}
var materials: Array[StandardMaterial3D] = []
var player: Player
var ui: CanvasLayer
var menu: Control
var hud: Control
var status: Label
var message: Label
var selection: MeshInstance3D
var selected_kind := 0
var spawn := Vector3(0.5, 8, 9.5)
var npc: CharacterBody3D
var npc_origin := Vector3.ZERO
var elapsed := 0.0
var message_time := 0.0
var started := false

func material(color: Color) -> StandardMaterial3D:
	var result := StandardMaterial3D.new()
	result.albedo_color = color
	result.roughness = 0.95
	return result

func _ready() -> void:
	for color in [Color("7b9952"), Color("8b6547"), Color("88919a"), Color("795537"), Color("416c47"), Color("d5c08d")]:
		materials.append(material(color))
	var env := WorldEnvironment.new()
	var atmosphere := Environment.new()
	atmosphere.background_mode = Environment.BG_COLOR
	atmosphere.background_color = Color("9bc7dc")
	atmosphere.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	atmosphere.ambient_light_color = Color("c4dce7")
	atmosphere.ambient_light_energy = 0.65
	env.environment = atmosphere
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-48, -30, 0)
	sun.light_energy = 1.2
	add_child(sun)
	generate_world()
	player = Player.new()
	add_child(player)
	respawn()
	create_npc()
	selection = MeshInstance3D.new()
	var cube := BoxMesh.new()
	cube.size = Vector3.ONE * 1.015
	selection.mesh = cube
	var outline := material(Color(1, 0.9, 0.55, 0.18))
	outline.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	selection.material_override = outline
	add_child(selection)
	create_ui()
	if "--smoke-test" in OS.get_cmdline_user_args():
		call_deferred("smoke_test")

func height_at(x: int, z: int) -> int:
	var river := 5.0 * sin(float(z) * 0.12) - 7.0
	if absf(x - river) < 2.0: return -1
	var mountain := maxf(0, 8 - Vector2(x - 13, z + 10).length() * 0.6)
	return int(floor(1 + sin(x * 0.22) * 0.7 + cos(z * 0.2) * 0.8 + mountain))

func generate_world() -> void:
	for x in range(-WORLD_SIZE, WORLD_SIZE):
		for z in range(-WORLD_SIZE, WORLD_SIZE):
			var top := height_at(x, z)
			for y in range(-3, top + 1):
				var kind := 2 if y < top - 2 else 1
				if y == top: kind = 5 if top < 1 else 0
				add_block(Vector3i(x, y, z), kind)
			if top > 0 and posmod(x * 37 + z * 71, 113) == 0 and Vector2(x, z - 9).length() > 5:
				for y in range(top + 1, top + 4): add_block(Vector3i(x, y, z), 3)
				for dx in range(-1, 2):
					for dz in range(-1, 2):
						for dy in range(2): add_block(Vector3i(x + dx, top + 4 + dy, z + dz), 4)
			elif top > 0 and posmod(x * 17 + z * 43, 47) == 0:
				add_decoration(Vector3(x + 0.5, top + 1.15, z + 0.5), false)
			elif top > 0 and posmod(x * 31 + z * 19, 17) == 0:
				add_decoration(Vector3(x + 0.5, top + 1.22, z + 0.5), true)
	var water := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(WORLD_SIZE * 2, WORLD_SIZE * 2)
	water.mesh = plane
	water.position.y = 0.55
	var blue := material(Color(0.16, 0.48, 0.66, 0.72))
	blue.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	water.material_override = blue
	add_child(water)

func add_block(cell: Vector3i, kind: int) -> void:
	if blocks.has(cell): return
	var body := StaticBody3D.new()
	body.position = Vector3(cell) + Vector3.ONE * 0.5
	body.set_meta("cell", cell)
	body.set_meta("kind", kind)
	var mesh := MeshInstance3D.new()
	mesh.mesh = BoxMesh.new()
	mesh.material_override = materials[kind]
	body.add_child(mesh)
	var collision := CollisionShape3D.new()
	collision.shape = BoxShape3D.new()
	body.add_child(collision)
	add_child(body)
	blocks[cell] = body

func add_decoration(at: Vector3, grass: bool) -> void:
	var mesh := MeshInstance3D.new()
	if grass:
		var blade := PrismMesh.new()
		blade.size = Vector3(0.35, 0.45, 0.35)
		mesh.mesh = blade
		mesh.material_override = materials[4]
	else:
		var rock := SphereMesh.new()
		rock.radius = 0.35
		rock.height = 0.45
		mesh.mesh = rock
		mesh.material_override = materials[2]
	mesh.position = at
	add_child(mesh)

func respawn() -> void:
	spawn.y = height_at(0, 9) + 2.0
	player.position = spawn
	player.velocity = Vector3.ZERO

func create_npc() -> void:
	npc = CharacterBody3D.new()
	npc.name = "Guide"
	npc.set_meta("npc", true)
	npc.position = Vector3(3.5, height_at(3, 7) + 1.0, 7.5)
	npc_origin = npc.position
	var collision := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.35
	capsule.height = 1.8
	collision.shape = capsule
	collision.position.y = 0.9
	npc.add_child(collision)
	var body := MeshInstance3D.new()
	var shape := CapsuleMesh.new()
	shape.radius = 0.3
	shape.height = 1.25
	body.mesh = shape
	body.position.y = 0.7
	body.material_override = material(Color("d99559"))
	npc.add_child(body)
	var head := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.25
	sphere.height = 0.5
	head.mesh = sphere
	head.position.y = 1.5
	head.material_override = material(Color("f1d5ae"))
	npc.add_child(head)
	var label := Label3D.new()
	label.text = "向导 · E 交谈"
	label.position.y = 2.15
	label.font_size = 38
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	npc.add_child(label)
	add_child(npc)

func create_ui() -> void:
	ui = CanvasLayer.new()
	add_child(ui)
	hud = Control.new()
	hud.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(hud)
	status = Label.new()
	status.position = Vector2(24, 20)
	hud.add_child(status)
	var help := Label.new()
	help.text = "WASD 移动  /  鼠标 观察  /  空格 跳跃\n左键 挖掘  /  右键 放置  /  1–6 选择方块  /  E 交谈  /  Esc 菜单"
	help.position = Vector2(24, 620)
	hud.add_child(help)
	var crosshair := Label.new()
	crosshair.text = "+"
	crosshair.add_theme_font_size_override("font_size", 28)
	crosshair.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	hud.add_child(crosshair)
	message = Label.new()
	message.position = Vector2(250, 540)
	message.add_theme_font_size_override("font_size", 22)
	hud.add_child(message)
	menu = Control.new()
	menu.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ui.add_child(menu)
	var shade := ColorRect.new()
	shade.color = Color(0.035, 0.075, 0.09, 0.9)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	menu.add_child(shade)
	var column := VBoxContainer.new()
	column.position = Vector2(100, 160)
	column.add_theme_constant_override("separation", 22)
	menu.add_child(column)
	var title := Label.new()
	title.text = "方 野  /  BLOCKLANDS"
	title.add_theme_font_size_override("font_size", 48)
	column.add_child(title)
	var subtitle := Label.new()
	subtitle.text = "探索河谷，挖掘大地，搭建你的第一处家园。\n第一版原型 · 自由建造 · 友善向导"
	column.add_child(subtitle)
	var play := Button.new()
	play.text = "开始 / 继续游戏"
	play.custom_minimum_size = Vector2(340, 52)
	play.pressed.connect(start_game)
	column.add_child(play)
	var quit := Button.new()
	quit.text = "退出游戏"
	quit.pressed.connect(func(): get_tree().quit())
	column.add_child(quit)
	hud.hide()

func start_game() -> void:
	started = true
	player.active = true
	menu.hide()
	hud.show()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func target() -> Dictionary:
	var from: Vector3 = player.camera.global_position
	var to: Vector3 = from - player.camera.global_transform.basis.z * 6.0
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.exclude = [player.get_rid()]
	return get_world_3d().direct_space_state.intersect_ray(query)

func remove_block(cell: Vector3i) -> void:
	if not blocks.has(cell): return
	var body: StaticBody3D = blocks[cell]
	blocks.erase(cell)
	remove_child(body)
	body.queue_free()

func place_block(cell: Vector3i) -> bool:
	if blocks.has(cell): return false
	var player_box := AABB(player.position + Vector3(-0.35, 0.01, -0.35), Vector3(0.7, 1.8, 0.7))
	var npc_box := AABB(npc.position + Vector3(-0.4, 0, -0.4), Vector3(0.8, 1.9, 0.8))
	var block_box := AABB(Vector3(cell), Vector3.ONE)
	if block_box.intersects(player_box) or block_box.intersects(npc_box): return false
	add_block(cell, selected_kind)
	return true

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE and started:
			var opening := not menu.visible
			menu.visible = opening
			player.active = not opening
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if opening else Input.MOUSE_MODE_CAPTURED
		if event.keycode >= KEY_1 and event.keycode <= KEY_6: selected_kind = event.keycode - KEY_1
		if event.keycode == KEY_E and player.active and player.position.distance_to(npc.position) < 4:
			message.text = "向导：欢迎！用左键挖掘，右键搭建，数字键选择材料。"
			message_time = 6
	if not player.active or menu.visible: return
	if event is InputEventMouseButton and event.pressed:
		var hit := target()
		if hit.is_empty() or not hit.collider.has_meta("cell"): return
		var cell: Vector3i = hit.collider.get_meta("cell")
		if event.button_index == MOUSE_BUTTON_LEFT: remove_block(cell)
		if event.button_index == MOUSE_BUTTON_RIGHT: place_block(cell + Vector3i(hit.normal.round()))

func _physics_process(delta: float) -> void:
	if not started or not player.active: return
	elapsed += delta
	var heading := Vector3(sin(elapsed * 0.4), 0, cos(elapsed * 0.4))
	if npc.position.distance_to(npc_origin) > 3: heading = (npc_origin - npc.position).normalized()
	var obstacle := PhysicsRayQueryParameters3D.create(npc.position + Vector3.UP * 0.6, npc.position + Vector3.UP * 0.6 + heading)
	obstacle.exclude = [npc.get_rid()]
	if not get_world_3d().direct_space_state.intersect_ray(obstacle).is_empty(): heading = Vector3(-heading.z, 0, heading.x)
	npc.velocity.x = heading.x * 0.65
	npc.velocity.z = heading.z * 0.65
	if not npc.is_on_floor(): npc.velocity.y -= 22 * delta
	else: npc.velocity.y = 0
	npc.move_and_slide()
	if npc.position.y < -10: npc.position = npc_origin
	status.text = "方野 · 原型 0.1    |    当前方块：" + ["草地", "泥土", "石头", "木头", "树叶", "沙子"][selected_kind] + "    |    自由建造：材料无限"
	message_time -= delta
	if message_time <= 0: message.text = "按 E 与向导交谈" if player.position.distance_to(npc.position) < 4 else ""
	var hit := target()
	selection.visible = not hit.is_empty() and hit.collider.has_meta("cell")
	if selection.visible: selection.position = Vector3(hit.collider.get_meta("cell")) + Vector3.ONE * 0.5

func smoke_test() -> void:
	start_game()
	await get_tree().physics_frame
	await get_tree().physics_frame
	assert(blocks.size() > 5000, "Terrain generation failed")
	assert(npc != null and player.camera != null, "Characters missing")
	var cell := Vector3i(0, height_at(0, 9), 9)
	assert(blocks.has(cell))
	remove_block(cell)
	assert(not blocks.has(cell), "Mining failed")
	add_block(cell, 0)
	assert(blocks.has(cell), "Replacement failed")
	assert(not place_block(Vector3i((player.position + Vector3.UP * 0.9).floor())), "Player overlap protection failed")
	assert(place_block(Vector3i(0, 15, 0)), "Construction failed")
	for frame in range(120): await get_tree().physics_frame
	assert(player.is_on_floor(), "Player did not land on terrain")
	player.camera.rotation.x = -1.4
	await get_tree().physics_frame
	var hit := target()
	assert(not hit.is_empty() and hit.collider.has_meta("cell"), "Aim ray failed")
	var mined_cell: Vector3i = hit.collider.get_meta("cell")
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	_unhandled_input(click)
	assert(not blocks.has(mined_cell), "Mouse mining failed")
	player.position = npc.position + Vector3(1, 0, 0)
	var interact := InputEventKey.new()
	interact.keycode = KEY_E
	interact.pressed = true
	_unhandled_input(interact)
	assert(message.text.begins_with("向导："), "NPC dialogue failed")
	var escape := InputEventKey.new()
	escape.keycode = KEY_ESCAPE
	escape.pressed = true
	_unhandled_input(escape)
	assert(menu.visible and not player.active, "Pause menu failed")
	start_game()
	assert(not menu.visible and player.active, "Resume failed")
	print("SMOKE PASS: menu, terrain, player collision, mining, construction, NPC")
	get_tree().quit()
