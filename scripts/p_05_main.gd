extends Node

const STARTER : Dictionary = {&"floor_00": 20, &"wall_00": 20, &"workbench_00": 2, &"chest_00": 2, &"stone_00": 50}   # test-only
var sync : PlayerSync
var net : NetSession
var pid : String = ""
var quiet : bool = false
var wf : WorldField
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
	elif "--forge" in a: fz = _forge
	elif "--dc" in a: fz = _dc
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
	wf = WorldField.new()
	sync.world.add_child(wf)
	sync.world.move_child(wf, 0)
	wf.setup(net, sync.local)
	var bf : BuildField = BuildField.new()
	sync.world.add_child(bf)
	sync.world.move_child(bf, 1)
	bf.setup(net, sync.local, wf)

func _on_joined(_id : int, p : String) -> void:
	sync.broadcast_roster()
	if is_instance_valid(wf): wf.notice("%s เข้าร่วมแล้ว" % p)

func _on_left(_id : int, p : String) -> void:
	if net.logic != null:
		var iv : Inventory = net.logic.invs.get(p)
		print("[%s] SUMMARY left=%s reqs=%d invariant_fail=%d conserved=%s inv_hash=%s grid_hash=%s" % [pid, p, net.reqs, net.inv_fail, net.logic.conserved(), NetSession.state_hash({p: iv}) if iv != null else "-", NetSession.grid_hash(net.logic.grid.to_dict())])
	sync.broadcast_roster()
	if is_instance_valid(wf): wf.notice("%s ออกจากเกม" % p)

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

func _c(label : String, op : String, item : String, qty : Variant, src : String, dst : String, kind : String, exp : String, pv : int = 1) -> Dictionary:
	return {"label": label, "pv": pv, "op": op, "item": item, "qty": qty, "src": src, "dst": dst, "kind": kind, "exp": exp}

# dev: client ส่งคำขอปลอมตรง ๆ (ห้ามขยับตัว ให้อยู่จุด spawn) ทีละคำขอ รอผลก่อนส่งถัดไป
func _forge() -> void:
	await get_tree().create_timer(0.5).timeout
	var other : String = ""
	var w : int = 0
	while other == "" and w < 300:
		for id in sync.roster:
			if sync.roster[id] != pid: other = sync.roster[id]
		w += 1
		await get_tree().process_frame
	var cases : Array = [
		_c("client add", "add", "wood_00", 5, "", pid, "net", "add_disabled"),
		_c("remove จากคนอื่น", "remove", "wood_00", 1, other, "", "net", "denied"),
		_c("transfer ต้นทางคนอื่น", "transfer", "stone_00", 1, other, pid, "net", "denied"),
		_c("transfer ไปคนอื่น (D-22)", "transfer", "stone_00", 1, pid, other, "net", "player_transfer_denied"),
		_c("qty เป็น float", "remove", "stone_00", 1.0, pid, "", "net", "bad_request"),
		_c("qty ติดลบ", "remove", "stone_00", -5, pid, "", "res", "invalid_quantity"),
		_c("item ปลอม", "remove", "nope_item", 1, pid, "", "res", "unknown_item"),
		_c("cell เสีย", "place", "wall_00", 0, "x,y", "", "net", "bad_request"),
		_c("cell ใหญ่เกิน", "place", "wall_00", 0, "99999999999,3", "", "net", "bad_request"),
		_c("rot ผิด", "place", "wall_00", 7, "6,6", "", "res", "bad_rotation"),
		_c("protocol ผิด", "remove", "stone_00", 1, pid, "", "net", "bad_protocol", 99),
		_c("op ปลอม", "teleport", "", 0, "", "", "net", "bad_op"),
		_c("node ไกลเกิน", "gather", "", 0, "f1", "", "net", "too_far"),
		_c("node ไม่มี", "gather", "", 0, "nope", "", "net", "no_node"),
		_c("chest ปลอม", "transfer", "stone_00", 1, pid, "chest_999", "net", "denied"),
		_c("gather ปลอม item/qty", "gather", "stone_00", 999999, "w1", "", "res", "ok"),
	]
	var rid : int = 1000
	var pass_n : int = 0
	var fail_n : int = 0
	for c in cases:
		rid += 1
		net.send_raw({"pv": c["pv"], "rid": rid, "op": c["op"], "item": c["item"], "qty": c["qty"], "src": c["src"], "dst": c["dst"]})
		var r : Dictionary = await net.result_received
		var got : String = str(r["net_reason"])
		if c["kind"] == "res":
			got = str(r["result"]["reason"]) if r["result"] != null else "REJECTED:" + got
		if got == c["exp"]:
			pass_n += 1
		else:
			fail_n += 1
			print("[%s] FORGE FAIL %s: got=%s expected=%s" % [pid, c["label"], got, c["exp"]])
	rid += 1
	var d : Dictionary = {"pv": 1, "rid": rid, "op": "remove", "item": "wood_00", "qty": 0, "src": pid, "dst": ""}
	net.send_raw(d)
	await net.result_received
	net.send_raw(d)
	var r2 : Dictionary = await net.result_received
	if str(r2["net_reason"]) == "duplicate_request": pass_n += 1
	else:
		fail_n += 1
		print("[%s] FORGE FAIL rid ซ้ำ: got=%s" % [pid, r2["net_reason"]])
	var inv : Inventory = net.my_inv()
	if inv.count_of(&"wood_00") == 60 and inv.count_of(&"stone_00") == 50: pass_n += 1
	else:
		fail_n += 1
		print("[%s] FORGE FAIL ของหลัง gather ปลอม wood=%d stone=%d" % [pid, inv.count_of(&"wood_00"), inv.count_of(&"stone_00")])
	print("[%s] FORGE checks=%d pass=%d fail=%d" % [pid, pass_n + fail_n, pass_n, fail_n])

# dev: ยิงคำขอรัว ๆ แล้วตัดการเชื่อมกลางทาง จากนั้น rejoin ด้วย pid เดิมในโปรเซสเดียว
func _dc() -> void:
	await get_tree().create_timer(0.5).timeout
	var rng : RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = pid.hash()
	var ids : Array = net.nodes_now().keys()
	var pieces : Array = [&"floor_00", &"wall_00", &"workbench_00", &"chest_00"]
	for i in 40:
		var cell : String = "%d,%d" % [rng.randi_range(9, 13), rng.randi_range(11, 13)]
		var k : int = rng.randi() % 3
		if k == 0: net.send_request("place", pieces[rng.randi() % 4], 0, cell, "")
		elif k == 1: net.send_request("gather", &"", 0, ids[rng.randi() % ids.size()], "")
		else: net.send_request("demolish", &"", 0, cell, "")
	for i in 3:
		await get_tree().process_frame
	net.reset()   # ตัดกลาง op
	await get_tree().create_timer(1.0).timeout
	net.join_host("127.0.0.1", pid)
	var w : int = 0
	while net.status != NetSession.Status.CONNECTED and w < 600:
		w += 1
		await get_tree().process_frame
	await get_tree().create_timer(0.5).timeout
	var inv : Inventory = net.my_inv()
	print("[%s] DC rejoin inv_hash=%s grid_hash=%s" % [pid, NetSession.state_hash({pid: inv}) if inv != null else "-", NetSession.grid_hash(net.grid_view.to_dict())])
