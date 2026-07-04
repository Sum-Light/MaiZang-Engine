#!/usr/bin/env python3
"""Build the battle parity coverage report and source symbol index."""

import argparse
import json
import re
import sys
from collections import Counter
from pathlib import Path


STATUS_VALUES = ["implemented", "first_pass", "metadata_only", "unsupported", "untraced"]


UNSUPPORTED_CODE_REGISTRY = {
    "battle_script_vm_pending": "Battle scripts are not yet decoded/executed by a source-backed VM.",
    "battle_animation_runtime_pending": "Battle animation scripts, sprite tags, and visual tasks are not yet interpreted.",
    "battle_assets_pending": "Source battle Pokemon/trainer/interface/environment assets are not yet imported as Godot textures/resources.",
    "battle_environment_asset_pending": "The source environment row has no imported battle background/entry texture in this slice.",
    "battle_environment_runtime_pending": "Battle background selection, scrolling, entry overlay playback, and scene presentation are not source-equivalent yet.",
    "battle_hud_pending": "Source healthboxes, windows, text printer, and menu tilemaps are not yet rendered.",
    "battle_audio_playback_pending": "Battle music, cries, fanfares, and sound effects are metadata-only.",
    "ability_runtime_pending": "Ability flags are generated, but battle hook behavior and popup timing are not implemented.",
    "trainer_ai_pending": "Trainer AI flags are generated, but source AI scoring/action choice is not implemented.",
    "trainer_rewards_pending": "Trainer reward, rematch, and post-battle mutation flow are metadata/future work.",
    "pokemon_asset_import_pending": "Pokemon front/back sprites, palettes, offsets, shadows, and animations are not imported.",
    "trainer_asset_import_pending": "Trainer battle sprites, palettes, mugshots, and slide metadata are not imported.",
    "debug_launcher_pending": "Developer quick battle launchers are not implemented yet.",
    "debug_random_wild_not_source_encounter": "F6 is a Godot-only random species/random level battle fixture, not a source grass/water/fishing encounter path.",
    "map_decoupled_debug_only": "The row describes a Godot-only developer access path, not source gameplay.",
}


BATTLE_SOURCE_PATTERNS = [
    "src/battle_setup.c",
    "src/battle_main.c",
    "src/battle_intro.c",
    "src/battle_controller_*.c",
    "src/battle_script_commands.c",
    "src/battle_anim.c",
    "src/battle_anim_*.c",
    "src/battle_interface.c",
    "src/battle_bg.c",
    "src/data/battle_environment.h",
    "src/data/graphics/battle_environment.h",
    "src/battle_message.c",
    "src/battle_ai_*.c",
    "src/battle_move_resolution.c",
    "src/battle_util.c",
    "src/battle_util2.c",
    "src/battle_transition.c",
    "src/battle_transition_frontier.c",
    "src/trainer_pokemon_sprites.c",
    "src/pokemon_animation.c",
    "src/data/battle_move_effects.h",
    "src/data/battle_anim.h",
    "src/data/graphics/pokemon.h",
    "src/data/graphics/trainers.h",
    "data/battle_scripts_1.s",
    "data/battle_scripts_2.s",
    "data/battle_anim_scripts.s",
    "include/constants/battle_string_ids.h",
    "include/constants/battle_script_commands.h",
    "include/constants/battle_move_effects.h",
    "include/constants/battle_anim.h",
    "include/config/battle.h",
]


FIXED_BATTLE_SYMBOLS = [
    "Task_BattleStart",
    "BattleSetup_StartWildBattle",
    "DoStandardWildBattle",
    "DoTrainerBattle",
    "GetWildBattleTransition",
    "GetTrainerBattleTransition",
    "CB2_InitBattle",
    "CB2_InitBattleInternal",
    "BattleMainCB2",
    "DoBattleIntro",
    "HandleTurnActionSelectionState",
    "SetActionsAndBattlersTurnOrder",
    "RunTurnActionsFunctions",
    "CalculateBaseDamage",
    "DoMoveDamageCalcVars",
    "gBattleMoveEffects",
    "gBattleAnimTable",
    "gBattleAnimBackgroundTable",
    "gBattleEnvironmentInfo",
    "sStandardBattleWindowTemplates",
    "sBattlerHealthboxCoords",
    "gText_WhatWillPkmnDo",
    "gText_BattleMenu",
    "gText_MoveInterfacePP",
    "gText_MoveInterfaceType",
]


