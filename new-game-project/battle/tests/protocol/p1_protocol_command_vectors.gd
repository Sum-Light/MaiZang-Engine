extends RefCounted

const SYNTHETIC_PAYLOAD_GOLDEN_HEX := (
	"00000017424154544c455f4445434953494f4e5f5041594c4f4144"
	+ "0000000000000001000000000000000100000000000000010000000000000007"
)
const SYNTHETIC_PAYLOAD_GOLDEN_SHA256 := (
	"95429fc4803f092c08a9cc35589ed1e6e1f6f0acc6c73d5fc30f9fd386dc9a40"
)
const EMPTY_BATCH_GOLDEN_HEX := (
	"00000014424154544c455f434f4d4d414e445f4241544348"
	+ "000000000000000100"
)
const EMPTY_BATCH_GOLDEN_SHA256 := (
	"6e82e4d907a907f87d8029d0f53e356297a1d28b43c9a6e359538ddee7f5f886"
)
const FULL_BATCH_GOLDEN_SHA256 := (
	"592c08f55224c37137c28f512fb035397368e7c806d5a4d342a248f4ea980714"
)

class SyntheticPayload:
	extends BattleDecisionPayload

	var _option_id := BattleStableId.INVALID_ID


	func _init(
		p_option_id: int,
		p_kind: BattleDecisionPayload.Kind = BattleDecisionPayload.Kind.ACTION
	) -> void:
		if not BattleStableId.is_valid(p_option_id):
			_invalidate(BattleError.create(
				BattleError.Category.PROTOCOL,
				BattleError.PAYLOAD_REJECTED,
				BattleError.INVALID_CONTEXT_ID,
				BattleError.INVALID_CONTEXT_ID,
				p_option_id,
				BattleError.INVALID_CONTEXT_ID,
				&"synthetic_option_id"
			))
			return
		_option_id = p_option_id
		_configure_payload(p_kind, PAYLOAD_SCHEMA_VERSION)


	func get_option_id() -> int:
		return _option_id


	func copy_payload() -> BattleDecisionPayload:
		return SyntheticPayload.new(_option_id, get_kind())


	func _append_canonical_fields(writer: CanonicalWriter) -> BattleOperationResult:
		return writer.write_i64(_option_id)


class SyntheticRequest:
	extends BattleInputRequest

	const MAX_OPTIONS: int = 16
	var _option_ids: Array[int] = []


	func _init(
		p_battle_id: StringName,
		p_request_no: int,
		p_actor_id: int,
		p_kind: BattleDecisionPayload.Kind,
		p_candidate_digest: PackedByteArray,
		p_view_hash: PackedByteArray,
		p_option_ids: Array[int]
	) -> void:
		if not _validate_options(p_option_ids):
			_invalidate(BattleError.create(
				BattleError.Category.PROTOCOL,
				BattleError.INVALID_OPTION_SET,
				BattleError.INVALID_CONTEXT_ID,
				BattleError.INVALID_CONTEXT_ID,
				p_actor_id,
				BattleError.INVALID_CONTEXT_ID,
				&"synthetic_request_options"
			))
			return
		_option_ids = p_option_ids.duplicate()
		_configure_request(
			p_battle_id,
			p_request_no,
			p_actor_id,
			p_kind,
			p_candidate_digest,
			p_view_hash
		)


	func get_option_ids() -> Array[int]:
		return _option_ids.duplicate()


	func validate_payload(payload: BattleDecisionPayload) -> BattleOperationResult:
		var header := _validate_payload_header(payload)
		if not header.is_ok:
			return header
		if not payload is SyntheticPayload:
			return BattleOperationResult.failure(BattleError.create(
				BattleError.Category.PROTOCOL,
				BattleError.PAYLOAD_REJECTED,
				BattleError.INVALID_CONTEXT_ID,
				BattleError.INVALID_CONTEXT_ID,
				get_actor_id(),
				BattleError.INVALID_CONTEXT_ID,
				&"synthetic_payload_type"
			))
		var option_id := (payload as SyntheticPayload).get_option_id()
		if option_id not in _option_ids:
			return BattleOperationResult.failure(BattleError.create(
				BattleError.Category.PROTOCOL,
				BattleError.PAYLOAD_REJECTED,
				BattleError.INVALID_CONTEXT_ID,
				BattleError.INVALID_CONTEXT_ID,
				get_actor_id(),
				option_id,
				&"synthetic_option_not_offered"
			))
		return BattleOperationResult.success()


	func copy_request() -> BattleInputRequest:
		return SyntheticRequest.new(
			get_battle_id(),
			get_request_no(),
			get_actor_id(),
			get_kind(),
			get_candidate_digest(),
			get_view_hash(),
			_option_ids
		)


	func _append_canonical_fields(writer: CanonicalWriter) -> BattleOperationResult:
		return writer.write_int_array(_option_ids)


	func _validate_options(values: Array[int]) -> bool:
		if values.is_empty() or values.size() > MAX_OPTIONS:
			return false
		for index in values.size():
			if not BattleStableId.is_valid(values[index]):
				return false
			for previous_index in index:
				if values[previous_index] == values[index]:
					return false
		return true


