# Forever recipe verification gate

Goal: verify every CraftRoster catalogue recipe against **Forever-specific evidence**, without converting Classic fallback information into false Forever claims.

## Source priority
1. WoW Forever client-derived profession data (spell ID, output item ID, reagent IDs/counts, tools, skill thresholds). Reference: https://endgametools.com/en/wow-forever/professions — build 1.60.1.70532 as of 2026-10-23.
2. Wowhead Forever recipe item, spell, NPC, quest and profession pages: https://www.wowhead.com/forever/items/recipes ; https://www.wowhead.com/forever/database .
3. Verified in-game Forever observations for acquisition, faction, stock, NPC position and drop evidence.
4. Classic DB/Questie only as explicitly labelled fallback.

## Reconciliation
- Enumerate every local recipe spell ID and output ID; retain duplicate names with distinct IDs/versions.
- Join on exact IDs, not fuzzy names. Distinguish crafting spells from recipe-teaching items; do not equate counts between them.
- Compare profession, skill thresholds, crafted item, output quantity, reagents, tools, and acquisition independently.
- Record per-field evidence URL, source version/date and status: verified_forever / classic_reference / conflicting / unknown / unobtainable.
- For trainers/vendors verify name, rank, zone, coordinates, faction and availability; never infer coordinates.
- For drops verify NPC/instance separately from drop probability. No probabilities from loot weights.
- Output a row for **every** local recipe including missing or conflicting evidence, plus a summary by profession.
- Review discrepancies manually before updating bundled data; run automated tests and ZIP validation after changes.
- Do not mark a recipe fully verified if its acquisition is unknown; distinguish client-verified craft data from server-verified acquisition.

## Current baseline (not a verification result)
Existing catalogue: 2,510 entries. Classic detailed acquisition references: 1,135; insufficient evidence: 118; no exact Classic counterpart: 1,257. These are **Classic coverage categories**, not Forever verification results.

## Release acceptance
A release report must include total catalogue entries, exact Forever ID matches, client-field mismatches, server-acquisition verification, unknown/conflicting entries, and dated evidence. No 100% claim until every required field is supported. In-game verification remains a separate gate.
