class_name BattleStepInput
extends RefCounted

const INPUT_SCHEMA_VERSION: int = 1
const CANONICAL_DOMAIN: String = "BATTLE_STEP_INPUT"
const MAX_BATTLE_ID_BYTES: int = 128

var _is_valid := false
var _battle_id: StringName = &""
var _request_no := 0
var _actor_id := BattleStableId.INVALID_ID
var _expected_candidate_digest := PackedByteArray()
var _payload := BattleDecisionPayload.new()
var _error := BattleError.contract_violation(&"direct_step_input_constructor")


static func create(
	p_battle_id: StringName,
	p_request_no: int,
	p_actor_id: int,
	p_expected_candidate_digest: PackedByteArray,
	p_payload: BattleDecisionPayload
) -> BattleStepInputBuildResult:
	var value := BattleStepInput.new()
	var configured := value._configure(
		p_battle_id,
		p_request_no,
		p_actor_id,
		p_expected_candidate_digest,
		p_payload
	)
	if not configured.is_ok:
		return BattleStepInputBuildResult.failure(configured.error)
	return BattleStepInputBuildResult.success(value)


func is_valid() -> bool:
	return _is_valid


func get_battle_id() -> StringName:
	return _battle_id


func get_request_no() -> int:
	return _request_no


func get_actor_id() -> int:
	return _actor_id


func get_expected_candidate_digest() -> PackedByteArray:
	return _expected_candidate_digest.duplicate()


func get_payload() -> BattleDecisionPayload:
	var result := _payload.copy_payload()
	if result == null or result == _payload or not result.is_valid():
		return BattleDecisionPayload.new()
	return result


func get_error() -> BattleError:
	return _error.copy()


func copy_input() -> BattleStepInput:
	var result := BattleStepInput.new()
	if not _is_valid:
		return result
	var payload_copy := _payload.copy_payload()
	if payload_copy == null or payload_copy == _payload or not payload_copy.is_valid():
		return result
	var original_bytes := _payload.canonical_bytes()
	var copied_bytes := payload_copy.canonical_bytes()
	if (
		not original_bytes.is_ok
		or not copied_bytes.is_ok
		or original_bytes.value != copied_bytes.value
	):
		return result
	result._is_valid = true
	result._battle_id = _battle_id
	result._request_no = _request_no
	result._actor_id = _actor_id
	result._expected_candidate_digest = _expected_candidate_digest.duplicate()
	result._payload = payload_copy
	result._error = BattleError.success()
	return result


func validate_against(request: BattleInputRequest) -> BattleOperationResult:
	if not _is_valid:
		return BattleOperationResult.failure(_error)
	if request == null or not request.is_valid():
		return BattleOperationResult.failure(BattleError.create(
			BattleError.Category.PROTOCOL,
			BattleError.INVALID_REQUEST,
			BattleError.INVALID_CONTEXT_ID,
			BattleError.INVALID_CONTEXT_ID,
			_actor_id,
			BattleError.INVALID_CONTEXT_ID,
			&"step_request_invalid"
		))
	if _battle_id != request.get_battle_id():
		return _mismatch(BattleError.BATTLE_ID_MISMATCH, &"step_battle_id")
	if _request_no != request.get_request_no():
		return _mismatch(BattleError.REQUEST_NO_MISMATCH, &"step_request_no")
	if _actor_id != request.get_actor_id():
		return _mismatch(BattleError.ACTOR_ID_MISMATCH, &"step_actor_id")
	if _expected_candidate_digest != request.get_candidate_digest():
		return _mismatch(
			BattleError.CANDIDATE_DIGEST_MISMATCH,
			&"step_candidate_digest"
		)
	return request.validate_payload(_payload)


func canonical_bytes() -> BattleBytesResult:
	if not _is_valid:
		return BattleBytesResult.failure(_error)
	var payload_bytes := _payload.canonical_bytes()
	if not payload_bytes.is_ok:
		return payload_bytes
	var writer := CanonicalWriter.new()
	writer.write_string(CANONICAL_DOMAIN)
	writer.write_i64(INPUT_SCHEMA_VERSION)
	writer.write_string(String(_battle_id))
	writer.write_i64(_request_no)
	writer.write_i64(_actor_id)
	writer.write_bytes(_expected_candidate_digest)
	writer.write_bytes(payload_bytes.value)
	return writer.finish()


func canonical_hash() -> BattleBytesResult:
	var encoded := canonical_bytes()
	if not encoded.is_ok:
		return encoded
	return BattleHash.sha256_bytes(encoded.value)


