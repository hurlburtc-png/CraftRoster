# CraftRoster 0.8.0-beta.11 test candidate

Status: candidate for controlled in-game testing. Automated API mocks pass; native client compatibility is not yet verified.
Target client reported by the user: Forever **1.60.1, build 70450, interface 16001**.
The TOC now declares 16001; beta 1 declared Retail interface 110200 and was rejected
by Forever's loader. Beta 2 then exposed a missing
`CharacterFrameTabButtonTemplate` on the actual client. Beta 3 uses standard
buttons for the three directory tabs and removes the associated tab-template API
calls. A regression scenario rejects that template and exercises all three tabs.
Further runtime compatibility on Forever still requires a real client run. Lua 5.1/LuaJIT checks use API mocks, not a WoW installation. Record the actual
client/flavor/build/interface with `/crdiagnostics`.
Do not treat the generated mockup images as runtime evidence.

Beta 4 moves tabs inside the footer, gives content explicit window bounds, fixes
bottom anchor directions, reserves scrollbar space, and keeps filters on two rows.
These layout corrections still need visual confirmation on Forever.

Beta 5 includes locally discovered unlearned recipes in search without treating
them as learned. A recipe with zero saved owners shows a scrollable acquisition
pane and clickable recipe tooltip; Shift-click inserts the link into an open
chat edit box. A known but offline owner remains a crafter, even with Online only
enabled. Optional client source APIs may return nothing: that state is explicit.
The current candidate bundles the Forever catalogue; see the later updates below.

Beta 6 preserves complete material lists when required reagent slots are still
loading, tolerates transient schematic API errors, and reads the real schematic's
outputItemID. Filtering a selected offline crafter out now clears that action
target. Refresh requests an updated roster, including on clients using the global
GuildRoster API. An unavailable recipe tooltip has a readable fallback, and hiding
the minimap button stops its drag update handler.

Beta 7 ships teaching-recipe item links, item binding and four starter Classic
source/rate estimates. They are explicitly unconfirmed for Forever. Bundled
LibProfessionDB enriches recipe-item mappings and source names. It does not supply percentages. See
[coverage and provenance](docs/RECIPE_SOURCES.md) and [remaining plans](docs/ROADMAP.md).

Beta 8 bundles the pinned LibProfessionDB v1.9.1 Forever payload and licenses.
Tests load the real 2,511-recipe database in all 12 shipped locales on Lua 5.1
and LuaJIT, reject other client interfaces, verify repeated shared-library loads,
check pinned file hashes and exercise the offline update importer. Ace3 and a
standalone ProfessionDB installation are not required. The current candidate imports the complete bundled catalogue for offline search.

### Recipe-source acceptance checks

1. Open each profession and scan. Check an unlearned recipe appears without
   increasing your learned count or being advertised as your known recipe.
2. Search Red Dragonscale Breastplate, Crusader, Flask of the Titans, and Hyper-Radiant Flame Reflector. Check the actual Pattern/Formula/Recipe/Schematic item tooltip, binding, source and labeled percentage. The pattern binding must describe the scroll, not the crafted armor. Select a recipe with no saved crafter. Check the link/tooltip and Shift-click
   into an open chat draft. Confirm no message is sent automatically.
3. Check a recipe with client source text and one without it. Missing details
   must say Source unknown, and prior source text must survive an incomplete scan.
4. Resize to 620 x 420, 760 x 500 and a larger window. Scroll long source text;
   check the source pane does not cover the action buttons or recipe list.
5. Sync a character who knows the recipe. The source pane should return to the
   crafter list. With Online only checked, offline owners must not be called unknown.

## Automated review

```sh
python -m pip install -r tests/requirements.txt
python scripts/package_addon.py CraftRoster.zip
python -m unittest discover -s tests -v
python tests/benchmark.py
```

The current suite exercises Lua 5.1 and LuaJIT 2.1 with modern, legacy and
minimal API scenarios, plus real bundled-data locale checks. Ten checks are
intentionally skipped for APIs absent from a profile. Record the final test count
from the run rather than using historical counts. ZIP checks verify every packaged
module against the source and that extraction creates one CraftRoster folder.

Performance numbers in [the measured baseline](docs/PERFORMANCE.md) use mock
runtimes, not game FPS or native memory measurements. The main material panel
refreshes on bag changes with a coalesced timer; a hidden directory does no bag work.

Review fixes include reliable whisper addressing; visible results after filtering
or shrinking a scrolled list; reset-before-first-open; preserving search-template
handlers; explicit addon-send failure handling; manual sync publishing the local
snapshot as well as requesting peers; and reporting interrupted chunk sends.

## In-game acceptance run

1. **Install and startup.** Install only the packaged CraftRoster directory. Test
   once with existing SavedVariables and once with a backed-up, clean profile.
   Record any out-of-date/interface warning. Check `/crdiagnostics` and startup
   for Lua errors. Exercise the supported APIs in the actual target client.
