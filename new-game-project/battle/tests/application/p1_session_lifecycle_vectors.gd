extends RefCounted

const EMPTY_ENGINE_STATE_SHA256 := (
	"05fbbd378f1dbeb6e03f9aaa86367fe566d8eedc6246e2643ab80479048a7a77"
)
const EMPTY_ENGINE_RESULT_SHA256 := (
	"08acb1f7c632cfa9423243bb234fda92d1c36d0c906bf724975c1a4517946b0d"
)
const EXPECTED_CHECKS: int = 270


class SyntheticPayload:
	extends BattleDecisionPayload

	var _option_id := BattleStableId.INVALID_ID


	func _init(p_option_id: int) -> void:
		if not BattleStableId.is_valid(p_option_id):
			_invalidate(BattleError.contract_violation(&"synthetic_option"))
			return
		_option_id = p_option_id
		_configure_payload(Kind.ACTION, PAYLOAD_SCHEMA_VERSION)


	func get_option_id() -> int:
		return _option_id


	func copy_payload() -> BattleDecisionPayload:
		return SyntheticPayload.new(_option_id)


	func _append_canonical_fields(writer: CanonicalWriter) -> BattleOperationResult:
		return writer.write_i64(_option_id)


class SyntheticRequest:
	extends BattleInputRequest

	var _option_id := BattleStableId.INVALID_ID


	func _init(
		battle_id: StringName,
		request_no: int,
		candidate_digest: PackedByteArray,
		view_hash: PackedByteArray,
		option_id: int
	) -> void:
		_option_id = option_id
		_configure_request(
			battle_id,
			request_no,
			3,
			BattleDecisionPayload.Kind.ACTION,
			candidate_digest,
			view_hash
		)


	func validate_payload(payload: BattleDecisionPayload) -> BattleOperationResult:
		var header := _validate_payload_header(payload)
		if not header.is_ok:
			return header
		if not payload is SyntheticPayload:
			return BattleOperationResult.failure(BattleError.contract_violation(
				&"synthetic_payload_type"
			))
		if (payload as SyntheticPayload).get_option_id() != _option_id:
			return BattleOperationResult.failure(BattleError.create(
				BattleError.Category.PROTOCOL,
				BattleError.PAYLOAD_REJECTED,
				BattleError.INVALID_CONTEXT_ID,
				BattleError.INVALID_CONTEXT_ID,
				3,
				_option_id,
				&"synthetic_option_not_offered"
			))
		return BattleOperationResult.success()


	func copy_request() -> BattleInputRequest:
		return SyntheticRequest.new(
			get_battle_id(),
			get_request_no(),
			get_candidate_digest(),
			get_view_hash(),
			_option_id
		)


	func _append_canonical_fields(writer: CanonicalWriter) -> BattleOperationResult:
		return writer.write_i64(_option_id)


class SyntheticEngine:
	extends BattleEngine

	var step_count := 0
	var shutdown_count := 0
	var _battle_id: StringName


	func _init(p_battle_id: StringName) -> void:
		_battle_id = p_battle_id


	func _step_impl(step_input: BattleStepInput) -> BattleStepResult:
		step_count += 1
		var triggering_request := 0 if step_input == null else step_input.get_request_no()
		var batch_build := BattleCommandBatch.create_published(
			_battle_id,
			triggering_request,
			step_count,
			BattleContractVersions.CATALOG_VERSION,
			_hash_text("synthetic-catalog"),
			step_input != null,
			PackedByteArray() if step_input == null else step_input.canonical_hash().value,
			1,
			_hash_text("synthetic-before-%d" % step_count),
			_hash_text("synthetic-after-%d" % step_count),
			[]
		)
		if not batch_build.is_success():
			return BattleStepResult.failed(
				BattleCommandBatch.empty_unpublished(),
				batch_build.get_error(),
				false,
				PackedByteArray()
			)
		var candidate_digest := _candidate_digest(7)
		var request := SyntheticRequest.new(
			_battle_id,
			step_count,
			candidate_digest,
			_hash_text("synthetic-view-%d" % step_count),
			7
		)
		return BattleStepResult.need_input(
			batch_build.get_value(),
			request,
			true,
			_hash_text("synthetic-authority-%d" % step_count)
		)


	func shutdown() -> BattleOperationResult:
		if not is_shutdown():
			shutdown_count += 1
		return super.shutdown()


	func _candidate_digest(option_id: int) -> PackedByteArray:
		var writer := CanonicalWriter.new()
		writer.write_string("P1_SESSION_CANDIDATE")
		writer.write_i64(BattleDecisionPayload.Kind.ACTION)
		writer.write_i64(option_id)
		return BattleHash.sha256_bytes(writer.finish().value).value


	func _hash_text(value: String) -> PackedByteArray:
		return BattleHash.sha256_bytes(value.to_utf8_buffer()).value


