extends RefCounted
class_name InteractPickTests

var passed : int = 0
var failed : int = 0

func t(label : String, cond : bool) -> void:
	if cond:
		passed += 1
	else:
		failed += 1
		print("FAIL: ", label)

func cand(kind : int, pos : Vector2) -> Dictionary:
	return {"kind": kind, "pos": pos, "ref": null}

func run_all() -> void:
	var o : Vector2 = Vector2.ZERO
	var f : Vector2 = Vector2.RIGHT
	var kp : int = InteractPick.KIND_PICKUP
	var ki : int = InteractPick.KIND_INTERACT
	t("empty", InteractPick.pick(o, f, []).is_empty())
	t("front in range", not InteractPick.pick(o, f, [cand(ki, Vector2(30, 0))]).is_empty())
	t("behind", InteractPick.pick(o, f, [cand(ki, Vector2(-30, 0))]).is_empty())
	t("side (dot 0)", InteractPick.pick(o, f, [cand(ki, Vector2(0, 30))]).is_empty())
	t("out of range", InteractPick.pick(o, f, [cand(ki, Vector2(60, 0))]).is_empty())
	t("boundary 48 in", not InteractPick.pick(o, f, [cand(ki, Vector2(48, 0))]).is_empty())
	t("49 out", InteractPick.pick(o, f, [cand(ki, Vector2(49, 0))]).is_empty())
	t("on top (d<=4)", not InteractPick.pick(o, f, [cand(ki, Vector2(-2, 0))]).is_empty())
	t("pickup beats nearer chest", InteractPick.pick(o, f, [cand(ki, Vector2(10, 0)), cand(kp, Vector2(40, 0))])["kind"] == kp)
	t("order independent", InteractPick.pick(o, f, [cand(kp, Vector2(40, 0)), cand(ki, Vector2(10, 0))])["kind"] == kp)
	t("nearest same kind", InteractPick.pick(o, f, [cand(kp, Vector2(40, 0)), cand(kp, Vector2(20, 0))])["pos"] == Vector2(20, 0))
	t("pickup behind ignored", InteractPick.pick(o, f, [cand(kp, Vector2(-20, 0)), cand(ki, Vector2(20, 0))])["kind"] == ki)
	var d : Vector2 = Vector2(1, 1).normalized()
	t("diag front", not InteractPick.pick(o, d, [cand(ki, Vector2(20, 20))]).is_empty())
	t("diag side out", InteractPick.pick(o, d, [cand(ki, Vector2(-20, 20))]).is_empty())
	print("InteractPick: Passed ", passed, " / Failed ", failed)
