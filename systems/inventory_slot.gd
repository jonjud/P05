extends Resource
class_name InventorySlot

#ตาม DOC-03 , หัวข้อที่ 1.3
@export var item_data: ItemData # reference ไปยัง definition
@export var quantity: int = 1
@export var unique_id: String = "" # สำหรับ non-stackable / equipment instance
@export var metadata: Dictionary = {}    # quality / enchant / owner history ฯลฯ (เพิ่มเมื่อมีหลักฐานว่าจำเป็น)
