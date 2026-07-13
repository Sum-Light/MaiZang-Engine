extends RefCounted

const EXPECTED_CHECKS: int = 164

var _failures: Array[String] = []
var _checks := 0


func run() -> Array[String]:
	_test_contract_versions()
	_test_error_and_stable_id()
	_test_integer_math()
	_test_fixed_ratio()
	_test_canonical_writer()
	_test_hash_vectors()
	return _failures


func check_count() -> int:
	return _checks


func _test_contract_versions() -> void:
	var versions: Array[int] = [
		BattleContractVersions.SCHEMA_VERSION,
		BattleContractVersions.CATALOG_VERSION,
		BattleContractVersions.PROFILE_VERSION,
		BattleContractVersions.HANDLER_VERSION,
		BattleContractVersions.FEATURE_VERSION,
		BattleContractVersions.SNAPSHOT_VERSION,
		BattleContractVersions.COMMAND_VERSION,
		BattleContractVersions.SAVE_VERSION,
		BattleContractVersions.FIXTURE_VERSION,
	]
	_expect(versions.size() == 9, "All nine contract version domains must be present.")
	for version in versions:
		_expect(version == 1, "Initial contract versions must be frozen at 1.")


func _test_error_and_stable_id() -> void:
	var error := BattleError.create(
		BattleError.Category.NUMERIC,
		BattleError.INTEGER_OVERFLOW,
		11,
		12,
		13,
		14,
		&"synthetic"
	)
	_expect(error.is_error(), "A numeric error must be distinguishable from success.")
	_expect(error.code == &"BATTLE_FOUNDATION_INTEGER_OVERFLOW", "Error code must be stable.")
	_expect(error.mechanism_id == 11, "Error mechanism diagnostic was not retained.")
	_expect(error.stage_id == 12, "Error stage diagnostic was not retained.")
	_expect(error.source_id == 13, "Error source diagnostic was not retained.")
	_expect(error.target_id == 14, "Error target diagnostic was not retained.")
	_expect(not BattleError.success().is_error(), "Success must not report an error.")
	var direct_error := BattleError.new()
	_expect(direct_error.is_error(), "Direct error construction must fail closed.")
	_expect(
		direct_error.code == BattleError.RESULT_CONTRACT_VIOLATION,
		"Direct error construction returned the wrong contract error."
	)
	var mismatched_error := BattleError.create(
		BattleError.Category.NONE,
		BattleError.INTEGER_OVERFLOW
	)
	_expect(mismatched_error.is_error(), "Mismatched error category/code was accepted.")
	_expect(
		mismatched_error.code == BattleError.RESULT_CONTRACT_VIOLATION,
		"Mismatched error category/code returned the wrong contract error."
	)
	var contradictory_result := BattleIntResult.failure(BattleError.success())
	_expect(not contradictory_result.is_ok, "Contradictory failure result became successful.")
	_expect(
		contradictory_result.error.code == BattleError.RESULT_CONTRACT_VIOLATION,
		"Contradictory failure result was not normalized."
	)
	var null_error_result := BattleIntResult.failure(null)
	_expect(not null_error_result.is_ok, "Null failure error became successful.")
	_expect(
		null_error_result.error.code == BattleError.RESULT_CONTRACT_VIOLATION,
		"Null failure error was not normalized."
	)
	var direct_result := BattleIntResult.new()
	_expect(not direct_result.is_ok, "Direct result construction must fail closed.")
	_expect(
		direct_result.error.code == BattleError.RESULT_CONTRACT_VIOLATION,
		"Direct result construction returned the wrong contract error."
	)

	_expect(BattleStableId.INVALID_ID == 0, "Stable ID zero must remain the invalid sentinel.")
	_expect(not BattleStableId.is_valid(0), "Invalid stable ID was accepted.")
	_expect(BattleStableId.is_valid(1), "Minimum stable ID was rejected.")
	_expect(
		BattleStableId.is_valid(BattleStableId.MAX_VALID_ID),
		"Maximum stable ID was rejected."
	)
	var invalid := BattleStableId.validate(BattleStableId.MAX_VALID_ID + 1)
	_expect(not invalid.is_ok, "Out-of-range stable ID must return a typed failure.")
	_expect(invalid.error.code == BattleError.INVALID_STABLE_ID, "Stable ID error code changed.")