class SyntheticCommand:
	extends BattleCommand

	var _argument := 0


	func _init(
		p_sequence_no: int,
		p_kind: BattleCommand.Kind,
		p_opcode: int,
		p_audience_id: int,
		p_argument: int,
		p_sync_policy: BattleCommand.SyncPolicy = BattleCommand.SyncPolicy.NO_WAIT,
		p_optional_visual: bool = false
	) -> void:
		_argument = p_argument
		_configure_command(
			p_sequence_no,
			p_kind,
			p_opcode,
			COMMAND_SCHEMA_VERSION,
			p_audience_id,
			p_sync_policy,
			p_optional_visual
		)


	func get_argument() -> int:
		return _argument


	func copy_command() -> BattleCommand:
		return SyntheticCommand.new(
			get_sequence_no(),
			get_kind(),
			get_opcode(),
			get_audience_id(),
			_argument,
			get_sync_policy(),
			is_optional_visual()
		)


	func _append_canonical_fields(writer: CanonicalWriter) -> BattleOperationResult:
		return writer.write_i64(_argument)


class AliasingPayload:
	extends BattleDecisionPayload


	func _init() -> void:
		_configure_payload(Kind.ACTION, PAYLOAD_SCHEMA_VERSION)


	func copy_payload() -> BattleDecisionPayload:
		return self


	func _append_canonical_fields(writer: CanonicalWriter) -> BattleOperationResult:
		return writer.write_i64(1)


class AliasingRequest:
	extends BattleInputRequest


	func _init(candidate_digest: PackedByteArray, view_hash: PackedByteArray) -> void:
		_configure_request(
			&"battle-alpha",
			5,
			3,
			BattleDecisionPayload.Kind.ACTION,
			candidate_digest,
			view_hash
		)


	func copy_request() -> BattleInputRequest:
		return self


	func _append_canonical_fields(writer: CanonicalWriter) -> BattleOperationResult:
		return writer.write_i64(1)


class AliasingCommand:
	extends BattleCommand


	func _init() -> void:
		_configure_command(
			1,
			Kind.CONTROL,
			101,
			COMMAND_SCHEMA_VERSION,
			1,
			SyncPolicy.NO_WAIT,
			false
		)


	func copy_command() -> BattleCommand:
		return self


	func _append_canonical_fields(writer: CanonicalWriter) -> BattleOperationResult:
		return writer.write_i64(1)


var _failures: Array[String] = []
var _checks := 0


func run() -> Array[String]:
	_test_fail_closed_bases()
	_test_payload_contract()
	_test_request_contract()
	_test_step_input_contract()
	_test_command_contract()
	_test_batch_contract()
	_test_step_result_contract()
	return _failures


func check_count() -> int:
	return _checks


func _test_fail_closed_bases() -> void:
	var payload := BattleDecisionPayload.new()
	_expect(not payload.is_valid(), "Direct decision payload must fail closed.")
	_expect(not payload.canonical_bytes().is_ok, "Invalid payload encoded canonical bytes.")
	var request := BattleInputRequest.new()
	_expect(not request.is_valid(), "Direct input request must fail closed.")
	_expect(not request.canonical_bytes().is_ok, "Invalid request encoded canonical bytes.")
	var command := BattleCommand.new()
	_expect(not command.is_valid(), "Direct command must fail closed.")
	_expect(not command.canonical_bytes().is_ok, "Invalid command encoded canonical bytes.")
	var step_input := BattleStepInput.new()
	_expect(not step_input.is_valid(), "Direct step input must fail closed.")
	var input_result := BattleStepInputBuildResult.new()
	_expect(not input_result.is_success(), "Direct input build result must fail closed.")
	var batch := BattleCommandBatch.new()
	_expect(not batch.is_valid(), "Direct command batch must fail closed.")
	var batch_result := BattleCommandBatchBuildResult.new()
	_expect(not batch_result.is_success(), "Direct batch build result must fail closed.")
	var step_result := BattleStepResult.new()
	_expect(
		step_result.get_kind() == BattleStepResult.Kind.FAILED,
		"Direct step result must normalize to FAILED."
	)
	_expect(step_result.get_error().is_error(), "Direct step result lost its error.")
	_expect(step_result.get_commands() != null, "Step result commands must never be null.")
	_expect(
		not step_result.get_commands().is_published(),
		"Direct step result must use the unpublished empty batch."
	)


