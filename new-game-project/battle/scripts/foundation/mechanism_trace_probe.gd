class_name MechanismTraceProbe
extends RefCounted

enum RecordKind {
	BRANCH = 1,
	STAGE = 2,
	RNG = 3,
	STATE_OP = 4,
}

enum RecordField {
	KIND = 0,
	SEQUENCE_NO = 1,
	TEST_ID = 2,
	FIXTURE_ID = 3,
	MECHANISM_ID = 4,
	BRANCH_ID = 5,
	STAGE_ID = 6,
	DRAW_ID = 7,
	STREAM_ID = 8,
	TAG_ID = 9,
	CURSOR_BEFORE = 10,
	CURSOR_AFTER = 11,
	OPCODE = 12,
	FIELD_COUNT = 13,
}

const NO_STABLE_ID: int = BattleStableId.INVALID_ID
const NO_CURSOR: int = -1
const DEFAULT_MAX_RECORDS: int = 4096
const MAX_RECORDS: int = 65_536

var _enabled := false
var _max_records := 0
var _records := PackedInt64Array()
var _record_count := 0
var _oldest_slot := 0
var _next_slot := 0
var _sequence_no := 0
var _dropped_count := 0
var _rejected_count := 0
var _scope_active := false
var _test_id := BattleStableId.INVALID_ID
var _fixture_id := BattleStableId.INVALID_ID
var _error: BattleError


func _init(
	p_enabled: bool = false,
	p_max_records: int = DEFAULT_MAX_RECORDS
) -> void:
	_enabled = p_enabled
	_error = BattleError.success()
	if not _enabled:
		return
	if p_max_records < 1 or p_max_records > MAX_RECORDS:
		_latch_error(BattleError.create(
			BattleError.Category.VALIDATION,
			BattleError.TRACE_INVALID_CAPACITY,
			BattleError.INVALID_CONTEXT_ID,
			BattleError.INVALID_CONTEXT_ID,
			p_max_records,
			BattleError.INVALID_CONTEXT_ID,
			&"max_records"
		))
		return
	_max_records = p_max_records
	_records.resize(_max_records * RecordField.FIELD_COUNT)


func begin_test(test_id: int, fixture_id: int) -> void:
	if not _enabled:
		return
	if _scope_active:
		_reject(BattleError.create(
			BattleError.Category.INTERNAL,
			BattleError.TRACE_SCOPE_ALREADY_ACTIVE,
			BattleError.INVALID_CONTEXT_ID,
			BattleError.INVALID_CONTEXT_ID,
			test_id,
			fixture_id,
			&"begin_test"
		))
		return
	if not BattleStableId.is_valid(test_id):
		_reject(BattleError.create(
			BattleError.Category.VALIDATION,
			BattleError.TRACE_INVALID_TEST_SCOPE,
			BattleError.INVALID_CONTEXT_ID,
			BattleError.INVALID_CONTEXT_ID,
			test_id,
			fixture_id,
			&"test_id"
		))
		return
	if fixture_id != BattleStableId.INVALID_ID and fixture_id != test_id:
		_reject(BattleError.create(
			BattleError.Category.VALIDATION,
			BattleError.TRACE_INVALID_TEST_SCOPE,
			BattleError.INVALID_CONTEXT_ID,
			BattleError.INVALID_CONTEXT_ID,
			test_id,
			fixture_id,
			&"fixture_id"
		))
		return
	_scope_active = true
	_test_id = test_id
	_fixture_id = fixture_id


func enter_branch(mechanism_id: int, branch_id: int) -> void:
	if not _enabled:
		return
	if not _require_scope(&"enter_branch"):
		return
	if not _validate_record_ids(mechanism_id, branch_id):
		return
	_append_record(
		RecordKind.BRANCH,
		mechanism_id,
		branch_id,
		NO_STABLE_ID,
		NO_STABLE_ID,
		NO_STABLE_ID,
		NO_STABLE_ID,
		NO_CURSOR,
		NO_CURSOR,
		NO_STABLE_ID
	)