func _test_integer_math() -> void:
	_expect_int(BattleIntMath.add_checked(2, 3), 5, "checked add")
	_expect_error(
		BattleIntMath.add_checked(BattleIntMath.MAX_INT, 1),
		BattleError.INTEGER_OVERFLOW,
		"positive add overflow"
	)
	_expect_error(
		BattleIntMath.add_checked(BattleIntMath.MIN_INT, -1),
		BattleError.INTEGER_OVERFLOW,
		"negative add overflow"
	)
	_expect_int(BattleIntMath.subtract_checked(2, 3), -1, "checked subtract")
	_expect_error(
		BattleIntMath.subtract_checked(BattleIntMath.MIN_INT, 1),
		BattleError.INTEGER_OVERFLOW,
		"subtract overflow"
	)
	_expect_int(BattleIntMath.multiply_checked(-7, 6), -42, "checked multiply")
	_expect_error(
		BattleIntMath.multiply_checked(BattleIntMath.MAX_INT, 2),
		BattleError.INTEGER_OVERFLOW,
		"positive multiply overflow"
	)
	_expect_error(
		BattleIntMath.multiply_checked(BattleIntMath.MIN_INT, -1),
		BattleError.INTEGER_OVERFLOW,
		"minimum integer multiply overflow"
	)
	_expect_int(
		BattleIntMath.multiply_checked(-4_611_686_018_427_387_904, 2),
		BattleIntMath.MIN_INT,
		"exact negative multiply boundary"
	)
	_expect_int(
		BattleIntMath.multiply_checked(-3_074_457_345_618_258_602, -3),
		9_223_372_036_854_775_806,
		"exact positive multiply boundary"
	)
	_expect_error(
		BattleIntMath.multiply_checked(-3_074_457_345_618_258_603, -3),
		BattleError.INTEGER_OVERFLOW,
		"negative by negative multiply overflow"
	)

	var modes: Array[BattleIntMath.RoundingMode] = [
		BattleIntMath.RoundingMode.FLOOR,
		BattleIntMath.RoundingMode.CEIL,
		BattleIntMath.RoundingMode.TOWARD_ZERO,
		BattleIntMath.RoundingMode.AWAY_FROM_ZERO,
		BattleIntMath.RoundingMode.NEAREST_TIES_DOWN,
		BattleIntMath.RoundingMode.NEAREST_TIES_UP,
	]
	var positive_expected: Array[int] = [2, 3, 2, 3, 2, 3]
	var negative_expected: Array[int] = [-3, -2, -2, -3, -3, -2]
	for index in modes.size():
		_expect_int(
			BattleIntMath.divide_checked(5, 2, modes[index]),
			positive_expected[index],
			"positive tie mode %d" % index
		)
		_expect_int(
			BattleIntMath.divide_checked(-5, 2, modes[index]),
			negative_expected[index],
			"negative tie mode %d" % index
		)
		_expect_int(
			BattleIntMath.divide_checked(6, 3, modes[index]),
			2,
			"exact division mode %d" % index
		)
	_expect_int(
		BattleIntMath.divide_checked(4, 3, BattleIntMath.RoundingMode.NEAREST_TIES_UP),
		1,
		"nearest below half"
	)
	_expect_int(
		BattleIntMath.divide_checked(5, 3, BattleIntMath.RoundingMode.NEAREST_TIES_DOWN),
		2,
		"nearest above half"
	)
	_expect_error(
		BattleIntMath.divide_checked(5, 0, BattleIntMath.RoundingMode.FLOOR),
		BattleError.INVALID_DENOMINATOR,
		"zero denominator"
	)
	_expect_error(
		BattleIntMath.divide_checked(5, -2, BattleIntMath.RoundingMode.FLOOR),
		BattleError.INVALID_DENOMINATOR,
		"negative denominator"
	)
	_expect_error(
		BattleIntMath.apply_ratio(
			BattleIntMath.MAX_INT,
			2,
			0,
			BattleIntMath.RoundingMode.FLOOR
		),
		BattleError.INVALID_DENOMINATOR,
		"ratio validates denominator before multiplication"
	)
	_expect_error(
		BattleIntMath.apply_ratio(BattleIntMath.MAX_INT, 2, 1, 99),
		BattleError.INVALID_ROUNDING_MODE,
		"ratio validates rounding before multiplication"
	)
	_expect_int(BattleIntMath.clamp_checked(9, 1, 5), 5, "checked clamp")
	_expect_error(
		BattleIntMath.clamp_checked(3, 5, 1),
		BattleError.INVALID_RANGE,
		"reversed clamp"
	)


