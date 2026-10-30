extends RefCounted
class_name InventoryTests

var db : ItemDatabase = ItemDatabase.new()
var passed : int = 0
var failed : int = 0

func run_all() -> void:
	db.load_from_directory("res://data/")
	test_add()
	test_remove()
	test_nonstackable()
	test_invalid_input()
	test_swap()
	test_move()
	test_transfer()
	test_atomic()
	test_serialize()
	test_deserialize()
	test_slot_range()
	test_signals()
	test_conservation()
	print("Passed ", passed, " / Failed ", failed)

# ---------- helpers ----------
func check(label : String , condition : bool) -> void:
	if condition :
		passed += 1
	else :
		failed += 1
		print("FAIL: ", label)

# ---------- signals ----------
# lambda แก้ตัวแปร int ข้างนอกไม่ได้ จึงใช้ Array เป็นตัวนับ
func count_emits(inv : Inventory) -> Array:
	var counter : Array = [0]
	inv.inventory_changed.connect(func(): counter[0] += 1)
	return counter

func stone() -> ItemData:
	return db.get_item(&"stone_00")
func wood() -> ItemData:
	return db.get_item(&"wood_00")
func sword() -> ItemData:
	return db.get_item(&"wooden_sword_00")

func add_test_slot(inv : Inventory , item : ItemData , amount : int) -> void:
	var slot : InventorySlot = InventorySlot.new()
	slot.item_data = item
	slot.quantity = amount
	inv.slots.append(slot)

func qtys(inv : Inventory) -> Array:
	var out : Array = []
	for s in inv.slots :
		out.append(s.quantity)
	return out

func ids(inv : Inventory) -> Array:
	var out : Array = []
	for s in inv.slots :
		out.append(s.item_data.id if s.item_data != null else &"")
	return out

func total_of(inv : Inventory) -> int:
	var t : int = 0
	for s in inv.slots :
		if s.item_data != null and s.item_data.id == &"stone_00" :
			t += s.quantity
	return t

func check_add(label : String , inv : Inventory , r : Dictionary , done : int , remaining : int , reason : StringName , expected : Array) -> void:
	check_contract(label, r)
	check(label + " done", r["done"] == done)
	check(label + " remaining", r["remaining"] == remaining)
	check(label + " reason", r["reason"] == reason)
	check(label + " slots", qtys(inv) == expected)

func check_remove(label : String , inv : Inventory , r : Dictionary , done : int , remaining : int , reason : StringName , expected : Array) -> void:
	check_contract(label, r)
	check(label + " atomic", r["done"] == 0 or r["done"] == r["requested"])
	check(label + " done", r["done"] == done)
	check(label + " remaining", r["remaining"] == remaining)
	check(label + " reason", r["reason"] == reason)
	check(label + " slots", qtys(inv) == expected)

func check_move(label : String , inv : Inventory , r : Dictionary , ok : bool , remaining : int , reason : StringName , expected : Array) -> void:
	check_contract(label, r)
	check(label + " ok", r["ok"] == ok)
	check(label + " remaining", r["remaining"] == remaining)
	check(label + " reason", r["reason"] == reason)
	check(label + " slots", qtys(inv) == expected)

func check_swap(label : String , inv : Inventory , r : Dictionary , ok : bool , reason : StringName , expected : Array) -> void:
	check_contract(label, r)
	check(label + " ok", r["ok"] == ok)
	check(label + " reason", r["reason"] == reason)
	check(label + " slots", qtys(inv) == expected)

func check_contract(label : String , r : Dictionary) -> void:
	check(label + " ok<=>reason", r["ok"] == (r["reason"] == OpResult.OK))
	check(label + " remaining>=0", r["remaining"] >= 0)
	if r["ok"] :
		check(label + " ok means full", r["done"] == r["requested"] and r["remaining"] == 0)
	if r["requested"] >= 0 :
		check(label + " done+remaining", r["done"] + r["remaining"] == r["requested"])

