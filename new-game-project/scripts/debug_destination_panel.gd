class_name PlatinumDebugDestinationPanel
extends CanvasLayer

const DEFAULT_CELL_SENTINEL := Vector2i(-1, -1)

@export_node_path("Node") var streamer_path := NodePath("../WorldStreamer")

var _streamer: Node
var _panel_open := false
var _submitting := false
var _has_destination_fields := false
var _owns_pause := false
var _previous_tree_paused := false

@onready var _matrix_spin := %MatrixSpin as SpinBox
@onready var _area_spin := %AreaSpin as SpinBox
@onready var _default_cell_check := %DefaultCellCheck as CheckBox
@onready var _cell_x_spin := %CellXSpin as SpinBox
@onready var _cell_y_spin := %CellYSpin as SpinBox
@onready var _tile_x_spin := %TileXSpin as SpinBox
@onready var _tile_y_spin := %TileYSpin as SpinBox
@onready var _error_label := %ErrorLabel as Label
@onready var _cancel_button := %CancelButton as Button
@onready var _jump_button := %JumpButton as Button


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	_streamer = get_node_or_null(streamer_path)
	_cancel_button.pressed.connect(close_panel)
	_jump_button.pressed.connect(submit_jump)
	_default_cell_check.toggled.connect(_on_default_cell_toggled)
	for spin: SpinBox in _destination_spins():
		spin.value_changed.connect(_on_numeric_field_changed)
	_update_cell_editability()


func _exit_tree() -> void:
	if _owns_pause:
		_restore_pause_state()


func _input(event: InputEvent) -> void:
	if not event is InputEventKey:
		return
	var key_event := event as InputEventKey
	if not key_event.pressed or key_event.echo:
		return

	if _matches_key(key_event, KEY_F2):
		if not _submitting:
			if _panel_open:
				close_panel()
			else:
				open_panel()
		get_viewport().set_input_as_handled()
		return

	if not _panel_open or _submitting:
		return
	if _matches_key(key_event, KEY_ESCAPE):
		close_panel()
		get_viewport().set_input_as_handled()
	elif _matches_key(key_event, KEY_ENTER) or _matches_key(key_event, KEY_KP_ENTER):
		_release_editor_focus()
		get_viewport().set_input_as_handled()
		call_deferred("_submit_after_editor_commit")


func is_open() -> bool:
	return _panel_open


func open_panel() -> void:
	if _panel_open or _submitting:
		return
	if not _has_destination_fields:
		_prefill_from_streamer()
	_previous_tree_paused = get_tree().paused
	_owns_pause = true
	get_tree().paused = true
	_panel_open = true
	visible = true
	_set_error("")
	_set_submitting(false)
	var editor := _matrix_spin.get_line_edit()
	editor.grab_focus()
	editor.select_all()


func close_panel() -> void:
	if not _panel_open or _submitting:
		return
	_release_editor_focus()
	_panel_open = false
	visible = false
	_set_error("")
	_restore_pause_state()


func set_destination_fields(
	matrix: int,
	area: int,
	use_default_cell: bool,
	cell: Vector2i,
	tile: Vector2i
) -> void:
	_matrix_spin.set_value_no_signal(matrix)
	_area_spin.set_value_no_signal(area)
	_default_cell_check.set_pressed_no_signal(use_default_cell)
	_cell_x_spin.set_value_no_signal(cell.x)
	_cell_y_spin.set_value_no_signal(cell.y)
	_tile_x_spin.set_value_no_signal(tile.x)
	_tile_y_spin.set_value_no_signal(tile.y)
	_has_destination_fields = true
	_update_cell_editability()
	_set_error("")


func submit_jump() -> bool:
	if not _panel_open or _submitting:
		return false
	_release_editor_focus()
	if _streamer == null or not _streamer.has_method("resolve_debug_destination_request"):
		_set_error("Destination resolver is unavailable.")
		return false

	var requested_cell := DEFAULT_CELL_SENTINEL
	if not _default_cell_check.button_pressed:
		requested_cell = Vector2i(roundi(_cell_x_spin.value), roundi(_cell_y_spin.value))
	var requested_tile := Vector2i(roundi(_tile_x_spin.value), roundi(_tile_y_spin.value))
	var result_value: Variant = _streamer.call(
		"resolve_debug_destination_request",
		roundi(_matrix_spin.value),
		roundi(_area_spin.value),
		requested_cell,
		requested_tile
	)
	if typeof(result_value) != TYPE_DICTIONARY:
		_set_error("Destination resolver returned invalid data.")
		return false
	var result := result_value as Dictionary
	if not bool(result.get("ok", false)):
		_set_error(String(result.get("error", "Destination is not available.")))
		_focus_error_field(String(result.get("field", "")))
		return false

	_set_submitting(true)
	_panel_open = false
	visible = false
	_restore_pause_state()
	call_deferred("_queue_and_reload", result.duplicate(true))
	return true


