extends SceneTree
var errors := 0
func _initialize() -> void:
	call_deferred("run")
func expect(ok: bool, text: String) -> void:
	if not ok:
		errors += 1
		push_error("VISUAL INPUT FAILED: " + text)
func press(code: Key) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = true
	Input.parse_input_event(event)
	await process_frame
	event = InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	Input.parse_input_event(event)
	await process_frame
func point(at: Vector2) -> void:
	Input.warp_mouse(at)
	var motion := InputEventMouseMotion.new()
	motion.position = at
	motion.global_position = at
	Input.parse_input_event(motion)
	await process_frame
	await process_frame
func click(button: Control, right := false) -> void:
	await point(button.get_global_rect().get_center())
	var event := InputEventMouseButton.new()
	event.position = button.get_global_rect().get_center()
	event.global_position = event.position
	event.button_index = MOUSE_BUTTON_RIGHT if right else MOUSE_BUTTON_LEFT
	event.pressed = true
	Input.parse_input_event(event)
	await process_frame
	event = InputEventMouseButton.new()
	event.position = button.get_global_rect().get_center()
	event.button_index = MOUSE_BUTTON_RIGHT if right else MOUSE_BUTTON_LEFT
	Input.parse_input_event(event)
	await process_frame
func capture(path: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(path)
func run() -> void:
	var game = load("res://main.tscn").instantiate()
	root.add_child(game)
	for frame in range(1800):
		await process_frame
		if game.ready_announced: break
	game.start_game()
	for frame in range(90): await physics_frame
	for xz in [Vector2i(-2, 6), Vector2i(-1, 5)]:
		var cell := Vector3i(xz.x, game.world.height_at(xz.x, xz.y), xz.y)
		var info: Dictionary = game.world.resource_at(cell)
		game.player.camera.look_at(info.at)
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = true
		Input.parse_input_event(event)
		await process_frame
		event = InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		Input.parse_input_event(event)
		await process_frame
	expect(game.bag.total(11) == 2, "two plants harvested via real input")
	game.player.rotation.y = 0.8
	game.player.camera.rotation = Vector3(-0.18, 0, 0)
	for frame in range(150): await process_frame
	await capture("/tmp/blocklands-v03-game.png")
	await press(KEY_B)
	expect(game.inventory.visible, "B routes through real input")
	await click(game.bag_hotbar_buttons[0])
	expect(game.bag.cursor.count == 2, "left click picks fiber stack")
	await click(game.craft_buttons[0], true)
	await click(game.craft_buttons[1])
	expect(game.bag.can_craft(), "actual right/left clicks populate craft inputs")
	await capture("/tmp/blocklands-v03-craft.png")
	await point(game.craft_output.get_global_rect().get_center())
	await press(KEY_Q)
	expect(game.bag.total(11) == 2 and get_nodes_in_group("dropped_items").is_empty(), "Q cannot drop a recipe preview")
	await click(game.craft_output)
	expect(game.bag.total(12) == 1 and game.bag.total(11) == 0, "output click creates rope")
	await point(game.bag_hotbar_buttons[0].get_global_rect().get_center())
	await press(KEY_Q)
	expect(game.bag.total(12) == 0, "hovered-slot Q removes rope")
	var drop_total := 0
	for drop in get_nodes_in_group("dropped_items"): drop_total += int(drop.count)
	expect(drop_total == 1, "hovered-slot Q creates exactly one ground item")
	await point(Vector2(20, 600))
	await press(KEY_Q)
	expect(get_nodes_in_group("dropped_items").size() == 1, "Q on background does nothing")
	await capture("/tmp/blocklands-v03-inventory.png")
	await press(KEY_B)
	expect(game.player.active and not game.inventory.visible, "B closes inventory")
	print("VISUAL INPUT CHECKS COMPLETE; failures=", errors)
	quit(1 if errors else 0)
