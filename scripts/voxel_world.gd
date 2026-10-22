extends Node3D
## Voxel storage is independent of rendering. Only nearby chunks have scene nodes.
const SIZE := 16
const HALF := 64
const MIN_Y := -8
const MAX_Y := 40
const HEIGHT := MAX_Y - MIN_Y
const SEED := 42817
const VIEW_RADIUS := 2
const COLLISION_RADIUS := 1
const COLORS := [Color("7b9952"), Color("8b6547"), Color("88919a"), Color("795537"), Color("416c47"), Color("d5c08d"), Color("bc905b"), Color("ae6253"), Color("d3d8d8")]
const NAMES := ["草地", "泥土", "石头", "木头", "树叶", "沙子", "木板", "砖块", "白石"]
var data: Dictionary = {}
var heights: Dictionary = {}
var decorations: Dictionary = {}
var collected_resources: Dictionary = {}
const RESOURCE_ITEMS := [13, 9, 11, 10]
var chunks: Dictionary = {}
var revisions: Dictionary = {}
var pending: Dictionary = {}
var worker := Thread.new()
var job := ""
var job_key := Vector2i.ZERO
var job_revision := 0
var center := Vector2i(0, 0)
var last_center := Vector2i(999, 999)
var initialized := false
var terrain_material: StandardMaterial3D
var generated_quads := 0
var last_mesh_ms := 0.0
var last_apply_ms := 0.0
var meshes_built := 0
var collision_cache: Dictionary = {}
var generation_ms := 0.0
var max_apply_ms := 0.0
var max_snapshot_ms := 0.0

func _ready() -> void:
	terrain_material = StandardMaterial3D.new()
	terrain_material.vertex_color_use_as_albedo = true
	terrain_material.roughness = 1.0
	job = "generate"
	worker.start(_generate_data)

static func chunk_at(cell: Vector3i) -> Vector2i:
	return Vector2i(floori(float(cell.x) / SIZE), floori(float(cell.z) / SIZE))

static func index_of(x: int, y: int, z: int) -> int:
	return (x * SIZE + z) * HEIGHT + y - MIN_Y

static func hash_at(x: int, z: int) -> int:
	return posmod(x * 73856093 ^ z * 19349663 ^ SEED, 2147483647)

static func river_x(z: float) -> float:
	return -15.0 + sin(z * 0.045) * 10.0 + sin(z * 0.11) * 2.0

