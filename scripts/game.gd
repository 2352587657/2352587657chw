extends Node3D

const Player = preload("res://scripts/player.gd")
const World = preload("res://scripts/voxel_world.gd")
const BlockIcon = preload("res://scripts/block_icon.gd")
var world: World
var player: Player
var npc: CharacterBody3D
var npc_origin := Vector3.ZERO
var elapsed := 0.0
var message_time := 0.0
var started := false
var selected_slot := 0
var slots: Array[int] = [0, 1, 2, 3, 4, 5, 6, 7, 8]
var ui: CanvasLayer
var menu: Control
var hud: Control
var inventory: Control
var status: Label
var message: Label
var fps_label: Label
var loading: Label
var play_button: Button
var selection: MeshInstance3D
var hotbar_buttons: Array[Button] = []
var slot_icons: Array[Control] = []
var inventory_buttons: Array[Button] = []
var frame_samples: Array[float] = []
var fps_timer := 0.0
var ready_announced := false
var test_mode := false
var failures := 0
var checkpoint: Vector3

func material(color: Color) -> StandardMaterial3D:
	var result := StandardMaterial3D.new()
	result.albedo_color = color
	result.roughness = 0.95
	return result

func _ready() -> void:
	test_mode = "--smoke-test" in OS.get_cmdline_user_args()
	var environment := WorldEnvironment.new()
	var atmosphere := Environment.new()
	atmosphere.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sky_material := ProceduralSkyMaterial.new()
	sky_material.sky_top_color = Color("4c8cb6")
	sky_material.sky_horizon_color = Color("b5d2d8")
	sky_material.ground_horizon_color = Color("b5d2d8")
	sky.sky_material = sky_material
	atmosphere.sky = sky
	atmosphere.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	atmosphere.ambient_light_color = Color("c4dce7")
	atmosphere.ambient_light_energy = 0.65
	atmosphere.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	atmosphere.fog_enabled = true
	atmosphere.fog_light_color = Color("b5d2d8")
	atmosphere.fog_density = 0.009
	environment.environment = atmosphere
	add_child(environment)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-48, -30, 0)
	sun.light_energy = 1.3
	add_child(sun)
	world = World.new()
	add_child(world)
	var water := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(World.HALF * 2, World.HALF * 2)
	water.mesh = plane
	water.position.y = 0.55
	var blue := material(Color(0.16, 0.48, 0.66, 0.8))
	blue.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	water.material_override = blue
	add_child(water)
	player = Player.new()
	add_child(player)
	player.collision_layer = 4
	player.collision_mask = 3
	player.camera.far = 80
	respawn()
	selection = MeshInstance3D.new()
	var cube := BoxMesh.new()
	cube.size = Vector3.ONE * 1.008
	selection.mesh = cube
	var outline := material(Color(1, 0.92, 0.6, 0.16))
	outline.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	outline.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	selection.material_override = outline
	selection.visible = false
	add_child(selection)
	create_ui()
	if test_mode: call_deferred("smoke_test")

func respawn() -> void:
	# Find a free two-block-tall spot above the current terrain, including player edits.
	var y := World.MIN_Y
	for h in range(World.MAX_Y - 3, World.MIN_Y - 1, -1):
		if world.get_kind(Vector3i(0, h, 9)) >= 0:
			y = h + 1
			break
	if y == World.MIN_Y: y = 6
	player.position = Vector3(0.5, y + 0.15, 9.5)
	player.velocity = Vector3.ZERO
	world.follow(player.position)

func can_move_to(at: Vector3) -> bool:
	return world.position_ready(at)
func create_npc() -> void:
	npc = CharacterBody3D.new()
	npc.name = "Guide"
	npc.collision_layer = 2
	npc.collision_mask = 1
	npc.set_meta("npc", true)
	npc.position = Vector3(3.5, world.height_at(3, 7) + 1.0, 7.5)
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


func panel_style(background: Color, border := Color("40545b"), width := 1) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.set_border_width_all(width)
	style.set_corner_radius_all(7)
	style.content_margin_left = 10
	style.content_margin_right = 10
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	return style

func make_label(text: String, font_size: int) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	return label

