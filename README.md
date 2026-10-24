# CraftRoster

[**Download CraftRoster.zip — 0.8.0-beta.52**](https://github.com/hurlburtc-png/CraftRoster/raw/refs/heads/main/CraftRoster.zip)

[**Download tagged beta.52 ZIP**](https://github.com/hurlburtc-png/CraftRoster/releases/download/v0.8.0-beta.52/CraftRoster.zip)

**Version:** `0.8.0-beta.52`  
**Released:** October 24, 2026 at 4:26:45 PM MDT (America/Edmonton; UTC−6).



Unsure which guildie can craft it? Is their name an abomination you can’t type without some cooked accents?? Are they offline, so you can’t ask whether they know the recipe? Wondering what the mats are—or how to help someone get the recipe if nobody knows it? Need a shopping list showing what’s missing and how much to buy? Are your bags a mess, and wouldn’t it be easier to have an addon pull the mats into your trade window or mail, with recipient checks and you in control of the final click?! All of this and MUCH MORE with **CRAFTROSTER!!!!**

**Preferred install download.** Extracts to one **CraftRoster** folder, ready for `Interface/AddOns`. This link stays the same as the addon is updated.

**Target:** Forever 1.60.1, build 70450 · Interface 16001

**Status:** Beta.52 source, addon and release checks passed: 2,182 tests (10 skipped), Forever recipe reconciliation and automated single-root `CraftRoster/` ZIP validation. No in-game validation claimed.

**Material pricing:** The recipe pane shows **Full mats** and **To buy** estimates using available local Auctioneer or TSM data. Full mats values all raw materials for your selected craft quantity. To buy subtracts bag stock, confirmed deliveries and crafter-provided materials. Missing prices show incomplete totals, never free materials. Hover for sources and coverage; click the estimate to reread local data. No scanning, external price database or purchases are added. [Pricing details and supported APIs](docs/PRICING.md).

**Location tools:** Reviewed vendor, trainer and mob records can show NPC names, zones and coordinates, with copy controls and compatible TomTom/native map markers. Trainers show the required profession skill and are limited to verified trainers for your faction or neutral trainers. Unverified references cannot create waypoints. Coordinate coverage is still limited; missing positions are never guessed.

**Classic sources by default:** When confirmed Forever details are missing, exact Classic matches show named vendors, trainers, drops or quest sources. Vendor/trainer details include full NPC names, trainer titles, zones, coordinates where recorded, and training requirements. Boss and dungeon/raid drops show the boss or mob and instance, without coordinate clutter. Faction-specific trainers and vendors are filtered for your character. The catalogue-wide build checks all 2,510 recipes and supplies detailed Classic records for 1,135; 1,257 have no exact Classic counterpart and 118 need further acquisition evidence. These references are labelled unconfirmed in Forever and cannot create map markers. [Coverage and build details](docs/CLASSIC_SOURCE_BUILD.md).


**Crafter data freshness:** Hover a crafter to see when their saved recipe snapshot was shared. Missing timestamps are stated explicitly. Online status does not establish that their recipe scan is current.

**Latest reliability fixes:** Selected-recipe and shopping-list shift-clicks no longer open another chat editor if a hybrid client lacks the active-editor lookup and native insertion fails. Successful native inserts and confirmed-closed chat fallbacks remain available.  Concurrent identical active trade requests no longer borrow one another's delivered-material credits in the selected-recipe shopping list; ambiguous credits remain unapplied until only one active request matches. Selected-recipe shift-click links no longer open a second chat editor when the hybrid chat-window lookup throws; both craft and teaching-scroll links now fail closed if editor state is unknown.  Invalid, infinite or fractional hybrid inventory counts now fall back to legacy APIs or remain unknown instead of falsely showing available stock. Impossible bag slot/stack counts cannot trigger unbounded scans. Outgoing craft mail now leaves drafts untouched when recipient, money/COD, subject/body or attachment inspection APIs fail on hybrid clients; retry is possible after the API recovers. Closed trade requests no longer credit previously delivered materials against a new identical shopping list; active order progress still counts. Material Auction House searches now stop safely if modern or legacy search-frame visibility fails, instead of filling an unrelated stale search field.  Opened-mail capture rechecks the visible reader and sender/subject after reading the body, preventing mid-read inbox changes from attributing a request to the wrong customer. Shopping material clicks no longer crash or switch to an Auction House search when hybrid chat-window lookup fails. Hybrid clients with incomplete or throwing modern bag APIs now retry a coherent legacy bag scan. If neither can read bags safely, material counts remain unknown rather than falsely showing zero. Concurrent identical crafting requests are kept separate for review when more than one whisper/addon work order could match; no arbitrary request identity is attached.  Guild request status messages now fail safely when hybrid clients throw during restriction checks, guild membership checks or addon transport; uncertain sends are not retried automatically to avoid duplicate requests.  Trade and mail material auto-fill now tolerates unavailable modern bag APIs, falls back to legacy bag reads where possible, and skips transfers safely when bag contents cannot be read. Opened-mail imports pause when the visible reader and inbox report conflicting valid mail indices, avoiding a work order for the wrong sender. Craft mail will not overwrite an already-addressed draft or attach materials after its recipient changes. Opened-mail imports handle invalid inbox indexes on hybrid clients. Selected-recipe shift-click links tolerate chat API failures. Whisper drafts remain available for retry if the game cannot open a chat window.

**Search performance:** Version-group tables are now allocated only for duplicate recipes. Profession, guild and favorite filters run before text matching, and rarity colors reuse one shared table. Paired mock measurements are in [performance notes](docs/PERFORMANCE.md).

**Loading and memory:** Generated source expansions now use a bounded 32-entry cache. The full catalogue and reviewed source records remain available. Mock benchmarks show less retained memory after browsing and faster directory opening; these are not in-game FPS or login-speed measurements. [Measured comparison](docs/PERFORMANCE.md).

**Latest usability fixes:** Mock anchor tests now exercise selected recipes with 3, 6 and 10 materials across five pane widths and six Lua/client configurations; rendered one-pane fit still requires in-game testing.  Click the availability button below **Known by guild** to cycle **All**, **I know** and **Not in my scan**. These use this character’s saved learned recipes and combine with guild, profession and favorite filters. Scan your professions to update the results; absence from a scan does not establish that a recipe is unlearned. Long source previews are limited to four lines; hover the source heading for the complete summary or expand it for full sources and navigation controls. Craft / Request craft sits beside Quantity on normal-width panes, saving 44 pixels below the materials. Narrow panes keep the controls separate to prevent overlap. The default window keeps recipe details and materials side by side; narrow panes stack them for readability. 

 Clear the active shopping list with **Clear list**. Search matches all entered words, including aliases such as wrist/bracer. Tick **Known by guild** below the search to show only recipes in your own or saved guildmates’ scans, including offline members. Same-name recipes share one result with a **Version** selector; each version keeps its own crafters, materials and sources. The selected-recipe pane uses more width and shows a short source overview; expand it for full details. Ten Enchanting recipes now include named Classic vendor examples and sourced coordinates, clearly unconfirmed for Forever.


**Item readability:** Crafted-item names use the client’s rarity colour and have room for two lines. Crafter counts sit below the name, beside a short pattern/formula link. Unknown rarity stays neutral. Scroll footers have a solid background and wrapped text is remeasured when its content changes.

## Install

1. Download **CraftRoster.zip** above, rather than GitHub’s **Code → Download ZIP**.
2. Extract into `Interface/AddOns`, so the file sits at `Interface/AddOns/CraftRoster/CraftRoster.toc`.
   If your extractor adds an outer folder, move the inner **CraftRoster** folder directly into **AddOns**. The folder containing **CraftRoster.toc** is the addon.
3. Restart WoW and type `/cr`.

## Get started

Open your professions and scan them, then click **Refresh** to share recipes with guildmates running CraftRoster. Search for a craft, set its quantity and select a crafter.

- **Whisper:** edit the request, then click a known crafter or **Send**. Copy the text for someone outside the guild. Long requests use **Send next**.
- **Mail:** prepare the recipient, subject, materials and attachments; review and send the mail yourself.
- **Materials:** see icons and live bag counts in the main window or shopping list. Click to insert its item link into an open whisper draft or active chat; otherwise, with the Auction House open, fill its search box. Shift-click links into chat.
- **Work Orders:** track requests, choose single crafts or batches, and import recognized crafting mail when read. Orders survive normal logout/reload.

## Other features

- Bundled recipe catalogue, online/offline guild crafters, item tooltips and favorites.
- Daily online database checks prepare a draft review when upstream recipes or
  acquisition files change. Approved database changes ship through addon updates;
  the game does not download web data. See [database updates](docs/DATABASE_UPDATES.md).
- Partial delivery tracking, an **Auto-load items** toggle, and **Cancel request** to update connected crafters.
- Personal-bank material tracking: bags and saved bank stock shown separately,
  with withdrawal and remaining-shortage details. Visit the bank once to scan it;
  counts stay private and bank stock never counts as ready to trade or mail.
- Public crafting notes, private member notes and missing material details fetched from a crafter’s scan.
- Movable, resizable windows with scrolling for longer recipe details.
- Larger item headings and a native-style editable quantity field with up/down
  arrows, acquisition locations directly below
  the recipe link, and an inline **Craft / Request craft** button. Direct crafting
  uses your learned recipes and selected quantity; guild requests prepare a whisper.
- Dark-and-gold styling, a wider craft detail pane and highlighted recipe/crafter selections.
- **Settings → Appearance:** live 75–150% addon scaling and ten clickable themes:
  Classic Gold, Dark, High Contrast, Frost Blue, Emerald, Arcane Violet, Ember Fire,
  Woodland Nature, Fel Chaos and Ironbound. A sample previews selections immediately,
  with no Apply button or reload. Preferences save automatically;
  **Reset appearance** restores the defaults. Large windows fit the available screen.
- **Settings → Window controls:** live 40–100% window opacity alongside UI scale.
  Settings stays solid and opens independently of the main window; use **Open main
  window** to compare changes, or drag its bottom-right corner to resize the layout.
  General controls, window controls and all themes fit on one settings page.

You confirm trades, mail and completed orders yourself. Missing guild data does not mean nobody knows a recipe. Acquisition sources and drop estimates are labeled with their provenance.

## Commands

| Command | Opens |
| --- | --- |
| `/cr` | Crafting directory |
| `/cr orders` | Crafter work orders |
| `/cr shopping` | Shopping list |
| `/cr settings` | Settings and recipe scan |
| `/crtrade` | Material delivery review |
| `/cr bug` | Lua error report |

[Full guide](docs/USAGE.md) · [Testing and limitations](TESTING.md) · [Roadmap](docs/ROADMAP.md) · [Report an issue](https://github.com/hurlburtc-png/CraftRoster/issues)

Made by Triggles · [MIT license](LICENSE)