func _test_payload_contract() -> void:
	var payload := SyntheticPayload.new(7)
	_expect(payload.is_valid(), "Synthetic decision payload was rejected.")
	_expect(payload.get_kind() == BattleDecisionPayload.Kind.ACTION, "Payload kind changed.")
	_expect(payload.get_payload_version() == 1, "Payload version changed.")
	var first := payload.canonical_bytes()
	var second := payload.canonical_bytes()
	_expect(first.is_ok and second.is_ok, "Payload canonical encoding failed.")
	_expect(first.value == second.value, "Payload canonical bytes were not repeatable.")
	var copied := payload.copy_payload()
	_expect(copied.is_valid(), "Payload copy was invalid.")
	_expect(
		copied.canonical_bytes().value == first.value,
		"Payload copy changed canonical bytes."
	)
	var hash_a := payload.canonical_hash()
	var hash_b := copied.canonical_hash()
	_expect(hash_a.is_ok and hash_b.is_ok, "Payload canonical hash failed.")
	_expect(hash_a.value == hash_b.value, "Payload copy changed canonical hash.")
	_expect(
		first.value.hex_encode() == SYNTHETIC_PAYLOAD_GOLDEN_HEX,
		"Payload canonical bytes drifted from the independent golden vector."
	)
	_expect(
		hash_a.value.hex_encode() == SYNTHETIC_PAYLOAD_GOLDEN_SHA256,
		"Payload canonical hash drifted from the independent golden vector."
	)
	var sealed_mutation := payload._invalidate(BattleError.contract_violation(
		&"synthetic_payload_mutation"
	))
	_expect(not sealed_mutation.is_ok, "Sealed payload accepted invalidation.")
	_expect(payload.is_valid(), "Sealed payload invalidation changed validity.")
	_expect(
		payload.canonical_bytes().value == first.value,
		"Sealed payload invalidation changed canonical bytes."
	)
	var invalid_option := SyntheticPayload.new(0)
	_expect(not invalid_option.is_valid(), "Invalid payload option was accepted.")
	var invalid_kind := SyntheticPayload.new(7, BattleDecisionPayload.Kind.INVALID)
	_expect(not invalid_kind.is_valid(), "Invalid payload kind was accepted.")