DEBUG_LAUNCHER_ROWS = [
    {
        "id": "debug_quick_wild_battle",
        "label": "Quick wild battle",
        "requested_action": "debug_quick_wild_battle",
        "proposed_key": "F6",
        "implementation_status": "first_pass",
        "map_decoupled": True,
        "developer_only": True,
        "normal_contract": "random generated species + random level -> BattleEngine.create_wild_battle_state -> BattleScene handoff",
        "tests": ["tools/godot_smoke/debug_battle_launcher_smoke.gd"],
        "unsupported": [
            "debug_random_wild_not_source_encounter",
            "map_decoupled_debug_only",
            "battle_hud_pending",
            "battle_audio_playback_pending",
        ],
    },
    {
        "id": "debug_trainer_battle_selector",
        "label": "Trainer battle selector",
        "requested_action": "debug_trainer_battle_selector",
        "proposed_key": "F7",
        "implementation_status": "first_pass",
        "map_decoupled": True,
        "developer_only": True,
        "normal_contract": "trainer id/symbol -> BattleEngine.create_trainer_battle_state",
        "tests": ["tools/godot_smoke/debug_battle_launcher_smoke.gd"],
        "unsupported": [
            "map_decoupled_debug_only",
            "battle_hud_pending",
            "battle_audio_playback_pending",
            "trainer_rewards_pending",
        ],
    },
]


def load_json(path):
    with path.open("r", encoding="utf-8") as handle:
        return json.load(handle)


def load_json_optional(path):
    if not path.exists():
        return {}
    return load_json(path)


def write_json(path, data):
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8", newline="\n") as handle:
        json.dump(data, handle, ensure_ascii=False, indent=2)
        handle.write("\n")


def to_project_path(value):
    return str(value).replace("\\", "/")


def constant_symbol(value):
    if isinstance(value, dict):
        return str(value.get("symbol", ""))
    return ""


def source_ref(record):
    if not isinstance(record, dict):
        return {}
    source = record.get("source", {})
    return source if isinstance(source, dict) else {}


def int_field_value(value, default=0):
    if isinstance(value, dict):
        value = value.get("value", default)
    try:
        return int(value)
    except (TypeError, ValueError):
        return default


def unsupported_row(*codes):
    return [code for code in codes if code]


def build_move_rows(moves_data):
    rows = []
    moves = moves_data.get("moves", {})
    for symbol in moves_data.get("move_order", []):
        record = moves.get(symbol, {})
        effect_symbol = constant_symbol(record.get("effect", {}))
        battle_script_label = str(record.get("battle_effect_script", ""))
        power = int(record.get("power", 0) or 0)
        ordinary_first_pass = effect_symbol == "EFFECT_HIT" and power > 0
        rows.append({
            "id": symbol,
            "move_symbol": symbol,
            "effect_symbol": effect_symbol,
            "battle_script_label": battle_script_label,
            "battle_anim_script": str(record.get("battle_anim_script", "")),
            "target": constant_symbol(record.get("target", {})),
            "flags_present": sorted(record.get("flags", {}).keys()) if isinstance(record.get("flags"), dict) else [],
            "additional_effect_count": len(record.get("additional_effects", [])) if isinstance(record.get("additional_effects"), list) else 0,
            "logic_status": "first_pass" if ordinary_first_pass else "unsupported",
            "animation_status": "unsupported",
            "asset_status": "metadata_only" if record.get("battle_anim_script") else "unsupported",
            "hud_status": "metadata_only",
            "audio_status": "metadata_only",
            "tests": [
                "tools/godot_smoke/data_registry_moves_smoke.gd",
                "tools/godot_smoke/data_registry_move_effects_smoke.gd",
            ] + (["tools/godot_smoke/battle_engine_smoke.gd"] if ordinary_first_pass else []),
            "unsupported": unsupported_row(
                "battle_script_vm_pending",
                "battle_animation_runtime_pending",
                "battle_assets_pending",
                "battle_audio_playback_pending",
            ),
            "source": source_ref(record),
        })
    return rows


def build_ability_rows(abilities_data):
    rows = []
    abilities = abilities_data.get("abilities", {})
    for symbol in abilities_data.get("ability_order", []):
        record = abilities.get(symbol, {})
        flags = record.get("flags", {}) if isinstance(record.get("flags"), dict) else {}
        rows.append({
            "id": symbol,
            "ability_symbol": symbol,
            "flags": flags,
            "hook_families": [],
            "runtime_status": "metadata_only",
            "popup_status": "unsupported",
            "ai_status": "metadata_only" if record.get("ai_rating") is not None else "unsupported",
            "tests": ["tools/godot_smoke/data_registry_abilities_smoke.gd"],
            "unsupported": unsupported_row("ability_runtime_pending", "battle_hud_pending"),
            "source": source_ref(record),
        })
    return rows


