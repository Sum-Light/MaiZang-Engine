class_name BattleOperationResult
extends RefCounted

var _is_ok: bool
var _error: BattleError

var is_ok: bool:
	get:
		return _is_ok
	set(_value):
		pass
var error: BattleError:
	get:
		return _error.copy()
	set(_value):
		pass


func _init() -> void:
	_is_ok = false
	_error = BattleError.contract_violation(&"direct_operation_result_constructor")


static func success() -> BattleOperationResult:
	var result := BattleOperationResult.new()
	result._is_ok = true
	result._error = BattleError.success()
	return result


static func failure(p_error: BattleError) -> BattleOperationResult:
	var result := BattleOperationResult.new()
	result._is_ok = false
	result._error = (
		p_error.copy()
		if p_error != null and p_error.is_error()
		else BattleError.contract_violation(&"operation_failure_requires_error")
	)
	return result
