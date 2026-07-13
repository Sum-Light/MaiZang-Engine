class_name LocalBattleAuthority
extends BattleAuthorityPort

const MAX_BATTLE_ID_BYTES: int = 128

var _engine: BattleEngine
var _battle_id: StringName = &""
var _is_valid := false
var _started := false
var _busy := false
var _finished := false
var _shutdown := false
var _pending_request: BattleInputRequest
var _error := BattleError.create(
	BattleError.Category.LIFECYCLE,
	BattleError.AUTHORITY_NOT_CONFIGURED,
	BattleError.INVALID_CONTEXT_ID,
	BattleError.INVALID_CONTEXT_ID,
	BattleError.INVALID_CONTEXT_ID,
	BattleError.INVALID_CONTEXT_ID,
	&"direct_local_authority_constructor"
)


static func create(p_battle_id: StringName, p_engine: BattleEngine) -> LocalBattleAuthority:
	var result := LocalBattleAuthority.new()
	result._configure(p_battle_id, p_engine)
	return result


func is_valid() -> bool:
	return _is_valid


func get_battle_id() -> StringName:
	return _battle_id


func get_error() -> BattleError:
	return _error.copy()


func is_started() -> bool:
	return _started


func is_busy() -> bool:
	return _busy


func is_finished() -> bool:
	return _finished


func is_shutdown() -> bool:
	return _shutdown


func has_pending_request() -> bool:
	return _pending_request != null


func start() -> BattleOperationResult:
	var ready := _require_dispatch_ready(false)
	if not ready.is_ok:
		return ready
	if _started:
		return _lifecycle_failure(
			BattleError.AUTHORITY_ALREADY_STARTED,
			&"authority_start_repeated"
		)
	_started = true
	return _run_step(null)


func submit_input(step_input: BattleStepInput) -> BattleOperationResult:
	var ready := _require_dispatch_ready(true)
	if not ready.is_ok:
		return ready
	if step_input == null or not step_input.is_valid():
		return _protocol_failure(
			BattleError.INVALID_STEP_INPUT,
			&"authority_input_invalid"
		)
	if step_input.get_battle_id() != _battle_id:
		return _protocol_failure(
			BattleError.BATTLE_ID_MISMATCH,
			&"authority_input_battle_id"
		)
	if _pending_request == null:
		return _lifecycle_failure(
			BattleError.AUTHORITY_INPUT_NOT_EXPECTED,
			&"authority_has_no_pending_request"
		)
	var request_validation := step_input.validate_against(_pending_request)
	if not request_validation.is_ok:
		return request_validation
	var input_copy := step_input.copy_input()
	if input_copy == null or input_copy == step_input or not input_copy.is_valid():
		return _protocol_failure(
			BattleError.INVALID_STEP_INPUT,
			&"authority_input_copy"
		)
	var original_bytes := step_input.canonical_bytes()
	var copied_bytes := input_copy.canonical_bytes()
	if (
		not original_bytes.is_ok
		or not copied_bytes.is_ok
		or original_bytes.value != copied_bytes.value
	):
		return _protocol_failure(
			BattleError.INVALID_STEP_INPUT,
			&"authority_input_copy_mismatch"
		)
	return _run_step(input_copy)


func shutdown() -> BattleOperationResult:
	if _shutdown:
		return BattleOperationResult.success()
	if not _is_valid:
		return BattleOperationResult.failure(_error)
	if _busy:
		return _lifecycle_failure(
			BattleError.AUTHORITY_BUSY,
			&"authority_shutdown_while_busy"
		)
	_shutdown = true
	_finished = true
	_pending_request = null
	if _engine != null:
		var engine_shutdown := _engine.shutdown()
		_engine = null
		if not engine_shutdown.is_ok:
			_error = engine_shutdown.error.copy()
			_disconnect_result_listeners()
			return engine_shutdown
	_disconnect_result_listeners()
	_error = BattleError.success()
	return BattleOperationResult.success()


func _configure(p_battle_id: StringName, p_engine: BattleEngine) -> BattleOperationResult:
	if _is_valid:
		return _lifecycle_failure(
			BattleError.AUTHORITY_ALREADY_CONFIGURED,
			&"authority_is_sealed"
		)
	var encoded_id := String(p_battle_id).to_utf8_buffer()
	if encoded_id.is_empty() or encoded_id.size() > MAX_BATTLE_ID_BYTES:
		return _invalidate(
			BattleError.INVALID_BATTLE_ID,
			&"authority_battle_id"
		)
	if p_engine == null or p_engine.is_shutdown():
		return _invalidate(
			BattleError.AUTHORITY_INVALID_ENGINE,
			&"authority_engine"
		)
	_battle_id = p_battle_id
	_engine = p_engine
	_is_valid = true
	_error = BattleError.success()
	return BattleOperationResult.success()


