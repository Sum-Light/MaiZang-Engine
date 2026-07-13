class_name BattleHash
extends RefCounted

const SHA256_BYTE_LENGTH: int = 32
const SHA256_HEX_LENGTH: int = 64


static func sha256_bytes(payload: PackedByteArray) -> BattleBytesResult:
	var context := HashingContext.new()
	var start_error := context.start(HashingContext.HASH_SHA256)
	if start_error != OK:
		return BattleBytesResult.failure(_hash_error(&"start"))
	if not payload.is_empty():
		var update_error := context.update(payload)
		if update_error != OK:
			return BattleBytesResult.failure(_hash_error(&"update"))
	var digest := context.finish()
	if digest.size() != SHA256_BYTE_LENGTH:
		return BattleBytesResult.failure(_hash_error(&"digest_length"))
	return BattleBytesResult.success(digest)


static func sha256_hex(payload: PackedByteArray) -> BattleStringResult:
	var digest := sha256_bytes(payload)
	if not digest.is_ok:
		return BattleStringResult.failure(digest.error)
	var encoded := digest.value.hex_encode()
	if encoded.length() != SHA256_HEX_LENGTH:
		return BattleStringResult.failure(_hash_error(&"hex_length"))
	return BattleStringResult.success(encoded)


static func _hash_error(detail_key: StringName) -> BattleError:
	return BattleError.create(
		BattleError.Category.SERIALIZATION,
		BattleError.HASH_CONTEXT_FAILED,
		BattleError.INVALID_CONTEXT_ID,
		BattleError.INVALID_CONTEXT_ID,
		BattleError.INVALID_CONTEXT_ID,
		BattleError.INVALID_CONTEXT_ID,
		detail_key
	)