def build_trainer_rows(trainers_data, trainer_sprites_data):
    rows = []
    trainers = trainers_data.get("trainers", {})
    trainer_sprite_records = trainer_sprites_data.get("trainers", {}) if isinstance(trainer_sprites_data.get("trainers", {}), dict) else {}
    for symbol in trainers_data.get("trainer_order", []):
        record = trainers.get(symbol, {})
        sprite_record = trainer_sprite_records.get(symbol, {})
        sprite_coverage = sprite_record.get("coverage", {}) if isinstance(sprite_record, dict) else {}
        sprite_asset_status = str(sprite_coverage.get("asset_status", "unsupported"))
        front_sprite = sprite_record.get("front", {}) if isinstance(sprite_record.get("front", {}), dict) else {}
        palette = sprite_record.get("palette", {}) if isinstance(sprite_record.get("palette", {}), dict) else {}
        mugshot_record = sprite_record.get("mugshot", {}) if isinstance(sprite_record.get("mugshot", {}), dict) else {}
        battle_type = constant_symbol(record.get("battle_type", {}))
        is_double = bool(record.get("battle_type", {}).get("is_double", False)) if isinstance(record.get("battle_type"), dict) else False
        tests = ["tools/godot_smoke/data_registry_trainers_smoke.gd", "tools/godot_smoke/battle_engine_smoke.gd"]
        if sprite_asset_status == "first_pass":
            tests.append("tools/godot_smoke/data_registry_trainer_sprites_smoke.gd")
        rows.append({
            "id": symbol,
            "trainer_symbol": symbol,
            "numeric_id": int(record.get("id", -1)),
            "trainer_class": constant_symbol(record.get("trainer_class", {})),
            "pic": constant_symbol(record.get("pic", {})),
            "trainer_pic_symbol": constant_symbol(record.get("pic", {})),
            "trainer_pic_numeric_id": int(record.get("pic", {}).get("value", -1)) if isinstance(record.get("pic"), dict) else -1,
            "front_sprite_image": str(front_sprite.get("image_project_path", "")),
            "front_sprite_source_symbol": str(front_sprite.get("source_symbol", "")),
            "palette_source_symbol": str(palette.get("source_symbol", "")),
            "palette_color_count": int(palette.get("color_count", 0) or 0),
            "party_size": int_field_value(record.get("party_size", 0)),
            "held_item_count": count_party_held_items(record.get("party", [])),
            "explicit_move_mon_count": count_party_move_source(record.get("party", []), "explicit"),
            "default_move_mon_count": count_party_move_source(record.get("party", []), "level_up_default"),
            "ai_flag_count": len(record.get("ai_flags", [])) if isinstance(record.get("ai_flags"), list) else 0,
            "battle_type": battle_type,
            "mugshot": constant_symbol(record.get("mugshot", {})),
            "mugshot_transition_status": str(mugshot_record.get("transition_status", "not_used")),
            "party_status": "first_pass",
            "ai_status": "metadata_only",
            "sprite_status": sprite_asset_status,
            "asset_status": sprite_asset_status,
            "palette_status": str(sprite_coverage.get("palette_status", "unsupported")),
            "slide_status": str(sprite_coverage.get("slide_status", "unsupported")),
            "reward_status": "metadata_only",
            "post_battle_status": "unsupported",
            "animation_status": "unsupported",
            "audio_status": "metadata_only",
            "debug_selectable": True,
            "tests": tests,
            "unsupported": unsupported_row(
                "trainer_ai_pending",
                "trainer_asset_import_pending" if sprite_asset_status != "first_pass" else "",
                "battle_animation_runtime_pending",
                "battle_audio_playback_pending",
                "trainer_rewards_pending",
                "battle_hud_pending" if is_double else "",
            ),
            "source": source_ref(record),
        })
    return rows


def count_party_held_items(party):
    count = 0
    for mon in party if isinstance(party, list) else []:
        held = mon.get("held_item", {}) if isinstance(mon, dict) else {}
        if isinstance(held, dict) and held.get("symbol") not in ("", "ITEM_NONE", None):
            count += 1
    return count


def count_party_move_source(party, expected):
    count = 0
    for mon in party if isinstance(party, list) else []:
        move_source = mon.get("move_source_behavior", {}) if isinstance(mon, dict) else {}
        kind = move_source.get("kind") if isinstance(move_source, dict) else ""
        if kind == expected:
            count += 1
    return count


