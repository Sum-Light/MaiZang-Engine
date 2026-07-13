class_name BattleCommandBatch
extends RefCounted

const BATCH_SCHEMA_VERSION: int = 1
const CANONICAL_DOMAIN: String = "BATTLE_COMMAND_BATCH"
const MAX_BATTLE_ID_BYTES: int = 128
const MAX_COMMANDS: int = 4096
const NO_REQUEST: int = 0
const MAX_REQUEST_NO: int = BattleStableId.MAX_VALID_ID

var _is_valid := false
var _is_published := false
var _battle_id: StringName = &""
var _request_no := NO_REQUEST
var _battle_progress := 0
var _catalog_version := BattleContractVersions.CATALOG_VERSION
var _catalog_hash := PackedByteArray()
var _has_source_action_digest := false
var _source_action_digest := PackedByteArray()
var _audience_id := BattleStableId.INVALID_ID
var _view_hash_before := PackedByteArray()
var _view_hash_after := PackedByteArray()
var _commands: Array[BattleCommand] = []
var _error := BattleError.contract_violation(&"direct_command_batch_constructor")


static func empty_unpublished() -> BattleCommandBatch:
	var result := BattleCommandBatch.new()
	result._is_valid = true
	result._is_published = false
	result._error = BattleError.success()
	return result


static func create_published(
	p_battle_id: StringName,
	p_request_no: int,
	p_battle_progress: int,
	p_catalog_version: int,
	p_catalog_hash: PackedByteArray,
	p_has_source_action_digest: bool,
	p_source_action_digest: PackedByteArray,
	p_audience_id: int,
	p_view_hash_before: PackedByteArray,
	p_view_hash_after: PackedByteArray,
	p_commands: Array[BattleCommand]
) -> BattleCommandBatchBuildResult:
	var value := BattleCommandBatch.new()
	var configured := value._configure_published(
		p_battle_id,
		p_request_no,
		p_battle_progress,
		p_catalog_version,
		p_catalog_hash,
		p_has_source_action_digest,
		p_source_action_digest,
		p_audience_id,
		p_view_hash_before,
		p_view_hash_after,
		p_commands
	)
	if not configured.is_ok:
		return BattleCommandBatchBuildResult.failure(configured.error)
	return BattleCommandBatchBuildResult.success(value)


func is_valid() -> bool:
	return _is_valid


func is_published() -> bool:
	return _is_published


func get_battle_id() -> StringName:
	return _battle_id


func get_request_no() -> int:
	return _request_no


func get_battle_progress() -> int:
	return _battle_progress


func get_catalog_version() -> int:
	return _catalog_version


func get_catalog_hash() -> PackedByteArray:
	return _catalog_hash.duplicate()


func has_source_action_digest() -> bool:
	return _has_source_action_digest


func get_source_action_digest() -> PackedByteArray:
	return _source_action_digest.duplicate()


func get_audience_id() -> int:
	return _audience_id


func get_view_hash_before() -> PackedByteArray:
	return _view_hash_before.duplicate()


func get_view_hash_after() -> PackedByteArray:
	return _view_hash_after.duplicate()


func get_commands() -> Array[BattleCommand]:
	var result: Array[BattleCommand] = []
	result.resize(_commands.size())
	for index in _commands.size():
		var command_copy := _commands[index].copy_command()
		if (
			command_copy == null
			or command_copy == _commands[index]
			or not command_copy.is_valid()
		):
			return []
		result[index] = command_copy
	return result


func get_error() -> BattleError:
	return _error.copy()


func copy_batch() -> BattleCommandBatch:
	if not _is_valid:
		return BattleCommandBatch.new()
	if not _is_published:
		return empty_unpublished()
	var result := BattleCommandBatch.new()
	result._is_valid = true
	result._is_published = true
	result._battle_id = _battle_id
	result._request_no = _request_no
	result._battle_progress = _battle_progress
	result._catalog_version = _catalog_version
	result._catalog_hash = _catalog_hash.duplicate()
	result._has_source_action_digest = _has_source_action_digest
	result._source_action_digest = _source_action_digest.duplicate()
	result._audience_id = _audience_id
	result._view_hash_before = _view_hash_before.duplicate()
	result._view_hash_after = _view_hash_after.duplicate()
	result._commands = get_commands()
	if result._commands.size() != _commands.size():
		return BattleCommandBatch.new()
	result._error = BattleError.success()
	return result


func canonical_bytes() -> BattleBytesResult:
	if not _is_valid:
		return BattleBytesResult.failure(_error)
	var writer := CanonicalWriter.new()
	writer.write_string(CANONICAL_DOMAIN)
	writer.write_i64(BATCH_SCHEMA_VERSION)
	writer.write_bool(_is_published)
	if not _is_published:
		return writer.finish()
	writer.write_string(String(_battle_id))
	writer.write_i64(_request_no)
	writer.write_i64(_battle_progress)
	writer.write_i64(_catalog_version)
	writer.write_bytes(_catalog_hash)
	writer.write_bool(_has_source_action_digest)
	if _has_source_action_digest:
		writer.write_bytes(_source_action_digest)
	writer.write_i64(_audience_id)
	writer.write_bytes(_view_hash_before)
	writer.write_bytes(_view_hash_after)
	var command_bytes: Array[PackedByteArray] = []
	command_bytes.resize(_commands.size())
	for index in _commands.size():
		var encoded := _commands[index].canonical_bytes()
		if not encoded.is_ok:
			return encoded
		command_bytes[index] = encoded.value
	writer.write_bytes_array(command_bytes)
	return writer.finish()