func _configure(
	p_battle_id: StringName,
	p_request_no: int,
	p_actor_id: int,
	p_expected_candidate_digest: PackedByteArray,
	p_payload: BattleDecisionPayload
) -> BattleOperationResult:
	if _is_valid:
		return BattleOperationResult.failure(BattleError.contract_violation(
			&"step_input_is_sealed"
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
			&"step_battle_id"
		))
	if (
		p_request_no < BattleInputRequest.MIN_REQUEST_NO
		or p_request_no > BattleInputRequest.MAX_REQUEST_NO
	):
		return _invalidate(BattleError.create(
			BattleError.Category.PROTOCOL,
			BattleError.INVALID_SEQUENCE,
			BattleError.INVALID_CONTEXT_ID,
			BattleError.INVALID_CONTEXT_ID,
			p_actor_id,
			BattleError.INVALID_CONTEXT_ID,
			&"step_request_no"
		))
	var actor_validation := BattleStableId.validate(p_actor_id, &"step_actor_id")
	if not actor_validation.is_ok:
		return _invalidate(actor_validation.error)
	if p_expected_candidate_digest.size() != BattleHash.SHA256_BYTE_LENGTH:
		return _invalidate(BattleError.create(
			BattleError.Category.PROTOCOL,
			BattleError.INVALID_HASH_LENGTH,
			BattleError.INVALID_CONTEXT_ID,
			BattleError.INVALID_CONTEXT_ID,
			p_actor_id,
			BattleError.INVALID_CONTEXT_ID,
			&"step_candidate_digest"
		))
	if p_payload == null or not p_payload.is_valid():
		return _invalidate(BattleError.create(
			BattleError.Category.PROTOCOL,
			BattleError.PAYLOAD_REJECTED,
			BattleError.INVALID_CONTEXT_ID,
			BattleError.INVALID_CONTEXT_ID,
			p_actor_id,
			BattleError.INVALID_CONTEXT_ID,
			&"step_payload_invalid"
		))
	var payload_copy := p_payload.copy_payload()
	if payload_copy == null or payload_copy == p_payload or not payload_copy.is_valid():
		return _invalidate(BattleError.create(
			BattleError.Category.PROTOCOL,
			BattleError.PAYLOAD_REJECTED,
			BattleError.INVALID_CONTEXT_ID,
			BattleError.INVALID_CONTEXT_ID,
			p_actor_id,
			BattleError.INVALID_CONTEXT_ID,
			&"step_payload_copy"
		))
	var original_bytes := p_payload.canonical_bytes()
	var copied_bytes := payload_copy.canonical_bytes()
	if (
		not original_bytes.is_ok
		or not copied_bytes.is_ok
		or original_bytes.value != copied_bytes.value
	):
		return _invalidate(BattleError.create(
			BattleError.Category.PROTOCOL,
			BattleError.PAYLOAD_REJECTED,
			BattleError.INVALID_CONTEXT_ID,
			BattleError.INVALID_CONTEXT_ID,
			p_actor_id,
			BattleError.INVALID_CONTEXT_ID,
			&"step_payload_copy_mismatch"
		))
	_battle_id = p_battle_id
	_request_no = p_request_no
	_actor_id = p_actor_id
	_expected_candidate_digest = p_expected_candidate_digest.duplicate()
	_payload = payload_copy
	_error = BattleError.success()
	_is_valid = true
	return BattleOperationResult.success()


func _invalidate(p_error: BattleError) -> BattleOperationResult:
	if _is_valid:
		return BattleOperationResult.failure(BattleError.contract_violation(
			&"step_input_is_sealed"
		))
	_is_valid = false
	_battle_id = &""
	_request_no = 0
	_actor_id = BattleStableId.INVALID_ID
	_expected_candidate_digest = PackedByteArray()
	_payload = BattleDecisionPayload.new()
	_error = (
		p_error.copy()
		if p_error != null and p_error.is_error()
		else BattleError.contract_violation(&"step_input_invalidation_requires_error")
	)
	return BattleOperationResult.failure(_error)


func _mismatch(code: StringName, detail_key: StringName) -> BattleOperationResult:
	return BattleOperationResult.failure(BattleError.create(
		BattleError.Category.PROTOCOL,
		code,
		BattleError.INVALID_CONTEXT_ID,
		BattleError.INVALID_CONTEXT_ID,
		_actor_id,
		BattleError.INVALID_CONTEXT_ID,
		detail_key
	))
