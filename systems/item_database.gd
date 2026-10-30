extends RefCounted
class_name ItemDatabase

var _items : Dictionary = {}

func load_from_directory(path : String) -> bool :
	var dir = DirAccess.open(path) #เปิดไฟล์ตำแหน่งนี้
	if not dir :
		push_error("เปิด directory ไม่ได้: " + path)
		return false

	var ok = true #เอาไว้เช็ค
	var loaded : Dictionary = {}   # โหลดลงตัวชั่วคราวก่อน

	dir.list_dir_begin() #เริ่มเอาไฟล์ออกมาเรียง
	var file_name = dir.get_next()
	while file_name != "" :
		if not dir.current_is_dir() and file_name.get_extension() == "tres" :
			var res = ResourceLoader.load(path.path_join(file_name))
			if res is ItemData :
				if loaded.has(res.id) :
					push_error("id ซ้ำ : " + str(res.id))
					ok = false
				else :
					loaded[res.id] = res
			else :
				push_error("โหลด " + file_name + " ไม่ได้")
				ok = false
		file_name = dir.get_next()
	dir.list_dir_end()

	if ok :
		_items = loaded   # เปลี่ยน state จริงเฉพาะตอนไม่มี error
	return ok

func get_item(id : StringName) -> ItemData :
	return _items.get(id)

func has_item(id : StringName) -> bool :
	return _items.has(id)
