extends RefCounted
class_name BuildGridTests

var db : ItemDatabase = ItemDatabase.new()
var passed : int = 0
var failed : int = 0

func t(label : String, cond : bool) -> void:
	if cond:
		passed += 1
	else:
		failed += 1
		print("FAIL: ", label)

func run_all() -> void:
	db.load_from_directory("res://data/")
	test_pure()
	test_place_basic()
	test_bounds()
	test_rotation()
	test_invalid_input()
	test_remove()
	test_chest()
	test_serialize()
	test_fuzz()
	print("BuildGrid: Passed ", passed, " / Failed ", failed)

# ---------- helpers ----------
func inv_with(items : Dictionary) -> Inventory:
	var inv : Inventory = Inventory.new()
	for id in items:
		inv.add_to_existing_stacks(db, id, items[id])
	return inv

func total(g : BuildGrid, invs : Array, id : StringName) -> int:
	var n : int = g.count_placed(id) + g.count_in_chests(id)
	for i in invs:
		n += i.count_of(id)
	return n

func rs(r : Dictionary) -> StringName:
	t("result shape keys", r.has("ok") and r.has("reason") and r.has("requested") and r.has("done") and r.has("remaining"))
	t("result reason/ok invariant", r["ok"] == (r["reason"] == BuildGrid.OK))
	t("result count invariant", r["done"] + r["remaining"] == r["requested"])
	if r["ok"]:
		t("result success is complete", r["done"] == r["requested"])
	return r["reason"]

# ---------- pure ----------
func test_pure() -> void:
	var o : Object = BuildGrid.new()
	t("pure: not a scene object", not (o is Node) and o is RefCounted)
	var src : String = FileAccess.get_file_as_string("res://systems/build_grid.gd") + FileAccess.get_file_as_string("res://systems/build_result.gd")
	t("pure: source has no scene-object type", src.length() > 0 and not src.contains("Node"))
	var c : Vector2i = Vector2i(3, 4)
	t("const roundtrip", BuildConst.world_to_cell(BuildConst.cell_to_world(c)) == c)
	t("const negative", BuildConst.world_to_cell(Vector2(-1, -1)) == Vector2i(-1, -1))
	t("const edge", BuildConst.world_to_cell(Vector2(31, 32)) == Vector2i(0, 1))

# ---------- place พื้นฐาน ----------
func test_place_basic() -> void:
	var g : BuildGrid = BuildGrid.new()
	var inv : Inventory = inv_with({&"floor_00": 3, &"wall_00": 3})
	var r : Dictionary = g.check(db, &"wall_00", Vector2i(2, 2), 0)
	t("check result shape", r["ok"] and r["requested"] == 0 and r["done"] == 0 and r["remaining"] == 0 and g.struct_count() == 0)
	t("check result invariants", r["ok"] == (r["reason"] == BuildGrid.OK) and r["done"] + r["remaining"] == r["requested"] and (not r["ok"] or r["done"] == r["requested"]))
	r = g.place(db, inv, &"wall_00", Vector2i(2, 2), 0)
	t("place ok", r["ok"] and r["done"] == 1)
	t("place: inv -1", inv.count_of(&"wall_00") == 2)
	t("place: struct_at", g.struct_at(Vector2i(2, 2)) >= 0 and g.count_placed(&"wall_00") == 1)
	r = g.place(db, inv, &"wall_00", Vector2i(3, 2), 0)
	t("adjacent ok", r["ok"] and g.struct_count() == 2)
	var before : Dictionary = inv.to_dict()
	r = g.place(db, inv, &"wall_00", Vector2i(2, 2), 0)
	t("overlap rejected", rs(r) == BuildGrid.OVERLAP and r["done"] == 0)
	t("overlap: inventory untouched", inv.to_dict() == before and g.struct_count() == 2)
	r = g.place(db, inv, &"floor_00", Vector2i(2, 2), 0)
	t("floor under wall ok (คนละ layer)", r["ok"] and g.struct_count() == 3)
	r = g.place(db, inv, &"floor_00", Vector2i(2, 2), 0)
	t("floor on floor overlap", rs(r) == BuildGrid.OVERLAP)
	t("total wall conserved", total(g, [inv], &"wall_00") == 3)
	t("all_structs matches", g.all_structs().size() == g.struct_count() and g.all_structs()[0]["piece"] == "wall_00")