func transfer_case(label : String , src : Inventory , dst : Inventory , qty : int , ok : bool , reason : StringName , src_exp : Array , dst_exp : Array) -> void:
	var before : int = total_of(src) + total_of(dst)
	var r : Dictionary = src.transfer_to(dst, db, &"stone_00", qty)
	check_contract(label, r)
	check(label + " atomic", r["done"] == 0 or r["done"] == r["requested"])
	check(label + " ok", r["ok"] == ok)
	check(label + " reason", r["reason"] == reason)
	check(label + " src", qtys(src) == src_exp)
	check(label + " dst", qtys(dst) == dst_exp)
	check(label + " total", total_of(src) + total_of(dst) == before)

# ---------- add ----------
func test_add() -> void:
	var a1 := Inventory.new()
	a1.max_slots = 2
	check_add("add1 partial_full", a1, a1.add_to_existing_stacks(db, &"stone_00", 250), 198, 52, OpResult.PARTIAL_FULL, [99, 99])
	var a2 := Inventory.new()
	a2.max_slots = 2
	add_test_slot(a2, stone(), 99)
	add_test_slot(a2, stone(), 99)
	check_add("add2 full", a2, a2.add_to_existing_stacks(db, &"stone_00", 10), 0, 10, OpResult.FULL, [99, 99])
	var a3 := Inventory.new()
	a3.max_slots = 2
	add_test_slot(a3, stone(), 90)
	check_add("add3 exact", a3, a3.add_to_existing_stacks(db, &"stone_00", 9), 9, 0, OpResult.OK, [99])
	var a4 := Inventory.new()
	add_test_slot(a4, stone(), 90)
	add_test_slot(a4, stone(), 50)
	check_add("add4 first stack", a4, a4.add_to_existing_stacks(db, &"stone_00", 5), 5, 0, OpResult.OK, [95, 50])
	var a5 := Inventory.new()
	add_test_slot(a5, stone(), 90)
	add_test_slot(a5, stone(), 50)
	check_add("add5 new slot", a5, a5.add_to_existing_stacks(db, &"stone_00", 90), 90, 0, OpResult.OK, [99, 99, 32])
	check("fiber in db", db.has_item(&"fiber_00"))
	var f1 := Inventory.new()
	check_add("add fiber",f1,f1.add_to_existing_stacks(db,&"fiber_00",120),120,0,OpResult.OK,[99,21])

# ---------- remove (stackable) ----------
func test_remove() -> void:
	var r1 := Inventory.new()
	add_test_slot(r1, stone(), 99)
	check_remove("rm1 partial", r1, r1.remove_item(db, &"stone_00", 30), 30, 0, OpResult.OK, [69])
	var r2 := Inventory.new()
	add_test_slot(r2, stone(), 99)
	check_remove("rm2 all", r2, r2.remove_item(db, &"stone_00", 99), 99, 0, OpResult.OK, [0])
	check("rm2 slot empty", r2.slots[0].item_data == null)
	var r3 := Inventory.new()
	add_test_slot(r3, stone(), 99)
	add_test_slot(r3, stone(), 50)
	check_remove("rm3 from last", r3, r3.remove_item(db, &"stone_00", 120), 120, 0, OpResult.OK, [29, 0])
	var r4 := Inventory.new()
	add_test_slot(r4, stone(), 99)
	add_test_slot(r4, stone(), 50)
	check_remove("rm4 not enough", r4, r4.remove_item(db, &"stone_00", 150), 0, 150, OpResult.NOT_ENOUGH, [99, 50])
	var r5 := Inventory.new()
	add_test_slot(r5, stone(), 50)
	add_test_slot(r5, null, 0)
	add_test_slot(r5, stone(), 30)
	check_remove("rm5 empty middle", r5, r5.remove_item(db, &"stone_00", 60), 60, 0, OpResult.OK, [20, 0, 0])

