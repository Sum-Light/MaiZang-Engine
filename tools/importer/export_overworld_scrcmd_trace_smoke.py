#!/usr/bin/env python3
"""Smoke checks for the overworld script-command trace report."""

import argparse
import sys
from pathlib import Path

from export_overworld_scrcmd_trace import build_export
from source_probe import load_config


def main(argv):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--config", type=Path, help="JSON config with source and output roots.")
    parser.add_argument("--source", type=Path, help="pokeemerald-expansion source root.")
    args = parser.parse_args(argv)

    config = load_config(args.config)
    source_root = args.source or Path(config.get("source_root", ""))
    exported = build_export(source_root)
    stats = exported["stats"]

    _assert(exported["schema_version"] == 1, "unexpected schema version")
    _assert(exported["generated_by"].endswith("export_overworld_scrcmd_trace.py"), "unexpected generator")
    _assert(stats["flow_count"] == 13, "unexpected flow count")
    _assert(stats["source_file_count"] == 32, "unexpected source file count")
    _assert(stats["missing_source_file_count"] == 0, "missing source files")
    _assert(stats["required_symbol_count"] == 120, "unexpected required symbol count")
    _assert(stats["missing_symbol_count"] == 0, "missing source symbols: %s" % stats["missing_symbols"])
    _assert(stats["unsupported_count"] == 15, "unexpected unsupported count")
    _assert(stats["status_counts"].get("first_pass", 0) == 5, "unexpected first-pass flow count")
    _assert(stats["status_counts"].get("unsupported", 0) == 4, "unexpected unsupported flow count")
    _assert(stats["status_counts"].get("metadata_only", 0) == 4, "unexpected metadata-only flow count")
    _assert(stats["unsupported_status_counts"].get("unsupported", 0) == 13, "unexpected unsupported gap count")
    _assert(stats["unsupported_status_counts"].get("metadata_only", 0) == 2, "unexpected metadata-only gap count")

    _assert(stats["script_cmd_table_entry_count"] == 231, "unexpected command table count")
    _assert(stats["script_cmd_table_last_opcode"] == 230, "unexpected last opcode")
    _assert(stats["script_cmd_table_requests_effects_count"] == 231, "unexpected requests_effects count")
    _assert(stats["unique_table_handler_count"] == 225, "unexpected unique handler count")
    _assert(stats["scrcmd_function_count"] == 239, "unexpected ScrCmd function count")
    _assert(stats["scrcmd_functions_not_in_table_count"] == 14, "unexpected extra ScrCmd function count")
    _assert(stats["table_handlers_missing_definition_count"] == 0, "missing table handler definitions")
    _assert(stats["event_macro_count"] == 385, "unexpected event macro count")
    _assert(stats["event_macro_with_opcode_count"] == 228, "unexpected opcode macro count")
    _assert(stats["event_macro_with_native_handler_count"] == 18, "unexpected native-handler macro count")
    _assert(stats["native_wait_function_count"] == 20, "unexpected native wait count")
    _assert(stats["script_context_stop_function_count"] == 19, "unexpected ScriptContext_Stop count")
    _assert(stats["hardware_effect_function_count"] == 98, "unexpected hardware-effect count")
    _assert(stats["save_effect_function_count"] == 66, "unexpected save-effect count")
    _assert(stats["supported_generated_op_count"] == 63, "unexpected ScriptVM op count")
    _assert(stats["direct_table_command_supported_count"] == 43, "unexpected direct table support count")
    _assert(stats["supported_macro_name_count"] == 57, "unexpected supported macro name count")

    category_counts = stats["category_counts"]
    _assert(category_counts["wait_timing"] == 11, "unexpected wait category count")
    _assert(category_counts["door"] == 6, "unexpected door category count")
    _assert(category_counts["warp_transition"] == 13, "unexpected warp category count")
    _assert(category_counts["weather_fade_flash"] == 13, "unexpected weather/fade category count")
    _assert(category_counts["audio"] == 12, "unexpected audio category count")
    _assert(category_counts["field_effect"] == 3, "unexpected field-effect category count")
    _assert(category_counts["object_event"] == 22, "unexpected object-event category count")
    _assert(category_counts["trainer_battle"] == 11, "unexpected trainer/battle category count")
    _assert(category_counts["map_mutation"] == 4, "unexpected map-mutation category count")

    commands = {entry["handler"]: entry for entry in exported["script_command_table"]}
    _assert(commands["ScrCmd_nop"]["opcode_hex"] == "0x00", "nop opcode mismatch")
    _assert(commands["ScrCmd_getbraillestringwidth"]["opcode_hex"] == "0xe6", "last opcode mismatch")
    _assert(commands["ScrCmd_delay"]["uses_setup_native_script"], "delay should use SetupNativeScript")
    _assert(commands["ScrCmd_delay"]["returns_true_literal"], "delay should return TRUE")
    _assert(commands["ScrCmd_fadescreenswapbuffers"]["uses_setup_native_script"], "fadescreenswapbuffers should wait unless nowait")
    _assert("FadeScreenHardware" in commands["ScrCmd_fadescreenswapbuffers"]["source_calls"], "missing FadeScreenHardware call")
    _assert(commands["ScrCmd_setweather"]["categories"] == ["weather_fade_flash"], "setweather category mismatch")
    _assert("SetSavedWeather" in commands["ScrCmd_setweather"]["source_calls"], "missing SetSavedWeather call")
    _assert("DoCurrentWeather" in commands["ScrCmd_doweather"]["source_calls"], "missing DoCurrentWeather call")

    _assert(commands["ScrCmd_warp"]["godot_status"] == "first_pass", "warp should be first-pass")
    _assert("DoWarp" in commands["ScrCmd_warp"]["source_calls"], "missing DoWarp call")
    _assert("ResetInitialPlayerAvatarState" in commands["ScrCmd_warp"]["source_calls"], "missing warp avatar reset")
    _assert(commands["ScrCmd_warpsilent"]["godot_status"] == "first_pass", "warpsilent should be first-pass")
    _assert("DoDiveWarp" in commands["ScrCmd_warpsilent"]["source_calls"], "missing warpsilent DoDiveWarp call")
    _assert(commands["ScrCmd_warpdoor"]["godot_status"] == "unsupported", "warpdoor should remain unsupported")
    _assert("DoDoorWarp" in commands["ScrCmd_warpdoor"]["source_calls"], "missing DoDoorWarp call")
    _assert("DoFallWarp" in commands["ScrCmd_warphole"]["source_calls"], "missing DoFallWarp call")
    _assert("DoSpinEnterWarp" in commands["ScrCmd_warpspinenter"]["source_calls"], "missing DoSpinEnterWarp call")
    _assert("DoWhiteFadeWarp" in commands["ScrCmd_warpwhitefade"]["source_calls"], "missing DoWhiteFadeWarp call")

    _assert(commands["ScrCmd_playse"]["godot_status"] == "first_pass", "playse should be first-pass metadata")
    _assert("PlaySE" in commands["ScrCmd_playse"]["source_calls"], "missing PlaySE call")
    _assert(commands["ScrCmd_waitse"]["uses_setup_native_script"], "waitse should use native wait")
    _assert("SetupNativeScript" in commands["ScrCmd_waitse"]["source_calls"], "missing waitse SetupNativeScript call")
    _assert("PlayFanfare" in commands["ScrCmd_playfanfare"]["source_calls"], "missing PlayFanfare call")
    _assert(commands["ScrCmd_waitfanfare"]["uses_setup_native_script"], "waitfanfare should use native wait")

    _assert("BattleSetup_ConfigureTrainerBattle" in commands["ScrCmd_trainerbattle"]["source_calls"], "missing trainer setup call")
    _assert(commands["ScrCmd_trainerbattle"]["effect_flags"] == ["SCREFF_TRAINERBATTLE", "SCREFF_V1"], "trainerbattle flags mismatch")
    _assert("BattleSetup_StartTrainerBattle" in commands["ScrCmd_dotrainerbattle"]["source_calls"], "missing trainer battle start")
    _assert(commands["ScrCmd_dotrainerbattle"]["returns_true_literal"], "dotrainerbattle should return TRUE")
    _assert("CreateScriptedWildMon" in commands["ScrCmd_setwildbattle"]["source_calls"], "missing scripted wild mon call")
    _assert("CreateScriptedDoubleWildMon" in commands["ScrCmd_setwildbattle"]["source_calls"], "missing scripted double wild mon call")
    _assert(commands["ScrCmd_dowildbattle"]["stops_script_context"], "dowildbattle should stop script context")

    _assert("FieldEffectStart" in commands["ScrCmd_dofieldeffect"]["source_calls"], "missing FieldEffectStart call")
    _assert(commands["ScrCmd_waitfieldeffect"]["uses_setup_native_script"], "waitfieldeffect should install a native wait")
    _assert(_has_occurrence(exported["required_symbols"], "FieldEffectActiveListContains", "src/scrcmd.c"), "missing FieldEffectActiveListContains occurrence")
    _assert(commands["ScrCmd_setmetatile"]["godot_status"] == "first_pass", "setmetatile should be first-pass")
    _assert("MapGridSetMetatileIdAt" in commands["ScrCmd_setmetatile"]["source_calls"], "missing MapGridSetMetatileIdAt call")
    _assert(commands["ScrCmd_opendoor"]["godot_status"] == "first_pass", "opendoor should be first-pass")
    _assert("FieldAnimateDoorOpen" in commands["ScrCmd_opendoor"]["source_calls"], "missing FieldAnimateDoorOpen call")
    _assert("PlaySE" in commands["ScrCmd_opendoor"]["source_calls"], "missing opendoor PlaySE call")
    _assert(commands["ScrCmd_waitdooranim"]["uses_setup_native_script"], "waitdooranim should use native wait")

    functions_not_in_table = set(stats["scrcmd_functions_not_in_table"])
    for function in [
        "ScrCmd_gettimeofday",
        "ScrCmd_getobjectxy",
        "ScrCmd_removeallitem",
        "ScrCmd_setstartingstatus",
    ]:
        _assert(function in functions_not_in_table, "missing extra ScrCmd function %s" % function)

    macros = {entry["macro"]: entry for entry in exported["event_macros"]}
    _assert(not macros["formatwarp"]["emits_command"], "formatwarp is a helper macro")
    _assert(macros["warp"]["command_constants"] == ["SCR_OP_WARP"], "warp macro mismatch")
    _assert(macros["warpsilent"]["command_constants"] == ["SCR_OP_WARPSILENT"], "warpsilent macro mismatch")
    _assert(macros["warpwhitefade"]["command_constants"] == ["SCR_OP_WARPWHITEFADE"], "warpwhitefade macro mismatch")
    _assert(macros["setmetatile"]["command_constants"] == ["SCR_OP_SETMETATILE"], "setmetatile macro mismatch")
    _assert(macros["setweather"]["command_constants"] == ["SCR_OP_SETWEATHER"], "setweather macro mismatch")
    _assert(macros["dofieldeffect"]["command_constants"] == ["SCR_OP_DOFIELDEFFECT"], "dofieldeffect macro mismatch")
    _assert(macros["gettimeofday"]["native_handlers"] == ["ScrCmd_gettimeofday"], "gettimeofday should use callnative handler")
    _assert(not macros["trainerbattle_single"]["emits_command"], "trainerbattle_single delegates through trainerbattle macro")

    flows = {entry["id"]: entry for entry in exported["source_flows"]}
    for flow_id in [
        "script_command_table_order",
        "effect_instrumentation",
        "wait_and_native_blocking",
        "warp_and_transition_commands",
        "map_mutation_and_door_commands",
        "weather_fade_flash_commands",
        "audio_commands",
        "movement_object_lock_commands",
        "trainer_and_battle_commands",
        "field_effect_commands",
        "message_ui_and_menu_commands",
        "godot_current_script_vm_gap",
        "visual_effect_and_audio_policy",
    ]:
        _assert(flow_id in flows, "missing flow %s" % flow_id)
    _assert(flows["wait_and_native_blocking"]["status"] == "unsupported", "wait flow should be unsupported")
    _assert(flows["audio_commands"]["status"] == "metadata_only", "audio flow should be metadata-only")
    _assert(flows["movement_object_lock_commands"]["status"] == "first_pass", "movement/object flow should be first-pass")

    unsupported_codes = {entry["code"] for entry in exported["unsupported"]}
    for code in [
        "scrcmd_full_vm_pending",
        "async_native_wait_scheduler_pending",
        "weather_script_commands_pending",
        "fade_palette_runtime_pending",
        "audio_playback_metadata_only",
        "field_effect_runtime_pending",
        "trainerbattle_script_commands_pending",
        "scripted_wild_battle_commands_pending",
        "broad_warp_variants_pending",
        "door_set_open_closed_pending",
        "object_subpriority_vobject_pending",
        "map_layout_step_callback_pending",
        "shop_menu_contest_commands_pending",
        "callnative_special_broad_pending",
        "gba_hardware_effects_godot_native",
    ]:
        _assert(code in unsupported_codes, "missing unsupported code %s" % code)

    godot = exported["godot_current"]
    _assert(godot["runtime_status"] == "first_pass_synchronous_subset", "unexpected Godot runtime status")
    _assert(godot["supported_generated_op_count"] == 63, "unexpected Godot op count")
    _assert(godot["direct_table_command_supported_count"] == 43, "unexpected direct table support")
    _assert("warp" in godot["supported_generated_ops"], "missing supported warp op")
    _assert("setweather" not in godot["supported_generated_ops"], "setweather should not be supported")
    _assert(godot["audio_status"] == "metadata_only", "audio status mismatch")
    _assert(godot["weather_status"] == "unsupported", "weather status mismatch")
    _assert(godot["trainerbattle_script_status"] == "unsupported", "trainerbattle script status mismatch")

    policy = exported["visual_effect_policy"]
    _assert("Godot-native" in policy["palette_and_affine"], "missing Godot-native visual policy")
    _assert("metadata_only" in policy["audio"], "missing audio metadata-only policy")

    print("export_overworld_scrcmd_trace_smoke: ok")
    return 0


def _assert(condition, message):
    if not condition:
        raise AssertionError(message)


def _has_occurrence(symbols, symbol, source_file):
    for occurrence in symbols.get(symbol, []):
        if occurrence.get("file") == source_file:
            return True
    return False


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
