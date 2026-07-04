extends RefCounted

const DEFAULT_TRAINER_REF := "TRAINER_SAWYER_1"
const DEFAULT_RANDOM_MIN_LEVEL := 1
const DEFAULT_RANDOM_MAX_LEVEL := 100
const DEFAULT_DEBUG_PLAYER_SPECIES := "SPECIES_TORCHIC"
const DEFAULT_DEBUG_PLAYER_MOVES := ["MOVE_SCRATCH", "MOVE_EMBER"]
const REQUIRED_BASE_STATS := ["hp", "attack", "defense", "speed", "sp_attack", "sp_defense"]

var data_registry: Node = null
var battle_engine: Node = null
var party_runtime: Node = null
var game_state: Node = null
var event_manager: Node = null
var selected_trainer_ref := DEFAULT_TRAINER_REF


func configure(
	new_data_registry: Node,
	new_battle_engine: Node,
	new_party_runtime: Node,
	new_game_state: Node,
	new_event_manager: Node = null
) -> void:
	data_registry = new_data_registry
	battle_engine = new_battle_engine
	party_runtime = new_party_runtime
	game_state = new_game_state
	event_manager = new_event_manager


func launch_random_wild_battle(options: Dictionary = {}) -> Dictionary:
	var encounter := create_random_wild_encounter(options)
	if String(encounter.get("status", "")) != "ok":
		return encounter
	var player_party_result := _debug_player_battle_party(int(encounter.get("level", 1)), options)
	if String(player_party_result.get("status", "")) == "error":
		return player_party_result
	var player_party = player_party_result.get("battle_party", [])
	if typeof(player_party) != TYPE_ARRAY:
		player_party = []
	if player_party.is_empty():
		return {
			"status": "error",
			"error": "missing_debug_player_party",
			"detail": "A debug wild battle still needs at least one player battler.",
		}
	if event_manager == null or not event_manager.has_method("request_debug_wild_battle_start"):
		return {
			"status": "missing_event_manager_bridge",
			"debug_encounter": encounter,
			"debug_player_party": player_party_result,
		}
	var request := {
		"encounter": encounter,
		"player_battle_party": player_party,
		"debug_player_party": player_party_result,
		"battle_origin": "debug_random_wild_battle",
		"debug_fixture": true,
		"enable_battle_scene_handoff": true,
		"map": String(options.get("map", "DEBUG_RANDOM_WILD")),
		"map_transition_type": String(options.get("map_transition_type", "normal")),
		"position": options.get("position", _player_position()),
	}
	var result = event_manager.request_debug_wild_battle_start(request)
	if typeof(result) != TYPE_DICTIONARY:
		return {"status": "invalid_event_manager_result"}
	result["debug_encounter"] = encounter
	result["debug_player_party"] = player_party_result
	return result


func create_random_wild_encounter(options: Dictionary = {}) -> Dictionary:
	if battle_engine == null or not battle_engine.has_method("create_wild_battle_state"):
		return {"status": "error", "error": "missing_battle_engine"}
	var candidates := _battle_ready_species_candidates()
	if candidates.is_empty():
		return {
			"status": "error",
			"error": "missing_battle_ready_species",
			"detail": "No generated species records with complete base stats were found.",
		}
	var selected_index := _selected_species_index(candidates.size(), options)
	var record = candidates[selected_index]
	if typeof(record) != TYPE_DICTIONARY:
		return {"status": "error", "error": "invalid_species_candidate"}
	var level := _selected_level(options)
	var symbol := String(record.get("symbol", ""))
	return {
		"status": "ok",
		"species": symbol,
		"species_id": int(record.get("id", -1)),
		"level": level,
		"area": "debug_random",
		"map": String(options.get("map", "DEBUG_RANDOM_WILD")),
		"record_label": "debug_random_species_level",
		"slot_index": selected_index,
		"debug_random": true,
		"random_pool_size": candidates.size(),
		"source": "Godot-only debug battle launcher",
		"unsupported": [{
			"code": "debug_random_wild_not_source_encounter",
			"source": "Godot-only debug battle launcher",
			"detail": "F6 intentionally selects a random generated species and random level for fast battle testing; it does not reproduce grass, water, fishing, Repel, Lure, slot-probability, or map encounter rules.",
		}],
	}