# ---------- remove (non-stackable) ----------
func test_nonstackable() -> void:
	var n1 := Inventory.new()
	check_remove("ns1 empty inv", n1, n1.remove_item(db, &"wooden_sword_00", 3), 0, 3,OpResult.NOT_ENOUGH, [])
	var n2 := Inventory.new()
	add_test_slot(n2, sword(), 1)
	check_remove("ns2 one sword", n2, n2.remove_item(db, &"wooden_sword_00", 1), 1, 0, OpResult.OK, [0])
	var n3 := Inventory.new()
	add_test_slot(n3, sword(), 1)
	add_test_slot(n3, sword(), 1)
	check_remove("ns3 not enough", n3, n3.remove_item(db, &"wooden_sword_00", 3), 0, 3, OpResult.NOT_ENOUGH, [1, 1])
	var n4 := Inventory.new()
	add_test_slot(n4, sword(), 1)
	add_test_slot(n4, sword(), 1)
	add_test_slot(n4, sword(), 1)
	check_remove("ns4 last first", n4, n4.remove_item(db, &"wooden_sword_00", 1), 1, 0, OpResult.OK, [1, 1, 0])
	var n5 := Inventory.new()
	add_test_slot(n5, sword(), 1)
	add_test_slot(n5, null, 0)
	add_test_slot(n5, sword(), 1)
	check_remove("ns5 empty between", n5, n5.remove_item(db, &"wooden_sword_00", 1), 1, 0, OpResult.OK, [1, 0, 0])

# ---------- invalid input ----------
func test_invalid_input() -> void:
	var inv := Inventory.new()
	add_test_slot(inv, stone(), 50)
	check_remove("inv1 null db", inv, inv.remove_item(null, &"stone_00", 1), 0, 1, OpResult.NULL_DB, [50])
	check_remove("inv2 zero", inv, inv.remove_item(db, &"stone_00", 0), 0, 0, OpResult.INVALID_QUANTITY, [50])
	check_remove("inv3 negative", inv, inv.remove_item(db, &"stone_00", -1), 0, 0, OpResult.INVALID_QUANTITY, [50])
	check_remove("inv4 bad id", inv, inv.remove_item(db, &"not_existed_id", 1), 0, 1, OpResult.UNKNOWN_ITEM, [50])
	check_add("inv5 add null db", inv, inv.add_to_existing_stacks(null, &"stone_00", 1), 0, 1, OpResult.NULL_DB, [50])
	check_add("inv6 add zero", inv, inv.add_to_existing_stacks(db, &"stone_00", 0), 0, 0, OpResult.INVALID_QUANTITY, [50])
	
# ---------- swap ----------
func test_swap() -> void:
	var s1 := Inventory.new()
	add_test_slot(s1, stone(), 50)
	add_test_slot(s1, wood(), 20)
	check_swap("sw1 two items", s1, s1.swap_slots(0, 1), true, OpResult.OK, [20, 50])
	check("sw1 ids", ids(s1) == [&"wood_00", &"stone_00"])
	var s2 := Inventory.new()
	add_test_slot(s2, stone(), 10)
	add_test_slot(s2, null, 0)
	check_swap("sw2 with empty", s2, s2.swap_slots(0, 1), true, OpResult.OK, [0, 10])
	var s3 := Inventory.new()
	add_test_slot(s3, stone(), 10)
	add_test_slot(s3, wood(), 20)
	check_swap("sw3 same index", s3, s3.swap_slots(0, 0), true, OpResult.OK, [10, 20])
	var s4 := Inventory.new()
	add_test_slot(s4, stone(), 50)
	add_test_slot(s4, wood(), 30)
	check_swap("sw4 out of range", s4, s4.swap_slots(-1, 2), false, OpResult.INVALID_INDEX, [50, 30])
	var s5 := Inventory.new()
	add_test_slot(s5, stone(), 50)
	add_test_slot(s5, stone(), 30)
	check_swap("sw5 not merge", s5, s5.swap_slots(0, 1), true, OpResult.OK, [30, 50])

