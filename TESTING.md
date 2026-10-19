# CraftRoster 0.8.0-beta.6 test candidate

Status: ready for controlled in-game testing; release approval still requires a real client run.
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
No complete external catalogue or Forever acquisition database is bundled.

Beta 6 preserves complete material lists when required reagent slots are still
loading, tolerates transient schematic API errors, and reads the real schematic's
outputItemID. Filtering a selected offline crafter out now clears that action
target. Refresh requests an updated roster, including on clients using the global
GuildRoster API. An unavailable recipe tooltip has a readable fallback, and hiding
the minimap button stops its drag update handler.

The later conversation previews show proposed recipe-scroll item links, binding
labels and drop percentages. Those are not shipped yet: this candidate's source
pane links the crafting spell, and uses source text only when the client provides
it. The spell ID and crafted output item ID do not identify the learnable recipe
scroll. That requires a separate verified mapping and acquisition dataset.

### Recipe-source acceptance checks

1. Open each profession and scan. Check an unlearned recipe appears without
   increasing your learned count or being advertised as your known recipe.
2. Select a recipe with no saved crafter. Check the link/tooltip and Shift-click
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

Current review: 463 tests executed, 453 passed and 10 explicitly skipped for APIs
absent from the chosen profile. Both Lua 5.1 and LuaJIT 2.1 run modern, legacy and
minimal API scenarios. Isolated peer tests cover sync and request/status exchange.
Syntax and ZIP membership/integrity checks also pass.

The 5,000-recipe / 105,000-link workload keeps startup at 8 mocked UI objects,
adds 60 on first directory open, and adds only 4 more after 100 scrolls. A 20-event
recipe burst schedules one scan. Timings measure the mock runtime, not game FPS
or memory. Lua error storms retain at most 10 distinct reports, reuse the stack
for repeated messages, and print at most one capture notice per 10 seconds.

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
5. **Whisper and mail.** Select a crafter. Whisper Player must open an addressed
   draft with bracketed recipe quantities, without sending it. Send with Enter;
   exercise `/crwhisper` for long material lists. Mail Player must fill the exact
   selected Name-Realm and recipe subject, including an already-open mailbox and
   a recipe with no material data. Confirm recipients and attachments manually.
6. **Shopping list.** Pin a recipe, close the directory, acquire/remove materials,
   and verify counts. Drag the list and reload; reopen with `/cr shopping`. Close
   its X and ensure it stays closed after reload. Select a crafter and click a
   material to enter their contribution. Check requirements, whisper wording,
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

