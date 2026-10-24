# CraftRoster

[**Download CraftRoster.zip — 0.8.0-beta.31**](https://github.com/hurlburtc-png/CraftRoster/raw/refs/heads/main/CraftRoster.zip)

**Version:** `0.8.0-beta.31`  
**Released:** ZIP validation in progress.



Unsure which guildie can craft it? Is their name an abomination you can’t type without some cooked accents?? Are they offline, so you can’t ask whether they know the recipe? Wondering what the mats are—or how to help someone get the recipe if nobody knows it? Need a shopping list showing what’s missing and how much to buy? Are your bags a mess, and wouldn’t it be easier to have an addon pull the mats into your trade window or mail, with recipient checks and you in control of the final click?! All of this and MUCH MORE with **CRAFTROSTER!!!!**

**Preferred install download.** Extracts to one **CraftRoster** folder, ready for `Interface/AddOns`. This link stays the same as the addon is updated.

**Target:** Forever 1.60.1, build 70450 · Interface 16001

**Status:** Beta. Beta 31 release validation is in progress; in-game verification is still required.

**Location tools:** Reviewed vendor, trainer and mob records can show NPC names, zones and coordinates, with copy controls and compatible TomTom/native map markers. Trainers show the required profession skill and are limited to verified trainers for your faction or neutral trainers. Unverified references cannot create waypoints. Coordinate coverage is still limited; missing positions are never guessed.

**Classic sources by default:** When confirmed Forever details are missing, exact Classic matches show named vendors, trainers, drops or quest sources. Vendor/trainer details include full NPC names, trainer titles, zones, coordinates where recorded, and training requirements. Boss and dungeon/raid drops show the boss or mob and instance, without coordinate clutter. Faction-specific trainers and vendors are filtered for your character. The catalogue-wide build checks all 2,510 recipes and supplies detailed Classic records for 1,135; 1,257 have no exact Classic counterpart and 118 need further acquisition evidence. These references are labelled unconfirmed in Forever and cannot create map markers. [Coverage and build details](docs/CLASSIC_SOURCE_BUILD.md).


**Crafter data freshness:** Hover a crafter to see when their saved recipe snapshot was shared. Missing timestamps are stated explicitly. Online status does not establish that their recipe scan is current.

**Latest usability fixes:** Long source previews are limited to four lines; hover the source heading for the complete summary or expand it for full sources and navigation controls. Craft / Request craft sits beside Quantity on normal-width panes, saving 44 pixels below the materials. Narrow panes keep the controls separate to prevent overlap. The default window keeps recipe details and materials side by side; narrow panes stack them for readability. Beta 29’s installable ZIP passed its automated suite: 1,670 tests run, 10 skipped.

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