class ReentrantProbeEngine:
	extends BattleEngine

	var implementation_count := 0
	var inner_error_code: StringName = &""


	func _step_impl(step_input: BattleStepInput) -> BattleStepResult:
		implementation_count += 1
		inner_error_code = step(null).get_error().code
		return super._step_impl(step_input)


class CopyReentryProbe:
	extends RefCounted

	var _engine_ref: WeakRef
	var inner_error_code: StringName = &""


	func _init(engine: BattleEngine) -> void:
		_engine_ref = weakref(engine)


	func trigger() -> void:
		var engine := _engine_ref.get_ref() as BattleEngine
		inner_error_code = engine.step(null).get_error().code


class ReentrantCanonicalBatch:
	extends BattleCommandBatch

	var _probe: CopyReentryProbe


	func _init(probe: CopyReentryProbe) -> void:
		_probe = probe


	func is_valid() -> bool:
		return true


	func is_published() -> bool:
		return false


	func copy_batch() -> BattleCommandBatch:
		return BattleCommandBatch.empty_unpublished()


	func canonical_bytes() -> BattleBytesResult:
		_probe.trigger()
		return BattleCommandBatch.empty_unpublished().canonical_bytes()


class ReentrantCopyEngine:
	extends BattleEngine

	var implementation_count := 0
	var probe: CopyReentryProbe


	func _init() -> void:
		probe = CopyReentryProbe.new(self)


	func _step_impl(step_input: BattleStepInput) -> BattleStepResult:
		implementation_count += 1
		var result := super._step_impl(step_input)
		result._commands = ReentrantCanonicalBatch.new(probe)
		return result


class ForgedStepResult:
	extends BattleStepResult

	enum Mode {
		ENDED_WITHOUT_OUTCOME = 1,
		COMPLETE_WITH_UNPUBLISHED = 2,
	}

	var _mode: Mode


	func _init(mode: Mode) -> void:
		_mode = mode
		_kind = (
			Kind.BATTLE_ENDED
			if mode == Mode.ENDED_WITHOUT_OUTCOME
			else Kind.COMPLETE
		)
		_commands = BattleCommandBatch.empty_unpublished()
		_input_request = null
		_error = BattleError.success()
		_has_authority_hash = false
		_authority_state_hash_after = PackedByteArray()


	func copy_result() -> BattleStepResult:
		return ForgedStepResult.new(_mode)


class ForgedResultEngine:
	extends BattleEngine

	var _mode: ForgedStepResult.Mode


	func _init(mode: ForgedStepResult.Mode) -> void:
		_mode = mode


	func _step_impl(_step_input: BattleStepInput) -> BattleStepResult:
		return ForgedStepResult.new(_mode)


class LyingForgedStepResult:
	extends ForgedStepResult


	func validate() -> BattleOperationResult:
		return BattleOperationResult.success()


	func is_valid() -> bool:
		return true


	func copy_result() -> BattleStepResult:
		return LyingForgedStepResult.new(_mode)


class LyingResultEngine:
	extends BattleEngine


	func _step_impl(_step_input: BattleStepInput) -> BattleStepResult:
		return LyingForgedStepResult.new(
			ForgedStepResult.Mode.ENDED_WITHOUT_OUTCOME
		)


class ScriptedAuthority:
	extends BattleAuthorityPort

	var _battle_id: StringName
	var _started := false
	var _shutdown := false
	var shutdown_count := 0


	func _init(p_battle_id: StringName) -> void:
		_battle_id = p_battle_id


	func is_valid() -> bool:
		return true


	func get_battle_id() -> StringName:
		return _battle_id


	func get_error() -> BattleError:
		return BattleError.success()


	func is_started() -> bool:
		return _started


	func is_shutdown() -> bool:
		return _shutdown


	func start() -> BattleOperationResult:
		_started = true
		emit_progress(1)
		emit_progress(2)
		return BattleOperationResult.success()


	func submit_input(_step_input: BattleStepInput) -> BattleOperationResult:
		return BattleOperationResult.failure(BattleError.contract_violation(
			&"scripted_authority_rejects_input"
		))


	func shutdown() -> BattleOperationResult:
		if not _shutdown:
			shutdown_count += 1
		_shutdown = true
		return BattleOperationResult.success()


	func emit_progress(progress: int) -> void:
		if _shutdown:
			return
		var batch_build := BattleCommandBatch.create_published(
			_battle_id,
			0,
			progress,
			BattleContractVersions.CATALOG_VERSION,
			_hash_text("fifo-catalog"),
			false,
			PackedByteArray(),
			1,
			_hash_text("fifo-before-%d" % progress),
			_hash_text("fifo-after-%d" % progress),
			[]
		)
		result_ready.emit(BattleStepResult.complete(
			batch_build.get_value(),
			true,
			_hash_text("fifo-authority-%d" % progress)
		))


	func _hash_text(value: String) -> PackedByteArray:
		return BattleHash.sha256_bytes(value.to_utf8_buffer()).value