func _test_request_contract() -> void:
	var options: Array[int] = [7, 9]
	var candidate := _candidate_digest(BattleDecisionPayload.Kind.ACTION, options)
	var view_hash := _hash_text("view-a")
	var request := SyntheticRequest.new(
		&"battle-alpha",
		1,
		3,
		BattleDecisionPayload.Kind.ACTION,
		candidate,
		view_hash,
		options
	)
	_expect(request.is_valid(), "Synthetic input request was rejected.")
	options[0] = 11
	_expect(request.get_option_ids() == [7, 9], "Request retained the source option array.")
	var exposed_candidate := request.get_candidate_digest()
	exposed_candidate[0] = exposed_candidate[0] ^ 0xff
	_expect(
		request.get_candidate_digest() != exposed_candidate,
		"Request exposed mutable candidate digest storage."
	)
	var exposed_options := request.get_option_ids()
	exposed_options.clear()
	_expect(request.get_option_ids() == [7, 9], "Request exposed mutable option storage.")
	var encoded := request.canonical_bytes()
	var copied := request.copy_request()
	_expect(encoded.is_ok and copied.is_valid(), "Request copy or encoding failed.")
	_expect(
		copied.canonical_bytes().value == encoded.value,
		"Request copy changed canonical bytes."
	)
	_expect(request.validate_payload(SyntheticPayload.new(7)).is_ok, "Offered payload failed.")
	var rejected := request.validate_payload(SyntheticPayload.new(8))
	_expect(not rejected.is_ok, "Unoffered payload was accepted.")
	_expect(rejected.error.code == BattleError.PAYLOAD_REJECTED, "Wrong option error.")
	var wrong_kind := request.validate_payload(SyntheticPayload.new(
		7,
		BattleDecisionPayload.Kind.TARGET
	))
	_expect(not wrong_kind.is_ok, "Wrong payload kind was accepted.")
	_expect(
		wrong_kind.error.code == BattleError.PAYLOAD_KIND_MISMATCH,
		"Wrong payload-kind mismatch code."
	)
	_expect(
		not SyntheticRequest.new(
			&"",
			1,
			3,
			BattleDecisionPayload.Kind.ACTION,
			candidate,
			view_hash,
			[7]
		).is_valid(),
		"Empty battle ID was accepted."
	)
	_expect(
		not SyntheticRequest.new(
			&"battle-alpha",
			0,
			3,
			BattleDecisionPayload.Kind.ACTION,
			candidate,
			view_hash,
			[7]
		).is_valid(),
		"Request number zero was accepted."
	)
	_expect(
		not SyntheticRequest.new(
			&"battle-alpha",
			1,
			0,
			BattleDecisionPayload.Kind.ACTION,
			candidate,
			view_hash,
			[7]
		).is_valid(),
		"Invalid actor ID was accepted."
	)
	_expect(
		not SyntheticRequest.new(
			&"battle-alpha",
			1,
			3,
			BattleDecisionPayload.Kind.ACTION,
			PackedByteArray(),
			view_hash,
			[7]
		).is_valid(),
		"Wrong request digest length was accepted."
	)
	_expect(
		not SyntheticRequest.new(
			&"battle-alpha",
			1,
			3,
			BattleDecisionPayload.Kind.ACTION,
			candidate,
			view_hash,
			[7, 7]
		).is_valid(),
		"Duplicate request options were accepted."
	)


func _test_step_input_contract() -> void:
	var options: Array[int] = [7, 9]
	var candidate := _candidate_digest(BattleDecisionPayload.Kind.ACTION, options)
	var request := SyntheticRequest.new(
		&"battle-alpha",
		2,
		3,
		BattleDecisionPayload.Kind.ACTION,
		candidate,
		_hash_text("view-b"),
		options
	)
	var build := BattleStepInput.create(
		&"battle-alpha",
		2,
		3,
		candidate,
		SyntheticPayload.new(7)
	)
	_expect(build.is_success(), "Valid step input failed to build.")
	var input := build.get_value()
	_expect(input.is_valid(), "Built step input was invalid.")
	_expect(input.validate_against(request).is_ok, "Matching request/input was rejected.")
	var encoded := input.canonical_bytes()
	var copied := input.copy_input()
	_expect(encoded.is_ok and copied.is_valid(), "Step input copy or encoding failed.")
	_expect(copied.canonical_bytes().value == encoded.value, "Step input copy changed bytes.")
	_expect(input.canonical_hash().value == copied.canonical_hash().value, "Input hash changed.")
	var snapshot_result := BattleStepInputBuildResult.success(input)
	_expect(snapshot_result.is_success(), "Valid step input snapshot was rejected.")
	_expect(snapshot_result._value != input, "Step input build result retained caller identity.")
	var exposed := input.get_expected_candidate_digest()
	exposed[0] = exposed[0] ^ 0xff
	_expect(
		input.get_expected_candidate_digest() != exposed,
		"Step input exposed mutable digest storage."
	)
	_expect_mismatch(
		_make_input(&"other-battle", 2, 3, candidate, 7).validate_against(request),
		BattleError.BATTLE_ID_MISMATCH,
		"battle ID mismatch"
	)
	_expect_mismatch(
		_make_input(&"battle-alpha", 3, 3, candidate, 7).validate_against(request),
		BattleError.REQUEST_NO_MISMATCH,
		"request number mismatch"
	)
	_expect_mismatch(
		_make_input(&"battle-alpha", 2, 4, candidate, 7).validate_against(request),
		BattleError.ACTOR_ID_MISMATCH,
		"actor mismatch"
	)
	_expect_mismatch(
		_make_input(&"battle-alpha", 2, 3, _hash_text("wrong"), 7).validate_against(request),
		BattleError.CANDIDATE_DIGEST_MISMATCH,
		"candidate digest mismatch"
	)
	var wrong_kind_build := BattleStepInput.create(
		&"battle-alpha",
		2,
		3,
		candidate,
		SyntheticPayload.new(7, BattleDecisionPayload.Kind.TARGET)
	)
	_expect(wrong_kind_build.is_success(), "Wrong-kind input could not be represented.")
	_expect_mismatch(
		wrong_kind_build.get_value().validate_against(request),
		BattleError.PAYLOAD_KIND_MISMATCH,
		"payload kind mismatch"
	)
	var wrong_option := _make_input(&"battle-alpha", 2, 3, candidate, 8)
	var option_result := wrong_option.validate_against(request)
	_expect(not option_result.is_ok, "Unoffered step option was accepted.")
	_expect(option_result.error.code == BattleError.PAYLOAD_REJECTED, "Wrong option code.")
	_expect(
		not BattleStepInput.create(
			&"battle-alpha",
			2,
			3,
			PackedByteArray(),
			SyntheticPayload.new(7)
		).is_success(),
		"Step input accepted a wrong digest length."
	)
	_expect(
		not BattleStepInput.create(
			&"battle-alpha",
			2,
			3,
			candidate,
			null
		).is_success(),
		"Step input accepted null payload."
	)
	_expect(
		not BattleStepInput.create(
			&"battle-alpha", 2, 3, candidate, AliasingPayload.new()
		).is_success(),
		"Step input accepted a self-aliasing payload copy."
	)


