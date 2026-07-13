class_name BattleStepResult
extends RefCounted

enum Kind {
	INVALID = 0,
	COMPLETE = 1,
	NEED_INPUT = 2,
	BATTLE_ENDED = 3,
	FAILED = 4,
}

const RESULT_SCHEMA_VERSION: int = 1
const CANONICAL_DOMAIN: String = "BATTLE_STEP_RESULT"

var _kind: Kind = Kind.FAILED
var _commands := BattleCommandBatch.empty_unpublished()
var _input_request: BattleInputRequest
var _error := BattleError.contract_violation(&"direct_step_result_constructor")
var _has_authority_hash := false
var _authority_state_hash_after := PackedByteArray()


static func complete(
	p_commands: BattleCommandBatch,
	p_has_authority_hash: bool,
	p_authority_state_hash_after: PackedByteArray
) -> BattleStepResult:
	if p_commands == null or not p_commands.is_valid() or not p_commands.is_published():
		return _contract_failure(&"complete_requires_published_batch")
	var commands_copy := p_commands.copy_batch()
	if not _is_independent_batch_copy(p_commands, commands_copy):
		return _contract_failure(&"complete_command_copy")
	var hash_error := _validate_hash_presence(
		p_has_authority_hash,
		p_authority_state_hash_after
	)
	if hash_error.is_error():
		return _contract_failure(hash_error.detail_key)
	var result := BattleStepResult.new()
	result._kind = Kind.COMPLETE
	result._commands = commands_copy
	result._input_request = null
	result._error = BattleError.success()
	result._has_authority_hash = p_has_authority_hash
	result._authority_state_hash_after = p_authority_state_hash_after.duplicate()
	return result


static func need_input(
	p_commands: BattleCommandBatch,
	p_input_request: BattleInputRequest,
	p_has_authority_hash: bool,
	p_authority_state_hash_after: PackedByteArray
) -> BattleStepResult:
	if (
		p_commands == null
		or not p_commands.is_valid()
		or not p_commands.is_published()
		or p_input_request == null
		or not p_input_request.is_valid()
	):
		return _contract_failure(&"need_input_requires_batch_and_request")
	if p_commands.get_battle_id() != p_input_request.get_battle_id():
		return _contract_failure(&"need_input_battle_id_mismatch")
	var commands_copy := p_commands.copy_batch()
	if not _is_independent_batch_copy(p_commands, commands_copy):
		return _contract_failure(&"need_input_command_copy")
	var request_copy := p_input_request.copy_request()
	if (
		request_copy == null
		or request_copy == p_input_request
		or not request_copy.is_valid()
	):
		return _contract_failure(&"need_input_request_copy")
	var original_bytes := p_input_request.canonical_bytes()
	var copied_bytes := request_copy.canonical_bytes()
	if (
		not original_bytes.is_ok
		or not copied_bytes.is_ok
		or original_bytes.value != copied_bytes.value
	):
		return _contract_failure(&"need_input_request_copy_mismatch")
	var hash_error := _validate_hash_presence(
		p_has_authority_hash,
		p_authority_state_hash_after
	)
	if hash_error.is_error():
		return _contract_failure(hash_error.detail_key)
	var result := BattleStepResult.new()
	result._kind = Kind.NEED_INPUT
	result._commands = commands_copy
	result._input_request = request_copy
	result._error = BattleError.success()
	result._has_authority_hash = p_has_authority_hash
	result._authority_state_hash_after = p_authority_state_hash_after.duplicate()
	return result


static func failed(
	p_commands: BattleCommandBatch,
	p_error: BattleError,
	p_has_authority_hash: bool,
	p_authority_state_hash_after: PackedByteArray
) -> BattleStepResult:
	if p_commands == null or not p_commands.is_valid():
		return _contract_failure(&"failed_requires_nonnull_batch")
	if p_error == null or not p_error.is_error():
		return _contract_failure(&"failed_requires_error")
	var commands_copy := p_commands.copy_batch()
	if not _is_independent_batch_copy(p_commands, commands_copy):
		return _contract_failure(&"failed_command_copy")
	var hash_error := _validate_hash_presence(
		p_has_authority_hash,
		p_authority_state_hash_after
	)
	if hash_error.is_error():
		return _contract_failure(hash_error.detail_key)
	var result := BattleStepResult.new()
	result._kind = Kind.FAILED
	result._commands = commands_copy
	result._input_request = null
	result._error = p_error.copy()
	result._has_authority_hash = p_has_authority_hash
	result._authority_state_hash_after = p_authority_state_hash_after.duplicate()
	return result


func get_kind() -> Kind:
	return _kind


