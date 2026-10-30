extends RefCounted
class_name BuildResult
# Build operation result follows OpResult: {ok, reason, requested, done, remaining}.
# State change is determined by done > 0, never by ok alone.

static func make(reason: StringName, requested: int, done: int) -> Dictionary:
	var remaining: int = requested - done
	assert(requested >= 0 and done >= 0 and remaining >= 0, "BuildResult counts must be valid")
	assert((reason == &"ok") == (done == requested), "ok reason and completed count must agree")
	return {
		"ok": reason == &"ok",
		"reason": reason,
		"requested": requested,
		"done": done,
		"remaining": remaining,
	}
