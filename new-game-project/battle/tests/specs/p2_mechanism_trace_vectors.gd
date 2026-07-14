extends RefCounted

const TRACE_PROBE = preload(
	"res://battle/scripts/foundation/mechanism_trace_probe.gd"
)
const EXPECTED_CHECKS: int = 227

var _failures: Array[String] = []
var _checks := 0


func run() -> Array[String]:
	_test_disabled_probe()
	_test_record_layouts_and_scopes()
	_test_scope_rejections()
	_test_scope_lifecycle_errors()
	_test_record_validation()
	_test_capacity_and_snapshots()
	_test_deterministic_bytes()
	return _failures


func check_count() -> int:
	return _checks


func _test_disabled_probe() -> void:
	var probe := TRACE_PROBE.new(false, -1)
	probe.begin_test(0, 99)
	probe.enter_branch(0, 0)
	probe.enter_stage(0, 0, 0)
	probe.record_rng(0, 0, 0, 0, 0, -1, -2)
	probe.record_state_op(0, 0, 0)
	probe.end_test(0, 99)
	_expect(not probe.is_enabled(), "Disabled probe reported enabled.")
	_expect(probe.is_valid(), "Disabled probe validated ignored calls.")
	_expect(not probe.has_active_scope(), "Disabled probe opened a scope.")
	_expect(probe.max_records() == 0, "Disabled probe allocated capacity.")
	_expect(probe.record_count() == 0, "Disabled probe retained records.")
	_expect(probe.records().is_empty(), "Disabled probe returned record storage.")
	_expect(probe.dropped_count() == 0, "Disabled probe counted dropped records.")
	_expect(probe.rejected_count() == 0, "Disabled probe counted rejected calls.")
	_expect(not probe.get_error().is_error(), "Disabled probe exposed an error.")


func _test_record_layouts_and_scopes() -> void:
	var probe := TRACE_PROBE.new(true, 8)
	_expect(probe.is_enabled(), "Enabled probe reported disabled.")
	_expect(probe.is_valid(), "Valid enabled probe started with an error.")
	_expect(probe.max_records() == 8, "Enabled probe capacity changed.")
	probe.begin_test(101, 0)
	_expect(probe.has_active_scope(), "Unit-test scope did not open.")
	probe.enter_branch(1, 2)
	probe.enter_stage(1, 2, 3)
	probe.record_rng(1, 2, 4, 5, 6, 7, 8)
	probe.record_state_op(1, 2, 9)
	var expected := PackedInt64Array([
		TRACE_PROBE.RecordKind.BRANCH, 1, 101, 0, 1, 2, 0, 0, 0, 0, -1, -1, 0,
		TRACE_PROBE.RecordKind.STAGE, 2, 101, 0, 1, 2, 3, 0, 0, 0, -1, -1, 0,
		TRACE_PROBE.RecordKind.RNG, 3, 101, 0, 1, 2, 0, 4, 5, 6, 7, 8, 0,
		TRACE_PROBE.RecordKind.STATE_OP, 4, 101, 0, 1, 2, 0, 0, 0, 0, -1, -1, 9,
	])
	_expect(probe.record_count() == 4, "Four trace calls did not create four records.")
	_expect_packed(probe.records(), expected, "unit record layout")
	probe.end_test(101, 0)
	_expect(not probe.has_active_scope(), "Matching unit-test scope did not close.")
	_expect(probe.is_valid(), "Valid unit-test scope latched an error.")

	probe.begin_test(202, 202)
	probe.enter_branch(BattleStableId.MAX_VALID_ID, BattleStableId.MAX_VALID_ID)
	probe.end_test(202, 202)
	_expect(not probe.has_active_scope(), "Matching scenario scope did not close.")
	_expect(probe.record_count() == 5, "Scenario record was not appended.")
	var records := probe.records()
	var offset := 4 * TRACE_PROBE.RecordField.FIELD_COUNT
	_expect(records[offset + TRACE_PROBE.RecordField.SEQUENCE_NO] == 5, "Sequence did not continue across scopes.")
	_expect(records[offset + TRACE_PROBE.RecordField.TEST_ID] == 202, "Scenario test ID was not inherited.")
	_expect(records[offset + TRACE_PROBE.RecordField.FIXTURE_ID] == 202, "Scenario fixture ID was not inherited.")
	_expect(records[offset + TRACE_PROBE.RecordField.MECHANISM_ID] == BattleStableId.MAX_VALID_ID, "Maximum mechanism ID was rejected.")
	_expect(records[offset + TRACE_PROBE.RecordField.BRANCH_ID] == BattleStableId.MAX_VALID_ID, "Maximum branch ID was rejected.")