# ---------- move ----------
func test_move() -> void:
	var m1 := Inventory.new()
	add_test_slot(m1, stone(), 99)
	add_test_slot(m1, null, 0)
	check_move("mv1 to empty", m1, m1.move_slots(0, 1), true, 0, OpResult.OK, [0, 99])
	var m2 := Inventory.new()
	add_test_slot(m2, stone(), 30)
	add_test_slot(m2, stone(), 20)
	check_move("mv2 merge all", m2, m2.move_slots(0, 1), true, 0, OpResult.OK, [0, 50])
	var m3 := Inventory.new()
	add_test_slot(m3, wood(), 99)
	add_test_slot(m3, wood(), 50)
	check_move("mv3 merge partial", m3, m3.move_slots(0, 1), false, 50, OpResult.PARTIAL_FULL, [50, 99])
	var m4 := Inventory.new()
	add_test_slot(m4, stone(), 66)
	add_test_slot(m4, wood(), 55)
	check_move("mv4 different", m4, m4.move_slots(0, 1), true, 0, OpResult.OK, [55, 66])
	var m5 := Inventory.new()
	add_test_slot(m5, sword(), 1)
	add_test_slot(m5, sword(), 1)
	check_move("mv5 swords", m5, m5.move_slots(0, 1), true, 0, OpResult.OK, [1, 1])
	var m6 := Inventory.new()
	add_test_slot(m6, null, 0)
	add_test_slot(m6, wood(), 55)
	check_move("mv6 empty src", m6, m6.move_slots(0, 1), false, 0, OpResult.EMPTY_SOURCE, [0, 55])
	var m7 := Inventory.new()
	add_test_slot(m7, wood(), 66)
	add_test_slot(m7, wood(), 55)
	check_move("mv7 out of range", m7, m7.move_slots(-1, 2), false, 0, OpResult.INVALID_INDEX, [66, 55])
	var m8 := Inventory.new()
	add_test_slot(m8, stone(), 66)
	add_test_slot(m8, wood(), 55)
	check_move("mv8 bad same index", m8, m8.move_slots(20, 20), false, 0, OpResult.INVALID_INDEX, [66, 55])
	var m9 := Inventory.new()
	add_test_slot(m9, stone(), 66)
	add_test_slot(m9, wood(), 55)
	check_move("mv9 same index", m9, m9.move_slots(0, 0), false, 0, OpResult.SAME_INDEX, [66, 55])

# ---------- transfer ----------
func test_transfer() -> void:
	var s1 := Inventory.new()
	var d1 := Inventory.new()
	add_test_slot(s1, stone(), 50)
	add_test_slot(d1, stone(), 20)
	transfer_case("tr1 normal", s1, d1, 30, true, OpResult.OK, [20], [50])
	var s2 := Inventory.new()
	var d2 := Inventory.new()
	add_test_slot(s2, stone(), 50)
	d2.max_slots = 1
	add_test_slot(d2, stone(), 90)
	transfer_case("tr2 dst full", s2, d2, 20, false, OpResult.DESTINATION_FULL, [50], [90])
	var s3 := Inventory.new()
	var d3 := Inventory.new()
	add_test_slot(s3, stone(), 10)
	add_test_slot(d3, stone(), 20)
	transfer_case("tr3 not enough", s3, d3, 20, false, OpResult.NOT_ENOUGH, [10], [20])
	var s4 := Inventory.new()
	add_test_slot(s4, stone(), 10)
	transfer_case("tr4 to self", s4, s4, 20, false, OpResult.SAME_INVENTORY, [10], [10])
	var s5 := Inventory.new()
	var d5 := Inventory.new()
	add_test_slot(s5, stone(), 50)
	d5.max_slots = 1
	add_test_slot(d5, stone(), 90)
	transfer_case("tr5 exact fit", s5, d5, 9, true, OpResult.OK, [41], [99])
	var s6 := Inventory.new()
	var d6 := Inventory.new()
	add_test_slot(s6, stone(), 50)
	d6.max_slots = 2
	add_test_slot(d6, wood(), 10)
	transfer_case("tr6 new slot", s6, d6, 50, true, OpResult.OK, [0], [10, 50])
	check("tr6 ids", ids(d6) == [&"wood_00", &"stone_00"])
	var s7 := Inventory.new()
	var d7 := Inventory.new()
	add_test_slot(s7, stone(), 50)
	check("tr7a null other", s7.transfer_to(null, db, &"stone_00", 10)["reason"] == OpResult.NULL_INVENTORY)
	check("tr7b null db", s7.transfer_to(d7, null, &"stone_00", 10)["reason"] == OpResult.NULL_DB)
	check("tr7 unchanged", qtys(s7) == [50] and qtys(d7) == [])
	var s8 := Inventory.new()
	var d8 := Inventory.new()
	add_test_slot(s8, stone(), 90)
	add_test_slot(s8, stone(), 50)
	transfer_case("tr8 two src slots", s8, d8, 120, true, OpResult.OK, [20, 0], [99, 21])

