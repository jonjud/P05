extends Node2D

func _ready() -> void:
	InventoryTests.new().run_all()
	BuildGridTests.new().run_all()
	var db := ItemDatabase.new()
	print("load: ", db.load_from_directory("res://data/"), " chest is piece: ", db.get_item(&"chest_00") is BuildingPieceData)
	InteractPickTests.new().run_all()
