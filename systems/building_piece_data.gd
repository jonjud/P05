extends ItemData
class_name BuildingPieceData

enum BuildingCategory {
	FLOOR,
	WALL,
	STATION,
	STORAGE
}

@export var scene_path : String = ""
@export var size_in_cells : Vector2i = Vector2i(1,1)
@export var can_be_rotated : bool = true
@export var category : BuildingCategory = BuildingCategory.FLOOR
