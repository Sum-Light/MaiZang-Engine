class_name BattleInputRequest
extends RefCounted

const REQUEST_SCHEMA_VERSION: int = 1
const CANONICAL_DOMAIN: String = "BATTLE_INPUT_REQUEST"
const MAX_BATTLE_ID_BYTES: int = 128
const MIN_REQUEST_NO: int = 1
const MAX_REQUEST_NO: int = BattleStableId.MAX_VALID_ID

var _is_valid := false
var _battle_id: StringName = &""
var _request_no := 0
var _actor_id := BattleStableId.INVALID_ID
var _kind: BattleDecisionPayload.Kind = BattleDecisionPayload.Kind.INVALID
var _candidate_digest := PackedByteArray()
var _view_hash := PackedByteArray()
var _error := BattleError.contract_violation(&"direct_input_request_constructor")


func is_valid() -> bool:
	return _is_valid


func get_battle_id() -> StringName:
	return _battle_id


func get_request_no() -> int:
	return _request_no


func get_actor_id() -> int:
	return _actor_id


func get_kind() -> BattleDecisionPayload.Kind:
	return _kind


func get_candidate_digest() -> PackedByteArray:
	return _candidate_digest.duplicate()


func get_view_hash() -> PackedByteArray:
	return _view_hash.duplicate()


func get_error() -> BattleError:
	return _error.copy()


func validate() -> BattleOperationResult:
	if not _is_valid:
		return BattleOperationResult.failure(_error)
	return BattleOperationResult.success()


func validate_payload(payload: BattleDecisionPayload) -> BattleOperationResult:
	return _validate_payload_header(payload)


func copy_request() -> BattleInputRequest:
	return BattleInputRequest.new()


func canonical_bytes() -> BattleBytesResult:
	var validation := validate()
	if not validation.is_ok:
		return BattleBytesResult.failure(validation.error)
	var writer := CanonicalWriter.new()
	writer.write_string(CANONICAL_DOMAIN)
	writer.write_i64(REQUEST_SCHEMA_VERSION)
	writer.write_string(String(_battle_id))
	writer.write_i64(_request_no)
	writer.write_i64(_actor_id)
	writer.write_i64(_kind)
	writer.write_bytes(_candidate_digest)
	writer.write_bytes(_view_hash)
	var fields_result := _append_canonical_fields(writer)
	if not fields_result.is_ok:
		return BattleBytesResult.failure(fields_result.error)
	return writer.finish()


func canonical_hash() -> BattleBytesResult:
	var encoded := canonical_bytes()
	if not encoded.is_ok:
		return encoded
	return BattleHash.sha256_bytes(encoded.value)


