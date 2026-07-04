extends SceneTree

const DATA_REGISTRY_SCRIPT := preload("res://scripts/autoload/data_registry.gd")

var _failed := false


func _init() -> void:
	var registry = DATA_REGISTRY_SCRIPT.new()
	registry._ready()

	var items_data := registry.get_items_data()
	var stats = items_data.get("stats", {})
	_assert(typeof(items_data) == TYPE_DICTIONARY and not items_data.is_empty(), "expected items data")
	_assert(typeof(stats) == TYPE_DICTIONARY, "expected item stats")
	_assert(int(stats.get("item_count", 0)) == 874, "unexpected item count")
	_assert(int(stats.get("items_count_constant", 0)) == 874, "unexpected ITEMS_COUNT value")
	_assert(int(stats.get("highest_item_id", 0)) == 873, "unexpected highest item id")
	_assert(int(stats.get("items_with_descriptions", 0)) == 874, "unexpected description count")
	_assert(int(stats.get("items_with_effect_refs", 0)) == 139, "unexpected item effect reference count")
	_assert(int(stats.get("resolved_item_effect_count", 0)) == 72, "unexpected resolved item effect count")
	_assert(int(stats.get("item_effect_count", 0)) == 72, "unexpected item effect count")
	_assert(int(stats.get("preprocessor_warning_count", -1)) == 0, "expected no item preprocessor warnings")
	_assert(int(stats.get("warning_count", -1)) == 0, "expected no item export warnings")
	_assert(int(stats.get("unsupported_field_count", -1)) == 0, "expected no unsupported item fields")

	var constants = _dict_field(items_data, "constants")
	var item_constants = _dict_field(constants, "items")
	_assert(int(_dict_field(item_constants, "ITEMS_COUNT").get("value", -1)) == 874, "expected ITEMS_COUNT constant")
	_assert(int(_dict_field(item_constants, "ITEM_TM_THUNDER").get("value", -1)) == 606, "expected TM Thunder alias constant")

	var none := registry.get_item_record("ITEM_NONE")
	var poke_ball := registry.get_item_record("ITEM_POKE_BALL")
	var poke_ball_by_id := registry.get_item_record(1)
	var poke_ball_by_short_name := registry.get_item_record("poke_ball")
	var strange_ball := registry.get_item_record("ITEM_STRANGE_BALL")
	_assert(String(none.get("symbol", "")) == "ITEM_NONE", "expected ITEM_NONE")
	_assert(int(none.get("id", -1)) == 0, "unexpected ITEM_NONE id")
	_assert(String(_text_field(none, "name").get("display_text", "")).length() > 0, "expected ITEM_NONE name")
	_assert(String(poke_ball_by_id.get("symbol", "")) == "ITEM_POKE_BALL", "expected item id lookup")
	_assert(String(poke_ball_by_short_name.get("symbol", "")) == "ITEM_POKE_BALL", "expected short item symbol lookup")
	_assert(int(poke_ball.get("id", -1)) == 1, "unexpected Poke Ball id")
	_assert(int(poke_ball.get("price", -1)) == 200, "unexpected Poke Ball price")
	_assert(int(poke_ball.get("sell_price", -1)) == 50, "unexpected Poke Ball sell price")
	_assert(String(_dict_field(poke_ball, "pocket").get("symbol", "")) == "POCKET_POKE_BALLS", "expected Poke Ball pocket")
	_assert(String(_dict_field(poke_ball, "battle_usage").get("symbol", "")) == "EFFECT_ITEM_THROW_BALL", "expected Poke Ball battle usage")
	_assert(String(_dict_field(poke_ball, "secondary_id").get("symbol", "")) == "BALL_POKE", "expected Poke Ball secondary id")
	_assert(int(strange_ball.get("id", -1)) == 828, "unexpected Strange Ball id")
	_assert(String(_dict_field(strange_ball, "secondary_id").get("symbol", "")) == "BALL_STRANGE", "expected Strange Ball secondary id")

	var potion := registry.get_item_record("potion")
	var item_effects = _dict_field(items_data, "item_effects")
	var potion_effect = _dict_field(item_effects, "gItemEffect_Potion")
	_assert(String(potion.get("symbol", "")) == "ITEM_POTION", "expected Potion lookup")
	_assert(int(potion.get("id", -1)) == 28, "unexpected Potion id")
	_assert(String(_dict_field(potion, "battle_usage").get("symbol", "")) == "EFFECT_ITEM_RESTORE_HP", "expected Potion battle usage")
	_assert(String(_dict_field(potion, "effect").get("symbol", "")) == "gItemEffect_Potion", "expected Potion effect symbol")
	_assert(int(_dict_field(potion, "effect").get("length", -1)) == 7, "expected Potion effect length")
	_assert(int(_array_field(potion_effect, "values")[4]) == 4, "expected Potion ITEM4_HEAL_HP effect")
	_assert(int(_array_field(potion_effect, "values")[6]) == 20, "expected Potion HP amount")

	var rare_candy := registry.get_item_record("ITEM_RARE_CANDY")
	var rare_candy_effect = _dict_field(item_effects, "gItemEffect_RareCandy")
	_assert(int(rare_candy.get("id", -1)) == 102, "unexpected Rare Candy id")
	_assert(String(_dict_field(rare_candy, "sort_type").get("symbol", "")) == "ITEM_TYPE_LEVEL_UP_ITEM", "expected Rare Candy sort type")
	_assert(int(_array_field(rare_candy_effect, "values")[7]) == 5, "expected Rare Candy friendship macro low value")
	_assert(int(_array_field(rare_candy_effect, "values")[8]) == 3, "expected Rare Candy friendship macro mid value")
	_assert(int(_array_field(rare_candy_effect, "values")[9]) == 2, "expected Rare Candy friendship macro high value")
	_assert(int(_array_field(rare_candy_effect, "byte_values")[6]) == 253, "expected Rare Candy u8 level-up HP marker")

	var cheri := registry.get_item_record("ITEM_CHERI_BERRY")
	var paralyze_effect = _dict_field(item_effects, "gItemEffect_ParalyzeHeal")
	_assert(int(cheri.get("id", -1)) == 514, "unexpected Cheri Berry id")
	_assert(String(_dict_field(cheri, "pocket").get("symbol", "")) == "POCKET_BERRIES", "expected Cheri Berry pocket")
	_assert(String(_dict_field(cheri, "hold_effect").get("symbol", "")) == "HOLD_EFFECT_CURE_PAR", "expected Cheri Berry hold effect")
	_assert(String(_dict_field(cheri, "battle_usage").get("symbol", "")) == "EFFECT_ITEM_CURE_STATUS", "expected Cheri Berry battle usage")
	_assert(int(_array_field(paralyze_effect, "values")[3]) == 2, "expected paralyze heal effect byte")

	var leftovers := registry.get_item_record("leftovers")
	_assert(int(leftovers.get("id", -1)) == 472, "unexpected Leftovers id")
	_assert(String(_dict_field(leftovers, "hold_effect").get("symbol", "")) == "HOLD_EFFECT_LEFTOVERS", "expected Leftovers hold effect")
	_assert(int(leftovers.get("hold_effect_param", -1)) == 10, "unexpected Leftovers hold effect param")

	var growth_mulch := registry.get_item_record("ITEM_GROWTH_MULCH")
	var orange_mail := registry.get_item_record("ITEM_ORANGE_MAIL")
	var tm_thunder := registry.get_item_record("tm_thunder")
	var hm_cut := registry.get_item_record("HM_CUT")
	_assert(int(_dict_field(growth_mulch, "secondary_id").get("value", -1)) == 1, "expected Growth Mulch secondary id")
	_assert(String(_dict_field(growth_mulch, "secondary_id").get("kind", "")) == "mulch_index", "expected Growth Mulch secondary kind")
	_assert(int(_dict_field(orange_mail, "secondary_id").get("value", -1)) == 0, "expected Orange Mail secondary id")
	_assert(String(_dict_field(orange_mail, "secondary_id").get("kind", "")) == "mail_index", "expected Orange Mail secondary kind")
	_assert(int(tm_thunder.get("id", -1)) == 606, "unexpected TM Thunder id")
	_assert(String(_dict_field(tm_thunder, "pocket").get("symbol", "")) == "POCKET_TM_HM", "expected TM Thunder pocket")
	_assert(int(hm_cut.get("id", -1)) == 682, "unexpected HM Cut id")
	_assert(int(hm_cut.get("importance", -1)) == 1, "expected HM Cut importance")

	if _failed:
		return

	print(JSON.stringify({
		"data_registry_items_smoke": "ok",
		"item_count": int(stats.get("item_count", 0)),
		"potion_effect_amount": int(_array_field(potion_effect, "values")[6]),
		"tm_thunder_id": int(tm_thunder.get("id", -1)),
	}))
	registry.free()
	quit(0)


func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	push_error(message)
	_failed = true
	quit(1)


func _dict_field(record, field_name: String) -> Dictionary:
	if typeof(record) != TYPE_DICTIONARY:
		return {}
	var value = record.get(field_name, {})
	return value if typeof(value) == TYPE_DICTIONARY else {}


func _text_field(record: Dictionary, field_name: String) -> Dictionary:
	var value = record.get(field_name, {})
	return value if typeof(value) == TYPE_DICTIONARY else {}


func _array_field(record: Dictionary, field_name: String) -> Array:
	var value = record.get(field_name, [])
	return value if typeof(value) == TYPE_ARRAY else []
