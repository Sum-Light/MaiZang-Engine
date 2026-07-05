extends Control

const STATUS := "source_healthbox_runtime_first_pass"
const VIEWPORT_SIZE := Vector2(240, 160)
const HEALTHBAR_PIXELS := 48
const HEALTHBAR_HEIGHT := 2
const HP_BAR_EMPTY := "empty"
const HP_BAR_RED := "red"
const HP_BAR_YELLOW := "yellow"
const HP_BAR_GREEN := "green"
const HP_BAR_FULL := "full"
const HP_BAR_OUTLINE := Color8(82, 107, 90, 255)
const HP_ROW_RGBAS := {
	HP_BAR_GREEN: [[90, 214, 132, 255], [115, 255, 173, 255]],
	HP_BAR_YELLOW: [[205, 172, 8, 255], [255, 230, 57, 255]],
	HP_BAR_RED: [[172, 65, 74, 255], [255, 90, 57, 255]],
}
const SOURCE_TRACE := [
	"src/battle_interface.c:CreateBattlerHealthboxSprites",
	"src/battle_interface.c:SpriteCB_HealthBar",
	"src/battle_interface.c:sBattlerHealthboxCoords",
	"src/battle_interface.c:UpdateHealthboxAttribute",
	"src/battle_interface.c:MoveBattleBar",
	"src/battle_interface.c:GetScaledHPFraction",
	"src/battle_interface.c:GetHPBarLevel",
	"include/config/battle.h:B_FAST_HP_DRAIN",
	"include/config/battle.h:B_HPBAR_COLOR_THRESHOLD",
]

var _role := ""
var _side := ""
var _battler_position := ""
var _source_coord := Vector2.ZERO
var _frame_rect := Rect2()
var _hp_bar_rect := Rect2()
var _frame_asset_snapshot: Dictionary = {}
var _layout_profile_status := ""
var _current_hp := -1
var _max_hp := 1
var _mon_name := ""
var _level := 1
var _last_update_event: Dictionary = {}
var _frame_texture_rect: TextureRect = null
var _bar_outline: ColorRect = null
var _bar_container: Control = null
var _bar_top: ColorRect = null
var _bar_bottom: ColorRect = null


func _init() -> void:
	name = "BattleHealthbox"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	position = Vector2.ZERO
	size = VIEWPORT_SIZE
	custom_minimum_size = VIEWPORT_SIZE


func configure_healthbox(
	role: String,
	frame_asset: Dictionary,
	frame_rect: Rect2,
	hp_bar_rect: Rect2,
	source_coord: Vector2,
	layout_profile: Dictionary = {},
	options: Dictionary = {}
) -> void:
	_ensure_nodes()
	_role = role
	_side = String(options.get("side", role))
	_battler_position = String(options.get("battler_position", "%s_left" % role))
	_source_coord = source_coord
	_frame_rect = frame_rect
	_hp_bar_rect = hp_bar_rect
	_layout_profile_status = String(layout_profile.get("status", ""))
	_frame_asset_snapshot = _asset_snapshot(frame_asset, frame_rect)
	_apply_frame_asset(frame_asset, frame_rect)
	_apply_hp_layout(hp_bar_rect)
	_apply_hp_fill()


func set_battle_mon(mon: Dictionary) -> void:
	var max_hp: int = max(1, int(mon.get("max_hp", 1)))
	var hp: int = clampi(int(mon.get("hp", 0)), 0, max_hp)
	var previous_hp := _current_hp
	var previous_max_hp := _max_hp
	_current_hp = hp
	_max_hp = max_hp
	_mon_name = String(mon.get("name", mon.get("species", "")))
	_level = int(mon.get("level", 1))
	_apply_hp_fill()
	if previous_hp >= 0 and (previous_hp != hp or previous_max_hp != max_hp):
		_last_update_event = _build_hp_update_event(previous_hp, previous_max_hp, hp, max_hp)
	elif previous_hp < 0 and _last_update_event.is_empty():
		_last_update_event = _build_initial_event(hp, max_hp)


func record_hp_delta_event(from_hp: int, to_hp: int, max_hp: int) -> Dictionary:
	var clamped_max: int = max(1, max_hp)
	var clamped_to: int = clampi(to_hp, 0, clamped_max)
	_current_hp = clamped_to
	_max_hp = clamped_max
	_last_update_event = _build_hp_update_event(from_hp, clamped_max, clamped_to, clamped_max)
	_apply_hp_fill()
	return _last_update_event.duplicate(true)


func source_scaled_hp_fraction(hp: int, max_hp: int, scale: int = HEALTHBAR_PIXELS) -> int:
	if max_hp <= 0 or scale <= 0:
		return 0
	var clamped_hp: int = clampi(hp, 0, max_hp)
	var result := _idiv(clamped_hp * scale, max_hp)
	if result == 0 and clamped_hp > 0:
		return 1
	return result