func _configure_request(
	p_battle_id: StringName,
	p_request_no: int,
	p_actor_id: int,
	p_kind: BattleDecisionPayload.Kind,
	p_candidate_digest: PackedByteArray,
	p_view_hash: PackedByteArray
) -> BattleOperationResult:
	if _is_valid:
		return BattleOperationResult.failure(BattleError.contract_violation(
			&"input_request_is_sealed"
		))
	var battle_id_bytes := String(p_battle_id).to_utf8_buffer()
	if battle_id_bytes.is_empty() or battle_id_bytes.size() > MAX_BATTLE_ID_BYTES:
		return _invalidate(BattleError.create(
			BattleError.Category.PROTOCOL,
			BattleError.INVALID_BATTLE_ID,
			BattleError.INVALID_CONTEXT_ID,
			BattleError.INVALID_CONTEXT_ID,
			p_actor_id,
			BattleError.INVALID_CONTEXT_ID,
			&"request_battle_id"
		))
	if p_request_no < MIN_REQUEST_NO or p_request_no > MAX_REQUEST_NO:
		return _invalidate(BattleError.create(
			BattleError.Category.PROTOCOL,
			BattleError.INVALID_SEQUENCE,
			BattleError.INVALID_CONTEXT_ID,
			BattleError.INVALID_CONTEXT_ID,
			p_actor_id,
			BattleError.INVALID_CONTEXT_ID,
			&"request_no"
		))
	var actor_validation := BattleStableId.validate(p_actor_id, &"request_actor_id")
	if not actor_validation.is_ok:
		return _invalidate(actor_validation.error)
	if (
		p_kind <= BattleDecisionPayload.Kind.INVALID
		or p_kind > BattleDecisionPayload.Kind.DISCRETE_TIME
	):
		return _invalidate(BattleError.create(
			BattleError.Category.PROTOCOL,
			BattleError.INVALID_PAYLOAD_KIND,
			BattleError.INVALID_CONTEXT_ID,
			BattleError.INVALID_CONTEXT_ID,
			p_actor_id,
			BattleError.INVALID_CONTEXT_ID,
			&"request_kind"
		))
	if (
		p_candidate_digest.size() != BattleHash.SHA256_BYTE_LENGTH
		or p_view_hash.size() != BattleHash.SHA256_BYTE_LENGTH
	):
		return _invalidate(BattleError.create(
			BattleError.Category.PROTOCOL,
			BattleError.INVALID_HASH_LENGTH,
			BattleError.INVALID_CONTEXT_ID,
			BattleError.INVALID_CONTEXT_ID,
			p_actor_id,
			BattleError.INVALID_CONTEXT_ID,
			&"request_hash"
		))
	_battle_id = p_battle_id
	_request_no = p_request_no
	_actor_id = p_actor_id
	_kind = p_kind
	_candidate_digest = p_candidate_digest.duplicate()
	_view_hash = p_view_hash.duplicate()
	_error = BattleError.success()
	_is_valid = true
	return BattleOperationResult.success()


func _validate_payload_header(payload: BattleDecisionPayload) -> BattleOperationResult:
	if not _is_valid:
		return BattleOperationResult.failure(_error)
	if payload == null or not payload.is_valid():
		return BattleOperationResult.failure(BattleError.create(
			BattleError.Category.PROTOCOL,
			BattleError.PAYLOAD_REJECTED,
			BattleError.INVALID_CONTEXT_ID,
			BattleError.INVALID_CONTEXT_ID,
			_actor_id,
			BattleError.INVALID_CONTEXT_ID,
			&"request_payload_invalid"
		))
	if payload.get_kind() != _kind:
		return BattleOperationResult.failure(BattleError.create(
			BattleError.Category.PROTOCOL,
			BattleError.PAYLOAD_KIND_MISMATCH,
			BattleError.INVALID_CONTEXT_ID,
			BattleError.INVALID_CONTEXT_ID,
			_actor_id,
			BattleError.INVALID_CONTEXT_ID,
			&"request_payload_kind"
		))
	return BattleOperationResult.success()


func _invalidate(p_error: BattleError) -> BattleOperationResult:
	if _is_valid:
		return BattleOperationResult.failure(BattleError.contract_violation(
			&"input_request_is_sealed"
		))
	_is_valid = false
	_battle_id = &""
	_request_no = 0
	_actor_id = BattleStableId.INVALID_ID
	_kind = BattleDecisionPayload.Kind.INVALID
	_candidate_digest = PackedByteArray()
	_view_hash = PackedByteArray()
	_error = (
		p_error.copy()
		if p_error != null and p_error.is_error()
		else BattleError.contract_violation(&"request_invalidation_requires_error")
	)
	return BattleOperationResult.failure(_error)


func _append_canonical_fields(_writer: CanonicalWriter) -> BattleOperationResult:
	return BattleOperationResult.failure(BattleError.create(
		BattleError.Category.PROTOCOL,
		BattleError.INVALID_REQUEST,
		BattleError.INVALID_CONTEXT_ID,
		BattleError.INVALID_CONTEXT_ID,
		_actor_id,
		BattleError.INVALID_CONTEXT_ID,
		&"request_subtype_canonical_fields"
	))