2. **Directory and settings.** Open `/cr`, all three tabs, and `/cr settings`.
   Move/resize at minimum, default and large sizes, including a non-default UI
   scale. Reload and verify geometry. Run `/cr reset` before first opening, too.
   Scroll deeply, then search/filter/favorite down to one or zero results.
3. **Recipes.** Open each profession, scan, learn a recipe, and scan unchanged
   data again. Inspect known names, quantities, required/optional slots and
   alternative reagent quality. Linked/guild profession views must not become
   the player's learned recipes. Verify temporarily uncached reagent data.
4. **Guild peers.** Use two characters running this candidate. Check manual
   refresh in both directions, received recipe names, offline/online and
   cross-realm identities, and a realistically large recipe collection. Retry
   after chat restrictions or a reported interrupted transfer.
5. **Whisper and mail.** Open Whisper with and without a selected crafter. Move
   the composer, copy/edit text, inspect its item links and click a known crafter.
   Check one first whisper is sent, with no duplicate on repeated selection.
   Long requests need explicit Send next clicks. Test quantity changes, pending
   old requests and a failed send. When direct chat sending is unavailable, check
   the native draft fallback. Mail must fill the exact selected Name-Realm and
   recipe subject, including an already-open mailbox and a recipe with no data.
   Confirm recipients and attachments manually.
6. **Shopping list.** Pin a recipe, close the directory, acquire/remove materials,
   and verify counts. Drag the list and reload; reopen with `/cr shopping`. Close
   its X and ensure it stays closed after reload. Select a crafter and right-click a
   material to enter their contribution. Left-click a material with the Auction
   House open and confirm that its name fills the search field. Check requirements, whisper wording,
   and trade/mail quantities; switching crafters must not reuse another's share.
7. **Trades.** Test sufficient, partial, locked and missing stacks; an occupied
   cursor; occupied offer slots; the wrong partner; cancellation before/after
   acceptance; an ordinary close; a retry; and successful exchange. The addon
   must never open/accept a trade or complete the craft itself. Verify real
   success/cancel event ordering and corresponding `/crrequests` material status.
   Without a recognized notification, status must remain unconfirmed. Confirm
   returned materials in the shopping list after cancellation.
8. **Craft completion.** Receive the crafted item, then mark the request complete
   manually with `/crstatus <id> completed`. Confirm the peer sees it and that a
   late accepted-status message cannot downgrade it.
9. **Bug report.** Open `/cr bug` (or the beetle in `/cr settings`). Copy with
   Ctrl+C / Cmd+C and paste into a text editor or issue. Confirm the report has
   the candidate version, client build/interface, captured message and stack,
   repeat count and first/last timestamps. It must remain available after
   reload. Test keyboard focus, scrolling, selection and Escape in-game.

## Known limits to include with test feedback

- Protected inventory/chat APIs, template layout, clipboard interaction and real
  trade/mail events require the client; cloud tests cannot certify them.
- Alternative reagent slots currently choose the first listed alternative.
  Confirm quality before using auto-fill. Material schematics are scanned
  locally; guild sync shares recipe IDs/names/professions, not schematics.
- One snapshot is bounded to 256 chunks of 200 payload bytes, with 60-second
  receive expiry and at most eight incoming senders. Oversized snapshots are
  rejected with a message. Timerless clients support small snapshots only.
- Trade close alone is not success. Successful material exchange is not proof of
  finished crafting. The shopping list counts current bags, not delivered items.
- Error capture starts when ErrorReporter.lua loads and records attributable
  CraftRoster errors, not every other addon's errors or errors caught privately
  by another error handler. Reports are copied manually and never uploaded.

For feedback, include the copied `/cr bug` report plus steps, expected/actual
behavior, recipient/quantity details where relevant, and whether other addons
were enabled. Avoid publishing account information or unrelated private chat.


## Beta 9 in-game feedback checks

- Drag the top edge of Whisper Player and Mail Player target dialogs. Confirm Cancel and Enter still work; unrelated Blizzard popups must retain their normal behavior.
- Confirm the green flask has a standard round minimap border and sits outside the map; drag it around the edge.
- Open the profession menu: All must be first, followed by a blank separator and alphabetized professions.
- Search bundled recipes before any guild sync. A catalogue recipe must never imply a guildmate knows it.
- Check Bug Report in the title row of both Settings and the main directory, including minimum window width.
- While outgoing addon messages are restricted, repeated actions must produce at most one explanatory warning per minute. Manual whisper drafts and local search must remain usable.
- Extract the direct CraftRoster.zip into an empty AddOns directory: only CraftRoster/ should appear, with CraftRoster.toc immediately inside.


## Multi-window material delivery and recovery