static func _generate_data() -> Dictionary:
	var begin := Time.get_ticks_usec()
	var noise := FastNoiseLite.new()
	noise.seed = SEED
	noise.frequency = 0.018
	noise.fractal_octaves = 3
	var detail := FastNoiseLite.new()
	detail.seed = SEED + 1
	detail.frequency = 0.07
	var storage: Dictionary = {}
	var tops: Dictionary = {}
	var decor: Dictionary = {}
	for cx in range(-4, 4):
		for cz in range(-4, 4):
			var key := Vector2i(cx, cz)
			var bytes := PackedByteArray()
			bytes.resize(SIZE * SIZE * HEIGHT)
			var grasses := PackedVector3Array()
			var rocks := PackedVector3Array()
			var fibers := PackedVector3Array()
			var branches := PackedVector3Array()
			for lx in range(SIZE):
				for lz in range(SIZE):
					var x := cx * SIZE + lx
					var z := cz * SIZE + lz
					var distance := absf(x - river_x(z))
					var hill := maxf(0, 1.0 - Vector2(x - 30, z + 24).length() / 35.0)
					var raw := 4.0 + noise.get_noise_2d(x, z) * 8.0 + detail.get_noise_2d(x, z) * 1.8 + hill * hill * 17.0
					var bank := smoothstep(3.0, 10.0, distance)
					var h := floori(lerpf(-2.0, maxf(2, raw), bank))
					# A safe, flat starting clearing for the player and guide.
					var clearing := 1.0 - smoothstep(5.0, 10.0, Vector2(x - 1, z - 8).length())
					h = roundi(lerpf(h, 4.0, clearing))
					tops[Vector2i(x, z)] = h
					for y in range(MIN_Y, h + 1):
						var kind := 2 if y < h - 2 else 1
						if y == h: kind = 5 if h <= 1 or distance < 6 else 0
						bytes[index_of(lx, y, lz)] = kind + 1
					var hash_value := hash_at(x, z)
					if h > 1:
						if Vector2i(x, z) in [Vector2i(-2, 6), Vector2i(-1, 5)] or hash_value % 53 == 0:
							fibers.append(Vector3(x + 0.5, h + 1.45, z + 0.5))
						elif Vector2i(x, z) == Vector2i(-2, 9) or hash_value % 97 == 0:
							rocks.append(Vector3(x + 0.5, h + 1.18, z + 0.5))
						elif Vector2i(x, z) == Vector2i(2, 10) or hash_value % 71 == 0:
							branches.append(Vector3(x + 0.5, h + 1.1, z + 0.5))
						elif hash_value % 19 == 0:
							grasses.append(Vector3(x + 0.5, h + 1.25, z + 0.5))
			storage[key] = bytes
			decor[key] = [grasses, rocks, fibers, branches]

	# Trees write across chunk borders before any mesh is built.
	for x in range(-HALF + 2, HALF - 2):
		for z in range(-HALF + 2, HALF - 2):
			var h: int = tops[Vector2i(x, z)]
			if hash_at(x, z) % 139 != 0 or h < 2 or absf(x - river_x(z)) < 7 or Vector2(x - 1, z - 8).length() < 7: continue
			for y in range(h + 1, h + 5): _write(storage, Vector3i(x, y, z), 4)
			for dx in range(-2, 3):
				for dz in range(-2, 3):
					for dy in range(3):
						if absi(dx) + absi(dz) + dy > 4: continue
						var cell := Vector3i(x + dx, h + 4 + dy, z + dz)
						if _read(storage, cell) == 0: _write(storage, cell, 5)
	return {"data": storage, "heights": tops, "decorations": decor, "ms": (Time.get_ticks_usec() - begin) / 1000.0}

static func _read(storage: Dictionary, cell: Vector3i) -> int:
	if cell.y < MIN_Y or cell.y >= MAX_Y: return 0
	var key := chunk_at(cell)
	if not storage.has(key): return 0
	var bytes: PackedByteArray = storage[key]
	return bytes[index_of(posmod(cell.x, SIZE), cell.y, posmod(cell.z, SIZE))]

static func _write(storage: Dictionary, cell: Vector3i, value: int) -> void:
	if cell.y < MIN_Y or cell.y >= MAX_Y: return
	var key := chunk_at(cell)
	if not storage.has(key): return
	# Packed arrays are reference-counted; writing the dictionary's array updates it in place.
	storage[key][index_of(posmod(cell.x, SIZE), cell.y, posmod(cell.z, SIZE))] = value

func get_kind(cell: Vector3i) -> int:
	return _read(data, cell) - 1

func height_at(x: int, z: int) -> int:
	return heights.get(Vector2i(x, z), 4)

func set_block(cell: Vector3i, kind: int) -> bool:
	var key := chunk_at(cell)
	if not initialized or not data.has(key) or cell.y < MIN_Y or cell.y >= MAX_Y: return false
	_write(data, cell, kind + 1)
	mark_dirty(key)
	# The adjacent mesh changes only if a boundary face is affected.
	var lx := posmod(cell.x, SIZE)
	var lz := posmod(cell.z, SIZE)
	if lx == 0: mark_dirty(key + Vector2i.LEFT)
	if lx == SIZE - 1: mark_dirty(key + Vector2i.RIGHT)
	if lz == 0: mark_dirty(key + Vector2i(0, -1))
	if lz == SIZE - 1: mark_dirty(key + Vector2i(0, 1))
	return true

func mark_dirty(key: Vector2i) -> void:
	revisions[key] = revisions.get(key, 0) + 1
	collision_cache.erase(key)
	if _in_view(key): pending[key] = true

func _in_view(key: Vector2i) -> bool:
	return data.has(key) and absi(key.x - center.x) <= VIEW_RADIUS and absi(key.y - center.y) <= VIEW_RADIUS

