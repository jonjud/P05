extends GridContainer
class_name DragInventoryView

signal slot_dropped(src_inv : Inventory, src_index : int, dst_inv : Inventory, dst_index : int)
var inv : Inventory

func _init() -> void:
	columns = 4

func bind(inventory : Inventory) -> void:
	if inv != null and inv.inventory_changed.is_connected(refresh):
		inv.inventory_changed.disconnect(refresh)
	inv = inventory
	if inv != null:
		inv.inventory_changed.connect(refresh)
	refresh()

func refresh() -> void:
	if inv == null:
		return
	for c in get_children():
		remove_child(c)
		c.queue_free()
	for i in range(inv.max_slots):
		var cell : DragCell = DragCell.new()
		cell.inv = inv
		cell.index = i
		cell.custom_minimum_size = Vector2(92, 38)
		cell.clip_text = true
		if i < inv.slots.size() and inv.slots[i].item_data != null:
			cell.text = "%s x%d" % [inv.slots[i].item_data.display_name, inv.slots[i].quantity]
			cell.tooltip_text = inv.slots[i].item_data.description
		else:
			cell.text = "-"
		cell.dropped.connect(_on_cell_dropped.bind(i))
		add_child(cell)

func _on_cell_dropped(src_inv : Inventory, src_index : int, _dst_index : int, dst_index : int) -> void:
	slot_dropped.emit(src_inv, src_index, inv, dst_index)
