extends Node3D

const Player = preload("res://scripts/player.gd")
const World = preload("res://scripts/voxel_world.gd")
const Items = preload("res://scripts/item_store.gd")
const DroppedItem = preload("res://scripts/dropped_item.gd")
const BlockIcon = preload("res://scripts/block_icon.gd")
var world: World
var player: Player
var npc: CharacterBody3D
var npc_origin := Vector3.ZERO
var elapsed := 0.0
var message_time := 0.0
var started := false
var selected_slot := 0
var bag := Items.new()
var bag_hotbar_buttons: Array[Button] = []
var craft_buttons: Array[Button] = []
var craft_output: Button
var cursor_visual: Button
var inventory_hint: Label
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
var inventory_buttons: Array[Button] = []
var frame_samples: Array[float] = []
var fps_timer := 0.0
var ready_announced := false
var test_mode := false

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
	var help := make_label("WASD 移动 · 空格 跳跃 · 左键 采集/挖掘 · 右键 放置\n1–9 / 滚轮 切换 · B 背包 · Q 丢弃 · E 交谈 · Esc 菜单", 16)
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
		var button := make_item_button(Vector2(76, 74))
		button.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bar.add_child(button)
		hotbar_buttons.append(button)
	message = make_label("", 20)
	message.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	message.position = Vector2(-360, -145)
	hud.add_child(message)
	create_menu()
	create_inventory()
	refresh_inventory()
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
	column.add_child(make_label("远古生存 · 采集与搓绳\n原型 0.3 / 128 × 128 / 世界种子 42817", 22))
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
	column.add_child(make_label("空手开局 · 堆叠上限 9 · 退出后进度暂不保存。", 16))

func create_inventory() -> void:
	inventory = Control.new()
	inventory.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ui.add_child(inventory)
	var shade := ColorRect.new()
	shade.color = Color(0.015, 0.03, 0.04, 0.82)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	inventory.add_child(shade)
	var panel := PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	panel.position = Vector2(-402, -323)
	panel.custom_minimum_size = Vector2(804, 646)
	panel.add_theme_stylebox_override("panel", panel_style(Color("14252d"), Color("7a9c96"), 2))
	inventory.add_child(panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 7)
	panel.add_child(column)
	column.add_child(make_label("行囊 / 徒手制作", 27))
	column.add_child(make_label("左键：拿起 / 放下 / 合并    右键：取一半 / 放 1 个\nQ：丢 1 个    Ctrl+Q：丢整叠    每格最多 9 个", 15))
	var craft_row := HBoxContainer.new()
	craft_row.add_theme_constant_override("separation", 12)
	column.add_child(craft_row)
	for i in range(2):
		var button := make_item_button(Vector2(76, 65))
		connect_slot(button, "craft", i)
		craft_buttons.append(button)
		craft_row.add_child(button)
	craft_row.add_child(make_label(" → ", 28))
	craft_output = make_item_button(Vector2(88, 65))
	craft_output.pressed.connect(craft_rope)
	craft_row.add_child(craft_output)
	craft_row.add_child(make_label("手工配方：植物纤维 ×2 → 粗绳 ×1\n材料可放一格或分两格，点击成品制作\n成品优先入包，放不下才掉到地上", 15))
	column.add_child(make_label("背包 · 27 格", 17))
	var grid := GridContainer.new()
	grid.columns = 9
	grid.add_theme_constant_override("h_separation", 5)
	grid.add_theme_constant_override("v_separation", 5)
	column.add_child(grid)
	for index in range(9, Items.SLOT_COUNT):
		var button := make_item_button(Vector2(76, 58))
		connect_slot(button, "storage", index)
		grid.add_child(button)
		inventory_buttons.append(button)
	column.add_child(make_label("快捷栏 · 9 格（数字 1–9 选择当前格）", 17))
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 5)
	column.add_child(bar)
	for i in range(9):
		var button := make_item_button(Vector2(76, 58))
		connect_slot(button, "storage", i)
		bar.add_child(button)
		bag_hotbar_buttons.append(button)
	inventory_hint = make_label("开局没有物品：左键采集碎石、枯枝、草与浅黄色纤维植物。", 15)
	column.add_child(inventory_hint)
	var close := Button.new()
	close.text = "返回游戏 [ B / Esc ] · 手上与手工区材料会自动收回"
	close.custom_minimum_size.y = 34
	close.focus_mode = Control.FOCUS_NONE
	close.pressed.connect(func(): toggle_inventory(false))
	column.add_child(close)
	inventory.hide()
	cursor_visual = make_item_button(Vector2(76, 74))
	cursor_visual.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(cursor_visual)
	cursor_visual.hide()

func make_item_button(dimensions: Vector2) -> Button:
	var button := Button.new()
	button.custom_minimum_size = dimensions
	button.focus_mode = Control.FOCUS_NONE
	button.add_theme_stylebox_override("normal", panel_style(Color("25363b")))
	var icon := BlockIcon.new()
	icon.name = "Icon"
	icon.position = Vector2(20, 3)
	icon.size = Vector2(34, 34) if dimensions.y >= 65 else Vector2(29, 29)
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(icon)
	var label := make_label("", 11)
	label.name = "Caption"
	label.position = Vector2(3, dimensions.y - 23)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(label)
	var count := make_label("", 16)
	count.name = "Count"
	count.position = Vector2(dimensions.x - 18, 2)
	count.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(count)
	return button

