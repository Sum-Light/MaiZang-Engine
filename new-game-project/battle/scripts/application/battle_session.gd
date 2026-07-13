class_name BattleSession
extends Node

signal result_ready(result: BattleStepResult)

const MAX_INBOX_ITEMS: int = 1024

var _authority: BattleAuthorityPort
var _pending_request: BattleInputRequest
var _result_inbox: Array[BattleStepResult] = []
var _input_inbox: Array[BattleStepInput] = []
var _configured := false
var _started := false
var _dispatching_authority := false
var _processing := false
var _finished := false
var _closed := false
var _error := BattleError.success()


func configure(authority: BattleAuthorityPort) -> BattleOperationResult:
	if _closed:
		return _failure(BattleError.SESSION_CLOSED, &"session_configure_after_close")
	if _configured:
		return _failure(
			BattleError.SESSION_ALREADY_CONFIGURED,
			&"session_configure_repeated"
		)
	if (
		authority == null
		or not authority.is_valid()
		or authority.is_started()
		or authority.is_finished()
		or authority.is_shutdown()
	):
		return _failure(
			BattleError.SESSION_INVALID_AUTHORITY,
			&"session_authority"
		)
	_authority = authority
	_authority.result_ready.connect(_on_authority_result)
	_configured = true
	_error = BattleError.success()
	return BattleOperationResult.success()


func start() -> BattleOperationResult:
	var ready := _require_open(true)
	if not ready.is_ok:
		return ready
	if _dispatching_authority:
		return _failure(BattleError.SESSION_BUSY, &"session_start_reentrant")
	if _started:
		return _failure(BattleError.SESSION_ALREADY_STARTED, &"session_start_repeated")
	_dispatching_authority = true
	var started := _authority.start()
	_dispatching_authority = false
	if not started.is_ok:
		_error = started.error.copy()
		return started
	_started = true
	return BattleOperationResult.success()


func submit_input(step_input: BattleStepInput) -> BattleOperationResult:
	var ready := _require_started()
	if not ready.is_ok:
		return ready
	if _finished or _authority.is_finished():
		return _failure(BattleError.AUTHORITY_FINISHED, &"session_input_after_finish")
	if _pending_request == null:
		return _failure(
			BattleError.AUTHORITY_INPUT_NOT_EXPECTED,
			&"session_has_no_published_request"
		)
	if step_input == null or not step_input.is_valid():
		return _protocol_failure(BattleError.INVALID_STEP_INPUT, &"session_input_invalid")
	if step_input.get_battle_id() != _authority.get_battle_id():
		return _protocol_failure(BattleError.BATTLE_ID_MISMATCH, &"session_input_battle_id")
	var request_validation := step_input.validate_against(_pending_request)
	if not request_validation.is_ok:
		return request_validation
	var input_copy := step_input.copy_input()
	if input_copy == null or input_copy == step_input or not input_copy.is_valid():
		return _protocol_failure(BattleError.INVALID_STEP_INPUT, &"session_input_copy")
	var original_bytes := step_input.canonical_bytes()
	var copied_bytes := input_copy.canonical_bytes()
	if (
		not original_bytes.is_ok
		or not copied_bytes.is_ok
		or original_bytes.value != copied_bytes.value
	):
		return _protocol_failure(
			BattleError.INVALID_STEP_INPUT,
			&"session_input_copy_mismatch"
		)
	if _input_inbox.size() >= MAX_INBOX_ITEMS:
		return _failure(BattleError.SESSION_INBOX_FULL, &"session_input_inbox")
	_input_inbox.append(input_copy)
	_pending_request = null
	return BattleOperationResult.success()


func pump() -> BattleOperationResult:
	var ready := _require_started()
	if not ready.is_ok:
		return ready
	if _processing:
		return _failure(BattleError.SESSION_REENTRANT_PUMP, &"session_pump_reentrant")
	if _error.is_error():
		return BattleOperationResult.failure(_error)

	_processing = true
	var result_count := _result_inbox.size()
	var input_count := mini(_input_inbox.size(), 1)
	for _index in result_count:
		var result: BattleStepResult = _result_inbox.pop_front()
		_finished = result.get_kind() in [
			BattleStepResult.Kind.BATTLE_ENDED,
			BattleStepResult.Kind.FAILED,
		]
		_pending_request = (
			result.get_input_request()
			if result.get_kind() == BattleStepResult.Kind.NEED_INPUT
			else null
		)
		result_ready.emit(result.copy_result())
		if _finished:
			_pending_request = null
			_input_inbox.clear()
			_result_inbox.clear()
			break

	if not _finished:
		for _index in input_count:
			var input: BattleStepInput = _input_inbox.pop_front()
			var submitted := _authority.submit_input(input)
			if not submitted.is_ok:
				_error = submitted.error.copy()
				_processing = false
				return submitted

	_processing = false
	return BattleOperationResult.success()


