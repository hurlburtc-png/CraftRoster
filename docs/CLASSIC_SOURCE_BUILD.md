# Catalogue-wide Classic sources

Classic locations are shown by default when an exact matching recipe has no confirmed Forever acquisition record. The main pane includes an eligible NPC's full name and title, zone and coordinates; source details contain every bundled eligible vendor/trainer alternative. Trainers include recipe skill, character level when recorded, and additional prerequisites. Alliance/Horde trainers and vendors are filtered for the player's faction; neutral NPCs remain available. Missing faction information cannot authorize a trainer listing.

`scripts/build_classic_sources.py` enumerates **every recipe in the installed ProfessionDB catalogue**, then joins exact spell IDs to Classic training spells, trainer templates, teaching items, vendors, loot reference pools, quest rewards and Questie NPC locations. Teaching-item recipes retain an exact item-ID guard. Forever-added teaching scrolls for an unchanged Classic trainer spell can show that spell's Classic trainer, explicitly as a Classic reference. There is no name-based or fuzzy matching and no transplantation of a Classic vendor to a different Forever teaching item.

The generated `data/classic-source-coverage.json` accounts for every catalogue entry, including uncovered entries. `ClassicSourceData.lua` shares NPC records and expands source data only when a recipe is requested. No network requests, all-catalogue scans or SQL processing run in the game. Full vendor/trainer lists are retained; very large world-drop pools retain up to 24 locatable examples with the full candidate count. Drop probabilities are not derived from emulator loot weights. Previously reviewed individual drop-rate references remain separate.

## Rebuild

Download these immutable input snapshots into one directory, using the local filenames shown:

* `classic.sql.gz`: [CMaNGOS Classic-DB 77b848e… Full_DB/ClassicDB_1_12_1_z2815.sql.gz](https://github.com/cmangos/classic-db/blob/77b848e78fe31bdd0c5562922be49a4e8e5e79df/Full_DB/ClassicDB_1_12_1_z2815.sql.gz)
* `classicNpcDB.lua`: [QuestieDB Classic NPC data](https://github.com/Questie/QuestieDB/blob/1f538335cfbb240c14a97c340f48c555fdc8a52b/data/Classic/classicNpcDB.lua)
* `classicItemDB.lua`: [QuestieDB Classic item data](https://github.com/Questie/QuestieDB/blob/1f538335cfbb240c14a97c340f48c555fdc8a52b/data/Classic/classicItemDB.lua)
* `instanceIdToAreaId.lua`: [QuestieDB instance-to-area mapping](https://github.com/Questie/QuestieDB/blob/1f538335cfbb240c14a97c340f48c555fdc8a52b/support/Zones/instanceIdToAreaId.lua)
* `zones.lua`: [QuestieDB zone enum](https://github.com/Questie/QuestieDB/blob/1f538335cfbb240c14a97c340f48c555fdc8a52b/src/corrections/enum/zones.lua)

Run `python scripts/build_classic_sources.py /path/to/snapshots` with Lupa installed. Input SHA256 hashes are checked against the reviewed pins before parsing and recorded in the coverage report. The SQL is parsed as data, not run against a database. Questie literal tables are loaded in an offline Lua runtime. The final addon contains neither the SQL dump nor the full Questie databases. Regenerate the report and data together, review the coverage difference, run the tests and rebuild the install ZIP.

## Accuracy limits

These are **Classic reference locations**, not confirmed Forever stock or trainer availability. They never silently replace a confirmed Forever source and cannot create confirmed Forever navigation records. A new Forever spell with no exact Classic counterpart stays unmatched; a similar name is not evidence. A Classic record without a locatable NPC is reported as a gap. Hidden/unobtainable catalogue entries are recorded separately in each report row. Quest requirements and vendor stock may still differ in Forever.

Trainer titles and geographic facts are drawn from the cited databases. A record saying “additional Classic trainer condition” has an upstream condition that is not interpreted by this importer; it is shown as a prerequisite warning rather than a promise of immediate eligibility. Boss and instance drops omit coordinates and coordinate-unknown messages: the NPC and instance are sufficient. No outdoor entrance is inferred. Open-world mob coordinates are spawn examples, not fixed guarantees.

## Attribution and source distribution

The generated factual acquisition dataset draws on QuestieDB and CMaNGOS Classic-DB (GPL-2.0-or-later). Our generated dataset and transformation are provided under GPL-3.0. QuestieDB has a mixed historic licensing notice and its team permits reuse under GPLv3; that full notice is preserved, rather than asserting every historic contribution has a uniform licence. Their notices and licence texts are included under `vendor/ClassicSources`. Source snapshots are linked above; the complete transformation script, generated data and coverage report are provided in this repository. Existing hand-reviewed Classic entries retain their original per-record providers.
