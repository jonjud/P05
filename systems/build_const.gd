extends RefCounted
class_name BuildConst

const CELL_SIZE : int = 32 #ชั่วคราว ไม่ใช่ pixel scale สุดท้าย (Art Spec 20.7)

static func cell_to_world(c: Vector2i) -> Vector2: #used static cause have to create from nothin'
	return Vector2(c * CELL_SIZE)

static func world_to_cell(p: Vector2) -> Vector2i: 
	return Vector2i(floori(p.x / CELL_SIZE), floori(p.y / CELL_SIZE))