func _require_dispatch_ready(require_started: bool) -> BattleOperationResult:
	if not _is_valid:
		return BattleOperationResult.failure(_error)
	if _shutdown:
		return _lifecycle_failure(
			BattleError.AUTHORITY_SHUTDOWN,
			&"authority_after_shutdown"
		)
	if _busy:
		return _lifecycle_failure(
			BattleError.AUTHORITY_BUSY,
			&"authority_reentrant_dispatch"
		)
	if _finished:
		return _lifecycle_failure(
			BattleError.AUTHORITY_FINISHED,
			&"authority_after_finish"
		)
	if require_started and not _started:
		return _lifecycle_failure(
			BattleError.AUTHORITY_NOT_CONFIGURED,
			&"authority_input_before_start"
		)
	return BattleOperationResult.success()


func _run_step(step_input: BattleStepInput) -> BattleOperationResult:
	_busy = true
	if step_input != null:
		_pending_request = null
	var result := _engine.step(step_input)
	var published := _copy_or_failure(result)
	if published.get_kind() == BattleStepResult.Kind.NEED_INPUT:
		var request_copy := published.get_input_request()
		if request_copy != null and request_copy.is_valid():
			_pending_request = request_copy
	_finished = published.get_kind() in [
		BattleStepResult.Kind.BATTLE_ENDED,
		BattleStepResult.Kind.FAILED,
	]
	result_ready.emit(published)
	_busy = false
	return BattleOperationResult.success()


func _copy_or_failure(result: BattleStepResult) -> BattleStepResult:
	if (
		result != null
		and BattleStepResult.validate_instance(result).is_ok
		and _result_matches_battle(result)
	):
		var original_bytes := result.canonical_bytes()
		var result_copy := result.copy_result()
		if (
			result_copy != null
			and result_copy != result
			and BattleStepResult.validate_instance(result_copy).is_ok
			and _result_matches_battle(result_copy)
		):
			var copied_bytes := result_copy.canonical_bytes()
			if (
				original_bytes.is_ok
				and copied_bytes.is_ok
				and original_bytes.value == copied_bytes.value
			):
				return result_copy
	return BattleStepResult.failed(
		BattleCommandBatch.empty_unpublished(),
		BattleError.create(
			BattleError.Category.LIFECYCLE,
			BattleError.AUTHORITY_INVALID_RESULT,
			BattleError.INVALID_CONTEXT_ID,
			BattleError.INVALID_CONTEXT_ID,
			BattleError.INVALID_CONTEXT_ID,
			BattleError.INVALID_CONTEXT_ID,
			&"authority_engine_result"
		),
		false,
		PackedByteArray()
	)


func _result_matches_battle(result: BattleStepResult) -> bool:
	var commands := result.get_commands()
	if commands.is_published() and commands.get_battle_id() != _battle_id:
		return false
	if result.get_kind() == BattleStepResult.Kind.NEED_INPUT:
		var request := result.get_input_request()
		return request != null and request.get_battle_id() == _battle_id
	return true


func _invalidate(code: StringName, detail_key: StringName) -> BattleOperationResult:
	if _is_valid:
		return _lifecycle_failure(
			BattleError.AUTHORITY_ALREADY_CONFIGURED,
			&"authority_is_sealed"
		)
	_engine = null
	_battle_id = &""
	_is_valid = false
	_error = BattleError.create(
		(
			BattleError.Category.PROTOCOL
			if code == BattleError.INVALID_BATTLE_ID
			else BattleError.Category.LIFECYCLE
		),
		code,
		BattleError.INVALID_CONTEXT_ID,
		BattleError.INVALID_CONTEXT_ID,
		BattleError.INVALID_CONTEXT_ID,
		BattleError.INVALID_CONTEXT_ID,
		detail_key
	)
	return BattleOperationResult.failure(_error)


func _lifecycle_failure(code: StringName, detail_key: StringName) -> BattleOperationResult:
	return BattleOperationResult.failure(BattleError.create(
		BattleError.Category.LIFECYCLE,
		code,
		BattleError.INVALID_CONTEXT_ID,
		BattleError.INVALID_CONTEXT_ID,
		BattleError.INVALID_CONTEXT_ID,
		BattleError.INVALID_CONTEXT_ID,
		detail_key
	))


func _protocol_failure(code: StringName, detail_key: StringName) -> BattleOperationResult:
	return BattleOperationResult.failure(BattleError.create(
		BattleError.Category.PROTOCOL,
		code,
		BattleError.INVALID_CONTEXT_ID,
		BattleError.INVALID_CONTEXT_ID,
		BattleError.INVALID_CONTEXT_ID,
		BattleError.INVALID_CONTEXT_ID,
		detail_key
	))


func _disconnect_result_listeners() -> void:
	for connection: Dictionary in result_ready.get_connections():
		var callback: Callable = connection["callable"]
		if result_ready.is_connected(callback):
			result_ready.disconnect(callback)
