extends SceneTree

const PROTOCOL_VECTORS = preload(
	"res://battle/tests/protocol/p1_protocol_command_vectors.gd"
)


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var vectors := PROTOCOL_VECTORS.new()
	var failures: Array[String] = vectors.run()
	if not failures.is_empty():
		for failure in failures:
			push_error(failure)
		quit(1)
		return
	print("BATTLE_P1_PROTOCOL_COMMAND_OK checks=%d" % vectors.check_count())
	quit(0)
