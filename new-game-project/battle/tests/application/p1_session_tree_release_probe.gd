extends RefCounted

const SESSION_VECTORS = preload(
	"res://battle/tests/application/p1_session_lifecycle_vectors.gd"
)
const EXPECTED_CHECKS: int = 12

var _failures: Array[String] = []
var _checks := 0


func run(tree: SceneTree) -> Array[String]:
	var battle_id := &"battle-tree-release"
	var engine := SESSION_VECTORS.SyntheticEngine.new(battle_id)
	var authority := LocalBattleAuthority.create(battle_id, engine)
	var session := BattleSession.new()
	tree.root.add_child(session)
	_expect(session.configure(authority).is_ok, "Tree session configure failed.")
	_expect(session.start().is_ok, "Tree session start failed.")
	_expect(session.pending_result_count() == 1, "Tree session did not retain result.")

	var session_ref: WeakRef = weakref(session)
	var authority_ref: WeakRef = weakref(authority)
	var engine_ref: WeakRef = weakref(engine)
	var result: BattleStepResult = session._result_inbox[0]
	var result_ref: WeakRef = weakref(result)
	var batch: BattleCommandBatch = result._commands
	var batch_ref: WeakRef = weakref(batch)
	var request: BattleInputRequest = authority._pending_request
	var request_ref: WeakRef = weakref(request)
	result = null
	batch = null
	request = null

	session.queue_free()
	session = null
	await tree.process_frame
	await tree.process_frame
	_expect(session_ref.get_ref() == null, "Queued Session node was not released.")
	_expect(result_ref.get_ref() == null, "Session inbox result was not released.")
	_expect(batch_ref.get_ref() == null, "Session inbox batch was not released.")
	_expect(request_ref.get_ref() == null, "Authority pending request was not released.")
	_expect(engine.is_shutdown(), "Tree exit did not shut down engine.")
	_expect(engine.shutdown_count == 1, "Tree exit shutdown count was not one.")
	_expect(
		authority.result_ready.get_connections().is_empty(),
		"Tree exit retained authority result connections."
	)

	authority = null
	engine = null
	await tree.process_frame
	_expect(authority_ref.get_ref() == null, "Tree-exited authority was not released.")
	_expect(engine_ref.get_ref() == null, "Tree-exited engine was not released.")
	return _failures


func check_count() -> int:
	return _checks


func _expect(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(message)
