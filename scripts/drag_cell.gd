extends Button
class_name DragCell
# ช่องเดียวที่ลากได้/รับการวางได้ ไม่ถือของ แค่อ้าง Inventory + index

signal dropped(src_inv : Inventory, src_index : int, dst_index : int)
var inv : Inventory
var index : int = -1

func _get_drag_data(_at : Vector2) -> Variant:
	if inv == null or index < 0 or index >= inv.slots.size() or inv.slots[index].item_data == null:
		return null
	var l : Label = Label.new()
	l.text = inv.slots[index].item_data.display_name
	set_drag_preview(l)
	return {"inv": inv, "index": index}

func _can_drop_data(_at : Vector2, data : Variant) -> bool:
	return typeof(data) == TYPE_DICTIONARY and data.has("inv") and data.has("index") and data["inv"] is Inventory

func _drop_data(_at : Vector2, data : Variant) -> void:
	dropped.emit(data["inv"], data["index"], index)
