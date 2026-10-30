extends Node2D
# UI ไม่ถือ state ของโครงสร้าง/ของ: อยู่ใน BuildGrid กับ Inventory ทั้งหมด

const REASONS : Dictionary = {
	BuildGrid.OK: "วางแล้ว",
	BuildGrid.OUT_OF_BOUNDS: "ออกนอกพื้นที่",
	BuildGrid.OVERLAP: "มีของวางทับอยู่",
	BuildGrid.CANNOT_ROTATE: "ชิ้นนี้หมุนไม่ได้",
	BuildGrid.NOT_ENOUGH: "ไม่มีชิ้นนี้ในกระเป๋า",
	BuildGrid.NO_STRUCTURE: "ไม่มีอะไรให้รื้อ",
	BuildGrid.CHEST_NOT_EMPTY: "หีบยังมีของ เอาออกก่อน",
	BuildGrid.INVENTORY_FULL: "กระเป๋าเต็ม รื้อไม่ได้",
}
const CAT_COLORS : Array = [Color(0.55, 0.45, 0.3), Color(0.5, 0.5, 0.55), Color(0.3, 0.5, 0.8), Color(0.8, 0.6, 0.2)]
const CAT_NAMES : Array = ["พื้น", "ผนัง", "สถานี", "หีบ"]   # ลำดับต้องตรง BuildingCategory

var db : ItemDatabase = ItemDatabase.new()
var inv : Inventory = Inventory.new()
var grid : BuildGrid = BuildGrid.new()
var build_mode : bool = false
var cat : int = 0
var sel_id : StringName = &""
var rot : int = 0
var _cell : Vector2i = Vector2i.ZERO
var _ghost : Dictionary = {}
var status : Label
var cat_bar : HBoxContainer
var piece_grid : GridContainer
var hint : Label
var msg : Label
var chest_panel : VBoxContainer
var chest_title : Label
var chest_view : DragInventoryView
var player_view : DragInventoryView
var total_lbl : Label
var player : CharacterBody2D
var prompt : Label
var _target : Dictionary = {}
var _open_pos : Vector2 = Vector2.ZERO

const MOVE_MSG : Dictionary = {
	OpResult.OK: "ย้ายแล้ว",
	OpResult.PARTIAL_FULL: "ย้ายได้ไม่ครบ ช่องเต็ม",
	OpResult.DESTINATION_FULL: "ปลายทางเต็ม ย้ายไม่ได้",
	OpResult.EMPTY_SOURCE: "ช่องนี้ไม่มีของ",
	OpResult.SAME_INDEX: "ช่องเดิม",
	OpResult.NOT_ENOUGH: "ของไม่พอ",
}
var _open_chest : Inventory = null


func _ready() -> void:
	_ensure_actions()
	db.load_from_directory("res://data/")
	for e in [[&"floor_00", 20], [&"wall_00", 20], [&"workbench_00", 2], [&"chest_00", 2], [&"stone_00", 50]]:
		inv.add_to_existing_stacks(db, e[0], e[1])
	inv.inventory_changed.connect(_refresh_pieces)
	player = (load("res://scenes/player.tscn") as PackedScene).instantiate()
	player.position = Vector2(320, 400)
	add_child(player)
	player.inv = inv      # ตั้งหลัง add_child เพราะ _ready ของ player สร้าง inv/db ของตัวเองไว้ก่อน
	player.db = db
	player.pickup_done.connect(_on_pickup_done)
	for p in [[&"wood_00", 30, Vector2(160, 400)], [&"fiber_00", 120, Vector2(480, 400)]]:
		var pk : Pickup = (load("res://scenes/pickup.tscn") as PackedScene).instantiate()
		pk.item_id = p[0]
		pk.amount = p[1]
		pk.position = p[2]
		pk.add_to_group("pickup")
		add_child(pk)
	_build_ui()
	_set_mode(false)