func enter_stage(mechanism_id: int, branch_id: int, stage_id: int) -> void:
	if not _enabled:
		return
	if not _require_scope(&"enter_stage"):
		return
	if not _validate_record_ids(mechanism_id, branch_id):
		return
	if not _validate_stable_id(stage_id, &"stage_id", mechanism_id, stage_id):
		return
	_append_record(
		RecordKind.STAGE,
		mechanism_id,
		branch_id,
		stage_id,
		NO_STABLE_ID,
		NO_STABLE_ID,
		NO_STABLE_ID,
		NO_CURSOR,
		NO_CURSOR,
		NO_STABLE_ID
	)


func record_rng(
	mechanism_id: int,
	branch_id: int,
	draw_id: int,
	stream_id: int,
	tag_id: int,
	cursor_before: int,
	cursor_after: int
) -> void:
	if not _enabled:
		return
	if not _require_scope(&"record_rng"):
		return
	if not _validate_record_ids(mechanism_id, branch_id):
		return
	if not _validate_stable_id(draw_id, &"draw_id", mechanism_id):
		return
	if not _validate_stable_id(stream_id, &"stream_id", mechanism_id):
		return
	if not _validate_stable_id(tag_id, &"tag_id", mechanism_id):
		return
	if cursor_before < 0 or cursor_after <= cursor_before:
		_reject(BattleError.create(
			BattleError.Category.VALIDATION,
			BattleError.TRACE_INVALID_RNG_CURSOR,
			mechanism_id,
			BattleError.INVALID_CONTEXT_ID,
			cursor_before,
			cursor_after,
			&"rng_cursor"
		))
		return
	_append_record(
		RecordKind.RNG,
		mechanism_id,
		branch_id,
		NO_STABLE_ID,
		draw_id,
		stream_id,
		tag_id,
		cursor_before,
		cursor_after,
		NO_STABLE_ID
	)


func record_state_op(mechanism_id: int, branch_id: int, opcode: int) -> void:
	if not _enabled:
		return
	if not _require_scope(&"record_state_op"):
		return
	if not _validate_record_ids(mechanism_id, branch_id):
		return
	if not _validate_stable_id(opcode, &"opcode", mechanism_id):
		return
	_append_record(
		RecordKind.STATE_OP,
		mechanism_id,
		branch_id,
		NO_STABLE_ID,
		NO_STABLE_ID,
		NO_STABLE_ID,
		NO_STABLE_ID,
		NO_CURSOR,
		NO_CURSOR,
		opcode
	)


func end_test(test_id: int, fixture_id: int) -> void:
	if not _enabled:
		return
	if not _scope_active:
		_reject(BattleError.create(
			BattleError.Category.INTERNAL,
			BattleError.TRACE_SCOPE_REQUIRED,
			BattleError.INVALID_CONTEXT_ID,
			BattleError.INVALID_CONTEXT_ID,
			test_id,
			fixture_id,
			&"end_test"
		))
		return
	if test_id != _test_id or fixture_id != _fixture_id:
		_reject(BattleError.create(
			BattleError.Category.INTERNAL,
			BattleError.TRACE_SCOPE_MISMATCH,
			BattleError.INVALID_CONTEXT_ID,
			BattleError.INVALID_CONTEXT_ID,
			test_id,
			fixture_id,
			&"end_test"
		))
		_clear_scope()
		return
	_clear_scope()


func is_enabled() -> bool:
	return _enabled


func is_valid() -> bool:
	return not _error.is_error()


func has_active_scope() -> bool:
	return _scope_active


func max_records() -> int:
	return _max_records


func record_count() -> int:
	return _record_count


func dropped_count() -> int:
	return _dropped_count


func rejected_count() -> int:
	return _rejected_count


func get_error() -> BattleError:
	return _error.copy()


func records() -> PackedInt64Array:
	var snapshot := PackedInt64Array()
	if _record_count == 0:
		return snapshot
	snapshot.resize(_record_count * RecordField.FIELD_COUNT)
	for record_index in _record_count:
		var slot := (_oldest_slot + record_index) % _max_records
		var source_offset := slot * RecordField.FIELD_COUNT
		var target_offset := record_index * RecordField.FIELD_COUNT
		for field_index in RecordField.FIELD_COUNT:
			snapshot[target_offset + field_index] = _records[source_offset + field_index]
	return snapshot