# ---------- serialize ----------
func test_serialize() -> void:
	var inv := Inventory.new()
	inv.owner_id = "p1"
	add_test_slot(inv, stone(), 99)
	add_test_slot(inv, null, 0)
	add_test_slot(inv, db.get_item(&"fiber_00"), 5)
	var d : Dictionary = inv.to_dict()
	check("ser1 version", d["schema_version"] == 1)
	check("ser1 owner", d["owner_id"] == "p1")
	check("ser1 max_slots", d["max_slots"] == inv.max_slots)
	check("ser1 length", d["slots"].size() == 3)
	check("ser1 slot0", d["slots"][0] == {"id": "stone_00", "quantity": 99})
	check("ser1 empty", d["slots"][1] == {"id": "", "quantity": 0})
	check("ser1 slot2", d["slots"][2] == {"id": "fiber_00", "quantity": 5})
	d["slots"][0]["quantity"] = 1
	check("ser1 no reference", inv.slots[0].quantity == 99)
	check("ser2 empty inv", Inventory.new().to_dict()["slots"] == [])

# ---------- deserialize ----------
func fiber() -> ItemData:
	return db.get_item(&"fiber_00")

# dict มาตรฐาน: stone 99 / ช่องว่าง / fiber 5
func base_dict() -> Dictionary:
	var inv := Inventory.new()
	inv.owner_id = "p1"
	add_test_slot(inv, stone(), 99)
	add_test_slot(inv, null, 0)
	add_test_slot(inv, fiber(), 5)
	return inv.to_dict()

# โหลดแล้วต้องล้ม: ok == false, inventory == null, reason ตรงที่คาด
func check_fail(label : String , d : Dictionary , reason : StringName) -> void:
	var r : Dictionary = Inventory.from_dict(d, db)
	check(label + " ok", r["ok"] == false)
	check(label + " inventory", r["inventory"] == null)
	check(label + " reason", r["reason"] == reason)

