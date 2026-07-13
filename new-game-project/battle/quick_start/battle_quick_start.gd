@tool
extends Node

const TARGET_SCENE_PATH := "res://battle/scenes/battle_text_console.tscn"
const SYNTHETIC_BOOTSTRAP_MODE := "SYNTHETIC"
const CATALOG_BOOTSTRAP_MODE := "CATALOG"

@export_tool_button("Quick Start Text Battle", "Play")
var quick_start_text_battle: Callable = _quick_start_text_battle


func _quick_start_text_battle() -> void:
	if not Engine.is_editor_hint():
		return

	if not ResourceLoader.exists(TARGET_SCENE_PATH, "PackedScene"):
		_report_editor_error("Target scene is missing: %s" % TARGET_SCENE_PATH)
		return

	var loaded_resource := ResourceLoader.load(
		TARGET_SCENE_PATH,
		"PackedScene",
		ResourceLoader.CACHE_MODE_IGNORE
	)
	if not loaded_resource is PackedScene:
		_report_editor_error("Target scene or one of its scripts could not be parsed.")
		return

	var target_scene := loaded_resource as PackedScene
	var probe := target_scene.instantiate(PackedScene.GEN_EDIT_STATE_DISABLED)
	if probe == null:
		_report_editor_error("Target scene could not be instantiated for validation.")
		return
	if probe.get_script() == null or not probe.has_method(&"_on_exit_button_pressed"):
		probe.free()
		_report_editor_error("Target scene script is missing or failed to parse.")
		return

	var bootstrap_mode := String(probe.get_meta(&"battle_bootstrap_mode", ""))
	var bootstrap_ready := bool(probe.get_meta(&"battle_bootstrap_ready", false))
	var catalog_ready := bool(probe.get_meta(&"battle_catalog_ready", false))
	probe.free()

	match bootstrap_mode:
		SYNTHETIC_BOOTSTRAP_MODE:
			if not bootstrap_ready:
				_report_editor_error("Synthetic battle bootstrap is not ready.")
				return
		CATALOG_BOOTSTRAP_MODE:
			if not catalog_ready:
				_report_editor_error("Battle catalog bootstrap is not ready.")
				return
		_:
			_report_editor_error("Battle bootstrap mode is missing or unsupported.")
			return

	var editor_interface := Engine.get_singleton(&"EditorInterface")
	if editor_interface == null or not editor_interface.has_method(&"play_custom_scene"):
		_report_editor_error("Godot EditorInterface is unavailable.")
		return
	if bool(editor_interface.call(&"is_playing_scene")):
		_report_editor_error("Stop the current play session before quick starting battle.")
		return

	editor_interface.call(&"play_custom_scene", TARGET_SCENE_PATH)


func _report_editor_error(message: String) -> void:
	push_error("Battle quick start: %s" % message)
