extends Node2D
class_name BuildField

const REASONS : Dictionary = {
	"ok": "สำเร็จ", "out_of_bounds": "ออกนอกพื้นที่", "overlap": "มีของวางทับอยู่",
	"cannot_rotate": "ชิ้นนี้หมุนไม่ได้", "not_enough_quantity": "ไม่มีชิ้นนี้ในกระเป๋า",
	"no_structure": "ไม่มีอะไรให้รื้อ", "chest_not_empty": "หีบยังมีของ เอาออกก่อน",
	"inventory_full": "กระเป๋าเต็ม รื้อไม่ได้", "too_far": "ไกลเกินไป",
	"player_transfer_denied": "โอนให้ผู้เล่นอื่นโดยตรงไม่ได้ ใช้หีบ", "denied": "ทำไม่ได้",
	"destination_full": "ปลายทางเต็ม", "partial_full": "ย้ายได้ไม่ครบ",
	"duplicate_request": "คำขอซ้ำ", "bad_rotation": "หมุนไม่ถูกต้อง",
}
const CAT_COLORS : Array = [Color(0.55, 0.45, 0.3), Color(0.5, 0.5, 0.55), Color(0.3, 0.5, 0.8), Color(0.8, 0.6, 0.2)]
var net : NetSession
var local : CharacterBody2D
var wf : WorldField
var build_mode : bool = false
var sel_id : StringName = &""
var rot : int = 0
var status : Label
var hint : Label
var msg : Label
var chest_panel : VBoxContainer
var chest_title : Label
var chest_view : DragInventoryView
var player_view : DragInventoryView
var _cell : Vector2i = Vector2i.ZERO
var _ghost : Dictionary = {}
var _target : Dictionary = {}
var _open_sid : String = ""
var _mine : Dictionary = {}

func setup(n : NetSession, player : CharacterBody2D, field : WorldField) -> void:
	net = n
	local = player
	wf = field
	var layer : CanvasLayer = CanvasLayer.new()
	add_child(layer)
	var panel : VBoxContainer = VBoxContainer.new()
	panel.position = Vector2(680, 10)
	layer.add_child(panel)
	status = Label.new()
	panel.add_child(status)
	hint = Label.new()
	panel.add_child(hint)
	msg = Label.new()
	panel.add_child(msg)
	chest_panel = VBoxContainer.new()
	chest_panel.position = Vector2(680, 110)
	chest_panel.visible = false
	layer.add_child(chest_panel)
	chest_title = Label.new()
	chest_panel.add_child(chest_title)
	chest_view = DragInventoryView.new()
	chest_view.slot_dropped.connect(_on_drop)
	chest_panel.add_child(chest_view)
	var pl : Label = Label.new()
	pl.text = "กระเป๋าผู้เล่น"
	chest_panel.add_child(pl)
	player_view = DragInventoryView.new()
	player_view.slot_dropped.connect(_on_drop)
	chest_panel.add_child(player_view)
	net.result_received.connect(_on_result)
	net.inventories_changed.connect(_rebind)
	net.grid_changed.connect(_rebind)
	_set_mode(false)

func _set_mode(v : bool) -> void:
	build_mode = v
	if v:
		_close_chest()
	status.text = "BUILD | 1-9 เลือกชิ้น ซ้าย=วาง ขวา=รื้อ R=หมุน B=ออก" if v else "B สร้าง | E เก็บ/เปิดหีบ | N ซ่อนชื่อ"
	queue_redraw()

func _pieces() -> Array:
	var out : Array = []
	var inv : Inventory = net.my_inv()
	if inv == null:
		return out
	var seen : Dictionary = {}
	for s in inv.slots:
		if s != null and s.item_data is BuildingPieceData and s.quantity > 0 and not seen.has(s.item_data.id):
			seen[s.item_data.id] = true
			out.append(s.item_data)
	out.sort_custom(func(a, b): return String(a.id) < String(b.id))
	return out

func _chest_center(sid : String) -> Vector2:
	var s : Dictionary = net.grid_now().get_struct(int(sid.substr(6)))
	if s.is_empty():
		return Vector2.ZERO
	return HostLogic.piece_center(net.db.get_item(StringName(s["piece"])) as BuildingPieceData, s["cell"], s["rot"])

func _chest_cands() -> Array:
	var out : Array = []
	var g : BuildGrid = net.grid_now()
	for s in g.all_structs():
		var sid : String = BuildGrid.storage_id(s["uid"])
		if g.chest(sid) != null:
			out.append({"kind": InteractPick.KIND_INTERACT, "pos": _chest_center(sid), "ref": sid})
	return out

func _process(_d : float) -> void:
	if net == null or local == null or net.my_inv() == null:
		return
	if sel_id != &"" and net.my_inv().count_of(sel_id) < 1:
		sel_id = &""
	if build_mode:
		_cell = BuildConst.world_to_cell(get_global_mouse_position())
		_ghost = net.grid_now().check(net.db, sel_id, _cell, rot) if sel_id != &"" else {}
		var names : PackedStringArray = []
		var ps : Array = _pieces()
		for i in ps.size():
			names.append("%s%d %s x%d" % ["> " if ps[i].id == sel_id else "", i + 1, ps[i].display_name, net.my_inv().count_of(ps[i].id)])
		var v : String = "เลือกชิ้นก่อน" if _ghost.is_empty() else ("วางได้" if _ghost["ok"] else "วางไม่ได้: " + str(REASONS.get(str(_ghost["reason"]), _ghost["reason"])))
		hint.text = "  ".join(names) + "\n" + v
		_target = {}
	else:
		hint.text = ""
		_target = InteractPick.pick(local.global_position, local.get_facing(), _chest_cands())
		if _open_sid != "" and (net.grid_now().chest(_open_sid) == null or local.global_position.distance_to(_chest_center(_open_sid)) > InteractPick.RANGE * 1.5):
			_close_chest()
	queue_redraw()