func test_deserialize() -> void:
	# round-trip
	var inv := Inventory.new()
	inv.owner_id = "p1"
	add_test_slot(inv, stone(), 99)
	add_test_slot(inv, null, 0)
	add_test_slot(inv, fiber(), 5)
	var d1 : Dictionary = inv.to_dict()
	var r1 : Dictionary = Inventory.from_dict(d1, db)
	check("des1 ok", r1["ok"] == true)
	check("des1 reason", r1["reason"] == OpResult.OK)
	check("des1 same dict", r1["inventory"].to_dict() == d1)
	check("des1 owner", r1["inventory"].owner_id == "p1")
	check("des1 max_slots", r1["inventory"].max_slots == inv.max_slots)
	check("des1 empty slot kept", r1["inventory"].slots[1].item_data == null)
	check("des1 new object", r1["inventory"] != inv)
	var r2 : Dictionary = Inventory.from_dict(Inventory.new().to_dict(), db)
	check("des2 empty inv", r2["ok"] == true and r2["inventory"].slots.size() == 0)

	# แก้ dict หลังโหลด กระเป๋าที่ได้ต้องไม่เปลี่ยน
	var d : Dictionary = base_dict()
	var r3 : Dictionary = Inventory.from_dict(d, db)
	d["slots"][0]["quantity"] = 1
	check("des3 no reference", r3["inventory"].slots[0].quantity == 99)

	# ข้อมูลผิด ต้องล้มทุกเคส
	d = base_dict()
	d["slots"][0]["id"] = "no_such_item"
	check_fail("des4 unknown id", d, OpResult.UNKNOWN_ITEM)
	d = base_dict()
	d["schema_version"] = 99
	check_fail("des5 schema", d, OpResult.BAD_SCHEMA)
	d = base_dict()
	d.erase("slots")
	check_fail("des6 missing slots", d, OpResult.INCOMPLETE_DATA)
	d = base_dict()
	d["slots"][0]["quantity"] = 150
	check_fail("des7 over max_stack", d, OpResult.INVALID_QUANTITY)
	d = base_dict()
	d["slots"][0]["quantity"] = -1
	check_fail("des8 negative", d, OpResult.INVALID_QUANTITY)
	d = base_dict()
	d["slots"][0]["quantity"] = 0
	check_fail("des9 zero with item", d, OpResult.INVALID_QUANTITY)
	var r10 : Dictionary = Inventory.from_dict(base_dict(), null)
	check("des10 ok", r10["ok"] == false)
	check("des10 reason", r10["reason"] == OpResult.NULL_DB)
	d = base_dict()
	d["slots"][1]["quantity"] = 5
	check_fail("des11 empty slot with qty", d, OpResult.BAD_SLOT)
	d = base_dict()
	d["max_slots"] = 2
	check_fail("des12 too many slots", d, OpResult.TOO_MANY_SLOTS)
	d = base_dict()
	d["slots"][0] = 5
	check_fail("des13 slot not dict", d, OpResult.INCOMPLETE_SLOT)
	d = base_dict()
	d["slots"] = "x"
	check_fail("des14 slots not array", d, OpResult.BAD_SLOTS_TYPE)
	d = base_dict()
	d["slots"][0]["quantity"] = "99"
	check_fail("des15 qty wrong type", d, OpResult.BAD_SLOT)
	d = base_dict()
	d["slots"][0].erase("id")
	check_fail("des16 slot missing id", d, OpResult.INCOMPLETE_SLOT)
	d = base_dict()
	d["max_slots"] = "20"
	check_fail("des17 max_slots type", d, OpResult.BAD_MAX_SLOTS)
	d = base_dict()
	d["owner_id"] = 5
	check_fail("des18 owner type", d, OpResult.BAD_OWNER_ID)

# ---------- ช่องว่างท้าย array (ข้อ A) ----------
func one_stone() -> Inventory:
	var inv := Inventory.new()
	add_test_slot(inv, stone(), 99)
	return inv

func test_slot_range() -> void:
	var a := one_stone()
	check_move("rg1 move far", a, a.move_slots(0, 10), true, 0, OpResult.OK, [0,0,0,0,0,0,0,0,0,0,99])
	var b := one_stone()
	check_swap("rg2 swap far", b, b.swap_slots(0, 10), true, OpResult.OK, [0,0,0,0,0,0,0,0,0,0,99])
	# ล้มแล้ว array ต้องยาวเท่าเดิม (qtys เทียบทั้ง array)
	var c := one_stone()
	check_move("rg3 to max_slots", c, c.move_slots(0, 20), false, 0, OpResult.INVALID_INDEX, [99])
	var d := one_stone()
	check_move("rg4 src beyond array", d, d.move_slots(15, 0), false, 0, OpResult.EMPTY_SOURCE, [99])
	var e := one_stone()
	add_test_slot(e, null, 0)
	check_move("rg5 empty src no pad", e, e.move_slots(1, 10), false, 0, OpResult.EMPTY_SOURCE, [99, 0])
	var f := one_stone()
	check_move("rg6 same index no pad", f, f.move_slots(0, 0), false, 0, OpResult.SAME_INDEX, [99])
	var g := one_stone()
	check_swap("rg7 swap over max", g, g.swap_slots(0, 20), false, OpResult.INVALID_INDEX, [99])
	# ขอบบน: index สุดท้ายที่ใช้ได้
	var h := one_stone()
	check("rg8 last index ok", h.move_slots(0, 19)["reason"] == OpResult.OK)
	check("rg8 size", h.slots.size() == 20)
	check("rg8 item", h.slots[19].quantity == 99)
	# serialize หลังต่อช่อง
	var j := one_stone()
	j.move_slots(0, 10)
	var dj : Dictionary = j.to_dict()
	var rj : Dictionary = Inventory.from_dict(dj, db)
	check("rg9 roundtrip ok", rj["ok"] == true)
	check("rg9 same dict", rj["inventory"].to_dict() == dj)
	# max_slots เล็ก
	var k := one_stone()
	k.max_slots = 3
	check_move("rg10 last of 3", k, k.move_slots(0, 2), true, 0, OpResult.OK, [0, 0, 99])
	check_move("rg11 over 3", k, k.move_slots(2, 3), false, 0, OpResult.INVALID_INDEX, [0, 0, 99])

