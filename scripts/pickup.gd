extends Area2D
class_name Pickup

@export var item_id : StringName = &"stone_00"
@export var amount : int = 1

func _on_body_entered(_body : Node2D) -> void:
	pass   # ปิด auto-pickup (pickup.tscn ยังเชื่อม signal นี้อยู่ ห้ามลบฟังก์ชัน)

func interact(player : Node) -> Dictionary:
	var r : Dictionary = player.handle_pickup(item_id, amount)
	amount = r["remaining"]
	if amount <= 0:
		queue_free()
	return r
