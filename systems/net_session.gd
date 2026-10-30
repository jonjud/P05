extends Node
class_name NetSession
# Node ตัวนี้ต้องชื่อ "Net" ทั้งสองฝั่ง (RPC หากันด้วย node path)

const PORT : int = 24567
enum Status { IDLE, HOSTING, JOINING, CONNECTED, FAILED }
signal status_changed(status : int, detail : String)
signal player_joined(sender : int, pid : String)
signal player_left(sender : int, pid : String)

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
	_set_status(Status.IDLE)

# ---------- host ----------
func start_host(pid : String) -> bool:
	my_pid = pid
	logic = HostLogic.new()
	logic.db = db
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