func _require_scope(detail_key: StringName) -> bool:
	if _scope_active:
		return true
	_reject(BattleError.create(
		BattleError.Category.INTERNAL,
		BattleError.TRACE_SCOPE_REQUIRED,
		BattleError.INVALID_CONTEXT_ID,
		BattleError.INVALID_CONTEXT_ID,
		BattleError.INVALID_CONTEXT_ID,
		BattleError.INVALID_CONTEXT_ID,
		detail_key
	))
	return false


func _validate_record_ids(mechanism_id: int, branch_id: int) -> bool:
	if not _validate_stable_id(
		mechanism_id,
		&"mechanism_id",
		mechanism_id
	):
		return false
	return _validate_stable_id(
		branch_id,
		&"branch_id",
		mechanism_id,
		BattleError.INVALID_CONTEXT_ID,
		branch_id
	)


func _validate_stable_id(
	value: int,
	detail_key: StringName,
	mechanism_id: int = BattleError.INVALID_CONTEXT_ID,
	stage_id: int = BattleError.INVALID_CONTEXT_ID,
	source_id: int = BattleError.INVALID_CONTEXT_ID
) -> bool:
	if BattleStableId.is_valid(value):
		return true
	_reject(BattleError.create(
		BattleError.Category.VALIDATION,
		BattleError.TRACE_INVALID_RECORD_ID,
		mechanism_id,
		stage_id,
		value if source_id == BattleError.INVALID_CONTEXT_ID else source_id,
		BattleError.INVALID_CONTEXT_ID,
		detail_key
	))
	return false


func _append_record(
	kind: RecordKind,
	mechanism_id: int,
	branch_id: int,
	stage_id: int,
	draw_id: int,
	stream_id: int,
	tag_id: int,
	cursor_before: int,
	cursor_after: int,
	opcode: int
) -> void:
	if _max_records == 0:
		_dropped_count += 1
		_latch_error(BattleError.create(
			BattleError.Category.INTERNAL,
			BattleError.TRACE_CAPACITY_EXCEEDED,
			mechanism_id,
			stage_id,
			_dropped_count,
			BattleError.INVALID_CONTEXT_ID,
			&"trace_record_dropped"
		))
		return

	_sequence_no += 1
	var offset := _next_slot * RecordField.FIELD_COUNT
	_records[offset + RecordField.KIND] = kind
	_records[offset + RecordField.SEQUENCE_NO] = _sequence_no
	_records[offset + RecordField.TEST_ID] = _test_id
	_records[offset + RecordField.FIXTURE_ID] = _fixture_id
	_records[offset + RecordField.MECHANISM_ID] = mechanism_id
	_records[offset + RecordField.BRANCH_ID] = branch_id
	_records[offset + RecordField.STAGE_ID] = stage_id
	_records[offset + RecordField.DRAW_ID] = draw_id
	_records[offset + RecordField.STREAM_ID] = stream_id
	_records[offset + RecordField.TAG_ID] = tag_id
	_records[offset + RecordField.CURSOR_BEFORE] = cursor_before
	_records[offset + RecordField.CURSOR_AFTER] = cursor_after
	_records[offset + RecordField.OPCODE] = opcode
	_next_slot = (_next_slot + 1) % _max_records
	if _record_count < _max_records:
		_record_count += 1
		return
	_oldest_slot = (_oldest_slot + 1) % _max_records
	_dropped_count += 1
	_latch_error(BattleError.create(
		BattleError.Category.INTERNAL,
		BattleError.TRACE_CAPACITY_EXCEEDED,
		mechanism_id,
		stage_id,
		_dropped_count,
		BattleError.INVALID_CONTEXT_ID,
		&"trace_record_dropped"
	))


func _reject(error: BattleError) -> void:
	_rejected_count += 1
	_latch_error(error)


func _latch_error(error: BattleError) -> void:
	if _error.is_error():
		return
	_error = error.copy()


func _clear_scope() -> void:
	_scope_active = false
	_test_id = BattleStableId.INVALID_ID
	_fixture_id = BattleStableId.INVALID_ID
