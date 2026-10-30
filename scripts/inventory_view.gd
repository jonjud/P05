extends Control

var inv : Inventory



@onready var grid_con : GridContainer = $GridContainer

signal slot_clicked(index: int)

func _ready() -> void:
	pass


func bind(inventory : Inventory) -> void:
	if inv != null and inv.inventory_changed.is_connected(refresh):
		inv.inventory_changed.disconnect(refresh)
	inv = inventory
	if inv != null:
		inv.inventory_changed.connect(refresh)
	refresh()


func refresh() -> void:
	if inv == null:
		return
	for child in grid_con.get_children():
		grid_con.remove_child(child)
		child.queue_free()
	for i in range(inv.max_slots):
		var cell : Button = Button.new()
		cell.pressed.connect(_on_cell_pressed.bind(i))
		cell.custom_minimum_size = Vector2(80, 50)
		if i < inv.slots.size() and inv.slots[i].item_data != null:
			cell.text = "%s\nx%d" % [
				inv.slots[i].item_data.display_name,
				inv.slots[i].quantity
			]
			cell.tooltip_text = inv.slots[i].item_data.description
		else:
			cell.text = "-"

		grid_con.add_child(cell)


func _on_cell_pressed(i : int) -> void:
	slot_clicked.emit(i)