func _ensure_actions() -> void:
	var keys : Dictionary = {"move_left": KEY_A, "move_right": KEY_D, "move_up": KEY_W, "move_down": KEY_S}
	for a in keys:
		if not InputMap.has_action(a):
			InputMap.add_action(a)
			var ev : InputEventKey = InputEventKey.new()
			ev.physical_keycode = keys[a]
			InputMap.action_add_event(a, ev)

func _build_ui() -> void:
	var layer : CanvasLayer = CanvasLayer.new()
	add_child(layer)
	var panel : VBoxContainer = VBoxContainer.new()
	panel.position = Vector2(680, 10)
	panel.custom_minimum_size = Vector2(380, 0)
	layer.add_child(panel)
	status = Label.new()
	panel.add_child(status)
	cat_bar = HBoxContainer.new()
	panel.add_child(cat_bar)
	for i in CAT_NAMES.size():
		var b : Button = Button.new()
		b.text = CAT_NAMES[i]
		b.pressed.connect(_set_cat.bind(i))
		cat_bar.add_child(b)
	piece_grid = GridContainer.new()
	piece_grid.columns = 2
	panel.add_child(piece_grid)
	hint = Label.new()
	panel.add_child(hint)
	msg = Label.new()
	panel.add_child(msg)
	chest_panel = VBoxContainer.new()
	chest_panel.position = Vector2(680, 50)
	chest_panel.visible = false
	layer.add_child(chest_panel)
	chest_title = Label.new()
	chest_panel.add_child(chest_title)
	chest_view = DragInventoryView.new()
	chest_view.slot_dropped.connect(_on_slot_dropped)
	chest_panel.add_child(chest_view)
	var pl : Label = Label.new()
	pl.text = "กระเป๋าผู้เล่น"
	chest_panel.add_child(pl)
	player_view = DragInventoryView.new()
	player_view.slot_dropped.connect(_on_slot_dropped)
	chest_panel.add_child(player_view)
	total_lbl = Label.new()
	chest_panel.add_child(total_lbl)
	prompt = Label.new()
	prompt.position = Vector2(10, 500)
	layer.add_child(prompt)

func _set_mode(v : bool) -> void:
	build_mode = v
	if v:
		_close_chest()
	cat_bar.visible = v
	piece_grid.visible = v
	hint.visible = v
	status.text = "BUILD MODE | ซ้าย=วาง ขวา=รื้อ R=หมุน B=ออก" if v else "WASD เดิน | E โต้ตอบ | B สร้าง | Esc ปิดหีบ"
	_refresh_pieces()
	queue_redraw()

func _set_cat(i : int) -> void:
	cat = i
	sel_id = &""
	rot = 0
	_refresh_pieces()

func _select(id : StringName) -> void:
	sel_id = id
	rot = 0
	_refresh_pieces()

# แสดงเฉพาะชิ้นที่มีใน Inventory จริง ตามหมวดที่เลือก
func _refresh_pieces() -> void:
	for c in piece_grid.get_children():
		piece_grid.remove_child(c)
		c.queue_free()
	var seen : Dictionary = {}
	for s in inv.slots:
		if s == null or s.item_data == null or s.quantity <= 0 or not (s.item_data is BuildingPieceData):
			continue
		var p : BuildingPieceData = s.item_data
		if p.category != cat or seen.has(p.id):
			continue
		seen[p.id] = true
		var b : Button = Button.new()
		b.text = "%s%s x%d" % ["> " if p.id == sel_id else "", p.display_name, inv.count_of(p.id)]
		b.pressed.connect(_select.bind(p.id))
		piece_grid.add_child(b)

func _show(reason : StringName) -> void:
	msg.text = REASONS.get(reason, String(reason))

func _rotate() -> void:
	var p : BuildingPieceData = db.get_item(sel_id) as BuildingPieceData
	if p == null:
		return
	if p.can_be_rotated:
		rot = (rot + 1) % 4
	else:
		_show(BuildGrid.CANNOT_ROTATE)

