extends RefCounted
class_name HostLogic

const PROTOCOL_VERSION : int = 1
const SHARED_ID : String = "shared_01"
const MAX_PLAYERS : int = 2
const GATHER_RANGE : float = 80.0
const CHEST_RANGE : float = 96.0
const CELL_LIMIT : int = 100000
var db : ItemDatabase
var invs : Dictionary = {}       # owner_id -> Inventory (ผู้เล่น + shared)
var peers : Dictionary = {}      # sender -> player_id (D-23)
var nodes : Dictionary = {}      # node_id -> {item, amount, pos?}
var positions : Dictionary = {}  # sender -> Vector2 (PlayerSync เขียน)
var grid : BuildGrid = BuildGrid.new()   # โครงสร้าง + chest (host ถือของจริง)
var starter : Dictionary = {}    # test-only: ของเริ่มต้นของ inventory ใหม่
var minted : Dictionary = {}     # item -> จำนวนสุทธิที่ host สร้าง (ไว้ตรวจ conservation)
var allow_client_add : bool = false
var _seen : Dictionary = {}

func _err(rid : int, why : StringName) -> Dictionary:
	return {"rid": rid, "accepted": false, "net_reason": why, "result": null, "changed": {}}

func _shape_ok(r : Dictionary) -> bool:
	for k in ["op", "item", "src", "dst"]:
		if typeof(r.get(k)) != TYPE_STRING:
			return false
	return typeof(r.get("qty")) == TYPE_INT

static func valid_player_id(pid : Variant) -> bool:
	if typeof(pid) != TYPE_STRING:
		return false
	var s : String = pid
	if s == SHARED_ID or s.begins_with("chest_"):
		return false
	var re : RegEx = RegEx.new()
	re.compile("^[a-z0-9_]{1,40}$")
	return re.search(s) != null

# "x,y" -> Vector2i หรือ null (ไม่เพิ่มรูปแบบ envelope: cell อยู่ใน src)
static func parse_cell(s : String) -> Variant:
	if s.length() > 24:
		return null
	var p : PackedStringArray = s.split(",")
	if p.size() != 2 or not p[0].is_valid_int() or not p[1].is_valid_int():
		return null
	var x : int = int(p[0])
	var y : int = int(p[1])
	if absi(x) > CELL_LIMIT or absi(y) > CELL_LIMIT:
		return null
	return Vector2i(x, y)

static func piece_center(p : BuildingPieceData, cell : Vector2i, rot : int) -> Vector2:
	return BuildConst.cell_to_world(cell) + Vector2(BuildGrid.footprint(p, rot) * BuildConst.CELL_SIZE) / 2.0

func _join_res(ok : bool, reason : StringName, pid : String = "") -> Dictionary:
	return {"ok": ok, "reason": reason, "player_id": pid}

func join(sender : int, pid : Variant) -> Dictionary:
	if not valid_player_id(pid):
		return _join_res(false, &"bad_player_id")
	var p : String = pid
	if peers.has(sender):
		return _join_res(false, &"already_joined")
	if peers.values().has(p):
		return _join_res(false, &"player_already_connected")
	if peers.size() >= MAX_PLAYERS:
		return _join_res(false, &"host_full")
	if not invs.has(p):
		var inv : Inventory = Inventory.new()
		inv.owner_id = p
		invs[p] = inv
		for it in starter:   # ให้เฉพาะ inventory ใหม่ reconnect ไม่ได้ซ้ำ
			var r : Dictionary = inv.add_to_existing_stacks(db, it, starter[it])
			minted[it] = minted.get(it, 0) + r["done"]
	peers[sender] = p
	return _join_res(true, &"ok", p)

func add_node(node_id : String, item : StringName, amount : int, pos : Variant = null) -> bool:
	if node_id == "" or amount <= 0 or db == null or db.get_item(item) == null or nodes.has(node_id):
		return false
	nodes[node_id] = {"item": item, "amount": amount}
	if typeof(pos) == TYPE_VECTOR2:
		nodes[node_id]["pos"] = pos
	minted[item] = minted.get(item, 0) + amount
	return true

func leave(sender : int) -> void:
	peers.erase(sender)
	positions.erase(sender)
	_seen.erase(sender)

func total_of(it : StringName) -> int:
	var t : int = grid.count_placed(it) + grid.count_in_chests(it)
	for o in invs:
		t += invs[o].count_of(it)
	for k in nodes:
		if nodes[k]["item"] == it:
			t += nodes[k]["amount"]
	return t

func conserved() -> bool:
	for it in minted:
		if total_of(it) != minted[it]:
			return false
	return true

func _get_for(sender : int, owner : String) -> Inventory:
	if owner == SHARED_ID or owner == peers.get(sender, ""):
		return invs.get(owner)
	return null

