extends RefCounted
class_name OpResult
# สัญญาผลลัพธ์ของ op ที่เปลี่ยนกระเป๋า (add, remove, swap, move, transfer)
# {ok, reason, requested, done, remaining}
# - ok == true ก็ต่อเมื่อ reason == OK และ OK ใช้ได้เมื่อคำขอถูกต้องและ remaining == 0
# - remaining >= 0 เสมอ
# - ok == false ไม่ได้แปลว่า state ไม่เปลี่ยน (PARTIAL_FULL เปลี่ยนไปแล้ว)
#   ให้ตัดสินว่ามีการเปลี่ยนจาก done > 0 เท่านั้น ไม่ใช่จาก ok
# - move: requested = จำนวนในช่องต้นทาง (ถ้ามี split ในอนาคต requested ต้องเป็นจำนวนที่ผู้เรียกขอ)
# - from_dict ไม่ใช้รูปแบบนี้ ({ok, inventory, reason}) แต่ใช้รหัสชุดนี้

const OK : StringName = &"ok"
const PARTIAL_FULL : StringName = &"partial_full"
const FULL : StringName = &"full"
const NULL_DB : StringName = &"null_db"
const UNKNOWN_ITEM : StringName = &"unknown_item"
const INVALID_QUANTITY : StringName = &"invalid_quantity"
const NOT_ENOUGH : StringName = &"not_enough_quantity"
const DESTINATION_FULL : StringName = &"destination_full"
const NULL_INVENTORY : StringName = &"null_inventory"
const SAME_INVENTORY : StringName = &"same_inventory"
const INVALID_INDEX : StringName = &"invalid_index"
const SAME_INDEX : StringName = &"same_index"
const EMPTY_SOURCE : StringName = &"empty_source"
const INTERNAL : StringName = &"internal"
# from_dict
const INCOMPLETE_DATA : StringName = &"incomplete_data"
const BAD_SCHEMA : StringName = &"bad_schema"
const BAD_OWNER_ID : StringName = &"bad_owner_id"
const BAD_MAX_SLOTS : StringName = &"bad_max_slots"
const BAD_SLOTS_TYPE : StringName = &"bad_slots_type"
const TOO_MANY_SLOTS : StringName = &"too_many_slots"
const INCOMPLETE_SLOT : StringName = &"incomplete_slot"
const BAD_SLOT : StringName = &"bad_slot"


static func make(reason: StringName , requested : int , done: int) -> Dictionary:
	var remaining : int = maxi(0,requested - done)
	if reason == OK and remaining != 0:
		push_error("OpResult: reason ok but remaining != 0")
	return {"ok": reason == OK, "reason": reason, "requested": requested, "done": done, "remaining": remaining}
	
	