# ---------- signals ----------
func test_signals() -> void:
	# add
	var a := Inventory.new()
	var ca := count_emits(a)
	a.add_to_existing_stacks(db, &"stone_00", 10)
	check("sig add ok", ca[0] == 1)
	a.add_to_existing_stacks(db, &"no_such_id", 10)
	a.add_to_existing_stacks(db, &"stone_00", 0)
	check("sig add fail", ca[0] == 1)
	var f := Inventory.new()
	f.max_slots = 1
	add_test_slot(f, stone(), 99)
	var cf := count_emits(f)
	f.add_to_existing_stacks(db, &"stone_00", 10)
	check("sig add full", cf[0] == 0)
	var p := Inventory.new()
	p.max_slots = 1
	add_test_slot(p, stone(), 90)
	var cp := count_emits(p)
	p.add_to_existing_stacks(db, &"stone_00", 20)
	check("sig add partial", cp[0] == 1)

	# remove
	var r := Inventory.new()
	add_test_slot(r, stone(), 50)
	var cr := count_emits(r)
	r.remove_item(db, &"stone_00", 10)
	check("sig remove ok", cr[0] == 1)
	r.remove_item(db, &"stone_00", 999)
	check("sig remove fail", cr[0] == 1)

	# swap
	var s := Inventory.new()
	add_test_slot(s, stone(), 50)
	add_test_slot(s, wood(), 20)
	var cs := count_emits(s)
	s.swap_slots(0, 1)
	check("sig swap ok", cs[0] == 1)
	s.swap_slots(-1, 1)
	check("sig swap fail", cs[0] == 1)

	# move: สลับ / รวม stack / ไปช่องว่าง ต้องยิงอย่างละครั้ง ล้มต้องไม่ยิง
	var m1 := Inventory.new()
	add_test_slot(m1, stone(), 50)
	add_test_slot(m1, wood(), 20)
	var cm1 := count_emits(m1)
	m1.move_slots(0, 1)
	check("sig move swap once", cm1[0] == 1)
	var m2 := Inventory.new()
	add_test_slot(m2, stone(), 30)
	add_test_slot(m2, stone(), 20)
	var cm2 := count_emits(m2)
	m2.move_slots(0, 1)
	check("sig move merge once", cm2[0] == 1)
	var m3 := Inventory.new()
	add_test_slot(m3, stone(), 30)
	add_test_slot(m3, null, 0)
	var cm3 := count_emits(m3)
	m3.move_slots(0, 1)
	check("sig move to empty once", cm3[0] == 1)
	m3.move_slots(1, 1)
	check("sig move fail", cm3[0] == 1)

	# transfer: สำเร็จ ฝั่งละครั้ง / ล้ม ไม่ยิงทั้งสองฝั่ง
	var s1 := Inventory.new()
	var d1 := Inventory.new()
	add_test_slot(s1, stone(), 50)
	var cs1 := count_emits(s1)
	var cd1 := count_emits(d1)
	s1.transfer_to(d1, db, &"stone_00", 30)
	check("sig transfer src ok", cs1[0] == 1)
	check("sig transfer dst ok", cd1[0] == 1)
	var s2 := Inventory.new()
	var d2 := Inventory.new()
	add_test_slot(s2, stone(), 50)
	d2.max_slots = 1
	add_test_slot(d2, stone(), 99)
	var cs2 := count_emits(s2)
	var cd2 := count_emits(d2)
	s2.transfer_to(d2, db, &"stone_00", 10)
	check("sig transfer src fail", cs2[0] == 0)
	check("sig transfer dst fail", cd2[0] == 0)

