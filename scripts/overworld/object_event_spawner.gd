extends Node2D

const OBJECT_EVENT_PLACEHOLDER := preload("res://scripts/overworld/object_event_placeholder.gd")

var spawned_count := 0


func configure_from_events(object_events: Array, tile_size: int) -> void:
	_clear_spawned_events()
	for object_event in object_events:
		if typeof(object_event) != TYPE_DICTIONARY:
			continue
		var placeholder = OBJECT_EVENT_PLACEHOLDER.new()
		add_child(placeholder)
		placeholder.configure(object_event, tile_size)
		spawned_count += 1


func _clear_spawned_events() -> void:
	for child in get_children():
		child.queue_free()
	spawned_count = 0