func get_commands() -> BattleCommandBatch:
	return _commands.copy_batch()


func has_input_request() -> bool:
	return _input_request != null


func get_input_request() -> BattleInputRequest:
	if _input_request == null:
		return null
	var result := _input_request.copy_request()
	if result == null or result == _input_request or not result.is_valid():
		return BattleInputRequest.new()
	return result


func get_error() -> BattleError:
	return _error.copy()


func has_authority_hash() -> bool:
	return _has_authority_hash


func get_authority_state_hash_after() -> PackedByteArray:
	return _authority_state_hash_after.duplicate()


func copy_result() -> BattleStepResult:
	var commands_copy := _commands.copy_batch()
	if not _is_independent_batch_copy(_commands, commands_copy):
		return _contract_failure(&"step_result_command_copy")
	var request_copy: BattleInputRequest
	if _input_request != null:
		request_copy = _input_request.copy_request()
		if (
			request_copy == null
			or request_copy == _input_request
			or not request_copy.is_valid()
		):
			return _contract_failure(&"step_result_request_copy")
	var result := BattleStepResult.new()
	result._kind = _kind
	result._commands = commands_copy
	result._input_request = request_copy
	result._error = _error.copy()
	result._has_authority_hash = _has_authority_hash
	result._authority_state_hash_after = _authority_state_hash_after.duplicate()
	return result


func canonical_bytes() -> BattleBytesResult:
	var command_bytes := _commands.canonical_bytes()
	if not command_bytes.is_ok:
		return command_bytes
	var writer := CanonicalWriter.new()
	writer.write_string(CANONICAL_DOMAIN)
	writer.write_i64(RESULT_SCHEMA_VERSION)
	writer.write_i64(_kind)
	writer.write_bytes(command_bytes.value)
	writer.write_bool(_input_request != null)
	if _input_request != null:
		var request_bytes := _input_request.canonical_bytes()
		if not request_bytes.is_ok:
			return request_bytes
		writer.write_bytes(request_bytes.value)
	writer.write_i64(_error.category)
	writer.write_string(String(_error.code))
	writer.write_i64(_error.mechanism_id)
	writer.write_i64(_error.stage_id)
	writer.write_i64(_error.source_id)
	writer.write_i64(_error.target_id)
	writer.write_string(String(_error.detail_key))
	writer.write_bool(_has_authority_hash)
	if _has_authority_hash:
		writer.write_bytes(_authority_state_hash_after)
	return writer.finish()


func canonical_hash() -> BattleBytesResult:
	var encoded := canonical_bytes()
	if not encoded.is_ok:
		return encoded
	return BattleHash.sha256_bytes(encoded.value)


static func _validate_hash_presence(
	p_has_authority_hash: bool,
	p_authority_state_hash_after: PackedByteArray
) -> BattleError:
	if (
		(p_has_authority_hash
			and p_authority_state_hash_after.size() != BattleHash.SHA256_BYTE_LENGTH)
		or (not p_has_authority_hash
			and not p_authority_state_hash_after.is_empty())
	):
		return BattleError.create(
			BattleError.Category.PROTOCOL,
			BattleError.INVALID_HASH_LENGTH,
			BattleError.INVALID_CONTEXT_ID,
			BattleError.INVALID_CONTEXT_ID,
			BattleError.INVALID_CONTEXT_ID,
			BattleError.INVALID_CONTEXT_ID,
			&"step_result_authority_hash"
		)
	return BattleError.success()


static func _is_independent_batch_copy(
	original: BattleCommandBatch,
	copy: BattleCommandBatch
) -> bool:
	if copy == null or copy == original or not copy.is_valid():
		return false
	if copy.is_published() != original.is_published():
		return false
	var original_bytes := original.canonical_bytes()
	var copied_bytes := copy.canonical_bytes()
	return (
		original_bytes.is_ok
		and copied_bytes.is_ok
		and original_bytes.value == copied_bytes.value
	)


static func _contract_failure(detail_key: StringName) -> BattleStepResult:
	var result := BattleStepResult.new()
	result._kind = Kind.FAILED
	result._commands = BattleCommandBatch.empty_unpublished()
	result._input_request = null
	result._error = BattleError.create(
		BattleError.Category.PROTOCOL,
		BattleError.INVALID_STEP_RESULT,
		BattleError.INVALID_CONTEXT_ID,
		BattleError.INVALID_CONTEXT_ID,
		BattleError.INVALID_CONTEXT_ID,
		BattleError.INVALID_CONTEXT_ID,
		detail_key
	)
	result._has_authority_hash = false
	result._authority_state_hash_after = PackedByteArray()
	return result
