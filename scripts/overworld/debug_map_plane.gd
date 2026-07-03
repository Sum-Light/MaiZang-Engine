extends Node2D

@export var map_size := Vector2i(20, 20)
@export var tile_size := 16

var block_ids: Array = []
var tileset_data: Dictionary = {}
var _atlas_texture: Texture2D = null
var _atlas_tile_size := 16
var _atlas_columns := 0
var _atlas_total_metatiles := 0
var _door_animation_overlays: Dictionary = {}
var _door_animation_texture_cache: Dictionary = {}

const FALLBACK_TILE_SIZE := 16
const FALLBACK_MAP_SIZE := Vector2i(20, 20)
const TILE_A := Color(0.64, 0.78, 0.50, 1.0)
const TILE_B := Color(0.56, 0.72, 0.45, 1.0)
const GRID_LINE := Color(0.22, 0.31, 0.24, 0.55)
const BORDER_LINE := Color(0.08, 0.12, 0.10, 0.95)
const BLOCK_COLORS := [
	Color(0.44, 0.68, 0.36, 1.0),
	Color(0.58, 0.76, 0.42, 1.0),
	Color(0.72, 0.66, 0.45, 1.0),
	Color(0.43, 0.58, 0.72, 1.0),
	Color(0.55, 0.46, 0.70, 1.0),
	Color(0.70, 0.52, 0.42, 1.0),
	Color(0.45, 0.70, 0.62, 1.0),
	Color(0.68, 0.70, 0.50, 1.0),
]


func configure_from_map_data(map_data: Dictionary, new_tileset_data: Dictionary = {}) -> void:
	var registry := get_node_or_null("/root/DataRegistry")
	tile_size = FALLBACK_TILE_SIZE
	_configure_tileset_data(new_tileset_data)

	if map_data.is_empty():
		map_size = _registry_start_map_size(registry)
		block_ids = []
		clear_door_animations()
		queue_redraw()
		return

	var layout_info = map_data.get("layout", {})
	if typeof(layout_info) == TYPE_DICTIONARY:
		map_size = Vector2i(
			int(layout_info.get("width", map_size.x)),
			int(layout_info.get("height", map_size.y))
		)
	block_ids = map_data.get("block_ids", [])
	clear_door_animations()
	queue_redraw()


func _draw() -> void:
	for y in range(map_size.y):
		for x in range(map_size.x):
			var rect := Rect2(x * tile_size, y * tile_size, tile_size, tile_size)
			var block_id := _get_block_id(x, y)
			if not _draw_atlas_tile(block_id, rect):
				var fill := _get_tile_color(block_id, x, y)
				draw_rect(rect, fill, true)
			draw_rect(rect, GRID_LINE, false, 1.0)

	var border := Rect2(Vector2.ZERO, Vector2(map_size.x * tile_size, map_size.y * tile_size))
	_draw_door_animation_overlays()
	draw_rect(border, BORDER_LINE, false, 2.0)


func set_door_animation_frame(position: Vector2i, animation: Dictionary, frame_index: int) -> bool:
	if frame_index < 0:
		clear_door_animation(position)
		return true

	var texture := _door_animation_texture(animation)
	if texture == null:
		return false

	var frame := _door_animation_frame(animation, frame_index)
	if frame.is_empty():
		return false

	_door_animation_overlays[_cell_key(position)] = {
		"position": position,
		"texture": texture,
		"source_rect": frame["source_rect"],
		"frame_size": frame["frame_size"],
	}
	queue_redraw()
	return true


func clear_door_animation(position: Vector2i) -> void:
	var key := _cell_key(position)
	if _door_animation_overlays.has(key):
		_door_animation_overlays.erase(key)
		queue_redraw()


func clear_door_animations() -> void:
	if _door_animation_overlays.is_empty():
		return
	_door_animation_overlays.clear()
	queue_redraw()


func get_door_animation_overlay_count() -> int:
	return _door_animation_overlays.size()


func _configure_tileset_data(new_tileset_data: Dictionary) -> void:
	tileset_data = new_tileset_data
	_atlas_texture = null
	_atlas_tile_size = tile_size
	_atlas_columns = 0
	_atlas_total_metatiles = 0

	if tileset_data.is_empty():
		return

	var atlas_info = tileset_data.get("atlas", {})
	if typeof(atlas_info) != TYPE_DICTIONARY:
		return

	_atlas_tile_size = int(atlas_info.get("tile_size", tile_size))
	_atlas_columns = int(atlas_info.get("columns", 0))
	_atlas_total_metatiles = int(atlas_info.get("total_metatiles", 0))
	if _atlas_tile_size > 0:
		tile_size = _atlas_tile_size

	var image_path := String(atlas_info.get("image", ""))
	if image_path.is_empty():
		return

	var loaded_resource := load(image_path)
	if loaded_resource is Texture2D:
		_atlas_texture = loaded_resource
		return

	var image := Image.new()
	var load_error := image.load(image_path)
	if load_error != OK:
		push_warning("Could not load generated tileset atlas: %s" % image_path)
		return

	_atlas_texture = ImageTexture.create_from_image(image)


