extends RefCounted
class_name BuildGrid

const SCHEMA_VERSION : int = 1
const LAYER_FLOOR : int = 0
const LAYER_OBJECT : int = 1

# Build-specific result reasons; shared reasons use the same names/values as OpResult.
const OK : StringName = &"ok"
const NULL_DB : StringName = &"null_db"
const NULL_INVENTORY : StringName = &"null_inventory"
const UNKNOWN_PIECE : StringName = &"unknown_piece"
const BAD_ROTATION : StringName = &"bad_rotation"
const CANNOT_ROTATE : StringName = &"cannot_rotate"
const OUT_OF_BOUNDS : StringName = &"out_of_bounds"
const OVERLAP : StringName = &"overlap"
const NOT_ENOUGH : StringName = &"not_enough_quantity"
const NO_STRUCTURE : StringName = &"no_structure"
const CHEST_NOT_EMPTY : StringName = &"chest_not_empty"
const INVENTORY_FULL : StringName = &"inventory_full"
const INTERNAL : StringName = &"internal"
const INCOMPLETE_DATA : StringName = &"incomplete_data"
const BAD_SCHEMA : StringName = &"bad_schema"
const BAD_DATA : StringName = &"bad_data"

var size : Vector2i = Vector2i(20, 15)   # ขอบเขตวางได้ (cell)
var chest_slots : int = 20
var _structs : Dictionary = {}           # uid -> {piece:String, cell:Vector2i, rot:int}
var _occ : Array = [{}, {}]              # layer -> {cell: uid}
var _chests : Dictionary = {}            # storage_id -> Inventory
var _next_uid : int = 1

static func storage_id(uid : int) -> String:
	return "chest_%d" % uid

static func layer_of(p : BuildingPieceData) -> int:
	return LAYER_FLOOR if p.category == BuildingPieceData.BuildingCategory.FLOOR else LAYER_OBJECT

static func footprint(p : BuildingPieceData, rot : int) -> Vector2i:
	var s : Vector2i = p.size_in_cells
	return Vector2i(s.y, s.x) if rot % 2 == 1 else s

func _piece(db : ItemDatabase, id : StringName) -> BuildingPieceData:
	return db.get_item(id) as BuildingPieceData

# ---------- query ----------
func struct_at(cell : Vector2i) -> int:
	if _occ[LAYER_OBJECT].has(cell):
		return _occ[LAYER_OBJECT][cell]
	return _occ[LAYER_FLOOR].get(cell, -1)

func get_struct(uid : int) -> Dictionary:
	return _structs.get(uid, {}).duplicate()

func struct_count() -> int:
	return _structs.size()

func chest(sid : String) -> Inventory:
	return _chests.get(sid)

func chest_id_at(cell : Vector2i) -> String:
	var uid : int = struct_at(cell)
	return storage_id(uid) if _chests.has(storage_id(uid)) else ""

func chest_ids() -> Array:
	var ids : Array = _chests.keys()
	ids.sort()
	return ids

func count_placed(id : StringName) -> int:
	var n : int = 0
	for uid in _structs:
		if _structs[uid]["piece"] == String(id):
			n += 1
	return n

func count_in_chests(id : StringName) -> int:
	var n : int = 0
	for sid in _chests:
		n += _chests[sid].count_of(id)
	return n

func all_structs() -> Array:
	var out : Array = []
	var uids : Array = _structs.keys()
	uids.sort()
	for uid in uids:
		var s : Dictionary = _structs[uid]
		out.append({"uid": uid, "piece": s["piece"], "cell": s["cell"], "rot": s["rot"]})
	return out

