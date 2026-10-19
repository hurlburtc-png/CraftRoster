# CraftRoster independent review request

Please independently audit **https://github.com/hurlburtc-png/CraftRoster** before
I test the addon in WoW Forever. Read the actual current files and install ZIP;
do not rely on earlier assistant descriptions, cached file sizes or old paths.

**Review only. Do not push commits, edit files, restore earlier versions or replace
anything with summaries/placeholders.** Return evidence and proposed fixes first.

## Establish exactly what you reviewed

- Record the branch, full commit SHA, review date, TOC addon version and target
  interface. Pin subsequent reads to that commit. This request accompanies
  **0.8.0-beta.8**, targeting Forever **1.60.1, build 70450, interface 16001**;
  report explicitly if you see an earlier build.
- Addon files are now at the repository root, e.g. `Directory.lua` and
  `GuildSync.lua`. The old repository name was `wow-forever-addons`. A 404 for
  `CraftRoster/Directory.lua` inside this repo is not proof of corruption.
- Read full contents. Check every TOC-listed file exists, Lua syntax is valid,
  module load order is correct, and no code file contains literal placeholder
  prose such as `<full updated ...>`. File size alone cannot establish integrity.
- Extract `CraftRoster.zip`. It must contain one `CraftRoster/` addon folder,
  including its TOC, modules, vendor files, upstream license and manifest. Compare
  every shipped runtime file byte-for-byte with the same commit's source. Flag
  stale/missing/extra files, unsafe paths or differing source/package versions.

## Bundled database and maintenance

- Inspect `vendor/ProfessionDB/manifest.json`, `scripts/update_profession_db.py`,
  the TOC and `scripts/package_addon.py`. Verify the official ProfessionDB v1.9.1
  release, CurseForge file 9095167, archive checksum, vendored file hashes and
  original-member records. Check independently against the actual upstream ZIP
  where possible; describe any retrieval limitation.
- Only LibStub, the library engine and Forever data should be included. Confirm
  other expansions and the standalone guild-version-check bootstrap are omitted,
  and CraftRoster works with no separate ProfessionDB, Ace3 or VersionCheck.
- Verify locale concatenation preserves each original chunk's bytes, order,
  locals and early-return guards. Validate all shipped locales and client
  detection: a different/future interface must not silently receive Forever data.
- Check actual library APIs and returns, readiness, rank-book exclusion,
  duplicate loads and LibStub coexistence. Specifically examine different
  embedding addons/load orders, including equal library MINOR versions carrying
  different data revisions. Do not assume API-version deduplication proves that
  the most recent recipe data wins.
- Confirm upstream license/attribution is retained in the distributable.
  Evaluate `docs/DATABASE_UPDATES.md`: deterministic imports, changed file lists,
  provenance/build recording, review/test gates and rollback. A checksum computed
  locally pins bytes; it is not independent publisher authentication.

## Recipe identity and acquisition accuracy

- Inspect `RecipeSources.lua`, `Recipes.lua`, `Directory.lua` and
  `docs/RECIPE_SOURCES.md`. Distinguish the craft spell, crafted output item and
  **teaching recipe/formula/pattern/schematic item**. Hover and Shift-click should
  use the teaching item when mapped, with an honest fallback when not mapped.
- Binding must describe the teaching item. Prefer current loaded client data;
  missing binding must remain unknown or explicitly qualified as a reference.
  Check API return positions, uncached items, failed loads and refresh behavior.
- Verify these starter records independently: spell 17635 / item 13519 Flask of
  the Titans; 20034 / 16252 Crusader; 19054 / 15730 Red Dragonscale Breastplate;
  23081 / 18657 Hyper-Radiant Flame Reflector. Check NPC, location, profession,
  skill/specialization, binding and displayed estimates (4.60%, 0.43%, 4.95%,
  8.08%). Report disagreements and provenance rather than assuming these are true.
- **None of those percentages is claimed confirmed for Forever.** Check Classic
  estimate labels, borrowed Vanilla flags and missing-data messages. The library
  supplies source names, not percentages. Do not mistake agreement between sites
  using the same underlying data for independent confirmation.
- Verify an unlearned/catalogue entry never becomes a player's known recipe or
  an advertised guild craft. Zero synced owners is not proof the whole guild
  lacks it; offline saved owners must remain known owners.
- The bundled lookup contains 2,511 recipes, but the directory still lists
  scanned/synced recipes plus four starter records. **Full catalogue import into
  search is not implemented.** Verify this boundary is documented accurately.

## Runtime, workflow, UI and performance

- Audit nil/throwing/missing APIs, event arguments, SavedVariables upgrades,
  partial recipe/material cache results, profession scans and disabled behavior.
  Confirm incomplete scans do not erase previously complete materials.
- Inspect guild sync sender validation, chunk batching/deduplication, expiry,
  maximum sizes, throttling, stale snapshots, disabled handling and ownership.
  Check crafted-request/status transitions and recipient validation. Current
  addon request traffic uses GUILD with target filtering; it is not private
  whisper transport. No incoming Accept/Decline popup is claimed implemented.
- Check shopping-list bag counts, shortages, crafter contributions, switching
  recipes/crafters, partial stacks, locked slots, cancellation and trades with
  the wrong person. Whisper drafts must not send automatically; trade acceptance,
  mail sending and crafting remain user actions. Trade close alone is not success.
- Inspect frame anchors, minimum/default/large sizes, text wrapping, scroll
  limits, source pane/action-button separation, tabs, filters, favorites,
  online/offline states, minimap dragging and settings. Exercise actual button
  callbacks; do not claim visual/client validation from source or mocks alone.
- Review startup cost of the actual bundled database, localized file parsing,
  memory growth, repeated refreshes and large guilds. Separate startup/database
  parsing from first-open and scrolling measurements; mock timings are not FPS.
- Compare README, `TESTING.md`, `docs/USAGE.md` and `docs/ROADMAP.md` with code.
  Identify undocumented limitations or any promised feature still absent.

## Validation and report format

If you can execute the repository, install `tests/requirements.txt` and run:

```sh
python -m unittest discover -s tests -v
python tests/benchmark.py
```

Do not rebuild the checked-in ZIP before checking its integrity: that can hide a
stale package. If an isolated rebuild is useful, compare it afterwards. Distinguish
checks you actually executed from source review and proposed in-game tests.

Return findings in severity order (blocker/high/medium/low), each with:

1. File and precise function/line reference at the reviewed SHA.
2. Trigger/reproduction and concrete effect on the player or stored data.
3. Evidence, confidence and classification: confirmed defect, suspected risk,
   missing feature or in-game verification required.
4. A minimal proposed fix and a meaningful regression check.

End with a short assessment of readiness for controlled in-game testing and the
highest-priority test steps. Explicitly state retrieval/execution limitations.
If you find no blocker, say **no blocker found in the checks performed**, not
that the addon is proven error-free. Please do not modify the repository.