func _send(op : String, item : StringName, qty : int, src : String, dst : String) -> void:
	_mine[net.next_rid()] = true
	net.send_request(op, item, qty, src, dst)

func _on_result(res : Dictionary) -> void:
	if not _mine.erase(res["rid"]):
		return
	var why : String = String(res["net_reason"]) if not res["accepted"] else String(res["result"]["reason"])
	msg.text = str(REASONS.get(why, why))

func _unhandled_input(e : InputEvent) -> void:
	if net == null or local == null:
		return
	if e is InputEventKey and e.pressed and not e.echo:
		if e.keycode == KEY_B:
			_set_mode(not build_mode)
		elif e.keycode == KEY_ESCAPE:
			_close_chest()
		elif e.keycode == KEY_E and not build_mode and wf._target.is_empty() and not _target.is_empty():
			_open(_target["ref"])
		elif build_mode and e.keycode == KEY_R:
			var p : BuildingPieceData = net.db.get_item(sel_id) as BuildingPieceData
			if p != null and p.can_be_rotated:
				rot = (rot + 1) % 4
			else:
				msg.text = "ชิ้นนี้หมุนไม่ได้"
		elif build_mode and e.keycode >= KEY_1 and e.keycode <= KEY_9:
			var ps : Array = _pieces()
			var i : int = e.keycode - KEY_1
			if i < ps.size():
				sel_id = ps[i].id
				rot = 0
	elif e is InputEventMouseButton and e.pressed and build_mode:
		var cs : String = "%d,%d" % [_cell.x, _cell.y]
		if e.button_index == MOUSE_BUTTON_LEFT:
			if sel_id == &"":
				msg.text = "เลือกชิ้นก่อน"
			else:
				_send("place", sel_id, rot, cs, "")
		elif e.button_index == MOUSE_BUTTON_RIGHT:
			_send("demolish", &"", 0, cs, "")

func _open(sid : String) -> void:
	_open_sid = sid
	chest_title.text = "หีบ: " + sid
	chest_panel.visible = true
	_rebind()

func _close_chest() -> void:
	_open_sid = ""
	if chest_panel != null:
		chest_panel.visible = false

func _rebind() -> void:
	if _open_sid == "":
		return
	var c : Inventory = net.grid_now().chest(_open_sid)
	if c == null:
		_close_chest()
		return
	chest_view.bind(c)
	player_view.bind(net.my_inv())

func _on_drop(src_inv : Inventory, si : int, dst_inv : Inventory, _di : int) -> void:
	if src_inv == dst_inv:
		msg.text = "จัดช่องภายในกระเป๋าเดียวกันยังไม่รองรับใน co-op"
		return
	if si >= src_inv.slots.size() or src_inv.slots[si].item_data == null:
		return
	var s : InventorySlot = src_inv.slots[si]
	_send("transfer", s.item_data.id, s.quantity, src_inv.owner_id, dst_inv.owner_id)

func _rect(cell : Vector2i, fp : Vector2i) -> Rect2:
	return Rect2(BuildConst.cell_to_world(cell), Vector2(fp * BuildConst.CELL_SIZE))

func _draw() -> void:
	if net == null:
		return
	var g : BuildGrid = net.grid_now()
	var sz : Vector2 = Vector2(g.size * BuildConst.CELL_SIZE)
	var a : float = 0.25 if build_mode else 0.08
	for x in range(g.size.x + 1):
		draw_line(Vector2(x * BuildConst.CELL_SIZE, 0), Vector2(x * BuildConst.CELL_SIZE, sz.y), Color(1, 1, 1, a))
	for y in range(g.size.y + 1):
		draw_line(Vector2(0, y * BuildConst.CELL_SIZE), Vector2(sz.x, y * BuildConst.CELL_SIZE), Color(1, 1, 1, a))
	var items : Array = g.all_structs()
	for layer in [BuildGrid.LAYER_FLOOR, BuildGrid.LAYER_OBJECT]:
		for s in items:
			var p : BuildingPieceData = net.db.get_item(StringName(s["piece"])) as BuildingPieceData
			if p == null or BuildGrid.layer_of(p) != layer:
				continue
			var r : Rect2 = _rect(s["cell"], BuildGrid.footprint(p, s["rot"]))
			draw_rect(r, CAT_COLORS[p.category])
			draw_rect(r, Color.BLACK, false, 1.0)
			draw_string(ThemeDB.fallback_font, r.position + Vector2(4, 14), p.display_name.left(1), HORIZONTAL_ALIGNMENT_LEFT, -1, 12)
	if build_mode and not _ghost.is_empty():
		var gp : BuildingPieceData = net.db.get_item(sel_id) as BuildingPieceData
		var gr : Rect2 = _rect(_cell, BuildGrid.footprint(gp, rot))
		var col : Color = Color(0.2, 1, 0.3) if _ghost["ok"] else Color(1, 0.2, 0.2)
		draw_rect(gr, Color(col, 0.4))
		draw_rect(gr, col, false, 2.0)
		if not _ghost["ok"]:   # กากบาท: ไม่พึ่งสีอย่างเดียว
			draw_line(gr.position, gr.end, col, 2.0)
			draw_line(Vector2(gr.position.x, gr.end.y), Vector2(gr.end.x, gr.position.y), col, 2.0)
	if not build_mode and not _target.is_empty():
		draw_arc(_target["pos"], 18.0, 0, TAU, 24, Color(1, 1, 0), 2.0)