# ---------- validity (ไม่แก้ state, ใช้กับ ghost ได้) ----------
func check(db : ItemDatabase, id : StringName, cell : Vector2i, rot : int) -> Dictionary:
	if db == null:
		return BuildResult.make(BuildGrid.NULL_DB, 1, 0)
	var p : BuildingPieceData = _piece(db, id)
	if p == null:
		return BuildResult.make(BuildGrid.UNKNOWN_PIECE, 1, 0)
	if rot < 0 or rot > 3:
		return BuildResult.make(BuildGrid.BAD_ROTATION, 1, 0)
	if rot != 0 and not p.can_be_rotated:
		return BuildResult.make(BuildGrid.CANNOT_ROTATE, 1, 0)
	var fp : Vector2i = footprint(p, rot)
	if cell.x < 0 or cell.y < 0 or cell.x + fp.x > size.x or cell.y + fp.y > size.y:
		return BuildResult.make(BuildGrid.OUT_OF_BOUNDS, 1, 0)
	var layer : int = layer_of(p)
	for x in range(fp.x):
		for y in range(fp.y):
			if _occ[layer].has(cell + Vector2i(x, y)):
				return BuildResult.make(BuildGrid.OVERLAP, 1, 0)
	return BuildResult.make(BuildGrid.OK, 0, 0)

# ---------- place: ตรวจครบก่อน แล้วค่อยเขียน ----------
func place(db : ItemDatabase, inv : Inventory, id : StringName, cell : Vector2i, rot : int) -> Dictionary:
	if db == null:
		return BuildResult.make(BuildGrid.NULL_DB, 1, 0)
	if inv == null:
		return BuildResult.make(BuildGrid.NULL_INVENTORY, 1, 0)
	var r : Dictionary = check(db, id, cell, rot)
	if not r["ok"]:
		return r
	if inv.count_of(id) < 1:
		return BuildResult.make(BuildGrid.NOT_ENOUGH, 1, 0)
	if not inv.remove_item(db, id, 1)["ok"]:
		push_error("BuildGrid.place: ตรวจแล้วแต่ remove_item ล้ม")
		return BuildResult.make(BuildGrid.INTERNAL, 1, 0)
	_insert(_next_uid, _piece(db, id), cell, rot)
	_next_uid += 1
	return BuildResult.make(BuildGrid.OK, 1, 1)

# ---------- remove: คืนเข้ากระเป๋าก่อน แล้วค่อยลบโครงสร้าง ----------
func remove_at(db : ItemDatabase, inv : Inventory, cell : Vector2i) -> Dictionary:
	if db == null:
		return BuildResult.make(BuildGrid.NULL_DB, 1, 0)
	if inv == null:
		return BuildResult.make(BuildGrid.NULL_INVENTORY, 1, 0)
	var uid : int = struct_at(cell)
	if uid < 0:
		return BuildResult.make(BuildGrid.NO_STRUCTURE, 1, 0)
	var s : Dictionary = _structs[uid]
	var id : StringName = StringName(s["piece"])
	var p : BuildingPieceData = _piece(db, id)
	if p == null:
		return BuildResult.make(BuildGrid.UNKNOWN_PIECE, 1, 0)
	var sid : String = storage_id(uid)
	if _chests.has(sid) and not _is_empty(_chests[sid]):
		return BuildResult.make(BuildGrid.CHEST_NOT_EMPTY, 1, 0)
	if inv.free_space_for(p) < 1:
		return BuildResult.make(BuildGrid.INVENTORY_FULL, 1, 0)
	if not inv.add_to_existing_stacks(db, id, 1)["ok"]:
		push_error("BuildGrid.remove_at: free_space_for ผ่านแต่ add ล้ม")
		return BuildResult.make(BuildGrid.INTERNAL, 1, 0)
	_erase(uid, p)
	return BuildResult.make(BuildGrid.OK, 1, 1)

# ---------- internal ----------
func _is_empty(inv : Inventory) -> bool:
	for s in inv.slots:
		if s != null and s.item_data != null and s.quantity > 0:
			return false
	return true

func _insert(uid : int, p : BuildingPieceData, cell : Vector2i, rot : int) -> void:
	_structs[uid] = {"piece": String(p.id), "cell": cell, "rot": rot}
	var fp : Vector2i = footprint(p, rot)
	var layer : int = layer_of(p)
	for x in range(fp.x):
		for y in range(fp.y):
			_occ[layer][cell + Vector2i(x, y)] = uid
	if p.category == BuildingPieceData.BuildingCategory.STORAGE:
		var c : Inventory = Inventory.new()
		c.owner_id = storage_id(uid)
		c.max_slots = chest_slots
		_chests[c.owner_id] = c