func follow(at: Vector3) -> void:
	center = chunk_at(Vector3i(at.floor()))
	if not initialized or center == last_center: return
	last_center = center
	for key: Vector2i in chunks.keys():
		if not _in_view(key):
			chunks[key].queue_free()
			chunks.erase(key)
	for key: Vector2i in pending.keys():
		if not _in_view(key): pending.erase(key)
	for dx in range(-VIEW_RADIUS, VIEW_RADIUS + 1):
		for dz in range(-VIEW_RADIUS, VIEW_RADIUS + 1):
			var key := center + Vector2i(dx, dz)
			if data.has(key) and not chunks.has(key): pending[key] = true
	for key: Vector2i in chunks:
		_sync_collision(key)

func _sync_collision(key: Vector2i) -> void:
	if not chunks.has(key): return
	var body: StaticBody3D = chunks[key]
	var collider := body.get_node_or_null("Collision") as CollisionShape3D
	var near := absi(key.x - center.x) <= COLLISION_RADIUS and absi(key.y - center.y) <= COLLISION_RADIUS
	if not near:
		if collider: collider.queue_free()
	elif not collider:
		if not collision_cache.has(key):
			var visual := body.get_node_or_null("Terrain") as MeshInstance3D
			if visual == null: return
			collision_cache[key] = visual.mesh.create_trimesh_shape()
		collider = CollisionShape3D.new()
		collider.name = "Collision"
		collider.shape = collision_cache[key]
		body.add_child(collider)

func position_ready(at: Vector3) -> bool:
	if not initialized: return false
	for dx in [-0.4, 0.4]:
		for dz in [-0.4, 0.4]:
			var key := chunk_at(Vector3i((at + Vector3(dx, 0, dz)).floor()))
			if not data.has(key): return false
			if not chunks.has(key) or not chunks[key].has_node("Collision"): return false
	return true

func spawn_ready() -> bool:
	if not initialized: return false
	for dx in range(-1, 2):
		for dz in range(-1, 2):
			var key := Vector2i(dx, dz)
			if not chunks.has(key) or not chunks[key].has_node("Collision"): return false
	return true

func _process(_delta: float) -> void:
	if worker.is_started():
		if worker.is_alive(): return
		var result: Dictionary = worker.wait_to_finish()
		if job == "generate":
			data = result.data
			heights = result.heights
			decorations = result.decorations
			generation_ms = result.ms
			initialized = true
			follow(Vector3(0.5, 6, 9.5))
		else:
			if job_revision == revisions.get(job_key, 0) and _in_view(job_key): _install_chunk(job_key, result)
			elif _in_view(job_key): pending[job_key] = true
	if not initialized or pending.is_empty(): return
	var chosen := Vector2i.ZERO
	var best := INF
	for key: Vector2i in pending:
		var priority := float((key - center).length_squared())
		if chunks.has(key): priority -= 100 # Edits are visible before distant scenery.
		if priority < best:
			best = priority
			chosen = key
	pending.erase(chosen)
	job_key = chosen
	job_revision = revisions.get(chosen, 0)
	job = "mesh"
	# Copy an immutable one-cell border for the worker. Scene and live data stay on the main thread.
	var snapshot_begin := Time.get_ticks_usec()
	var padded := PackedByteArray()
	padded.resize((SIZE + 2) * (SIZE + 2) * (HEIGHT + 2))
	for x in range(-1, SIZE + 1):
		for z in range(-1, SIZE + 1):
			var wx := chosen.x * SIZE + x
			var wz := chosen.y * SIZE + z
			var neighbor := chunk_at(Vector3i(wx, 0, wz))
			if not data.has(neighbor): continue
			var source: PackedByteArray = data[neighbor]
			var source_start := index_of(posmod(wx, SIZE), MIN_Y, posmod(wz, SIZE))
			var destination := ((x + 1) * (SIZE + 2) + z + 1) * (HEIGHT + 2) + 1
			for y in range(HEIGHT): padded[destination + y] = source[source_start + y]
	max_snapshot_ms = maxf(max_snapshot_ms, (Time.get_ticks_usec() - snapshot_begin) / 1000.0)
	worker.start(_mesh_chunk.bind(padded))

static func sample(bytes: PackedByteArray, at: Vector3i) -> int:
	return bytes[((at.x + 1) * (SIZE + 2) + at.z + 1) * (HEIGHT + 2) + at.y + 1]