func _test_scope_rejections() -> void:
	_assert_scope_required(
		&"branch before begin",
		&"enter_branch",
		func(probe): probe.enter_branch(1, 2)
	)
	_assert_scope_required(
		&"stage before begin",
		&"enter_stage",
		func(probe): probe.enter_stage(1, 2, 3)
	)
	_assert_scope_required(
		&"rng before begin",
		&"record_rng",
		func(probe): probe.record_rng(1, 2, 3, 4, 5, 0, 1)
	)
	_assert_scope_required(
		&"state-op before begin",
		&"record_state_op",
		func(probe): probe.record_state_op(1, 2, 3)
	)
	_assert_scope_required_after_end(
		&"branch after end",
		&"enter_branch",
		func(probe): probe.enter_branch(1, 2)
	)
	_assert_scope_required_after_end(
		&"stage after end",
		&"enter_stage",
		func(probe): probe.enter_stage(1, 2, 3)
	)
	_assert_scope_required_after_end(
		&"rng after end",
		&"record_rng",
		func(probe): probe.record_rng(1, 2, 3, 4, 5, 0, 1)
	)
	_assert_scope_required_after_end(
		&"state-op after end",
		&"record_state_op",
		func(probe): probe.record_state_op(1, 2, 3)
	)


func _test_scope_lifecycle_errors() -> void:
	var invalid_test := TRACE_PROBE.new(true, 4)
	invalid_test.begin_test(0, 0)
	_expect(not invalid_test.has_active_scope(), "Invalid test ID opened a scope.")
	_expect_error(invalid_test, BattleError.TRACE_INVALID_TEST_SCOPE, &"test_id", "invalid test ID")

	var invalid_fixture := TRACE_PROBE.new(true, 4)
	invalid_fixture.begin_test(11, 12)
	_expect(not invalid_fixture.has_active_scope(), "Mismatched fixture ID opened a scope.")
	_expect_error(invalid_fixture, BattleError.TRACE_INVALID_TEST_SCOPE, &"fixture_id", "invalid fixture relation")

	var nested := TRACE_PROBE.new(true, 4)
	nested.begin_test(21, 0)
	nested.begin_test(22, 22)
	_expect(nested.has_active_scope(), "Nested begin cleared the original scope.")
	_expect_error(nested, BattleError.TRACE_SCOPE_ALREADY_ACTIVE, &"begin_test", "nested begin")
	nested.enter_branch(1, 2)
	var nested_records := nested.records()
	_expect(nested_records[TRACE_PROBE.RecordField.TEST_ID] == 21, "Nested begin replaced the test scope.")
	_expect(nested_records[TRACE_PROBE.RecordField.FIXTURE_ID] == 0, "Nested begin replaced the fixture scope.")
	nested.end_test(21, 0)
	_expect(not nested.has_active_scope(), "Original scope did not close after nested begin.")

	var missing := TRACE_PROBE.new(true, 4)
	missing.end_test(31, 0)
	_expect(not missing.has_active_scope(), "End without begin created a scope.")
	_expect_error(missing, BattleError.TRACE_SCOPE_REQUIRED, &"end_test", "end without begin")

	var mismatch := TRACE_PROBE.new(true, 4)
	mismatch.begin_test(41, 41)
	mismatch.end_test(42, 42)
	_expect(not mismatch.has_active_scope(), "Mismatched end did not clear scope for teardown.")
	_expect_error(mismatch, BattleError.TRACE_SCOPE_MISMATCH, &"end_test", "mismatched end")


func _test_record_validation() -> void:
	_assert_invalid_record_id(&"mechanism_id", func(probe): probe.enter_branch(0, 1))
	_assert_invalid_record_id(&"branch_id", func(probe): probe.enter_branch(1, 0))
	_assert_invalid_record_id(&"stage_id", func(probe): probe.enter_stage(1, 2, 0))
	_assert_invalid_record_id(&"draw_id", func(probe): probe.record_rng(1, 2, 0, 4, 5, 0, 1))
	_assert_invalid_record_id(&"stream_id", func(probe): probe.record_rng(1, 2, 3, 0, 5, 0, 1))
	_assert_invalid_record_id(&"tag_id", func(probe): probe.record_rng(1, 2, 3, 4, 0, 0, 1))
	_assert_invalid_record_id(&"opcode", func(probe): probe.record_state_op(1, 2, 0))
	_assert_invalid_cursor(-1, 0, "negative cursor")
	_assert_invalid_cursor(2, 1, "reversed cursor")
	_assert_invalid_cursor(6, 6, "unchanged cursor")

	var first_error := TRACE_PROBE.new(true, 4)
	first_error.begin_test(61, 0)
	first_error.enter_branch(0, 1)
	first_error.record_rng(1, 2, 3, 4, 5, -1, 0)
	_expect(first_error.rejected_count() == 2, "Rejected call counter did not accumulate.")
	_expect(first_error.get_error().detail_key == &"mechanism_id", "First trace error was not latched.")