class AuthorityReentryProbe:
	extends RefCounted

	var _authority_ref: WeakRef
	var callback_count := 0
	var start_code: StringName = &""
	var submit_code: StringName = &""
	var shutdown_code: StringName = &""


	func _init(authority: LocalBattleAuthority) -> void:
		_authority_ref = weakref(authority)


	func on_result(_result: BattleStepResult) -> void:
		callback_count += 1
		if callback_count != 1:
			return
		var authority := _authority_ref.get_ref() as LocalBattleAuthority
		start_code = authority.start().error.code
		submit_code = authority.submit_input(null).error.code
		shutdown_code = authority.shutdown().error.code


class FailingShutdownAuthority:
	extends ScriptedAuthority


	func shutdown() -> BattleOperationResult:
		if not _shutdown:
			shutdown_count += 1
		_shutdown = true
		return BattleOperationResult.failure(BattleError.create(
			BattleError.Category.LIFECYCLE,
			BattleError.AUTHORITY_SHUTDOWN,
			BattleError.INVALID_CONTEXT_ID,
			BattleError.INVALID_CONTEXT_ID,
			BattleError.INVALID_CONTEXT_ID,
			BattleError.INVALID_CONTEXT_ID,
			&"synthetic_shutdown_failure"
		))


class SessionReentryProbe:
	extends RefCounted

	var _session_ref: WeakRef
	var _input: BattleStepInput
	var callback_count := 0
	var pump_code: StringName = &""
	var close_code: StringName = &""
	var submit_ok := false
	var duplicate_submit_code: StringName = &""


	func _init(session: BattleSession, step_input: BattleStepInput) -> void:
		_session_ref = weakref(session)
		_input = step_input.copy_input()


	func on_result(_result: BattleStepResult) -> void:
		callback_count += 1
		if callback_count != 1:
			return
		var session := _session_ref.get_ref() as BattleSession
		pump_code = session.pump().error.code
		close_code = session.close().error.code
		submit_ok = session.submit_input(_input).is_ok
		duplicate_submit_code = session.submit_input(_input).error.code


class SessionStartReentryProbe:
	extends RefCounted

	var _session_ref: WeakRef
	var callback_count := 0
	var start_code: StringName = &""
	var close_code: StringName = &""


	func _init(session: BattleSession) -> void:
		_session_ref = weakref(session)


	func on_result(_result: BattleStepResult) -> void:
		callback_count += 1
		var session := _session_ref.get_ref() as BattleSession
		start_code = session.start().error.code
		close_code = session.close().error.code


class FifoProbe:
	extends RefCounted

	var _authority_ref: WeakRef
	var progress_values: Array[int] = []
	var depth := 0
	var max_depth := 0


	func _init(authority: ScriptedAuthority) -> void:
		_authority_ref = weakref(authority)


	func on_result(result: BattleStepResult) -> void:
		depth += 1
		max_depth = maxi(max_depth, depth)
		var progress := result.get_commands().get_battle_progress()
		progress_values.append(progress)
		if progress == 1:
			var authority := _authority_ref.get_ref() as ScriptedAuthority
			authority.emit_progress(3)
		depth -= 1


class ResultCodeProbe:
	extends RefCounted

	var callback_count := 0
	var codes: Array[StringName] = []


	func on_result(result: BattleStepResult) -> void:
		callback_count += 1
		codes.append(result.get_error().code)


class AliasingStepResult:
	extends BattleStepResult


	func _init(template: BattleStepResult) -> void:
		_kind = template.get_kind()
		_commands = template.get_commands()
		_input_request = template.get_input_request()
		_error = template.get_error()
		_has_authority_hash = template.has_authority_hash()
		_authority_state_hash_after = template.get_authority_state_hash_after()


	func copy_result() -> BattleStepResult:
		return self


var _failures: Array[String] = []
var _checks := 0


func run() -> Array[String]:
	_test_empty_engine()
	_test_engine_reentry()
	_test_step_result_truth_boundary()
	_test_local_authority()
	_test_protocol_error_categories()
	_test_session_start_dispatch_guard()
	_test_session_inbox()
	_test_session_fifo_and_alias_rejection()
	_test_terminal_late_result()
	_test_release_graphs()
	return _failures


func check_count() -> int:
	return _checks


