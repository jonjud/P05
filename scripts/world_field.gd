extends Node2D
class_name WorldField

const MSG : Dictionary = {
	"ok": "เก็บแล้ว", "no_node": "มีคนเก็บไปแล้ว", "too_far": "ไกลเกินไป",
	"full": "กระเป๋าเต็ม", "partial_full": "เก็บได้ไม่ครบ กระเป๋าเต็ม",
	"not_joined": "ยังไม่ได้เข้า session", "duplicate_request": "คำขอซ้ำ",
}
var net : NetSession
var local : CharacterBody2D
var hud : Label
var msg : String = ""
var _target : Dictionary = {}
var _mine : Dictionary = {}

func setup(n : NetSession, player : CharacterBody2D) -> void:
	net = n
	local = player
	var layer : CanvasLayer = CanvasLayer.new()
	add_child(layer)
	hud = Label.new()
	hud.position = Vector2(10, 10)
	layer.add_child(hud)
	net.result_received.connect(_on_result)

func _on_result(res : Dictionary) -> void:
	if not _mine.erase(res["rid"]):
		return
	var why : String = String(res["net_reason"]) if not res["accepted"] else String(res["result"]["reason"])
	msg = str(MSG.get(why, why))

func _process(_d : float) -> void:
	var nv : Dictionary = net.nodes_now()
	var c : Array = []
	for id in nv:
		c.append({"kind": InteractPick.KIND_INTERACT, "pos": nv[id]["pos"], "ref": id})
	_target = InteractPick.pick(local.global_position, local.get_facing(), c)
	var t : Dictionary = {}
	var inv : Inventory = net.my_inv()
	if inv != null:
		for s in inv.slots:
			if s != null and s.item_data != null and s.quantity > 0:
				t[s.item_data.display_name] = t.get(s.item_data.display_name, 0) + s.quantity
	var parts : PackedStringArray = []
	for k in t: parts.append("%s x%d" % [k, t[k]])
	var prompt : String = ""
	if not _target.is_empty():
		var n : Dictionary = nv[_target["ref"]]
		var it : ItemData = net.db.get_item(StringName(n["item"]))
		prompt = "E: เก็บ %s x%d" % [it.display_name if it != null else n["item"], n["amount"]]
	hud.text = "กระเป๋า: %s\n%s\n%s" % [", ".join(parts) if not parts.is_empty() else "ว่าง", msg, prompt]
	queue_redraw()

func _unhandled_input(e : InputEvent) -> void:
	if e is InputEventKey and e.pressed and not e.echo and e.keycode == KEY_E and not _target.is_empty():
		_mine[net.next_rid()] = true
		net.send_request("gather", &"", 0, _target["ref"], "")

func _draw() -> void:
	var nv : Dictionary = net.nodes_now()
	for id in nv:
		var n : Dictionary = nv[id]
		var col : Color = Color(0.3, 0.7, 0.3)
		if "wood" in n["item"]: col = Color(0.55, 0.35, 0.15)
		elif "stone" in n["item"]: col = Color(0.6, 0.6, 0.65)
		draw_rect(Rect2(n["pos"] - Vector2(14, 14), Vector2(28, 28)), col)
		draw_string(ThemeDB.fallback_font, n["pos"] + Vector2(-14, 28), str(n["amount"]), HORIZONTAL_ALIGNMENT_LEFT, -1, 12)
	if not _target.is_empty():
		draw_arc(_target["pos"], 22.0, 0, TAU, 24, Color(1, 1, 0), 2.0)

func notice(t : String) -> void:
	msg = t