# ---------- ขอบเขต ----------
func test_bounds() -> void:
	var g : BuildGrid = BuildGrid.new()
	var inv : Inventory = inv_with({&"wall_00": 9, &"workbench_00": 9})
	for c in [Vector2i(-1, 0), Vector2i(0, -1), Vector2i(20, 0), Vector2i(0, 15)]:
		t("oob wall %s" % str(c), rs(g.place(db, inv, &"wall_00", c, 0)) == BuildGrid.OUT_OF_BOUNDS)
	t("corner (19,14) ok", g.place(db, inv, &"wall_00", Vector2i(19, 14), 0)["ok"])
	t("wide piece oob x", rs(g.place(db, inv, &"workbench_00", Vector2i(19, 0), 0)) == BuildGrid.OUT_OF_BOUNDS)
	t("wide piece fits", g.place(db, inv, &"workbench_00", Vector2i(18, 0), 0)["ok"])
	t("rotated piece oob y", rs(g.place(db, inv, &"workbench_00", Vector2i(0, 14), 1)) == BuildGrid.OUT_OF_BOUNDS)
	t("rotated piece fits", g.place(db, inv, &"workbench_00", Vector2i(0, 13), 1)["ok"])
	t("bounds: conserved", total(g, [inv], &"wall_00") == 9 and total(g, [inv], &"workbench_00") == 9)

# ---------- rotation ----------
func test_rotation() -> void:
	var g : BuildGrid = BuildGrid.new()
	var inv : Inventory = inv_with({&"workbench_00": 9, &"wall_00": 9, &"chest_00": 9})
	t("rot0 placed", g.place(db, inv, &"workbench_00", Vector2i(0, 0), 0)["ok"])
	t("rot0 covers (1,0) not (0,1)", g.struct_at(Vector2i(1, 0)) >= 0 and g.struct_at(Vector2i(0, 1)) < 0)
	t("rot0 same uid", g.struct_at(Vector2i(0, 0)) == g.struct_at(Vector2i(1, 0)))
	t("rot1 placed", g.place(db, inv, &"workbench_00", Vector2i(5, 5), 1)["ok"])
	t("rot1 covers (5,6) not (6,5)", g.struct_at(Vector2i(5, 6)) >= 0 and g.struct_at(Vector2i(6, 5)) < 0)
	t("wall next to rot1 ok", g.place(db, inv, &"wall_00", Vector2i(6, 5), 0)["ok"])
	t("wall blocked by rot1 footprint", rs(g.place(db, inv, &"wall_00", Vector2i(5, 6), 0)) == BuildGrid.OVERLAP)
	t("rot2 placed", g.place(db, inv, &"workbench_00", Vector2i(10, 10), 2)["ok"] and g.struct_at(Vector2i(11, 10)) >= 0)
	t("rot3 placed", g.place(db, inv, &"workbench_00", Vector2i(14, 2), 3)["ok"] and g.struct_at(Vector2i(14, 3)) >= 0)
	t("wall cannot rotate", rs(g.place(db, inv, &"wall_00", Vector2i(8, 8), 1)) == BuildGrid.CANNOT_ROTATE)
	t("chest cannot rotate", rs(g.place(db, inv, &"chest_00", Vector2i(8, 8), 2)) == BuildGrid.CANNOT_ROTATE)
	t("rot 4 bad", rs(g.check(db, &"workbench_00", Vector2i(8, 8), 4)) == BuildGrid.BAD_ROTATION)
	t("rot -1 bad", rs(g.check(db, &"workbench_00", Vector2i(8, 8), -1)) == BuildGrid.BAD_ROTATION)

