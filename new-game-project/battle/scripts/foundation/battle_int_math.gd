class_name BattleIntMath
extends RefCounted

enum RoundingMode {
	FLOOR = 0,
	CEIL = 1,
	TOWARD_ZERO = 2,
	AWAY_FROM_ZERO = 3,
	NEAREST_TIES_DOWN = 4,
	NEAREST_TIES_UP = 5,
}

const MIN_INT: int = -9_223_372_036_854_775_807 - 1
const MAX_INT: int = 9_223_372_036_854_775_807


static func add_checked(left: int, right: int) -> BattleIntResult:
	if (
		(right > 0 and left > MAX_INT - right)
		or (right < 0 and left < MIN_INT - right)
	):
		return _overflow(&"add")
	return BattleIntResult.success(left + right)


static func subtract_checked(left: int, right: int) -> BattleIntResult:
	if (
		(right > 0 and left < MIN_INT + right)
		or (right < 0 and left > MAX_INT + right)
	):
		return _overflow(&"subtract")
	return BattleIntResult.success(left - right)


static func multiply_checked(left: int, right: int) -> BattleIntResult:
	if left == 0 or right == 0:
		return BattleIntResult.success(0)
	if (
		(left == MIN_INT and right == -1)
		or (right == MIN_INT and left == -1)
	):
		return _overflow(&"multiply")
	if left > 0:
		if (
			(right > 0 and left > MAX_INT / right)
			or (right < 0 and right < MIN_INT / left)
		):
			return _overflow(&"multiply")
	else:
		if (
			(right > 0 and left < MIN_INT / right)
			or (right < 0 and left < MAX_INT / right)
		):
			return _overflow(&"multiply")
	return BattleIntResult.success(left * right)


static func divide_checked(
	numerator: int,
	denominator: int,
	rounding: RoundingMode
) -> BattleIntResult:
	var validation := _validate_division_contract(denominator, rounding)
	if not validation.is_ok:
		return BattleIntResult.failure(validation.error)

	var quotient: int = numerator / denominator
	var remainder: int = numerator % denominator
	if remainder == 0:
		return BattleIntResult.success(quotient)

	match rounding:
		RoundingMode.FLOOR:
			return BattleIntResult.success(quotient - 1 if numerator < 0 else quotient)
		RoundingMode.CEIL:
			return BattleIntResult.success(quotient + 1 if numerator > 0 else quotient)
		RoundingMode.TOWARD_ZERO:
			return BattleIntResult.success(quotient)
		RoundingMode.AWAY_FROM_ZERO:
			return BattleIntResult.success(quotient + (1 if numerator > 0 else -1))
		RoundingMode.NEAREST_TIES_DOWN, RoundingMode.NEAREST_TIES_UP:
			return BattleIntResult.success(_round_nearest(
				quotient,
				remainder,
				denominator,
				rounding
			))
	return BattleIntResult.failure(BattleError.create(
		BattleError.Category.INTERNAL,
		BattleError.INVALID_ROUNDING_MODE,
		BattleError.INVALID_CONTEXT_ID,
		BattleError.INVALID_CONTEXT_ID,
		BattleError.INVALID_CONTEXT_ID,
		BattleError.INVALID_CONTEXT_ID,
		&"unreachable_rounding_mode"
	))


static func apply_ratio(
	value: int,
	numerator: int,
	denominator: int,
	rounding: RoundingMode
) -> BattleIntResult:
	var validation := _validate_division_contract(denominator, rounding)
	if not validation.is_ok:
		return BattleIntResult.failure(validation.error)
	var product := multiply_checked(value, numerator)
	if not product.is_ok:
		return product
	return divide_checked(product.value, denominator, rounding)


static func clamp_checked(value: int, minimum: int, maximum: int) -> BattleIntResult:
	if minimum > maximum:
		return BattleIntResult.failure(BattleError.create(
			BattleError.Category.NUMERIC,
			BattleError.INVALID_RANGE,
			BattleError.INVALID_CONTEXT_ID,
			BattleError.INVALID_CONTEXT_ID,
			BattleError.INVALID_CONTEXT_ID,
			BattleError.INVALID_CONTEXT_ID,
			&"minimum_exceeds_maximum"
		))
	return BattleIntResult.success(clampi(value, minimum, maximum))


static func _round_nearest(
	quotient: int,
	remainder: int,
	denominator: int,
	rounding: RoundingMode
) -> int:
	var magnitude := absi(remainder)
	var half: int = denominator / 2
	var is_tie := denominator % 2 == 0 and magnitude == half
	var is_above_half := magnitude > half
	if is_above_half:
		return quotient + (1 if remainder > 0 else -1)
	if not is_tie:
		return quotient
	if rounding == RoundingMode.NEAREST_TIES_DOWN:
		return quotient - 1 if remainder < 0 else quotient
	return quotient + 1 if remainder > 0 else quotient


static func _validate_division_contract(
	denominator: int,
	rounding: RoundingMode
) -> BattleOperationResult:
	if denominator <= 0:
		return BattleOperationResult.failure(BattleError.create(
			BattleError.Category.NUMERIC,
			BattleError.INVALID_DENOMINATOR,
			BattleError.INVALID_CONTEXT_ID,
			BattleError.INVALID_CONTEXT_ID,
			BattleError.INVALID_CONTEXT_ID,
			BattleError.INVALID_CONTEXT_ID,
			&"denominator_must_be_positive"
		))
	if rounding < RoundingMode.FLOOR or rounding > RoundingMode.NEAREST_TIES_UP:
		return BattleOperationResult.failure(BattleError.create(
			BattleError.Category.NUMERIC,
			BattleError.INVALID_ROUNDING_MODE,
			BattleError.INVALID_CONTEXT_ID,
			BattleError.INVALID_CONTEXT_ID,
			BattleError.INVALID_CONTEXT_ID,
			BattleError.INVALID_CONTEXT_ID,
			&"rounding_mode"
		))
	return BattleOperationResult.success()


static func _overflow(detail_key: StringName) -> BattleIntResult:
	return BattleIntResult.failure(BattleError.create(
		BattleError.Category.NUMERIC,
		BattleError.INTEGER_OVERFLOW,
		BattleError.INVALID_CONTEXT_ID,
		BattleError.INVALID_CONTEXT_ID,
		BattleError.INVALID_CONTEXT_ID,
		BattleError.INVALID_CONTEXT_ID,
		detail_key
	))