func _place() -> void:
	if sel_id == &"":
		msg.text = "เลือกชิ้นส่วนก่อน"
		return
	var r : Dictionary = grid.place(db, inv, sel_id, _cell, rot)
	_show(r["reason"])
	if r["done"] > 0 and inv.count_of(sel_id) < 1:
		sel_id = &""
		_refresh_pieces()

func _remove() -> void:
	_show(grid.remove_at(db, inv, _cell)["reason"])

func _unhandled_input(e : InputEvent) -> void:
	if e is InputEventKey and e.pressed and not e.echo:
		if e.keycode == KEY_B:
			_set_mode(not build_mode)
		elif e.keycode == KEY_ESCAPE:
			_close_chest()
		elif e.keycode == KEY_E and not build_mode:
			_interact()
		elif build_mode and e.keycode == KEY_R:
			_rotate()
	elif e is InputEventMouseButton and e.pressed and build_mode:
		if e.button_index == MOUSE_BUTTON_LEFT:
			_place()
		elif e.button_index == MOUSE_BUTTON_RIGHT:
			_remove()

func _open_chest_by_id(sid : String, pos : Vector2) -> void:
	_open_chest = grid.chest(sid)
	if _open_chest == null:
		return
	_open_pos = pos
	chest_title.text = "หีบ: " + sid
	chest_view.bind(_open_chest)
	player_view.bind(inv)
	chest_panel.visible = true
	_update_total()
	msg.text = ""

const PICK_MSG : Dictionary = {
	OpResult.OK: "เก็บแล้ว",
	OpResult.PARTIAL_FULL: "เก็บได้ไม่ครบ กระเป๋าเต็ม",
	OpResult.FULL: "กระเป๋าเต็ม",
}

func _close_chest() -> void:
	_open_chest = null
	chest_panel.visible = false

func _on_slot_dropped(src : Inventory, si : int, dst : Inventory, di : int) -> void:
	var r : Dictionary
	if src == dst:
		r = src.move_slots(si, di)
	else:
		if si >= src.slots.size() or src.slots[si].item_data == null:
			msg.text = MOVE_MSG[OpResult.EMPTY_SOURCE]
			return
		var s : InventorySlot = src.slots[si]
		r = src.transfer_to(dst, db, s.item_data.id, s.quantity)
	msg.text = MOVE_MSG.get(r["reason"], "ทำไม่ได้: " + String(r["reason"]))
	_update_total()

# แสดงผลรวมหิน (กระเป๋า + ทุกหีบ) ต้องคงที่ = 50 ตลอด
func _update_total() -> void:
	total_lbl.text = "รวมหิน (กระเป๋า+หีบ): %d" % (inv.count_of(&"stone_00") + grid.count_in_chests(&"stone_00"))


func _process(_d : float) -> void:
	if build_mode:
		_cell = BuildConst.world_to_cell(get_global_mouse_position())
		_ghost = grid.check(db, sel_id, _cell, rot) if sel_id != &"" else {}
		if _ghost.is_empty():
			hint.text = "เลือกชิ้นส่วนจากแถบด้านบน"
		else:
			hint.text = "วางได้" if _ghost["ok"] else "วางไม่ได้: " + REASONS.get(_ghost["reason"], String(_ghost["reason"]))
		_target = {}
	else:
		_target = InteractPick.pick(player.global_position, player.get_facing(), _candidates())
		if _open_chest != null and player.global_position.distance_to(_open_pos) > InteractPick.RANGE * 1.5:
			_close_chest()
	prompt.text = _prompt_text(_target)
	queue_redraw()

func _on_pickup_done(r : Dictionary) -> void:
	msg.text = PICK_MSG.get(r["reason"], "เก็บไม่ได้: " + String(r["reason"]))

func _candidates() -> Array:
	var out : Array = []
	for pk in get_tree().get_nodes_in_group("pickup"):
		if is_instance_valid(pk) and not pk.is_queued_for_deletion():
			out.append({"kind": InteractPick.KIND_PICKUP, "pos": pk.global_position, "ref": pk})
	for s in grid.all_structs():
		var sid : String = BuildGrid.storage_id(s["uid"])
		if grid.chest(sid) == null:
			continue
		var p : BuildingPieceData = db.get_item(StringName(s["piece"])) as BuildingPieceData
		var c : Vector2 = BuildConst.cell_to_world(s["cell"]) + Vector2(BuildGrid.footprint(p, s["rot"]) * BuildConst.CELL_SIZE) / 2.0
		out.append({"kind": InteractPick.KIND_INTERACT, "pos": c, "ref": sid})
	return out

