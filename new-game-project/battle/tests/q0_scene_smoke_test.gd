extends SceneTree

const QUICK_START_SCENE := "res://battle/quick_start/battle_quick_start.tscn"
const TEXT_CONSOLE_SCENE := "res://battle/scenes/battle_text_console.tscn"
const QUICK_START_SCRIPT := "res://battle/quick_start/battle_quick_start.gd"
const CONSOLE_SCRIPT := "res://battle/scripts/presentation/text/battle_text_console.gd"
const EXPECTED_SIZE := Vector2(256.0, 192.0)

var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var initial_scene := current_scene
	var initial_pause := paused
	_validate_quick_start()
	_validate_text_console()
	_validate_dependency_boundary()

	if current_scene != initial_scene:
		_failures.append("Q0 validation changed the current scene.")
	if paused != initial_pause:
		_failures.append("Q0 validation changed the SceneTree pause state.")

	if not _failures.is_empty():
		for failure in _failures:
			push_error(failure)
		quit(1)
		return

	print("BATTLE_Q0_SCENE_SMOKE_OK")
	quit(0)


func _validate_quick_start() -> void:
	var scene := _load_scene(QUICK_START_SCENE)
	if scene == null:
		return
	var root_node := scene.instantiate()
	if root_node == null:
		_failures.append("Quick-start scene could not be instantiated.")
		return
	if not root_node.has_method(&"_quick_start_text_battle"):
		_failures.append("Quick-start root is missing its tool callback.")

	var button_property_found := false
	for property: Dictionary in root_node.get_property_list():
		if StringName(property.get("name", "")) != &"quick_start_text_battle":
			continue
		button_property_found = true
		if int(property.get("type", TYPE_NIL)) != TYPE_CALLABLE:
			_failures.append("Inspector quick-start property is not a Callable.")
		if int(property.get("hint", PROPERTY_HINT_NONE)) != PROPERTY_HINT_TOOL_BUTTON:
			_failures.append("Inspector quick-start property is not a tool button.")
		break
	if not button_property_found:
		_failures.append("Inspector quick-start tool button was not exported.")

	var callback: Callable = root_node.get(&"quick_start_text_battle")
	if not callback.is_valid():
		_failures.append("Inspector quick-start Callable is invalid.")
	elif not Engine.is_editor_hint():
		callback.call()
	root_node.free()


func _validate_text_console() -> void:
	var scene := _load_scene(TEXT_CONSOLE_SCENE)
	if scene == null:
		return
	var root_node := scene.instantiate() as Control
	if root_node == null:
		_failures.append("Text console root is not a Control.")
		return
	if root_node.get_script() == null:
		_failures.append("Text console script is missing or failed to parse.")
	for method_name: StringName in [&"_on_exit_button_pressed", &"_unhandled_key_input"]:
		if not root_node.has_method(method_name):
			_failures.append("Text console script is missing %s()." % method_name)
	if root_node.custom_minimum_size != EXPECTED_SIZE:
		_failures.append("Text console does not preserve the 256 x 192 contract.")
	if String(root_node.get_meta(&"battle_stage", "")) != "Q0":
		_failures.append("Text console does not report Q0 stage metadata.")
	if String(root_node.get_meta(&"battle_bootstrap_mode", "")) != "SYNTHETIC":
		_failures.append("Text console bootstrap mode is not synthetic.")
	if not bool(root_node.get_meta(&"battle_bootstrap_ready", false)):
		_failures.append("Synthetic bootstrap is not marked ready.")
	if bool(root_node.get_meta(&"battle_catalog_ready", true)):
		_failures.append("Q0 incorrectly claims that a battle catalog is ready.")

	_assert_label(root_node, NodePath("%Phase"), "Q0 / P0-P18 status")
	_assert_label(root_node, NodePath("%BootstrapStatus"), "Bootstrap: synthetic ready")
	_assert_label(root_node, NodePath("%CatalogStatus"), "Catalog: not implemented")
	_assert_label(root_node, NodePath("%EngineStatus"), "Engine: not implemented")
	_assert_label(root_node, NodePath("%BattleStatus"), "Battle: unavailable")
	var exit_button := root_node.get_node_or_null(NodePath("%ExitButton")) as Button
	if exit_button == null or not exit_button.pressed.is_connected(
		Callable(root_node, "_on_exit_button_pressed")
	):
		_failures.append("Text console Exit button is not connected to its local owner.")
	root_node.free()


func _validate_dependency_boundary() -> void:
	var forbidden := [
		"res://scripts/",
		"res://scenes/main.tscn",
		"ProjectSettings",
		"get_tree().root",
		"PlatinumWorldStreamer",
		"PlatinumCollisionMap",
		"PlatinumPlayerController",
		"FollowCamera",
		"EditorPlugin",
		"InputMap",
	]
	for path in [QUICK_START_SCRIPT, CONSOLE_SCRIPT]:
		var file := FileAccess.open(path, FileAccess.READ)
		if file == null:
			_failures.append("Could not read battle script: %s" % path)
			continue
		var source := file.get_as_text()
		for token: String in forbidden:
			if source.contains(token):
				_failures.append("%s contains forbidden dependency token %s." % [path, token])


func _load_scene(path: String) -> PackedScene:
	if not ResourceLoader.exists(path, "PackedScene"):
		_failures.append("Scene is missing: %s" % path)
		return null
	var resource := ResourceLoader.load(path, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE)
	if not resource is PackedScene:
		_failures.append("Scene or attached script failed to parse: %s" % path)
		return null
	return resource as PackedScene


func _assert_label(root_node: Node, path: NodePath, expected: String) -> void:
	var label := root_node.get_node_or_null(path) as Label
	if label == null or label.text != expected:
		_failures.append("Text console status mismatch for %s." % path)