func _test_empty_engine() -> void:
	var first_engine := BattleEngine.new()
	var second_engine := BattleEngine.new()
	var first := first_engine.step(null)
	var repeated := first_engine.step(null)
	var independent := second_engine.step(null)
	_expect(first.get_kind() == BattleStepResult.Kind.FAILED, "Empty engine did not fail.")
	_expect(first.get_error().code == BattleError.ENGINE_NOT_CONFIGURED, "Wrong empty error.")
	_expect(first.get_commands() != null, "Empty engine returned null commands.")
	_expect(first.get_commands().is_valid(), "Empty engine returned invalid commands.")
	_expect(not first.get_commands().is_published(), "Empty failure published a batch.")
	_expect(first.has_authority_hash(), "Empty failure omitted authority hash.")
	_expect(first.get_authority_state_hash_after().size() == 32, "Wrong empty state hash size.")
	_expect(
		first.get_authority_state_hash_after().hex_encode() == EMPTY_ENGINE_STATE_SHA256,
		"Empty authority state hash drifted from the independent golden."
	)
	_expect(first != repeated and first != independent, "Empty engine reused result identity.")
	_expect(
		first.canonical_bytes().value == repeated.canonical_bytes().value,
		"Repeated empty step changed canonical result."
	)
	_expect(
		first.canonical_hash().value == independent.canonical_hash().value,
		"Independent empty engines produced different result hashes."
	)
	_expect(
		first.canonical_hash().value.hex_encode() == EMPTY_ENGINE_RESULT_SHA256,
		"Empty engine result drifted from the independent golden."
	)
	var unexpected_input := first_engine.step(BattleStepInput.new())
	_expect(
		unexpected_input.get_error().code == BattleError.ENGINE_INPUT_NOT_EXPECTED,
		"Empty engine did not distinguish unexpected input."
	)
	_expect(
		unexpected_input.get_authority_state_hash_after()
			== first.get_authority_state_hash_after(),
		"Unexpected input changed empty authority state."
	)
	_expect(first_engine.shutdown().is_ok, "Empty engine shutdown failed.")
	_expect(first_engine.shutdown().is_ok, "Empty engine shutdown was not idempotent.")
	var after_shutdown := first_engine.step(null)
	_expect(after_shutdown.get_error().code == BattleError.ENGINE_SHUTDOWN, "Closed engine stepped.")


func _test_engine_reentry() -> void:
	var engine := ReentrantProbeEngine.new()
	var outer := engine.step(null)
	_expect(engine.implementation_count == 1, "Engine reentry reran implementation.")
	_expect(
		engine.inner_error_code == BattleError.ENGINE_REENTRANT_STEP,
		"Inner engine reentry returned wrong error."
	)
	_expect(outer.get_error().code == BattleError.ENGINE_NOT_CONFIGURED, "Outer step changed.")
	_expect(not engine.is_stepping(), "Engine remained in stepping state.")

	var copy_engine := ReentrantCopyEngine.new()
	var copy_outer := copy_engine.step(null)
	_expect(copy_engine.implementation_count == 1, "Canonical reentry reran implementation.")
	_expect(
		copy_engine.probe.inner_error_code == BattleError.ENGINE_REENTRANT_STEP,
		"Result canonicalization escaped the engine reentry guard."
	)
	_expect(
		copy_outer.get_error().code == BattleError.ENGINE_NOT_CONFIGURED,
		"Copy reentry changed outer result."
	)
	_expect(not copy_engine.is_stepping(), "Copy validation left engine locked.")


func _test_step_result_truth_boundary() -> void:
	var ended := ForgedStepResult.new(ForgedStepResult.Mode.ENDED_WITHOUT_OUTCOME)
	var complete := ForgedStepResult.new(ForgedStepResult.Mode.COMPLETE_WITH_UNPUBLISHED)
	_expect(not ended.is_valid(), "Ended result without outcome was valid.")
	_expect(not complete.is_valid(), "Complete result accepted unpublished batch.")
	_expect(not ended.canonical_bytes().is_ok, "Forged ended result encoded.")
	var ended_engine := ForgedResultEngine.new(ForgedStepResult.Mode.ENDED_WITHOUT_OUTCOME)
	var complete_engine := ForgedResultEngine.new(
		ForgedStepResult.Mode.COMPLETE_WITH_UNPUBLISHED
	)
	_expect(
		ended_engine.step(null).get_error().code == BattleError.ENGINE_INVALID_RESULT,
		"Engine accepted forged ended result."
	)
	_expect(
		complete_engine.step(null).get_error().code == BattleError.ENGINE_INVALID_RESULT,
		"Engine accepted forged complete result."
	)
	var lying := LyingForgedStepResult.new(
		ForgedStepResult.Mode.ENDED_WITHOUT_OUTCOME
	)
	_expect(lying.validate().is_ok, "Lying result fixture did not override validate.")
	_expect(
		not BattleStepResult.validate_instance(lying).is_ok,
		"Static StepResult validator accepted lying subtype."
	)
	_expect(not lying.canonical_bytes().is_ok, "Lying result encoded canonical bytes.")
	_expect(
		LyingResultEngine.new().step(null).get_error().code
			== BattleError.ENGINE_INVALID_RESULT,
		"Engine accepted lying forged result."
	)


