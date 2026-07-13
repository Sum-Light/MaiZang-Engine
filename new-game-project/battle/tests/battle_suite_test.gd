extends SceneTree

const FOUNDATION_VECTORS_PATH := (
	"res://battle/tests/foundation/p1_foundation_vectors.gd"
)
const PROTOCOL_VECTORS_PATH := (
	"res://battle/tests/protocol/p1_protocol_command_vectors.gd"
)
const SESSION_VECTORS_PATH := (
	"res://battle/tests/application/p1_session_lifecycle_vectors.gd"
)
const TREE_RELEASE_PROBE_PATH := (
	"res://battle/tests/application/p1_session_tree_release_probe.gd"
)

const VALID_SUITES: Array[String] = [
	"all",
	"p1_foundation",
	"p1_protocol_command",
	"p1_session_lifecycle",
]
const EXIT_TEST_FAILURE: int = 1
const EXIT_USAGE: int = 2
const EXPECTED_ALL_CHECKS: int = 597


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var parsed := _parse_suite(OS.get_cmdline_user_args())
	if not parsed.is_valid:
		push_error("BATTLE_SUITE_USAGE: %s" % parsed.error)
		print(
			"Usage: --script res://battle/tests/battle_suite_test.gd -- "
			+ "[--suite=<%s>]" % "|".join(VALID_SUITES)
		)
		quit(EXIT_USAGE)
		return

	var suite: String = parsed.suite
	var failures: Array[String] = []
	var checks := 0
	if suite == "all":
		checks = _run_all_suites(failures)
	elif suite == "p1_foundation":
		checks += _run_sync_suite(
			"p1_foundation",
			FOUNDATION_VECTORS_PATH,
			164,
			failures
		)
	elif suite == "p1_protocol_command":
		checks += _run_sync_suite(
			"p1_protocol_command",
			PROTOCOL_VECTORS_PATH,
			151,
			failures
		)
	elif suite == "p1_session_lifecycle":
		checks += await _run_session_suite(failures)
	if suite == "all" and checks != EXPECTED_ALL_CHECKS:
		failures.append("[all] check count stopped at %d; expected %d." % [
			checks,
			EXPECTED_ALL_CHECKS,
		])
	await process_frame

	if not failures.is_empty():
		for failure: String in failures:
			push_error(failure)
		quit(EXIT_TEST_FAILURE)
		return
	print("BATTLE_SUITE_OK suite=%s checks=%d" % [suite, checks])
	quit(0)


func _run_all_suites(failures: Array[String]) -> int:
	var executable := OS.get_executable_path()
	if executable.is_empty():
		failures.append("[all] Godot executable path is unavailable.")
		return 0
	var project_path := ProjectSettings.globalize_path("res://")
	var suites: Array[Dictionary] = [
		{"name": "p1_foundation", "checks": 164},
		{"name": "p1_protocol_command", "checks": 151},
		{"name": "p1_session_lifecycle", "checks": 282},
	]
	var checks := 0
	for child: Dictionary in suites:
		var child_output: Array = []
		var child_suite: String = child.name
		var child_checks: int = child.checks
		var arguments := PackedStringArray([
			"--no-header",
			"--headless",
			"--path",
			project_path,
			"--script",
			"res://battle/tests/battle_suite_test.gd",
			"--",
			"--suite=%s" % child_suite,
		])
		var exit_code := OS.execute(
			executable,
			arguments,
			child_output,
			true,
			false
		)
		var output_text := "".join(child_output)
		if not output_text.is_empty():
			print(output_text.strip_edges())
		var expected := "BATTLE_SUITE_OK suite=%s checks=%d" % [
			child_suite,
			child_checks,
		]
		if exit_code != 0:
			failures.append("[all] suite %s exited %d." % [child_suite, exit_code])
		elif (
			output_text.to_lower().contains("leaked at exit")
			or output_text.to_lower().contains("resources still in use")
		):
			failures.append("[all] suite %s leaked objects or resources." % child_suite)
		elif output_text.count(expected) != 1:
			failures.append("[all] suite %s emitted %d success markers; expected one." % [
				child_suite,
				output_text.count(expected),
			])
		else:
			checks += child_checks
	return checks


