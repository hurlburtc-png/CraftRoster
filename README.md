# CraftRoster

Find the right guild crafter for any recipe.

CraftRoster is a lightweight World of Warcraft addon for tracking professions and recipes, with a foundation for a guild-wide recipe directory.

## Installation

1. Go to **Releases** and download the latest **CraftRoster.zip**.
2. Extract the zip.
3. Copy the **CraftRoster** folder into your WoW `Interface\AddOns` folder.
4. Restart WoW, or type `/reload` in-game.

## Commands

- `/cr` — open the directory
- `/craftroster` — alternate command
- `/cr settings` — open settings
- `/cr reset` — reset the directory window position and size
- `/cr toggle` — enable or disable CraftRoster
- `/crdiagnostics` — show client build, API availability, and sync status
- `/crrequests` — show recent crafting requests
- `/crstatus <id> <accepted|completed>` — update a request status and sync it to the guild
- `/crfavorites` — list favorite recipes
- `/crdiscord` — print a Discord-ready guild crafting directory

## Actions

- **Update My Recipes** — manually rescan your known recipes.
- **Refresh** — request a guild recipe sync and refresh the directory.
- **Favorite** — toggle a recipe as a favorite.
- **Whisper & Trade Mats** — pick a recipe, enter a character, and arm trade auto-fill for materials.
- **Mail Crafter Mats** — pick a recipe, enter a full character name (name-server), and arm mail auto-fill for materials.

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

- Directory rows are pooled and reused.
- The recipe index is cached and rebuilt only when recipe data changes.
- The directory does not refresh while hidden.
- Newly learned recipes are captured automatically through `NEW_RECIPE_LEARNED`.