static func _mesh_chunk(bytes: PackedByteArray) -> Dictionary:
	var begin := Time.get_ticks_usec()
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()
	var dims := Vector3i(SIZE, HEIGHT, SIZE)
	var quads := 0
	# Greedy meshing: each slice is a mask of exposed faces. Merge equal rectangles.
	for axis in range(3):
		var u := (axis + 1) % 3
		var v := (axis + 2) % 3
		var step := Vector3i.ZERO
		step[axis] = 1
		for slice in range(-1, dims[axis]):
			var mask := PackedInt32Array()
			mask.resize(dims[u] * dims[v])
			for j in range(dims[v]):
				for i in range(dims[u]):
					var at := Vector3i.ZERO
					at[axis] = slice
					at[u] = i
					at[v] = j
					var a := sample(bytes, at)
					var b := sample(bytes, at + step)
					var face := 0
					if a != 0 and b == 0 and slice >= 0: face = a
					elif a == 0 and b != 0 and slice < dims[axis] - 1: face = -b
					mask[j * dims[u] + i] = face
			var j := 0
			while j < dims[v]:
				var i := 0
				while i < dims[u]:
					var face := mask[j * dims[u] + i]
					if face == 0:
						i += 1
						continue
					var width := 1
					while i + width < dims[u] and mask[j * dims[u] + i + width] == face: width += 1
					var height := 1
					var expand := true
					while j + height < dims[v] and expand:
						for k in range(width):
							if mask[(j + height) * dims[u] + i + k] != face:
								expand = false
								break
						if expand: height += 1
					var origin := Vector3.ZERO
					origin[axis] = slice + 1
					origin[u] = i
					origin[v] = j
					origin.y += MIN_Y
					var du := Vector3.ZERO
					var dv := Vector3.ZERO
					du[u] = width
					dv[v] = height
					var normal := Vector3(step) * (1 if face > 0 else -1)
					var color: Color = COLORS[absi(face) - 1]
					if absi(face) == 1 and normal != Vector3.UP: color = COLORS[1]
					var base := vertices.size()
					vertices.append_array(PackedVector3Array([origin, origin + du, origin + du + dv, origin + dv]))
					for k in range(4):
						normals.append(normal)
						colors.append(color)
					# Godot uses clockwise winding for the front face.
					if face > 0: indices.append_array(PackedInt32Array([base, base + 2, base + 1, base, base + 3, base + 2]))
					else: indices.append_array(PackedInt32Array([base, base + 1, base + 2, base, base + 2, base + 3]))
					quads += 1
					for hj in range(height):
						for wi in range(width): mask[(j + hj) * dims[u] + i + wi] = 0
					i += width
				j += 1
	return {"vertices": vertices, "normals": normals, "colors": colors, "indices": indices, "quads": quads, "ms": (Time.get_ticks_usec() - begin) / 1000.0}

func _install_chunk(key: Vector2i, result: Dictionary) -> void:
	var begin := Time.get_ticks_usec()
	if chunks.has(key):
		var old: Node3D = chunks[key]
		remove_child(old)
		old.queue_free()
	var body := StaticBody3D.new()
	body.position = Vector3(key.x * SIZE, 0, key.y * SIZE)
	body.set_meta("terrain", true)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = result.vertices
	arrays[Mesh.ARRAY_NORMAL] = result.normals
	arrays[Mesh.ARRAY_COLOR] = result.colors
	arrays[Mesh.ARRAY_INDEX] = result.indices
	if result.vertices.size() > 0:
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		var visual := MeshInstance3D.new()
		visual.name = "Terrain"
		visual.mesh = mesh
		visual.material_override = terrain_material
		body.add_child(visual)
	add_child(body)
	chunks[key] = body
	_sync_collision(key)
	add_decorations(body, key)
	generated_quads += result.quads
	last_mesh_ms = result.ms
	last_apply_ms = (Time.get_ticks_usec() - begin) / 1000.0
	max_apply_ms = maxf(max_apply_ms, last_apply_ms)
	meshes_built += 1