func _run_sync_suite(
	suite: String,
	vectors_path: String,
	expected_checks: int,
	failures: Array[String]
) -> int:
	var failure_count := failures.size()
	var vectors_script := _load_test_script(vectors_path, suite, failures)
	if vectors_script == null:
		return 0
	var vectors = vectors_script.new()
	var suite_failures: Array[String] = vectors.run()
	for failure: String in suite_failures:
		failures.append("[%s] %s" % [suite, failure])
	var checks: int = vectors.check_count()
	if checks != expected_checks:
		failures.append("[%s] check count stopped at %d; expected %d." % [
			suite,
			checks,
			expected_checks,
		])
	if failures.size() == failure_count:
		print("BATTLE_SUITE_CASE_OK suite=%s checks=%d" % [suite, checks])
	return checks


func _run_session_suite(failures: Array[String]) -> int:
	var suite := "p1_session_lifecycle"
	var failure_count := failures.size()
	var vectors_script := _load_test_script(SESSION_VECTORS_PATH, suite, failures)
	var probe_script := _load_test_script(TREE_RELEASE_PROBE_PATH, suite, failures)
	if vectors_script == null or probe_script == null:
		return 0
	var vectors = vectors_script.new()
	var vector_failures: Array[String] = vectors.run()
	for failure: String in vector_failures:
		failures.append("[%s] %s" % [suite, failure])
	if vectors.check_count() != 270:
		failures.append("[%s] vector count stopped at %d; expected %d." % [
			suite,
			vectors.check_count(),
			270,
		])

	var tree_probe = probe_script.new()
	var tree_failures: Array[String] = await tree_probe.run(self, vectors_script)
	for failure: String in tree_failures:
		failures.append("[%s] %s" % [suite, failure])
	if tree_probe.check_count() != 12:
		failures.append("[%s] tree count stopped at %d; expected %d." % [
			suite,
			tree_probe.check_count(),
			12,
		])

	var checks: int = vectors.check_count() + tree_probe.check_count()
	if failures.size() == failure_count:
		print("BATTLE_SUITE_CASE_OK suite=%s checks=%d" % [suite, checks])
	return checks


func _load_test_script(
	path: String,
	suite: String,
	failures: Array[String]
) -> Script:
	var resource := ResourceLoader.load(
		path,
		"GDScript",
		ResourceLoader.CACHE_MODE_IGNORE
	)
	if (
		resource == null
		or not resource is Script
		or not (resource as Script).can_instantiate()
	):
		failures.append("[%s] could not load test vectors: %s" % [suite, path])
		return null
	return resource as Script


func _parse_suite(arguments: PackedStringArray) -> Dictionary:
	var suite := "all"
	var has_suite := false
	var index := 0
	while index < arguments.size():
		var argument: String = arguments[index]
		if argument == "--suite":
			if has_suite:
				return _parse_failure("--suite may be provided only once.")
			if index + 1 >= arguments.size():
				return _parse_failure("--suite requires a value.")
			index += 1
			suite = arguments[index].strip_edges().to_lower()
			has_suite = true
		elif argument.begins_with("--suite="):
			if has_suite:
				return _parse_failure("--suite may be provided only once.")
			suite = argument.trim_prefix("--suite=").strip_edges().to_lower()
			has_suite = true
		else:
			return _parse_failure("Unknown argument '%s'." % argument)
		index += 1

	if suite.is_empty():
		return _parse_failure("--suite requires a non-empty value.")
	if suite not in VALID_SUITES:
		return _parse_failure("Unknown suite '%s'." % suite)
	return {"is_valid": true, "suite": suite, "error": ""}


func _parse_failure(message: String) -> Dictionary:
	return {"is_valid": false, "suite": "", "error": message}
