class_name BattleDecisionPayload
extends RefCounted

enum Kind {
	INVALID = 0,
	ACTION = 1,
	TARGET = 2,
	REPLACEMENT = 3,
	FEATURE_DECISION = 4,
	DISCRETE_TIME = 5,
}

const PAYLOAD_SCHEMA_VERSION: int = 1
const CANONICAL_DOMAIN: String = "BATTLE_DECISION_PAYLOAD"

var _is_valid := false
var _kind: Kind = Kind.INVALID
var _payload_version := 0
var _error := BattleError.contract_violation(&"direct_decision_payload_constructor")


func is_valid() -> bool:
	return _is_valid


func get_kind() -> Kind:
	return _kind


func get_payload_version() -> int:
	return _payload_version


func get_error() -> BattleError:
	return _error.copy()


func validate() -> BattleOperationResult:
	if not _is_valid:
		return BattleOperationResult.failure(_error)
	return BattleOperationResult.success()


func copy_payload() -> BattleDecisionPayload:
	return BattleDecisionPayload.new()


func canonical_bytes() -> BattleBytesResult:
	var validation := validate()
	if not validation.is_ok:
		return BattleBytesResult.failure(validation.error)
	var writer := CanonicalWriter.new()
	writer.write_string(CANONICAL_DOMAIN)
	writer.write_i64(PAYLOAD_SCHEMA_VERSION)
	writer.write_i64(_payload_version)
	writer.write_i64(_kind)
	var fields_result := _append_canonical_fields(writer)
	if not fields_result.is_ok:
		return BattleBytesResult.failure(fields_result.error)
	return writer.finish()


func canonical_hash() -> BattleBytesResult:
	var encoded := canonical_bytes()
	if not encoded.is_ok:
		return encoded
	return BattleHash.sha256_bytes(encoded.value)


func _configure_payload(p_kind: Kind, p_payload_version: int) -> BattleOperationResult:
	if _is_valid:
		return BattleOperationResult.failure(BattleError.contract_violation(
			&"decision_payload_is_sealed"
		))
	if p_kind <= Kind.INVALID or p_kind > Kind.DISCRETE_TIME:
		return _invalidate(BattleError.create(
			BattleError.Category.PROTOCOL,
			BattleError.INVALID_PAYLOAD_KIND,
			BattleError.INVALID_CONTEXT_ID,
			BattleError.INVALID_CONTEXT_ID,
			BattleError.INVALID_CONTEXT_ID,
			BattleError.INVALID_CONTEXT_ID,
			&"payload_kind"
		))
	if p_payload_version != PAYLOAD_SCHEMA_VERSION:
		return _invalidate(BattleError.create(
			BattleError.Category.PROTOCOL,
			BattleError.INVALID_PAYLOAD_VERSION,
			BattleError.INVALID_CONTEXT_ID,
			BattleError.INVALID_CONTEXT_ID,
			BattleError.INVALID_CONTEXT_ID,
			BattleError.INVALID_CONTEXT_ID,
			&"payload_version"
		))
	_kind = p_kind
	_payload_version = p_payload_version
	_error = BattleError.success()
	_is_valid = true
	return BattleOperationResult.success()


func _invalidate(p_error: BattleError) -> BattleOperationResult:
	if _is_valid:
		return BattleOperationResult.failure(BattleError.contract_violation(
			&"decision_payload_is_sealed"
		))
	_is_valid = false
	_kind = Kind.INVALID
	_payload_version = 0
	_error = (
		p_error.copy()
		if p_error != null and p_error.is_error()
		else BattleError.contract_violation(&"payload_invalidation_requires_error")
	)
	return BattleOperationResult.failure(_error)


func _append_canonical_fields(_writer: CanonicalWriter) -> BattleOperationResult:
	return BattleOperationResult.failure(BattleError.create(
		BattleError.Category.PROTOCOL,
		BattleError.PAYLOAD_REJECTED,
		BattleError.INVALID_CONTEXT_ID,
		BattleError.INVALID_CONTEXT_ID,
		BattleError.INVALID_CONTEXT_ID,
		BattleError.INVALID_CONTEXT_ID,
		&"payload_subtype_canonical_fields"
	))