func _erase(uid : int, p : BuildingPieceData) -> void:
	var s : Dictionary = _structs[uid]
	var fp : Vector2i = footprint(p, s["rot"])
	var layer : int = layer_of(p)
	for x in range(fp.x):
		for y in range(fp.y):
			_occ[layer].erase(s["cell"] + Vector2i(x, y))
	_structs.erase(uid)
	_chests.erase(storage_id(uid))

# ---------- serialize (id + cell + rot ไม่มี node path) ----------
func to_dict() -> Dictionary:
	var arr : Array = []
	var uids : Array = _structs.keys()
	uids.sort()
	for uid in uids:
		var s : Dictionary = _structs[uid]
		arr.append({"uid": uid, "piece": s["piece"], "x": s["cell"].x, "y": s["cell"].y, "rot": s["rot"]})
	var ch : Dictionary = {}
	for sid in _chests:
		ch[sid] = _chests[sid].to_dict()
	return {"schema_version": SCHEMA_VERSION, "size": [size.x, size.y], "next_uid": _next_uid, "structs": arr, "chests": ch}

static func _fail(reason : StringName) -> Dictionary:
	return {"ok": false, "grid": null, "reason": reason}

static func from_dict(data : Dictionary, db : ItemDatabase) -> Dictionary:
	if db == null:
		return _fail(BuildGrid.NULL_DB)
	for k in ["schema_version", "size", "next_uid", "structs", "chests"]:
		if not data.has(k):
			return _fail(BuildGrid.INCOMPLETE_DATA)
	if data["schema_version"] != SCHEMA_VERSION:
		return _fail(BuildGrid.BAD_SCHEMA)
	var sz = data["size"]
	if typeof(sz) != TYPE_ARRAY or sz.size() != 2 or typeof(sz[0]) != TYPE_INT or typeof(sz[1]) != TYPE_INT or sz[0] < 1 or sz[1] < 1:
		return _fail(BuildGrid.BAD_DATA)
	if typeof(data["next_uid"]) != TYPE_INT or typeof(data["structs"]) != TYPE_ARRAY or typeof(data["chests"]) != TYPE_DICTIONARY:
		return _fail(BuildGrid.BAD_DATA)
	var g : BuildGrid = BuildGrid.new()
	g.size = Vector2i(sz[0], sz[1])
	var storage : Array = []
	for s in data["structs"]:
		if typeof(s) != TYPE_DICTIONARY:
			return _fail(BuildGrid.BAD_DATA)
		for k in ["uid", "piece", "x", "y", "rot"]:
			if not s.has(k):
				return _fail(BuildGrid.INCOMPLETE_DATA)
		if typeof(s["piece"]) != TYPE_STRING or typeof(s["uid"]) != TYPE_INT or typeof(s["x"]) != TYPE_INT or typeof(s["y"]) != TYPE_INT or typeof(s["rot"]) != TYPE_INT:
			return _fail(BuildGrid.BAD_DATA)
		var uid : int = s["uid"]
		if uid < 1 or uid >= data["next_uid"] or g._structs.has(uid):
			return _fail(BuildGrid.BAD_DATA)
		var id : StringName = StringName(s["piece"])
		var cell : Vector2i = Vector2i(s["x"], s["y"])
		var r : Dictionary = g.check(db, id, cell, s["rot"])
		if not r["ok"]:
			return _fail(r["reason"])
		g._insert(uid, g._piece(db, id), cell, s["rot"])
		if g._chests.has(storage_id(uid)):
			storage.append(storage_id(uid))
	g._next_uid = data["next_uid"]
	if data["chests"].size() != storage.size():
		return _fail(BuildGrid.BAD_DATA)
	for sid in storage:
		if not data["chests"].has(sid) or typeof(data["chests"][sid]) != TYPE_DICTIONARY:
			return _fail(BuildGrid.BAD_DATA)
		var ir : Dictionary = Inventory.from_dict(data["chests"][sid], db)
		if not ir["ok"]:
			return _fail(ir["reason"])
		if ir["inventory"].owner_id != sid:
			return _fail(BuildGrid.BAD_DATA)
		g._chests[sid] = ir["inventory"]
	return {"ok": true, "grid": g, "reason": BuildGrid.OK}
