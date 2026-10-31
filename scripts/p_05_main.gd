extends Node

var sync : PlayerSync
var net : NetSession
var pid : String = ""
var quiet : bool = false
var stat : Dictionary = {"n": 0, "won": 0, "diverge": 0}

func _arg(a : PackedStringArray, key : String, def : String = "") -> String:
	var i : int = a.find(key)
	if i < 0 or i + 1 >= a.size() or a[i + 1].begins_with("--"):
		return def
	return a[i + 1]

func _ready() -> void:
	var a : PackedStringArray = OS.get_cmdline_user_args()
	quiet = "--quiet" in a
	net = NetSession.new()
	net.name = "Net"
	add_child(net)
	sync = PlayerSync.new()
	sync.name = "Sync"
	add_child(sync)
	sync.net = net
	net.db = ItemDatabase.new()
	print("db loaded: ", net.db.load_from_directory("res://data/"), " items=", net.db._items.size())
	pid = NetSession.load_player_id(_arg(a, "--pid"))
	net.status_changed.connect(func(s : int, d : String) -> void: print("[%s] status=%s %s" % [pid, NetSession.Status.keys()[s], d]))
	net.player_joined.connect(func(id : int, p : String) -> void: print("[%s] joined %d %s" % [pid, id, p]))
	net.player_left.connect(func(id : int, p : String) -> void: print("[%s] left %d %s" % [pid, id, p]))
	net.status_changed.connect(_on_status)
	net.player_joined.connect(_on_joined)
	net.player_left.connect(_on_left)
	net.result_received.connect(_on_result)
	if "--badpv" in a: net.hello_pv = 99
	if "--dropitem" in a: net.db._items.erase(net.db._items.keys()[0])
	if "--gfuzz" in a:
		if "--host" in a:
			net.player_joined.connect(func(_i : int, _p : String) -> void: _gfuzz(), CONNECT_ONE_SHOT)
		else:
			net.nodes_changed.connect(_gfuzz, CONNECT_ONE_SHOT)
	if "--host" in a:
		net.start_host(pid)
	elif "--join" in a:
		net.join_host(_arg(a, "--join", "127.0.0.1"), pid)
	else:
		var lobby : Lobby = Lobby.new()
		add_child(lobby)
		lobby.setup(net, pid)

func _on_status(s : int, _d : String) -> void:
	if s == NetSession.Status.HOSTING:
		var lg : HostLogic = net.logic
		lg.add_node("w1", &"wood_00", 60, Vector2(352, 428))   # กลางระหว่างจุด spawn: ทั้งสองคนเข้าระยะพร้อมกัน (ไว้ทดสอบ race)
		lg.add_node("s1", &"stone_00", 120, Vector2(480, 400))
		lg.add_node("f1", &"fiber_00", 40, Vector2(320, 250))
		net.note_nodes()
		_enter(Vector2(320, 400))
	elif s == NetSession.Status.CONNECTED:
		_enter(Vector2(384, 400))
	else:
		sync.leave_world()

func _enter(spawn : Vector2) -> void:
	sync.enter_world(self, spawn, pid)
	var wf : WorldField = WorldField.new()
	sync.world.add_child(wf)
	sync.world.move_child(wf, 0)   # วาด node ใต้ตัวผู้เล่น
	wf.setup(net, sync.local)

func _on_joined(_id : int, _p : String) -> void:
	sync.broadcast_roster()

func _on_left(_id : int, _p : String) -> void:
	if net.logic != null:
		print("[%s] SUMMARY reqs=%d invariant_fail=%d" % [pid, net.reqs, net.inv_fail])
	sync.broadcast_roster()

func _on_result(res : Dictionary) -> void:
	var r = res.get("result")
	var h : String = "-"
	if net.logic == null and res.has("h"):
		h = "MATCH" if res["h"] == NetSession.state_hash(net.replicas) else "DIVERGE"
	stat["n"] += 1
	if r != null and r["done"] > 0: stat["won"] += 1
	if h == "DIVERGE": stat["diverge"] += 1
	if not quiet:
		print("[%s] result rid=%s acc=%s net=%s reason=%s done=%s hash=%s" % [pid, res["rid"], res["accepted"], res["net_reason"], r["reason"] if r else "-", r["done"] if r else "-", h])

# dev: ยิง gather รัว ๆ ทั้งสองฝั่ง (ห้ามขยับตัวระหว่างทดสอบ ให้อยู่ที่จุด spawn)
func _gfuzz() -> void:
	await get_tree().create_timer(0.5).timeout
	var ids : Array = net.nodes_now().keys() + ["nope"]
	var rng : RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = pid.hash()
	for i in 200:
		net.send_request("gather", &"", 0, ids[rng.randi() % ids.size()], "")
		if i % 5 == 0:
			await get_tree().process_frame
	await get_tree().create_timer(1.5).timeout
	print("[%s] GFUZZ sent=200 results=%d won=%d diverge=%d" % [pid, stat["n"], stat["won"], stat["diverge"]])
