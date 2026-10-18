# CraftRoster

Find the right guild crafter for any recipe.

CraftRoster is a lightweight World of Warcraft addon for tracking professions and recipes, with a foundation for a guild-wide recipe directory.

## Installation

Target client: **WoW Forever 1.60.1, build 70450, interface 16001**, as reported
in-game. Beta 2 corrects the Retail interface declaration that caused Forever to
mark the previous package incompatible. Actual UI/API behavior still needs testing
in Forever; matching the manifest removes the loader mismatch only.

1. Go to **Releases** and download the latest **CraftRoster.zip**.
2. Extract the zip.
3. Copy the **CraftRoster** folder into your WoW `Interface\AddOns` folder.
4. Restart WoW, or type `/reload` in-game.

## Commands

- `/cr` — open the directory
- `/craftroster` — alternate command
- `/cr settings` — open settings
- `/cr reset` — reset the directory window position and size
- `/cr shopping` — reopen or close the pinned shopping list
- `/crwhisper` — open the next prepared whisper when a materials list needs multiple messages
- `/cr toggle` — enable or disable CraftRoster
- `/crdiagnostics` — show client build, API availability, and sync status
- `/crrequests` — show recent crafting requests
- `/crstatus <id> <accepted|completed>` — update a request status and sync it to the guild
- `/crfavorites` — list favorite recipes
- `/crdiscord` — print a Discord-ready guild crafting directory

## Actions

- **Update My Recipes** — manually rescan your known recipes.
- **Refresh** — request a guild recipe sync and refresh the directory.
- **Favorite** — toggle a recipe as a favorite; use **Favorites only** to narrow the directory.
- **Crafter rows** — select a guild crafter to address the Whisper Player and Mail Player actions. Selection alone sends nothing.
- **Shopping List** — pin the selected recipe in a small independent material tracker.
- **Whisper Player** — prepare a direct-whisper draft for the selected crafter, including the recipe and bracketed materials/quantities. Press Enter to send; when material data exists, exact-quantity trade auto-fill is also armed.
- **Mail Player** — prepare mail to the selected full character-realm name, with a `CraftRoster: <recipe>` subject and your material share. Fields fill when the mailbox opens, or immediately if already open. Without a selected crafter, enter their full name in the dialog. Mail is never sent automatically.

## Window controls

- Drag the title bar to move the directory.
- Drag the bottom-right corner to resize it.
- Position and size are saved automatically.
- Minimum size is 620 x 420.
- Use `/cr reset` or **Reset Window Position** in settings to restore the default centered 760 x 500 layout.

## Directory

- **Professions:** search recipes, filter by profession, and see who can craft a selected recipe.
- **Players:** search characters and view race/gender icons, class-colored names, and recipe counts.
- **My Recipes:** view your saved recipes and manually update them.

## Performance

- The directory and settings frames are created on first use.
- Lists render only the viewport and reuse rows while scrolling (up to 128 rows per list).
- Recipe event bursts are coalesced into a scan after 0.25 seconds when timers are available.
- Unchanged scans retain saved material tables and cached indexes.
- Only the active directory tab refreshes; repeated data changes share one pending refresh.
- Guild snapshots are serialized once per data change, and unchanged automatic sends are suppressed.
- Throttled recipe changes queue a one-shot retry on timer-capable clients.
- Material auto-fill walks inventory once and aggregates duplicate reagent requirements.
- The recipe index is cached and rebuilt only when recipe data changes.
- The directory does not refresh while hidden.
- Newly learned recipes are captured automatically through `NEW_RECIPE_LEARNED`.

## Development checks

Current candidate: **0.8.0-beta.4**. See [TESTING.md](TESTING.md) for readiness,
known limits and the in-game acceptance checklist.

Install Python 3.12 and run:

```sh
python -m pip install -r tests/requirements.txt
python -m unittest discover -s tests -v
```

The suite runs the addon in Lua 5.1 and LuaJIT 2.1 through Lupa, with modern,
legacy, and minimal WoW API mocks. It checks startup, recipe imports, directory
selection, sync validation and chunk reassembly, request status routing, and exact
material quantities. Missing-API scenarios are explicitly skipped where the
feature cannot run. These are simulated API checks, not certification of a WoW
version. Release packaging runs the suite before creating the archive.