def build_trainer_party_rows(trainers_data):
    rows = []
    trainers = trainers_data.get("trainers", {})
    for trainer_symbol in trainers_data.get("trainer_order", []):
        trainer = trainers.get(trainer_symbol, {})
        party = trainer.get("party", [])
        if not isinstance(party, list):
            continue
        for mon in party:
            species = constant_symbol(mon.get("species", {}))
            held_item = constant_symbol(mon.get("held_item", {}))
            ability = constant_symbol(mon.get("ability", {}))
            move_source = mon.get("move_source_behavior", {}) if isinstance(mon.get("move_source_behavior"), dict) else {}
            rows.append({
                "id": "%s:%s" % (trainer_symbol, mon.get("index", len(rows))),
                "trainer_symbol": trainer_symbol,
                "trainer_id": int(trainer.get("id", -1)),
                "party_index": int(mon.get("index", 0) or 0),
                "species": species,
                "level": int(mon.get("level", {}).get("value", 0)) if isinstance(mon.get("level"), dict) else 0,
                "held_item": held_item,
                "ability": ability,
                "gender": constant_symbol(mon.get("gender", {})),
                "ivs_status": "metadata_only" if isinstance(mon.get("ivs"), dict) else "unsupported",
                "evs_status": "metadata_only" if isinstance(mon.get("evs"), dict) else "metadata_only",
                "move_source_kind": str(move_source.get("kind", "")),
                "party_construction_status": "first_pass",
                "tests": ["tools/godot_smoke/battle_engine_smoke.gd", "tools/godot_smoke/data_registry_trainers_smoke.gd"],
                "unsupported": unsupported_row("ability_runtime_pending", "trainer_ai_pending"),
                "source": source_ref(mon),
            })
    return rows


def build_pokemon_rows(species_data, battle_sprites_data=None):
    rows = []
    species = species_data.get("species", {})
    battle_sprites_data = battle_sprites_data or {}
    battle_sprites = battle_sprites_data.get("sprites", {})
    if not isinstance(battle_sprites, dict):
        battle_sprites = {}
    seen = set()
    for symbol in species_data.get("species_order", []):
        if symbol in seen:
            continue
        seen.add(symbol)
        record = species.get(symbol, {})
        refs = record.get("source_references", {}) if isinstance(record.get("source_references"), dict) else {}
        sprite_record = battle_sprites.get(symbol, {})
        if not isinstance(sprite_record, dict):
            sprite_record = {}
        front_sprite = sprite_record.get("front", {}) if isinstance(sprite_record.get("front"), dict) else {}
        back_sprite = sprite_record.get("back", {}) if isinstance(sprite_record.get("back"), dict) else {}
        icon_sprite = sprite_record.get("icon", {}) if isinstance(sprite_record.get("icon"), dict) else {}
        palettes = sprite_record.get("palettes", {}) if isinstance(sprite_record.get("palettes"), dict) else {}
        animation = sprite_record.get("animation", {}) if isinstance(sprite_record.get("animation"), dict) else {}
        cry = sprite_record.get("cry", {}) if isinstance(sprite_record.get("cry"), dict) else {}
        coverage = sprite_record.get("coverage", {}) if isinstance(sprite_record.get("coverage"), dict) else {}
        unsupported = list(sprite_record.get("unsupported", [])) if isinstance(sprite_record.get("unsupported"), list) else []
        if not sprite_record:
            unsupported = unsupported_row("pokemon_asset_import_pending")
        tests = ["tools/godot_smoke/data_registry_species_smoke.gd"]
        if sprite_record:
            tests.append("tools/godot_smoke/data_registry_pokemon_battle_sprites_smoke.gd")
        rows.append({
            "id": symbol,
            "species_symbol": symbol,
            "numeric_id": int(record.get("id", -1)),
            "initializer_kind": str(record.get("initializer_kind", "")),
            "evaluation_status": str(record.get("evaluation_status", "")),
            "base_stats_status": "metadata_only" if isinstance(record.get("base_stats"), dict) and record.get("base_stats") else "unsupported",
            "typing_status": "metadata_only" if isinstance(record.get("types"), list) and record.get("types") else "unsupported",
            "abilities_status": "metadata_only" if isinstance(record.get("abilities"), list) and record.get("abilities") else "unsupported",
            "learnset_status": "metadata_only" if refs.get("level_up_learnset") else "unsupported",
            "front_sprite_symbol": str(refs.get("front_pic", "")),
            "back_sprite_symbol": str(refs.get("back_pic", "")),
            "front_sprite_image": str(front_sprite.get("image_project_path", "")),
            "back_sprite_image": str(back_sprite.get("image_project_path", "")),
            "icon_sprite_symbol": str(refs.get("icon_sprite", "")),
            "icon_sprite_image": str(icon_sprite.get("image_project_path", "")),
            "palette_symbol": str(refs.get("palette", "")),
            "shiny_palette_symbol": str(refs.get("shiny_palette", "")),
            "palette_status": str(coverage.get("palette_status", "metadata_only" if palettes else "unsupported")),
            "animation_status": str(coverage.get("animation_status", "metadata_only" if animation else "unsupported")),
            "audio_status": str(coverage.get("audio_status", "metadata_only" if cry.get("source_symbol") else "unsupported")),
            "asset_status": str(coverage.get(
                "asset_status",
                "metadata_only" if refs.get("front_pic") or refs.get("back_pic") else "unsupported",
            )),
            "runtime_status": "metadata_only" if record.get("evaluation_status") == "ok" else "unsupported",
            "tests": tests,
            "unsupported": unsupported,
            "source": source_ref(record),
        })
    return rows


