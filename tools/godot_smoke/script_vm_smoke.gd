extends SceneTree

const SCRIPT_VM_SCRIPT := preload("res://scripts/autoload/script_vm.gd")
const DATA_REGISTRY_SCRIPT := preload("res://scripts/autoload/data_registry.gd")
const GAME_STATE_SCRIPT := preload("res://scripts/autoload/game_state.gd")
const SCRIPT_PATH := "res://data/generated/scripts/littleroot_town.json"


func _init() -> void:
	var script_data := _load_json_object(SCRIPT_PATH)
	var registry = DATA_REGISTRY_SCRIPT.new()
	registry._ready()
	var vm = SCRIPT_VM_SCRIPT.new()
	vm.configure_from_script_data(script_data)
	vm.configure_data_registry(registry)
	var game_state = GAME_STATE_SCRIPT.new()
	vm.configure_game_state(game_state)

	var twin_result := vm.run_script("LittlerootTown_EventScript_Twin")
	var town_sign_result := vm.run_script("LittlerootTown_EventScript_TownSign")
	var need_pokemon_result := vm.run_script("LittlerootTown_EventScript_NeedPokemonTriggerLeft")
	game_state.set_var("VAR_LITTLEROOT_TOWN_STATE", 1)
	var set_twin_pos_result := vm.run_script("LittlerootTown_EventScript_SetTwinPos")
	var set_rival_birch_pos_result := vm.run_script("LittlerootTown_EventScript_SetRivalBirchPosForDexUpgradeMale")
	game_state.set_player_gender("MALE")
	var dex_upgrade_male_result := vm.run_script("LittlerootTown_EventScript_SetRivalBirchPosForDexUpgrade")
	var brendans_house_sign_male_result := vm.run_script("LittlerootTown_EventScript_BrendansHouseSign")
	game_state.set_player_gender("FEMALE")
	var dex_upgrade_female_result := vm.run_script("LittlerootTown_EventScript_SetRivalBirchPosForDexUpgrade")
	var brendans_house_sign_female_result := vm.run_script("LittlerootTown_EventScript_BrendansHouseSign")
	var running_shoes_result := vm.run_script("LittlerootTown_EventScript_SetReceivedRunningShoes")
	game_state.set_var("VAR_0x8009", 5)
	game_state.set_var("VAR_0x800A", 8)
	var mom_return_home_result := vm.run_script("LittlerootTown_EventScript_MomReturnHomeMale2")
	var step_off_truck_result := vm.run_script("LittlerootTown_EventScript_StepOffTruckMale")
	var give_running_shoes_result := vm.run_script("LittlerootTown_EventScript_GiveRunningShoes")
	var synthetic_script_data := script_data.duplicate(true)
	var synthetic_scripts: Dictionary = synthetic_script_data.get("scripts", {})
	var synthetic_texts: Dictionary = synthetic_script_data.get("texts", {})
	synthetic_texts["Smoke_Text_PlayerBigGuyGirl"] = {
		"label": "Smoke_Text_PlayerBigGuyGirl",
		"display_text": "称呼:{STR_VAR_1}",
		"kind": "text",
		"source": "smoke",
	}
	synthetic_texts["Smoke_Text_RivalSonDaughter"] = {
		"label": "Smoke_Text_RivalSonDaughter",
		"display_text": "关系:{STR_VAR_1}",
		"kind": "text",
		"source": "smoke",
	}
	synthetic_texts["Smoke_Text_PlayerNameKun"] = {
		"label": "Smoke_Text_PlayerNameKun",
		"display_text": "你好{PLAYER}{KUN}:{STR_VAR_1}",
		"kind": "text",
		"source": "smoke",
	}
	synthetic_texts["Smoke_Text_RivalPlaceholder"] = {
		"label": "Smoke_Text_RivalPlaceholder",
		"display_text": "对手:{RIVAL}",
		"kind": "text",
		"source": "smoke",
	}
	synthetic_texts["Smoke_Text_TextControls"] = {
		"label": "Smoke_Text_TextControls",
		"display_text": "{COLOR BLUE}{SHADOW LIGHT_BLUE}{FONT_MALE}Alpha{PAUSE 15}Beta{PAUSE_UNTIL_PRESS}{UNRESOLVED_TOKEN}",
		"kind": "text",
		"source": "smoke",
	}
	synthetic_scripts["Smoke_EventScript_DelayOnly"] = {
		"instructions": [
			{"op": "delay", "args": ["30"], "line": 1, "raw": "delay 30"},
			{"op": "end", "args": [], "line": 2, "raw": "end"},
		],
	}
	synthetic_scripts["Smoke_EventScript_WarpOnly"] = {
		"instructions": [
			{"op": "warp", "args": ["MAP_LITTLEROOT_TOWN_PROFESSOR_BIRCHS_LAB", "6", "5"], "line": 1, "raw": "warp MAP_LITTLEROOT_TOWN_PROFESSOR_BIRCHS_LAB, 6, 5"},
			{"op": "waitstate", "args": [], "line": 2, "raw": "waitstate"},
			{"op": "end", "args": [], "line": 3, "raw": "end"},
		],
	}
	synthetic_scripts["Smoke_EventScript_GlobalText"] = {
		"instructions": [
			{"op": "msgbox", "args": ["gText_ConfirmSave", "MSGBOX_DEFAULT"], "line": 1, "raw": "msgbox gText_ConfirmSave, MSGBOX_DEFAULT"},
			{"op": "end", "args": [], "line": 2, "raw": "end"},
		],
	}
	synthetic_scripts["Smoke_EventScript_BattlePcCreatorName"] = {
		"instructions": [
			{"op": "msgbox", "args": ["gText_PkmnSentToPCAfterCatch", "MSGBOX_DEFAULT"], "line": 1, "raw": "msgbox gText_PkmnSentToPCAfterCatch, MSGBOX_DEFAULT"},
			{"op": "end", "args": [], "line": 2, "raw": "end"},
		],
	}
	synthetic_scripts["Smoke_EventScript_YesNoPending"] = {
		"instructions": [
			{"op": "msgbox", "args": ["gText_ConfirmSave", "MSGBOX_YESNO"], "line": 1, "raw": "msgbox gText_ConfirmSave, MSGBOX_YESNO"},
			{"op": "end", "args": [], "line": 2, "raw": "end"},
		],
	}
	synthetic_scripts["Smoke_EventScript_YesNoBranch"] = {
		"instructions": [
			{"op": "msgbox", "args": ["gText_ConfirmSave", "MSGBOX_YESNO"], "line": 1, "raw": "msgbox gText_ConfirmSave, MSGBOX_YESNO"},
			{"op": "goto_if_eq", "args": ["VAR_RESULT", "YES", "Smoke_EventScript_YesNoYes"], "line": 2, "raw": "goto_if_eq VAR_RESULT, YES, Smoke_EventScript_YesNoYes"},
			{"op": "msgbox", "args": ["gText_AlreadySavedFile", "MSGBOX_DEFAULT"], "line": 3, "raw": "msgbox gText_AlreadySavedFile, MSGBOX_DEFAULT"},
			{"op": "end", "args": [], "line": 4, "raw": "end"},
		],
	}
	synthetic_scripts["Smoke_EventScript_YesNoYes"] = {
		"instructions": [
			{"op": "msgbox", "args": ["gText_SavingDontTurnOffPower", "MSGBOX_DEFAULT"], "line": 5, "raw": "msgbox gText_SavingDontTurnOffPower, MSGBOX_DEFAULT"},
			{"op": "end", "args": [], "line": 6, "raw": "end"},
		],
	}
	synthetic_scripts["Smoke_EventScript_PlayerBigGuyGirl"] = {
		"instructions": [
			{"op": "special", "args": ["GetPlayerBigGuyGirlString"], "line": 1, "raw": "special GetPlayerBigGuyGirlString"},
			{"op": "msgbox", "args": ["Smoke_Text_PlayerBigGuyGirl", "MSGBOX_DEFAULT"], "line": 2, "raw": "msgbox Smoke_Text_PlayerBigGuyGirl, MSGBOX_DEFAULT"},
			{"op": "end", "args": [], "line": 3, "raw": "end"},
		],
	}
	synthetic_scripts["Smoke_EventScript_RivalSonDaughter"] = {
		"instructions": [
			{"op": "special", "args": ["GetRivalSonDaughterString"], "line": 1, "raw": "special GetRivalSonDaughterString"},
			{"op": "msgbox", "args": ["Smoke_Text_RivalSonDaughter", "MSGBOX_DEFAULT"], "line": 2, "raw": "msgbox Smoke_Text_RivalSonDaughter, MSGBOX_DEFAULT"},
			{"op": "end", "args": [], "line": 3, "raw": "end"},
		],
	}
	synthetic_scripts["Smoke_EventScript_PlayerNameKun"] = {
		"instructions": [
			{"op": "special", "args": ["GetPlayerBigGuyGirlString"], "line": 1, "raw": "special GetPlayerBigGuyGirlString"},
			{"op": "msgbox", "args": ["Smoke_Text_PlayerNameKun", "MSGBOX_DEFAULT"], "line": 2, "raw": "msgbox Smoke_Text_PlayerNameKun, MSGBOX_DEFAULT"},
			{"op": "end", "args": [], "line": 3, "raw": "end"},
		],
	}
	synthetic_scripts["Smoke_EventScript_RivalPlaceholder"] = {
		"instructions": [
			{"op": "msgbox", "args": ["Smoke_Text_RivalPlaceholder", "MSGBOX_DEFAULT"], "line": 1, "raw": "msgbox Smoke_Text_RivalPlaceholder, MSGBOX_DEFAULT"},
			{"op": "end", "args": [], "line": 2, "raw": "end"},
		],
	}
	synthetic_scripts["Smoke_EventScript_TextControls"] = {
		"instructions": [
			{"op": "message", "args": ["Smoke_Text_TextControls"], "line": 1, "raw": "message Smoke_Text_TextControls"},
			{"op": "end", "args": [], "line": 2, "raw": "end"},
		],
	}
	synthetic_script_data["scripts"] = synthetic_scripts
	synthetic_script_data["texts"] = synthetic_texts
	vm.configure_from_script_data(synthetic_script_data)
	var delay_result := vm.run_script("Smoke_EventScript_DelayOnly")
	var warp_result := vm.run_script("Smoke_EventScript_WarpOnly")
	var global_text_result := vm.run_script("Smoke_EventScript_GlobalText")
	var text_controls_result := vm.run_script("Smoke_EventScript_TextControls")
	game_state.clear_flag("FLAG_SYS_PC_LANETTE")
	var battle_pc_someones_result := vm.run_script("Smoke_EventScript_BattlePcCreatorName")
	game_state.set_flag("FLAG_SYS_PC_LANETTE", true)
	var battle_pc_lanettes_result := vm.run_script("Smoke_EventScript_BattlePcCreatorName")
	game_state.clear_flag("FLAG_SYS_PC_LANETTE")
	var yesno_pending_result := vm.run_script("Smoke_EventScript_YesNoPending")
	var yesno_pending_var_result := game_state.get_var("VAR_RESULT", -1)
	var yesno_yes_result := vm.run_script("Smoke_EventScript_YesNoBranch", {"yesno_choice": "YES"})
	var yesno_yes_var_result := game_state.get_var("VAR_RESULT", -1)
	var yesno_no_result := vm.run_script("Smoke_EventScript_YesNoBranch", {"yesno_choice": "NO"})
	var yesno_no_var_result := game_state.get_var("VAR_RESULT", -1)
	game_state.set_player_gender("MALE")
	game_state.set_player_name("小悠")
	var special_player_male_result := vm.run_script("Smoke_EventScript_PlayerBigGuyGirl")
	var special_rival_male_result := vm.run_script("Smoke_EventScript_RivalSonDaughter")
	var player_name_kun_result := vm.run_script("Smoke_EventScript_PlayerNameKun")
	var rival_placeholder_male_result := vm.run_script("Smoke_EventScript_RivalPlaceholder")
	game_state.set_player_gender("FEMALE")
	game_state.set_player_name("小遥")
	var special_player_female_result := vm.run_script("Smoke_EventScript_PlayerBigGuyGirl")
	var special_rival_female_result := vm.run_script("Smoke_EventScript_RivalSonDaughter")
	var rival_placeholder_female_result := vm.run_script("Smoke_EventScript_RivalPlaceholder")
	vm.configure_from_script_data(script_data)
	var missing_result := vm.run_script("Missing_EventScript")

	_assert(twin_result.get("status", "") == "ok", "expected Twin script to execute")
	_assert(twin_result.get("finished", false), "expected Twin script to finish")
	_assert(_first_text_label(twin_result) == "LittlerootTown_Text_IfYouGoInGrassPokemonWillJumpOut", "unexpected Twin text")
	_assert(_has_effect(twin_result, "lock"), "expected Twin lock effect")
	_assert(_has_effect(twin_result, "faceplayer"), "expected Twin faceplayer effect")
	_assert(_has_effect(twin_result, "release"), "expected Twin release effect")
	_assert(_unsupported_count(twin_result) == 0, "expected no unsupported Twin ops")

	_assert(town_sign_result.get("status", "") == "ok", "expected town sign script to execute")
	_assert(town_sign_result.get("finished", false), "expected town sign script to finish")
	_assert(_first_text_label(town_sign_result) == "LittlerootTown_Text_TownSign", "unexpected town sign text")
	_assert(_text_encoding_status(script_data, "LittlerootTown_Text_TownSign") == "ok", "expected town sign charmap encoding")
	_assert(_text_source_byte_count(script_data, "LittlerootTown_Text_TownSign") > 0, "expected town sign source bytes")
	_assert(_text_has_control_token(script_data, "LittlerootTown_Text_TownSign", "\\n"), "expected town sign newline control")
	_assert(_text_has_terminator(script_data, "LittlerootTown_Text_TownSign"), "expected town sign terminator")
	_assert(_first_message_encoding_status(town_sign_result) == "ok", "expected town sign runtime encoding status")
	_assert(_first_message_source_byte_count(town_sign_result) > 0, "expected town sign runtime source byte count")
	_assert(not _first_message_text(town_sign_result).ends_with("$"), "expected town sign display text without terminator")
	_assert(_first_message_text(town_sign_result).find("\n") != -1, "expected town sign display newline")
	_assert(_has_effect(town_sign_result, "lockall"), "expected town sign lockall effect")
	_assert(_has_effect(town_sign_result, "releaseall"), "expected town sign releaseall effect")
	_assert(_unsupported_count(town_sign_result) == 0, "expected no unsupported town sign ops")

	_assert(need_pokemon_result.get("status", "") == "ok", "expected need-pokemon script to execute")
	_assert(need_pokemon_result.get("finished", false), "expected need-pokemon script to finish")
	_assert(_message_count(need_pokemon_result) == 2, "expected two need-pokemon messages")
	_assert(_movement_count(need_pokemon_result) == 4, "expected four need-pokemon movements")
	_assert(
		_movement_label(need_pokemon_result, 0) == "LittlerootTown_Movement_TwinApproachPlayerLeft",
		"unexpected first need-pokemon movement"
	)
	_assert(_movement_target(need_pokemon_result, 0) == "LOCALID_LITTLEROOT_TWIN", "unexpected first movement target")
	_assert(_movement_net_delta(need_pokemon_result, 0) == Vector2i(3, -2), "unexpected first movement delta")
	_assert(_movement_step_count(need_pokemon_result, 0) == 13, "unexpected first movement step count")
	_assert(_movement_final_facing(need_pokemon_result, 0) == "down", "unexpected first movement facing")
	_assert(_has_movement(need_pokemon_result, "LOCALID_PLAYER", "LittlerootTown_Movement_PushPlayerBackFromRoute"), "expected player push movement")
	_assert(_effect_count_for_op(need_pokemon_result, "waitmovement") == 3, "expected three waitmovement effects")
	_assert(bool(need_pokemon_result.get("wait_movement", false)), "expected wait movement metadata")
	_assert(_unsupported_count(need_pokemon_result) == 0, "expected no unsupported need-pokemon ops")

	_assert(set_twin_pos_result.get("status", "") == "ok", "expected set-twin-pos script to execute")
	_assert(_object_effect_count(set_twin_pos_result) == 2, "expected two set-twin-pos object effects")
	_assert(_object_effect_op(set_twin_pos_result, 0) == "setobjectxyperm", "unexpected set-twin-pos first op")
	_assert(_object_effect_target(set_twin_pos_result, 0) == "LOCALID_LITTLEROOT_TWIN", "unexpected set-twin-pos target")
	_assert(_object_effect_position(set_twin_pos_result, 0) == Vector2i(10, 1), "unexpected twin template position")
	_assert(_object_effect_op(set_twin_pos_result, 1) == "setobjectmovementtype", "unexpected set-twin-pos second op")
	_assert(_object_effect_movement_type(set_twin_pos_result, 1) == "MOVEMENT_TYPE_FACE_UP", "unexpected twin movement type")
	_assert(_unsupported_count(set_twin_pos_result) == 0, "expected no unsupported set-twin-pos ops")

	_assert(set_rival_birch_pos_result.get("status", "") == "ok", "expected rival/birch position script to execute")
	_assert(_object_effect_count(set_rival_birch_pos_result) == 2, "expected two rival/birch object effects")
	_assert(_object_effect_position(set_rival_birch_pos_result, 0) == Vector2i(6, 10), "unexpected rival position")
	_assert(_object_effect_position(set_rival_birch_pos_result, 1) == Vector2i(5, 10), "unexpected Birch position")
	_assert(_unsupported_count(set_rival_birch_pos_result) == 0, "expected no unsupported rival/birch ops")

	_assert(dex_upgrade_male_result.get("status", "") == "ok", "expected male dex-upgrade script to execute")
	_assert(_effect_value_for_op(dex_upgrade_male_result, "checkplayergender") == 0, "expected male gender value")
	_assert(_object_effect_count(dex_upgrade_male_result) == 4, "expected male dex-upgrade add/move object effects")
	_assert(_object_effect_position(dex_upgrade_male_result, 2) == Vector2i(6, 10), "unexpected male rival position")
	_assert(_object_effect_position(dex_upgrade_male_result, 3) == Vector2i(5, 10), "unexpected male Birch position")
	_assert(_first_text_label(brendans_house_sign_male_result) == "LittlerootTown_Text_PlayersHouse", "unexpected male Brendan sign text")
	_assert(_unsupported_count(dex_upgrade_male_result) == 0, "expected no unsupported male dex-upgrade ops")
	_assert(_unsupported_count(brendans_house_sign_male_result) == 0, "expected no unsupported male sign ops")

	_assert(dex_upgrade_female_result.get("status", "") == "ok", "expected female dex-upgrade script to execute")
	_assert(_effect_value_for_op(dex_upgrade_female_result, "checkplayergender") == 1, "expected female gender value")
	_assert(_object_effect_count(dex_upgrade_female_result) == 4, "expected female dex-upgrade add/move object effects")
	_assert(_object_effect_position(dex_upgrade_female_result, 2) == Vector2i(13, 10), "unexpected female rival position")
	_assert(_object_effect_position(dex_upgrade_female_result, 3) == Vector2i(14, 10), "unexpected female Birch position")
	_assert(_first_text_label(brendans_house_sign_female_result) == "LittlerootTown_Text_ProfBirchsHouse", "unexpected female Brendan sign text")
	_assert(_unsupported_count(dex_upgrade_female_result) == 0, "expected no unsupported female dex-upgrade ops")
	_assert(_unsupported_count(brendans_house_sign_female_result) == 0, "expected no unsupported female sign ops")

	_assert(running_shoes_result.get("status", "") == "ok", "expected running-shoes script to execute")
	_assert(_object_effect_count(running_shoes_result) == 1, "expected one running-shoes object effect")
	_assert(_object_effect_op(running_shoes_result, 0) == "removeobject", "unexpected running-shoes object op")
	_assert(_object_effect_target(running_shoes_result, 0) == "LOCALID_LITTLEROOT_MOM", "unexpected running-shoes object target")
	_assert(_unsupported_count(running_shoes_result) == 0, "expected no unsupported running-shoes ops")

	_assert(mom_return_home_result.get("status", "") == "ok", "expected mom return-home script to execute")
	_assert(_movement_count(mom_return_home_result) == 2, "expected two mom return-home movements")
	_assert(_object_effect_count(mom_return_home_result) == 1, "expected one mom return-home object effect")
	_assert(_object_effect_op(mom_return_home_result, 0) == "hideobjectat", "unexpected mom return-home object op")
	_assert(_field_effect_count(mom_return_home_result) == 4, "expected four mom return-home field effects")
	_assert(_field_effect_op(mom_return_home_result, 0) == "opendoor", "unexpected first door field effect")
	_assert(_field_effect_position(mom_return_home_result, 0) == Vector2i(5, 8), "unexpected opened door position")
	_assert(_field_effect_op(mom_return_home_result, 1) == "waitdooranim", "unexpected first door wait effect")
	_assert(_field_effect_op(mom_return_home_result, 2) == "closedoor", "unexpected second door field effect")
	_assert(_field_effect_position(mom_return_home_result, 2) == Vector2i(5, 8), "unexpected closed door position")
	_assert(_field_effect_op(mom_return_home_result, 3) == "waitdooranim", "unexpected second door wait effect")
	_assert(_unsupported_count(mom_return_home_result) == 0, "expected no unsupported mom return-home ops")

	_assert(step_off_truck_result.get("status", "") == "ok", "expected step-off-truck script to execute")
	_assert(_message_count(step_off_truck_result) == 1, "expected one step-off-truck message")
	_assert(_movement_count(step_off_truck_result) == 7, "expected seven step-off-truck movements")
	_assert(_object_effect_count(step_off_truck_result) == 1, "expected one step-off-truck object effect")
	_assert(_audio_effect_count(step_off_truck_result) == 1, "expected one step-off-truck audio effect")
	_assert(_audio_effect_op(step_off_truck_result, 0) == "playse", "unexpected step-off-truck audio op")
	_assert(_audio_effect_sound(step_off_truck_result, 0) == "SE_LEDGE", "unexpected step-off-truck sound")
	_assert(_player_effect_count(step_off_truck_result) == 1, "expected one step-off-truck player effect")
	_assert(_player_effect_op(step_off_truck_result, 0) == "hideplayer", "unexpected step-off-truck player op")
	_assert(not _player_effect_visible(step_off_truck_result, 0), "expected step-off-truck hideplayer to hide player")
	_assert(_transition_effect_count(step_off_truck_result) == 1, "expected one step-off-truck transition effect")
	_assert(_transition_effect_op(step_off_truck_result, 0) == "warpsilent", "unexpected step-off-truck transition op")
	_assert(
		_transition_effect_map(step_off_truck_result, 0) == "MAP_LITTLEROOT_TOWN_BRENDANS_HOUSE_1F",
		"unexpected step-off-truck destination map"
	)
	_assert(_transition_effect_position(step_off_truck_result, 0) == Vector2i(8, 8), "unexpected step-off-truck warp position")
	_assert(_transition_effect_style(step_off_truck_result, 0) == "silent", "unexpected step-off-truck warp style")
	_assert(_field_effect_count(step_off_truck_result) == 11, "expected eleven step-off-truck field effects")
	_assert(_field_effect_op(step_off_truck_result, 10) == "waitstate", "unexpected final step-off-truck field effect")
	_assert(bool(step_off_truck_result.get("wait_state", false)), "expected step-off-truck waitstate metadata")
	_assert(_unsupported_count(step_off_truck_result) == 0, "expected no unsupported step-off-truck ops")
	_assert(game_state.get_var("VAR_LITTLEROOT_INTRO_STATE", 0) == 3, "expected step-off-truck intro state update")

	_assert(give_running_shoes_result.get("status", "") == "ok", "expected give-running-shoes script to execute")
	_assert(_message_count(give_running_shoes_result) == 4, "expected four give-running-shoes messages")
	_assert(_audio_effect_count(give_running_shoes_result) == 2, "expected two give-running-shoes audio effects")
	_assert(_audio_effect_op(give_running_shoes_result, 0) == "playfanfare", "unexpected give-running-shoes first audio op")
	_assert(_audio_effect_fanfare(give_running_shoes_result, 0) == "MUS_OBTAIN_ITEM", "unexpected give-running-shoes fanfare")
	_assert(_audio_effect_op(give_running_shoes_result, 1) == "waitfanfare", "unexpected give-running-shoes second audio op")
	_assert(bool(give_running_shoes_result.get("wait_audio", false)), "expected give-running-shoes audio wait metadata")
	_assert(_field_effect_count(give_running_shoes_result) == 1, "expected one give-running-shoes field effect")
	_assert(_field_effect_op(give_running_shoes_result, 0) == "delay", "unexpected give-running-shoes field effect")
	_assert(game_state.is_flag_set("FLAG_RECEIVED_RUNNING_SHOES"), "expected running shoes flag to be set")
	_assert(_unsupported_count(give_running_shoes_result) == 0, "expected no unsupported give-running-shoes ops")

	_assert(delay_result.get("status", "") == "ok", "expected delay-only script to execute")
	_assert(_field_effect_count(delay_result) == 1, "expected one delay field effect")
	_assert(_field_effect_op(delay_result, 0) == "delay", "unexpected delay field effect op")
	_assert(_field_effect_frames(delay_result, 0) == 30, "unexpected delay frame count")
	_assert(_unsupported_count(delay_result) == 0, "expected no unsupported delay ops")

	_assert(warp_result.get("status", "") == "ok", "expected warp-only script to execute")
	_assert(_transition_effect_count(warp_result) == 1, "expected one warp-only transition effect")
	_assert(_transition_effect_op(warp_result, 0) == "warp", "unexpected warp-only transition op")
	_assert(_transition_effect_map(warp_result, 0) == "MAP_LITTLEROOT_TOWN_PROFESSOR_BIRCHS_LAB", "unexpected warp-only destination map")
	_assert(_transition_effect_position(warp_result, 0) == Vector2i(6, 5), "unexpected warp-only position")
	_assert(_transition_effect_style(warp_result, 0) == "normal", "unexpected warp-only style")
	_assert(_transition_effect_sound(warp_result, 0) == "SE_EXIT", "unexpected warp-only sound effect")
	_assert(bool(warp_result.get("wait_state", false)), "expected warp-only waitstate metadata")
	_assert(_field_effect_count(warp_result) == 1, "expected one warp-only field effect")
	_assert(_field_effect_op(warp_result, 0) == "waitstate", "unexpected warp-only field effect")
	_assert(_unsupported_count(warp_result) == 0, "expected no unsupported warp-only ops")

	_assert(global_text_result.get("status", "") == "ok", "expected global-text script to execute")
	_assert(global_text_result.get("finished", false), "expected global-text script to finish")
	_assert(_message_count(global_text_result) == 1, "expected one global-text message")
	_assert(_first_text_label(global_text_result) == "gText_ConfirmSave", "unexpected global text label")
	_assert(_first_message_encoding_status(global_text_result) == "ok", "expected global text encoding status")
	_assert(_first_message_source_byte_count(global_text_result) == 29, "unexpected global text source byte count")
	_assert(_first_message_has_terminator(global_text_result), "expected global text terminator metadata")
	_assert(_first_message_text_source(global_text_result) == "data/text/save.inc", "unexpected global text source")
	_assert(_first_message_text_kind(global_text_result) == "text", "unexpected global text kind")
	_assert(_first_message_text(global_text_result).find("\n") != -1, "expected global text display newline")
	_assert(_unsupported_count(global_text_result) == 0, "expected no unsupported global-text ops")

	_assert(text_controls_result.get("status", "") == "ok", "expected text-control script to execute")
	_assert(_message_count(text_controls_result) == 1, "expected one text-control message")
	_assert(_first_message_text(text_controls_result) == "AlphaBeta{UNRESOLVED_TOKEN}", "expected text controls to be removed from display text")
	_assert(_first_message_unexpanded_text(text_controls_result) == "{COLOR BLUE}{SHADOW LIGHT_BLUE}{FONT_MALE}Alpha{PAUSE 15}Beta{PAUSE_UNTIL_PRESS}{UNRESOLVED_TOKEN}", "expected unexpanded text controls to be preserved")
	_assert(_first_message_expanded_text(text_controls_result) == _first_message_unexpanded_text(text_controls_result), "expected expanded text to preserve control tokens before cleanup")
	_assert(_first_message_text_control_count(text_controls_result) == 5, "expected five parsed text controls")
	_assert(_first_message_text_control_code_id_for_token(text_controls_result, "{COLOR BLUE}") == 1, "unexpected COLOR code id")
	_assert(_first_message_text_control_value_id_for_token(text_controls_result, "{COLOR BLUE}") == 8, "unexpected COLOR value id")
	_assert(_first_message_text_control_code_id_for_token(text_controls_result, "{SHADOW LIGHT_BLUE}") == 3, "unexpected SHADOW code id")
	_assert(_first_message_text_control_value_id_for_token(text_controls_result, "{SHADOW LIGHT_BLUE}") == 9, "unexpected SHADOW value id")
	_assert(_first_message_text_control_code_id_for_token(text_controls_result, "{FONT_MALE}") == 6, "unexpected FONT code id")
	_assert(_first_message_text_control_value_id_for_token(text_controls_result, "{FONT_MALE}") == 1, "unexpected FONT value id")
	_assert(_first_message_text_control_code_id_for_token(text_controls_result, "{PAUSE 15}") == 8, "unexpected PAUSE code id")
	_assert(_first_message_text_control_frames_for_token(text_controls_result, "{PAUSE 15}") == 15, "unexpected PAUSE frame count")
	_assert(_first_message_text_control_code_id_for_token(text_controls_result, "{PAUSE_UNTIL_PRESS}") == 9, "unexpected PAUSE_UNTIL_PRESS code id")
	_assert(_first_message_text_control_source_length_for_token(text_controls_result, "{PAUSE_UNTIL_PRESS}") == 1, "unexpected PAUSE_UNTIL_PRESS source length")
	_assert(bool(text_controls_result.get("wait_buttonpress", false)), "expected PAUSE_UNTIL_PRESS to require button press")
	_assert(_unsupported_count(text_controls_result) == 0, "expected no unsupported text-control ops")

	_assert(battle_pc_someones_result.get("status", "") == "ok", "expected battle PC creator text to execute without Lanette flag")
	_assert(battle_pc_lanettes_result.get("status", "") == "ok", "expected battle PC creator text to execute with Lanette flag")
	_assert(_first_message_text(battle_pc_someones_result).find("{B_PC_CREATOR_NAME}") == -1, "expected PC creator token to expand without Lanette flag")
	_assert(_first_message_text(battle_pc_lanettes_result).find("{B_PC_CREATOR_NAME}") == -1, "expected PC creator token to expand with Lanette flag")
	_assert(_first_message_placeholder_substitution_count(battle_pc_someones_result) == 3, "expected STR_VAR_1/2 and PC creator substitutions")
	_assert(_first_message_placeholder_id_for_token(battle_pc_someones_result, "{B_PC_CREATOR_NAME}") == 0x27, "unexpected PC creator placeholder id")
	_assert(_first_message_placeholder_source_for_token(battle_pc_someones_result, "{B_PC_CREATOR_NAME}") == "BattleStringExpandPlaceholders", "unexpected PC creator placeholder source")
	_assert(_first_message_placeholder_value_key_for_token(battle_pc_someones_result, "{B_PC_CREATOR_NAME}") == "SOMEONES", "expected default PC creator key")
	_assert(_first_message_placeholder_value_key_for_token(battle_pc_lanettes_result, "{B_PC_CREATOR_NAME}") == "LANETTES", "expected Lanette PC creator key")
	_assert(_first_message_placeholder_value_for_token(battle_pc_someones_result, "{B_PC_CREATOR_NAME}") != _first_message_placeholder_value_for_token(battle_pc_lanettes_result, "{B_PC_CREATOR_NAME}"), "expected PC creator values to differ by flag")
	_assert(_unsupported_count(battle_pc_someones_result) == 0, "expected no unsupported default PC creator ops")
	_assert(_unsupported_count(battle_pc_lanettes_result) == 0, "expected no unsupported Lanette PC creator ops")

	_assert(yesno_pending_result.get("status", "") == "waiting_for_ui", "expected pending yes/no UI status")
	_assert(yesno_pending_result.get("finished", false), "expected pending yes/no script to stop")
	_assert(_message_count(yesno_pending_result) == 1, "expected one pending yes/no message")
	_assert(_first_text_label(yesno_pending_result) == "gText_ConfirmSave", "unexpected pending yes/no text")
	_assert(_ui_effect_count(yesno_pending_result) == 1, "expected one pending yes/no UI effect")
	_assert(_ui_effect_op(yesno_pending_result, 0) == "yesnobox", "unexpected pending yes/no UI op")
	_assert(_ui_effect_script_position(yesno_pending_result, 0) == Vector2i(20, 8), "unexpected yes/no script position")
	_assert(_ui_effect_menu_position(yesno_pending_result, 0) == Vector2i(21, 9), "unexpected source yes/no menu position")
	_assert(_ui_effect_menu_size(yesno_pending_result, 0) == Vector2i(5, 4), "unexpected source yes/no menu size")
	_assert(_ui_effect_default_choice(yesno_pending_result, 0) == "YES", "unexpected yes/no default choice")
	_assert(_ui_effect_b_choice(yesno_pending_result, 0) == "NO", "unexpected yes/no B choice")
	_assert(_ui_effect_input_delay_frames(yesno_pending_result, 0) == 5, "unexpected yes/no input delay")
	_assert(_ui_effect_selected_choice(yesno_pending_result, 0) == "PENDING", "unexpected pending yes/no choice")
	_assert(_ui_effect_selected_value(yesno_pending_result, 0) == 255, "unexpected pending yes/no value")
	_assert(bool(yesno_pending_result.get("wait_ui", false)), "expected pending yes/no wait_ui metadata")
	_assert(not bool(yesno_pending_result.get("wait_buttonpress", false)), "expected yes/no std script without buttonpress wait")
	_assert(yesno_pending_var_result == 255, "expected pending yes/no VAR_RESULT")
	_assert(_unsupported_count(yesno_pending_result) == 0, "expected no unsupported pending yes/no ops")

	_assert(yesno_yes_result.get("status", "") == "ok", "expected injected YES script to execute")
	_assert(yesno_yes_result.get("finished", false), "expected injected YES script to finish")
	_assert(_message_count(yesno_yes_result) == 2, "expected two injected YES messages")
	_assert(_message_text_label(yesno_yes_result, 0) == "gText_ConfirmSave", "unexpected injected YES first text")
	_assert(_message_text_label(yesno_yes_result, 1) == "gText_SavingDontTurnOffPower", "unexpected injected YES branch text")
	_assert(_ui_effect_count(yesno_yes_result) == 1, "expected one injected YES UI effect")
	_assert(_ui_effect_selected_choice(yesno_yes_result, 0) == "YES", "unexpected injected YES choice")
	_assert(_ui_effect_selected_value(yesno_yes_result, 0) == 1, "unexpected injected YES value")
	_assert(bool(yesno_yes_result.get("wait_ui", false)), "expected injected YES wait_ui metadata")
	_assert(yesno_yes_var_result == 1, "expected injected YES VAR_RESULT")
	_assert(_unsupported_count(yesno_yes_result) == 0, "expected no unsupported injected YES ops")

	_assert(yesno_no_result.get("status", "") == "ok", "expected injected NO script to execute")
	_assert(yesno_no_result.get("finished", false), "expected injected NO script to finish")
	_assert(_message_count(yesno_no_result) == 2, "expected two injected NO messages")
	_assert(_message_text_label(yesno_no_result, 0) == "gText_ConfirmSave", "unexpected injected NO first text")
	_assert(_message_text_label(yesno_no_result, 1) == "gText_AlreadySavedFile", "unexpected injected NO fallback text")
	_assert(_ui_effect_count(yesno_no_result) == 1, "expected one injected NO UI effect")
	_assert(_ui_effect_selected_choice(yesno_no_result, 0) == "NO", "unexpected injected NO choice")
	_assert(_ui_effect_selected_value(yesno_no_result, 0) == 0, "unexpected injected NO value")
	_assert(bool(yesno_no_result.get("wait_ui", false)), "expected injected NO wait_ui metadata")
	_assert(yesno_no_var_result == 0, "expected injected NO VAR_RESULT")
	_assert(_unsupported_count(yesno_no_result) == 0, "expected no unsupported injected NO ops")

	_assert(special_player_male_result.get("status", "") == "ok", "expected player big-guy special to execute for male")
	_assert(_special_effect_count(special_player_male_result) == 1, "expected one player big-guy special effect for male")
	_assert(_special_effect_function(special_player_male_result, 0) == "GetPlayerBigGuyGirlString", "unexpected player big-guy special function")
	_assert(_special_effect_write_value(special_player_male_result, 0, "STR_VAR_1") == "大哥哥", "unexpected male player big-guy string")
	_assert(_string_var_value(special_player_male_result, "STR_VAR_1") == "大哥哥", "expected male player string var")
	_assert(_first_message_text(special_player_male_result) == "称呼:大哥哥", "expected expanded male player big-guy message")
	_assert(_first_message_unexpanded_text(special_player_male_result) == "称呼:{STR_VAR_1}", "expected unexpanded male player big-guy message")
	_assert(_first_message_placeholder_substitution_count(special_player_male_result) == 1, "expected one male player placeholder substitution")
	_assert(_first_message_placeholder_value(special_player_male_result, 0) == "大哥哥", "unexpected male player placeholder value")
	_assert(_unsupported_count(special_player_male_result) == 0, "expected no unsupported male player special ops")

	_assert(special_player_female_result.get("status", "") == "ok", "expected player big-guy special to execute for female")
	_assert(_special_effect_count(special_player_female_result) == 1, "expected one player big-guy special effect for female")
	_assert(_special_effect_write_value(special_player_female_result, 0, "STR_VAR_1") == "大姐姐", "unexpected female player big-guy string")
	_assert(_string_var_value(special_player_female_result, "STR_VAR_1") == "大姐姐", "expected female player string var")
	_assert(_first_message_text(special_player_female_result) == "称呼:大姐姐", "expected expanded female player big-guy message")
	_assert(_unsupported_count(special_player_female_result) == 0, "expected no unsupported female player special ops")

	_assert(special_rival_male_result.get("status", "") == "ok", "expected rival relation special to execute for male")
	_assert(_special_effect_count(special_rival_male_result) == 1, "expected one rival relation special effect for male")
	_assert(_special_effect_function(special_rival_male_result, 0) == "GetRivalSonDaughterString", "unexpected rival relation special function")
	_assert(_special_effect_write_value(special_rival_male_result, 0, "STR_VAR_1") == "女儿", "unexpected male rival relation string")
	_assert(_string_var_value(special_rival_male_result, "STR_VAR_1") == "女儿", "expected male rival relation string var")
	_assert(_first_message_text(special_rival_male_result) == "关系:女儿", "expected expanded male rival relation message")
	_assert(_unsupported_count(special_rival_male_result) == 0, "expected no unsupported male rival special ops")

	_assert(special_rival_female_result.get("status", "") == "ok", "expected rival relation special to execute for female")
	_assert(_special_effect_count(special_rival_female_result) == 1, "expected one rival relation special effect for female")
	_assert(_special_effect_write_value(special_rival_female_result, 0, "STR_VAR_1") == "儿子", "unexpected female rival relation string")
	_assert(_string_var_value(special_rival_female_result, "STR_VAR_1") == "儿子", "expected female rival relation string var")
	_assert(_first_message_text(special_rival_female_result) == "关系:儿子", "expected expanded female rival relation message")
	_assert(_unsupported_count(special_rival_female_result) == 0, "expected no unsupported female rival special ops")

	_assert(player_name_kun_result.get("status", "") == "ok", "expected player-name placeholder script to execute")
	_assert(_first_message_text(player_name_kun_result) == "你好小悠:大哥哥", "expected expanded PLAYER/KUN/string-var message")
	_assert(_first_message_unexpanded_text(player_name_kun_result) == "你好{PLAYER}{KUN}:{STR_VAR_1}", "expected unexpanded PLAYER/KUN message")
	_assert(_first_message_placeholder_substitution_count(player_name_kun_result) == 3, "expected three PLAYER/KUN/string-var substitutions")
	_assert(_first_message_placeholder_value_for_token(player_name_kun_result, "{PLAYER}") == "小悠", "unexpected PLAYER placeholder value")
	_assert(_first_message_placeholder_value_for_token(player_name_kun_result, "{KUN}") == "", "expected empty KUN placeholder value in current source")
	_assert(_first_message_placeholder_value_for_token(player_name_kun_result, "{STR_VAR_1}") == "大哥哥", "unexpected STR_VAR_1 placeholder value")
	_assert(_first_message_placeholder_id_for_token(player_name_kun_result, "{PLAYER}") == 1, "unexpected PLAYER placeholder id")
	_assert(_first_message_placeholder_id_for_token(player_name_kun_result, "{KUN}") == 5, "unexpected KUN placeholder id")
	_assert(_unsupported_count(player_name_kun_result) == 0, "expected no unsupported player-name placeholder ops")

	_assert(rival_placeholder_male_result.get("status", "") == "ok", "expected male rival placeholder script to execute")
	_assert(_first_message_text(rival_placeholder_male_result) == "对手:小遥", "expected male player rival placeholder to expand to May")
	_assert(_first_message_unexpanded_text(rival_placeholder_male_result) == "对手:{RIVAL}", "expected unexpanded male rival placeholder message")
	_assert(_first_message_placeholder_substitution_count(rival_placeholder_male_result) == 1, "expected one male rival placeholder substitution")
	_assert(_first_message_placeholder_value_for_token(rival_placeholder_male_result, "{RIVAL}") == "小遥", "unexpected male RIVAL placeholder value")
	_assert(_first_message_placeholder_id_for_token(rival_placeholder_male_result, "{RIVAL}") == 6, "unexpected RIVAL placeholder id")
	_assert(_unsupported_count(rival_placeholder_male_result) == 0, "expected no unsupported male rival placeholder ops")

	_assert(rival_placeholder_female_result.get("status", "") == "ok", "expected female rival placeholder script to execute")
	_assert(_first_message_text(rival_placeholder_female_result) == "对手:小悠", "expected female player rival placeholder to expand to Brendan")
	_assert(_first_message_placeholder_value_for_token(rival_placeholder_female_result, "{RIVAL}") == "小悠", "unexpected female RIVAL placeholder value")
	_assert(_first_message_placeholder_id_for_token(rival_placeholder_female_result, "{RIVAL}") == 6, "unexpected female RIVAL placeholder id")
	_assert(_unsupported_count(rival_placeholder_female_result) == 0, "expected no unsupported female rival placeholder ops")

	_assert(missing_result.get("status", "") == "missing_script", "expected missing script status")

	print(JSON.stringify({
		"script_vm_smoke": "ok",
		"twin": _result_summary(twin_result),
		"town_sign": _result_summary(town_sign_result),
		"need_pokemon": _result_summary(need_pokemon_result),
		"set_twin_pos": _result_summary(set_twin_pos_result),
		"set_rival_birch_pos": _result_summary(set_rival_birch_pos_result),
		"dex_upgrade_male": _result_summary(dex_upgrade_male_result),
		"dex_upgrade_female": _result_summary(dex_upgrade_female_result),
		"running_shoes": _result_summary(running_shoes_result),
		"mom_return_home": _result_summary(mom_return_home_result),
		"step_off_truck": _result_summary(step_off_truck_result),
		"give_running_shoes": _result_summary(give_running_shoes_result),
		"delay": _result_summary(delay_result),
		"warp": _result_summary(warp_result),
		"global_text": _result_summary(global_text_result),
		"text_controls": _result_summary(text_controls_result),
		"battle_pc_someones": _result_summary(battle_pc_someones_result),
		"battle_pc_lanettes": _result_summary(battle_pc_lanettes_result),
		"yesno_pending": _result_summary(yesno_pending_result),
		"yesno_yes": _result_summary(yesno_yes_result),
		"yesno_no": _result_summary(yesno_no_result),
		"special_player_male": _result_summary(special_player_male_result),
		"special_player_female": _result_summary(special_player_female_result),
		"special_rival_male": _result_summary(special_rival_male_result),
		"special_rival_female": _result_summary(special_rival_female_result),
		"player_name_kun": _result_summary(player_name_kun_result),
		"rival_placeholder_male": _result_summary(rival_placeholder_male_result),
		"rival_placeholder_female": _result_summary(rival_placeholder_female_result),
		"missing_status": String(missing_result.get("status", "")),
	}))
	game_state.free()
	vm.free()
	registry.free()
	quit(0)


