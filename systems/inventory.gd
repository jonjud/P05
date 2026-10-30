extends Resource
class_name Inventory

@export var slots: Array[InventorySlot] = []
@export var max_slots: int = 20          # หรือใช้ weight-based ภายหลัง
@export var owner_id: String = ""        # character / player / world storage
const SCHEMA_VERSION : int = 1

signal inventory_changed

func add_to_existing_stacks(db : ItemDatabase , id : StringName , quantity : int) -> Dictionary :
	if db == null:
		return OpResult.make(OpResult.NULL_DB, quantity, 0)
	var item : ItemData = db.get_item(id)
	if item == null:
		return OpResult.make(OpResult.UNKNOWN_ITEM, quantity, 0)
	if quantity <= 0 :
		return OpResult.make(OpResult.INVALID_QUANTITY, quantity, 0)
	var remaining : int = quantity #ใส่แล้วเหลือเท่าไหร่
	#ไล่หาอันที่มีอยู่แล้ว (Existed) ก่อนแล้วเอาไปใส่
	for slot in slots :
		if remaining <= 0 :
			break
		if slot.item_data != null and slot.item_data.id == id :
			var space : int = maxi(0,item.max_stack - slot.quantity) #ช่องว่าง
			var to_add : int = mini(space, remaining) #ช่องที่เติมได้
			slot.quantity += to_add
			remaining -= to_add
	#ต่อด้วยช่องที่มีอยู่แล้วแต่ว่าง (item_data == null)
	for slot in slots :
		if remaining <= 0 :
			break
		if slot.item_data == null :
			var to_add : int = mini(item.max_stack , remaining)
			slot.item_data = item
			slot.quantity = to_add #ใช้ = เพราะ default ของ slot ใหม่คือ 1
			remaining -= to_add
	#ยังเหลือ และยังไม่ถึง max_slots = สร้างช่องใหม่
	while remaining > 0 and slots.size() < max_slots :
		var s : InventorySlot = InventorySlot.new()
		var to_add : int = mini(item.max_stack , remaining)
		s.item_data = item
		s.quantity = to_add
		slots.append(s)
		remaining -= to_add
	var added : int = quantity - remaining
	var reason : StringName = OpResult.OK
	if remaining > 0 :
		reason = OpResult.PARTIAL_FULL if added > 0 else OpResult.FULL
	if added > 0 :
		inventory_changed.emit()
	return OpResult.make(reason, quantity, added)

func remove_item(db: ItemDatabase, id: StringName, quantity: int) -> Dictionary:
	if db == null:
		return OpResult.make(OpResult.NULL_DB, quantity, 0)
	if db.get_item(id) == null:
		return OpResult.make(OpResult.UNKNOWN_ITEM, quantity, 0)
	if quantity <= 0:
		return OpResult.make(OpResult.INVALID_QUANTITY, quantity, 0)
	if count_of(id) < quantity:
		return OpResult.make(OpResult.NOT_ENOUGH, quantity, 0)
	var remaining: int = quantity
	for i in range(slots.size() - 1, -1, -1):
		if remaining == 0:
			break
		var slot = slots[i]
		if slot == null or slot.item_data == null or slot.item_data.id != id or slot.quantity <= 0:
			continue
		var to_remove: int = mini(slot.quantity, remaining)
		slot.quantity -= to_remove
		remaining -= to_remove
		if slot.quantity == 0:
			slot.item_data = null
	inventory_changed.emit()
	return OpResult.make(OpResult.OK, quantity, quantity - remaining)

func swap_slots(a: int, b: int) -> Dictionary:
	if a < 0 or a >= max_slots or b < 0 or b >= max_slots :
		return OpResult.make(OpResult.INVALID_INDEX, 1, 0)
	_ensure_size(maxi(a, b) + 1)
	var temp : InventorySlot = slots[a]
	slots[a] = slots[b]
	slots[b] = temp
	inventory_changed.emit()
	return OpResult.make(OpResult.OK, 1, 1)

