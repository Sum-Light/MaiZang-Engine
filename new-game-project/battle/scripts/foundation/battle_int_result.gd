class_name BattleIntResult
extends RefCounted

var _is_ok: bool
var _value: int
var _error: BattleError

var is_ok: bool:
	get:
		return _is_ok
	set(_new_value):
		pass
var value: int:
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
	_value = 0
	_error = BattleError.contract_violation(&"direct_int_result_constructor")


static func success(p_value: int) -> BattleIntResult:
	var result := BattleIntResult.new()
	result._is_ok = true
	result._value = p_value
	result._error = BattleError.success()
	return result


static func failure(p_error: BattleError) -> BattleIntResult:
	var result := BattleIntResult.new()
	result._is_ok = false
	result._value = 0
	result._error = (
		p_error.copy()
		if p_error != null and p_error.is_error()
		else BattleError.contract_violation(&"int_failure_requires_error")
	)
	return result