func _load_json_object(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("Could not open %s" % path)
		quit(1)
		return {}

	var parsed = JSON.parse_string(file.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("%s is not a JSON object" % path)
		quit(1)
		return {}

	return parsed


func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	push_error(message)
	quit(1)


func _first_text_label(result: Dictionary) -> String:
	var messages = result.get("messages", [])
	if typeof(messages) != TYPE_ARRAY or messages.is_empty():
		return ""
	var first = messages[0]
	if typeof(first) != TYPE_DICTIONARY:
		return ""
	return String(first.get("text_label", ""))


func _message_at(result: Dictionary, index: int) -> Dictionary:
	var messages = result.get("messages", [])
	if typeof(messages) != TYPE_ARRAY or index < 0 or index >= messages.size():
		return {}
	var message = messages[index]
	return message if typeof(message) == TYPE_DICTIONARY else {}


func _message_text_label(result: Dictionary, index: int) -> String:
	return String(_message_at(result, index).get("text_label", ""))


func _first_message_text(result: Dictionary) -> String:
	var messages = result.get("messages", [])
	if typeof(messages) != TYPE_ARRAY or messages.is_empty():
		return ""
	var first = messages[0]
	if typeof(first) != TYPE_DICTIONARY:
		return ""
	return String(first.get("text", ""))


func _first_message_unexpanded_text(result: Dictionary) -> String:
	return String(_message_at(result, 0).get("unexpanded_text", ""))


func _first_message_expanded_text(result: Dictionary) -> String:
	return String(_message_at(result, 0).get("expanded_text", ""))


func _first_message_placeholder_substitution_count(result: Dictionary) -> int:
	var substitutions = _message_at(result, 0).get("placeholder_substitutions", [])
	return substitutions.size() if typeof(substitutions) == TYPE_ARRAY else 0


func _first_message_placeholder_value(result: Dictionary, index: int) -> String:
	var substitutions = _message_at(result, 0).get("placeholder_substitutions", [])
	if typeof(substitutions) != TYPE_ARRAY or index < 0 or index >= substitutions.size():
		return ""
	var substitution = substitutions[index]
	if typeof(substitution) != TYPE_DICTIONARY:
		return ""
	return String(substitution.get("value", ""))


func _first_message_placeholder_value_for_token(result: Dictionary, token: String) -> String:
	var substitution := _first_message_placeholder_for_token(result, token)
	return String(substitution.get("value", ""))


func _first_message_placeholder_id_for_token(result: Dictionary, token: String) -> int:
	var substitution := _first_message_placeholder_for_token(result, token)
	return int(substitution.get("placeholder_id", -1))


func _first_message_placeholder_value_key_for_token(result: Dictionary, token: String) -> String:
	var substitution := _first_message_placeholder_for_token(result, token)
	return String(substitution.get("value_key", ""))


func _first_message_placeholder_source_for_token(result: Dictionary, token: String) -> String:
	var substitution := _first_message_placeholder_for_token(result, token)
	return String(substitution.get("source", ""))


func _first_message_placeholder_for_token(result: Dictionary, token: String) -> Dictionary:
	var substitutions = _message_at(result, 0).get("placeholder_substitutions", [])
	if typeof(substitutions) != TYPE_ARRAY:
		return {}
	for substitution in substitutions:
		if typeof(substitution) == TYPE_DICTIONARY and String(substitution.get("token", "")) == token:
			return substitution
	return {}


func _first_message_text_control_count(result: Dictionary) -> int:
	var controls = _message_at(result, 0).get("text_controls", [])
	return controls.size() if typeof(controls) == TYPE_ARRAY else 0


func _first_message_text_control_code_id_for_token(result: Dictionary, token: String) -> int:
	var control := _first_message_text_control_for_token(result, token)
	return int(control.get("code_id", -1))


func _first_message_text_control_value_id_for_token(result: Dictionary, token: String) -> int:
	var control := _first_message_text_control_for_token(result, token)
	return int(control.get("value_id", -1))


func _first_message_text_control_frames_for_token(result: Dictionary, token: String) -> int:
	var control := _first_message_text_control_for_token(result, token)
	return int(control.get("frames", -1))


func _first_message_text_control_source_length_for_token(result: Dictionary, token: String) -> int:
	var control := _first_message_text_control_for_token(result, token)
	return int(control.get("source_length", -1))


func _first_message_text_control_for_token(result: Dictionary, token: String) -> Dictionary:
	var controls = _message_at(result, 0).get("text_controls", [])
	if typeof(controls) != TYPE_ARRAY:
		return {}
	for control in controls:
		if typeof(control) == TYPE_DICTIONARY and String(control.get("token", "")) == token:
			return control
	return {}


func _first_message_encoding_status(result: Dictionary) -> String:
	var messages = result.get("messages", [])
	if typeof(messages) != TYPE_ARRAY or messages.is_empty():
		return ""
	var first = messages[0]
	if typeof(first) != TYPE_DICTIONARY:
		return ""
	return String(first.get("encoding_status", ""))


func _first_message_source_byte_count(result: Dictionary) -> int:
	var messages = result.get("messages", [])
	if typeof(messages) != TYPE_ARRAY or messages.is_empty():
		return 0
	var first = messages[0]
	if typeof(first) != TYPE_DICTIONARY:
		return 0
	return int(first.get("source_byte_count", 0))


func _first_message_has_terminator(result: Dictionary) -> bool:
	var messages = result.get("messages", [])
	if typeof(messages) != TYPE_ARRAY or messages.is_empty():
		return false
	var first = messages[0]
	if typeof(first) != TYPE_DICTIONARY:
		return false
	return bool(first.get("terminator_present", false))


func _first_message_text_source(result: Dictionary) -> String:
	var messages = result.get("messages", [])
	if typeof(messages) != TYPE_ARRAY or messages.is_empty():
		return ""
	var first = messages[0]
	if typeof(first) != TYPE_DICTIONARY:
		return ""
	return String(first.get("text_source", ""))


func _first_message_text_kind(result: Dictionary) -> String:
	var messages = result.get("messages", [])
	if typeof(messages) != TYPE_ARRAY or messages.is_empty():
		return ""
	var first = messages[0]
	if typeof(first) != TYPE_DICTIONARY:
		return ""
	return String(first.get("text_kind", ""))


func _text_record(script_data: Dictionary, text_label: String) -> Dictionary:
	var texts = script_data.get("texts", {})
	if typeof(texts) != TYPE_DICTIONARY:
		return {}
	var record = texts.get(text_label, {})
	return record if typeof(record) == TYPE_DICTIONARY else {}


func _text_encoding(script_data: Dictionary, text_label: String) -> Dictionary:
	var record := _text_record(script_data, text_label)
	var encoding = record.get("encoding", {})
	return encoding if typeof(encoding) == TYPE_DICTIONARY else {}


func _text_encoding_status(script_data: Dictionary, text_label: String) -> String:
	return String(_text_encoding(script_data, text_label).get("status", ""))


func _text_source_byte_count(script_data: Dictionary, text_label: String) -> int:
	return int(_text_encoding(script_data, text_label).get("byte_count", 0))


func _text_has_terminator(script_data: Dictionary, text_label: String) -> bool:
	return bool(_text_encoding(script_data, text_label).get("terminator_present", false))


func _text_has_control_token(script_data: Dictionary, text_label: String, token: String) -> bool:
	var controls = _text_encoding(script_data, text_label).get("control_codes", [])
	if typeof(controls) != TYPE_ARRAY:
		return false
	for control in controls:
		if typeof(control) == TYPE_DICTIONARY and String(control.get("token", "")) == token:
			return true
	return false


func _has_effect(result: Dictionary, op: String) -> bool:
	var effects = result.get("effects", [])
	if typeof(effects) != TYPE_ARRAY:
		return false
	for effect in effects:
		if typeof(effect) == TYPE_DICTIONARY and String(effect.get("op", "")) == op:
			return true
	return false


func _effect_count_for_op(result: Dictionary, op: String) -> int:
	var effects = result.get("effects", [])
	if typeof(effects) != TYPE_ARRAY:
		return 0
	var count := 0
	for effect in effects:
		if typeof(effect) == TYPE_DICTIONARY and String(effect.get("op", "")) == op:
			count += 1
	return count


func _effect_value_for_op(result: Dictionary, op: String) -> int:
	var effects = result.get("effects", [])
	if typeof(effects) != TYPE_ARRAY:
		return -1
	for effect in effects:
		if typeof(effect) == TYPE_DICTIONARY and String(effect.get("op", "")) == op:
			return int(effect.get("value", -1))
	return -1


func _unsupported_count(result: Dictionary) -> int:
	var unsupported_ops = result.get("unsupported_ops", [])
	if typeof(unsupported_ops) != TYPE_ARRAY:
		return 0
	return unsupported_ops.size()


func _result_summary(result: Dictionary) -> Dictionary:
	return {
		"status": String(result.get("status", "")),
		"message_count": _message_count(result),
		"first_text_label": _first_text_label(result),
		"effect_count": _effect_count(result),
		"movement_count": _movement_count(result),
		"object_effect_count": _object_effect_count(result),
		"field_effect_count": _field_effect_count(result),
		"ui_effect_count": _ui_effect_count(result),
		"special_effect_count": _special_effect_count(result),
		"audio_effect_count": _audio_effect_count(result),
		"transition_effect_count": _transition_effect_count(result),
		"player_effect_count": _player_effect_count(result),
		"wait_buttonpress": bool(result.get("wait_buttonpress", false)),
		"wait_movement": bool(result.get("wait_movement", false)),
		"wait_ui": bool(result.get("wait_ui", false)),
		"wait_state": bool(result.get("wait_state", false)),
		"wait_audio": bool(result.get("wait_audio", false)),
		"step_count": int(result.get("step_count", 0)),
	}


func _message_count(result: Dictionary) -> int:
	var messages = result.get("messages", [])
	return messages.size() if typeof(messages) == TYPE_ARRAY else 0


func _effect_count(result: Dictionary) -> int:
	var effects = result.get("effects", [])
	return effects.size() if typeof(effects) == TYPE_ARRAY else 0


func _movement_count(result: Dictionary) -> int:
	var movements = result.get("movements", [])
	return movements.size() if typeof(movements) == TYPE_ARRAY else 0


func _object_effect_count(result: Dictionary) -> int:
	var object_effects = result.get("object_effects", [])
	return object_effects.size() if typeof(object_effects) == TYPE_ARRAY else 0


func _field_effect_count(result: Dictionary) -> int:
	var field_effects = result.get("field_effects", [])
	return field_effects.size() if typeof(field_effects) == TYPE_ARRAY else 0


func _ui_effect_count(result: Dictionary) -> int:
	var ui_effects = result.get("ui_effects", [])
	return ui_effects.size() if typeof(ui_effects) == TYPE_ARRAY else 0


func _special_effect_count(result: Dictionary) -> int:
	var special_effects = result.get("special_effects", [])
	return special_effects.size() if typeof(special_effects) == TYPE_ARRAY else 0


func _audio_effect_count(result: Dictionary) -> int:
	var audio_effects = result.get("audio_effects", [])
	return audio_effects.size() if typeof(audio_effects) == TYPE_ARRAY else 0


func _transition_effect_count(result: Dictionary) -> int:
	var transition_effects = result.get("transition_effects", [])
	return transition_effects.size() if typeof(transition_effects) == TYPE_ARRAY else 0


func _player_effect_count(result: Dictionary) -> int:
	var player_effects = result.get("player_effects", [])
	return player_effects.size() if typeof(player_effects) == TYPE_ARRAY else 0


func _movement_at(result: Dictionary, index: int) -> Dictionary:
	var movements = result.get("movements", [])
	if typeof(movements) != TYPE_ARRAY or index < 0 or index >= movements.size():
		return {}
	var movement = movements[index]
	return movement if typeof(movement) == TYPE_DICTIONARY else {}


func _object_effect_at(result: Dictionary, index: int) -> Dictionary:
	var object_effects = result.get("object_effects", [])
	if typeof(object_effects) != TYPE_ARRAY or index < 0 or index >= object_effects.size():
		return {}
	var object_effect = object_effects[index]
	return object_effect if typeof(object_effect) == TYPE_DICTIONARY else {}


func _field_effect_at(result: Dictionary, index: int) -> Dictionary:
	var field_effects = result.get("field_effects", [])
	if typeof(field_effects) != TYPE_ARRAY or index < 0 or index >= field_effects.size():
		return {}
	var field_effect = field_effects[index]
	return field_effect if typeof(field_effect) == TYPE_DICTIONARY else {}


func _ui_effect_at(result: Dictionary, index: int) -> Dictionary:
	var ui_effects = result.get("ui_effects", [])
	if typeof(ui_effects) != TYPE_ARRAY or index < 0 or index >= ui_effects.size():
		return {}
	var ui_effect = ui_effects[index]
	return ui_effect if typeof(ui_effect) == TYPE_DICTIONARY else {}


func _special_effect_at(result: Dictionary, index: int) -> Dictionary:
	var special_effects = result.get("special_effects", [])
	if typeof(special_effects) != TYPE_ARRAY or index < 0 or index >= special_effects.size():
		return {}
	var special_effect = special_effects[index]
	return special_effect if typeof(special_effect) == TYPE_DICTIONARY else {}


func _audio_effect_at(result: Dictionary, index: int) -> Dictionary:
	var audio_effects = result.get("audio_effects", [])
	if typeof(audio_effects) != TYPE_ARRAY or index < 0 or index >= audio_effects.size():
		return {}
	var audio_effect = audio_effects[index]
	return audio_effect if typeof(audio_effect) == TYPE_DICTIONARY else {}


func _transition_effect_at(result: Dictionary, index: int) -> Dictionary:
	var transition_effects = result.get("transition_effects", [])
	if typeof(transition_effects) != TYPE_ARRAY or index < 0 or index >= transition_effects.size():
		return {}
	var transition_effect = transition_effects[index]
	return transition_effect if typeof(transition_effect) == TYPE_DICTIONARY else {}


func _player_effect_at(result: Dictionary, index: int) -> Dictionary:
	var player_effects = result.get("player_effects", [])
	if typeof(player_effects) != TYPE_ARRAY or index < 0 or index >= player_effects.size():
		return {}
	var player_effect = player_effects[index]
	return player_effect if typeof(player_effect) == TYPE_DICTIONARY else {}


func _movement_label(result: Dictionary, index: int) -> String:
	return String(_movement_at(result, index).get("movement_label", ""))


func _movement_target(result: Dictionary, index: int) -> String:
	return String(_movement_at(result, index).get("target", ""))


func _object_effect_op(result: Dictionary, index: int) -> String:
	return String(_object_effect_at(result, index).get("op", ""))


func _field_effect_op(result: Dictionary, index: int) -> String:
	return String(_field_effect_at(result, index).get("op", ""))


func _ui_effect_op(result: Dictionary, index: int) -> String:
	return String(_ui_effect_at(result, index).get("op", ""))


func _special_effect_function(result: Dictionary, index: int) -> String:
	return String(_special_effect_at(result, index).get("function", ""))


func _special_effect_write_value(result: Dictionary, index: int, var_name: String) -> String:
	var writes = _special_effect_at(result, index).get("writes", [])
	if typeof(writes) != TYPE_ARRAY:
		return ""
	for write in writes:
		if typeof(write) == TYPE_DICTIONARY and String(write.get("var", "")) == var_name:
			return String(write.get("value", ""))
	return ""


func _string_var_value(result: Dictionary, var_name: String) -> String:
	var string_vars = result.get("string_vars", {})
	if typeof(string_vars) != TYPE_DICTIONARY:
		return ""
	return String(string_vars.get(var_name, ""))


func _audio_effect_op(result: Dictionary, index: int) -> String:
	return String(_audio_effect_at(result, index).get("op", ""))


func _transition_effect_op(result: Dictionary, index: int) -> String:
	return String(_transition_effect_at(result, index).get("op", ""))


func _player_effect_op(result: Dictionary, index: int) -> String:
	return String(_player_effect_at(result, index).get("op", ""))


func _object_effect_target(result: Dictionary, index: int) -> String:
	return String(_object_effect_at(result, index).get("target", ""))


func _object_effect_movement_type(result: Dictionary, index: int) -> String:
	return String(_object_effect_at(result, index).get("movement_type", ""))


func _object_effect_position(result: Dictionary, index: int) -> Vector2i:
	var position = _object_effect_at(result, index).get("position", [0, 0])
	if typeof(position) != TYPE_ARRAY or position.size() < 2:
		return Vector2i.ZERO
	return Vector2i(int(position[0]), int(position[1]))


func _field_effect_position(result: Dictionary, index: int) -> Vector2i:
	var position = _field_effect_at(result, index).get("position", [0, 0])
	if typeof(position) != TYPE_ARRAY or position.size() < 2:
		return Vector2i.ZERO
	return Vector2i(int(position[0]), int(position[1]))


func _field_effect_frames(result: Dictionary, index: int) -> int:
	return int(_field_effect_at(result, index).get("frames", 0))


func _ui_effect_script_position(result: Dictionary, index: int) -> Vector2i:
	return _vector_from_array(_ui_effect_at(result, index).get("script_position", [0, 0]))


func _ui_effect_menu_position(result: Dictionary, index: int) -> Vector2i:
	return _vector_from_array(_ui_effect_at(result, index).get("menu_position", [0, 0]))


func _ui_effect_menu_size(result: Dictionary, index: int) -> Vector2i:
	return _vector_from_array(_ui_effect_at(result, index).get("menu_size", [0, 0]))


func _ui_effect_default_choice(result: Dictionary, index: int) -> String:
	return String(_ui_effect_at(result, index).get("default_choice", ""))


func _ui_effect_b_choice(result: Dictionary, index: int) -> String:
	return String(_ui_effect_at(result, index).get("b_choice", ""))


func _ui_effect_input_delay_frames(result: Dictionary, index: int) -> int:
	return int(_ui_effect_at(result, index).get("input_delay_frames", 0))


func _ui_effect_selected_choice(result: Dictionary, index: int) -> String:
	return String(_ui_effect_at(result, index).get("selected_choice", ""))


func _ui_effect_selected_value(result: Dictionary, index: int) -> int:
	return int(_ui_effect_at(result, index).get("selected_value", -1))


func _vector_from_array(value) -> Vector2i:
	if typeof(value) != TYPE_ARRAY or value.size() < 2:
		return Vector2i.ZERO
	return Vector2i(int(value[0]), int(value[1]))


func _audio_effect_sound(result: Dictionary, index: int) -> String:
	return String(_audio_effect_at(result, index).get("sound", ""))


func _audio_effect_fanfare(result: Dictionary, index: int) -> String:
	return String(_audio_effect_at(result, index).get("fanfare", ""))


func _transition_effect_map(result: Dictionary, index: int) -> String:
	return String(_transition_effect_at(result, index).get("map", ""))


func _transition_effect_style(result: Dictionary, index: int) -> String:
	return String(_transition_effect_at(result, index).get("style", ""))


func _transition_effect_sound(result: Dictionary, index: int) -> String:
	return String(_transition_effect_at(result, index).get("sound_effect", ""))


func _transition_effect_position(result: Dictionary, index: int) -> Vector2i:
	var position = _transition_effect_at(result, index).get("position", [0, 0])
	if typeof(position) != TYPE_ARRAY or position.size() < 2:
		return Vector2i.ZERO
	return Vector2i(int(position[0]), int(position[1]))


func _player_effect_visible(result: Dictionary, index: int) -> bool:
	return bool(_player_effect_at(result, index).get("visible", true))


func _movement_step_count(result: Dictionary, index: int) -> int:
	return int(_movement_at(result, index).get("step_count", 0))


func _movement_final_facing(result: Dictionary, index: int) -> String:
	return String(_movement_at(result, index).get("final_facing", ""))


func _movement_net_delta(result: Dictionary, index: int) -> Vector2i:
	var delta = _movement_at(result, index).get("net_delta", [0, 0])
	if typeof(delta) != TYPE_ARRAY or delta.size() < 2:
		return Vector2i.ZERO
	return Vector2i(int(delta[0]), int(delta[1]))


func _has_movement(result: Dictionary, target: String, movement_label: String) -> bool:
	var movements = result.get("movements", [])
	if typeof(movements) != TYPE_ARRAY:
		return false
	for movement in movements:
		if typeof(movement) != TYPE_DICTIONARY:
			continue
		if String(movement.get("target", "")) == target and String(movement.get("movement_label", "")) == movement_label:
			return true
	return false