func get_error_text() -> String:
	return _error_label.text


func _submit_after_editor_commit() -> void:
	if _panel_open and not _submitting:
		submit_jump()


func _queue_and_reload(result: Dictionary) -> void:
	if not is_inside_tree():
		return
	if _streamer == null or not _streamer.has_method("queue_debug_destination_request"):
		_recover_submission("Destination handoff is unavailable.")
		return
	var queue_value: Variant = _streamer.call("queue_debug_destination_request", result)
	if typeof(queue_value) != TYPE_DICTIONARY:
		_recover_submission("Destination handoff returned invalid data.")
		return
	var queue_result := queue_value as Dictionary
	if not bool(queue_result.get("ok", false)):
		_recover_submission(
			String(queue_result.get("error", "Could not queue the destination jump.")),
			String(queue_result.get("field", ""))
		)
		return
	var token := StringName(queue_result.get("token", ""))
	if token == StringName():
		_recover_submission("Destination handoff returned no token.")
		return

	var tree := get_tree()
	var reload_error := tree.reload_current_scene()
	if reload_error == OK:
		return
	if is_instance_valid(_streamer) and _streamer.has_method("cancel_debug_destination_request"):
		_streamer.call("cancel_debug_destination_request", token)
	_recover_submission("Scene reload failed (error %d)." % reload_error)


func _recover_submission(message: String, field: String = "") -> void:
	_set_submitting(false)
	open_panel()
	_set_error(message)
	_focus_error_field(field)


func _prefill_from_streamer() -> void:
	if _streamer == null or not _streamer.has_method("get_stream_stats"):
		return
	var stats_value: Variant = _streamer.call("get_stream_stats")
	if typeof(stats_value) != TYPE_DICTIONARY:
		return
	var stats := stats_value as Dictionary
	var start: Dictionary = stats.get("start", {})
	var cell: Dictionary = start.get("cell", {})
	var tile: Dictionary = start.get("tile", {})
	set_destination_fields(
		int(stats.get("matrix", 0)),
		int(stats.get("area", -1)),
		true,
		Vector2i(int(cell.get("x", 0)), int(cell.get("y", 0))),
		Vector2i(int(tile.get("x", 0)), int(tile.get("y", 0)))
	)


func _restore_pause_state() -> void:
	if not _owns_pause:
		return
	get_tree().paused = _previous_tree_paused
	_owns_pause = false


func _set_submitting(value: bool) -> void:
	_submitting = value
	_matrix_spin.editable = not value
	_area_spin.editable = not value
	_default_cell_check.disabled = value
	_tile_x_spin.editable = not value
	_tile_y_spin.editable = not value
	_cancel_button.disabled = value
	_jump_button.disabled = value
	_update_cell_editability()


func _update_cell_editability() -> void:
	var editable := not _submitting and not _default_cell_check.button_pressed
	_cell_x_spin.editable = editable
	_cell_y_spin.editable = editable


func _on_default_cell_toggled(_pressed: bool) -> void:
	_has_destination_fields = true
	_update_cell_editability()
	_set_error("")


func _on_numeric_field_changed(_value: float) -> void:
	_has_destination_fields = true
	_set_error("")


func _focus_error_field(field: String) -> void:
	var spin: SpinBox
	match field:
		"matrix":
			spin = _matrix_spin
		"area":
			spin = _area_spin
		"cell":
			spin = _cell_x_spin
		"tile":
			spin = _tile_x_spin
		_:
			return
	if spin.editable:
		spin.get_line_edit().grab_focus()
		spin.get_line_edit().select_all()


func _set_error(message: String) -> void:
	_error_label.text = message


func _release_editor_focus() -> void:
	var focus_owner := get_viewport().gui_get_focus_owner()
	if focus_owner != null:
		focus_owner.release_focus()


func _destination_spins() -> Array[SpinBox]:
	return [
		_matrix_spin,
		_area_spin,
		_cell_x_spin,
		_cell_y_spin,
		_tile_x_spin,
		_tile_y_spin,
	]


func _matches_key(event: InputEventKey, key: Key) -> bool:
	return event.keycode == key or event.physical_keycode == key