func _xfer_inv(sender : int, owner : String) -> Inventory:
	var i : Inventory = _get_for(sender, owner)
	return i if i != null else grid.chest(owner)

func _chest_pos(sid : String) -> Variant:
	if not sid.begins_with("chest_") or not sid.substr(6).is_valid_int():
		return null
	var s : Dictionary = grid.get_struct(int(sid.substr(6)))
	if s.is_empty():
		return null
	var p : BuildingPieceData = db.get_item(StringName(s["piece"])) as BuildingPieceData
	return piece_center(p, s["cell"], s["rot"]) if p != null else null

func _near(sender : int, pos : Variant, rng : float) -> bool:
	var pp : Variant = positions.get(sender)
	return typeof(pp) == TYPE_VECTOR2 and typeof(pos) == TYPE_VECTOR2 and (pp as Vector2).distance_to(pos) <= rng

func host_handle(sender : int, req : Dictionary) -> Dictionary:
	var rid = req.get("rid")
	if typeof(rid) != TYPE_INT or rid < 0 or not _shape_ok(req):
		return _err(-1, &"bad_request")
	if typeof(req.get("pv")) != TYPE_INT or req["pv"] != PROTOCOL_VERSION:
		return _err(rid, &"bad_protocol")
	if not peers.has(sender):
		return _err(rid, &"not_joined")
	var seen : Dictionary = _seen.get_or_add(sender, {})
	if seen.has(rid):
		return _err(rid, &"duplicate_request")
	seen[rid] = true
	var me : String = peers[sender]
	var id : StringName = StringName(req["item"])
	var q : int = req["qty"]
	var res : Dictionary
	var touched : Array = []
	match req["op"]:
		"add":    # D-24: production ปิด host ให้ของเองจากการเก็บ
			if not allow_client_add:
				return _err(rid, &"add_disabled")
			var inv : Inventory = _get_for(sender, req["dst"])
			if inv == null: return _err(rid, &"denied")
			res = inv.add_to_existing_stacks(db, id, q)
			if res["done"] > 0: minted[id] = minted.get(id, 0) + res["done"]
			touched = [req["dst"]]
		"remove":
			var inv : Inventory = _get_for(sender, req["src"])
			if inv == null: return _err(rid, &"denied")
			res = inv.remove_item(db, id, q)
			if res["done"] > 0: minted[id] = minted.get(id, 0) - res["done"]
			touched = [req["src"]]
		"transfer":    # D-22: ต้องมีฝั่งเป็นตัวเอง; ปลายทาง/ต้นทางเป็น shared หรือ chest ได้
			var src : String = req["src"]
			var dst : String = req["dst"]
			var a : Inventory = _xfer_inv(sender, src)
			if a == null: return _err(rid, &"denied")
			if dst != SHARED_ID and dst != me and invs.has(dst):
				return _err(rid, &"player_transfer_denied")
			var b : Inventory = _xfer_inv(sender, dst)
			if b == null or (src != me and dst != me): return _err(rid, &"denied")
			for o in [src, dst]:
				if grid.chest(o) != null and not _near(sender, _chest_pos(o), CHEST_RANGE):
					return _err(rid, &"too_far")
			res = a.transfer_to(b, db, id, q)
			touched = [src, dst]
		"gather":    # D-24: host ให้ของเอง ไม่เชื่อ item/qty จาก client
			var n : Dictionary = nodes.get(req["src"], {})
			if n.is_empty(): return _err(rid, &"no_node")
			if n.has("pos") and not _near(sender, n["pos"], GATHER_RANGE):
				return _err(rid, &"too_far")
			res = invs[me].add_to_existing_stacks(db, n["item"], n["amount"])
			if res["done"] > 0:
				n["amount"] -= res["done"]
				if n["amount"] <= 0: nodes.erase(req["src"])
			touched = [me]
		"place":    # item=ชิ้น, qty=rot, src="x,y"
			var c : Variant = parse_cell(req["src"])
			if c == null: return _err(rid, &"bad_request")
			res = grid.place(db, invs[me], id, c, q)
			touched = [me]
		"demolish":    # src="x,y" ทุกคนรื้อได้ (D-25) ของคืนผู้รื้อ
			var c : Variant = parse_cell(req["src"])
			if c == null: return _err(rid, &"bad_request")
			res = grid.remove_at(db, invs[me], c)
			touched = [me]
		_:
			return _err(rid, &"bad_op")
	if res["reason"] == OpResult.INTERNAL:
		push_error("P-05: INTERNAL ถือเป็นบั๊ก หยุดและรายงาน")
	var changed : Dictionary = {}
	if res["done"] > 0:
		for o in touched:
			if invs.has(o):    # chest อยู่ใน grid ส่งผ่าน grid ทั้งก้อน
				changed[o] = invs[o].to_dict()
	return {"rid": rid, "accepted": true, "net_reason": &"", "result": res, "changed": changed}