func create_ui() -> void:
	ui = CanvasLayer.new()
	add_child(ui)
	hud = Control.new()
	hud.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(hud)
	status = make_label("", 20)
	status.position = Vector2(24, 22)
	status.add_theme_color_override("font_shadow_color", Color.BLACK)
	status.add_theme_constant_override("shadow_offset_x", 2)
	status.add_theme_constant_override("shadow_offset_y", 2)
	hud.add_child(status)
	var fps_panel := PanelContainer.new()
	fps_panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	fps_panel.position = Vector2(-300, 16)
	fps_panel.size = Vector2(280, 85)
	fps_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fps_panel.add_theme_stylebox_override("panel", panel_style(Color(0.03, 0.07, 0.08, 0.85)))
	ui.add_child(fps_panel)
	fps_label = make_label("FPS --  |  -- ms\n正在准备地图…", 17)
	fps_panel.add_child(fps_label)
	var help := make_label("WASD 移动 · 空格 跳跃 · 左键 挖掘 · 右键 放置\n1–9 / 滚轮 切换 · B 背包 · E 交谈 · Esc 菜单", 16)
	help.position = Vector2(24, 94)
	hud.add_child(help)
	var crosshair := make_label("+", 28)
	crosshair.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	crosshair.position -= Vector2(9, 20)
	hud.add_child(crosshair)
	var bar_panel := PanelContainer.new()
	bar_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	bar_panel.position = Vector2(-374, -103)
	bar_panel.add_theme_stylebox_override("panel", panel_style(Color(0.025, 0.045, 0.05, 0.9)))
	bar_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(bar_panel)
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 5)
	bar_panel.add_child(bar)
	for i in range(9):
		var button := Button.new()
		button.custom_minimum_size = Vector2(76, 74)
		button.focus_mode = Control.FOCUS_NONE
		button.mouse_filter = Control.MOUSE_FILTER_IGNORE
		button.add_theme_stylebox_override("normal", panel_style(Color("25363b")))
		bar.add_child(button)
		var icon := BlockIcon.new()
		icon.position = Vector2(21, 7)
		icon.size = Vector2(36, 36)
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		button.add_child(icon)
		var label := make_label("", 12)
		label.name = "Caption"
		label.position = Vector2(5, 48)
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		button.add_child(label)
		hotbar_buttons.append(button)
		slot_icons.append(icon)
	message = make_label("", 20)
	message.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	message.position = Vector2(-360, -145)
	hud.add_child(message)
	create_menu()
	create_inventory()
	update_hotbar()
	hud.hide()

func create_menu() -> void:
	menu = Control.new()
	menu.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ui.add_child(menu)
	var shade := ColorRect.new()
	shade.color = Color(0.025, 0.055, 0.065, 0.92)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	menu.add_child(shade)
	var column := VBoxContainer.new()
	column.position = Vector2(95, 155)
	column.add_theme_constant_override("separation", 22)
	menu.add_child(column)
	column.add_child(make_label("方 野 / BLOCKLANDS", 48))
	column.add_child(make_label("河谷探索 · 自由建造\n原型 0.2 / 128 × 128 / 世界种子 42817", 22))
	play_button = Button.new()
	play_button.text = "正在准备出生点…"
	play_button.disabled = true
	play_button.custom_minimum_size = Vector2(370, 52)
	play_button.pressed.connect(start_game)
	column.add_child(play_button)
	var quit := Button.new()
	quit.text = "退出游戏"
	quit.pressed.connect(func(): get_tree().quit())
	column.add_child(quit)
	loading = make_label("正在后台生成地形数据…", 16)
	column.add_child(loading)
	column.add_child(make_label("自由建造：材料无限。退出后本次地图改动不会保存。", 16))

func create_inventory() -> void:
	inventory = Control.new()
	inventory.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ui.add_child(inventory)
	var shade := ColorRect.new()
	shade.color = Color(0.015, 0.03, 0.04, 0.78)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	inventory.add_child(shade)
	var panel := PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	panel.position = Vector2(-305, -235)
	panel.custom_minimum_size = Vector2(610, 470)
	panel.add_theme_stylebox_override("panel", panel_style(Color("14252d"), Color("7a9c96"), 2))
	inventory.add_child(panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 14)
	panel.add_child(column)
	column.add_child(make_label("背包 / 方块目录", 30))
	column.add_child(make_label("无限材料 · 点击方块放入当前快捷格\n数字 1–9 可选择要替换的快捷格", 18))
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	column.add_child(grid)
	for kind in range(World.NAMES.size()):
		var button := Button.new()
		button.custom_minimum_size = Vector2(185, 74)
		button.text = "      " + World.NAMES[kind] + "  ∞"
		button.focus_mode = Control.FOCUS_NONE
		button.add_theme_stylebox_override("normal", panel_style(Color("263c44")))
		var icon := BlockIcon.new()
		icon.color = World.COLORS[kind]
		icon.grass = kind == 0
		icon.position = Vector2(10, 17)
		icon.size = Vector2(37, 37)
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		button.add_child(icon)
		button.pressed.connect(assign_slot.bind(kind))
		grid.add_child(button)
		inventory_buttons.append(button)
	var close := Button.new()
	close.text = "返回游戏  [ B / Esc ]"
	close.custom_minimum_size.y = 44
	close.pressed.connect(func(): toggle_inventory(false))
	column.add_child(close)
	inventory.hide()