func move_slots(from_index : int , to_index : int) -> Dictionary:
	# 1. เช็กขอบเขต (กับ max_slots) ก่อนแตะ slots
	if from_index < 0 or from_index >= max_slots or to_index < 0 or to_index >= max_slots :
		return OpResult.make(OpResult.INVALID_INDEX, 0, 0)
	if from_index == to_index :
		return OpResult.make(OpResult.SAME_INDEX, 0, 0)
	# 2. ต้นทางว่าง (รวมกรณีเกินขนาด array) ต้องล้มก่อนต่อช่อง
	if from_index >= slots.size() or slots[from_index] == null or slots[from_index].item_data == null :
		return OpResult.make(OpResult.EMPTY_SOURCE, 0, 0)
	# 3. ผ่านการตรวจครบแล้วค่อยต่อช่อง
	_ensure_size(to_index + 1)
	var src : InventorySlot = slots[from_index]
	var dst : InventorySlot = slots[to_index]
	var requested : int = src.quantity   # จำนวนในช่องต้นทางก่อนย้าย
	# 4. ปลายทางว่าง = ย้ายไปทั้งช่อง (swap_slots ยิงสัญญาณให้แล้ว ห้ามยิงซ้ำ)
	if dst.item_data == null :
		swap_slots(from_index , to_index)
		return OpResult.make(OpResult.OK, requested, requested)
	# 5. ชนิดเดียวกัน และปลายทางยังมีที่ว่าง = รวม stack
	if dst.item_data.id == src.item_data.id :
		var space : int = maxi(0 , dst.item_data.max_stack - dst.quantity)
		if space > 0 :
			var moved : int = mini(space , requested)
			dst.quantity += moved
			src.quantity -= moved
			if src.quantity <= 0 :
				src.item_data = null
				src.quantity = 0
			inventory_changed.emit()
			var reason : StringName = OpResult.OK if moved == requested else OpResult.PARTIAL_FULL
			return OpResult.make(reason, requested, moved)
	# 6. นอกนั้น = สลับ (swap_slots ยิงสัญญาณให้แล้ว)
	swap_slots(from_index , to_index)
	return OpResult.make(OpResult.OK, requested, requested)

func transfer_to(other : Inventory , db : ItemDatabase, id : StringName, quantity : int) -> Dictionary:
	if db == null:
		return OpResult.make(OpResult.NULL_DB, quantity, 0)
	if other == null:
		return OpResult.make(OpResult.NULL_INVENTORY, quantity, 0)
	if other == self:
		return OpResult.make(OpResult.SAME_INVENTORY, quantity, 0)
	var item : ItemData = db.get_item(id)
	if item == null:
		return OpResult.make(OpResult.UNKNOWN_ITEM, quantity, 0)
	if quantity <= 0:
		return OpResult.make(OpResult.INVALID_QUANTITY, quantity, 0)
	
	# dry-run: ตรวจทั้งสองฝั่งให้ครบก่อน ยังไม่แก้อะไร
	if count_of(id) < quantity:
		return OpResult.make(OpResult.NOT_ENOUGH, quantity, 0)
	if other.free_space_for(item) < quantity:
		return OpResult.make(OpResult.DESTINATION_FULL, quantity, 0)
	
	# ผ่านการตรวจแล้ว ขั้นนี้ต้องสำเร็จทั้งสอง (สัญญาณยิงในสอง op นี้เองแล้ว ห้ามยิงซ้ำ)
	var removed : Dictionary = remove_item(db, id, quantity)
	var added : Dictionary = other.add_to_existing_stacks(db, id, quantity)
	if not removed["ok"] or not added["ok"]:
		push_error("transfer_to: dry-run ผ่านแต่ขั้นเขียนล้ม แปลว่า free_space_for ไม่ตรงกับ add")
		return OpResult.make(OpResult.INTERNAL, quantity, 0)
	return OpResult.make(OpResult.OK, quantity, quantity)

func to_dict() -> Dictionary:
	var slt : Array = []
	for slot in slots:
		var dct : Dictionary = {}
		if slot == null or slot.item_data == null:
			dct["id"] = ""
			dct["quantity"] = 0
		else:
			dct["id"] = str(slot.item_data.id)
			dct["quantity"] = slot.quantity
		slt.append(dct)
	return {"schema_version": SCHEMA_VERSION, "owner_id": owner_id, "max_slots": max_slots, "slots": slt}