# ---------- input ผิด ----------
func test_invalid_input() -> void:
	var g : BuildGrid = BuildGrid.new()
	var inv : Inventory = inv_with({&"stone_00": 5, &"wall_00": 1})
	t("not a piece", rs(g.place(db, inv, &"stone_00", Vector2i(0, 0), 0)) == BuildGrid.UNKNOWN_PIECE)
	t("unknown id", rs(g.place(db, inv, &"nope", Vector2i(0, 0), 0)) == BuildGrid.UNKNOWN_PIECE)
	t("null db", rs(g.place(null, inv, &"wall_00", Vector2i(0, 0), 0)) == BuildGrid.NULL_DB)
	t("null inv", rs(g.place(db, null, &"wall_00", Vector2i(0, 0), 0)) == BuildGrid.NULL_INVENTORY)
	var empty : Inventory = Inventory.new()
	t("not enough", rs(g.place(db, empty, &"wall_00", Vector2i(0, 0), 0)) == BuildGrid.NOT_ENOUGH)
	t("invalid: grid empty, inv untouched", g.struct_count() == 0 and inv.count_of(&"wall_00") == 1 and inv.count_of(&"stone_00") == 5)

# ---------- remove ----------
func test_remove() -> void:
	var g : BuildGrid = BuildGrid.new()
	var inv : Inventory = inv_with({&"wall_00": 2})
	g.place(db, inv, &"wall_00", Vector2i(4, 4), 0)
	var r : Dictionary = g.remove_at(db, inv, Vector2i(4, 4))
	t("remove ok", r["ok"] and r["done"] == 1)
	t("remove: item returned, struct gone", inv.count_of(&"wall_00") == 2 and g.struct_at(Vector2i(4, 4)) < 0 and g.struct_count() == 0)
	t("remove: cell reusable", g.place(db, inv, &"wall_00", Vector2i(4, 4), 0)["ok"])
	t("remove nothing", rs(g.remove_at(db, inv, Vector2i(9, 9))) == BuildGrid.NO_STRUCTURE)
	t("remove null inv", rs(g.remove_at(db, null, Vector2i(4, 4))) == BuildGrid.NULL_INVENTORY)
	# object ทับพื้น: รื้อได้ object ก่อน แล้วค่อยพื้น
	var g2 : BuildGrid = BuildGrid.new()
	var i2 : Inventory = inv_with({&"floor_00": 1, &"wall_00": 1})
	g2.place(db, i2, &"floor_00", Vector2i(1, 1), 0)
	g2.place(db, i2, &"wall_00", Vector2i(1, 1), 0)
	g2.remove_at(db, i2, Vector2i(1, 1))
	t("remove object first", g2.count_placed(&"wall_00") == 0 and g2.count_placed(&"floor_00") == 1)
	g2.remove_at(db, i2, Vector2i(1, 1))
	t("then floor", g2.struct_count() == 0 and total(g2, [i2], &"floor_00") == 1)
	# กระเป๋าเต็ม: ปฏิเสธ ไม่ทำของหาย
	var g3 : BuildGrid = BuildGrid.new()
	var full : Inventory = Inventory.new()
	full.max_slots = 1
	full.add_to_existing_stacks(db, &"wall_00", 1)
	g3.place(db, full, &"wall_00", Vector2i(0, 0), 0)
	full.add_to_existing_stacks(db, &"stone_00", 99)
	var before : Dictionary = full.to_dict()
	r = g3.remove_at(db, full, Vector2i(0, 0))
	t("remove when full rejected", rs(r) == BuildGrid.INVENTORY_FULL and r["done"] == 0)
	t("remove when full: nothing changed", full.to_dict() == before and g3.count_placed(&"wall_00") == 1)