func update_hotbar() -> void:
	for i in range(9):
		var kind := slots[i]
		var button := hotbar_buttons[i]
		button.get_node("Caption").text = str(i + 1) + " " + World.NAMES[kind]
		button.add_theme_stylebox_override("normal", panel_style(Color("3b514c") if i == selected_slot else Color("25363b"), Color("f3d38a") if i == selected_slot else Color("40545b"), 3 if i == selected_slot else 1))
		slot_icons[i].color = World.COLORS[kind]
		slot_icons[i].grass = kind == 0
		slot_icons[i].queue_redraw()
	status.text = "当前：" + World.NAMES[slots[selected_slot]] + "  |  快捷格 " + str(selected_slot + 1) + "  |  材料 ∞"

func assign_slot(kind: int) -> void:
	slots[selected_slot] = kind
	update_hotbar()

func choose_slot(slot: int) -> void:
	selected_slot = posmod(slot, 9)
	update_hotbar()

func toggle_inventory(opening: bool) -> void:
	if not started or menu.visible: return
	inventory.visible = opening
	player.active = not opening
	selection.visible = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if opening else Input.MOUSE_MODE_CAPTURED

func start_game() -> void:
	if not world.spawn_ready(): return
	if not started: respawn()
	started = true
	player.active = true
	menu.hide()
	inventory.hide()
	hud.show()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func target() -> Dictionary:
	# DDA traverses voxel data directly, so targeting updates before asynchronous collision rebuilds.
	var origin := player.camera.global_position
	var direction := -player.camera.global_transform.basis.z.normalized()
	var cell := Vector3i(origin.floor())
	var step := Vector3i.ZERO
	var t_max := Vector3(INF, INF, INF)
	var t_delta := Vector3(INF, INF, INF)
	for axis in range(3):
		if absf(direction[axis]) < 0.000001: continue
		step[axis] = 1 if direction[axis] > 0 else -1
		var boundary := float(cell[axis] + (1 if direction[axis] > 0 else 0))
		t_max[axis] = (boundary - origin[axis]) / direction[axis]
		t_delta[axis] = absf(1.0 / direction[axis])
	var distance := 0.0
	var normal := Vector3i.ZERO
	while distance <= 6:
		if world.get_kind(cell) >= 0:
			var query := PhysicsRayQueryParameters3D.create(origin, origin + direction * distance, 2)
			if distance > 0 and not get_world_3d().direct_space_state.intersect_ray(query).is_empty(): return {}
			return {"cell": cell, "normal": normal}
		var axis := 0
		if t_max.y < t_max.x: axis = 1
		if t_max.z < t_max[axis]: axis = 2
		distance = t_max[axis]
		cell[axis] += step[axis]
		t_max[axis] += t_delta[axis]
		normal = Vector3i.ZERO
		normal[axis] = -step[axis]
	return {}

func place_block(cell: Vector3i) -> bool:
	if world.get_kind(cell) >= 0: return false
	var player_box := AABB(player.position + Vector3(-0.35, 0, -0.35), Vector3(0.7, 1.8, 0.7))
	var npc_box := AABB(npc.position + Vector3(-0.4, 0, -0.4), Vector3(0.8, 1.9, 0.8))
	var block_box := AABB(Vector3(cell), Vector3.ONE)
	if block_box.intersects(player_box) or block_box.intersects(npc_box): return false
	return world.set_block(cell, slots[selected_slot])

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_B and started and not menu.visible:
			toggle_inventory(not inventory.visible)
			return
		if event.keycode == KEY_ESCAPE and started:
			if inventory.visible:
				toggle_inventory(false)
			else:
				menu.visible = not menu.visible
				player.active = not menu.visible
				selection.visible = false
				Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if menu.visible else Input.MOUSE_MODE_CAPTURED
			return
		if started and not menu.visible and event.keycode >= KEY_1 and event.keycode <= KEY_9: choose_slot(event.keycode - KEY_1)
		if event.keycode == KEY_E and player.active and player.position.distance_to(npc.position) < 4:
			message.text = "向导：按 B 打开背包，滚轮选择材料。去河对岸看看吧！"
			message_time = 6
	if not player.active or menu.visible or inventory.visible: return
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			choose_slot(selected_slot - 1)
			return
		if event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			choose_slot(selected_slot + 1)
			return
		var hit := target()
		if hit.is_empty(): return
		var cell: Vector3i = hit.cell
		if event.button_index == MOUSE_BUTTON_LEFT: world.set_block(cell, -1)
		if event.button_index == MOUSE_BUTTON_RIGHT: place_block(cell + hit.normal)