func _test_command_contract() -> void:
	var command := SyntheticCommand.new(
		1,
		BattleCommand.Kind.CONTROL,
		101,
		1,
		44,
		BattleCommand.SyncPolicy.WAIT_AFTER
	)
	_expect(command.is_valid(), "Synthetic command was rejected.")
	_expect(command.get_sequence_no() == 1, "Command sequence changed.")
	_expect(command.get_kind() == BattleCommand.Kind.CONTROL, "Command kind changed.")
	_expect(command.get_opcode() == 101, "Command opcode changed.")
	_expect(command.get_argument() == 44, "Command payload field changed.")
	var encoded := command.canonical_bytes()
	var copied := command.copy_command()
	_expect(encoded.is_ok and copied.is_valid(), "Command copy or encoding failed.")
	_expect(copied.canonical_bytes().value == encoded.value, "Command copy changed bytes.")
	_expect(command.canonical_hash().value == copied.canonical_hash().value, "Command hash changed.")
	var sealed_mutation := command._invalidate(BattleError.contract_violation(
		&"synthetic_command_mutation"
	))
	_expect(not sealed_mutation.is_ok, "Sealed command accepted invalidation.")
	_expect(command.is_valid(), "Sealed command invalidation changed validity.")
	_expect(
		command.canonical_bytes().value == encoded.value,
		"Sealed command invalidation changed canonical bytes."
	)
	_expect(
		not SyntheticCommand.new(
			0,
			BattleCommand.Kind.CONTROL,
			101,
			1,
			44
		).is_valid(),
		"Command sequence zero was accepted."
	)
	_expect(
		not SyntheticCommand.new(
			1,
			BattleCommand.Kind.INVALID,
			101,
			1,
			44
		).is_valid(),
		"Invalid command kind was accepted."
	)
	_expect(
		not SyntheticCommand.new(
			1,
			BattleCommand.Kind.CONTROL,
			0,
			1,
			44
		).is_valid(),
		"Invalid command opcode was accepted."
	)
	_expect(
		not SyntheticCommand.new(
			1,
			BattleCommand.Kind.STATE_OP,
			101,
			1,
			44,
			BattleCommand.SyncPolicy.NO_WAIT,
			true
		).is_valid(),
		"Optional state operation was accepted."
	)


