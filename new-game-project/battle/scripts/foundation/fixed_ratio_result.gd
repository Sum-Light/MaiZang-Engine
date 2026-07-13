class_name FixedRatioResult
extends RefCounted

var _is_ok: bool
var _value: FixedRatio
var _error: BattleError

var is_ok: bool:
	get:
		return _is_ok
	set(_new_value):
		pass
var value: FixedRatio:
	get:
		return _value
	set(_new_value):
		pass
var error: BattleError:
	get:
		return _error.copy()
	set(_new_value):
		pass


func _init() -> void:
	_is_ok = false
	_value = FixedRatio.new()
	_error = BattleError.contract_violation(&"direct_fixed_ratio_result_constructor")


static func success(p_value: FixedRatio) -> FixedRatioResult:
	if p_value == null:
		return failure(BattleError.contract_violation(
			&"fixed_ratio_success_requires_value"
		))
	var result := FixedRatioResult.new()
	result._is_ok = true
	result._value = p_value
	result._error = BattleError.success()
	return result


static func failure(p_error: BattleError) -> FixedRatioResult:
	var result := FixedRatioResult.new()
	result._is_ok = false
	result._value = FixedRatio.new()
	result._error = (
		p_error.copy()
		if p_error != null and p_error.is_error()
		else BattleError.contract_violation(&"fixed_ratio_failure_requires_error")
	)
	return result
