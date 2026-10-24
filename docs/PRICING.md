# Material pricing

CraftRoster reads optional pricing addons' existing local databases. It does not
scan the Auction House, download pricing, copy another addon's entire database,
buy anything or send your prices through guild sync.

## The two estimates

- **Full mats**: the value of every raw material for the selected number of craft
  executions, including materials already owned.
- **To buy**: the value of outstanding materials after bags, confirmed deliveries
  and the selected crafter's contribution. Saved bank stock is deliberately
  excluded; withdraw it into bags to reduce this number.
- An item unit price appears in its material tooltip when available.
- These are material market estimates, not vendor quotes, live listings or
  guaranteed purchase prices. Craft fees, tips and auction fees are not included.

Quantity, bags, crafter contributions and delivery updates refresh the displayed
estimate through the existing recipe refresh path.

## Providers and priority

Each item uses the first usable positive finite value from these interfaces:

1. **Auctioneer's Forever fork**: `Auctioneer:Statistics(itemID)`, first usable
   statistic's `Best()` value. Its statistic selection can differ from TSM.
2. **TSM modern API** when exported: `TSM_API.GetCustomPriceValue("dbmarket", "i:ID")`.
3. **TSM legacy API** when exported: `TSMAPI:GetItemValue("item:ID", "DBMarket")`.

Fallback happens per item; mixed-provider totals identify every provider used.
There is no support claim for every historical addon build. In particular the
old `AucAdvanced` API is not used by this initial integration. Actual installed
Forever provider versions still require in-game validation.

DBMarket is a market estimate, not the cheapest current auction. An API being
available does not establish that its local market data is recent or appropriate
to Forever. The tooltip explicitly leaves market scan age to the pricing addon.

Provider API references inspected during implementation:

- [Auctioneer Forever API](https://github.com/NoobyGains/Auctioneer-Forever/blob/main/Auctioneer/API.md)
- [Auctioneer statistic implementation](https://github.com/NoobyGains/Auctioneer-Forever/blob/main/Auctioneer/Statistics.lua)
- [Legacy TSM pricing API](https://github.com/Xurkon/TradeSkillMaster/blob/main/Core/Prices.lua)
- [TSM price-source meanings](https://support.tradeskillmaster.com/en_US/custom-strings/which-price-sources-can-i-use-and-what-do-they-mean)

## Missing information

- `+ ?` means the shown value is only the known subtotal; prices are missing.
- `? (bag count)` means the purchase estimate cannot be determined.
- `Prices unavailable` means the detected providers supplied no usable prices.
- If all outstanding materials are already covered, **To buy** can correctly be
  zero while **Full mats** remains unknown.

Install/enable a supported pricing addon and populate its local data normally.
Click CraftRoster's estimate to clear its small lookup cache and reread local
prices. This does not initiate a scan. The API lookup cache holds at most 128
items for up to 30 seconds, is not persisted, and detects provider replacement or
late API availability. No polling timer or frame update loop is introduced.

## Verification

Mock tests exercise native Auctioneer statistics, modern and legacy TSM call
shapes, fallback and errors, invalid prices, independent full/shortfall coverage,
unknown bags, fractional-unit rounding, cache eviction/expiry and late providers.
UI tests cover quantity/bag changes and the explicit refresh click. These checks
do not replace testing the installed pricing addons on the actual Forever client.
