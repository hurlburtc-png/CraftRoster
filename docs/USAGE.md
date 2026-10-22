# CraftRoster usage and development notes

## Appearance

Open `/cr settings` and use **Appearance** to choose Classic Gold, Frost Blue,
Emerald, Arcane Violet or High Contrast. Colours update immediately and save
between sessions. Item-quality colours, class colours and material readiness
indicators retain their in-game meaning.

Enable **Use custom addon scale** to resize CraftRoster windows from 75–150% of
your current WoW UI scale, in 5% steps. This applies to the directory, shopping
list, whisper composer, work orders, settings and bug-report window. Large
windows automatically fit the screen; your preferred scale is remembered for
larger displays. The minimap button and Blizzard windows keep their normal scale.
**Reset appearance** restores Classic Gold and the default scale.

New directory windows open at 1000 × 680. Existing saved sizes are retained;
`/cr reset` applies the new default size. Narrow windows stack the recipe and
materials; wider windows show them side by side. Recipe, materials, sources and
crafters share one scroll area, with request actions kept at the bottom.

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
- **Auto-load items** — uncheck beside the request buttons to place trade/mail materials manually. The choice is saved, takes effect on pending requests, and leaves whisper and mail text preparation available. Nothing is traded or mailed merely by standing nearby; you open the relevant window and confirm the trade or mail yourself.
- **Crafts** — type 1–999 recipe executions, or click the up/down arrows to change the number by one (starting at 1). Material requirements, shopping totals, whisper links/quantities, and mail drafts scale together. Recipes that produce multiple items still count as one execution. Prepared mail/trade requests retain their original quantity.
- **Shopping List** — pin the selected recipe in a small independent material tracker.
- **Whisper** — open a movable composer with item links and editable request text. Click a known crafter in the main window, or the composer's Send button, to send the first line and arm its material request. Long requests use one explicit **Send next** click per remaining line. Opening or closing the composer alone never sends a request. Use **Select text to copy** for someone outside the guild; the edit box contains the full text. If direct sending is unavailable, the native chat draft opens instead. Changing the Crafts quantity requires reviewing refreshed text before sending.
- **Mail** — prepare mail to the selected full character-realm name, with an `<item> craft requested` subject, the requested item and full material quantities in the body, and your material share as attachments. Fields fill when the mailbox opens, or immediately if already open. Without a selected crafter, enter their full name in the dialog. Mail is never sent automatically.

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

Current candidate: **0.8.0-beta.8**. See [TESTING.md](../TESTING.md) for readiness,
known limits and the in-game acceptance checklist.

Install Python 3.12 and run:

