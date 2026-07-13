class_name BattleError
extends RefCounted

enum Category {
	NONE = 0,
	VALIDATION = 1,
	NUMERIC = 2,
	SERIALIZATION = 3,
	LIFECYCLE = 4,
	PROTOCOL = 5,
	ENGINE = 6,
	INTERNAL = 7,
}

const OK: StringName = &"BATTLE_OK"
const INVALID_STABLE_ID: StringName = &"BATTLE_FOUNDATION_INVALID_STABLE_ID"
const INTEGER_OVERFLOW: StringName = &"BATTLE_FOUNDATION_INTEGER_OVERFLOW"
const INVALID_DENOMINATOR: StringName = &"BATTLE_FOUNDATION_INVALID_DENOMINATOR"
const INVALID_ROUNDING_MODE: StringName = &"BATTLE_FOUNDATION_INVALID_ROUNDING_MODE"
const INVALID_RANGE: StringName = &"BATTLE_FOUNDATION_INVALID_RANGE"
const INVALID_FIXED_RATIO: StringName = &"BATTLE_FOUNDATION_INVALID_FIXED_RATIO"
const CANONICAL_BYTE_OUT_OF_RANGE: StringName = &"BATTLE_FOUNDATION_CANONICAL_BYTE_OUT_OF_RANGE"
const CANONICAL_SEQUENCE_TOO_LARGE: StringName = &"BATTLE_FOUNDATION_CANONICAL_SEQUENCE_TOO_LARGE"
const CANONICAL_WRITER_SEALED: StringName = &"BATTLE_FOUNDATION_CANONICAL_WRITER_SEALED"
const HASH_CONTEXT_FAILED: StringName = &"BATTLE_FOUNDATION_HASH_CONTEXT_FAILED"
const RESULT_CONTRACT_VIOLATION: StringName = &"BATTLE_FOUNDATION_RESULT_CONTRACT_VIOLATION"

const INVALID_CONTEXT_ID: int = -1

var _category: Category
var _code: StringName
var _mechanism_id: int
var _stage_id: int
var _source_id: int
var _target_id: int
var _detail_key: StringName

var category: Category:
	get:
		return _category
	set(_value):
		pass
var code: StringName:
	get:
		return _code
	set(_value):
		pass
var mechanism_id: int:
	get:
		return _mechanism_id
	set(_value):
		pass
var stage_id: int:
	get:
		return _stage_id
	set(_value):
		pass
var source_id: int:
	get:
		return _source_id
	set(_value):
		pass
var target_id: int:
	get:
		return _target_id
	set(_value):
		pass
var detail_key: StringName:
	get:
		return _detail_key
	set(_value):
		pass


func _init() -> void:
	_set_fields(
		Category.INTERNAL,
		RESULT_CONTRACT_VIOLATION,
		INVALID_CONTEXT_ID,
		INVALID_CONTEXT_ID,
		INVALID_CONTEXT_ID,
		INVALID_CONTEXT_ID,
		&"direct_error_constructor"
	)


static func success() -> BattleError:
	return _build(
		Category.NONE,
		OK,
		INVALID_CONTEXT_ID,
		INVALID_CONTEXT_ID,
		INVALID_CONTEXT_ID,
		INVALID_CONTEXT_ID,
		&""
	)


static func create(
	p_category: Category,
	p_code: StringName,
	p_mechanism_id: int = INVALID_CONTEXT_ID,
	p_stage_id: int = INVALID_CONTEXT_ID,
	p_source_id: int = INVALID_CONTEXT_ID,
	p_target_id: int = INVALID_CONTEXT_ID,
	p_detail_key: StringName = &""
) -> BattleError:
	if (
		(p_category == Category.NONE and p_code != OK)
		or (p_category != Category.NONE and p_code == OK)
		or p_code == &""
	):
		return contract_violation(&"error_category_code_mismatch")
	return _build(
		p_category,
		p_code,
		p_mechanism_id,
		p_stage_id,
		p_source_id,
		p_target_id,
		p_detail_key
	)


static func contract_violation(p_detail_key: StringName) -> BattleError:
	return _build(
		Category.INTERNAL,
		RESULT_CONTRACT_VIOLATION,
		INVALID_CONTEXT_ID,
		INVALID_CONTEXT_ID,
		INVALID_CONTEXT_ID,
		INVALID_CONTEXT_ID,
		p_detail_key
	)


func copy() -> BattleError:
	return _build(
		_category,
		_code,
		_mechanism_id,
		_stage_id,
		_source_id,
		_target_id,
		_detail_key
	)


func is_error() -> bool:
	return _category != Category.NONE


static func _build(
	p_category: Category,
	p_code: StringName,
	p_mechanism_id: int,
	p_stage_id: int,
	p_source_id: int,
	p_target_id: int,
	p_detail_key: StringName
) -> BattleError:
	var result := BattleError.new()
	result._set_fields(
		p_category,
		p_code,
		p_mechanism_id,
		p_stage_id,
		p_source_id,
		p_target_id,
		p_detail_key
	)
	return result


func _set_fields(
	p_category: Category,
	p_code: StringName,
	p_mechanism_id: int,
	p_stage_id: int,
	p_source_id: int,
	p_target_id: int,
	p_detail_key: StringName
) -> void:
	_category = p_category
	_code = p_code
	_mechanism_id = p_mechanism_id
	_stage_id = p_stage_id
	_source_id = p_source_id
	_target_id = p_target_id
	_detail_key = p_detail_key
