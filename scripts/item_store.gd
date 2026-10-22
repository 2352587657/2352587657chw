extends RefCounted
## Inventory operations contain no scene/UI side effects. Every transfer conserves quantities.
const MAX_STACK := 9
const SLOT_COUNT := 36
const FIBER := 11
const ROPE := 12
const NAMES := ["草地方块", "泥土", "石头方块", "木头", "树叶", "沙子", "木板", "砖块", "白石", "碎石", "枯枝", "植物纤维", "粗绳", "干草"]
const COLORS := [Color("7b9952"), Color("8b6547"), Color("88919a"), Color("795537"), Color("416c47"), Color("d5c08d"), Color("bc905b"), Color("ae6253"), Color("d3d8d8"), Color("9ca8b0"), Color("916849"), Color("c2cd77"), Color("bb9b63"), Color("cbb573")]
var storage: Array[Dictionary] = []
var craft: Array[Dictionary] = []
var cursor: Dictionary = empty()

static func empty() -> Dictionary:
	return {"kind": -1, "count": 0}

static func stack(kind: int, count: int) -> Dictionary:
	return {"kind": kind, "count": count} if count > 0 else empty()

func _init() -> void:
	for i in range(SLOT_COUNT): storage.append(empty())
	for i in range(2): craft.append(empty())

func add(kind: int, amount: int) -> int:
	# Fill existing stacks first, then empty cells. Return what did not fit.
	for cell in storage:
		if cell.kind == kind and cell.count < MAX_STACK:
			var moved := mini(amount, MAX_STACK - int(cell.count))
			cell.count += moved
			amount -= moved
			if amount == 0: return 0
	for i in range(storage.size()):
		if storage[i].count == 0:
			var moved := mini(amount, MAX_STACK)
			storage[i] = stack(kind, moved)
			amount -= moved
			if amount == 0: return 0
	return amount

func click(section: String, index: int, right: bool) -> void:
	var cells: Array[Dictionary] = craft if section == "craft" else storage
	var cell: Dictionary = cells[index].duplicate()
	if cursor.count == 0:
		if cell.count == 0: return
		var amount: int = ceili(cell.count / 2.0) if right else int(cell.count)
		cursor = stack(cell.kind, amount)
		cells[index] = stack(cell.kind, cell.count - amount)
	elif cell.count == 0 or cell.kind == cursor.kind:
		var room := MAX_STACK - int(cell.count)
		var amount := mini(room, 1 if right else int(cursor.count))
		cells[index] = stack(cursor.kind, cell.count + amount)
		cursor = stack(cursor.kind, cursor.count - amount)
	elif not right:
		cells[index] = cursor.duplicate()
		cursor = cell

func extract(section: String, index: int, entire: bool) -> Dictionary:
	if section == "cursor":
		var amount: int = cursor.count if entire else mini(1, cursor.count)
		var result := stack(cursor.kind, amount)
		cursor = stack(cursor.kind, cursor.count - amount)
		return result
	var cells: Array[Dictionary] = craft if section == "craft" else storage
	var cell := cells[index]
	var amount: int = cell.count if entire else mini(1, cell.count)
	var result := stack(cell.kind, amount)
	cells[index] = stack(cell.kind, cell.count - amount)
	return result

func can_craft() -> bool:
	var fibers := 0
	for cell in craft:
		if cell.count > 0 and cell.kind != FIBER: return false
		fibers += int(cell.count)
	return fibers >= 2

func craft_once() -> bool:
	if not can_craft(): return false
	var needed := 2
	for i in range(2):
		var used := mini(needed, int(craft[i].count))
		craft[i] = stack(craft[i].kind, craft[i].count - used)
		needed -= used
	return true

func total(kind: int) -> int:
	var result := 0
	for cell in storage + craft + [cursor]:
		if cell.kind == kind: result += int(cell.count)
	return result

func valid() -> bool:
	for cell in storage + craft + [cursor]:
		if cell.count < 0 or cell.count > MAX_STACK: return false
		if cell.count == 0 and cell.kind != -1: return false
		if cell.count > 0 and (cell.kind < 0 or cell.kind >= NAMES.size()): return false
	return true