```sh
python -m pip install -r tests/requirements.txt
python scripts/package_addon.py CraftRoster.zip
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
required quality in-game before arming auto-fill. Ordinary recipe sync shares
ownership, names and professions. The new details protocol separately requests a selected known crafter’s complete required-material list from their local scan when local material data is missing; see below.

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
8 mocked UI objects at addon startup, 60 on first directory open, and only 4
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

With the Auction House open, left-click a material to fill its native search field.
Submit the search yourself.

Select the crafter before opening the list, then right-click a material to enter how many
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


## Material delivery across multiple trades

Auto-load fills up to six outgoing trade slots when you manually open a trade
with the selected crafter. It never accepts the trade. Further windows contain
only materials still outstanding after confirmed deliveries. `/crtrade` shows
confirmed delivered and remaining quantities for the latest material request.

Only the game's explicit trade-success event credits materials, using a snapshot
of the actual outgoing item IDs and quantities. Manual changes are included.
A successful material trade does not mark the craft complete. Cancelled trades
leave the outstanding quantities unchanged. Full bags, locked stacks, occupied
slots, missing split APIs and cursor problems do not count as deliveries.
Correct the problem and reopen the trade when the game confirms cancellation.

If a window closes without a reliable result, loading pauses. `/crtrade` opens a
review prompt: choose **Nothing delivered** only after checking that the last
trade transferred nothing. Otherwise keep loading paused and finish manually.
The addon does not guess the result or automatically retry failed trades.

Delivery progress is saved in request history. Selecting the same recipe and
crafter resumes a request with outstanding materials instead of creating a fresh
full-material request. Reloading during an unresolved trade leaves that request
paused for review. An armed trade's quantity and material shares stay fixed;
changing the quantity field affects future requests, not its delivery ledger.

Recipient bag capacity is not available to the addon. The game's trade error is
shown; free space or reduce the offered stacks before accepting again. In-game
Forever validation is still required for event ordering and inventory APIs.


## Crafter work orders

Open **Work Orders** at the bottom of the directory, or use `/cr orders` or
`/crorders`. Outstanding requests are stored separately from the short request
history and survive reloads. Each shows its customer, recipe, number of crafts,
progress and Accept/Decline controls. Completing one order leaves the rest open.

Incoming CraftRoster addon requests are added automatically. Recognizable
CraftRoster craft whispers are also captured when the recipe is known locally;
the addon request and its matching whisper are merged. Ordinary conversational
whispers are not guessed: select the recipe and Crafts quantity in the directory,
then use **Add selected recipe order** and enter the customer's Name-Realm.

Opening a trade with a customer automatically opens their outstanding orders.
Every selected row retains its own **Craft 1** or **Enchant** button. You may
choose gloves before chest, or any other order; there is no forced queue sequence.
Uncheck rows to disable their crafting buttons. **Show all customers** restores
the whole list, but crafting for another customer is blocked during a trade.

Ordinary items offer **Craft 1**, an editable number with **Craft number**, and
**Craft remaining**. Batch counts cannot exceed the order's outstanding crafts.
Enchants remain one application at a time. If the profession data
is not available, the button opens the correct profession where supported; click
the same order again once it has loaded. Legacy clients re-find the recipe by its
spell ID on every click, so reordering the native recipe list cannot change the
requested craft. Missing APIs, unlearned recipes, combat, active casting, linked
professions, and an existing targeting cursor block or defer the action.

For enchants, click the row's **Enchant** button and then select the customer's
correct item in the trade window using normal game targeting. Inspect the item
and enchant before accepting. A craft click never accepts the trade, chooses an
item automatically or marks the order complete. After verifying the result,
**+1 done** advances a single result. After a batch, **Confirm batch** asks how
many actually succeeded; edit that number if a batch stopped early. Failed or
interrupted casts and unaccepted enchants are never silently marked complete.

The queue retains up to 500 orders per character, pruning closed history first.
When all 500 are outstanding, adding more is refused with a message. Old open
orders are never silently removed. Guild status sync may be unavailable when
addon chat is restricted; local orders, manual entry and craft buttons still work.


### Logout, other characters and mail

Orders persist through normal logout/reload and return when that character logs
in again. **All characters** shows orders assigned to your other characters;
those rows are read-only until you switch to that character. Queues use the same
account's local addon SavedVariables, not a server service or cross-computer sync.
A hard crash/disconnect before WoW saves can lose changes since the last save.

CraftRoster-formatted crafting mail is imported when you open/read it. It becomes
a normal order with the same single/batch crafting controls, once the recipe is
known to the active crafter. Ordinary or ambiguous mail requires manual order
entry. Reopening a message does not add another order. Without a native mail ID,
messages with identical sender, subject and body count as one receipt; use
**Add selected recipe order** for an intentional identical second order.
Receipt history is limited to 1,000 entries and 1 MiB of retained signatures per
character; further mail orders require manual addition. The addon never scans
unopened mail, takes attachments or money, or sends mail on your behalf.

Material delivery history is retained while transfers remain outstanding even
when the short request log exceeds its normal 50-entry target. Each character
can have up to 100 open material transfers. Switching characters cannot resume
another character's deliveries. An incompatible new quantity requires choosing
whether to resume the old transfer or replace the old request. Replacement ends
the prior order; already-delivered materials remain recorded and are not returned.
Existing outgoing mail text, attachments, money and COD are preserved: clear or
send that draft before preparing a different craft request. Partial/unconfirmed
trade delivery cannot be bypassed by auto-mailing the full requirements again.


## Recipe links and window spacing

Search rows offer separate **Recipe** and **Craft** links. Hover either to inspect
its native tooltip; click to open it, Shift-click to insert it into chat, or
right-click for a selectable copy box. Chat insertion opens a draft and never
sends a message. Recipe scroll/book IDs are kept separate from crafted output IDs.
Trainer-only recipes and enchant effects use their actual spell when no item is
available. The selected source-details panel also includes the finished item.

Drag the visible bottom-right corner grip to resize the main directory. Drag a
border or the title area to move it. Minimum size is 620×420. Buttons and rows
keep fixed spacing; the result/detail columns and scrolling areas expand, long
labels truncate with tooltips, and source descriptions wrap/scroll. The corner
resize grip is separate from the move regions and never covers action buttons.
Size and position are saved; `/cr reset` restores the default window.

## Member notes

Use **My guild note** on Players to publish a note about your current character's
crafting availability (up to 240 UTF-8 bytes). It syncs with other updated clients
through Refresh. Right-click a player row to edit a private note, saved only on
this account. Both notes appear in the player tooltip; the public note also
appears alongside profession information. Clearing your public note shares the
empty value, removing the previous text from connected clients.

## Material details from guild crafters

Selecting a known crafter requests their scanned required-material list when no
local scan is present. The responder must have scanned that recipe on that
character with this version; merely knowing the spell or having cached another
player's list is insufficient. Reopen/scan the profession once after upgrading.
The message carries reagent names, quantities, item IDs where available, output
item ID and profession ID. Your own scan always takes precedence. A peer list
refreshes after five minutes when selected again. Missing or unavailable data
continues to use the bundled catalogue, or displays as unavailable.

Details are paced, capped and targeted by character on the guild addon channel;
they are not private transport. Older clients still receive the ordinary recipe
ownership sync and ignore the new detail messages. Disabling CraftRoster stops
sends/receives. Failed transfers can be retried with Refresh and reselection;
no incomplete list replaces a previous complete one.

## Acquisition-source coverage

Client source text and bundled source examples can now appear together. The
source panel reports the true source total even when the database ships only 12
examples, with an explicit number of additional sources. Unnamed entries stay
visible as unavailable names. Auto-taught recipes and required skill are shown
where supported. Source names from the bundled database are English; borrowed
Vanilla data and emulator-derived data are labeled. No percentage is invented
for recipes without an existing reference estimate.