func launch_trainer_battle(trainer_ref = selected_trainer_ref, options: Dictionary = {}) -> Dictionary:
	var resolved := resolve_trainer_ref(trainer_ref)
	if String(resolved.get("status", "")) != "ok":
		return resolved
	selected_trainer_ref = String(resolved.get("request_ref", trainer_ref))
	if event_manager == null or not event_manager.has_method("request_trainer_battle_start"):
		return {"status": "missing_event_manager_bridge", "trainer": resolved.get("trainer", {})}
	var request := {
		"trainer_id": resolved.get("battle_ref", selected_trainer_ref),
		"map": String(options.get("map", "DEBUG_TRAINER_BATTLE")),
		"position": options.get("position", _player_position()),
		"debug_fixture": true,
		"debug_allow_empty_party_fallback": true,
		"battle_origin": "debug_trainer_selector",
		"map_transition_type": String(options.get("map_transition_type", "normal")),
	}
	var result = event_manager.request_trainer_battle_start(request)
	if typeof(result) != TYPE_DICTIONARY:
		return {"status": "invalid_event_manager_result"}
	result["selected_trainer"] = resolved
	return result


func set_selected_trainer_ref(trainer_ref) -> Dictionary:
	var resolved := resolve_trainer_ref(trainer_ref)
	if String(resolved.get("status", "")) == "ok":
		selected_trainer_ref = String(resolved.get("request_ref", trainer_ref))
	return resolved


func resolve_trainer_ref(trainer_ref) -> Dictionary:
	if data_registry == null or not data_registry.has_method("get_trainer_record"):
		return {"status": "error", "error": "missing_data_registry"}
	var record = data_registry.get_trainer_record(trainer_ref)
	if typeof(record) != TYPE_DICTIONARY or record.is_empty():
		return {
			"status": "unknown_trainer",
			"request_ref": str(trainer_ref),
			"detail": "Enter a numeric trainer id, a full TRAINER_* symbol, or a short trainer symbol.",
		}
	var symbol := String(record.get("symbol", ""))
	return {
		"status": "ok",
		"request_ref": str(trainer_ref),
		"battle_ref": int(record.get("id", -1)) if str(trainer_ref).is_valid_int() else symbol,
		"trainer": {
			"symbol": symbol,
			"id": int(record.get("id", -1)),
			"name": _display_text(record.get("name", {}), symbol),
			"class": _constant_symbol(record.get("trainer_class", {})),
			"battle_type": record.get("battle_type", {}),
		},
	}


func selected_trainer_snapshot() -> Dictionary:
	return resolve_trainer_ref(selected_trainer_ref)


func _debug_player_battle_party(wild_level: int, options: Dictionary) -> Dictionary:
	if game_state != null and game_state.has_method("get_player_party"):
		var party: Array = game_state.get_player_party()
		if typeof(party) == TYPE_ARRAY and not party.is_empty():
			var battle_party: Array = party
			if party_runtime != null and party_runtime.has_method("build_battle_party"):
				var built: Array = party_runtime.build_battle_party(party)
				if typeof(built) == TYPE_ARRAY and not built.is_empty():
					battle_party = built
			return {
				"status": "existing_party",
				"party": party,
				"battle_party": battle_party,
				"temporary": false,
			}
	var fallback_level := clampi(int(options.get("debug_player_level", wild_level)), 1, 100)
	var mon := {}
	if party_runtime != null and party_runtime.has_method("create_party_mon"):
		mon = party_runtime.create_party_mon(DEFAULT_DEBUG_PLAYER_SPECIES, fallback_level, {
			"nickname": "Debug Torchic",
			"moves": DEFAULT_DEBUG_PLAYER_MOVES.duplicate(),
			"debug_only": true,
			"met_location": String(options.get("map", "DEBUG_RANDOM_WILD")),
		})
	elif battle_engine != null and battle_engine.has_method("create_battle_mon"):
		mon = battle_engine.create_battle_mon(DEFAULT_DEBUG_PLAYER_SPECIES, fallback_level, {
			"moves": DEFAULT_DEBUG_PLAYER_MOVES.duplicate(),
		})
	else:
		return {"status": "error", "error": "missing_party_runtime"}
	if typeof(mon) != TYPE_DICTIONARY or String(mon.get("status", "")) != "ok":
		return mon if typeof(mon) == TYPE_DICTIONARY else {"status": "error", "error": "debug_player_create_failed"}
	mon["debug_only"] = true
	mon["debug_source"] = "debug random wild battle fallback"
	var party := [mon]
	var battle_party := party
	if party_runtime != null and party_runtime.has_method("build_battle_party"):
		var built_party = party_runtime.build_battle_party(party)
		if typeof(built_party) == TYPE_ARRAY and not built_party.is_empty():
			battle_party = built_party
	return {
		"status": "debug_fallback_created",
		"party": party,
		"battle_party": battle_party,
		"debug_fallback_created": true,
		"temporary": true,
		"species": DEFAULT_DEBUG_PLAYER_SPECIES,
		"level": fallback_level,
		"unsupported": [{
			"code": "debug_only_temporary_player_party",
			"source": "Godot-only debug fixture overlay",
			"detail": "A temporary player Pokemon is created only when no real player party exists, so F6/F7 can enter battle before the starter and party UI flows are ported.",
		}],
	}


