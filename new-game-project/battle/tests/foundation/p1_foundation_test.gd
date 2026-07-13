extends SceneTree

const FOUNDATION_VECTORS = preload("res://battle/tests/foundation/p1_foundation_vectors.gd")


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var vectors := FOUNDATION_VECTORS.new()
	var failures: Array[String] = vectors.run()
	if not failures.is_empty():
		for failure in failures:
			push_error(failure)
		quit(1)
		return
	print("BATTLE_P1_FOUNDATION_OK checks=%d" % vectors.check_count())
	quit(0)
