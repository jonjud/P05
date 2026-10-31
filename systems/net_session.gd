extends Node
class_name NetSession
# Node ตัวนี้ต้องชื่อ "Net" ทั้งสองฝั่ง (RPC หากันด้วย node path)

const PORT : int = 24567
enum Status { IDLE, HOSTING, JOINING, CONNECTED, FAILED }
signal status_changed(status : int, detail : String)
signal player_joined(sender : int, pid : String)
signal player_left(sender : int, pid : String)
signal inventories_changed
signal nodes_changed
signal result_received(res : Dictionary)
var replicas : Dictionary = {}    # client: owner_id -> Inventory (host ใช้ logic.invs)
var node_view : Dictionary = {}   # client: node_id -> {item, amount, pos}
var dev_hash : bool = true        # dev only: ปิดใน release (INT-18)
var reqs : int = 0
var inv_fail : int = 0
var _rid : int = 0
var _resyncs : int = 0
signal grid_changed
var grid_view : BuildGrid = BuildGrid.new()   # client: สำเนา grid จาก host
var starter : Dictionary = {}   # test-only: ของเริ่มต้นของ inventory ใหม่ (host ตั้งใน p05_main)

var db : ItemDatabase
var logic : HostLogic
var status : int = Status.IDLE
var my_pid : String = ""
var hello_pv : int = HostLogic.PROTOCOL_VERSION   # --badpv ใช้ทดสอบ
var accepted : Dictionary = {}   # peer id -> true (ฝั่ง host)

# dev only (INT-18): ต้องปิดได้ใน release; อ่าน _items ตรงเพราะยังไม่มี API (P03-X3)
static func db_sig(d : ItemDatabase) -> String:
	var ids : Array = d._items.keys().map(func(k): return String(k))
	ids.sort()
	return "%d:%s" % [ids.size(), "|".join(ids).sha256_text()]

# player_id ถาวร (D-23): สร้างครั้งแรกแล้วเก็บในเครื่อง override ไว้ทดสอบหลาย instance บนเครื่องเดียว
static func load_player_id(override : String = "") -> String:
	if override != "":
		return override
	var path : String = "user://player_id.txt"
	if FileAccess.file_exists(path):
		var s : String = FileAccess.get_file_as_string(path).strip_edges()
		if HostLogic.valid_player_id(s):
			return s
	var pid : String = "p_" + "%08x%08x" % [randi(), randi()]
	var f : FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if f != null:
		f.store_string(pid)
	return pid

func _set_status(s : int, detail : String = "") -> void:
	status = s
	status_changed.emit(s, detail)

func _ready() -> void:
	multiplayer.peer_disconnected.connect(_on_left)
	multiplayer.connected_to_server.connect(_on_connected)
	multiplayer.connection_failed.connect(func(): _set_status(Status.FAILED, "connect_failed"))
	multiplayer.server_disconnected.connect(_on_host_lost)

func reset() -> void:
	var p : MultiplayerPeer = multiplayer.multiplayer_peer
	if p != null:
		p.close()
	multiplayer.multiplayer_peer = null
	accepted.clear()
	logic = null
	replicas.clear()
	node_view.clear()
	grid_view = BuildGrid.new()
	_rid = 0
	_resyncs = 0
	_set_status(Status.IDLE)

# ---------- host ----------
func start_host(pid : String) -> bool:
	my_pid = pid
	logic = HostLogic.new()
	logic.db = db
	logic.starter = starter
	var sh : Inventory = Inventory.new()
	sh.owner_id = HostLogic.SHARED_ID
	logic.invs[HostLogic.SHARED_ID] = sh
	var j : Dictionary = logic.join(1, pid)
	if not j["ok"]:
		_set_status(Status.FAILED, String(j["reason"]))
		return false
	var p : ENetMultiplayerPeer = ENetMultiplayerPeer.new()
	if p.create_server(PORT, 4) != OK:
		_set_status(Status.FAILED, "listen_failed")
		return false
	multiplayer.multiplayer_peer = p
	accepted[1] = true
	_set_status(Status.HOSTING, "port %d" % PORT)
	return true

