class_name CanonicalWriter
extends RefCounted

const MAX_SEQUENCE_LENGTH: int = 1_048_576

var _bytes := PackedByteArray()
var _error := BattleError.success()
var _has_failed := false
var _sealed := false


func write_u8(value: int) -> BattleOperationResult:
	var ready := _require_writable()
	if not ready.is_ok:
		return ready
	if value < 0 or value > 0xff:
		return _fail(BattleError.create(
			BattleError.Category.SERIALIZATION,
			BattleError.CANONICAL_BYTE_OUT_OF_RANGE,
			BattleError.INVALID_CONTEXT_ID,
			BattleError.INVALID_CONTEXT_ID,
			BattleError.INVALID_CONTEXT_ID,
			BattleError.INVALID_CONTEXT_ID,
			&"u8"
		))
	_bytes.append(value)
	return BattleOperationResult.success()


func write_bool(value: bool) -> BattleOperationResult:
	var ready := _require_writable()
	if not ready.is_ok:
		return ready
	_bytes.append(1 if value else 0)
	return BattleOperationResult.success()


func write_i64(value: int) -> BattleOperationResult:
	var ready := _require_writable()
	if not ready.is_ok:
		return ready
	_append_i64(value)
	return BattleOperationResult.success()


func write_bytes(value: PackedByteArray) -> BattleOperationResult:
	var ready := _require_writable()
	if not ready.is_ok:
		return ready
	var validation := _validate_length(value.size(), &"bytes")
	if not validation.is_ok:
		return validation
	_append_u32(value.size())
	_bytes.append_array(value)
	return BattleOperationResult.success()


func write_string(value: String) -> BattleOperationResult:
	var ready := _require_writable()
	if not ready.is_ok:
		return ready
	var encoded := value.to_utf8_buffer()
	var validation := _validate_length(encoded.size(), &"string_utf8")
	if not validation.is_ok:
		return validation
	_append_u32(encoded.size())
	_bytes.append_array(encoded)
	return BattleOperationResult.success()


func write_int_array(values: Array[int]) -> BattleOperationResult:
	var ready := _require_writable()
	if not ready.is_ok:
		return ready
	var validation := _validate_length(values.size(), &"int_array")
	if not validation.is_ok:
		return validation
	_append_u32(values.size())
	for value in values:
		_append_i64(value)
	return BattleOperationResult.success()


func write_bytes_array(values: Array[PackedByteArray]) -> BattleOperationResult:
	var ready := _require_writable()
	if not ready.is_ok:
		return ready
	var validation := _validate_length(values.size(), &"bytes_array")
	if not validation.is_ok:
		return validation
	for value in values:
		validation = _validate_length(value.size(), &"bytes_array_item")
		if not validation.is_ok:
			return validation
	_append_u32(values.size())
	for value in values:
		_append_u32(value.size())
		_bytes.append_array(value)
	return BattleOperationResult.success()


func write_string_array(values: Array[String]) -> BattleOperationResult:
	var ready := _require_writable()
	if not ready.is_ok:
		return ready
	var validation := _validate_length(values.size(), &"string_array")
	if not validation.is_ok:
		return validation
	var encoded_values: Array[PackedByteArray] = []
	encoded_values.resize(values.size())
	for index in values.size():
		var encoded := values[index].to_utf8_buffer()
		validation = _validate_length(encoded.size(), &"string_array_item_utf8")
		if not validation.is_ok:
			return validation
		encoded_values[index] = encoded
	_append_u32(encoded_values.size())
	for encoded in encoded_values:
		_append_u32(encoded.size())
		_bytes.append_array(encoded)
	return BattleOperationResult.success()


func finish() -> BattleBytesResult:
	if _has_failed:
		return BattleBytesResult.failure(_error)
	if _sealed:
		return BattleBytesResult.failure(BattleError.create(
			BattleError.Category.SERIALIZATION,
			BattleError.CANONICAL_WRITER_SEALED,
			BattleError.INVALID_CONTEXT_ID,
			BattleError.INVALID_CONTEXT_ID,
			BattleError.INVALID_CONTEXT_ID,
			BattleError.INVALID_CONTEXT_ID,
			&"finish"
		))
	_sealed = true
	return BattleBytesResult.success(_bytes)


func _validate_length(value: int, detail_key: StringName) -> BattleOperationResult:
	if value <= MAX_SEQUENCE_LENGTH:
		return BattleOperationResult.success()
	return _fail(BattleError.create(
		BattleError.Category.SERIALIZATION,
		BattleError.CANONICAL_SEQUENCE_TOO_LARGE,
		BattleError.INVALID_CONTEXT_ID,
		BattleError.INVALID_CONTEXT_ID,
		BattleError.INVALID_CONTEXT_ID,
		BattleError.INVALID_CONTEXT_ID,
		detail_key
	))


func _require_writable() -> BattleOperationResult:
	if _has_failed:
		return BattleOperationResult.failure(_error)
	if _sealed:
		return BattleOperationResult.failure(BattleError.create(
			BattleError.Category.SERIALIZATION,
			BattleError.CANONICAL_WRITER_SEALED,
			BattleError.INVALID_CONTEXT_ID,
			BattleError.INVALID_CONTEXT_ID,
			BattleError.INVALID_CONTEXT_ID,
			BattleError.INVALID_CONTEXT_ID,
			&"write"
		))
	return BattleOperationResult.success()


func _fail(error: BattleError) -> BattleOperationResult:
	_has_failed = true
	_error = error.copy()
	return BattleOperationResult.failure(error)


func _append_u32(value: int) -> void:
	for shift in [24, 16, 8, 0]:
		_bytes.append((value >> shift) & 0xff)


func _append_i64(value: int) -> void:
	for shift in [56, 48, 40, 32, 24, 16, 8, 0]:
		_bytes.append((value >> shift) & 0xff)