func _test_local_authority() -> void:
	var base_port := BattleAuthorityPort.new()
	_expect(not base_port.is_valid(), "Direct authority port was valid.")
	_expect(not base_port.start().is_ok, "Direct authority port started.")
	var invalid := LocalBattleAuthority.create(&"", null)
	_expect(not invalid.is_valid(), "Invalid local authority was accepted.")
	_expect(not invalid.shutdown().is_ok, "Invalid local authority shutdown succeeded.")

	var engine := SyntheticEngine.new(&"battle-session")
	var authority := LocalBattleAuthority.create(&"battle-session", engine)
	_expect(authority.is_valid(), "Local authority configuration failed.")
	var probe := AuthorityReentryProbe.new(authority)
	var callback := Callable(probe, "on_result")
	authority.result_ready.connect(callback)
	_expect(authority.start().is_ok, "Local authority start failed.")
	_expect(engine.step_count == 1, "Authority start stepped more than once.")
	_expect(probe.callback_count == 1, "Authority published wrong result count.")
	_expect(probe.start_code == BattleError.AUTHORITY_BUSY, "Reentrant start was not busy.")
	_expect(probe.submit_code == BattleError.AUTHORITY_BUSY, "Reentrant submit was not busy.")
	_expect(probe.shutdown_code == BattleError.AUTHORITY_BUSY, "Reentrant close was not busy.")
	_expect(authority.has_pending_request(), "Authority lost pending request.")
	_expect(
		authority.start().error.code == BattleError.AUTHORITY_ALREADY_STARTED,
		"Repeated authority start returned wrong error."
	)
	var wrong_battle := _make_input(&"other-battle", 1)
	_expect(
		authority.submit_input(wrong_battle).error.code == BattleError.BATTLE_ID_MISMATCH,
		"Authority accepted another battle input."
	)
	var stale := _make_input(&"battle-session", 2)
	_expect(
		authority.submit_input(stale).error.code == BattleError.REQUEST_NO_MISMATCH,
		"Authority accepted wrong request number."
	)
	_expect(authority.submit_input(_make_input(&"battle-session", 1)).is_ok, "Input failed.")
	_expect(engine.step_count == 2, "Accepted authority input did not step once.")
	_expect(authority.shutdown().is_ok, "Authority shutdown failed.")
	_expect(authority.shutdown().is_ok, "Authority shutdown was not idempotent.")
	_expect(engine.shutdown_count == 1, "Authority shut engine down more than once.")
	_expect(
		not authority.result_ready.is_connected(callback),
		"Authority shutdown retained result listener."
	)
	_expect(
		authority.submit_input(_make_input(&"battle-session", 2)).error.code
			== BattleError.AUTHORITY_SHUTDOWN,
		"Authority accepted input after shutdown."
	)
	if authority.result_ready.is_connected(callback):
		authority.result_ready.disconnect(callback)

	var wrong_engine := SyntheticEngine.new(&"other-battle")
	var wrong_authority := LocalBattleAuthority.create(&"battle-session", wrong_engine)
	var wrong_probe := ResultCodeProbe.new()
	var wrong_callback := Callable(wrong_probe, "on_result")
	wrong_authority.result_ready.connect(wrong_callback)
	_expect(wrong_authority.is_valid(), "Wrong-battle authority fixture was invalid.")
	_expect(wrong_authority.start().is_ok, "Wrong-battle authority did not dispatch.")
	_expect(wrong_probe.callback_count == 1, "Wrong-battle authority did not publish failure.")
	_expect(
		wrong_probe.codes[0] == BattleError.AUTHORITY_INVALID_RESULT,
		"Authority published a cross-battle engine result."
	)
	_expect(not wrong_authority.has_pending_request(), "Cross-battle request became pending.")
	wrong_authority.shutdown()