func _battle_ready_species_candidates() -> Array:
	if data_registry == null or not data_registry.has_method("get_species_data"):
		return []
	var species_data: Dictionary = data_registry.get_species_data()
	if typeof(species_data) != TYPE_DICTIONARY:
		return []
	var records: Dictionary = species_data.get("species", {})
	if typeof(records) != TYPE_DICTIONARY:
		return []
	var candidates: Array = []
	var keys: Array = records.keys()
	keys.sort()
	for key in keys:
		var record = records[key]
		if typeof(record) != TYPE_DICTIONARY:
			continue
		var symbol := String(record.get("symbol", key))
		if symbol.is_empty() or symbol == "SPECIES_NONE" or symbol == "SPECIES_EGG":
			continue
		var base_stats = record.get("base_stats", {})
		if typeof(base_stats) != TYPE_DICTIONARY:
			continue
		var complete := true
		for stat_key in REQUIRED_BASE_STATS:
			if not base_stats.has(stat_key):
				complete = false
				break
		if complete:
			candidates.append(record)
	return candidates


func _selected_species_index(pool_size: int, options: Dictionary) -> int:
	if options.has("species_symbol") or options.has("species"):
		var requested := String(options.get("species_symbol", options.get("species", "")))
		var candidates := _battle_ready_species_candidates()
		for index in range(candidates.size()):
			var record = candidates[index]
			if typeof(record) == TYPE_DICTIONARY and String(record.get("symbol", "")) == _species_symbol(requested):
				return index
	if options.has("species_index"):
		return clampi(int(options.get("species_index", 0)), 0, max(0, pool_size - 1))
	var rng := _rng(options)
	return rng.randi_range(0, max(0, pool_size - 1))


func _selected_level(options: Dictionary) -> int:
	if options.has("level"):
		return clampi(int(options.get("level", DEFAULT_RANDOM_MIN_LEVEL)), 1, 100)
	var min_level := clampi(int(options.get("min_level", DEFAULT_RANDOM_MIN_LEVEL)), 1, 100)
	var max_level := clampi(int(options.get("max_level", DEFAULT_RANDOM_MAX_LEVEL)), 1, 100)
	if min_level > max_level:
		var swap := min_level
		min_level = max_level
		max_level = swap
	var rng := _rng(options)
	return rng.randi_range(min_level, max_level)


func _rng(options: Dictionary) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	if options.has("seed"):
		rng.seed = int(options.get("seed", 1))
	else:
		rng.randomize()
	return rng


func _player_position() -> Vector2i:
	if game_state != null:
		return game_state.player_grid_position
	return Vector2i.ZERO


func _species_symbol(value: String) -> String:
	var normalized := value.strip_edges().to_upper()
	if normalized.is_empty():
		return ""
	return normalized if normalized.begins_with("SPECIES_") else "SPECIES_%s" % normalized


func _constant_symbol(value) -> String:
	if typeof(value) == TYPE_DICTIONARY:
		return String(value.get("symbol", value.get("name", "")))
	return String(value)


func _display_text(value, fallback: String) -> String:
	if typeof(value) == TYPE_DICTIONARY:
		var display := String(value.get("display_text", ""))
		if not display.is_empty():
			return display
		var source_text := String(value.get("source_text", ""))
		if not source_text.is_empty():
			return source_text
	return fallback
