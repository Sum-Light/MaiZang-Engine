# Decisions

## 2026-07-03 - Data-driven Godot rebuild

Decision: Treat `pokeemerald-expansion` as source data and behavioral reference, and rebuild runtime systems in Godot 4.7.

Reason: The source project is a GBA ROM hack base with C engine code, assembly, custom build tools, binary map/tile formats, and GBA-specific runtime assumptions. A direct compile-style port would couple Godot to the old platform model. A data-driven rebuild gives cleaner Godot architecture and allows incremental playable milestones.

## 2026-07-03 - Wiki and skill first

Decision: Establish a project wiki and Codex skill before implementing gameplay systems.

Reason: The port will span many sessions and many source formats. Durable project memory reduces rediscovery and lets future Q&A update the same shared facts, decisions, and roadmap.

## 2026-07-03 - Encoding-safe tooling and commits

Decision: Minimize PowerShell for script-like file processing and maintain the Godot project as a git repository with focused commits after completed changes.

Reason: The source project and future wiki/import outputs may contain Chinese text and custom encodings. Avoiding casual shell rewrites reduces encoding damage. Frequent commits make the port easier to review, bisect, and roll forward safely.

## 2026-07-03 - Preserve unpacked map-grid layers

Decision: Generated map JSON keeps both the original raw u16 map-grid values and unpacked metatile id, collision, and elevation grids.

Reason: The source `map.bin` does not store plain metatile ids. `include/global.fieldmap.h` defines each entry as 10 bits of metatile id, 2 bits of collision, and 4 bits of elevation. Keeping the raw and unpacked forms makes the first debug renderer simple while preserving data needed for later collision and movement behavior.

## 2026-07-03 - Bake palettes into generated images

Decision: Use GBA palette files only during import, then generate ordinary RGBA images for Godot runtime consumption.

Reason: Palette slots are a GBA hardware/runtime constraint. Godot does not need a runtime palette bank model for the first map renderer, and palette-baked textures are simpler to load, preview, export, and debug. The importer should still record enough source metadata to revisit special cases such as animated doors or layer splitting.

## 2026-07-03 - Use Porymap as a source-format reference

Decision: Treat Porymap as a reference for pokeemerald map, tileset, palette, and metatile editor semantics, not as an architecture model to copy into Godot.

Reason: Porymap is built to edit decomp project data in a Qt desktop workflow. The Godot port needs generated runtime assets and Godot-native systems, but Porymap's handling of source project context is useful for validating importer assumptions.

## 2026-07-04 - Centralize current-map queries in MapRuntime

Decision: Use a `MapRuntime` autoload as the first current-map query service for passability, bounds, collision, elevation, metatile ids, behavior, and layer type.

Reason: Player movement, NPC movement, event triggers, object interaction, warps, and future terrain effects all need the same map facts. Centralizing those queries keeps generated JSON parsing out of presentation scripts and lets richer movement rules grow without coupling them to `PlayerController`.

## 2026-07-04 - Use object-event placeholders before sprite import

Decision: Spawn generated `object_events` as lightweight placeholder nodes and use `MapRuntime` to make visible object-event cells block movement.

Reason: The first vertical slice needs map occupancy and event positions before the full overworld sprite pipeline is ready. Placeholders make source object data visible and testable without inventing final art or coupling movement to presentation nodes.

## 2026-07-04 - Add debug event dispatch before ScriptVM

Decision: Route `ui_accept` interaction through player facing direction, `MapRuntime.get_interaction_target`, and `EventManager` debug dialogue before implementing full event script parsing.

Reason: The vertical slice needs a testable object/sign/warp interaction path now, while real `.inc` script execution and text decoding require separate import work. A debug dispatcher keeps the boundary stable without pretending script semantics are already implemented.

## 2026-07-04 - Derive gameplay behavior from source C and resources

Decision: Implement Godot event script and gameplay behavior only after tracing the corresponding source C implementation and referenced resources. Treat GBA hardware graphics constraints as import-time decoding concerns instead of runtime architecture requirements.

Reason: Event scripts and gameplay systems encode behavior through engine commands, flags, vars, movement tables, text labels, object graphics, sounds, doors, field effects, warps, Pokemon data, item data, encounters, trainers, and battle rules. Guessing behavior from names would drift from the original project. Tracing source behavior first lets the Godot port remain modern internally while matching the source game's visible behavior and rules more closely. Palette banks, 4bpp tiles, binary metatiles, and packed map blocks exist because of GBA constraints and should be decoded into Godot-friendly assets/data rather than recreated as runtime limitations.

## 2026-07-04 - Generate script data before full ScriptVM

Decision: Convert map `scripts.inc` files into generated script JSON and use it for limited debug dialogue previews before implementing the full `ScriptVM`.

Reason: Script labels, text labels, movement labels, and instruction references are needed by interaction dispatch before complete opcode semantics exist. A generated data layer makes script references inspectable and testable while keeping real execution deferred until each command is traced to source C behavior and its referenced resources.

## 2026-07-04 - Start ScriptVM with the traced dialogue path

Decision: Introduce `ScriptVM` as an autoload and route object/BG dialogue interactions through it, starting with source-derived `msgbox` expansion and synchronous dialogue-result execution.

Reason: `msgbox` in the source is a macro that loads a text pointer and calls a standard script from `gStdScripts`. Implementing that path in the VM preserves the real script structure better than keeping ad hoc EventManager previews. The first implementation records wait/lock/facing effects instead of pretending object freezing, facing animation, and asynchronous UI continuation already exist.