With two Forever clients, test a request exceeding six stacks. Confirm the first
trade, reopen with the same crafter, and verify only outstanding materials load.
Remove/reduce a stack before accepting and verify the actual quantity is credited.
Repeat with a cancelled trade, full recipient bags, a locked stack, an occupied
cursor, occupied trade slots, and a wrong trade partner. No rejected or cancelled
window should reduce outstanding requirements. Verify duplicate success events
cannot credit a delivery twice and auto-load off still permits manual delivery.

Close without a known outcome and verify auto-loading pauses until `/crtrade`
review. Test reload during an open trade and between successful partial deliveries:
progress must persist; unknown outcomes must remain paused. The review prompt's
Nothing delivered action is appropriate only when both players verify no transfer.


## Crafter work-order acceptance

With two Forever clients, request a crafted item plus chest and glove enchants
from one customer, and another item from a second customer. Check quantities,
request/whisper deduplication, persistence after reload, and Accept/Decline sync.
Open a trade with the first customer: only their work should be brought forward.
Put gloves in the non-traded slot first, use the glove row's Enchant button and
normal item targeting, then repeat with the chest row. Both actions must remain
independently selectable. Cancel or fail one cast: it must not advance Done.

Check direct ordinary crafting with the profession open, closed, loading, sorted
and filtered. The order button should open the profession when necessary, then
craft exactly the requested recipe once per click. Test combat, missing materials,
linked profession views, an existing targeting cursor, and another player's trade.
No trade or profession event may automatically invoke a craft. Verify the game
accepts these hardware-click actions without taint or protected-action errors.


## Batch, character and received-mail checks

Request 30 potion crafts. Verify Craft1, a typed batch quantity and Craft remaining
invoke the correct native recipe/count. Interrupt a batch after 12 actual results;
Confirm batch12 must leave18 outstanding, without crediting the attempted30.
Try invalid quantities and repeated fast clicks. Enchants must remain single.

Log out normally and return: orders should persist. Switch to an alt and inspect
All characters: other-toon rows must be labeled and read-only. Confirm material
transfers never resume from another toon. Do not treat an unsaved hard crash as
guaranteed recovery. Read a generated crafting-mail request, reopen it and change
inbox sorting/indexes: only one order should remain. Unknown/ambiguous mail must
show manual-add guidance. Test late mail-body loading and recipient realm spaces.

Run `PYTHONPATH=<lupa-install> python tests/benchmark.py` for the mock directory,
queue/memory/row-reuse workload. Measure actual client addon memory and frame
profiling separately with realistic guild data; mock timings are not FPS claims.


## Search links and responsive main window

Verify distinct recipe and output links for Red Dragonscale Breastplate (recipe
item15730, finished item15047, crafting spell19054). Hover, inspect, Shift-click
with/without active chat, and right-click/copy each. Check trainer-only recipes,
uncached items, enchants with no produced item, and pooled empty/header rows.

Resize continuously at 620×420, 760×500, 1200×800 and a larger screen-fitting size.
Check both result links, crafter labels, quantity arrows, request actions and
source text never overlap. Drag each border/title, then resize from the corner;
buttons/links must remain independently clickable and the saved geometry must
return after reload. Check UI scale/font differences in the real client.

## Beta 11 priority checks

- With the shopping list closed, select a recipe. Check the item tooltip, native
  recipe preview, material icons, bag counts, and missing amounts. Add/remove bag
  materials; counts should refresh. Change Crafts using the keyboard and arrows.
- Resize the directory at 620 x 420, 760 x 500, and a larger UI scale. Scroll the
  right-hand craft pane to reach request buttons and crafters. Long recipe text
  must wrap and leave the material column separate. Search results keep native
  item tooltips.
- Cancel a request while the second client has Work Orders open. Its matching
  order should disappear, further auto-loading should stop, and other customers’
  orders should remain. If a trade was already accepted, verify the eventual
  delivery is recorded without reactivating the cancelled request.
- Read a crafting request mail twice and reload; it should create one order.
  Try Craft 1, a partial batch and Craft remaining. Confirm actual results after
  casting. Enchants require the user to choose the traded item and confirm trade.
- Log out normally and return: outstanding orders and transfer progress should
  persist. Unflushed SavedVariables can be lost on a hard crash.

The movable whisper composer is included; native drafts remain a fallback.
Cancellation status requires both connected clients
to run this candidate; offline/unavailable delivery is not queued for later replay.

- On Players, publish and clear My guild note, then Refresh on both clients. Add
  a private right-click note and verify it is not sent to the other client.
- Rescan a recipe on the crafter, then select that crafter on a requester lacking
  local materials. Verify all required reagents and item IDs arrive. A local scan
  must win over a conflicting peer list. Repeated selection should not flood chat.
- Check acquisition lists show source totals and omitted-example counts. Source
  names may be English; borrowed data and unknown percentages remain labeled.