func _test_protocol_error_categories() -> void:
	var invalid_authority := LocalBattleAuthority.create(&"", null)
	_expect(
		invalid_authority.get_error().category == BattleError.Category.PROTOCOL,
		"Invalid battle ID used non-protocol category."
	)
	var authority_engine := SyntheticEngine.new(&"battle-category")
	var authority := LocalBattleAuthority.create(&"battle-category", authority_engine)
	authority.start()
	var wrong_battle := authority.submit_input(_make_input(&"other-category", 1))
	_expect(
		wrong_battle.error.category == BattleError.Category.PROTOCOL,
		"Authority battle mismatch used non-protocol category."
	)
	var stale := authority.submit_input(_make_input(&"battle-category", 2))
	_expect(
		stale.error.category == BattleError.Category.PROTOCOL,
		"Authority request mismatch used non-protocol category."
	)
	authority.shutdown()

	var session_engine := SyntheticEngine.new(&"session-category")
	var session_authority := LocalBattleAuthority.create(&"session-category", session_engine)
	var session := BattleSession.new()
	session.configure(session_authority)
	session.start()
	session.pump()
	var session_wrong := session.submit_input(_make_input(&"other-category", 1))
	_expect(
		session_wrong.error.category == BattleError.Category.PROTOCOL,
		"Session battle mismatch used non-protocol category."
	)
	var session_invalid := session.submit_input(BattleStepInput.new())
	_expect(
		session_invalid.error.category == BattleError.Category.PROTOCOL,
		"Session invalid input used non-protocol category."
	)
	session.close()
	session.free()


func _test_session_start_dispatch_guard() -> void:
	for probe_first in [true, false]:
		var engine := SyntheticEngine.new(&"battle-start-guard")
		var authority := LocalBattleAuthority.create(&"battle-start-guard", engine)
		var session := BattleSession.new()
		var probe := SessionStartReentryProbe.new(session)
		var callback := Callable(probe, "on_result")
		if probe_first:
			authority.result_ready.connect(callback)
		_expect(session.configure(authority).is_ok, "Start-guard configure failed.")
		if not probe_first:
			authority.result_ready.connect(callback)
		_expect(session.start().is_ok, "Outer Session start failed.")
		_expect(probe.callback_count == 1, "Start-guard callback count changed.")
		_expect(probe.start_code == BattleError.SESSION_BUSY, "Reentrant start was not busy.")
		_expect(probe.close_code == BattleError.SESSION_BUSY, "Reentrant close was not busy.")
		_expect(session.is_started(), "Outer Session start did not commit.")
		_expect(not session.is_closed(), "Reentrant close closed Session.")
		_expect(session.pending_result_count() == 1, "Start callback cleared first result.")
		_expect(session.pump().is_ok, "Start-guard result did not pump.")
		_expect(session.has_pending_request(), "Start-guard request was not published.")
		_expect(session.close().is_ok, "Start-guard Session close failed.")
		session.free()


func _test_session_inbox() -> void:
	var invalid_session := BattleSession.new()
	_expect(
		invalid_session.configure(BattleAuthorityPort.new()).error.code
			== BattleError.SESSION_INVALID_AUTHORITY,
		"Session accepted invalid authority."
	)
	invalid_session.free()

	var engine := SyntheticEngine.new(&"battle-session")
	var authority := LocalBattleAuthority.create(&"battle-session", engine)
	var session := BattleSession.new()
	_expect(session.configure(authority).is_ok, "Session configure failed.")
	_expect(
		session.configure(authority).error.code == BattleError.SESSION_ALREADY_CONFIGURED,
		"Repeated session configure returned wrong error."
	)
	_expect(
		session.pump().error.code == BattleError.SESSION_NOT_STARTED,
		"Session pumped before start."
	)
	_expect(session.start().is_ok, "Session start failed.")
	_expect(session.pending_result_count() == 1, "Authority result was not queued.")
	_expect(engine.step_count == 1, "Session start stepped more than once.")
	var probe := SessionReentryProbe.new(session, _make_input(&"battle-session", 1))
	var callback := Callable(probe, "on_result")
	session.result_ready.connect(callback)
	_expect(session.pump().is_ok, "Session result pump failed.")
	_expect(probe.callback_count == 1, "Session published wrong result count.")
	_expect(
		probe.pump_code == BattleError.SESSION_REENTRANT_PUMP,
		"Reentrant session pump was not rejected."
	)
	_expect(
		probe.close_code == BattleError.SESSION_REENTRANT_PUMP,
		"Session closed from inside pump."
	)
	_expect(probe.submit_ok, "Session callback input was not queued.")
	_expect(
		probe.duplicate_submit_code == BattleError.AUTHORITY_INPUT_NOT_EXPECTED,
		"Session accepted a second response to one request."
	)
	_expect(session.pending_input_count() == 1, "Callback input did not remain queued.")
	_expect(engine.step_count == 1, "Callback input reentered engine.")
	_expect(session.pump().is_ok, "Queued input pump failed.")
	_expect(engine.step_count == 2, "Queued input did not step on next pump.")
	_expect(session.pending_result_count() == 1, "Input result was not deferred.")
	_expect(session.pump().is_ok, "Deferred result pump failed.")
	_expect(probe.callback_count == 2, "Deferred result was not published once.")
	_expect(session.close().is_ok, "Session close failed.")
	_expect(session.close().is_ok, "Session close was not idempotent.")
	_expect(engine.shutdown_count == 1, "Session closed engine more than once.")
	_expect(
		not session.result_ready.is_connected(callback),
		"Session close retained result listener."
	)
	_expect(session.pending_result_count() == 0, "Closed session retained results.")
	_expect(session.pending_input_count() == 0, "Closed session retained inputs.")
	_expect(session.start().error.code == BattleError.SESSION_CLOSED, "Closed session started.")
	_expect(session.pump().error.code == BattleError.SESSION_CLOSED, "Closed session pumped.")
	if session.result_ready.is_connected(callback):
		session.result_ready.disconnect(callback)
	session.free()

	var pending_authority := ScriptedAuthority.new(&"battle-pending-close")
	var pending_session := BattleSession.new()
	_expect(
		pending_session.configure(pending_authority).is_ok,
		"Pending-close session configure failed."
	)
	_expect(pending_session.start().is_ok, "Pending-close session start failed.")
	_expect(pending_session.pending_result_count() == 2, "Pending results were missing.")
	_expect(pending_session.close().is_ok, "Pending-close session close failed.")
	_expect(pending_session.pending_result_count() == 0, "Close retained pending results.")
	pending_authority.result_ready.emit(_complete_result(&"battle-pending-close", 3))
	_expect(pending_session.pending_result_count() == 0, "Late result entered closed inbox.")
	pending_session.free()

	var failing_authority := FailingShutdownAuthority.new(&"battle-close-failure")
	var failing_session := BattleSession.new()
	_expect(
		failing_session.configure(failing_authority).is_ok,
		"Failing-close session configure failed."
	)
	_expect(not failing_session.close().is_ok, "Authority shutdown failure was hidden.")
	_expect(failing_session.is_closed(), "Failed authority shutdown left session open.")
	_expect(failing_session.pending_result_count() == 0, "Failed close retained results.")
	_expect(failing_session.close().is_ok, "Failed close was not idempotent afterward.")
	_expect(failing_authority.shutdown_count == 1, "Failing authority shutdown repeated.")
	failing_session.free()


