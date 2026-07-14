extends SceneTree

const TRACE_VECTORS = preload(
	"res://battle/tests/specs/p2_mechanism_trace_vectors.gd"
)


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var vectors := TRACE_VECTORS.new()
	var failures: Array[String] = vectors.run()
	if vectors.check_count() != TRACE_VECTORS.EXPECTED_CHECKS:
		failures.append("Mechanism trace count stopped at %d; expected %d." % [
			vectors.check_count(),
			TRACE_VECTORS.EXPECTED_CHECKS,
		])
	if not failures.is_empty():
		for failure: String in failures:
			push_error(failure)
		quit(1)
		return
	print("BATTLE_P2_MECHANISM_TRACE_OK checks=%d" % vectors.check_count())
	quit(0)
