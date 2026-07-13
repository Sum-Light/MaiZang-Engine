class_name BattleStableId
extends RefCounted

const INVALID_ID: int = 0
const MIN_VALID_ID: int = 1
const MAX_VALID_ID: int = 2_147_483_647


static func is_valid(value: int) -> bool:
	return value >= MIN_VALID_ID and value <= MAX_VALID_ID


static func validate(value: int, detail_key: StringName = &"stable_id") -> BattleOperationResult:
	if is_valid(value):
		return BattleOperationResult.success()
	return BattleOperationResult.failure(BattleError.create(
		BattleError.Category.VALIDATION,
		BattleError.INVALID_STABLE_ID,
		BattleError.INVALID_CONTEXT_ID,
		BattleError.INVALID_CONTEXT_ID,
		value,
		BattleError.INVALID_CONTEXT_ID,
		detail_key
	))