func _reject(id : int, why : String) -> void:
	cli_rejected.rpc_id(id, why)
	get_tree().create_timer(0.3).timeout.connect(func():
		if multiplayer.get_peers().has(id):
			multiplayer.multiplayer_peer.disconnect_peer(id))

@rpc("any_peer", "call_remote", "reliable")
func hs_hello(pv : int, sig : String, pid : String) -> void:
	if not multiplayer.is_server():
		return
	var id : int = multiplayer.get_remote_sender_id()
	if pv != HostLogic.PROTOCOL_VERSION:
		_reject(id, "bad_protocol")
		return
	if sig != db_sig(db):
		_reject(id, "db_mismatch")
		return
	var j : Dictionary = logic.join(id, pid)
	if not j["ok"]:
		_reject(id, String(j["reason"]))
		return
	accepted[id] = true
	cli_welcome.rpc_id(id, pid)
	cli_full.rpc_id(id, _snapshot(), _nodes_payload(), logic.grid.to_dict())
	for p in accepted:
		if p != 1 and p != id:
			cli_delta.rpc_id(p, {pid: logic.invs[pid].to_dict()})
	inventories_changed.emit()
	player_joined.emit(id, pid)


func _on_left(id : int) -> void:
	if logic == null:
		return
	var pid : String = logic.peers.get(id, "")
	accepted.erase(id)
	logic.leave(id)
	if pid != "":
		player_left.emit(id, pid)

# ---------- client ----------
func join_host(addr : String, pid : String) -> bool:
	my_pid = pid
	var p : ENetMultiplayerPeer = ENetMultiplayerPeer.new()
	if p.create_client(addr, PORT) != OK:
		_set_status(Status.FAILED, "connect_failed")
		return false
	multiplayer.multiplayer_peer = p
	_set_status(Status.JOINING, addr)
	return true

func _on_connected() -> void:
	hs_hello.rpc_id(1, hello_pv, db_sig(db), my_pid)

func _on_host_lost() -> void:
	if status != Status.FAILED:   # ถ้าโดนปฏิเสธแล้ว ให้คงเหตุผลเดิมไว้
		_set_status(Status.FAILED, "host_lost")

@rpc("authority", "call_remote", "reliable")
func cli_welcome(pid : String) -> void:
	_set_status(Status.CONNECTED, pid)

@rpc("authority", "call_remote", "reliable")
func cli_rejected(why : String) -> void:
	_set_status(Status.FAILED, why)

static func state_hash(d : Dictionary) -> String:   # dev only
	var o : Dictionary = {}
	for k in d: o[k] = d[k].to_dict()
	return JSON.stringify(o, "", true).sha256_text().left(12)

func _snapshot() -> Dictionary:
	var d : Dictionary = {}
	for o in logic.invs: d[o] = logic.invs[o].to_dict()
	return d

func _nodes_payload() -> Dictionary:
	var d : Dictionary = {}
	for k in logic.nodes:
		var n : Dictionary = logic.nodes[k]
		d[k] = {"item": String(n["item"]), "amount": n["amount"], "pos": n.get("pos", Vector2.ZERO)}
	return d

func my_inv() -> Inventory:
	return logic.invs.get(my_pid) if logic != null else replicas.get(my_pid)

func nodes_now() -> Dictionary:
	return _nodes_payload() if logic != null else node_view




func send_request(op : String, item : StringName, qty : int, src : String = "", dst : String = "") -> int:
	_rid += 1
	var req : Dictionary = {"pv": HostLogic.PROTOCOL_VERSION, "rid": _rid, "op": op, "item": String(item), "qty": qty, "src": src, "dst": dst}
	if logic != null:
		_serve(1, req, true)
	else:
		srv_request.rpc_id(1, req)
	return _rid

