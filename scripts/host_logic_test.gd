extends Node
const W := &"wood_00"
var h : HostLogic
var fails : int = 0
var _rid : int = 0

func _t(n : String, c : bool) -> void:
	if not c:
		fails += 1
		print("FAIL ", n)

func _fresh(shared_slots : int = 20) -> void:
	h = HostLogic.new()
	h.allow_client_add = true   # test-only (D-24)
	h.db = ItemDatabase.new()
	h.db.load_from_directory("res://data/")
	for o in ["player_2", "player_3", "shared_01"]:
		var inv := Inventory.new()
		inv.owner_id = o
		inv.max_slots = shared_slots if o == "shared_01" else 20
		h.invs[o] = inv
	h.join(2, "player_2")
	h.join(3, "player_3")

func _r(op : String, item : StringName, q : int, src : String = "", dst : String = "") -> Dictionary:
	_rid += 1
	return {"pv": 1, "rid": _rid, "op": op, "item": String(item), "qty": q, "src": src, "dst": dst}

func _snap() -> Dictionary:
	var d : Dictionary = {}
	for o in h.invs: d[o] = h.invs[o].to_dict()
	return d

func _tot(id : StringName) -> int:
	var t : int = 0
	for o in h.invs: t += h.invs[o].count_of(id)
	return t

func _ready() -> void:
	_fresh()
	var r := h.host_handle(2, _r("add", W, 5, "", "player_2"))
	_t("add ok", r["accepted"] and r["result"]["ok"] and r["result"]["done"] == 5 and r["changed"].has("player_2"))
	var before := _snap()
	r = h.host_handle(2, _r("remove", W, 99, "player_2"))
	_t("remove เกินที่มี", r["result"]["reason"] == OpResult.NOT_ENOUGH and _snap() == before)
	r = h.host_handle(2, _r("transfer", W, 3, "player_2", "shared_01"))
	_t("transfer ok", r["result"]["ok"] and _tot(W) == 5 and h.invs["shared_01"].count_of(W) == 3)
	var dup := _r("remove", W, 1, "player_2")
	h.host_handle(2, dup)
	before = _snap()
	r = h.host_handle(2, dup)
	_t("rid ซ้ำ", not r["accepted"] and r["net_reason"] == &"duplicate_request" and _snap() == before)
	r = h.host_handle(2, _r("remove", W, 0, "player_2"))
	_t("qty 0", r["result"]["reason"] == OpResult.INVALID_QUANTITY)
	r = h.host_handle(2, _r("remove", &"no_such_item", 1, "player_2"))
	_t("item ปลอม", r["result"]["reason"] == OpResult.UNKNOWN_ITEM)
	before = _snap()
	r = h.host_handle(2, _r("remove", W, 1, "player_3"))
	_t("แตะของคนอื่น", r["net_reason"] == &"denied" and _snap() == before)
	r = h.host_handle(2, _r("transfer", W, 1, "player_3", "player_2"))
	_t("ดึงจากคนอื่น", r["net_reason"] == &"denied" and _snap() == before)
	var bad := _r("add", W, 1, "", "player_2")
	bad["pv"] = 99
	_t("protocol ไม่ตรง", h.host_handle(2, bad)["net_reason"] == &"bad_protocol")
	bad = _r("add", W, 1, "", "player_2")
	bad["qty"] = 1.0
	_t("qty เป็น float", h.host_handle(2, bad)["net_reason"] == &"bad_request")
	_fresh(1)
	h.invs["shared_01"].add_to_existing_stacks(h.db, W, 1)
	h.invs["player_2"].add_to_existing_stacks(h.db, W, 500)
	before = _snap()
	r = h.host_handle(2, _r("transfer", W, 500, "player_2", "shared_01"))
	_t("ปลายทางเต็ม", r["result"]["reason"] == OpResult.DESTINATION_FULL and _snap() == before)
	_session()
	_gather()
	_fuzz()
	print("P-12 host logic: fails = ", fails)