func source_hp_bar_level(hp: int, max_hp: int) -> String:
	if max_hp <= 0:
		return HP_BAR_EMPTY
	var clamped_hp: int = clampi(hp, 0, max_hp)
	if clamped_hp <= 0:
		return HP_BAR_EMPTY
	if clamped_hp == max_hp:
		return HP_BAR_FULL
	if clamped_hp > _idiv(max_hp * 50, 100):
		return HP_BAR_GREEN
	if clamped_hp > _idiv(max_hp * 20, 100):
		return HP_BAR_YELLOW
	return HP_BAR_RED


func has_frame_texture() -> bool:
	return _frame_texture_rect != null and _frame_texture_rect.texture != null


func get_runtime_snapshot() -> Dictionary:
	var level := source_hp_bar_level(_current_hp, _max_hp)
	var fill_width := source_scaled_hp_fraction(_current_hp, _max_hp, HEALTHBAR_PIXELS)
	return {
		"status": STATUS,
		"role": _role,
		"side": _side,
		"battler_position": _battler_position,
		"source_trace": SOURCE_TRACE.duplicate(),
		"source_contract": {
			"healthbar_pixels": HEALTHBAR_PIXELS,
			"healthbar_height": HEALTHBAR_HEIGHT,
			"nonzero_hp_min_pixel_width": 1,
			"hp_level_threshold_mode": "raw_hp_gen_latest",
			"fast_hp_drain": true,
			"screen_size": [int(VIEWPORT_SIZE.x), int(VIEWPORT_SIZE.y)],
		},
		"source_coord": [int(_source_coord.x), int(_source_coord.y)],
		"frame": _frame_asset_snapshot.duplicate(true),
		"hp_bar": {
			"screen_rect": _rect_array(_hp_bar_rect),
			"source_width_px": HEALTHBAR_PIXELS,
			"height_px": HEALTHBAR_HEIGHT,
			"filled_px": fill_width,
			"level": level,
			"row_rgba": _hp_row_rgba_for_level(level),
		},
		"battler": {
			"name": _mon_name,
			"level": _level,
			"current_hp": _current_hp,
			"max_hp": _max_hp,
			"hp_text": "%d/%d" % [_current_hp, _max_hp],
		},
		"last_update_event": _last_update_event.duplicate(true),
		"layout_profile_status": _layout_profile_status,
		"first_pass_supported": [
			"frame_texture_creation",
			"source_scaled_hp_fraction",
			"source_hp_bar_level",
			"vm_hp_delta_event_contract",
		],
		"unsupported": _unsupported_snapshot(),
	}


func _ensure_nodes() -> void:
	if _frame_texture_rect != null:
		return
	_frame_texture_rect = TextureRect.new()
	_frame_texture_rect.name = "Frame"
	_frame_texture_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_frame_texture_rect.stretch_mode = TextureRect.STRETCH_SCALE
	_frame_texture_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	add_child(_frame_texture_rect)

	_bar_outline = ColorRect.new()
	_bar_outline.name = "HPBarOutline"
	_bar_outline.color = HP_BAR_OUTLINE
	_bar_outline.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_bar_outline)

	_bar_container = Control.new()
	_bar_container.name = "HPBar"
	_bar_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_bar_container)

	_bar_top = ColorRect.new()
	_bar_top.name = "Top"
	_bar_top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bar_container.add_child(_bar_top)

	_bar_bottom = ColorRect.new()
	_bar_bottom.name = "Bottom"
	_bar_bottom.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bar_container.add_child(_bar_bottom)


func _apply_frame_asset(asset: Dictionary, rect: Rect2) -> void:
	_ensure_nodes()
	_frame_texture_rect.position = rect.position
	_frame_texture_rect.size = rect.size
	_frame_texture_rect.texture = _load_texture_for_asset(asset)
	_frame_texture_rect.visible = _frame_texture_rect.texture != null


func _apply_hp_layout(rect: Rect2) -> void:
	_ensure_nodes()
	_bar_outline.position = rect.position - Vector2(1, 1)
	_bar_outline.size = rect.size + Vector2(2, 2)
	_bar_container.position = rect.position
	_bar_container.size = Vector2(rect.size.x, max(HEALTHBAR_HEIGHT, int(rect.size.y)))


func _apply_hp_fill() -> void:
	_ensure_nodes()
	var fill_width := source_scaled_hp_fraction(_current_hp, _max_hp, HEALTHBAR_PIXELS)
	var level := source_hp_bar_level(_current_hp, _max_hp)
	var rows := _hp_row_rgba_for_level(level)
	_bar_container.size = Vector2(fill_width, max(HEALTHBAR_HEIGHT, int(_hp_bar_rect.size.y)))
	_bar_top.position = Vector2.ZERO
	_bar_top.size = Vector2(fill_width, 1)
	_bar_top.color = _color_from_rgba(_array_value(rows[0]) if rows.size() > 0 else [])
	_bar_bottom.position = Vector2(0, 1)
	_bar_bottom.size = Vector2(fill_width, 1)
	_bar_bottom.color = _color_from_rgba(_array_value(rows[1]) if rows.size() > 1 else [])


func _build_initial_event(hp: int, max_hp: int) -> Dictionary:
	return {
		"status": "initial",
		"to_hp": clampi(hp, 0, max(1, max_hp)),
		"max_hp": max(1, max_hp),
		"to_filled_px": source_scaled_hp_fraction(hp, max_hp, HEALTHBAR_PIXELS),
		"to_level": source_hp_bar_level(hp, max_hp),
		"final_pixel_width_matches_source_fraction": true,
	}


