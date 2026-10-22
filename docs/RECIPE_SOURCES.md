# Recipe sources and accuracy

The acquisition pane links the **teaching recipe item**, not the crafted output.
Binding comes from the client’s item API when loaded. A reference fallback is
explicitly marked; an unmapped item has unknown binding.

## Coverage

### Forever vendor additions

The pinned ProfessionDB payload maps Moonglow Boots (spell **1255143**, teaching
item **252764**) but has no acquisition record for it. This caused the screenshot's
"Source unknown" result. It is a new Forever recipe, distinct from Moonglow Vest
(spell 8322, pattern 6710); older quest sources must not be carried over by name.

CraftRoster supplements the missing vendor record with AllTheThings' own Forever
data at revision `d5741058c49a767660f894aa434f3246cd57485b`: Granny Finespindle,
Ironforge **39.3, 33.7**, **Alliance**. The same vendor entry lists pattern items
252761, 252762, 252832, 252764, 252763, 252826, 252830, 252831, 252827, 252828 and
252829; these exact teaching-item IDs share the acquisition reference. Vendor
stock remains subject to beta changes. No drop percentage is inferred.

- [Vendor entry](https://github.com/ATTWoWAddon/AllTheThings/blob/d5741058c49a767660f894aa434f3246cd57485b/.contrib/.db/forever/zones/eastern%20kingdoms/1%20-%20ironforge.lua)
- [Recipe mapping](https://github.com/ATTWoWAddon/AllTheThings/blob/d5741058c49a767660f894aa434f3246cd57485b/.contrib/.db/forever/profession%20db/leatherworking.lua)

Location information is displayed directly below the recipe link, beside materials
on wide windows and above them on narrow windows. Expanding "Where to get it"
shows the complete acquisition/binding description. Native item and pattern
tooltips remain available on their icons and links.

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


## Coordinate records and navigation (beta 19)

`RecipeLocations.lua` stores location records separately from the library's NPC
names. A record must match an exact craft spell or teaching-item ID and provide
an NPC ID, acquisition kind (`vendor`, `trainer`, `mob`), zone and numeric
coordinates from 0 to 100. Mob positions describe spawn points/areas, not a
promise that a creature is currently standing there. Multiple locations remain
separate; coordinates are never inferred from NPC names or copied from another
recipe with a similar name.

A location becomes navigable only after its status is explicitly `confirmed`
and its evidence URL, immutable revision and review date (`checked`, YYYY-MM-DD)
are recorded. Reviewers must confirm the recipe-to-NPC relationship AND the
NPC-to-zone/coordinate relationship for Forever, including faction, stock,
reputation, quest and other requirements. A Forever folder name alone is not
confirmation. Conflicting, borrowed, incomplete or changed evidence stays a
reference pending review. There are currently **no confirmed coordinate
records** in the bundle. Granny Finespindle remains an ATT reference; beta 19
does not silently approve it. The existing source-name catalogue remains
available even when coordinates are unknown.

Confirmed records offer a selectable copy popup. Records with a reviewed
`uiMapID` produce `/way #mapID x y NPC` for modern compatible TomTom versions;
otherwise the popup supplies plain zone, coordinates and NPC text for manual
entry into the user's coordinate addon. Clipboard access is user-driven Ctrl+C.
No command is executed automatically and no chat is sent.

On a click, navigation checks API availability: modern TomTom with a known
client map ID, the native user-waypoint API when supported, or legacy TomTom's
own zone-to-continent/index resolver. Numeric modern map IDs are never passed
to the legacy API. Invalid/unresolved maps and API errors fail safely. TomTom
markers are temporary (`persistent=false`). Native markers use the player's
single user waypoint. No map hooks, per-frame polling or added map library are
needed. TomTom is optional; no coordinate addon is bundled. Actual Forever
client compatibility still requires in-game testing.

For maintenance, daily source checks are an alert, not an import. Review only
changed source files and the records that cite them. Recheck affected confirmed
records, downgrade uncertain records, record the evidence revision/date, run
location tests and rebuild the ZIP. Ship approved changes in normal releases,
or a correction release for a material error. The addon never auto-promotes a
source's new coordinates to confirmed.


### Trainer requirements and faction filtering

Trainer coordinate records also require an explicit profession, numeric
`requiredSkill` for this exact recipe, and reviewed `faction` (`Alliance`,
`Horde`, or `Neutral`, meaning available to both). Only confirmed trainers
matching the current character's faction or neutral trainers are displayed.
Skill is shown per trainer as `Requires <profession> <skill>`; a general trainer
skill cap is not a recipe's training requirement. Low-skill characters can see
what they need to reach. Additional prerequisites remain visible.

Unclassified, opposing-faction, unconfirmed or skill-unknown trainers are
withheld. The bundled library's unclassified trainer names and totals are not
shown as eligible options. Opaque source text is also withheld for identified
trainer recipes because its embedded trainer names cannot be safely filtered.
Other acquisition categories remain visible. A message explains when no
verified eligible trainer is listed; it does not claim that no trainer exists.
Faction checks run again when copying or creating a marker.