func _fuzz() -> void:
	_fresh()
	var exp : int = 0
	var rng := RandomNumberGenerator.new()
	rng.seed = 12345
	var owners := ["player_2", "player_3", "shared_01"]
	for i in 500:
		var s : int = [2, 3][rng.randi() % 2]
		var op : String = ["add", "remove", "transfer"][rng.randi() % 3]
		var res := h.host_handle(s, _r(op, W, rng.randi_range(-1, 60), owners[rng.randi() % 3], owners[rng.randi() % 3]))
		if not res["accepted"]: continue
		_t("ไม่เข้า INTERNAL", res["result"]["reason"] != OpResult.INTERNAL)
		if op == "add": exp += res["result"]["done"]
		elif op == "remove": exp -= res["result"]["done"]
	_t("fuzz: ผลรวมคงที่", _tot(W) == exp)
	for o in owners:
		_t("round-trip " + o, Inventory.from_dict(h.invs[o].to_dict(), h.db)["inventory"].to_dict() == h.invs[o].to_dict())

func _snap_of(x : HostLogic) -> Dictionary:
	var d : Dictionary = {}
	for o in x.invs: d[o] = x.invs[o].to_dict()
	return d

func _session() -> void:
	var s := HostLogic.new()
	s.db = h.db
	var sh := Inventory.new()
	sh.owner_id = HostLogic.SHARED_ID
	s.invs[HostLogic.SHARED_ID] = sh   # host ต้องสร้าง shared เอง (เหมือน start_host)
	var r : Dictionary = s.join(1, "p_host")
	_t("join host", r["ok"] and r["player_id"] == "p_host" and s.invs.has("p_host"))
	_t("join client", s.join(2, "p_buddy")["ok"] and s.invs["p_buddy"].owner_id == "p_buddy")
	_t("host เต็ม", s.join(3, "p_third")["reason"] == &"host_full" and not s.invs.has("p_third"))
	_t("pid ซ้ำที่ต่ออยู่", s.join(4, "p_buddy")["reason"] == &"player_already_connected")
	_t("hello ซ้ำจาก peer เดิม", s.join(2, "p_other")["reason"] == &"already_joined")
	for bad in ["", "shared_01", "chest_3", "P_UP", "a b", "p_" + "x".repeat(50)]:
		_t("pid ไม่ถูก '%s'" % bad.left(8), s.join(9, bad)["reason"] == &"bad_player_id")
	_t("pid ไม่ใช่ string", s.join(9, 5)["reason"] == &"bad_player_id")
	r = s.host_handle(2, _r("add", W, 5, "", "p_buddy"))
	_t("add ปิดโดยค่าเริ่มต้น", not r["accepted"] and r["net_reason"] == &"add_disabled" and s.invs["p_buddy"].count_of(W) == 0)
	s.allow_client_add = true
	r = s.host_handle(2, _r("add", W, 5, "", "p_buddy"))
	_t("add เปิดแล้วได้", r["accepted"] and r["result"]["done"] == 5)
	s.allow_client_add = false
	var before := _snap_of(s)
	r = s.host_handle(2, _r("transfer", W, 1, "p_buddy", "p_host"))
	_t("ผู้เล่น->ผู้เล่น ถูกปฏิเสธ", r["net_reason"] == &"player_transfer_denied" and _snap_of(s) == before)
	r = s.host_handle(2, _r("transfer", W, 1, "shared_01", "p_host"))
	_t("shared->ผู้เล่นอื่น ถูกปฏิเสธ", r["net_reason"] == &"player_transfer_denied" and _snap_of(s) == before)
	r = s.host_handle(2, _r("remove", W, 1, "p_host"))
	_t("แตะ inventory ผู้เล่นอื่น", r["net_reason"] == &"denied" and _snap_of(s) == before)
	_t("ยังไม่ join", s.host_handle(77, _r("remove", W, 1, "p_buddy"))["net_reason"] == &"not_joined")
	r = s.host_handle(2, _r("transfer", W, 1, "p_buddy", "shared_01"))
	_t("ตัวเอง->shared ได้", r["accepted"] and r["result"]["ok"] and s.invs["shared_01"].count_of(W) == 1)
	var d : Dictionary = s.invs["p_buddy"].to_dict()
	s.leave(2)
	_t("leave เก็บของไว้", s.invs["p_buddy"].to_dict() == d and not s.peers.has(2))
	_t("หลัง leave ใช้ไม่ได้", s.host_handle(2, _r("remove", W, 1, "p_buddy"))["net_reason"] == &"not_joined")
	_t("reconnect ได้ของเดิม", s.join(5, "p_buddy")["ok"] and s.invs["p_buddy"].to_dict() == d)
	var q1 := {"pv": 1, "rid": 1, "op": "remove", "item": String(W), "qty": 1, "src": "p_buddy", "dst": ""}
	r = s.host_handle(5, q1)
	_t("rid เริ่มใหม่หลัง reconnect ไม่ชน", r["accepted"] and r["result"]["done"] == 1)
	_t("rid ซ้ำใน peer เดิมยังถูกปฏิเสธ", s.host_handle(5, q1)["net_reason"] == &"duplicate_request")