func _test_fixed_ratio() -> void:
	var reduced := FixedRatio.create(2, 4)
	_expect(reduced.is_ok, "Reducible ratio must be accepted.")
	_expect(reduced.value.get_numerator() == 1, "Ratio numerator was not reduced.")
	_expect(reduced.value.get_denominator() == 2, "Ratio denominator was not reduced.")
	var negative := FixedRatio.create(-6, 8)
	_expect(negative.is_ok, "Negative ratio must be accepted.")
	_expect(negative.value.get_numerator() == -3, "Negative ratio numerator was not reduced.")
	_expect(negative.value.get_denominator() == 4, "Negative ratio denominator was not reduced.")
	var zero := FixedRatio.create(0, BattleIntMath.MAX_INT)
	_expect(zero.is_ok, "Zero ratio must be accepted.")
	_expect(zero.value.get_numerator() == 0, "Zero ratio numerator changed.")
	_expect(zero.value.get_denominator() == 1, "Zero ratio must use canonical denominator 1.")
	var default_ratio := FixedRatio.new()
	_expect(default_ratio.get_numerator() == 0, "Default ratio must be canonical zero.")
	_expect(default_ratio.get_denominator() == 1, "Default ratio denominator must be one.")
	var invalid := FixedRatio.create(1, 0)
	_expect(not invalid.is_ok, "Zero-denominator ratio must fail.")
	_expect(invalid.error.code == BattleError.INVALID_FIXED_RATIO, "Ratio error code changed.")
	var null_success := FixedRatioResult.success(null)
	_expect(not null_success.is_ok, "Null fixed-ratio success was accepted.")
	_expect(
		null_success.error.code == BattleError.RESULT_CONTRACT_VIOLATION,
		"Null fixed-ratio success returned the wrong contract error."
	)
	_expect_int(
		reduced.value.apply(15, BattleIntMath.RoundingMode.NEAREST_TIES_DOWN),
		7,
		"ratio positive ties down"
	)
	_expect_int(
		reduced.value.apply(15, BattleIntMath.RoundingMode.NEAREST_TIES_UP),
		8,
		"ratio positive ties up"
	)
	_expect_int(
		reduced.value.apply(-15, BattleIntMath.RoundingMode.NEAREST_TIES_DOWN),
		-8,
		"ratio negative ties down"
	)
	_expect_int(
		reduced.value.apply(-15, BattleIntMath.RoundingMode.NEAREST_TIES_UP),
		-7,
		"ratio negative ties up"
	)


func _test_canonical_writer() -> void:
	var writer := CanonicalWriter.new()
	_expect(writer.write_u8(0xab).is_ok, "Canonical u8 write failed.")
	_expect(writer.write_bool(true).is_ok, "Canonical true write failed.")
	_expect(writer.write_bool(false).is_ok, "Canonical false write failed.")
	_expect(writer.write_i64(-2).is_ok, "Canonical i64 write failed.")
	_expect(
		writer.write_bytes(PackedByteArray([0, 255])).is_ok,
		"Canonical bytes write failed."
	)
	var utf8_value := "A" + String.chr(0x03a9)
	_expect(writer.write_string(utf8_value).is_ok, "Canonical UTF-8 write failed.")
	var integers: Array[int] = [1, -1]
	_expect(writer.write_int_array(integers).is_ok, "Canonical int array write failed.")
	var byte_arrays: Array[PackedByteArray] = [
		PackedByteArray([1, 2]),
		PackedByteArray(),
	]
	_expect(writer.write_bytes_array(byte_arrays).is_ok, "Canonical bytes array write failed.")
	var strings: Array[String] = ["Z", ""]
	_expect(writer.write_string_array(strings).is_ok, "Canonical string array write failed.")
	var encoded := writer.finish()
	_expect(encoded.is_ok, "Canonical writer did not finish.")
	_expect(
		encoded.value.hex_encode() == (
			"ab0100fffffffffffffffe0000000200ff0000000341cea9"
			+ "000000020000000000000001ffffffffffffffff"
			+ "0000000200000002010200000000"
			+ "00000002000000015a00000000"
		),
		"Canonical golden bytes changed."
	)
	_expect(
		writer.finish().error.code == BattleError.CANONICAL_WRITER_SEALED,
		"Finishing a sealed writer must return a stable error."
	)
	_expect(
		not writer.write_u8(1).is_ok,
		"A sealed writer accepted another field."
	)
	var integer_boundaries := CanonicalWriter.new()
	integer_boundaries.write_i64(BattleIntMath.MIN_INT)
	integer_boundaries.write_i64(BattleIntMath.MAX_INT)
	var boundary_bytes := integer_boundaries.finish()
	_expect(boundary_bytes.is_ok, "Canonical integer boundary writer failed.")
	_expect(
		boundary_bytes.value.hex_encode()
			== "80000000000000007fffffffffffffff",
		"Canonical signed-64 boundary bytes changed."
	)

	var failing_writer := CanonicalWriter.new()
	_expect(failing_writer.write_i64(7).is_ok, "Failure setup write failed.")
	var oversized := PackedByteArray()
	oversized.resize(CanonicalWriter.MAX_SEQUENCE_LENGTH + 1)
	var oversized_result := failing_writer.write_bytes(oversized)
	_expect(not oversized_result.is_ok, "Oversized canonical bytes were accepted.")
	_expect(
		oversized_result.error.code == BattleError.CANONICAL_SEQUENCE_TOO_LARGE,
		"Oversized canonical bytes returned the wrong error."
	)
	var exposed_error := oversized_result.error
	exposed_error.category = BattleError.Category.NONE
	exposed_error.code = BattleError.OK
	oversized_result.is_ok = true
	oversized_result.error = BattleError.success()
	_expect(exposed_error.is_error(), "Public error properties were mutable.")
	_expect(not oversized_result.is_ok, "Public result status was mutable.")
	var failed_finish := failing_writer.finish()
	_expect(not failed_finish.is_ok, "Failed writer exposed partial canonical bytes.")
	_expect(failed_finish.value.is_empty(), "Failed writer result retained partial bytes.")
	_expect(
		failed_finish.error.code == BattleError.CANONICAL_SEQUENCE_TOO_LARGE,
		"Canonical writer did not retain its first error."
	)
	_expect(
		failing_writer.write_bool(true).error.code == BattleError.CANONICAL_SEQUENCE_TOO_LARGE,
		"Canonical writer did not remain failed."
	)


