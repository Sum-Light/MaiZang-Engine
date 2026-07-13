class_name BattleEngine
extends RefCounted

const STATE_SCHEMA_VERSION: int = 1
const STATE_DOMAIN: String = "BATTLE_ENGINE_EMPTY_STATE"

var _is_stepping := false
var _is_shutdown := false


func step(step_input: BattleStepInput = null) -> BattleStepResult:
	if _is_stepping:
		return _failure(
			BattleError.ENGINE_REENTRANT_STEP,
			&"engine_step_reentrant"
		)
	if _is_shutdown:
		return _failure(
			BattleError.ENGINE_SHUTDOWN,
			&"engine_step_after_shutdown"
		)

	_is_stepping = true
	var raw_result := _step_impl(step_input)
	var result := _copy_or_failure(raw_result)
	_is_stepping = false
	return result


func shutdown() -> BattleOperationResult:
	if _is_stepping:
		return _lifecycle_failure(
			BattleError.ENGINE_REENTRANT_STEP,
			&"engine_shutdown_while_stepping"
		)
	_is_shutdown = true
	return BattleOperationResult.success()


func is_stepping() -> bool:
	return _is_stepping


func is_shutdown() -> bool:
	return _is_shutdown


func authority_state_hash() -> BattleBytesResult:
	var writer := CanonicalWriter.new()
	writer.write_string(STATE_DOMAIN)
	writer.write_i64(STATE_SCHEMA_VERSION)
	writer.write_bool(false)
	writer.write_bool(_is_shutdown)
	var encoded := writer.finish()
	if not encoded.is_ok:
		return encoded
	return BattleHash.sha256_bytes(encoded.value)


func _step_impl(step_input: BattleStepInput) -> BattleStepResult:
	if step_input != null:
		return _failure(
			BattleError.ENGINE_INPUT_NOT_EXPECTED,
			&"empty_engine_has_no_pending_request"
		)
	return _failure(
		BattleError.ENGINE_NOT_CONFIGURED,
		&"empty_catalog_and_setup"
	)


func _failure(code: StringName, detail_key: StringName) -> BattleStepResult:
	var state_hash := authority_state_hash()
	if not state_hash.is_ok:
		return BattleStepResult.failed(
			BattleCommandBatch.empty_unpublished(),
			state_hash.error,
			false,
			PackedByteArray()
		)
	return BattleStepResult.failed(
		BattleCommandBatch.empty_unpublished(),
		BattleError.create(
			BattleError.Category.ENGINE,
			code,
			BattleError.INVALID_CONTEXT_ID,
			BattleError.INVALID_CONTEXT_ID,
			BattleError.INVALID_CONTEXT_ID,
			BattleError.INVALID_CONTEXT_ID,
			detail_key
		),
		true,
		state_hash.value
	)


func _copy_or_failure(result: BattleStepResult) -> BattleStepResult:
	if result != null and BattleStepResult.validate_instance(result).is_ok:
		var original_bytes := result.canonical_bytes()
		var result_copy := result.copy_result()
		if (
			result_copy != null
			and result_copy != result
			and BattleStepResult.validate_instance(result_copy).is_ok
		):
			var copied_bytes := result_copy.canonical_bytes()
			if (
				original_bytes.is_ok
				and copied_bytes.is_ok
				and original_bytes.value == copied_bytes.value
			):
				return result_copy
	return _failure(BattleError.ENGINE_INVALID_RESULT, &"engine_step_impl_result")


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