def build_item_rows(items_data):
    rows = []
    items = items_data.get("items", {})
    for symbol in items_data.get("item_order", []):
        record = items.get(symbol, {})
        battle_usage = constant_symbol(record.get("battle_usage", {}))
        hold_effect = constant_symbol(record.get("hold_effect", {}))
        relevant = bool(battle_usage and battle_usage != "EFFECT_ITEM_USE_NONE") or bool(hold_effect and hold_effect != "HOLD_EFFECT_NONE")
        rows.append({
            "id": symbol,
            "item_symbol": symbol,
            "battle_relevant": relevant,
            "battle_usage": battle_usage,
            "hold_effect": hold_effect,
            "runtime_status": "metadata_only" if relevant else "not_battle_relevant",
            "tests": ["tools/godot_smoke/data_registry_items_smoke.gd"],
            "unsupported": unsupported_row("battle_script_vm_pending") if relevant else [],
            "source": source_ref(record),
        })
    return rows


def build_simple_rows(data, order_key, table_key, id_key, symbol_key, tests):
    rows = []
    table = data.get(table_key, {})
    for symbol in data.get(order_key, []):
        record = table.get(symbol, {})
        rows.append({
            "id": symbol,
            symbol_key: symbol,
            "runtime_status": "metadata_only",
            "tests": tests,
            "unsupported": [],
            "source": source_ref(record),
        })
    return rows


def build_wild_encounter_rows(wild_data):
    rows = []
    for record in wild_data.get("encounters", []):
        rows.append({
            "id": str(record.get("id", "")),
            "label": str(record.get("label", "")),
            "map_symbol": constant_symbol(record.get("map", {})),
            "runtime_status": "first_pass",
            "battle_setup_status": "first_pass",
            "debug_quick_wild_candidate": str(record.get("label", "")) == "gRoute101",
            "tests": ["tools/godot_smoke/data_registry_wild_encounters_smoke.gd", "tools/godot_smoke/encounter_engine_smoke.gd"],
            "unsupported": unsupported_row("battle_assets_pending", "battle_audio_playback_pending"),
            "source": {"file": "src/data/wild_encounters.json"},
        })
    return rows


def build_battle_environment_rows(environments_data):
    rows = []
    environments = environments_data.get("environments", {})
    if not isinstance(environments, dict):
        environments = {}
    for symbol in environments_data.get("environment_order", []):
        record = environments.get(symbol, {})
        if not isinstance(record, dict):
            record = {}
        coverage = record.get("coverage", {}) if isinstance(record.get("coverage"), dict) else {}
        background = record.get("background", {}) if isinstance(record.get("background"), dict) else {}
        entry = record.get("entry", {}) if isinstance(record.get("entry"), dict) else {}
        palette = record.get("palette", {}) if isinstance(record.get("palette"), dict) else {}
        source_assets = record.get("source_assets", {}) if isinstance(record.get("source_assets"), dict) else {}
        tests = ["tools/godot_smoke/data_registry_battle_environments_smoke.gd"]
        rows.append({
            "id": symbol,
            "environment_symbol": symbol,
            "numeric_id": int(record.get("numeric_id", -1)),
            "background_asset": str(source_assets.get("background_asset", "")),
            "entry_asset": str(source_assets.get("entry_asset", "")),
            "palette_source_symbol": str(source_assets.get("palette_symbol", "")),
            "background_image": str(background.get("image_project_path", "")),
            "entry_image": str(entry.get("image_project_path", "")),
            "background_size": background.get("size", {}) if isinstance(background.get("size"), dict) else {},
            "entry_size": entry.get("size", {}) if isinstance(entry.get("size"), dict) else {},
            "palette_color_count": int(palette.get("color_count", 0) or 0),
            "nature_power": str(record.get("nature_power", "")),
            "secret_power_effect": str(record.get("secret_power_effect", "")),
            "camouflage_type": str(record.get("camouflage_type", "")),
            "background_status": str(coverage.get("background_status", "unsupported")),
            "entry_status": str(coverage.get("entry_status", "unsupported")),
            "palette_status": str(coverage.get("palette_status", "unsupported")),
            "asset_status": str(coverage.get("asset_status", "unsupported")),
            "selection_status": str(coverage.get("selection_status", "metadata_only")),
            "runtime_status": str(coverage.get("runtime_status", "unsupported")),
            "audio_status": str(coverage.get("audio_status", "metadata_only")),
            "tests": tests,
            "unsupported": list(record.get("unsupported", [])) if isinstance(record.get("unsupported"), list) else [],
            "source": source_ref(record),
        })
    return rows


