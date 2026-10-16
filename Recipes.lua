local ADDON_NAME, WowForeverAddons = ...

local RecipeTracker = {}
WowForeverAddons.RecipeTracker = RecipeTracker

local function GetCharacterKey()
    return UnitName("player") .. "-" .. (GetRealmName() or "")
end

local function GetCharacterData()
    local key = GetCharacterKey()
    WowForeverAddonsDB.characters[key] = WowForeverAddonsDB.characters[key] or {
        recipes = {},
    }
    return WowForeverAddonsDB.characters[key]
end

function RecipeTracker:Initialize()
    self:RegisterEvent("NEW_RECIPE_LEARNED")
    self:SetScript("OnEvent", function(_, event, recipeID)
        if event == "NEW_RECIPE_LEARNED" then
            RecipeTracker:RecordRecipe(recipeID)
        end
    end)
end

function RecipeTracker:RecordRecipe(recipeID)
    if not recipeID then
        return false
    end

    local settings = WowForeverAddonsDB.settings
    local character = GetCharacterData()

    if not settings.autoUpdateRecipes and not self.manualUpdateInProgress then
        return false
    end

    if character.recipes[recipeID] then
        return false
    end

    character.recipes[recipeID] = {
        learnedAt = time(),
    }

    WowForeverAddonsDB.recipes[recipeID] = WowForeverAddonsDB.recipes[recipeID] or {
        firstSeenBy = GetCharacterKey(),
        firstSeenAt = time(),
    }

    WowForeverAddonsDB.lastRecipeUpdate = time()

    if WowForeverAddons.Panel then
        WowForeverAddons.Panel:RefreshStatus()
    end

    return true
end

function RecipeTracker:UpdateKnownRecipes()
    self.manualUpdateInProgress = true
    local added = 0

    -- Blizzard does not expose one universal API that returns every recipe ID
    -- known by every profession. Professions can register their own data
    -- providers here as they are implemented.

    self.manualUpdateInProgress = nil

    WowForeverAddonsDB.lastRecipeUpdate = time()

    if WowForeverAddons.Panel then
        WowForeverAddons.Panel:RefreshStatus()
    end

    return added
end

function RecipeTracker:GetKnownRecipeCount()
    local character = GetCharacterData()
    local count = 0

    for _ in pairs(character.recipes or {}) do
        count = count + 1
    end

    return count
end
