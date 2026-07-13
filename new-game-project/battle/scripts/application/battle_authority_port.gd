class_name BattleAuthorityPort
extends RefCounted

signal result_ready(result: BattleStepResult)


func is_valid() -> bool:
	return false


func get_battle_id() -> StringName:
	return &""


func get_error() -> BattleError:
	return BattleError.create(
		BattleError.Category.LIFECYCLE,
		BattleError.AUTHORITY_NOT_CONFIGURED,
		BattleError.INVALID_CONTEXT_ID,
		BattleError.INVALID_CONTEXT_ID,
		BattleError.INVALID_CONTEXT_ID,
		BattleError.INVALID_CONTEXT_ID,
		&"direct_authority_port_constructor"
	)


func is_started() -> bool:
	return false


func is_busy() -> bool:
	return false


func is_finished() -> bool:
	return false


func is_shutdown() -> bool:
	return false


func start() -> BattleOperationResult:
	return BattleOperationResult.failure(get_error())


func submit_input(_step_input: BattleStepInput) -> BattleOperationResult:
	return BattleOperationResult.failure(get_error())


func shutdown() -> BattleOperationResult:
	return BattleOperationResult.failure(get_error())
