extends Control
class_name Lobby

const MSG : Dictionary = {
	"bad_protocol": "เวอร์ชันเกมไม่ตรงกับ host",
	"db_mismatch": "ข้อมูลไอเท็มไม่ตรงกับ host",
	"host_full": "host เต็มแล้ว (สูงสุด 2 คน)",
	"player_already_connected": "player_id นี้กำลังเชื่อมต่ออยู่แล้ว",
	"bad_player_id": "player_id ไม่ถูกต้อง (a-z 0-9 _ ไม่เกิน 40 ตัว)",
	"already_joined": "เข้าร่วมไปแล้ว",
	"connect_failed": "ต่อ host ไม่ได้ ตรวจ IP / พอร์ต / ไฟร์วอลล์",
	"host_lost": "หลุดจาก host",
	"listen_failed": "เปิด host ไม่ได้ (พอร์ตถูกใช้อยู่?)",
}
var net : NetSession
var ip_edit : LineEdit
var pid_edit : LineEdit
var host_btn : Button
var join_btn : Button
var leave_btn : Button
var status_lbl : Label

func setup(n : NetSession, pid : String) -> void:
	net = n
	var box : VBoxContainer = VBoxContainer.new()
	box.position = Vector2(20, 20)
	box.custom_minimum_size = Vector2(320, 0)
	add_child(box)
	ip_edit = _row(box, "IP ของ host", "127.0.0.1")
	pid_edit = _row(box, "player_id", pid)
	host_btn = _btn(box, "เปิด Host", _on_host)
	join_btn = _btn(box, "เข้าร่วม", _on_join)
	leave_btn = _btn(box, "ตัดการเชื่อมต่อ", _on_leave)
	status_lbl = Label.new()
	box.add_child(status_lbl)
	net.status_changed.connect(_on_status)
	_on_status(net.status, "")

func _row(box : VBoxContainer, title : String, text : String) -> LineEdit:
	var l : Label = Label.new()
	l.text = title
	box.add_child(l)
	var e : LineEdit = LineEdit.new()
	e.text = text
	box.add_child(e)
	return e

func _btn(box : VBoxContainer, title : String, cb : Callable) -> Button:
	var b : Button = Button.new()
	b.text = title
	b.pressed.connect(cb)
	box.add_child(b)
	return b

func _pid() -> String:
	return pid_edit.text.strip_edges()

func _on_host() -> void:
	net.reset()
	net.start_host(_pid())

func _on_join() -> void:
	net.reset()
	net.join_host(ip_edit.text.strip_edges(), _pid())

func _on_leave() -> void:
	net.reset()

func _on_status(s : int, detail : String) -> void:
	var busy : bool = s == NetSession.Status.HOSTING or s == NetSession.Status.JOINING or s == NetSession.Status.CONNECTED
	host_btn.disabled = busy
	join_btn.disabled = busy
	leave_btn.disabled = not busy
	ip_edit.editable = not busy
	pid_edit.editable = not busy
	if busy:
		ip_edit.release_focus()
		pid_edit.release_focus()
	match s:
		NetSession.Status.IDLE: status_lbl.text = "พร้อม"
		NetSession.Status.HOSTING: status_lbl.text = "เป็น Host (%s)" % detail
		NetSession.Status.JOINING: status_lbl.text = "กำลังเชื่อมต่อ %s ..." % detail
		NetSession.Status.CONNECTED: status_lbl.text = "เชื่อมต่อแล้ว"
		_: status_lbl.text = "ล้มเหลว: " + str(MSG.get(detail, detail))