func _process(delta: float) -> void:
	frame_samples.append(delta * 1000)
	if frame_samples.size() > 120: frame_samples.pop_front()
	fps_timer += delta
	if fps_timer >= 0.25:
		fps_timer = 0
		var worst := 0.0
		var sum := 0.0
		for value in frame_samples:
			sum += value
			worst = maxf(worst, value)
		var average := sum / maxf(1, frame_samples.size())
		fps_label.text = "%d FPS | %.1f ms\n近120帧峰值 %.1f ms\n区块 %d / 队列 %d" % [Engine.get_frames_per_second(), average, worst, world.chunks.size(), world.pending.size() + (1 if world.worker.is_started() else 0)]
		fps_label.modulate = Color("ffc391") if average > 33.4 else Color("cce5cb")
	if not ready_announced:
		if world.initialized:
			loading.text = "出生点准备中 · 已加载 %d 个区块" % world.chunks.size()
		if world.spawn_ready():
			ready_announced = true
			create_npc()
			respawn()
			play_button.disabled = false
			play_button.text = "开始 / 继续游戏"
			loading.text = "出生点已就绪 · 远处地形将逐步加载"
	if started: world.follow(player.position)

func _physics_process(delta: float) -> void:
	if not started or not player.active or npc == null: return
	elapsed += delta
	var heading := Vector3(sin(elapsed * 0.4), 0, cos(elapsed * 0.4))
	if npc.position.distance_to(npc_origin) > 3: heading = (npc_origin - npc.position).normalized()
	var next := npc.position + heading * 0.8
	var query := PhysicsRayQueryParameters3D.create(npc.position + Vector3.UP * 0.6, next + Vector3.UP * 0.6, 1)
	# Do not walk into an unready chunk or a mined hole.
	var below := Vector3i((next - Vector3.UP * 0.1).floor())
	if not world.position_ready(next) or world.get_kind(below) < 0 or not get_world_3d().direct_space_state.intersect_ray(query).is_empty(): heading = Vector3(-heading.z, 0, heading.x)
	npc.velocity.x = heading.x * 0.65
	npc.velocity.z = heading.z * 0.65
	if not npc.is_on_floor(): npc.velocity.y -= 22 * delta
	else: npc.velocity.y = 0
	npc.move_and_slide()
	if npc.position.y < World.MIN_Y - 5: npc.position = npc_origin
	message_time -= delta
	if message_time <= 0:
		message.text = "按 E 与向导交谈" if player.position.distance_to(npc.position) < 4 else ""
		if absf(player.position.x) > 62 or absf(player.position.z) > 62: message.text = "已到达本次地图边界"
	var hit := target()
	selection.visible = not hit.is_empty()
	if selection.visible: selection.position = Vector3(hit.cell) + Vector3.ONE * 0.5

func check(condition: bool, description: String) -> void:
	if not condition:
		failures += 1
		push_error("CHECK FAILED: " + description)

func key_event(code: Key) -> void:
	var key := InputEventKey.new()
	key.keycode = code
	key.pressed = true
	_unhandled_input(key)

func wait_idle(limit := 3000) -> void:
	for frame in range(limit):
		await get_tree().process_frame
		if world.initialized and world.pending.is_empty() and not world.worker.is_started(): return
	check(false, "chunk queue timed out")

