extends SceneTree

const DATA_REGISTRY_SCRIPT := preload("res://scripts/autoload/data_registry.gd")
const BATTLE_HEALTHBOX_SCRIPT := preload("res://scripts/battle/battle_healthbox.gd")

var _failed := false


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var registry = DATA_REGISTRY_SCRIPT.new()
	registry._ready()

	var healthbox = BATTLE_HEALTHBOX_SCRIPT.new()
	get_root().add_child(healthbox)
	var player_asset = registry.get_battle_interface_texture_record("healthbox_singles_player")
	healthbox.configure_healthbox(
		"player",
		player_asset,
		Rect2(128, 74, 128, 64),
		Rect2(174, 92, 48, 2),
		Vector2(158, 88),
		{"status": "smoke_layout_profile"},
		{
			"side": "player",
			"battler_position": "B_POSITION_PLAYER_LEFT",
		}
	)

	_assert(healthbox.has_frame_texture(), "expected generated player healthbox frame texture")
	_assert(healthbox.source_scaled_hp_fraction(100, 100) == 48, "expected full HP to fill 48 px")
	_assert(healthbox.source_scaled_hp_fraction(50, 100) == 24, "expected half HP to fill 24 px")
	_assert(healthbox.source_scaled_hp_fraction(49, 100) == 23, "expected source floor HP scaling")
	_assert(healthbox.source_scaled_hp_fraction(1, 100) == 1, "expected nonzero HP to keep 1 visible px")
	_assert(healthbox.source_scaled_hp_fraction(0, 100) == 0, "expected zero HP to empty the bar")
	_assert(String(healthbox.source_hp_bar_level(100, 100)) == "full", "expected full HP bar level")
	_assert(String(healthbox.source_hp_bar_level(51, 100)) == "green", "expected above 50 percent to be green")
	_assert(String(healthbox.source_hp_bar_level(50, 100)) == "yellow", "expected 50 percent to be yellow")
	_assert(String(healthbox.source_hp_bar_level(21, 100)) == "yellow", "expected above 20 percent to be yellow")
	_assert(String(healthbox.source_hp_bar_level(20, 100)) == "red", "expected 20 percent to be red")
	_assert(String(healthbox.source_hp_bar_level(1, 100)) == "red", "expected 1 HP to be red")
	_assert(String(healthbox.source_hp_bar_level(0, 100)) == "empty", "expected zero HP to be empty")
	if _failed:
		_quit_failed(healthbox, registry)
		return

	healthbox.set_battle_mon({
		"name": "Mudkip",
		"level": 30,
		"hp": 100,
		"max_hp": 100,
	})
	var full_snapshot := _dict_value(healthbox.get_runtime_snapshot())
	var full_bar := _dict_value(full_snapshot.get("hp_bar", {}))
	_assert(String(full_snapshot.get("status", "")) == "source_healthbox_runtime_first_pass", "expected first-pass runtime status")
	_assert(_array_value(full_bar.get("screen_rect", [])) == [174, 92, 48, 2], "expected player HP bar rect")
	_assert(int(full_bar.get("filled_px", -1)) == 48, "expected full snapshot width")
	_assert(String(full_bar.get("level", "")) == "full", "expected full snapshot level")
	_assert(_array_value(full_bar.get("row_rgba", [])) == [[90, 214, 132, 255], [115, 255, 173, 255]], "expected full snapshot green rows")

	healthbox.set_battle_mon({
		"name": "Mudkip",
		"level": 30,
		"hp": 1,
		"max_hp": 100,
	})
	var low_snapshot := _dict_value(healthbox.get_runtime_snapshot())
	var low_bar := _dict_value(low_snapshot.get("hp_bar", {}))
	var low_event := _dict_value(low_snapshot.get("last_update_event", {}))
	_assert(int(low_bar.get("filled_px", -1)) == 1, "expected 1 HP snapshot width")
	_assert(String(low_bar.get("level", "")) == "red", "expected 1 HP snapshot level")
	_assert(String(low_event.get("status", "")) == "applied", "expected applied drain event")
	_assert(String(low_event.get("kind", "")) == "drain", "expected drain event kind")
	_assert(int(low_event.get("from_hp", -1)) == 100, "expected drain from HP")
	_assert(int(low_event.get("to_hp", -1)) == 1, "expected drain to HP")
	_assert(int(low_event.get("hp_delta", 0)) == -99, "expected VM HP delta")
	_assert(int(low_event.get("from_filled_px", -1)) == 48, "expected drain from width")
	_assert(int(low_event.get("to_filled_px", -1)) == 1, "expected drain final width")
	_assert(bool(low_event.get("vm_hp_delta_consumed", false)), "expected VM delta consumed flag")
	_assert(bool(low_event.get("final_pixel_width_matches_source_fraction", false)), "expected source final width match")

	var faint_event := _dict_value(healthbox.record_hp_delta_event(1, 0, 100))
	var faint_snapshot := _dict_value(healthbox.get_runtime_snapshot())
	var faint_bar := _dict_value(faint_snapshot.get("hp_bar", {}))
	_assert(String(faint_event.get("kind", "")) == "drain", "expected faint as drain event")
	_assert(int(faint_event.get("from_hp", -1)) == 1, "expected faint from HP")
	_assert(int(faint_event.get("to_hp", -1)) == 0, "expected faint to zero")
	_assert(int(faint_event.get("to_filled_px", -1)) == 0, "expected faint final width")
	_assert(int(faint_bar.get("filled_px", -1)) == 0, "expected faint snapshot width")
	_assert(String(faint_bar.get("level", "")) == "empty", "expected faint snapshot level")

	if _failed:
		_quit_failed(healthbox, registry)
		return

	print(JSON.stringify({
		"battle_healthbox_smoke": "ok",
		"status": String(full_snapshot.get("status", "")),
		"full_width": int(full_bar.get("filled_px", -1)),
		"one_hp_width": int(low_bar.get("filled_px", -1)),
		"faint_width": int(faint_bar.get("filled_px", -1)),
		"drain_delta": int(low_event.get("hp_delta", 0)),
		"source_trace_count": _array_value(full_snapshot.get("source_trace", [])).size(),
	}))
	healthbox.queue_free()
	registry.free()
	quit(0)


func _quit_failed(healthbox, registry) -> void:
	if healthbox != null:
		healthbox.queue_free()
	if registry != null:
		registry.free()
	quit(1)


func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	_failed = true
	push_error(message)


func _dict_value(value) -> Dictionary:
	return value if typeof(value) == TYPE_DICTIONARY else {}


func _array_value(value) -> Array:
	return value if typeof(value) == TYPE_ARRAY else []
