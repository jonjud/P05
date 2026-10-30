extends Node

func _arg(a : PackedStringArray, key : String, def : String = "") -> String:
	var i : int = a.find(key)
	if i < 0 or i + 1 >= a.size() or a[i + 1].begins_with("--"):
		return def
	return a[i + 1]

func _ready() -> void:
	var a : PackedStringArray = OS.get_cmdline_user_args()
	var net : NetSession = NetSession.new()
	net.name = "Net"
	add_child(net)
	net.db = ItemDatabase.new()
	print("db loaded: ", net.db.load_from_directory("res://data/"), " items=", net.db._items.size())
	var pid : String = NetSession.load_player_id(_arg(a, "--pid"))
	net.status_changed.connect(func(s : int, d : String) -> void: print("[%s] status=%s %s" % [pid, NetSession.Status.keys()[s], d]))
	net.player_joined.connect(func(id : int, p : String) -> void: print("[%s] joined %d %s" % [pid, id, p]))
	net.player_left.connect(func(id : int, p : String) -> void: print("[%s] left %d %s" % [pid, id, p]))
	if "--badpv" in a: net.hello_pv = 99
	if "--dropitem" in a: net.db._items.erase(net.db._items.keys()[0])
	if "--host" in a:
		net.start_host(pid)
	elif "--join" in a:
		net.join_host(_arg(a, "--join", "127.0.0.1"), pid)
	else:
		var lobby : Lobby = Lobby.new()
		add_child(lobby)
		lobby.setup(net, pid)
	#InventoryTests.new().run_all()
	#BuildGridTests.new().run_all()
	#InteractPickTests.new().run_all()