def build_evolution_rows(evolutions_data):
    rows = []
    seen_species = set()
    for species_symbol in evolutions_data.get("evolution_species_order", []):
        if species_symbol in seen_species:
            continue
        seen_species.add(species_symbol)
        bucket = evolutions_data.get("evolutions_by_species", {}).get(species_symbol, {})
        source = source_ref(bucket)
        for evo in bucket.get("evolutions", []) if isinstance(bucket, dict) else []:
            target = constant_symbol(evo.get("target_species", {}))
            rows.append({
                "id": "%s:%s:%s" % (species_symbol, evo.get("index", len(rows)), target),
                "species_symbol": species_symbol,
                "target_species": target,
                "method": constant_symbol(evo.get("method", {})),
                "runtime_status": "metadata_only",
                "tests": ["tools/godot_smoke/data_registry_evolutions_smoke.gd", "tools/godot_smoke/evolution_engine_smoke.gd"],
                "unsupported": [],
                "source": source,
            })
    return rows


def build_report(project_root, source_root):
    pokemon_root = project_root / "data" / "generated" / "pokemon"
    species_data = load_json(pokemon_root / "species.json")
    moves_data = load_json(pokemon_root / "moves.json")
    abilities_data = load_json(pokemon_root / "abilities.json")
    items_data = load_json(pokemon_root / "items.json")
    wild_data = load_json(pokemon_root / "wild_encounters.json")
    trainers_data = load_json(pokemon_root / "trainers.json")
    learnsets_data = load_json(pokemon_root / "learnsets.json")
    natures_data = load_json(pokemon_root / "natures.json")
    evolutions_data = load_json(pokemon_root / "evolutions.json")
    types_data = load_json(pokemon_root / "types.json")
    battle_sprites_data = load_json_optional(pokemon_root / "battle_sprites.json")
    battle_root = project_root / "data" / "generated" / "battle"
    trainer_sprites_data = load_json_optional(battle_root / "trainer_sprites.json")
    battle_environments_data = load_json_optional(battle_root / "environments.json")

    coverage_rows = {
        "moves": build_move_rows(moves_data),
        "abilities": build_ability_rows(abilities_data),
        "trainers": build_trainer_rows(trainers_data, trainer_sprites_data),
        "trainer_party_mons": build_trainer_party_rows(trainers_data),
        "pokemon_data": build_pokemon_rows(species_data, battle_sprites_data),
        "battle_items": build_item_rows(items_data),
        "wild_encounters": build_wild_encounter_rows(wild_data),
        "battle_environments": build_battle_environment_rows(battle_environments_data),
        "learnsets": build_simple_rows(learnsets_data, "learnset_order", "learnsets", "learnset_id", "learnset_symbol", ["tools/godot_smoke/data_registry_learnsets_smoke.gd"]),
        "natures": build_simple_rows(natures_data, "nature_order", "natures", "nature_id", "nature_symbol", ["tools/godot_smoke/data_registry_natures_smoke.gd"]),
        "evolutions": build_evolution_rows(evolutions_data),
        "types": build_simple_rows(types_data, "type_order", "types", "type_id", "type_symbol", ["tools/godot_smoke/data_registry_types_smoke.gd"]),
        "debug_launchers": DEBUG_LAUNCHER_ROWS,
    }
    stats = build_report_stats(coverage_rows, {
        "species": species_data.get("stats", {}),
        "moves": moves_data.get("stats", {}),
        "abilities": abilities_data.get("stats", {}),
        "items": items_data.get("stats", {}),
        "wild_encounters": wild_data.get("stats", {}),
        "trainers": trainers_data.get("stats", {}),
        "learnsets": learnsets_data.get("stats", {}),
        "natures": natures_data.get("stats", {}),
        "evolutions": evolutions_data.get("stats", {}),
        "types": types_data.get("stats", {}),
        "pokemon_battle_sprites": battle_sprites_data.get("stats", {}),
        "trainer_battle_sprites": trainer_sprites_data.get("stats", {}),
        "battle_environments": battle_environments_data.get("stats", {}),
    })
    return {
        "schema_version": 1,
        "generated_by": "tools/report_battle_parity.py",
        "source_root": to_project_path(source_root),
        "status_values": STATUS_VALUES,
        "unsupported_code_registry": [
            {"code": code, "description": description}
            for code, description in sorted(UNSUPPORTED_CODE_REGISTRY.items())
        ],
        "coverage_rows": coverage_rows,
        "stats": stats,
    }