func _prompt_text(c : Dictionary) -> String:
	if c.is_empty():
		return ""
	if c["kind"] == InteractPick.KIND_INTERACT:
		return "E: เปิดหีบ " + String(c["ref"])
	var pk : Pickup = c["ref"]
	var it : ItemData = db.get_item(pk.item_id)
	return "E: เก็บ %s x%d" % [it.display_name if it != null else String(pk.item_id), pk.amount]

func _interact() -> void:
	if _target.is_empty():
		return
	if _target["kind"] == InteractPick.KIND_PICKUP:
		_target["ref"].interact(player)
	else:
		_open_chest_by_id(_target["ref"], _target["pos"])

func _rect(cell : Vector2i, fp : Vector2i) -> Rect2:
	return Rect2(BuildConst.cell_to_world(cell), Vector2(fp * BuildConst.CELL_SIZE))

func _draw() -> void:
	var sz : Vector2 = Vector2(grid.size * BuildConst.CELL_SIZE)
	var a : float = 0.25 if build_mode else 0.08
	for x in range(grid.size.x + 1):
		draw_line(Vector2(x * BuildConst.CELL_SIZE, 0), Vector2(x * BuildConst.CELL_SIZE, sz.y), Color(1, 1, 1, a))
	for y in range(grid.size.y + 1):
		draw_line(Vector2(0, y * BuildConst.CELL_SIZE), Vector2(sz.x, y * BuildConst.CELL_SIZE), Color(1, 1, 1, a))
	var items : Array = grid.all_structs()
	for pass_layer in [BuildGrid.LAYER_FLOOR, BuildGrid.LAYER_OBJECT]:
		for s in items:
			var p : BuildingPieceData = db.get_item(StringName(s["piece"])) as BuildingPieceData
			if p == null or BuildGrid.layer_of(p) != pass_layer:
				continue
			var r : Rect2 = _rect(s["cell"], BuildGrid.footprint(p, s["rot"]))
			draw_rect(r, CAT_COLORS[p.category])
			draw_rect(r, Color.BLACK, false, 1.0)
			draw_string(ThemeDB.fallback_font, r.position + Vector2(4, 14), p.display_name.left(1), HORIZONTAL_ALIGNMENT_LEFT, -1, 12)
	if build_mode and not _ghost.is_empty():
		var p : BuildingPieceData = db.get_item(sel_id) as BuildingPieceData
		var r : Rect2 = _rect(_cell, BuildGrid.footprint(p, rot))
		if _ghost["ok"]:
			draw_rect(r, Color(0.2, 1, 0.3, 0.4))
			draw_rect(r, Color(0.2, 1, 0.3), false, 2.0)
		else:
			draw_rect(r, Color(1, 0.2, 0.2, 0.4))
			draw_rect(r, Color(1, 0.2, 0.2), false, 2.0)
			draw_line(r.position, r.end, Color(1, 0.2, 0.2), 2.0)   # กากบาท: ไม่พึ่งสีอย่างเดียว
			draw_line(Vector2(r.position.x, r.end.y), Vector2(r.end.x, r.position.y), Color(1, 0.2, 0.2), 2.0)
	if not build_mode:
		var o : Vector2 = player.global_position
		draw_line(o, o + player.get_facing() * InteractPick.RANGE, Color(1, 1, 0, 0.6), 2.0)
		draw_arc(o, InteractPick.RANGE, 0, TAU, 48, Color(1, 1, 0, 0.15), 1.0)
		if not _target.is_empty():
			draw_arc(_target["pos"], 14.0, 0, TAU, 24, Color(1, 1, 0), 2.0)