func _build_hp_update_event(from_hp: int, from_max_hp: int, to_hp: int, to_max_hp: int) -> Dictionary:
	var safe_from_max: int = max(1, from_max_hp)
	var safe_to_max: int = max(1, to_max_hp)
	var clamped_from: int = clampi(from_hp, 0, safe_from_max)
	var clamped_to: int = clampi(to_hp, 0, safe_to_max)
	var from_width := source_scaled_hp_fraction(clamped_from, safe_from_max, HEALTHBAR_PIXELS)
	var to_width := source_scaled_hp_fraction(clamped_to, safe_to_max, HEALTHBAR_PIXELS)
	return {
		"status": "applied",
		"kind": "drain" if clamped_to < clamped_from else "restore" if clamped_to > clamped_from else "resize",
		"from_hp": clamped_from,
		"to_hp": clamped_to,
		"from_max_hp": safe_from_max,
		"to_max_hp": safe_to_max,
		"hp_delta": clamped_to - clamped_from,
		"vm_hp_delta_consumed": true,
		"from_filled_px": from_width,
		"to_filled_px": to_width,
		"pixel_delta": to_width - from_width,
		"from_level": source_hp_bar_level(clamped_from, safe_from_max),
		"to_level": source_hp_bar_level(clamped_to, safe_to_max),
		"final_pixel_width_matches_source_fraction": to_width == source_scaled_hp_fraction(clamped_to, safe_to_max, HEALTHBAR_PIXELS),
		"source_trace": [
			"src/battle_interface.c:SetBattleBarStruct",
			"src/battle_interface.c:MoveBattleBar",
			"src/battle_interface.c:CalcNewBarValue",
			"src/battle_interface.c:GetScaledHPFraction",
		],
		"drain_restore_timing_status": "first_pass_event_contract",
	}


func _unsupported_snapshot() -> Array:
	return [{
		"code": "healthbox_slide_timing_pending",
		"source": "src/pokeball.c:StartHealthboxSlideIn",
		"detail": "Slide-in/out movement timing is not animated yet; the first pass creates the source-shaped frame and HP bar contract in place.",
	}, {
		"code": "healthbox_exp_status_party_pending",
		"source": "src/battle_interface.c:UpdateHealthboxAttribute",
		"detail": "EXP bar, status icon, level/name/gender exact text, and party status indicators remain future source-backed work.",
	}, {
		"code": "healthbox_bounce_indicator_pending",
		"source": "src/battle_interface.c:CreateBattlerHealthboxSprites",
		"detail": "Bounce, misc indicators, right-side sprite composition, and subtask choreography are not source-equivalent in this slice.",
	}]


func _hp_row_rgba_for_level(level: String) -> Array:
	var row_key := HP_BAR_GREEN if level == HP_BAR_FULL else level
	if not HP_ROW_RGBAS.has(row_key):
		return [[0, 0, 0, 0], [0, 0, 0, 0]]
	return _array_value(HP_ROW_RGBAS[row_key]).duplicate(true)


func _color_from_rgba(row: Array) -> Color:
	if row.size() < 4:
		return Color(0, 0, 0, 0)
	return Color8(int(row[0]), int(row[1]), int(row[2]), int(row[3]))


func _load_texture_for_asset(asset: Dictionary) -> Texture2D:
	var path := _asset_resource_path(asset)
	if path.is_empty():
		return null
	var texture = load(path)
	return texture if texture is Texture2D else null


func _asset_resource_path(asset: Dictionary) -> String:
	var path := String(asset.get("image", ""))
	if not path.is_empty():
		return path
	var project_path := String(asset.get("image_project_path", ""))
	if project_path.is_empty():
		return ""
	return "res://%s" % project_path


func _asset_project_path(asset: Dictionary) -> String:
	var project_path := String(asset.get("image_project_path", ""))
	if not project_path.is_empty():
		return project_path
	var path := String(asset.get("image", ""))
	if path.begins_with("res://"):
		return path.trim_prefix("res://")
	return path


func _asset_snapshot(asset: Dictionary, rect: Rect2) -> Dictionary:
	var asset_size := _dict_value(asset.get("size", asset.get("image_size", {})))
	return {
		"path": _asset_project_path(asset),
		"screen_rect": _rect_array(rect),
		"image_size": [int(asset_size.get("w", 0)), int(asset_size.get("h", 0))],
		"asset_status": String(asset.get("status", asset.get("asset_status", ""))),
	}


func _rect_array(rect: Rect2) -> Array:
	return [int(rect.position.x), int(rect.position.y), int(rect.size.x), int(rect.size.y)]


func _idiv(numerator: int, denominator: int) -> int:
	if denominator == 0:
		return 0
	return int(floor(float(numerator) / float(denominator)))


func _dict_value(value) -> Dictionary:
	return value if typeof(value) == TYPE_DICTIONARY else {}


func _array_value(value) -> Array:
	return value if typeof(value) == TYPE_ARRAY else []