def build_report_stats(coverage_rows, generated_stats):
    row_counts = {name: len(rows) for name, rows in coverage_rows.items()}
    unsupported_counts = Counter()
    status_counts = Counter()
    for rows in coverage_rows.values():
        for row in rows:
            for key, value in row.items():
                if key.endswith("_status") and isinstance(value, str):
                    status_counts[value] += 1
            for code in row.get("unsupported", []):
                unsupported_counts[code] += 1
    expected_counts = {
        "pokemon_data": int(generated_stats["species"].get("species_count", 0)),
        "moves": int(generated_stats["moves"].get("move_count", 0)),
        "abilities": int(generated_stats["abilities"].get("ability_count", 0)),
        "battle_items": int(generated_stats["items"].get("item_count", 0)),
        "wild_encounters": int(generated_stats["wild_encounters"].get("encounter_record_count", 0)),
        "battle_environments": int(generated_stats["battle_environments"].get("environment_count", 0)),
        "trainers": int(generated_stats["trainers"].get("trainer_count", 0)),
        "trainer_party_mons": int(generated_stats["trainers"].get("party_mon_count", 0)),
        "learnsets": int(generated_stats["learnsets"].get("learnset_count", 0)),
        "natures": int(generated_stats["natures"].get("nature_count", 0)),
        "evolutions": int(generated_stats["evolutions"].get("evolution_entry_count", 0)),
        "types": int(generated_stats["types"].get("type_count", 0)),
        "debug_launchers": len(DEBUG_LAUNCHER_ROWS),
    }
    missing = {
        name: expected_counts[name] - row_counts.get(name, 0)
        for name in expected_counts
        if expected_counts[name] != row_counts.get(name, 0)
    }
    return {
        "coverage_row_counts": row_counts,
        "expected_counts": expected_counts,
        "missing_expected_coverage": missing,
        "total_coverage_rows": sum(row_counts.values()),
        "status_counts": dict(sorted(status_counts.items())),
        "unsupported_entry_count": sum(1 for rows in coverage_rows.values() for row in rows if row.get("unsupported")),
        "unsupported_code_count": len(unsupported_counts),
        "unsupported_counts": dict(sorted(unsupported_counts.items())),
        "missing_registry_codes": sorted(code for code in unsupported_counts if code not in UNSUPPORTED_CODE_REGISTRY),
    }


def build_source_index(project_root, source_root, report):
    source_files = expand_source_files(source_root)
    labels = collect_labels(source_root, ["data/battle_scripts_1.s", "data/battle_scripts_2.s", "data/battle_anim_scripts.s"])
    symbols = {}

    for symbol, source in labels.items():
        add_symbol(symbols, symbol, "asm_label", source)

    for symbol in FIXED_BATTLE_SYMBOLS:
        matches = find_symbol_matches(source_root, source_files, symbol)
        for match in matches:
            add_symbol(symbols, symbol, "source_search", match)

    generated_symbols = generated_symbol_refs(report)
    for symbol, refs in generated_symbols.items():
        for ref in refs:
            add_symbol(symbols, symbol, "generated_data", ref)

    for move_row in report["coverage_rows"]["moves"]:
        script_symbol = move_row.get("battle_script_label", "")
        if script_symbol and script_symbol in labels:
            add_symbol(symbols, script_symbol, "asm_label", labels[script_symbol])
        anim_symbol = move_row.get("battle_anim_script", "")
        if anim_symbol and anim_symbol in labels:
            add_symbol(symbols, anim_symbol, "asm_label", labels[anim_symbol])

    return {
        "schema_version": 1,
        "generated_by": "tools/report_battle_parity.py",
        "source_root": to_project_path(source_root),
        "source_files": [
            {
                "path": path,
                "exists": (source_root / path).exists(),
            }
            for path in source_files
        ],
        "symbol_count": len(symbols),
        "symbols": symbols,
        "stats": {
            "source_file_count": len(source_files),
            "asm_label_count": len(labels),
            "generated_symbol_ref_count": len(generated_symbols),
            "missing_fixed_symbols": sorted(symbol for symbol in FIXED_BATTLE_SYMBOLS if symbol not in symbols),
        },
    }


def build_event_log_schema():
    return {
        "schema_version": 1,
        "generated_by": "tools/report_battle_parity.py",
        "purpose": "Battle parity fixtures compare ordered source-shaped events without depending on presentation nodes.",
        "required_event_fields": [
            "sequence_index",
            "phase",
            "event_type",
            "source_symbol",
            "battler",
            "side",
            "action",
            "message_id",
            "animation_id",
            "hp_delta",
            "pp_delta",
            "wait_frames",
            "rng_rolls",
            "unsupported",
        ],
        "field_definitions": {
            "sequence_index": "Zero-based ordered event index in the fixture log.",
            "phase": "Source-shaped battle phase such as intro, action_select, move_select, turn_action, animation, healthbar, faint, post_battle.",
            "event_type": "Stable event kind: prompt, input, message, stat_change, damage, heal, animation, wait, audio_metadata, state_mutation, unsupported.",
            "source_symbol": "Source C function, ASM label, table symbol, or generated symbol responsible for the event.",
            "battler": "Active battler id/symbol or empty when the event is side/global.",
            "side": "player, opponent, partner, enemy, field, or none.",
            "action": "Selected action or move/item/switch/run command metadata.",
            "message_id": "Battle string id or text symbol, not a final localized text assertion by itself.",
            "animation_id": "Move/general/status/special animation symbol or transition id.",
            "hp_delta": "Signed HP change applied by the event.",
            "pp_delta": "Signed PP change applied by the event.",
            "wait_frames": "Source-intended wait duration when known; null when not yet traced.",
            "rng_rolls": "Ordered RNG calls consumed by the event with source purpose labels.",
            "unsupported": "Array of unsupported/deviation records that remain visible in parity logs.",
        },
        "unsupported_record_fields": ["code", "source", "detail"],
        "status": "schema_only_first_pass",
    }