# ---------- atomic (P03-X2) ----------
func sample_inventories() -> Array:
	var out : Array = []
	out.append(Inventory.new())                          # 0 ว่าง
	var i2 := Inventory.new()                            # 1 stone 50
	add_test_slot(i2, stone(), 50)
	out.append(i2)
	var i3 := Inventory.new()                            # 2 เต็มช่องเดียว
	i3.max_slots = 1
	add_test_slot(i3, stone(), 99)
	out.append(i3)
	var i4 := Inventory.new()                            # 3 stone, ช่องว่าง, wood
	i4.max_slots = 4
	add_test_slot(i4, stone(), 90)
	add_test_slot(i4, null, 0)
	add_test_slot(i4, wood(), 10)
	out.append(i4)
	var i5 := Inventory.new()                            # 4 ใกล้เต็ม
	i5.max_slots = 2
	add_test_slot(i5, stone(), 99)
	add_test_slot(i5, wood(), 99)
	out.append(i5)
	return out

func clone_inv(inv : Inventory) -> Inventory:
	return Inventory.from_dict(inv.to_dict(), db)["inventory"]

func test_atomic() -> void:
	var tries : Array = [1, 9, 10, 50, 98, 99, 100, 150, 250, 400]
	var list : Array = sample_inventories()
	
	# (ก) free_space_for ต้องตรงกับที่ add ใส่ได้จริง
	for i in range(list.size()):
		var predicted : int = list[i].free_space_for(stone())
		for q in tries:
			var c : Inventory = clone_inv(list[i])
			var r : Dictionary = c.add_to_existing_stacks(db, &"stone_00", q)
			check("atm free_space i%d q%d" % [i, q], r["done"] == mini(q, predicted))
	
	# (ข) transfer ทุกคู่ × ทุกจำนวน ต้อง "ครบ" หรือ "ไม่เปลี่ยนอะไรเลย" และผลรวมไม่เปลี่ยน
	for i in range(list.size()):
		for j in range(list.size()):
			for q in tries:
				var src : Inventory = clone_inv(list[i])
				var dst : Inventory = clone_inv(list[j])
				var before_src : Array = qtys(src)
				var before_dst : Array = qtys(dst)
				var total_before : int = total_of(src) + total_of(dst)
				var r : Dictionary = src.transfer_to(dst, db, &"stone_00", q)
				var label : String = "atm tr %d>%d q%d" % [i, j, q]
				check_contract(label, r)
				check(label + " all or nothing", r["done"] == 0 or r["done"] == q)
				check(label + " conserved", total_of(src) + total_of(dst) == total_before)
				check(label + " not internal", r["reason"] != OpResult.INTERNAL)
				if not r["ok"]:
					check(label + " unchanged", qtys(src) == before_src and qtys(dst) == before_dst)

# ---------- conservation ของ swap/move ----------
func totals(inv : Inventory) -> Array:
	return [inv.count_of(&"stone_00"), inv.count_of(&"wood_00")]

func test_conservation() -> void:
	var idx : Array = [-1, 0, 1, 2, 3, 5, 19, 20]
	var list : Array = sample_inventories()
	for i in range(list.size()):
		for a in idx:
			for b in idx:
				var label : String = "cons i%d %d,%d" % [i, a, b]
				var s : Inventory = clone_inv(list[i])
				var before : Array = totals(s)
				var r1 : Dictionary = s.swap_slots(a, b)
				check_contract(label + " swap", r1)
				check(label + " swap total", totals(s) == before)
				var m : Inventory = clone_inv(list[i])
				var r2 : Dictionary = m.move_slots(a, b)
				check_contract(label + " move", r2)
				check(label + " move total", totals(m) == before)
				if r2["done"] == 0:
					check(label + " move unchanged", qtys(m) == qtys(list[i]))
