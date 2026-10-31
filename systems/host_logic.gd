extends RefCounted
class_name HostLogic

const PROTOCOL_VERSION : int = 1
const SHARED_ID : String = "shared_01"
const MAX_PLAYERS : int = 2   # รวม host (OQ-08-08)
const GATHER_RANGE : float = 80.0   # กว้างกว่า InteractPick.RANGE (48) เผื่อ latency
var db : ItemDatabase
var invs : Dictionary = {}    # owner_id -> Inventory (host ถือของจริง)
var peers : Dictionary = {}   # sender(peer id) -> player_id (D-23)
var nodes : Dictionary = {}   # node_id -> {"item": StringName, "amount": int} (host ถือของจริง)
var positions : Dictionary = {}   # sender -> Vector2 (PlayerSync เขียน) ไว้ตรวจระยะ
var allow_client_add : bool = false   # D-24: production ปิด, harness/test เปิดเอง
var _seen : Dictionary = {}   # sender -> {rid: true} (ล้างตอน leave)

func _err(rid : int, why : StringName) -> Dictionary:
	return {"rid": rid, "accepted": false, "net_reason": why, "result": null, "changed": {}}

func _shape_ok(r : Dictionary) -> bool:
	for k in ["op", "item", "src", "dst"]:
		if typeof(r.get(k)) != TYPE_STRING:
			return false
	return typeof(r.get("qty")) == TYPE_INT

# player_id มาจาก client จึงต้องกันชื่อที่ชนกับ id ของ host เอง (shared, chest)
static func valid_player_id(pid : Variant) -> bool:
	if typeof(pid) != TYPE_STRING:
		return false
	var s : String = pid
	if s == SHARED_ID or s.begins_with("chest_"):
		return false
	var re : RegEx = RegEx.new()
	re.compile("^[a-z0-9_]{1,40}$")
	return re.search(s) != null

func _join_res(ok : bool, reason : StringName, pid : String = "") -> Dictionary:
	return {"ok": ok, "reason": reason, "player_id": pid}

# เรียกตอน handshake ผ่านแล้ว (protocol_version + db_sig) ตัวตนมาจาก peer id ที่เครือข่ายยืนยัน
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
	peers[sender] = p
	return _join_res(true, &"ok", p)

# Inventory อยู่ต่อ (reconnect ด้วย player_id เดิมได้ของเดิม) rid เริ่มใหม่ตาม peer ใหม่
func leave(sender : int) -> void:
	peers.erase(sender)
	positions.erase(sender)
	_seen.erase(sender)

func add_node(node_id : String, item : StringName, amount : int, pos : Variant = null) -> bool:
	if node_id == "" or amount <= 0 or db == null or db.get_item(item) == null or nodes.has(node_id):
		return false
	nodes[node_id] = {"item": item, "amount": amount}
	if typeof(pos) == TYPE_VECTOR2:
		nodes[node_id]["pos"] = pos
	return true

# ตัวตนผู้ขอมาจาก peers[sender] ไม่ใช่จาก payload
func _get_for(sender : int, owner : String) -> Inventory:
	if owner == SHARED_ID or owner == peers.get(sender, ""):
		return invs.get(owner)
	return null

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
			touched = [req["dst"]]
		"remove":
			var inv : Inventory = _get_for(sender, req["src"])
			if inv == null: return _err(rid, &"denied")
			res = inv.remove_item(db, id, q)
			touched = [req["src"]]
		"transfer":    # D-22: ได้เฉพาะ ตัวเอง <-> shared ไม่มีผู้เล่น -> ผู้เล่น
			var a : Inventory = _get_for(sender, req["src"])
			if a == null: return _err(rid, &"denied")
			var dst : String = req["dst"]
			if dst != SHARED_ID and dst != me:
				return _err(rid, &"player_transfer_denied" if invs.has(dst) else &"denied")
			var b : Inventory = invs.get(dst)
			if b == null: return _err(rid, &"denied")
			res = a.transfer_to(b, db, id, q)
			touched = [req["src"], dst]
		"gather":    # D-24: host ให้ของเอง ไม่เชื่อ item/qty จาก client
			var n : Dictionary = nodes.get(req["src"], {})
			if n.is_empty(): return _err(rid, &"no_node")
			if n.has("pos"):
				var pp : Variant = positions.get(sender)
				if typeof(pp) != TYPE_VECTOR2 or (pp as Vector2).distance_to(n["pos"]) > GATHER_RANGE:
					return _err(rid, &"too_far")
			res = invs[me].add_to_existing_stacks(db, n["item"], n["amount"])
			if res["done"] > 0:
				n["amount"] -= res["done"]
				if n["amount"] <= 0: nodes.erase(req["src"])
			touched = [me]
		_:
			return _err(rid, &"bad_op")
	if res["reason"] == OpResult.INTERNAL:
		push_error("P-05: INTERNAL ใน transfer_to ถือเป็นบั๊ก หยุดและรายงาน")
	var changed : Dictionary = {}
	if res["done"] > 0:
		for o in touched:
			changed[o] = invs[o].to_dict()
	return {"rid": rid, "accepted": true, "net_reason": &"", "result": res, "changed": changed}
