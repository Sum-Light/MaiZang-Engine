class_name BattleCommand
extends RefCounted

enum Kind {
	INVALID = 0,
	STATE_OP = 1,
	PRESENTATION = 2,
	MESSAGE = 3,
	CONTROL = 4,
}

enum SyncPolicy {
	NO_WAIT = 0,
	WAIT_AFTER = 1,
}

const COMMAND_SCHEMA_VERSION: int = 1
const CANONICAL_DOMAIN: String = "BATTLE_COMMAND"
const MIN_SEQUENCE_NO: int = 1
const MAX_SEQUENCE_NO: int = BattleStableId.MAX_VALID_ID

var _is_valid := false
var _sequence_no := 0
var _kind: Kind = Kind.INVALID
var _opcode := BattleStableId.INVALID_ID
var _payload_version := 0
var _audience_id := BattleStableId.INVALID_ID
var _sync_policy: SyncPolicy = SyncPolicy.NO_WAIT
var _optional_visual := false
var _error := BattleError.contract_violation(&"direct_command_constructor")


func is_valid() -> bool:
	return _is_valid


func get_sequence_no() -> int:
	return _sequence_no


func get_kind() -> Kind:
	return _kind


func get_opcode() -> int:
	return _opcode


func get_payload_version() -> int:
	return _payload_version


func get_audience_id() -> int:
	return _audience_id


func get_sync_policy() -> SyncPolicy:
	return _sync_policy


func is_optional_visual() -> bool:
	return _optional_visual


func get_error() -> BattleError:
	return _error.copy()


func validate() -> BattleOperationResult:
	if not _is_valid:
		return BattleOperationResult.failure(_error)
	return BattleOperationResult.success()


func copy_command() -> BattleCommand:
	return BattleCommand.new()


func canonical_bytes() -> BattleBytesResult:
	var validation := validate()
	if not validation.is_ok:
		return BattleBytesResult.failure(validation.error)
	var writer := CanonicalWriter.new()
	writer.write_string(CANONICAL_DOMAIN)
	writer.write_i64(COMMAND_SCHEMA_VERSION)
	writer.write_i64(_sequence_no)
	writer.write_i64(_kind)
	writer.write_i64(_opcode)
	writer.write_i64(_payload_version)
	writer.write_i64(_audience_id)
	writer.write_i64(_sync_policy)
	writer.write_bool(_optional_visual)
	var fields_result := _append_canonical_fields(writer)
	if not fields_result.is_ok:
		return BattleBytesResult.failure(fields_result.error)
	return writer.finish()


func canonical_hash() -> BattleBytesResult:
	var encoded := canonical_bytes()
	if not encoded.is_ok:
		return encoded
	return BattleHash.sha256_bytes(encoded.value)


func _configure_command(
	p_sequence_no: int,
	p_kind: Kind,
	p_opcode: int,
	p_payload_version: int,
	p_audience_id: int,
	p_sync_policy: SyncPolicy,
	p_optional_visual: bool
) -> BattleOperationResult:
	if _is_valid:
		return BattleOperationResult.failure(BattleError.contract_violation(
			&"command_is_sealed"
		))
	if p_sequence_no < MIN_SEQUENCE_NO or p_sequence_no > MAX_SEQUENCE_NO:
		return _invalidate(BattleError.create(
			BattleError.Category.PROTOCOL,
			BattleError.INVALID_SEQUENCE,
			BattleError.INVALID_CONTEXT_ID,
			BattleError.INVALID_CONTEXT_ID,
			BattleError.INVALID_CONTEXT_ID,
			BattleError.INVALID_CONTEXT_ID,
			&"command_sequence_no"
		))
	if p_kind <= Kind.INVALID or p_kind > Kind.CONTROL:
		return _invalidate(BattleError.create(
			BattleError.Category.PROTOCOL,
			BattleError.INVALID_COMMAND_KIND,
			BattleError.INVALID_CONTEXT_ID,
			BattleError.INVALID_CONTEXT_ID,
			BattleError.INVALID_CONTEXT_ID,
			BattleError.INVALID_CONTEXT_ID,
			&"command_kind"
		))
	var opcode_validation := BattleStableId.validate(p_opcode, &"command_opcode")
	if not opcode_validation.is_ok:
		return _invalidate(opcode_validation.error)
	if (
		p_payload_version < 1
		or p_payload_version > BattleStableId.MAX_VALID_ID
	):
		return _invalidate(BattleError.create(
			BattleError.Category.PROTOCOL,
			BattleError.INVALID_PAYLOAD_VERSION,
			BattleError.INVALID_CONTEXT_ID,
			BattleError.INVALID_CONTEXT_ID,
			BattleError.INVALID_CONTEXT_ID,
			BattleError.INVALID_CONTEXT_ID,
			&"command_payload_version"
		))
	var audience_validation := BattleStableId.validate(
		p_audience_id,
		&"command_audience_id"
	)
	if not audience_validation.is_ok:
		return _invalidate(audience_validation.error)
	if p_sync_policy < SyncPolicy.NO_WAIT or p_sync_policy > SyncPolicy.WAIT_AFTER:
		return _invalidate(BattleError.create(
			BattleError.Category.PROTOCOL,
			BattleError.INVALID_COMMAND,
			BattleError.INVALID_CONTEXT_ID,
			BattleError.INVALID_CONTEXT_ID,
			BattleError.INVALID_CONTEXT_ID,
			BattleError.INVALID_CONTEXT_ID,
			&"command_sync_policy"
		))
	if p_kind == Kind.STATE_OP and p_optional_visual:
		return _invalidate(BattleError.create(
			BattleError.Category.PROTOCOL,
			BattleError.INVALID_COMMAND,
			BattleError.INVALID_CONTEXT_ID,
			BattleError.INVALID_CONTEXT_ID,
			BattleError.INVALID_CONTEXT_ID,
			BattleError.INVALID_CONTEXT_ID,
			&"state_op_cannot_be_optional"
		))
	_sequence_no = p_sequence_no
	_kind = p_kind
	_opcode = p_opcode
	_payload_version = p_payload_version
	_audience_id = p_audience_id
	_sync_policy = p_sync_policy
	_optional_visual = p_optional_visual
	_error = BattleError.success()
	_is_valid = true
	return BattleOperationResult.success()


func _invalidate(p_error: BattleError) -> BattleOperationResult:
	if _is_valid:
		return BattleOperationResult.failure(BattleError.contract_violation(
			&"command_is_sealed"
		))
	_is_valid = false
	_sequence_no = 0
	_kind = Kind.INVALID
	_opcode = BattleStableId.INVALID_ID
	_payload_version = 0
	_audience_id = BattleStableId.INVALID_ID
	_sync_policy = SyncPolicy.NO_WAIT
	_optional_visual = false
	_error = (
		p_error.copy()
		if p_error != null and p_error.is_error()
		else BattleError.contract_violation(&"command_invalidation_requires_error")
	)
	return BattleOperationResult.failure(_error)


func _append_canonical_fields(_writer: CanonicalWriter) -> BattleOperationResult:
	return BattleOperationResult.failure(BattleError.create(
		BattleError.Category.PROTOCOL,
		BattleError.INVALID_COMMAND,
		BattleError.INVALID_CONTEXT_ID,
		BattleError.INVALID_CONTEXT_ID,
		BattleError.INVALID_CONTEXT_ID,
		BattleError.INVALID_CONTEXT_ID,
		&"command_subtype_canonical_fields"
	))
