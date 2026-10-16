local ADDON_NAME, CraftRoster = ...

local RecipeTracker = {}
CraftRoster.RecipeTracker = RecipeTracker

local function GetCharacterKey()
    return UnitName("player") .. "-" .. (GetRealmName() or "")
end

local function GetCharacterData()
    local key = GetCharacterKey()
    CraftRosterDB.characters[key] = CraftRosterDB.characters[key] or {
        recipes = {},
    }
    return CraftRosterDB.characters[key]
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

    local settings = CraftRosterDB.settings
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

    CraftRosterDB.recipes[recipeID] = CraftRosterDB.recipes[recipeID] or {
        firstSeenBy = GetCharacterKey(),
        firstSeenAt = time(),
    }

    CraftRosterDB.lastRecipeUpdate = time()

    if CraftRoster.Panel then
        CraftRoster.Panel:RefreshStatus()
    end

    return true
end

function RecipeTracker:UpdateKnownRecipes()
    self.manualUpdateInProgress = true
    local added = 0

    -- Profession-specific importers will populate full known-recipe lists.

    self.manualUpdateInProgress = nil

    CraftRosterDB.lastRecipeUpdate = time()

    if CraftRoster.Panel then
        CraftRoster.Panel:RefreshStatus()
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