static func _fail(reason : StringName) -> Dictionary:
	return {"ok": false, "inventory": null, "reason": reason}

static func from_dict(data: Dictionary, db : ItemDatabase) -> Dictionary:
	if db == null:
		return _fail(OpResult.NULL_DB)
	if not data.has("schema_version") or not data.has("owner_id") or not data.has("max_slots") or not data.has("slots"):
		return _fail(OpResult.INCOMPLETE_DATA)
	if data["schema_version"] != SCHEMA_VERSION:
		return _fail(OpResult.BAD_SCHEMA)
	if typeof(data["owner_id"]) != TYPE_STRING:
		return _fail(OpResult.BAD_OWNER_ID)
	if typeof(data["max_slots"]) != TYPE_INT:
		return _fail(OpResult.BAD_MAX_SLOTS)
	if typeof(data["slots"]) != TYPE_ARRAY:
		return _fail(OpResult.BAD_SLOTS_TYPE)
	if data["slots"].size() > data["max_slots"]:
		return _fail(OpResult.TOO_MANY_SLOTS)
	# รอบที่ 1: ตรวจทุกช่องก่อน ยังไม่สร้างอะไร
	for s in data["slots"]:
		if typeof(s) != TYPE_DICTIONARY or not s.has("id") or not s.has("quantity"):
			return _fail(OpResult.INCOMPLETE_SLOT)
		if typeof(s["id"]) != TYPE_STRING or typeof(s["quantity"]) != TYPE_INT:
			return _fail(OpResult.BAD_SLOT)
		if s["id"] == "":
			if s["quantity"] != 0:
				return _fail(OpResult.BAD_SLOT)
			continue   # ช่องว่างถูกต้อง ตรวจรอบนี้เท่านั้น ไม่ได้ข้ามการสร้าง
		var item : ItemData = db.get_item(StringName(s["id"]))
		if item == null:
			return _fail(OpResult.UNKNOWN_ITEM)
		if s["quantity"] <= 0 or s["quantity"] > item.max_stack:
			return _fail(OpResult.INVALID_QUANTITY)
	# รอบที่ 2: ผ่านหมดแล้วค่อยสร้าง ทุกช่องต้องถูก append (รวมช่องว่าง)
	var inv : Inventory = Inventory.new()
	inv.owner_id = data["owner_id"]
	inv.max_slots = data["max_slots"]
	for s in data["slots"]:
		var slot : InventorySlot = InventorySlot.new()
		if s["id"] != "":
			slot.item_data = db.get_item(StringName(s["id"]))
			slot.quantity = s["quantity"]
		else:
			slot.quantity = 0
		inv.slots.append(slot)
	return {"ok": true, "inventory": inv, "reason": OpResult.OK}

func _ensure_size(n : int) -> void:
	while slots.size() < n :
		var s : InventorySlot = InventorySlot.new()
		s.quantity = 0      # default ของ InventorySlot เป็น 1 ต้องตั้ง 0 เอง
		slots.append(s)

# จำนวนรวมของ id นี้ในกระเป๋า
func count_of(id : StringName) -> int:
	var total : int = 0
	for s in slots:
		if s != null and s.item_data != null and s.item_data.id == id and s.quantity > 0:
			total += s.quantity
	return total

# ของชนิดนี้ใส่เพิ่มได้อีกกี่ชิ้น (ไม่แก้อะไรในกระเป๋า)
func free_space_for(item : ItemData) -> int:
	var space : int = 0
	for s in slots:
		if s == null:
			continue
		if s.item_data == null:
			space += item.max_stack                                   # ช่องว่างที่มีอยู่
		elif s.item_data.id == item.id:
			space += maxi(0, item.max_stack - s.quantity)             # ที่ว่างใน stack เดิม
	space += maxi(0, max_slots - slots.size()) * item.max_stack       # ช่องใหม่ที่ยังต่อได้
	return space