func add_decorations(body: Node3D, key: Vector2i) -> void:
	if not decorations.has(key): return
	var lists: Array = decorations[key]
	var container := Node3D.new()
	container.name = "Resources"
	body.add_child(container)
	for type in range(4):
		var positions: PackedVector3Array = lists[type]
		var visible_positions := PackedVector3Array()
		for at in positions:
			# A decoration disappears when its supporting block has been mined.
			var cell := support_cell(at)
			if get_kind(cell) >= 0 and not collected_resources.has(cell): visible_positions.append(at)
		if visible_positions.is_empty(): continue
		var multi := MultiMesh.new()
		multi.transform_format = MultiMesh.TRANSFORM_3D
		if type == 0:
			var grass := PrismMesh.new()
			grass.size = Vector3(0.35, 0.5, 0.35)
			multi.mesh = grass
		elif type == 2:
			var fiber := PrismMesh.new()
			fiber.size = Vector3(0.45, 0.9, 0.45)
			multi.mesh = fiber
		elif type == 3:
			var branch := BoxMesh.new()
			branch.size = Vector3(0.75, 0.12, 0.12)
			multi.mesh = branch
		else:
			var rock := SphereMesh.new()
			rock.radius = 0.35
			rock.height = 0.4
			rock.radial_segments = 8
			rock.rings = 4
			multi.mesh = rock
		multi.instance_count = visible_positions.size()
		for n in range(visible_positions.size()):
			multi.set_instance_transform(n, Transform3D(Basis.IDENTITY, visible_positions[n] - body.position))
		var visual := MultiMeshInstance3D.new()
		visual.multimesh = multi
		var mat := StandardMaterial3D.new()
		mat.albedo_color = [Color("708451"), Color("9ca8b0"), Color("c2cd77"), Color("916849")][type]
		visual.material_override = mat
		container.add_child(visual)

func _exit_tree() -> void:
	if worker.is_started(): worker.wait_to_finish()

static func support_cell(at: Vector3) -> Vector3i:
	return Vector3i(floori(at.x), floori(at.y) - 1, floori(at.z))

func resource_at(cell: Vector3i) -> Dictionary:
	if collected_resources.has(cell) or get_kind(cell) < 0: return {}
	var key := chunk_at(cell)
	if not decorations.has(key): return {}
	for type in range(4):
		for at: Vector3 in decorations[key][type]:
			if support_cell(at) == cell: return {"resource": true, "cell": cell, "at": at, "kind": RESOURCE_ITEMS[type]}
	return {}

func resource_target(origin: Vector3, direction: Vector3, reach: float) -> Dictionary:
	var end := origin + direction * reach
	var min_key := chunk_at(Vector3i(Vector3(minf(origin.x, end.x) - 1, 0, minf(origin.z, end.z) - 1).floor()))
	var max_key := chunk_at(Vector3i(Vector3(maxf(origin.x, end.x) + 1, 0, maxf(origin.z, end.z) + 1).floor()))
	var result := {}
	var nearest := reach
	for x in range(min_key.x, max_key.x + 1):
		for z in range(min_key.y, max_key.y + 1):
			var key := Vector2i(x, z)
			if not chunks.has(key) or not decorations.has(key): continue
			for type in range(4):
				for at: Vector3 in decorations[key][type]:
					var cell := support_cell(at)
					if collected_resources.has(cell) or get_kind(cell) < 0: continue
					var size := Vector3(0.65, 0.65, 0.65)
					if type == 2: size = Vector3(0.6, 0.95, 0.6)
					if type == 3: size = Vector3(0.85, 0.25, 0.35)
					var point = AABB(at - size * 0.5, size).intersects_segment(origin, end)
					if point == null: continue
					var distance: float = origin.distance_to(point)
					if distance < nearest:
						nearest = distance
						result = {"resource": true, "cell": cell, "at": at, "kind": RESOURCE_ITEMS[type], "distance": distance, "size": size}
	return result

func take_resource(cell: Vector3i) -> int:
	var info := resource_at(cell)
	if info.is_empty(): return -1
	collected_resources[cell] = true
	call_deferred("refresh_resources", chunk_at(cell))
	return info.kind

func refresh_resources(key: Vector2i) -> void:
	if not chunks.has(key): return
	var body: Node3D = chunks[key]
	var previous := body.get_node_or_null("Resources")
	if previous:
		body.remove_child(previous)
		previous.queue_free()
	add_decorations(body, key)
