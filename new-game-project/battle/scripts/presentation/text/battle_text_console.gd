extends Control


func _unhandled_key_input(event: InputEvent) -> void:
	var key_event := event as InputEventKey
	if key_event == null or not key_event.pressed or key_event.echo:
		return
	if key_event.keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		_request_exit()


func _on_exit_button_pressed() -> void:
	_request_exit()


func _request_exit() -> void:
	get_tree().quit()