func _gather() -> void:
	var s := HostLogic.new()
	s.db = h.db
	s.join(1, "p_host")
	s.join(2, "p_buddy")
	_t("add_node", s.add_node("n1", W, 30) and not s.add_node("n1", W, 5) and not s.add_node("n2", W, 0) and not s.add_node("n3", &"nope", 5))
	var r : Dictionary = s.host_handle(2, _r("gather", &"stone_00", 999999, "n1", ""))
	_t("host ให้ของเอง ไม่เชื่อ item/qty", r["accepted"] and r["result"]["done"] == 30 and s.invs["p_buddy"].count_of(W) == 30 and s.invs["p_buddy"].count_of(&"stone_00") == 0)
	_t("node หมดแล้วหาย", not s.nodes.has("n1"))
	r = s.host_handle(1, _r("gather", W, 0, "n1", ""))
	_t("คนที่สองช้ากว่า ได้ no_node", r["net_reason"] == &"no_node" and s.invs["p_host"].count_of(W) == 0)
	_t("src ไม่ใช่ node", s.host_handle(1, _r("gather", W, 0, "shared_01", ""))["net_reason"] == &"no_node")
	_t("ยังไม่ join", s.host_handle(9, _r("gather", W, 0, "n1", ""))["net_reason"] == &"not_joined")
	s.add_node("big", W, 3000)
	var free : int = s.invs["p_buddy"].free_space_for(s.db.get_item(W))
	r = s.host_handle(2, _r("gather", W, 0, "big", ""))
	_t("partial: ได้เท่าที่ใส่ได้ เหลือคงใน node", r["result"]["reason"] == OpResult.PARTIAL_FULL and r["result"]["done"] == free and s.nodes["big"]["amount"] == 3000 - free)
	r = s.host_handle(2, _r("gather", W, 0, "big", ""))
	_t("เต็ม: node ไม่เปลี่ยน", r["result"]["reason"] == OpResult.FULL and r["changed"].is_empty() and s.nodes["big"]["amount"] == 3000 - free)
	var s2 := HostLogic.new()
	s2.db = h.db
	s2.join(1, "p_host")
	s2.join(2, "p_buddy")
	for i in 3:
		s2.add_node("m%d" % i, W, 500)
	var rng := RandomNumberGenerator.new()
	rng.seed = 55
	for i in 200:
		s2.host_handle([1, 2][rng.randi() % 2], _r("gather", W, 0, "m%d" % rng.randi_range(0, 3), ""))
	var rem : int = 0
	for k in s2.nodes:
		rem += s2.nodes[k]["amount"]
	_t("fuzz gather: ผลรวมคงที่ 1500", s2.invs["p_host"].count_of(W) + s2.invs["p_buddy"].count_of(W) + rem == 1500)