func close() -> BattleOperationResult:
	if _closed:
		return BattleOperationResult.success()
	if _processing:
		return _failure(BattleError.SESSION_REENTRANT_PUMP, &"session_close_while_pumping")
	if _dispatching_authority:
		return _failure(BattleError.SESSION_BUSY, &"session_close_while_dispatching")
	var shutdown_result := BattleOperationResult.success()
	if _authority != null:
		var callback := Callable(self, "_on_authority_result")
		if _authority.result_ready.is_connected(callback):
			_authority.result_ready.disconnect(callback)
		shutdown_result = _authority.shutdown()
		_authority = null
	_result_inbox.clear()
	_input_inbox.clear()
	_pending_request = null
	_disconnect_result_listeners()
	_configured = false
	_finished = true
	_closed = true
	if not shutdown_result.is_ok:
		_error = shutdown_result.error.copy()
		return shutdown_result
	_error = BattleError.success()
	return BattleOperationResult.success()


func is_configured() -> bool:
	return _configured


func is_started() -> bool:
	return _started


func is_pumping() -> bool:
	return _processing


func is_dispatching_authority() -> bool:
	return _dispatching_authority


func is_finished() -> bool:
	return _finished


func is_closed() -> bool:
	return _closed


func pending_result_count() -> int:
	return _result_inbox.size()


func pending_input_count() -> int:
	return _input_inbox.size()


func has_pending_request() -> bool:
	return _pending_request != null


func get_error() -> BattleError:
	return _error.copy()


func _exit_tree() -> void:
	if not _closed:
		close()


func _on_authority_result(result: BattleStepResult) -> void:
	if _closed:
		return
	if _finished:
		_error = _make_error(BattleError.SESSION_INVALID_INBOX, &"session_late_result")
		return
	if (
		result == null
		or not BattleStepResult.validate_instance(result).is_ok
		or not _result_matches_battle(result)
	):
		_error = _make_error(BattleError.SESSION_INVALID_INBOX, &"session_null_result")
		return
	var original_bytes := result.canonical_bytes()
	var result_copy := result.copy_result()
	if (
		result_copy == null
		or result_copy == result
		or not BattleStepResult.validate_instance(result_copy).is_ok
		or not _result_matches_battle(result_copy)
	):
		_error = _make_error(BattleError.SESSION_INVALID_INBOX, &"session_result_alias")
		return
	var copied_bytes := result_copy.canonical_bytes()
	if (
		not original_bytes.is_ok
		or not copied_bytes.is_ok
		or original_bytes.value != copied_bytes.value
	):
		_error = _make_error(BattleError.SESSION_INVALID_INBOX, &"session_result_copy")
		return
	if _result_inbox.size() >= MAX_INBOX_ITEMS:
		_error = _make_error(BattleError.SESSION_INBOX_FULL, &"session_result_inbox")
		return
	_result_inbox.append(result_copy)


func _result_matches_battle(result: BattleStepResult) -> bool:
	if _authority == null:
		return false
	var battle_id := _authority.get_battle_id()
	var commands := result.get_commands()
	if commands.is_published() and commands.get_battle_id() != battle_id:
		return false
	if result.get_kind() == BattleStepResult.Kind.NEED_INPUT:
		var request := result.get_input_request()
		return request != null and request.get_battle_id() == battle_id
	return true


func _require_open(require_configured: bool) -> BattleOperationResult:
	if _closed:
		return _failure(BattleError.SESSION_CLOSED, &"session_closed")
	if require_configured and not _configured:
		return _failure(BattleError.SESSION_NOT_CONFIGURED, &"session_not_configured")
	return BattleOperationResult.success()


func _require_started() -> BattleOperationResult:
	var ready := _require_open(true)
	if not ready.is_ok:
		return ready
	if not _started:
		return _failure(BattleError.SESSION_NOT_STARTED, &"session_not_started")
	return BattleOperationResult.success()


func _failure(code: StringName, detail_key: StringName) -> BattleOperationResult:
	return BattleOperationResult.failure(_make_error(code, detail_key))


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


func _make_error(code: StringName, detail_key: StringName) -> BattleError:
	return BattleError.create(
		BattleError.Category.LIFECYCLE,
		code,
		BattleError.INVALID_CONTEXT_ID,
		BattleError.INVALID_CONTEXT_ID,
		BattleError.INVALID_CONTEXT_ID,
		BattleError.INVALID_CONTEXT_ID,
		detail_key
	)


func _disconnect_result_listeners() -> void:
	for connection: Dictionary in result_ready.get_connections():
		var callback: Callable = connection["callable"]
		if result_ready.is_connected(callback):
			result_ready.disconnect(callback)