func smoke_test() -> void:
	var deadline := Time.get_ticks_msec() + 90000
	while not ready_announced:
		await get_tree().process_frame
		if Time.get_ticks_msec() > deadline:
			check(false, "spawn loading timed out")
			get_tree().quit(1)
			return
	start_game()
	check(world.data.size() == 64, "128x128 map contains 64 chunks")
	# Two touching identical cubes become six rectangles, with no internal faces.
	var padded := PackedByteArray()
	padded.resize(18 * 18 * (World.HEIGHT + 2))
	padded[(2 * 18 + 2) * (World.HEIGHT + 2) + 2] = 3
	padded[(3 * 18 + 2) * (World.HEIGHT + 2) + 2] = 3
	var greedy := World._mesh_chunk(padded)
	check(greedy.quads == 6, "greedy merges neighboring cubes into six exterior faces")
	check(world.position_ready(player.position), "spawn collisions ready")
	check(hotbar_buttons.size() == 9, "nine visible slots")
	key_event(KEY_9)
	check(selected_slot == 8, "number-key slot selection")
	var wheel := InputEventMouseButton.new()
	wheel.button_index = MOUSE_BUTTON_WHEEL_DOWN
	wheel.pressed = true
	_unhandled_input(wheel)
	check(selected_slot == 0, "wheel wraps to first slot")
	key_event(KEY_B)
	check(inventory.visible and not player.active, "B opens inventory and freezes player")
	inventory_buttons[7].pressed.emit()
	check(slots[0] == 7, "inventory button assigns hotbar item")
	key_event(KEY_ESCAPE)
	check(not inventory.visible and player.active and not menu.visible, "Esc closes inventory only")
	for frame in range(120): await get_tree().physics_frame
	check(player.is_on_floor(), "player lands on greedy terrain collision")
	player.camera.rotation.x = -1.4
	var hit := target()
	check(not hit.is_empty(), "voxel DDA targets ground")
	if not hit.is_empty():
		var cell: Vector3i = hit.cell
		var click := InputEventMouseButton.new()
		click.pressed = true
		click.button_index = MOUSE_BUTTON_LEFT
		_unhandled_input(click)
		check(world.get_kind(cell) == -1, "mouse mining changes voxel data immediately")
		world.set_block(cell, 0)
	check(not place_block(Vector3i((player.position + Vector3.UP * 0.9).floor())), "body overlap rejected")
	check(place_block(Vector3i(2, 12, 10)), "construction accepted")
	check(world.get_kind(Vector3i(2, 12, 10)) == 7, "construction uses selected inventory block")
	# Boundary edits must dirty exactly the touching chunks, including negative coordinates.
	var before_a: int = world.revisions.get(Vector2i(0, 0), 0)
	var before_b: int = world.revisions.get(Vector2i(-1, 0), 0)
	world.set_block(Vector3i(0, 10, 8), 8)
	check(world.revisions[Vector2i(0, 0)] == before_a + 1 and world.revisions[Vector2i(-1, 0)] == before_b + 1, "boundary edits invalidate neighboring mesh")
	await wait_idle()
	# The neighbor that was edited while a mesh was building must retain the latest revision.
	world.set_block(Vector3i(0, 10, 8), 6)
	world.set_block(Vector3i(0, 10, 8), 8)
	await wait_idle()
	check(world.get_kind(Vector3i(0, 10, 8)) == 8, "rapid edits keep latest value")
	# Stream far enough to unload the edited origin, then come back.
	checkpoint = player.position
	player.active = false
	player.position = Vector3(48.5, 30, 48.5)
	world.follow(player.position)
	await wait_idle()
	check(not world.chunks.has(Vector2i(0, 0)), "distant origin scene unloaded")
	check(world.chunks.size() <= 25, "bounded visible chunk count")
	check(world.get_kind(Vector3i(0, 10, 8)) == 8, "unloaded chunk edits retained")
	player.position = checkpoint
	world.follow(player.position)
	await wait_idle()
	check(world.position_ready(player.position), "return collisions restored")
	check(world.get_kind(Vector3i(0, 10, 8)) == 8, "return preserves modifications")
	start_game()
	player.position = npc.position + Vector3.RIGHT
	key_event(KEY_E)
	check(message.text.begins_with("向导："), "NPC dialogue")
	key_event(KEY_ESCAPE)
	check(menu.visible and not player.active, "pause menu")
	start_game()
	check(not menu.visible and player.active, "resume")
	check(not can_move_to(Vector3(64.2, 6, 0)), "world boundary guarded")
	print("METRICS: generation %.1f ms, meshes %d, last mesh %.1f ms, last main-thread install %.1f ms, visible chunks %d, scene nodes %d" % [world.generation_ms, world.meshes_built, world.last_mesh_ms, world.last_apply_ms, world.chunks.size(), get_tree().get_node_count()])
	print("MAIN THREAD: max snapshot %.2f ms, max chunk install %.2f ms" % [world.max_snapshot_ms, world.max_apply_ms])
	if failures == 0: print("SMOKE PASS: larger map, greedy collision, mining, building, boundary edits, streaming persistence, FPS HUD, hotbar, inventory, NPC, menus")
	get_tree().quit(1 if failures else 0)
