extends Node

const STARTER : Dictionary = {&"floor_00": 20, &"wall_00": 20, &"workbench_00": 2, &"chest_00": 2, &"stone_00": 50}   # test-only
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
	net.starter = STARTER
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
	var fz : Callable = Callable()
	if "--gfuzz" in a: fz = _gfuzz
	elif "--bfuzz" in a: fz = _bfuzz
	if fz.is_valid():
		if "--host" in a:
			net.player_joined.connect(func(_i : int, _p : String) -> void: fz.call(), CONNECT_ONE_SHOT)
		else:
			net.nodes_changed.connect(fz, CONNECT_ONE_SHOT)
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
		lg.add_node("w1", &"wood_00", 60, Vector2(352, 428))
		lg.add_node("s1", &"stone_00", 120, Vector2(480, 400))
		lg.add_node("f1", &"fiber_00", 40, Vector2(320, 250))
		_enter(Vector2(320, 400))
	elif s == NetSession.Status.CONNECTED:
		_enter(Vector2(384, 400))
	else:
		sync.leave_world()

func _enter(spawn : Vector2) -> void:
	sync.enter_world(self, spawn, pid)
	var wf : WorldField = WorldField.new()
	sync.world.add_child(wf)
	sync.world.move_child(wf, 0)
	wf.setup(net, sync.local)
	var bf : BuildField = BuildField.new()
	sync.world.add_child(bf)
	sync.world.move_child(bf, 1)   # วาดใต้ตัวผู้เล่น
	bf.setup(net, sync.local, wf)

func _on_joined(_id : int, _p : String) -> void:
	sync.broadcast_roster()

func _on_left(_id : int, _p : String) -> void:
	if net.logic != null:
		print("[%s] SUMMARY reqs=%d invariant_fail=%d" % [pid, net.reqs, net.inv_fail])
	sync.broadcast_roster()

func _on_result(res : Dictionary) -> void:
	var r = res.get("result")
	var h : String = "-"
	var g : String = "-"
	if net.logic == null and res.has("h"):
		h = "MATCH" if res["h"] == NetSession.state_hash(net.replicas) else "DIVERGE"
		g = "MATCH" if res["g"] == NetSession.grid_hash(net.grid_view.to_dict()) else "DIVERGE"
	stat["n"] += 1
	if r != null and r["done"] > 0: stat["won"] += 1
	if h == "DIVERGE" or g == "DIVERGE": stat["diverge"] += 1
	if not quiet:
		print("[%s] result rid=%s acc=%s net=%s reason=%s done=%s hash=%s grid=%s" % [pid, res["rid"], res["accepted"], res["net_reason"], r["reason"] if r else "-", r["done"] if r else "-", h, g])

# dev: gather รัว ๆ (ห้ามขยับตัว ให้อยู่จุด spawn)
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

# dev: วาง/รื้อ/ฝาก/หยิบ chest รัว ๆ บนบริเวณเดียวกันทั้งสองฝั่ง (ห้ามขยับตัว)
func _bfuzz() -> void:
	await get_tree().create_timer(0.5).timeout
	var rng : RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = pid.hash()
	var pieces : Array = [&"floor_00", &"wall_00", &"workbench_00", &"chest_00"]
	for i in 300:
		var cell : String = "%d,%d" % [rng.randi_range(9, 13), rng.randi_range(11, 13)]
		var k : int = rng.randi() % 5
		if k <= 1:
			net.send_request("place", pieces[rng.randi() % 4], 0, cell, "")
		elif k == 2:
			net.send_request("demolish", &"", 0, cell, "")
		else:
			var cids : Array = net.grid_now().chest_ids()
			if not cids.is_empty():
				var c : String = cids[rng.randi() % cids.size()]
				var q : int = rng.randi_range(1, 30)
				if rng.randi() % 2 == 0:
					net.send_request("transfer", &"stone_00", q, pid, c)
				else:
					net.send_request("transfer", &"stone_00", q, c, pid)
		if i % 5 == 0:
			await get_tree().process_frame
	var sent : int = net.next_rid() - 1
	var w : int = 0
	while stat["n"] < sent and w < 1800:   # รอผลกลับครบ สูงสุดราว 30 วินาที
		w += 1
		await get_tree().process_frame
	print("[%s] BFUZZ sent=%d results=%d pending=%d won=%d diverge=%d frames=%d" % [pid, sent, stat["n"], sent - stat["n"], stat["won"], stat["diverge"], w])
