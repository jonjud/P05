extends Node2D
class_name Puppet

var target : Vector2 = Vector2.ZERO
var face : Vector2 = Vector2.DOWN
var _has : bool = false

func setup(pid : String, names : bool) -> void:
	visible = false   # ซ่อนจนกว่าจะได้ตำแหน่งแรก
	var body : ColorRect = ColorRect.new()
	body.size = Vector2(32, 32)
	body.position = Vector2(-16, -16)
	body.color = Color(0.4, 0.8, 1.0)
	add_child(body)
	add_child(PlayerSync.make_nameplate(pid, names))

func set_target(p : Vector2, f : Vector2) -> void:
	target = p
	face = f
	if not _has:
		_has = true
		position = p
		visible = true

func _process(delta : float) -> void:
	position = position.lerp(target, 1.0 - exp(-18.0 * delta))
	queue_redraw()

func _draw() -> void:
	draw_line(Vector2.ZERO, face * 48.0, Color(1, 1, 0, 0.6), 2.0)
