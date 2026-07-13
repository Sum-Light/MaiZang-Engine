class_name BattleBytesResult
extends RefCounted

var _is_ok: bool
var _value: PackedByteArray
var _error: BattleError

var is_ok: bool:
	get:
		return _is_ok
	set(_new_value):
		pass
var value: PackedByteArray:
	get:
		return _value.duplicate()
	set(_new_value):
		pass
var error: BattleError:
	get:
		return _error.copy()
	set(_new_value):
		pass


func _init() -> void:
	_is_ok = false
	_value = PackedByteArray()
	_error = BattleError.contract_violation(&"direct_bytes_result_constructor")


static func success(p_value: PackedByteArray) -> BattleBytesResult:
	var result := BattleBytesResult.new()
	result._is_ok = true
	result._value = p_value.duplicate()
	result._error = BattleError.success()
	return result


static func failure(p_error: BattleError) -> BattleBytesResult:
	var result := BattleBytesResult.new()
	result._is_ok = false
	result._value = PackedByteArray()
	result._error = (
		p_error.copy()
		if p_error != null and p_error.is_error()
		else BattleError.contract_violation(&"bytes_failure_requires_error")
	)
	return result
