class_name FixedRatio
extends RefCounted

var _numerator: int
var _denominator: int


func _init() -> void:
	_numerator = 0
	_denominator = 1


static func create(p_numerator: int, p_denominator: int) -> FixedRatioResult:
	if p_denominator <= 0:
		return FixedRatioResult.failure(BattleError.create(
			BattleError.Category.NUMERIC,
			BattleError.INVALID_FIXED_RATIO,
			BattleError.INVALID_CONTEXT_ID,
			BattleError.INVALID_CONTEXT_ID,
			BattleError.INVALID_CONTEXT_ID,
			BattleError.INVALID_CONTEXT_ID,
			&"denominator_must_be_positive"
		))
	if p_numerator == 0:
		return FixedRatioResult.success(FixedRatio.new())
	var divisor := _greatest_common_divisor(p_numerator, p_denominator)
	var result := FixedRatio.new()
	result._set_canonical(p_numerator / divisor, p_denominator / divisor)
	return FixedRatioResult.success(result)


func get_numerator() -> int:
	return _numerator


func get_denominator() -> int:
	return _denominator


func apply(value: int, rounding: BattleIntMath.RoundingMode) -> BattleIntResult:
	return BattleIntMath.apply_ratio(value, _numerator, _denominator, rounding)


func _set_canonical(p_numerator: int, p_denominator: int) -> void:
	_numerator = p_numerator
	_denominator = p_denominator


static func _greatest_common_divisor(left: int, right: int) -> int:
	var remainder := left % right
	var first := right
	var second := absi(remainder)
	while second != 0:
		var next := first % second
		first = second
		second = next
	return first
