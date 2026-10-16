# CraftRoster

Find the right guild crafter for any recipe.

CraftRoster is a World of Warcraft addon for tracking professions and recipes, with a foundation for a guild-wide recipe directory.

## Commands

- `/cr` — open the CraftRoster directory
- `/craftroster` — alternate command for the directory
- `/cr settings` — open the compact settings panel
- `/cr toggle` — enable or disable the addon

## Directory

### Professions

- Search saved recipes by name.
- Filter by profession.
- Recipes are grouped with standard WoW profession icons.
- Select a recipe to see its details and which saved characters can craft it.

### Players

- Search saved characters.
- Each player row shows a race/gender icon, class-colored character name, and saved recipe count.

### My Recipes

- View recipes saved for your current character.
- Click **Update My Recipes** to run a manual refresh.

## Recipe tracking

- Newly learned recipes are captured automatically when WoW reports `NEW_RECIPE_LEARNED`.
- Use **Auto-update new recipes** in the settings panel to enable or disable automatic capture.
- Recipe data is stored locally in `CraftRosterDB` for now.

## Development

- `Core.lua` — initialization, saved variables, and slash commands
- `Recipes.lua` — recipe capture and automatic new-recipe tracking
- `Panel.lua` — compact settings and status panel
- `Directory.lua` — main recipe/player directory interface
- `CraftRoster.toc` — addon metadata and load order