func _test_session_fifo_and_alias_rejection() -> void:
	var authority := ScriptedAuthority.new(&"battle-fifo")
	var session := BattleSession.new()
	var probe := FifoProbe.new(authority)
	var callback := Callable(probe, "on_result")
	_expect(session.configure(authority).is_ok, "FIFO session configure failed.")
	session.result_ready.connect(callback)
	_expect(session.start().is_ok, "FIFO session start failed.")
	_expect(probe.progress_values.is_empty(), "Session delivered inside authority stack.")
	_expect(session.pending_result_count() == 2, "Initial FIFO results were not queued.")
	_expect(session.pump().is_ok, "First FIFO pump failed.")
	_expect(probe.progress_values == [1, 2], "Stable FIFO batch was reordered.")
	_expect(session.pending_result_count() == 1, "Injected FIFO result was not deferred.")
	_expect(session.pump().is_ok, "Second FIFO pump failed.")
	_expect(probe.progress_values == [1, 2, 3], "Deferred FIFO result order changed.")
	_expect(probe.max_depth == 1, "Session result delivery recursed.")
	_expect(session.close().is_ok, "FIFO session close failed.")
	_expect(
		not session.result_ready.is_connected(callback),
		"FIFO session close retained result listener."
	)
	authority.emit_progress(4)
	_expect(probe.progress_values == [1, 2, 3], "Late result escaped closed session.")
	_expect(authority.shutdown_count == 1, "FIFO authority shutdown count changed.")
	if session.result_ready.is_connected(callback):
		session.result_ready.disconnect(callback)
	session.free()

	var alias_authority := ScriptedAuthority.new(&"battle-alias")
	var alias_session := BattleSession.new()
	_expect(alias_session.configure(alias_authority).is_ok, "Alias session configure failed.")
	var template := _complete_result(&"battle-alias", 1)
	alias_session._on_authority_result(AliasingStepResult.new(template))
	_expect(
		alias_session.get_error().code == BattleError.SESSION_INVALID_INBOX,
		"Session accepted self-aliasing result copy."
	)
	_expect(alias_session.start().is_ok, "Alias session start failed.")
	_expect(
		alias_session.pump().error.code == BattleError.SESSION_INVALID_INBOX,
		"Alias inbox error was not sticky."
	)
	_expect(alias_session.close().is_ok, "Alias session close failed.")
	alias_session.free()

	var wrong_authority := ScriptedAuthority.new(&"battle-expected")
	var wrong_session := BattleSession.new()
	_expect(
		wrong_session.configure(wrong_authority).is_ok,
		"Cross-battle session configure failed."
	)
	wrong_authority.result_ready.emit(_complete_result(&"battle-other", 1))
	_expect(
		wrong_session.get_error().code == BattleError.SESSION_INVALID_INBOX,
		"Session accepted cross-battle result."
	)
	_expect(wrong_session.pending_result_count() == 0, "Cross-battle result entered inbox.")
	_expect(wrong_session.close().is_ok, "Cross-battle session close failed.")
	wrong_session.free()