# ---------- chest ----------
func test_chest() -> void:
	var g : BuildGrid = BuildGrid.new()
	var inv : Inventory = inv_with({&"chest_00": 3, &"stone_00": 150, &"fiber_00": 20})
	t("chest placed", g.place(db, inv, &"chest_00", Vector2i(1, 1), 0)["ok"])
	var sid : String = g.chest_id_at(Vector2i(1, 1))
	var c : Inventory = g.chest(sid)
	t("chest exists, id stable", c != null and c.owner_id == sid and sid != "")
	t("deposit ok", inv.transfer_to(c, db, &"stone_00", 40)["ok"] and c.count_of(&"stone_00") == 40)
	t("deposit: conserved", total(g, [inv], &"stone_00") == 150)
	# ลบของออกจากกระเป๋าไม่ทำให้ chest เปลี่ยน
	inv.remove_item(db, &"stone_00", 10)
	t("chest independent", c.count_of(&"stone_00") == 40)
	inv.add_to_existing_stacks(db, &"stone_00", 10)
	# รื้อ chest ที่มีของ = ปฏิเสธ
	var r : Dictionary = g.remove_at(db, inv, Vector2i(1, 1))
	t("remove chest with items rejected", rs(r) == BuildGrid.CHEST_NOT_EMPTY and g.chest(sid) != null and c.count_of(&"stone_00") == 40)
	t("withdraw ok", c.transfer_to(inv, db, &"stone_00", 40)["ok"])
	r = g.remove_at(db, inv, Vector2i(1, 1))
	t("remove empty chest ok", r["ok"] and g.chest(sid) == null and g.struct_count() == 0)
	t("chest: all conserved", total(g, [inv], &"chest_00") == 3 and total(g, [inv], &"stone_00") == 150)
	# หลาย chest เนื้อหาแยกกัน
	var g2 : BuildGrid = BuildGrid.new()
	var i2 : Inventory = inv_with({&"chest_00": 3, &"stone_00": 100, &"fiber_00": 20})
	g2.place(db, i2, &"chest_00", Vector2i(0, 0), 0)
	g2.place(db, i2, &"chest_00", Vector2i(5, 0), 0)
	var a : Inventory = g2.chest(g2.chest_id_at(Vector2i(0, 0)))
	var b : Inventory = g2.chest(g2.chest_id_at(Vector2i(5, 0)))
	i2.transfer_to(a, db, &"stone_00", 10)
	i2.transfer_to(b, db, &"stone_00", 20)
	i2.transfer_to(b, db, &"fiber_00", 5)
	t("two chests separate", a != b and a.count_of(&"stone_00") == 10 and b.count_of(&"stone_00") == 20)
	t("fiber only in b", a.count_of(&"fiber_00") == 0 and b.count_of(&"fiber_00") == 5)
	t("two chest ids", g2.chest_ids().size() == 2 and g2.chest_ids()[0] != g2.chest_ids()[1])
	t("multi chest conserved", total(g2, [i2], &"stone_00") == 100 and total(g2, [i2], &"fiber_00") == 20)
	# chest เต็ม
	var g3 : BuildGrid = BuildGrid.new()
	g3.chest_slots = 1
	var i3 : Inventory = inv_with({&"chest_00": 1, &"stone_00": 150})
	g3.place(db, i3, &"chest_00", Vector2i(0, 0), 0)
	var c3 : Inventory = g3.chest(g3.chest_id_at(Vector2i(0, 0)))
	t("fill chest", i3.transfer_to(c3, db, &"stone_00", 99)["ok"])
	var snap_i : Dictionary = i3.to_dict()
	var snap_c : Dictionary = c3.to_dict()
	r = i3.transfer_to(c3, db, &"stone_00", 1)
	t("chest full rejected", rs(r) == OpResult.DESTINATION_FULL)
	t("chest full: both unchanged", i3.to_dict() == snap_i and c3.to_dict() == snap_c)