func _test_capacity_and_snapshots() -> void:
	var exact := TRACE_PROBE.new(true, 2)
	exact.begin_test(71, 0)
	exact.enter_branch(1, 1)
	exact.enter_branch(1, 2)
	_expect(exact.is_valid(), "Exact trace capacity reported overflow.")
	_expect(exact.dropped_count() == 0, "Exact trace capacity dropped a record.")

	exact.enter_branch(1, 3)
	_expect(not exact.is_valid(), "Trace overflow did not invalidate coverage evidence.")
	_expect(exact.get_error().code == BattleError.TRACE_CAPACITY_EXCEEDED, "Trace overflow returned the wrong error.")
	_expect(exact.record_count() == 2, "Trace overflow changed bounded record count.")
	_expect(exact.dropped_count() == 1, "Trace overflow did not count the dropped record.")
	_expect(exact.rejected_count() == 0, "Trace overflow was misclassified as input rejection.")
	var window := exact.records()
	_expect(window[TRACE_PROBE.RecordField.SEQUENCE_NO] == 2, "Ring window did not retain the second record.")
	_expect(window[TRACE_PROBE.RecordField.BRANCH_ID] == 2, "Ring window oldest record changed.")
	var second_offset := TRACE_PROBE.RecordField.FIELD_COUNT
	_expect(window[second_offset + TRACE_PROBE.RecordField.SEQUENCE_NO] == 3, "Ring window did not retain the newest sequence.")
	_expect(window[second_offset + TRACE_PROBE.RecordField.BRANCH_ID] == 3, "Ring window newest record changed.")

	window[TRACE_PROBE.RecordField.BRANCH_ID] = 999
	var fresh := exact.records()
	_expect(fresh[TRACE_PROBE.RecordField.BRANCH_ID] == 2, "Record snapshot mutation escaped into probe storage.")
	var error_copy := exact.get_error()
	_expect(error_copy != exact.get_error(), "Probe returned its retained error instance.")
	error_copy.detail_key = &"mutated"
	_expect(exact.get_error().detail_key == &"trace_record_dropped", "Error copy mutation escaped into probe state.")

	var invalid_low := TRACE_PROBE.new(true, 0)
	_expect(not invalid_low.is_valid(), "Zero trace capacity was accepted.")
	_expect(invalid_low.max_records() == 0, "Invalid trace capacity allocated storage.")
	_expect_error(invalid_low, BattleError.TRACE_INVALID_CAPACITY, &"max_records", "zero capacity")
	var invalid_high := TRACE_PROBE.new(true, TRACE_PROBE.MAX_RECORDS + 1)
	_expect(not invalid_high.is_valid(), "Oversize trace capacity was accepted.")
	_expect_error(invalid_high, BattleError.TRACE_INVALID_CAPACITY, &"max_records", "oversize capacity")

	var single := TRACE_PROBE.new(true, 1)
	single.begin_test(72, 0)
	single.enter_branch(1, 1)
	single.enter_branch(1, 2)
	single.enter_branch(1, 3)
	var single_window := single.records()
	_expect(single.record_count() == 1, "Single-record ring changed capacity.")
	_expect(single.dropped_count() == 2, "Single-record ring drop count changed.")
	_expect(not single.is_valid(), "Single-record ring overflow remained valid.")
	_expect(
		single_window[TRACE_PROBE.RecordField.SEQUENCE_NO] == 3,
		"Single-record ring lost the newest sequence."
	)
	_expect(
		single_window[TRACE_PROBE.RecordField.BRANCH_ID] == 3,
		"Single-record ring lost the newest record."
	)
	single.end_test(72, 0)

	var wrapped := TRACE_PROBE.new(true, 2)
	wrapped.begin_test(73, 0)
	for branch_id in range(1, 6):
		wrapped.enter_branch(1, branch_id)
	var wrapped_window := wrapped.records()
	_expect(wrapped.record_count() == 2, "Repeated wraps changed bounded count.")
	_expect(wrapped.dropped_count() == 3, "Repeated wraps changed drop count.")
	_expect(
		wrapped_window[TRACE_PROBE.RecordField.SEQUENCE_NO] == 4,
		"Repeated wraps changed the oldest sequence."
	)
	_expect(
		wrapped_window[TRACE_PROBE.RecordField.BRANCH_ID] == 4,
		"Repeated wraps changed the oldest record."
	)
	var wrapped_second := TRACE_PROBE.RecordField.FIELD_COUNT
	_expect(
		wrapped_window[wrapped_second + TRACE_PROBE.RecordField.SEQUENCE_NO] == 5,
		"Repeated wraps lost the newest sequence."
	)
	_expect(
		wrapped_window[wrapped_second + TRACE_PROBE.RecordField.BRANCH_ID] == 5,
		"Repeated wraps lost the newest record."
	)
	wrapped.end_test(73, 0)