func connect_slot(button: Button, section: String, index: int) -> void:
	button.set_meta("section", section)
	button.set_meta("slot_index", index)
	button.gui_input.connect(slot_input.bind(section, index))

func slot_input(event: InputEvent, section: String, index: int) -> void:
	if not inventory.visible: return
	if event is InputEventMouseButton and event.pressed and event.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT]:
		bag.click(section, index, event.button_index == MOUSE_BUTTON_RIGHT)
		refresh_inventory()
		get_viewport().set_input_as_handled()

func render_item(button: Button, cell: Dictionary, prefix := "", selected := false) -> void:
	var occupied: bool = cell.count > 0
	var icon := button.get_node("Icon") as Control
	icon.visible = occupied
	if occupied:
		icon.kind = cell.kind
		icon.color = Items.COLORS[cell.kind]
		icon.grass = cell.kind == 0
		icon.queue_redraw()
	var short_name := "空" if not occupied else str(Items.NAMES[cell.kind]).replace("方块", "").replace("植物", "")
	button.get_node("Caption").text = prefix + short_name
	button.get_node("Count").text = str(cell.count) if occupied else ""
	button.tooltip_text = "%s ×%d / %d" % [Items.NAMES[cell.kind], cell.count, Items.MAX_STACK] if occupied else "空格"
	button.add_theme_stylebox_override("normal", panel_style(Color("3b514c") if selected else Color("25363b"), Color("f3d38a") if selected else Color("40545b"), 3 if selected else 1))

func refresh_inventory() -> void:
	for i in range(9):
		render_item(hotbar_buttons[i], bag.storage[i], str(i + 1) + " ", i == selected_slot)
		render_item(bag_hotbar_buttons[i], bag.storage[i], str(i + 1) + " ", i == selected_slot)
	for i in range(inventory_buttons.size()): render_item(inventory_buttons[i], bag.storage[i + 9])
	for i in range(2): render_item(craft_buttons[i], bag.craft[i], str(i + 1) + " ")
	var recipe := bag.can_craft()
	render_item(craft_output, Items.stack(Items.ROPE, 1) if recipe else Items.empty())
	craft_output.disabled = not recipe
	craft_output.tooltip_text = "点击：消耗 2 份植物纤维，制作 1 根粗绳" if recipe else "需要 2 份植物纤维"
	render_item(cursor_visual, bag.cursor)
	cursor_visual.visible = inventory.visible and bag.cursor.count > 0
	var cell := bag.storage[selected_slot]
	status.text = "当前：空手" if cell.count == 0 else "当前：%s ×%d" % [Items.NAMES[cell.kind], cell.count]
	status.text += "  |  快捷格 " + str(selected_slot + 1)

func choose_slot(slot: int) -> void:
	selected_slot = posmod(slot, 9)
	refresh_inventory()

func return_held_items() -> void:
	var held := bag.cursor.duplicate()
	bag.cursor = Items.empty()
	var cells: Array[Dictionary] = [held, bag.craft[0].duplicate(), bag.craft[1].duplicate()]
	bag.craft[0] = Items.empty()
	bag.craft[1] = Items.empty()
	for cell in cells:
		if cell.count > 0: receive_item(cell.kind, cell.count)

func toggle_inventory(opening: bool) -> void:
	if not started or menu.visible: return
	if not opening: return_held_items()
	inventory.visible = opening
	player.active = not opening
	selection.visible = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if opening else Input.MOUSE_MODE_CAPTURED
	refresh_inventory()

func notice(text: String) -> void:
	message.text = text
	message_time = 3.0
	inventory_hint.text = text

func receive_item(kind: int, amount: int) -> void:
	var remainder := bag.add(kind, amount)
	if remainder > 0:
		spawn_drop(kind, remainder)
		notice("背包已满，" + Items.NAMES[kind] + " ×" + str(remainder) + " 掉在附近")
	else:
		notice("获得 " + Items.NAMES[kind] + " ×" + str(amount))
	refresh_inventory()

func craft_rope() -> void:
	if not inventory.visible or not bag.craft_once(): return
	receive_item(Items.ROPE, 1)
	refresh_inventory()

func spawn_drop(kind: int, amount: int) -> void:
	var direction := -player.camera.global_transform.basis.z
	var at := player.position + Vector3.UP * 1.2 + direction * 0.65
	if world.get_kind(Vector3i(at.floor())) >= 0 or not world.position_ready(at): at = player.position + Vector3.UP * 0.9
	while amount > 0:
		var drop := DroppedItem.new()
		drop.kind = kind
		drop.count = mini(Items.MAX_STACK, amount)
		drop.position = at
		drop.velocity = direction * 2.5 + Vector3.UP * 1.8
		add_child(drop)
		amount -= drop.count

