# Database update review

This is an upstream change report. It does not approve locations or replace installed data.

## ProfessionDB

Bundled: **v1.9.1**, file 9095167, client build 1.60.1.69977.
Publisher: **v1.9.1**, [file 9095167](https://www.curseforge.com/wow/addons/libprofessiondb/files/9095167).

If the publisher file differs, review its Forever changelog and import its official ZIP with
`scripts/update_profession_db.py` and an explicitly reviewed SHA-256. A version-only change is not proof of Forever changes.

## AllTheThings Forever

Previous observation: `621afde3b52e30b8435ffa61f49c1e729608aeac`.
New observation: `6df7a9c0c638a11207313eaf5f0a942cbe901d6b`.

Recipe IDs below are catalogue mappings from source text. Conditional/hidden entries still require review.

### Added recipe IDs (0)

None.

### Removed recipe IDs (0)

None.

### Changed teaching-item mappings (0)

None.

### Multiple teaching items requiring review (0)

None.

### Added source files (0)

None.

### Removed source files (0)

None.

### Changed source files (4)

- [`.config/.main.lua`](https://github.com/ATTWoWAddon/AllTheThings/blob/6df7a9c0c638a11207313eaf5f0a942cbe901d6b/.contrib/.db/forever/.config/.main.lua)
- [`promotions/collector's editions.lua`](https://github.com/ATTWoWAddon/AllTheThings/blob/6df7a9c0c638a11207313eaf5f0a942cbe901d6b/.contrib/.db/forever/promotions/collector%27s%20editions.lua)
- [`world drops/world drops.lua`](https://github.com/ATTWoWAddon/AllTheThings/blob/6df7a9c0c638a11207313eaf5f0a942cbe901d6b/.contrib/.db/forever/world%20drops/world%20drops.lua)
- [`zones/kalimdor/1 - orgrimmar.lua`](https://github.com/ATTWoWAddon/AllTheThings/blob/6df7a9c0c638a11207313eaf5f0a942cbe901d6b/.contrib/.db/forever/zones/kalimdor/1%20-%20orgrimmar.lua)

## Required review

- Check exact Forever recipe, teaching-item and NPC IDs; do not join by names.
- Review vendor coordinates, faction, reputation, quest and stock conditions in changed files.
- Treat affected location records as needing review; do not automatically promote them to confirmed.
- Changed files can affect materials, locations or conditions even when recipe IDs are unchanged.
- Import approved data, update provenance, rebuild CraftRoster.zip and run addon tests before publishing.
- Merging this report acknowledges a snapshot only. The bundled manifest remains the installed-data authority.