func _test_deterministic_bytes() -> void:
	var left := _build_deterministic_trace()
	var right := _build_deterministic_trace()
	_expect(left == right, "Identical trace calls produced different record bytes.")
	_expect(left.size() == 4 * TRACE_PROBE.RecordField.FIELD_COUNT, "Deterministic trace width changed.")


func _build_deterministic_trace() -> PackedInt64Array:
	var probe := TRACE_PROBE.new(true, 4)
	probe.begin_test(81, 81)
	probe.enter_branch(11, 12)
	probe.enter_stage(11, 12, 13)
	probe.record_rng(11, 12, 14, 15, 16, 17, 18)
	probe.record_state_op(11, 12, 19)
	probe.end_test(81, 81)
	return probe.records()


func _assert_scope_required(
	label: StringName,
	detail_key: StringName,
	action: Callable
) -> void:
	var probe := TRACE_PROBE.new(true, 2)
	action.call(probe)
	_expect(probe.record_count() == 0, "%s appended an out-of-scope record." % label)
	_expect(probe.rejected_count() == 1, "%s did not count one rejection." % label)
	_expect_error(probe, BattleError.TRACE_SCOPE_REQUIRED, detail_key, str(label))


func _assert_scope_required_after_end(
	label: StringName,
	detail_key: StringName,
	action: Callable
) -> void:
	var probe := TRACE_PROBE.new(true, 2)
	probe.begin_test(91, 0)
	probe.end_test(91, 0)
	action.call(probe)
	_expect(probe.record_count() == 0, "%s appended an out-of-scope record." % label)
	_expect(probe.rejected_count() == 1, "%s did not count one rejection." % label)
	_expect_error(probe, BattleError.TRACE_SCOPE_REQUIRED, detail_key, str(label))


func _assert_invalid_record_id(detail_key: StringName, action: Callable) -> void:
	var probe := TRACE_PROBE.new(true, 2)
	probe.begin_test(301, 0)
	action.call(probe)
	_expect(probe.record_count() == 0, "%s appended an invalid record." % detail_key)
	_expect(probe.rejected_count() == 1, "%s did not count one rejection." % detail_key)
	_expect_error(probe, BattleError.TRACE_INVALID_RECORD_ID, detail_key, str(detail_key))


func _assert_invalid_cursor(before: int, after: int, label: String) -> void:
	var probe := TRACE_PROBE.new(true, 2)
	probe.begin_test(401, 0)
	probe.record_rng(1, 2, 3, 4, 5, before, after)
	_expect(probe.record_count() == 0, "%s appended an invalid RNG record." % label)
	_expect(probe.rejected_count() == 1, "%s did not count one rejection." % label)
	_expect_error(probe, BattleError.TRACE_INVALID_RNG_CURSOR, &"rng_cursor", label)


func _expect_error(
	probe,
	code: StringName,
	detail_key: StringName,
	label: String
) -> void:
	var error: BattleError = probe.get_error()
	_expect(error.is_error(), "%s did not expose an error." % label)
	_expect(error.code == code, "%s returned the wrong error code." % label)
	_expect(error.detail_key == detail_key, "%s returned the wrong detail key." % label)


func _expect_packed(
	actual: PackedInt64Array,
	expected: PackedInt64Array,
	label: String
) -> void:
	_expect(actual.size() == expected.size(), "%s length changed." % label)
	var comparable := mini(actual.size(), expected.size())
	for index in comparable:
		_expect(actual[index] == expected[index], "%s field %d changed." % [label, index])


func _expect(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(message)