def expand_source_files(source_root):
    paths = []
    seen = set()
    for pattern in BATTLE_SOURCE_PATTERNS:
        matches = sorted(source_root.glob(pattern))
        if not matches:
            candidate = pattern.replace("\\", "/")
            if candidate not in seen:
                paths.append(candidate)
                seen.add(candidate)
            continue
        for match in matches:
            if match.is_file():
                relative = to_project_path(match.relative_to(source_root))
                if relative not in seen:
                    paths.append(relative)
                    seen.add(relative)
    return paths


def collect_labels(source_root, relative_files):
    labels = {}
    label_pattern = re.compile(r"^([A-Za-z_][A-Za-z0-9_]*):")
    for relative in relative_files:
        path = source_root / relative
        if not path.exists():
            continue
        for line_number, line in enumerate(path.read_text(encoding="utf-8", errors="replace").splitlines(), start=1):
            match = label_pattern.match(line)
            if match:
                labels[match.group(1)] = {"file": relative, "line": line_number}
    return labels


def find_symbol_matches(source_root, source_files, symbol):
    matches = []
    if not symbol:
        return matches
    token = str(symbol)
    for relative in source_files:
        path = source_root / relative
        if not path.exists() or not path.is_file():
            continue
        try:
            lines = path.read_text(encoding="utf-8", errors="replace").splitlines()
        except OSError:
            continue
        for line_number, line in enumerate(lines, start=1):
            if token in line:
                matches.append({"file": relative, "line": line_number})
                break
    return matches


def generated_symbol_refs(report):
    refs = {}
    for section_name in ["moves", "abilities", "trainers", "pokemon_data", "battle_items"]:
        for row in report["coverage_rows"].get(section_name, []):
            symbol = row.get("move_symbol") or row.get("ability_symbol") or row.get("trainer_symbol") or row.get("species_symbol") or row.get("item_symbol")
            source = row.get("source", {})
            if symbol and isinstance(source, dict) and source.get("file"):
                refs.setdefault(symbol, []).append(source)
    return refs


def add_symbol(symbols, symbol, reference_kind, source):
    entry = symbols.setdefault(symbol, {"symbol": symbol, "references": []})
    normalized = {
        "kind": reference_kind,
        "file": to_project_path(source.get("file", "")) if isinstance(source, dict) else "",
        "line": int(source.get("line", 0)) if isinstance(source, dict) and source.get("line") is not None else 0,
    }
    if normalized not in entry["references"]:
        entry["references"].append(normalized)


def main(argv):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--config", type=Path, help="JSON config with source and output roots.")
    parser.add_argument("--source", type=Path, help="pokeemerald-expansion source root.")
    parser.add_argument("--output-root", type=Path, default=Path("data/generated"), help="Generated data output root.")
    args = parser.parse_args(argv)

    config = load_json(args.config) if args.config is not None else {}
    source_root = args.source or Path(config.get("source_root", ""))
    output_root = Path(config.get("generated_data_root", args.output_root))
    project_root = Path.cwd()

    if not source_root.exists():
        print(json.dumps({"error": "source_root_missing", "source_root": to_project_path(source_root)}, ensure_ascii=False, indent=2))
        return 1

    report = build_report(project_root, source_root)
    source_index = build_source_index(project_root, source_root, report)

    report_path = output_root / "reports" / "battle_parity_report.json"
    source_index_path = output_root / "battle" / "source_index.json"
    event_log_schema_path = output_root / "battle" / "event_log_schema.json"
    write_json(report_path, report)
    write_json(source_index_path, source_index)
    write_json(event_log_schema_path, build_event_log_schema())

    summary = {
        "report": to_project_path(report_path),
        "source_index": to_project_path(source_index_path),
        "event_log_schema": to_project_path(event_log_schema_path),
        "coverage_rows": report["stats"]["coverage_row_counts"],
        "total_coverage_rows": report["stats"]["total_coverage_rows"],
        "missing_expected_coverage": report["stats"]["missing_expected_coverage"],
        "source_symbol_count": source_index["symbol_count"],
        "missing_fixed_symbols": source_index["stats"]["missing_fixed_symbols"],
    }
    print(json.dumps(summary, ensure_ascii=False, indent=2))
    return 0 if not report["stats"]["missing_expected_coverage"] and not source_index["stats"]["missing_fixed_symbols"] else 1


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