func _test_batch_contract() -> void:
	var unpublished := BattleCommandBatch.empty_unpublished()
	_expect(unpublished.is_valid(), "Empty unpublished batch was invalid.")
	_expect(not unpublished.is_published(), "Empty sentinel was published.")
	_expect(unpublished.get_commands().is_empty(), "Empty sentinel contained commands.")
	_expect(
		unpublished.canonical_bytes().value == unpublished.copy_batch().canonical_bytes().value,
		"Empty sentinel canonical bytes were unstable."
	)
	_expect(
		unpublished.canonical_bytes().value.hex_encode() == EMPTY_BATCH_GOLDEN_HEX,
		"Empty sentinel bytes drifted from the independent golden vector."
	)
	_expect(
		unpublished.canonical_hash().value.hex_encode() == EMPTY_BATCH_GOLDEN_SHA256,
		"Empty sentinel hash drifted from the independent golden vector."
	)
	var catalog_hash := _hash_text("catalog")
	var before_hash := _hash_text("view-before")
	var after_hash := _hash_text("view-after")
	var empty_build := BattleCommandBatch.create_published(
		&"battle-alpha",
		0,
		1,
		BattleContractVersions.CATALOG_VERSION,
		catalog_hash,
		false,
		PackedByteArray(),
		1,
		before_hash,
		after_hash,
		[]
	)
	_expect(empty_build.is_success(), "Published empty batch was rejected.")
	var empty_batch := empty_build.get_value()
	_expect(empty_batch.is_published(), "Published empty batch lost publication state.")
	_expect(empty_batch.get_commands().is_empty(), "Published empty batch gained commands.")
	var commands: Array[BattleCommand] = [
		SyntheticCommand.new(1, BattleCommand.Kind.CONTROL, 101, 1, 11),
		SyntheticCommand.new(
			2,
			BattleCommand.Kind.MESSAGE,
			102,
			1,
			22,
			BattleCommand.SyncPolicy.WAIT_AFTER,
			true
		),
	]
	var source_digest := _hash_text("accepted-input")
	var build := BattleCommandBatch.create_published(
		&"battle-alpha",
		17,
		3,
		BattleContractVersions.CATALOG_VERSION,
		catalog_hash,
		true,
		source_digest,
		1,
		before_hash,
		after_hash,
		commands
	)
	_expect(build.is_success(), "Ordered command batch was rejected.")
	var batch := build.get_value()
	_expect(batch.get_request_no() == 17, "Batch request number changed.")
	_expect(batch.get_battle_progress() == 3, "Batch progress changed.")
	var snapshot_result := BattleCommandBatchBuildResult.success(batch)
	_expect(snapshot_result.is_success(), "Valid command batch snapshot was rejected.")
	_expect(snapshot_result._value != batch, "Batch build result retained caller identity.")
	commands.clear()
	_expect(batch.get_commands().size() == 2, "Batch retained source command array.")
	var exposed := batch.get_commands()
	exposed.clear()
	_expect(batch.get_commands().size() == 2, "Batch exposed mutable command array.")
	var encoded := batch.canonical_bytes()
	var copied := batch.copy_batch()
	_expect(encoded.is_ok and copied.is_valid(), "Batch copy or encoding failed.")
	_expect(copied.canonical_bytes().value == encoded.value, "Batch copy changed bytes.")
	_expect(batch.canonical_hash().value == copied.canonical_hash().value, "Batch hash changed.")
	_expect(
		batch.canonical_hash().value.hex_encode() == FULL_BATCH_GOLDEN_SHA256,
		"Full batch field order drifted from the independent golden vector."
	)
	var gap_commands: Array[BattleCommand] = [
		SyntheticCommand.new(1, BattleCommand.Kind.CONTROL, 101, 1, 11),
		SyntheticCommand.new(3, BattleCommand.Kind.CONTROL, 102, 1, 22),
	]
	_expect(
		not BattleCommandBatch.create_published(
			&"battle-alpha", 2, 2, 1, catalog_hash, false, PackedByteArray(),
			1, before_hash, after_hash, gap_commands
		).is_success(),
		"Command sequence gap was accepted."
	)
	_expect(
		not BattleCommandBatch.create_published(
			&"battle-alpha", 2, 2, 1, PackedByteArray(), false,
			PackedByteArray(), 1, before_hash, after_hash, []
		).is_success(),
		"Wrong catalog hash length was accepted."
	)
	_expect(
		not BattleCommandBatch.create_published(
			&"battle-alpha", 2, 2, 1, catalog_hash, false, source_digest,
			1, before_hash, after_hash, []
		).is_success(),
		"Absent source digest carried bytes."
	)
	var oversized: Array[BattleCommand] = []
	oversized.resize(BattleCommandBatch.MAX_COMMANDS + 1)
	_expect(
		not BattleCommandBatch.create_published(
			&"battle-alpha", 2, 2, 1, catalog_hash, false,
			PackedByteArray(), 1, before_hash, after_hash, oversized
		).is_success(),
		"Oversized command batch was accepted."
	)
	var aliasing_commands: Array[BattleCommand] = [AliasingCommand.new()]
	_expect(
		not BattleCommandBatch.create_published(
			&"battle-alpha", 2, 2, 1, catalog_hash, false,
			PackedByteArray(), 1, before_hash, after_hash, aliasing_commands
		).is_success(),
		"Batch accepted a self-aliasing command copy."
	)
	var reversed: Array[BattleCommand] = [
		SyntheticCommand.new(1, BattleCommand.Kind.MESSAGE, 102, 1, 22),
		SyntheticCommand.new(2, BattleCommand.Kind.CONTROL, 101, 1, 11),
	]
	var reversed_batch := BattleCommandBatch.create_published(
		&"battle-alpha", 17, 3, 1, catalog_hash, true, source_digest,
		1, before_hash, after_hash, reversed
	)
	_expect(reversed_batch.is_success(), "Reordered valid batch failed to build.")
	_expect(
		reversed_batch.get_value().canonical_hash().value != batch.canonical_hash().value,
		"Command order did not change the batch hash."
	)


