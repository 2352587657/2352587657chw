extends RefCounted
const Items = preload("res://scripts/item_store.gd")
const World = preload("res://scripts/voxel_world.gd")
var game: Node3D
var failures := 0
var checks := 0

func expect(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("CHECK FAILED: " + description)

func click(section: String, index: int, right := false) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_RIGHT if right else MOUSE_BUTTON_LEFT
	event.pressed = true
	game.slot_input(event, section, index)

func press_q(entire := false, echo := false) -> void:
	var event := InputEventKey.new()
	event.keycode = KEY_Q
	event.pressed = true
	event.ctrl_pressed = entire
	event.echo = echo
	game._input(event)

func drops_total(kind: int) -> int:
	var count := 0
	for drop in game.get_tree().get_nodes_in_group("dropped_items"):
		if drop.kind == kind and not drop.is_queued_for_deletion(): count += int(drop.count)
	return count

func clear_drops() -> void:
	for drop in game.get_tree().get_nodes_in_group("dropped_items"):
		drop.set_physics_process(false)
		drop.queue_free()

func model_checks() -> void:
	var padded := PackedByteArray()
	padded.resize(18 * 18 * (World.HEIGHT + 2))
	padded[(2 * 18 + 2) * (World.HEIGHT + 2) + 2] = 3
	padded[(3 * 18 + 2) * (World.HEIGHT + 2) + 2] = 3
	expect(World._mesh_chunk(padded).quads == 6, "greedy meshing still merges adjacent cubes")
	var bag := Items.new()
	expect(bag.valid() and bag.total(11) == 0, "empty inventory")
	expect(bag.add(11, 20) == 0, "add beyond one stack")
	expect(bag.storage[0].count == 9 and bag.storage[1].count == 9 and bag.storage[2].count == 2, "stack cap is nine")
	bag.click("storage", 0, true)
	expect(bag.cursor.count == 5 and bag.storage[0].count == 4, "right-click takes rounded-up half")
	bag.click("storage", 2, false)
	expect(bag.storage[2].count == 7 and bag.cursor.count == 0, "left-click merges stacks")
	bag.add(2, 3)
	# Repeated arbitrary splits, merges and swaps must not create/delete any item.
	var totals: Array[int] = []
	for kind in range(Items.NAMES.size()): totals.append(bag.total(kind))
	var rng := RandomNumberGenerator.new()
	rng.seed = 9327
	for attempt in range(500):
		var section := "craft" if rng.randi_range(0, 3) == 0 else "storage"
		bag.click(section, rng.randi_range(0, 1 if section == "craft" else 35), rng.randi_range(0, 1) == 0)
		if not bag.valid():
			expect(false, "randomized transfers maintain stack limits")
			break
	var conserved := true
	for kind in range(Items.NAMES.size()):
		if bag.total(kind) != totals[kind]: conserved = false
	expect(conserved and bag.valid(), "500 transfers conserve every item and obey cap")
	var full := Items.new()
	for i in range(36): full.storage[i] = Items.stack(2, 9)
	expect(full.add(11, 2) == 2 and full.total(2) == 324, "full inventory returns overflow without changing items")
	var recipe := Items.new()
	recipe.craft[0] = Items.stack(11, 9)
	for i in range(4): expect(recipe.craft_once(), "recipe consumes exactly one pair")
	expect(not recipe.craft_once() and recipe.total(11) == 1, "odd remainder cannot craft")
	recipe.craft[1] = Items.stack(2, 1)
	expect(not recipe.can_craft(), "wrong ingredient rejected")

func run(node: Node3D) -> void:
	game = node
	model_checks()
	var deadline := Time.get_ticks_msec() + 90000
	while not game.ready_announced:
		await game.get_tree().process_frame
		if Time.get_ticks_msec() > deadline:
			expect(false, "spawn preparation timeout")
			game.get_tree().quit(1)
			return
	game.start_game()
	expect(game.bag.total(11) == 0 and game.bag.storage[0].count == 0, "actual game starts empty")
	expect(game.world.data.size() == 64 and game.world.position_ready(game.player.position), "large map and spawn collision ready")
	for frame in range(90): await game.get_tree().physics_frame
	expect(game.player.is_on_floor(), "player lands on chunk terrain")
	# Gather two real generated plants through the same aim/click path as gameplay.
	for xz in [Vector2i(-2, 6), Vector2i(-1, 5)]:
		var cell := Vector3i(xz.x, game.world.height_at(xz.x, xz.y), xz.y)
		var info: Dictionary = game.world.resource_at(cell)
		expect(not info.is_empty() and info.kind == 11, "fiber plants available at spawn")
		if info.is_empty(): continue
		game.player.camera.look_at(info.at)
		var hit: Dictionary = game.target()
		expect(hit.has("resource") and hit.cell == cell, "ray targets real fiber plant before terrain")
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = true
		game._unhandled_input(event)
		expect(not game.gather(cell), "harvest cannot be repeated")
	expect(game.bag.total(11) == 2, "two gathered plants yield two fibers")
	game.key_event(KEY_B)
	expect(game.inventory.visible and not game.player.active, "B opens finite inventory")
	click("storage", 0)
	click("craft", 0, true)
	click("craft", 1)
	expect(game.bag.craft[0].count == 1 and game.bag.craft[1].count == 1 and game.bag.cursor.count == 0, "split fibers between two crafting slots")
	expect(not game.craft_output.disabled, "recipe preview enabled")
	game.craft_output.pressed.emit()
	expect(game.bag.total(11) == 0 and game.bag.total(12) == 1, "output button consumes two fibers and creates one rope")
	game.craft_output.pressed.emit()
	expect(game.bag.total(12) == 1, "no free repeated crafting")
	# Hoverless cursor dropping, key repeat prevention and whole-stack dropping.
	game.bag.add(12, 3)
	click("storage", 0)
	press_q()
	expect(game.bag.cursor.count == 3 and drops_total(12) == 1, "Q drops one carried item")
	press_q(false, true)
	expect(game.bag.cursor.count == 3 and drops_total(12) == 1, "holding Q does not repeat")
	press_q(true)
	expect(game.bag.cursor.count == 0 and drops_total(12) == 4, "Ctrl Q drops remaining carried stack")
	game.key_event(KEY_ESCAPE)
	expect(game.player.active and not game.menu.visible, "Esc closes only inventory")
	# Cooldown actually prevents immediate pickup, then automatic pickup conserves counts.
	for drop in game.get_tree().get_nodes_in_group("dropped_items"):
		drop.position = game.player.position + Vector3.UP * 0.7
		drop.velocity = Vector3.ZERO
		drop._physics_process(0.01)
	expect(game.bag.total(12) == 0 and drops_total(12) == 4, "freshly thrown stacks are not immediately picked up")
	for drop in game.get_tree().get_nodes_in_group("dropped_items"):
		drop.cooldown = 0
		drop._physics_process(0.01)
	expect(game.bag.total(12) == 4 and drops_total(12) == 0, "dropped stacks can be picked up without duplication")
	await game.get_tree().process_frame
	press_q()
	expect(game.bag.total(12) == 3 and drops_total(12) == 1, "closed inventory Q drops selected quickbar item")
	game.key_event(KEY_ESCAPE)
	press_q()
	expect(game.bag.total(12) == 3, "Q in pause menu does nothing")
	game.start_game()
	clear_drops()
	await game.get_tree().process_frame
	for i in range(36): game.bag.storage[i] = Items.stack(2, 9)
	game.bag.storage[0] = Items.stack(12, 8)
	game.spawn_drop(12, 3)
	for drop in game.get_tree().get_nodes_in_group("dropped_items"):
		drop.position = game.player.position + Vector3.UP * 0.7
		drop.velocity = Vector3.ZERO
		drop.cooldown = 0
		drop._physics_process(0.01)
	expect(game.bag.storage[0].count == 9 and drops_total(12) == 2, "partial pickup leaves overflow on ground")
	clear_drops()
	await game.get_tree().process_frame
	# Full-inventory crafting and closing must never lose inputs or duplicate outputs.
	game.key_event(KEY_B)
	for i in range(36): game.bag.storage[i] = Items.stack(2, 9)
	game.bag.craft[0] = Items.stack(11, 2)
	game.craft_rope()
	expect(game.bag.total(11) == 0 and drops_total(12) == 1, "full inventory crafting drops the result")
	game.bag.storage[0] = Items.stack(12, 8)
	game.bag.craft[0] = Items.stack(11, 2)
	game.craft_rope()
	expect(game.bag.storage[0].count == 9 and drops_total(12) == 1, "craft output prefers an existing stack")
	game.bag.cursor = Items.stack(10, 3)
	game.bag.craft[1] = Items.stack(11, 2)
	game.toggle_inventory(false)
	expect(game.bag.cursor.count == 0 and game.bag.craft[1].count == 0 and drops_total(10) == 3 and drops_total(11) == 2, "closing full inventory returns or drops all held inputs")
	clear_drops()
	await game.get_tree().process_frame
	game.bag = Items.new()
	game.choose_slot(0)
	# Real stone, branch and ordinary grass are harvestable too.
	for xz in [Vector2i(-2, 9), Vector2i(2, 10)]:
		var cell := Vector3i(xz.x, game.world.height_at(xz.x, xz.y), xz.y)
		expect(game.gather(cell), "ground stone / branch harvested")
	expect(game.bag.total(9) == 1 and game.bag.total(10) == 1, "ground resources yield distinct items")
	var grass_found := false
	for at: Vector3 in game.world.decorations[Vector2i.ZERO][0]:
		if game.gather(World.support_cell(at)):
			grass_found = true
			break
	expect(grass_found and game.bag.total(13) == 1, "ordinary grass yields dry grass")
	game.bag = Items.new()
	game.refresh_inventory()
	var mined := Vector3i(2, game.world.height_at(2, 11), 11)
	var mined_kind: int = game.world.get_kind(mined)
	expect(game.mine(mined) and game.bag.total(mined_kind) == 1 and game.world.get_kind(mined) == -1, "mining grants the actual block")
	expect(not game.mine(mined) and game.bag.total(mined_kind) == 1, "cannot mine removed voxel twice")
	var holding := -1
	for i in range(9):
		if game.bag.storage[i].kind == mined_kind: holding = i
	game.choose_slot(holding)
	expect(not game.place_block(Vector3i((game.player.position + Vector3.UP * 0.9).floor())) and game.bag.total(mined_kind) == 1, "invalid placement consumes nothing")
	expect(game.place_block(mined) and game.bag.total(mined_kind) == 0, "successful placement consumes one block")
	expect(not game.place_block(Vector3i(2, 12, 10)), "empty slot cannot create blocks")
	# Return streaming must preserve both edited terrain and harvested resources.
	game.world.set_block(Vector3i(0, 10, 8), 8)
	expect(await game.wait_idle(), "chunk queue completes")
	var checkpoint: Vector3 = game.player.position
	game.player.active = false
	game.player.position = Vector3(48.5, 30, 48.5)
	game.world.follow(game.player.position)
	expect(await game.wait_idle(), "chunk queue completes")
	expect(not game.world.chunks.has(Vector2i.ZERO) and game.world.chunks.size() <= 25, "streaming unloads distant terrain")
	game.player.position = checkpoint
	game.world.follow(checkpoint)
	expect(await game.wait_idle(), "chunk queue completes")
	expect(game.world.get_kind(Vector3i(0, 10, 8)) == 8 and game.world.position_ready(checkpoint), "return restores edited terrain collision")
	expect(game.world.resource_at(Vector3i(-2, 4, 6)).is_empty(), "harvested plants do not respawn on reload")
	game.start_game()
	game.player.position = game.npc.position + Vector3.RIGHT
	game.key_event(KEY_E)
	expect(game.message.text.begins_with("向导："), "guide dialogue still works")
	expect(game.bag.valid(), "final inventory stack invariants")
	print("CHECKS: %d, FAILURES: %d" % [checks, failures])
	if failures == 0: print("SMOKE PASS: finite inventory, 9-stack cap, resource harvesting, splits/merges, two-slot crafting, full-bag overflow, Q/Ctrl-Q, drop cooldown/pickup, block consumption, streamed persistence, NPC")
	game.get_tree().quit(1 if failures else 0)