Guild sync shares recipe names and professions as well as learned recipe IDs.
Large snapshots use paced chunks with a 60-second receive timeout, up to 256
chunks and eight concurrent senders. Clients without `C_Timer.NewTimer` can send
small snapshots only; both peers need this version to exchange chunked snapshots
and incoming craft requests. A request appears in the selected crafter's
`/crrequests` list, where `/crstatus` can accept or complete it.

Material auto-fill uses saved quantities and skips locked stacks and occupied
attachment slots. It stops when the client lacks exact stack-splitting or cursor
APIs. It never accepts a trade or sends mail. Optional reagent slots are skipped when the client marks them optional, and
incomplete cached schematics preserve the last complete materials. For recipes
with alternative reagent qualities, scanning records the first listed alternative per slot; confirm the
required quality in-game before arming auto-fill. Synced recipe names do not
include material schematics: scan locally before using material actions.

Before release, test in the target client: `/cr`, `/cr settings`, fresh and saved
window layouts, scanning each profession, guild sync with two characters, request
accept/completion, and trade/mail attachments with partial stacks. Verify protected
API restrictions and template availability in that client. Confirm quantities and
recipients before manually accepting a trade or sending mail.

Run the mock performance workload separately:

```sh
python tests/benchmark.py
```

With 5,000 recipes and 105,000 crafter-recipe links, both tested runtimes created
8 mocked UI objects at addon startup, 55 on first directory open, and only 4
additional objects across 100 scroll operations. A 20-event recipe burst produced
one scan. These counts include mocked frames/textures and use a small simulated
viewport; they are regression evidence, not in-game memory or FPS measurements.
No persistent update loop is added; the minimap drag handler runs only while dragging.

## Persistent shopping list

Select a recipe and click **Shopping List**. The small draggable panel stays open
when the directory closes, shows bag quantities and missing amounts, and refreshes
on bag events without polling. Its corner X closes it and stops its event updates.
`/cr shopping` reopens the pinned recipe. Recipe, position and visibility are saved
per character, including across reloads. Material rows are reused when scrolling.
Recipes with no local material details show a waiting message rather than guessed
quantities; bank and account-bank contents are excluded from available counts.

Select the crafter before opening the list, then click a material to enter how many
that crafter agreed to provide. Your shopping requirement and trade/mail auto-fill
use the remaining share. Contributions are saved separately for each recipe and
crafter; setting zero restores your full requirement. The whisper draft includes
the full recipe quantities and explains your share versus the crafter's share.
These amounts reflect your agreement, not a scan of the other character's bags.

## Trade outcomes and partial materials

The addon never opens or accepts a trade, sends mail, or crafts an item itself.
Opening a trade with the armed crafter offers only the available part of your
agreed material share. A partial offer does not complete a request. Review the
quantities and confirm the trade manually.

A closed window alone is recorded as unconfirmed; recognized cancellation and
success notifications update the material-transfer status in `/crrequests`.
An unsuccessful or unconfirmed close leaves auto-fill armed for a retry with the
same crafter, using fresh quantities. A recognized successful trade disarms it.
The auto-fill cancel button explicitly disarms the request. Returned items are
recounted through bag events, so a cancelled trade does not consume shopping-list
inventory. The list tracks current bag contents, not a delivery ledger.

Trade success confirms the exchange only. It never automatically marks the craft
complete: after receiving the crafted item, use `/crstatus <id> completed`.
Clients without a recognized trade-success notification retain an unconfirmed
status instead of assuming success. Validate actual trade event ordering in-game.

## Copying Lua bug reports

Use `/cr bug` (or `/cr errors`), or click the beetle in `/cr settings`. The popup
selects a scrollable report for **Ctrl+C** (**Cmd+C** on Mac). Paste it into your
bug report and add what you clicked, what you expected, and what happened.

Reports include addon version, client/build/interface, up to ten recent distinct
CraftRoster errors, available stack traces, repeat counts and first/last occurrence
timestamps. Error history survives reloads; startup errors before SavedVariables
initialization are merged with saved history. Repeated messages reuse the stored
stack and capture notices are throttled. The original Lua error handler still runs.
No report is uploaded or sent automatically. Errors before this addon's reporter
loads, unrelated addon errors, and errors swallowed by other handlers may not appear.