# ---------- serialize ----------
func test_serialize() -> void:
	var g : BuildGrid = BuildGrid.new()
	var inv : Inventory = inv_with({&"floor_00": 2, &"wall_00": 2, &"workbench_00": 1, &"chest_00": 2, &"stone_00": 30})
	g.place(db, inv, &"floor_00", Vector2i(1, 1), 0)
	g.place(db, inv, &"wall_00", Vector2i(1, 1), 0)
	g.place(db, inv, &"workbench_00", Vector2i(6, 3), 1)
	g.place(db, inv, &"chest_00", Vector2i(9, 9), 0)
	var sid : String = g.chest_id_at(Vector2i(9, 9))
	inv.transfer_to(g.chest(sid), db, &"stone_00", 12)
	var d : Dictionary = g.to_dict()
	var r : Dictionary = BuildGrid.from_dict(d, db)
	t("ser ok", r["ok"] and r["reason"] == BuildGrid.OK)
	var g2 : BuildGrid = r["grid"]
	t("ser round-trip", g2 != null and g2.to_dict() == d)
	t("ser struct_at same", g2.struct_at(Vector2i(6, 4)) == g.struct_at(Vector2i(6, 4)) and g2.struct_count() == 4)
	t("ser chest content", g2.chest(sid).count_of(&"stone_00") == 12)
	var i2 : Inventory = inv_with({&"chest_00": 1})
	g2.place(db, i2, &"chest_00", Vector2i(12, 12), 0)
	t("ser next_uid kept (sid ใหม่ไม่ซ้ำ)", g2.chest_ids().size() == 2 and g2.chest_id_at(Vector2i(12, 12)) != sid)
	d["chests"][sid]["slots"][0]["quantity"] = 1
	t("ser no reference", BuildGrid.from_dict(g.to_dict(), db)["grid"].chest(sid).count_of(&"stone_00") == 12 and g.chest(sid).count_of(&"stone_00") == 12)
	t("ser empty grid", BuildGrid.from_dict(BuildGrid.new().to_dict(), db)["ok"])
	# ข้อมูลผิดต้องล้มทุกเคส
	var bad : Dictionary = g.to_dict()
	bad["schema_version"] = 99
	t("ser bad schema", BuildGrid.from_dict(bad, db)["reason"] == BuildGrid.BAD_SCHEMA)
	bad = g.to_dict()
	bad.erase("chests")
	t("ser missing key", BuildGrid.from_dict(bad, db)["reason"] == BuildGrid.INCOMPLETE_DATA)
	bad = g.to_dict()
	bad["next_uid"] = 100
	bad["structs"].append({"uid": 99, "piece": "wall_00", "x": 1, "y": 1, "rot": 0})
	t("ser overlap in data", BuildGrid.from_dict(bad, db)["reason"] == BuildGrid.OVERLAP)
	bad = g.to_dict()
	bad["structs"][0]["piece"] = "nope"
	t("ser unknown piece", BuildGrid.from_dict(bad, db)["reason"] == BuildGrid.UNKNOWN_PIECE)
	bad = g.to_dict()
	bad["chests"].erase(sid)
	t("ser chest missing", BuildGrid.from_dict(bad, db)["reason"] == BuildGrid.BAD_DATA)
	bad = g.to_dict()
	bad["structs"][0]["x"] = 99
	t("ser out of bounds in data", BuildGrid.from_dict(bad, db)["reason"] == BuildGrid.OUT_OF_BOUNDS)
	t("ser null db", BuildGrid.from_dict(g.to_dict(), null)["reason"] == BuildGrid.NULL_DB)

# ---------- fuzz: ผลรวมต้องคงที่ทุกขั้น ----------
func test_fuzz() -> void:
	var g : BuildGrid = BuildGrid.new()
	var inv : Inventory = inv_with({&"floor_00": 20, &"wall_00": 20, &"workbench_00": 5, &"chest_00": 5, &"stone_00": 150})
	var ids : Array = [&"floor_00", &"wall_00", &"workbench_00", &"chest_00"]
	var all : Array = ids + [&"stone_00"]
	var want : Dictionary = {}
	for id in all:
		want[id] = total(g, [inv], id)
	var rng : RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 4242
	var bad : int = 0
	var internal : int = 0
	var placed : int = 0
	var removed : int = 0
	var moved : int = 0
	for i in 400:
		var op : int = rng.randi() % 4
		var cell : Vector2i = Vector2i(rng.randi_range(-1, 20), rng.randi_range(-1, 15))
		var r : Dictionary = {}
		if op == 0:
			var rot : int = rng.randi_range(0, 3) if rng.randf() < 0.3 else 0
			r = g.place(db, inv, ids[rng.randi() % 4], cell, rot)
			if r["done"] > 0:
				placed += 1
		elif op == 1:
			r = g.remove_at(db, inv, cell)
			if r["done"] > 0:
				removed += 1
		else:
			var cids : Array = g.chest_ids()
			if cids.is_empty():
				continue
			var c : Inventory = g.chest(cids[rng.randi() % cids.size()])
			var q : int = rng.randi_range(0, 40)
			r = inv.transfer_to(c, db, &"stone_00", q) if op == 2 else c.transfer_to(inv, db, &"stone_00", q)
			if r["done"] > 0:
				moved += 1
		if r["reason"] == BuildGrid.INTERNAL:
			internal += 1
		for id in all:
			if total(g, [inv], id) != want[id]:
				bad += 1
	t("fuzz: conserved every step", bad == 0)
	t("fuzz: no internal", internal == 0)
	t("fuzz: exercised", placed > 10 and removed > 5 and moved > 5)
	t("fuzz: round-trip at end", BuildGrid.from_dict(g.to_dict(), db)["grid"].to_dict() == g.to_dict())