func _serve(id : int, req : Dictionary, local : bool) -> void:
	if not accepted.has(id):
		return
	reqs += 1
	var before : String = _dev_state() if dev_hash else ""
	var res : Dictionary = logic.host_handle(id, req)
	var moved : bool = res["accepted"] and res["result"]["done"] > 0
	if not res["changed"].is_empty():
		for p in accepted:
			if p != 1: cli_delta.rpc_id(p, res["changed"])
		inventories_changed.emit()
	if moved:
		if req.get("op") == "gather":
			for p in accepted:
				if p != 1: cli_nodes.rpc_id(p, _nodes_payload())
			nodes_changed.emit()
		elif _touches_grid(req):
			var gd : Dictionary = logic.grid.to_dict()
			for p in accepted:
				if p != 1: cli_grid.rpc_id(p, gd)
			grid_changed.emit()
	if dev_hash:
		res["h"] = state_hash(logic.invs)
		res["g"] = grid_hash(logic.grid.to_dict())
		if not moved and _dev_state() != before:
			inv_fail += 1
			push_error("STATE CHANGED ON REJECT req=%s" % str(req))
		if not logic.conserved():
			inv_fail += 1
			push_error("INVARIANT FAIL req=%s" % str(req))
	if local:
		result_received.emit(res)
	else:
		cli_result.rpc_id(id, res)

@rpc("any_peer", "call_remote", "reliable")
func srv_request(req : Dictionary) -> void:
	if multiplayer.is_server():
		_serve(multiplayer.get_remote_sender_id(), req, false)

@rpc("any_peer", "call_remote", "reliable")
func srv_resync() -> void:
	var id : int = multiplayer.get_remote_sender_id()
	if multiplayer.is_server() and accepted.has(id):
		cli_full.rpc_id(id, _snapshot(), _nodes_payload(), logic.grid.to_dict())

@rpc("authority", "call_remote", "reliable")
func cli_full(snap : Dictionary, nodes : Dictionary, grid : Dictionary) -> void:
	_apply(snap, true)
	node_view = nodes
	_apply_grid(grid)
	nodes_changed.emit()

@rpc("authority", "call_remote", "reliable")
func cli_delta(changed : Dictionary) -> void:
	_apply(changed, false)

@rpc("authority", "call_remote", "reliable")
func cli_nodes(nodes : Dictionary) -> void:
	node_view = nodes
	nodes_changed.emit()

@rpc("authority", "call_remote", "reliable")
func cli_result(res : Dictionary) -> void:
	result_received.emit(res)

func _apply(d : Dictionary, full : bool) -> void:
	var fresh : Dictionary = {}
	for o in d:
		var r : Dictionary = Inventory.from_dict(d[o], db)
		if not r["ok"]:
			push_error("from_dict ล้ม %s: %s" % [o, r["reason"]])
			if _resyncs < 3:
				_resyncs += 1
				srv_resync.rpc_id(1)
			return
		fresh[o] = r["inventory"]
	if full:
		replicas = fresh
	else:
		replicas.merge(fresh, true)
	inventories_changed.emit()

static func grid_hash(d : Dictionary) -> String:   # dev only
	return JSON.stringify(d, "", true).sha256_text().left(12)

static func _touches_grid(req : Dictionary) -> bool:
	var op : String = req.get("op", "")
	return op == "place" or op == "demolish" or (op == "transfer" and (str(req.get("src")).begins_with("chest_") or str(req.get("dst")).begins_with("chest_")))

func grid_now() -> BuildGrid:
	return logic.grid if logic != null else grid_view

func next_rid() -> int:   # ให้ UI ลงทะเบียน rid ก่อนส่ง (host ตอบแบบ synchronous)
	return _rid + 1

@rpc("authority", "call_remote", "reliable")
func cli_grid(d : Dictionary) -> void:
	_apply_grid(d)

func _apply_grid(d : Dictionary) -> void:
	var r : Dictionary = BuildGrid.from_dict(d, db)
	if not r["ok"]:
		push_error("grid from_dict ล้ม: %s" % r["reason"])
		if _resyncs < 3:
			_resyncs += 1
			srv_resync.rpc_id(1)
		return
	grid_view = r["grid"]
	grid_changed.emit()

func send_raw(req : Dictionary) -> void:   # dev: ส่งคำขอปลอมได้
	srv_request.rpc_id(1, req)

func _dev_state() -> String:
	return state_hash(logic.invs) + grid_hash(logic.grid.to_dict()) + str(logic.nodes.hash())
