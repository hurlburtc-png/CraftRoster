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

## Optional LibProfessionDB support

Install [LibProfessionDB](https://www.curseforge.com/wow/addons/libprofessiondb)
(standalone addon: ProfessionDB) for teaching-item mappings and acquisition-source
names beyond the starter set. CraftRoster only reads a ready **Forever** database,
feature-detects each method, excludes profession rank books and tolerates errors.
It does not download the database or require it to run. It enriches recipes already
in CraftRoster; it does not import the library's entire catalogue.

Borrowed sources are labeled with their original game version. The library's
source API does not supply drop percentages; absent estimates remain unknown.
No live HTTP requests are made by the addon. Client source text and curated
Classic references are displayed separately when both exist.

For manual checks use [Wowhead Forever recipes](https://www.wowhead.com/forever/items/recipes)
and [Forever Codex](https://forever-codex.com/items/). Read each source's provenance:
Codex explicitly uses Classic cMaNGOS loot data where Forever data is unavailable.
A comprehensive, confirmed Forever rate database is still pending.