func _get_block_id(x: int, y: int) -> int:
	if y < block_ids.size():
		var row = block_ids[y]
		if typeof(row) == TYPE_ARRAY and x < row.size():
			return int(row[x])
	return -1


func _draw_atlas_tile(block_id: int, rect: Rect2) -> bool:
	if _atlas_texture == null or _atlas_columns <= 0 or block_id < 0:
		return false
	if _atlas_total_metatiles > 0 and block_id >= _atlas_total_metatiles:
		return false

	var atlas_column := block_id % _atlas_columns
	var atlas_row := int(floor(float(block_id) / float(_atlas_columns)))
	var source_rect := Rect2(
		atlas_column * _atlas_tile_size,
		atlas_row * _atlas_tile_size,
		_atlas_tile_size,
		_atlas_tile_size
	)
	draw_texture_rect_region(_atlas_texture, rect, source_rect)
	return true


func _draw_door_animation_overlays() -> void:
	for overlay in _door_animation_overlays.values():
		if typeof(overlay) != TYPE_DICTIONARY:
			continue
		var texture = overlay.get("texture", null)
		if not texture is Texture2D:
			continue
		var position = overlay.get("position", Vector2i.ZERO)
		if typeof(position) != TYPE_VECTOR2I:
			continue
		var source_rect = overlay.get("source_rect", Rect2())
		if typeof(source_rect) != TYPE_RECT2:
			continue
		var frame_size = overlay.get("frame_size", Vector2(tile_size, tile_size * 2))
		if typeof(frame_size) != TYPE_VECTOR2:
			continue
		var dest_rect := Rect2(
			position.x * tile_size,
			position.y * tile_size,
			frame_size.x,
			frame_size.y
		)
		draw_texture_rect_region(texture, dest_rect, source_rect)


func _door_animation_texture(animation: Dictionary) -> Texture2D:
	var image_path := String(animation.get("image", ""))
	if image_path.is_empty():
		return null
	if _door_animation_texture_cache.has(image_path):
		var cached = _door_animation_texture_cache[image_path]
		return cached if cached is Texture2D else null

	var image := Image.new()
	if image.load(image_path) != OK:
		push_warning("Could not load generated door animation atlas: %s" % image_path)
		return null

	var texture := ImageTexture.create_from_image(image)
	_door_animation_texture_cache[image_path] = texture
	return texture


func _door_animation_frame(animation: Dictionary, frame_index: int) -> Dictionary:
	var frames = animation.get("frames", [])
	if typeof(frames) != TYPE_ARRAY:
		return {}

	var frame_size_info = animation.get("frame_size", {})
	var frame_size := Vector2(tile_size, tile_size * 2)
	if typeof(frame_size_info) == TYPE_DICTIONARY:
		frame_size = Vector2(
			float(frame_size_info.get("w", frame_size.x)),
			float(frame_size_info.get("h", frame_size.y))
		)

	for frame in frames:
		if typeof(frame) != TYPE_DICTIONARY or int(frame.get("index", -1)) != frame_index:
			continue
		var rect_info = frame.get("source_rect", {})
		if typeof(rect_info) != TYPE_DICTIONARY:
			return {}
		return {
			"source_rect": Rect2(
				float(rect_info.get("x", 0)),
				float(rect_info.get("y", 0)),
				float(rect_info.get("w", frame_size.x)),
				float(rect_info.get("h", frame_size.y))
			),
			"frame_size": frame_size,
		}
	return {}


func _cell_key(cell: Vector2i) -> String:
	return "%d,%d" % [cell.x, cell.y]


func _registry_start_map_size(registry: Node) -> Vector2i:
	if registry != null and registry.has_method("get_start_map_size"):
		var size = registry.call("get_start_map_size")
		if typeof(size) == TYPE_VECTOR2I:
			return size
	return FALLBACK_MAP_SIZE


func _get_tile_color(block_id: int, x: int, y: int) -> Color:
	if block_id >= 0:
		return BLOCK_COLORS[block_id % BLOCK_COLORS.size()]
	return TILE_A if (x + y) % 2 == 0 else TILE_B
