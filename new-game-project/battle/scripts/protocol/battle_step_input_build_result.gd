class_name BattleStepInputBuildResult
extends RefCounted

var _is_ok := false
var _value := BattleStepInput.new()
var _error := BattleError.contract_violation(&"direct_step_input_build_result")


func is_success() -> bool:
	return _is_ok


func get_value() -> BattleStepInput:
	return _value.copy_input()


func get_error() -> BattleError:
	return _error.copy()


static func success(p_value: BattleStepInput) -> BattleStepInputBuildResult:
	if p_value == null or not p_value.is_valid():
		return failure(BattleError.contract_violation(
			&"step_input_success_requires_valid_value"
		))
	var snapshot := p_value.copy_input()
	if snapshot == null or snapshot == p_value or not snapshot.is_valid():
		return failure(BattleError.contract_violation(
			&"step_input_success_requires_independent_copy"
		))
	var original_bytes := p_value.canonical_bytes()
	var snapshot_bytes := snapshot.canonical_bytes()
	if (
		not original_bytes.is_ok
		or not snapshot_bytes.is_ok
		or original_bytes.value != snapshot_bytes.value
	):
		return failure(BattleError.contract_violation(
			&"step_input_success_copy_mismatch"
		))
	var result := BattleStepInputBuildResult.new()
	result._is_ok = true
	result._value = snapshot
	result._error = BattleError.success()
	return result


static func failure(p_error: BattleError) -> BattleStepInputBuildResult:
	var result := BattleStepInputBuildResult.new()
	result._is_ok = false
	result._value = BattleStepInput.new()
	result._error = (
		p_error.copy()
		if p_error != null and p_error.is_error()
		else BattleError.contract_violation(&"step_input_failure_requires_error")
	)
	return result
