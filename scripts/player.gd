extends CharacterBody2D


#===== CONFIG =====
@export_group("Movement")
@export var max_speed: float = 220.0
@export var acceleration: float = 1800.0
@export var deceleration: float = 2200.0
@export var turn_speed: float = 14.0 # ความเร็วในการหมุนตัว (lerp)
@export var air_control: float = 0.6

@export_group("Feel")
@export var input_smoothing: float = 18.0 # ความนุ่มของ input vector
@export var speed_curve: Curve #optional: curve สำหรับปรับ velocity ตาม input magnitude
@export var knockback_damping: float = 6.0

@export_group("Facing")
@export var face_movement: bool = true
@export var dead_zone: float = 0.15

#===== INTERNAL =====
var _input_dir: Vector2 = Vector2.ZERO # raw input
var _smooth_input: Vector2 = Vector2.ZERO # smoothed input
var _external_force: Vector2 = Vector2.ZERO #Knockback / push
var _last_facing: Vector2 = Vector2.DOWN
@onready var _body: ColorRect = $ColorRect

var inv : Inventory = Inventory.new()
var db : ItemDatabase = ItemDatabase.new()

signal pickup_done(result: Dictionary)

func _ready() -> void:
	add_to_group("Player")
	inv.owner_id = "player_1"
	if not db.load_from_directory("res://data/"):
		push_error("load item database failed")
	#print(inv.to_dict())
	# added 0, remaining 10, full
func _physics_process(delta: float) -> void:
	_read_input()
	_smooth_input_step(delta)
	_track_facing()
	_apply_movement(delta)
	_apply_external_force(delta)
	move_and_slide()
#---------- INPUT ----------
func _read_input() -> void:
	_input_dir = Input.get_vector("move_left","move_right","move_up","move_down")
	if _input_dir.length() < dead_zone:
		_input_dir = Vector2.ZERO
	
 #สรุป ฟังก์ชั่นนี้ใช้รับและตั้ง screening input
func _smooth_input_step(delta: float) -> void:
	var t: float = 1.0 - exp(-input_smoothing * delta)
	_smooth_input = _smooth_input.lerp(_input_dir, t)
#---------- MOVEMENT ----------
func _apply_movement(delta: float) -> void:
	var target_speed: float = max_speed
	if speed_curve:
		target_speed *= speed_curve.sample(_smooth_input.length())
	var target_velocity: Vector2 = _smooth_input * target_speed  
	var rate: float = acceleration if _smooth_input.length_squared() > 0.0001 else deceleration  
	velocity = velocity.move_toward(target_velocity,rate * delta)

#---------- EXTERNAL FORCE ----------
func _apply_external_force(delta: float) -> void:
	if _external_force.length_squared() < 0.01:
		_external_force = Vector2.ZERO
		return
	velocity += _external_force * delta
	_external_force = _external_force.lerp(Vector2.ZERO, 1.0 - exp(-knockback_damping * delta))
func add_force(force: Vector2) -> void:
	_external_force += force
func apply_knockback(from_pos: Vector2, strength: float) -> void:
	var dir: Vector2 = (global_position - from_pos).normalized()
	add_force(dir * strength)
#---------- FACING (ใช้ pivot ที่ characterbody2d แทนการหมุนตัว) ----------
func _update_facing(delta: float) -> void:
	if not face_movement:
		return
	if _smooth_input.length_squared() < 0.0001:
		return
	_last_facing = _smooth_input.normalized()
	var target_angle: float = _last_facing.angle() #หมุน parent เพื่อไม่ให้ colorect เพี้ยน
	rotation = lerp_angle(rotation, target_angle, 1.0 - exp(-turn_speed * delta))

func _track_facing() -> void:
	if _smooth_input.length_squared() > 0.01:
		_last_facing = _smooth_input.normalized()
#---------- PUBLIC API ----------
func get_facing() -> Vector2:
	return _last_facing
func get_speed_ratio() -> float:
	return velocity.length() / max_speed
func is_moving() -> bool:
	return _smooth_input.length_squared() > 0.0001
#---------- PICK UP ----------
func handle_pickup(item_id : StringName, amount : int) -> Dictionary:
	var result : Dictionary = inv.add_to_existing_stacks(db, item_id, amount)
	pickup_done.emit(result)
	return result
