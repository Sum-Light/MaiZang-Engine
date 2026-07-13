extends SceneTree

const SESSION_VECTORS = preload(
	"res://battle/tests/application/p1_session_lifecycle_vectors.gd"
)
const TREE_RELEASE_PROBE = preload(
	"res://battle/tests/application/p1_session_tree_release_probe.gd"
)


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var vectors := SESSION_VECTORS.new()
	var failures: Array[String] = vectors.run()
	if vectors.check_count() != SESSION_VECTORS.EXPECTED_CHECKS:
		failures.append("Session vector count stopped at %d; expected %d." % [
			vectors.check_count(),
			SESSION_VECTORS.EXPECTED_CHECKS,
		])
	var tree_probe := TREE_RELEASE_PROBE.new()
	var tree_failures: Array[String] = await tree_probe.run(self, SESSION_VECTORS)
	failures.append_array(tree_failures)
	if tree_probe.check_count() != TREE_RELEASE_PROBE.EXPECTED_CHECKS:
		failures.append("Tree release vector count stopped at %d; expected %d." % [
			tree_probe.check_count(),
			TREE_RELEASE_PROBE.EXPECTED_CHECKS,
		])
	if not failures.is_empty():
		for failure in failures:
			push_error(failure)
		quit(1)
		return
	print("BATTLE_P1_SESSION_LIFECYCLE_OK checks=%d" % (
		vectors.check_count() + tree_probe.check_count()
	))
	quit(0)