func canonical_hash() -> BattleBytesResult:
	var encoded := canonical_bytes()
	if not encoded.is_ok:
		return encoded
	return BattleHash.sha256_bytes(encoded.value)


func _configure_published(
	p_battle_id: StringName,
	p_request_no: int,
	p_battle_progress: int,
	p_catalog_version: int,
	p_catalog_hash: PackedByteArray,
	p_has_source_action_digest: bool,
	p_source_action_digest: PackedByteArray,
	p_audience_id: int,
	p_view_hash_before: PackedByteArray,
	p_view_hash_after: PackedByteArray,
	p_commands: Array[BattleCommand]
) -> BattleOperationResult:
	if _is_valid:
		return BattleOperationResult.failure(BattleError.contract_violation(
			&"command_batch_is_sealed"
		))
	var battle_id_bytes := String(p_battle_id).to_utf8_buffer()
	if battle_id_bytes.is_empty() or battle_id_bytes.size() > MAX_BATTLE_ID_BYTES:
		return _invalidate(&"batch_battle_id")
	if (
		p_request_no < NO_REQUEST
		or p_request_no > MAX_REQUEST_NO
		or p_battle_progress < 1
		or p_battle_progress > BattleStableId.MAX_VALID_ID
	):
		return _invalidate(&"batch_sequence")
	if p_catalog_version != BattleContractVersions.CATALOG_VERSION:
		return _invalidate(&"batch_catalog_version")
	if (
		p_catalog_hash.size() != BattleHash.SHA256_BYTE_LENGTH
		or p_view_hash_before.size() != BattleHash.SHA256_BYTE_LENGTH
		or p_view_hash_after.size() != BattleHash.SHA256_BYTE_LENGTH
	):
		return _invalidate(&"batch_hash")
	if (
		(p_has_source_action_digest
			and p_source_action_digest.size() != BattleHash.SHA256_BYTE_LENGTH)
		or (not p_has_source_action_digest and not p_source_action_digest.is_empty())
	):
		return _invalidate(&"batch_source_action_digest")
	var audience_validation := BattleStableId.validate(
		p_audience_id,
		&"batch_audience_id"
	)
	if not audience_validation.is_ok:
		return _fail(audience_validation.error)
	if p_commands.size() > MAX_COMMANDS:
		return _invalidate(&"batch_command_count")

	var copied_commands: Array[BattleCommand] = []
	copied_commands.resize(p_commands.size())
	for index in p_commands.size():
		var command := p_commands[index]
		if (
			command == null
			or not command.is_valid()
			or command.get_sequence_no() != index + 1
		):
			return _invalidate(&"batch_command_sequence")
		var command_copy := command.copy_command()
		if command_copy == null or command_copy == command or not command_copy.is_valid():
			return _invalidate(&"batch_command_copy")
		var original_bytes := command.canonical_bytes()
		var copied_bytes := command_copy.canonical_bytes()
		if (
			not original_bytes.is_ok
			or not copied_bytes.is_ok
			or original_bytes.value != copied_bytes.value
		):
			return _invalidate(&"batch_command_copy_mismatch")
		copied_commands[index] = command_copy

	_is_valid = true
	_is_published = true
	_battle_id = p_battle_id
	_request_no = p_request_no
	_battle_progress = p_battle_progress
	_catalog_version = p_catalog_version
	_catalog_hash = p_catalog_hash.duplicate()
	_has_source_action_digest = p_has_source_action_digest
	_source_action_digest = p_source_action_digest.duplicate()
	_audience_id = p_audience_id
	_view_hash_before = p_view_hash_before.duplicate()
	_view_hash_after = p_view_hash_after.duplicate()
	_commands = copied_commands
	_error = BattleError.success()
	return BattleOperationResult.success()


func _invalidate(detail_key: StringName) -> BattleOperationResult:
	return _fail(BattleError.create(
		BattleError.Category.PROTOCOL,
		BattleError.INVALID_COMMAND_BATCH,
		BattleError.INVALID_CONTEXT_ID,
		BattleError.INVALID_CONTEXT_ID,
		BattleError.INVALID_CONTEXT_ID,
		BattleError.INVALID_CONTEXT_ID,
		detail_key
	))


func _fail(p_error: BattleError) -> BattleOperationResult:
	if _is_valid:
		return BattleOperationResult.failure(BattleError.contract_violation(
			&"command_batch_is_sealed"
		))
	_is_valid = false
	_is_published = false
	_battle_id = &""
	_request_no = NO_REQUEST
	_battle_progress = 0
	_catalog_version = BattleContractVersions.CATALOG_VERSION
	_catalog_hash = PackedByteArray()
	_has_source_action_digest = false
	_source_action_digest = PackedByteArray()
	_audience_id = BattleStableId.INVALID_ID
	_view_hash_before = PackedByteArray()
	_view_hash_after = PackedByteArray()
	_commands.clear()
	_error = (
		p_error.copy()
		if p_error != null and p_error.is_error()
		else BattleError.contract_violation(&"batch_invalidation_requires_error")
	)
	return BattleOperationResult.failure(_error)
