extends RefCounted
class_name InteractPick
# OQ-03-06 (EXPERIMENTAL): ระยะคงที่ + ครึ่งวงกลมด้านหน้า + priority ก่อน แล้วค่อยใกล้สุด

const RANGE : float = 48.0
const KIND_PICKUP : int = 0     # เลขน้อย = priority สูง
const KIND_INTERACT : int = 1

# cands: [{kind:int, pos:Vector2, ref:Variant}] คืน candidate ที่ชนะ หรือ {}
static func pick(origin : Vector2, facing : Vector2, cands : Array, reach : float = RANGE) -> Dictionary:
	var best : Dictionary = {}
	var best_d : float = INF
	for c in cands:
		var off : Vector2 = c["pos"] - origin
		var d : float = off.length()
		if d > reach:
			continue
		if d > 4.0 and off.dot(facing) <= 0.0:
			continue
		if best.is_empty() or c["kind"] < best["kind"] or (c["kind"] == best["kind"] and d < best_d):
			best = c
			best_d = d
	return best
