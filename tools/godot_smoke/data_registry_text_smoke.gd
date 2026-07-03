extends SceneTree

const DATA_REGISTRY_SCRIPT := preload("res://scripts/autoload/data_registry.gd")

var _failed := false


func _init() -> void:
	var registry = DATA_REGISTRY_SCRIPT.new()
	registry._ready()

	var text_data := registry.get_text_data()
	var stats = text_data.get("stats", {})
	var source = text_data.get("source", {})
	var source_preprocessor = source.get("preprocessor", {})
	var preprocessor_symbols = source_preprocessor.get("symbols", {})
	_assert(typeof(text_data) == TYPE_DICTIONARY and not text_data.is_empty(), "expected global text data")
	_assert(typeof(stats) == TYPE_DICTIONARY, "expected text stats")
	_assert(int(stats.get("source_file_count", 0)) == 37, "unexpected data/text source file count")
	_assert(int(stats.get("label_count", 0)) == 3454, "unexpected global text label count")
	_assert(int(stats.get("text_count", 0)) == 3454, "unexpected global text record count")
	_assert(int(stats.get("standard_text_count", 0)) == 3393, "unexpected standard text count")
	_assert(int(stats.get("braille_text_count", 0)) == 61, "unexpected braille text count")
	_assert(int(stats.get("charmap_warning_count", -1)) == 0, "expected no charmap warnings")
	_assert(int(stats.get("braille_warning_count", -1)) == 0, "expected no braille warnings")
	_assert(int(stats.get("preprocessor_decision_count", 0)) == 6, "expected IS_FRLG text decisions")
	_assert(int(stats.get("preprocessor_warning_count", -1)) == 0, "expected no preprocessor warnings")
	_assert(int(stats.get("unsupported_directive_count", -1)) == 0, "expected no unsupported text directives")
	_assert(typeof(preprocessor_symbols) == TYPE_DICTIONARY, "expected text preprocessor symbols")
	_assert(not bool(preprocessor_symbols.get("IS_FRLG", true)), "expected Emerald text branch")

	var confirm_save := registry.get_text_record("gText_ConfirmSave")
	var confirm_encoding = confirm_save.get("encoding", {})
	_assert(String(confirm_save.get("kind", "")) == "text", "expected confirm-save standard text")
	_assert(String(confirm_save.get("source", "")) == "data/text/save.inc", "unexpected confirm-save source")
	_assert(int(confirm_save.get("part_count", 0)) == 2, "unexpected confirm-save part count")
	_assert(String(confirm_encoding.get("status", "")) == "ok", "expected confirm-save encoding")
	_assert(int(confirm_encoding.get("byte_count", 0)) == 29, "unexpected confirm-save byte count")
	_assert(bool(confirm_encoding.get("terminator_present", false)), "expected confirm-save terminator")
	_assert(String(confirm_save.get("display_text", "")).contains("\n"), "expected confirm-save display newline")
	_assert(
		registry.get_text_display_text("gText_ConfirmSave") == String(confirm_save.get("display_text", "")),
		"expected display text helper to match record"
	)

	var pc_transfer := registry.get_text_record("gText_PkmnTransferredLanettesPC")
	var pc_encoding = pc_transfer.get("encoding", {})
	_assert(String(pc_transfer.get("source", "")) == "data/text/pc_transfer.inc", "unexpected PC transfer source")
	_assert(int(pc_transfer.get("part_count", 0)) == 3, "expected Emerald PC transfer branch")
	_assert(String(pc_encoding.get("status", "")) == "ok", "expected PC transfer encoding")
	_assert(int(pc_encoding.get("byte_count", 0)) == 47, "unexpected PC transfer byte count")
	_assert(bool(pc_encoding.get("terminator_present", false)), "expected PC transfer terminator")

	var braille := registry.get_text_record("Underwater_SealedChamber_Braille_GoUpHere")
	var braille_format = braille.get("braille_format", {})
	var braille_encoding = braille.get("encoding", {})
	var braille_source_bytes = braille.get("source_bytes", {})
	var format_header = braille_source_bytes.get("format_header", [])
	var combined_bytes = braille_source_bytes.get("combined", [])
	var braille_bytes = braille_encoding.get("bytes", [])
	_assert(String(braille.get("kind", "")) == "braille", "expected braille text kind")
	_assert(String(braille.get("source", "")) == "data/text/braille.inc", "unexpected braille source")
	_assert(int(braille.get("part_count", 0)) == 2, "unexpected braille part count")
	_assert(int(braille.get("source_pointer_skip_bytes", 0)) == 6, "expected source brailleformat skip")
	_assert(String(braille_format.get("status", "")) == "ok", "expected brailleformat status")
	_assert(_array_ints_equal(format_header, [4, 6, 26, 13, 7, 9]), "unexpected brailleformat values")
	_assert(String(braille_encoding.get("status", "")) == "ok", "expected braille encoding")
	_assert(int(braille_encoding.get("byte_count", 0)) == 19, "unexpected braille byte count")
	_assert(bool(braille_encoding.get("terminator_present", false)), "expected braille terminator")
	_assert(braille_bytes.size() == 19 and int(braille_bytes[0]) == 0x39, "expected first braille byte")
	_assert(int(braille_bytes[braille_bytes.size() - 1]) == 0xFF, "expected final braille terminator")
	_assert(combined_bytes.size() == 25 and int(combined_bytes[6]) == 0x39, "expected combined braille source bytes")
	_assert(String(braille.get("display_text", "")).contains("\n"), "expected braille display newline")

	var braille_eos := registry.get_text_record("SealedChamber_InnerRoom_Braille_WeFearedIt")
	_assert(
		String(braille_eos.get("source_display_text", "")).length() > String(braille_eos.get("display_text", "")).length(),
		"expected braille display text to stop at EOS"
	)
	if _failed:
		return

	print(JSON.stringify({
		"data_registry_text_smoke": "ok",
		"text_count": int(stats.get("text_count", 0)),
		"standard_text_count": int(stats.get("standard_text_count", 0)),
		"braille_text_count": int(stats.get("braille_text_count", 0)),
		"pc_transfer_byte_count": int(pc_encoding.get("byte_count", 0)),
		"braille_byte_count": int(braille_encoding.get("byte_count", 0)),
	}))
	registry.free()
	quit(0)


func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	push_error(message)
	_failed = true
	quit(1)


func _array_ints_equal(left, right: Array) -> bool:
	if typeof(left) != TYPE_ARRAY:
		return false
	if left.size() != right.size():
		return false
	for index in range(right.size()):
		if int(left[index]) != int(right[index]):
			return false
	return true
