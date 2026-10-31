extends Node
class_name PlayerSync
# Node ต้องชื่อ "Sync" ทั้งสองฝั่ง (RPC หากันด้วย node path)

const SEND_EVERY : float = 0.05
const PLAYER_SCENE : String = "res://scenes/player.tscn"
var net : NetSession
var world : Node2D = null
var local : CharacterBody2D = null
var puppets : Dictionary = {}     # peer id -> Puppet
var roster : Dictionary = {}      # peer id -> player_id
#var positions : Dictionary = {}   # host: peer id -> Vector2 (ไว้ตรวจระยะใน P05-07)
var names_visible : bool = true   # OQ-10-06: เปิดเป็นค่าเริ่มต้น กด N ปิด/เปิด
var _t : float = 0.0

static func make_nameplate(pid : String, shown : bool) -> Label:
	var l : Label = Label.new()
	l.text = pid
	l.position = Vector2(-40, -44)
	l.custom_minimum_size = Vector2(80, 0)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.visible = shown
	l.add_to_group("nameplate")
	return l

func enter_world(parent : Node, spawn : Vector2, pid : String) -> void:
	leave_world()
	world = Node2D.new()
	world.name = "World"
	parent.add_child(world)
	local = (load(PLAYER_SCENE) as PackedScene).instantiate()
	local.position = spawn
	world.add_child(local)
	local.add_child(make_nameplate(pid, names_visible))
	_rebuild()

func leave_world() -> void:
	if world != null:
		world.queue_free()
	world = null
	local = null
	puppets.clear()
	roster.clear()
	#positions.clear()

func _my_id() -> int:
	return multiplayer.get_unique_id() if multiplayer.multiplayer_peer != null else 1

# สร้าง/ลบ puppet ให้ตรงกับ roster (เรียกซ้ำได้ ไม่สร้างซ้ำ)
func _rebuild() -> void:
	if world == null:
		return
	var me : int = _my_id()
	for id in puppets.keys():
		if not roster.has(id) or id == me:
			puppets[id].queue_free()
			puppets.erase(id)
	for id in roster:
		if id != me and not puppets.has(id):
			var p : Puppet = Puppet.new()
			world.add_child(p)
			p.setup(roster[id], names_visible)
			puppets[id] = p

# ---------- host ----------
func broadcast_roster() -> void:
	if net.logic == null:
		return
	roster = net.logic.peers.duplicate()
	_rebuild()
	for id in net.accepted:
		if id != 1:
			cli_roster.rpc_id(id, roster)

static func _ok(v : Vector2, lim : float) -> bool:
	return v.is_finite() and absf(v.x) < lim and absf(v.y) < lim

@rpc("any_peer", "call_remote", "unreliable_ordered")
func srv_pos(pos : Vector2, face : Vector2) -> void:
	if not multiplayer.is_server():
		return
	var id : int = multiplayer.get_remote_sender_id()
	if not net.logic.peers.has(id) or not _ok(pos, 100000.0) or not _ok(face, 1.5):
		return
	net.logic.positions[id] = pos
	if puppets.has(id):
		puppets[id].set_target(pos, face)
	for p in net.accepted:
		if p != 1 and p != id:
			cli_pos.rpc_id(p, id, pos, face)

# ---------- client ----------
@rpc("authority", "call_remote", "reliable")
func cli_roster(r : Dictionary) -> void:
	roster = r
	_rebuild()

@rpc("authority", "call_remote", "unreliable_ordered")
func cli_pos(id : int, pos : Vector2, face : Vector2) -> void:
	if puppets.has(id):
		puppets[id].set_target(pos, face)

# ---------- ทั้งสองฝั่ง ----------
func _physics_process(delta : float) -> void:
	if local == null or net == null:
		return
	_t += delta
	if _t < SEND_EVERY:
		return
	_t = 0.0
	var pos : Vector2 = local.global_position
	var face : Vector2 = local.get_facing()
	if net.status == NetSession.Status.HOSTING:
		net.logic.positions[1] = pos
		for id in net.accepted:
			if id != 1:
				cli_pos.rpc_id(id, 1, pos, face)
	elif net.status == NetSession.Status.CONNECTED:
		srv_pos.rpc_id(1, pos, face)