func drop_item(section: String, index: int, entire: bool) -> void:
	var cell := bag.extract(section, index, entire)
	if cell.count == 0: return
	spawn_drop(cell.kind, cell.count)
	notice("丢弃 " + Items.NAMES[cell.kind] + " ×" + str(cell.count))
	refresh_inventory()

func _input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo: return
	if event.keycode != KEY_Q or not started or menu.visible: return
	if inventory.visible:
		if bag.cursor.count > 0:
			drop_item("cursor", 0, event.ctrl_pressed)
		else:
			var hovered := get_viewport().gui_get_hovered_control()
			while hovered != null and not hovered.has_meta("section"): hovered = hovered.get_parent_control()
			if hovered != null: drop_item(hovered.get_meta("section"), hovered.get_meta("slot_index"), event.ctrl_pressed)
	else:
		drop_item("storage", selected_slot, event.ctrl_pressed)
	get_viewport().set_input_as_handled()

func start_game() -> void:
	if not world.spawn_ready(): return
	if not started: respawn()
	started = true
	player.active = true
	menu.hide()
	inventory.hide()
	hud.show()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func voxel_target() -> Dictionary:
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
			return {"cell": cell, "normal": normal, "distance": distance}
		var axis := 0
		if t_max.y < t_max.x: axis = 1
		if t_max.z < t_max[axis]: axis = 2
		distance = t_max[axis]
		cell[axis] += step[axis]
		t_max[axis] += t_delta[axis]
		normal = Vector3i.ZERO
		normal[axis] = -step[axis]
	return {}

func target() -> Dictionary:
	var block := voxel_target()
	var distance: float = block.distance if not block.is_empty() else 6.0
	var resource := world.resource_target(player.camera.global_position, -player.camera.global_transform.basis.z, distance)
	if not resource.is_empty():
		var query := PhysicsRayQueryParameters3D.create(player.camera.global_position, resource.at, 2)
		if get_world_3d().direct_space_state.intersect_ray(query).is_empty(): return resource
	return block

func gather(cell: Vector3i) -> bool:
	var kind := world.take_resource(cell)
	if kind < 0: return false
	receive_item(kind, 1)
	return true

func mine(cell: Vector3i) -> bool:
	var kind := world.get_kind(cell)
	if kind < 0: return false
	# Collect a plant/stone above the mined support rather than silently deleting it.
	gather(cell)
	if not world.set_block(cell, -1): return false
	receive_item(kind, 1)
	return true

func place_block(cell: Vector3i) -> bool:
	var held := bag.storage[selected_slot]
	if held.count <= 0 or held.kind >= World.NAMES.size():
		notice("当前物品不能放成方块，请先挖掘并选择方块")
		return false
	if world.get_kind(cell) >= 0: return false
	var player_box := AABB(player.position + Vector3(-0.35, 0, -0.35), Vector3(0.7, 1.8, 0.7))
	var npc_box := AABB(npc.position + Vector3(-0.4, 0, -0.4), Vector3(0.8, 1.9, 0.8))
	var block_box := AABB(Vector3(cell), Vector3.ONE)
	if block_box.intersects(player_box) or block_box.intersects(npc_box): return false
	if not world.set_block(cell, held.kind): return false
	bag.extract("storage", selected_slot, false)
	refresh_inventory()
	return true

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
			message.text = "向导：采浅黄色纤维植物，按 B，用两份纤维搓一根粗绳。"
			message_time = 6
		elif event.keycode == KEY_E and player.active:
			var hit := target()
			if hit.has("resource"): gather(hit.cell)
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
		if event.button_index == MOUSE_BUTTON_LEFT:
			if hit.has("resource"): gather(cell)
			else: mine(cell)
		if event.button_index == MOUSE_BUTTON_RIGHT and not hit.has("resource"): place_block(cell + hit.normal)

func _process(delta: float) -> void:
	if inventory.visible and bag.cursor.count > 0:
		cursor_visual.position = get_viewport().get_mouse_position() + Vector2(14, 14)
		cursor_visual.position.x = minf(cursor_visual.position.x, 1190)
		cursor_visual.position.y = minf(cursor_visual.position.y, 630)
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
	if selection.visible:
		selection.position = hit.at if hit.has("resource") else Vector3(hit.cell) + Vector3.ONE * 0.5
		selection.scale = hit.size if hit.has("resource") else Vector3.ONE
		if message_time <= 0 and hit.has("resource"): message.text = "左键采集：" + Items.NAMES[hit.kind]

func key_event(code: Key) -> void:
	var key := InputEventKey.new()
	key.keycode = code
	key.pressed = true
	_unhandled_input(key)

func wait_idle(limit := 3000) -> bool:
	for frame in range(limit):
		await get_tree().process_frame
		if world.initialized and world.pending.is_empty() and not world.worker.is_started(): return true
	push_error("Chunk queue timed out")
	return false

func smoke_test() -> void:
	var suite = load("res://tests/game_smoke.gd").new()
	await suite.run(self)
