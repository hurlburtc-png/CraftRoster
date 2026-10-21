# Recipe sources and accuracy

The acquisition pane links the **teaching recipe item**, not the crafted output.
Binding comes from the client’s item API when loaded. A reference fallback is
explicitly marked; an unmapped item has unknown binding.

## Coverage

Four starter entries are searchable even before a local profession scan. They do
not count as learned recipes and are never advertised as the player's crafts.
These are Classic references, **not confirmed Forever loot tables**.

| Craft spell | Teaching item | Reference source | Estimate per kill |
| --- | --- | --- | --- |
| 17635 | 13519 Recipe: Flask of the Titans | General Drakkisath, Upper Blackrock Spire | 4.60% |
| 20034 | 16252 Formula: Enchant Weapon - Crusader | Scarlet Spellbinder, Western Plaguelands | 0.43% |
| 19054 | 15730 Pattern: Red Dragonscale Breastplate | General Drakkisath, Upper Blackrock Spire | 4.95% |
| 23081 | 18657 Schematic: Hyper-Radiant Flame Reflector | Solakar Flamewreath, Upper Blackrock Spire | 8.08% |

Reference pages checked 2026-10-19:

- https://foreverchanges.pro/items/13519
- https://wowclassicdatabase.com/item/formula-enchant-weapon---crusader
- https://www.wowhead.com/classic/item=15730/pattern-red-dragonscale-breastplate
- https://www.wowhead.com/classic/item=18657/schematic-hyper-radiant-flame-reflector

Percentages are approximate reference estimates, not guarantees. Sources may
share underlying data; agreement between sites does not independently confirm a
rate. Beta patches can change loot, requirements and binding. Requirements in
this starter set are Classic references too; the native item tooltip wins.

## Bundled LibProfessionDB

CraftRoster includes the Forever payload from the official **ProfessionDB-v1.9.1**
release (CurseForge file **9095167**). Its client data is built from
**1.60.1.69977**, with later captured trainer corrections; this is older than the
current target build 70450. Updates remain necessary as the beta changes.

Only LibStub, the library engine, and Forever core/localized data are bundled.
The standalone ProfessionDB bootstrap, other game versions, Ace3 and guild
version-check dependencies are omitted. The MIT license and public-domain
LibStub notice are retained. Locale chunks are combined into do/end blocks;
the original chunks retain their bytes, order, local scope and locale guards.

The actual payload contains **2,511 recipes across 10 professions**. The directory imports the full bundled catalogue for offline search. It also
enriches teaching-item mappings and acquisition-source names. Native scans and
guild ownership determine who can actually craft each recipe.
Scanned metadata and guild ownership stay separate from the bundled lookup data.

The importer, pinned archive checksum, per-file hashes, load order and provenance
are recorded in `scripts/update_profession_db.py` and
`vendor/ProfessionDB/manifest.json`. See [database maintenance](DATABASE_UPDATES.md).

Borrowed sources are labeled with their original game version. The library's
source API does not supply drop percentages; absent estimates remain unknown.
No live HTTP requests are made by the addon. Client source text and curated
Classic references are displayed separately when both exist.

For manual checks use [Wowhead Forever recipes](https://www.wowhead.com/forever/items/recipes)
and [Forever Codex](https://forever-codex.com/items/). Read each source's provenance:
Codex explicitly uses Classic cMaNGOS loot data where Forever data is unavailable.
A comprehensive, confirmed Forever rate database is still pending.

## Beta 11 acquisition display

The source panel includes every supported acquisition category (trainer, vendor,
quest, container and creature drop), source totals from the library's `.total`,
up to 12 examples per category and the number omitted by that cap. Entries with
missing names remain visible. Client source text does not suppress the bundled
reference details. Required skill and profession auto-taught recipes are included
when the library supplies them. These changes expand useful coverage beyond the
four percentage references without presenting emulator data as verified live
Forever drop rates. The pinned database provenance and checksums are unchanged.