func _test_step_result_contract() -> void:
	var batch := _empty_published_batch(&"battle-alpha", 5)
	var authority_hash := _hash_text("authority")
	var complete := BattleStepResult.complete(batch, true, authority_hash)
	_expect(complete.get_kind() == BattleStepResult.Kind.COMPLETE, "Complete kind changed.")
	_expect(not complete.has_input_request(), "Complete carried an input request.")
	_expect(complete.get_input_request() == null, "Complete request getter was not null.")
	_expect(complete.get_commands().is_published(), "Complete commands were unpublished.")
	_expect(not complete.get_error().is_error(), "Complete carried an error.")
	_expect(complete.has_authority_hash(), "Complete lost authority hash presence.")
	_expect(
		complete.get_authority_state_hash_after() == authority_hash,
		"Complete authority hash changed."
	)
	var options: Array[int] = [7]
	var request := SyntheticRequest.new(
		&"battle-alpha",
		5,
		3,
		BattleDecisionPayload.Kind.ACTION,
		_candidate_digest(BattleDecisionPayload.Kind.ACTION, options),
		_hash_text("view-result"),
		options
	)
	var need_input := BattleStepResult.need_input(batch, request, false, PackedByteArray())
	_expect(need_input.get_kind() == BattleStepResult.Kind.NEED_INPUT, "Need-input kind changed.")
	_expect(need_input.has_input_request(), "Need-input lost its request.")
	_expect(need_input.get_commands().is_published(), "Need-input commands were unpublished.")
	_expect(not need_input.get_error().is_error(), "Need-input carried an error.")
	_expect(not need_input.has_authority_hash(), "Need-input gained authority hash presence.")
	_expect(
		need_input.get_authority_state_hash_after().is_empty(),
		"Need-input carried bytes without authority hash presence."
	)
	_expect(
		need_input.get_input_request().canonical_bytes().value
			== request.canonical_bytes().value,
		"Need-input request copy changed."
	)
	var failure_error := BattleError.create(
		BattleError.Category.ENGINE,
		&"BATTLE_ENGINE_SYNTHETIC_FAILURE",
		1,
		2,
		3,
		4,
		&"synthetic"
	)
	var failed := BattleStepResult.failed(
		BattleCommandBatch.empty_unpublished(),
		failure_error,
		false,
		PackedByteArray()
	)
	_expect(failed.get_kind() == BattleStepResult.Kind.FAILED, "Failed kind changed.")
	_expect(not failed.has_input_request(), "Failed result carried a request.")
	_expect(failed.get_input_request() == null, "Failed request getter was not null.")
	_expect(failed.get_error().code == failure_error.code, "Failed error changed.")
	_expect(failed.get_commands() != null, "Failed result commands were null.")
	_expect(not failed.has_authority_hash(), "Failed result gained authority hash presence.")
	_expect(
		failed.get_authority_state_hash_after().is_empty(),
		"Failed result carried bytes without authority hash presence."
	)
	var first := failed.canonical_bytes()
	var second := failed.copy_result().canonical_bytes()
	_expect(first.is_ok and second.is_ok, "Failed result canonical encoding failed.")
	_expect(first.value == second.value, "Failed result copy changed canonical bytes.")
	_expect(
		failed.canonical_hash().value == failed.copy_result().canonical_hash().value,
		"Failed result copy changed hash."
	)
	var invalid_complete := BattleStepResult.complete(
		BattleCommandBatch.empty_unpublished(),
		false,
		PackedByteArray()
	)
	_expect(
		invalid_complete.get_kind() == BattleStepResult.Kind.FAILED,
		"Invalid complete did not normalize to failure."
	)
	_expect(
		invalid_complete.get_error().code == BattleError.INVALID_STEP_RESULT,
		"Invalid complete returned the wrong error."
	)
	var invalid_failed := BattleStepResult.failed(
		BattleCommandBatch.empty_unpublished(),
		BattleError.success(),
		false,
		PackedByteArray()
	)
	_expect(
		invalid_failed.get_error().code == BattleError.INVALID_STEP_RESULT,
		"Failure with success error was accepted."
	)
	var wrong_battle_request := SyntheticRequest.new(
		&"other-battle",
		5,
		3,
		BattleDecisionPayload.Kind.ACTION,
		_candidate_digest(BattleDecisionPayload.Kind.ACTION, [7]),
		_hash_text("view-result"),
		[7]
	)
	var invalid_need := BattleStepResult.need_input(
		batch,
		wrong_battle_request,
		false,
		PackedByteArray()
	)
	_expect(
		invalid_need.get_error().code == BattleError.INVALID_STEP_RESULT,
		"Need-input battle mismatch was accepted."
	)
	var invalid_hash := BattleStepResult.complete(batch, true, PackedByteArray([1]))
	_expect(
		invalid_hash.get_error().code == BattleError.INVALID_STEP_RESULT,
		"Wrong authority hash length was accepted."
	)
	var absent_hash_with_bytes := BattleStepResult.complete(batch, false, authority_hash)
	_expect(
		absent_hash_with_bytes.get_error().code == BattleError.INVALID_STEP_RESULT,
		"Absent authority hash accepted hidden bytes."
	)
	var aliasing_request := AliasingRequest.new(
		_candidate_digest(BattleDecisionPayload.Kind.ACTION, [7]),
		_hash_text("view-result")
	)
	var aliasing_need := BattleStepResult.need_input(
		batch,
		aliasing_request,
		false,
		PackedByteArray()
	)
	_expect(
		aliasing_need.get_error().code == BattleError.INVALID_STEP_RESULT,
		"Need-input accepted a self-aliasing request copy."
	)
	_expect(
		BattleStepResult.Kind.BATTLE_ENDED == 3,
		"Reserved battle-ended discriminant changed."
	)


