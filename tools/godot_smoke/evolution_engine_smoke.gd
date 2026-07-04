extends SceneTree

const DATA_REGISTRY_SCRIPT := preload("res://scripts/autoload/data_registry.gd")
const EVOLUTION_ENGINE_SCRIPT := preload("res://scripts/autoload/evolution_engine.gd")

var _failed := false


func _init() -> void:
	var registry = DATA_REGISTRY_SCRIPT.new()
	registry._ready()

	var engine = EVOLUTION_ENGINE_SCRIPT.new()
	engine.configure_registry(registry)

	var bulbasaur_15 := engine.get_evolution_target_species({
		"species": "SPECIES_BULBASAUR",
		"level": 15,
	}, "EVO_MODE_NORMAL")
	_assert(String(bulbasaur_15.get("status", "")) == "no_evolution", "expected level 15 Bulbasaur to not evolve")
	_assert(String(bulbasaur_15.get("target_species", "")) == "SPECIES_NONE", "expected no level 15 Bulbasaur target")

	var bulbasaur_16 := engine.get_evolution_target_species({
		"species": "SPECIES_BULBASAUR",
		"level": 16,
	}, "EVO_MODE_NORMAL")
	_assert(String(bulbasaur_16.get("status", "")) == "ok", "expected level 16 Bulbasaur evolution")
	_assert(String(bulbasaur_16.get("target_species", "")) == "SPECIES_IVYSAUR", "expected Bulbasaur to target Ivysaur")
	_assert(bool(bulbasaur_16.get("can_stop_evolution", false)), "expected normal level evolution to be stoppable")

	var bulbasaur_everstone := engine.get_evolution_target_species({
		"species": "SPECIES_BULBASAUR",
		"level": 16,
		"held_item": "ITEM_EVERSTONE",
	}, "EVO_MODE_NORMAL")
	_assert(String(bulbasaur_everstone.get("status", "")) == "blocked", "expected Everstone to block normal evolution")
	_assert(String(bulbasaur_everstone.get("block_reason", "")) == "held_item_prevent_evolve", "expected Everstone block reason")

	var eevee_thunder := engine.get_evolution_target_species({
		"species": "SPECIES_EEVEE",
		"level": 20,
	}, "EVO_MODE_ITEM_USE", {
		"evolution_item": "ITEM_THUNDER_STONE",
	})
	_assert(String(eevee_thunder.get("status", "")) == "ok", "expected Thunder Stone Eevee evolution")
	_assert(String(eevee_thunder.get("target_species", "")) == "SPECIES_JOLTEON", "expected Eevee to target Jolteon")
	_assert(not bool(eevee_thunder.get("can_stop_evolution", true)), "expected item-use evolution to be unstoppable")

	var eevee_item_check_everstone := engine.get_evolution_target_species({
		"species": "SPECIES_EEVEE",
		"level": 20,
		"held_item": "ITEM_EVERSTONE",
	}, "EVO_MODE_ITEM_CHECK", {
		"evolution_item": "ITEM_THUNDER_STONE",
	})
	_assert(String(eevee_item_check_everstone.get("status", "")) == "ok", "expected item-check to ignore Everstone")
	_assert(String(eevee_item_check_everstone.get("target_species", "")) == "SPECIES_JOLTEON", "expected item-check Jolteon target")

	var eevee_item_use_everstone := engine.get_evolution_target_species({
		"species": "SPECIES_EEVEE",
		"level": 20,
		"held_item": "ITEM_EVERSTONE",
	}, "EVO_MODE_ITEM_USE", {
		"evolution_item": "ITEM_THUNDER_STONE",
	})
	_assert(String(eevee_item_use_everstone.get("status", "")) == "blocked", "expected item-use to respect Everstone")

	var sylveon := engine.get_evolution_target_species({
		"species": "SPECIES_EEVEE",
		"level": 1,
		"friendship": 160,
		"moves": ["MOVE_DISARMING_VOICE"],
	}, "EVO_MODE_NORMAL", {
		"time_of_day": "TIME_NIGHT",
	})
	_assert(String(sylveon.get("target_species", "")) == "SPECIES_SYLVEON", "expected Eevee source order to prefer Sylveon before day/night forms")

	var umbreon := engine.get_evolution_target_species({
		"species": "SPECIES_EEVEE",
		"level": 1,
		"friendship": 160,
		"moves": ["MOVE_TACKLE"],
	}, "EVO_MODE_NORMAL", {
		"time_of_day": "TIME_NIGHT",
	})
	_assert(String(umbreon.get("target_species", "")) == "SPECIES_UMBREON", "expected night Eevee without Fairy move to target Umbreon")

	var tyrogue_low_attack := engine.get_evolution_target_species({
		"species": "SPECIES_TYROGUE",
		"level": 20,
		"stats": {"attack": 10, "defense": 11},
	}, "EVO_MODE_NORMAL")
	var tyrogue_high_attack := engine.get_evolution_target_species({
		"species": "SPECIES_TYROGUE",
		"level": 20,
		"stats": {"attack": 12, "defense": 11},
	}, "EVO_MODE_NORMAL")
	var tyrogue_equal_stats := engine.get_evolution_target_species({
		"species": "SPECIES_TYROGUE",
		"level": 20,
		"stats": {"attack": 11, "defense": 11},
	}, "EVO_MODE_NORMAL")
	_assert(String(tyrogue_low_attack.get("target_species", "")) == "SPECIES_HITMONCHAN", "expected Tyrogue low attack target")
	_assert(String(tyrogue_high_attack.get("target_species", "")) == "SPECIES_HITMONLEE", "expected Tyrogue high attack target")
	_assert(String(tyrogue_equal_stats.get("target_species", "")) == "SPECIES_HITMONTOP", "expected Tyrogue equal stats target")

	var nincada_primary := engine.get_evolution_target_species({
		"species": "SPECIES_NINCADA",
		"level": 20,
	}, "EVO_MODE_NORMAL")
	_assert(String(nincada_primary.get("target_species", "")) == "SPECIES_NINJASK", "expected Nincada primary evolution target")

	var shedinja := engine.get_split_evolution_candidate("SPECIES_NINCADA", "SPECIES_NINJASK", {
		"species": "SPECIES_NINCADA",
		"level": 20,
	}, {
		"party_count": 5,
		"bag_items": {"ITEM_POKE_BALL": 1},
	})
	_assert(String(shedinja.get("status", "")) == "ok", "expected Shedinja split candidate")
	_assert(String(shedinja.get("target_species", "")) == "SPECIES_SHEDINJA", "expected Shedinja target")
	_assert(_has_pending_removal(shedinja, "ITEM_POKE_BALL", 1), "expected Shedinja Poke Ball pending removal")

	var shedinja_party_full := engine.get_split_evolution_candidate("NINCADA", "NINJASK", {
		"species": "SPECIES_NINCADA",
		"level": 20,
	}, {
		"party_count": 6,
		"bag_items": {"ITEM_POKE_BALL": 1},
	})
	_assert(String(shedinja_party_full.get("status", "")) == "blocked", "expected full party to block Shedinja")
	_assert(String(shedinja_party_full.get("block_reason", "")) == "party_full", "expected Shedinja party-full reason")

	var tandemaus_normal := engine.get_evolution_target_species({
		"species": "SPECIES_TANDEMAUS",
		"level": 25,
		"personality": 1,
	}, "EVO_MODE_NORMAL")
	var maushold_four := engine.get_evolution_target_species({
		"species": "SPECIES_TANDEMAUS",
		"level": 25,
		"personality": 1,
	}, "EVO_MODE_BATTLE_ONLY")
	var maushold_three := engine.get_evolution_target_species({
		"species": "SPECIES_TANDEMAUS",
		"level": 25,
		"personality": 0,
	}, "EVO_MODE_BATTLE_ONLY")
	_assert(String(tandemaus_normal.get("target_species", "")) == "SPECIES_NONE", "expected Tandemaus battle-only method to skip normal mode")
	_assert(String(maushold_four.get("target_species", "")) == "SPECIES_MAUSHOLD_FOUR", "expected Tandemaus PID > 0 target")
	_assert(String(maushold_three.get("target_species", "")) == "SPECIES_MAUSHOLD_THREE", "expected Tandemaus PID == 0 target")

	var ivysaur_pre := engine.get_species_pre_evolution("IVYSAUR")
	_assert(String(ivysaur_pre.get("status", "")) == "ok", "expected Ivysaur pre-evolution")
	_assert(String(ivysaur_pre.get("source_species", "")) == "SPECIES_BULBASAUR", "expected Ivysaur pre-evolution source")

	if _failed:
		return

	print(JSON.stringify({
		"evolution_engine_smoke": "ok",
		"bulbasaur_target": String(bulbasaur_16.get("target_species", "")),
		"eevee_item_target": String(eevee_thunder.get("target_species", "")),
		"shedinja_target": String(shedinja.get("target_species", "")),
		"maushold_four_target": String(maushold_four.get("target_species", "")),
	}))
	engine.free()
	registry.free()
	quit(0)


func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	push_error(message)
	_failed = true
	quit(1)


func _has_pending_removal(result: Dictionary, item_symbol: String, count: int) -> bool:
	var removals = result.get("pending_item_removals", [])
	if typeof(removals) != TYPE_ARRAY:
		return false
	for removal in removals:
		if typeof(removal) != TYPE_DICTIONARY:
			continue
		if String(removal.get("item", "")) == item_symbol and int(removal.get("count", 0)) == count:
			return true
	return false