func _test_terminal_late_result() -> void:
	var engine := BattleEngine.new()
	var authority := LocalBattleAuthority.create(&"battle-terminal", engine)
	var session := BattleSession.new()
	var probe := ResultCodeProbe.new()
	var callback := Callable(probe, "on_result")
	_expect(session.configure(authority).is_ok, "Terminal session configure failed.")
	session.result_ready.connect(callback)
	_expect(session.start().is_ok, "Terminal session start failed.")
	_expect(session.pending_result_count() == 1, "Terminal result was not queued.")
	_expect(session.pump().is_ok, "Terminal result pump failed.")
	_expect(session.is_finished(), "Terminal result did not finish session.")
	_expect(probe.callback_count == 1, "Terminal result was not published once.")
	authority.result_ready.emit(_complete_result(&"battle-terminal", 1))
	_expect(
		session.get_error().code == BattleError.SESSION_INVALID_INBOX,
		"Late terminal result was not rejected."
	)
	_expect(session.pending_result_count() == 0, "Late terminal result entered inbox.")
	_expect(not session.pump().is_ok, "Terminal session ignored sticky late-result error.")
	_expect(probe.callback_count == 1, "Late terminal result was published.")
	_expect(session.close().is_ok, "Terminal session close failed.")
	session.free()


func _test_release_graphs() -> void:
	for iteration in 100:
		var refs := _build_closed_graph(iteration)
		var all_released := true
		for object_ref in refs:
			if object_ref.get_ref() != null:
				all_released = false
				break
		_expect(all_released, "Advanced graph leaked in release iteration %d." % iteration)


func _build_closed_graph(iteration: int) -> Array[WeakRef]:
	var battle_id := StringName("release-%d" % iteration)
	var engine := SyntheticEngine.new(battle_id)
	var authority := LocalBattleAuthority.create(battle_id, engine)
	var session := BattleSession.new()
	var session_ref: WeakRef = weakref(session)
	var authority_ref: WeakRef = weakref(authority)
	var engine_ref: WeakRef = weakref(engine)
	var refs: Array[WeakRef] = [session_ref, authority_ref, engine_ref]
	session.configure(authority)
	session.start()
	var authority_request: BattleInputRequest = authority._pending_request
	refs.append(weakref(authority_request))
	if iteration % 2 == 0:
		var result: BattleStepResult = session._result_inbox[0]
		var batch: BattleCommandBatch = result._commands
		var result_request: BattleInputRequest = result._input_request
		refs.append(weakref(result))
		refs.append(weakref(batch))
		refs.append(weakref(result_request))
	else:
		session.pump()
		var session_request: BattleInputRequest = session._pending_request
		refs.append(weakref(session_request))
	session.close()
	session.free()
	return refs


func _make_input(battle_id: StringName, request_no: int) -> BattleStepInput:
	var candidate := _candidate_digest(7)
	var build := BattleStepInput.create(
		battle_id,
		request_no,
		3,
		candidate,
		SyntheticPayload.new(7)
	)
	_expect(build.is_success(), "Synthetic step input fixture failed to build.")
	return build.get_value()


func _complete_result(battle_id: StringName, progress: int) -> BattleStepResult:
	var batch := BattleCommandBatch.create_published(
		battle_id,
		0,
		progress,
		BattleContractVersions.CATALOG_VERSION,
		_hash_text("complete-catalog"),
		false,
		PackedByteArray(),
		1,
		_hash_text("complete-before-%d" % progress),
		_hash_text("complete-after-%d" % progress),
		[]
	).get_value()
	return BattleStepResult.complete(
		batch,
		true,
		_hash_text("complete-authority-%d" % progress)
	)


func _candidate_digest(option_id: int) -> PackedByteArray:
	var writer := CanonicalWriter.new()
	writer.write_string("P1_SESSION_CANDIDATE")
	writer.write_i64(BattleDecisionPayload.Kind.ACTION)
	writer.write_i64(option_id)
	return BattleHash.sha256_bytes(writer.finish().value).value


func _hash_text(value: String) -> PackedByteArray:
	return BattleHash.sha256_bytes(value.to_utf8_buffer()).value


func _expect(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(message)