func _make_input(
	battle_id: StringName,
	request_no: int,
	actor_id: int,
	digest: PackedByteArray,
	option_id: int
) -> BattleStepInput:
	var build := BattleStepInput.create(
		battle_id,
		request_no,
		actor_id,
		digest,
		SyntheticPayload.new(option_id)
	)
	_expect(build.is_success(), "Mismatch fixture could not build step input.")
	return build.get_value()


func _empty_published_batch(battle_id: StringName, request_no: int) -> BattleCommandBatch:
	var build := BattleCommandBatch.create_published(
		battle_id,
		request_no,
		1,
		BattleContractVersions.CATALOG_VERSION,
		_hash_text("catalog-result"),
		false,
		PackedByteArray(),
		1,
		_hash_text("before-result"),
		_hash_text("after-result"),
		[]
	)
	_expect(build.is_success(), "Empty result batch failed to build.")
	return build.get_value()


func _candidate_digest(
	kind: BattleDecisionPayload.Kind,
	options: Array[int]
) -> PackedByteArray:
	var writer := CanonicalWriter.new()
	writer.write_string("SYNTHETIC_CANDIDATES")
	writer.write_i64(kind)
	writer.write_int_array(options)
	var encoded := writer.finish()
	return BattleHash.sha256_bytes(encoded.value).value


func _hash_text(value: String) -> PackedByteArray:
	return BattleHash.sha256_bytes(value.to_utf8_buffer()).value


func _expect_mismatch(
	result: BattleOperationResult,
	expected_code: StringName,
	label: String
) -> void:
	_expect(not result.is_ok, "%s unexpectedly succeeded." % label)
	if not result.is_ok:
		_expect(result.error.code == expected_code, "%s returned %s." % [
			label,
			result.error.code,
		])


func _expect(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(message)