func _test_hash_vectors() -> void:
	var empty_hash := BattleHash.sha256_hex(PackedByteArray())
	_expect(empty_hash.is_ok, "SHA-256 empty vector failed.")
	_expect(
		empty_hash.value == "e3b0c44298fc1c149afbf4c8996fb924"
			+ "27ae41e4649b934ca495991b7852b855",
		"SHA-256 empty vector changed."
	)
	var abc_hash := BattleHash.sha256_hex("abc".to_utf8_buffer())
	_expect(abc_hash.is_ok, "SHA-256 abc vector failed.")
	_expect(
		abc_hash.value == "ba7816bf8f01cfea414140de5dae2223"
			+ "b00361a396177a9cb410ff61f20015ad",
		"SHA-256 abc vector changed."
	)
	var first := _build_repeatable_payload()
	var second := _build_repeatable_payload()
	_expect(first.is_ok and second.is_ok, "Repeatable canonical payload did not encode.")
	_expect(first.value == second.value, "Equivalent values produced different canonical bytes.")
	var first_hash := BattleHash.sha256_bytes(first.value)
	var second_hash := BattleHash.sha256_bytes(second.value)
	_expect(first_hash.is_ok and second_hash.is_ok, "Canonical payload hash failed.")
	_expect(first_hash.value == second_hash.value, "Equivalent canonical bytes hashed differently.")
	_expect(
		first_hash.value.size() == BattleHash.SHA256_BYTE_LENGTH,
		"SHA-256 digest length changed."
	)
	var exposed_digest := first_hash.value
	exposed_digest[0] = exposed_digest[0] ^ 0xff
	_expect(
		first_hash.value != exposed_digest,
		"Byte result exposed mutable internal storage."
	)


func _build_repeatable_payload() -> BattleBytesResult:
	var writer := CanonicalWriter.new()
	var values: Array[int] = [4, 2, 9]
	writer.write_string("P1")
	writer.write_i64(BattleContractVersions.SCHEMA_VERSION)
	writer.write_int_array(values)
	return writer.finish()


func _expect_int(result: BattleIntResult, expected: int, label: String) -> void:
	_expect(result.is_ok, "%s returned error %s." % [label, result.error.code])
	if result.is_ok:
		_expect(result.value == expected, "%s expected %d, got %d." % [
			label,
			expected,
			result.value,
		])


func _expect_error(result: BattleIntResult, code: StringName, label: String) -> void:
	_expect(not result.is_ok, "%s unexpectedly succeeded." % label)
	if not result.is_ok:
		_expect(result.error.code == code, "%s returned error %s." % [
			label,
			result.error.code,
		])


func _expect(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(message)
