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
