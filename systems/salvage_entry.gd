extends Resource
class_name SalvageEntry

@export var item_id: StringName
@export var min_quantity: int = 1
@export var max_quantity: int = 1
@export var is_bonus: bool = false # false = แกนหลัก: ต้อง min == max และ chance == 1.0
@export var chance: float = 1.0    # ใช้ได้เฉพาะเมื่อ is_bonus = true
