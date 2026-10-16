local ADDON_NAME, CraftRoster = ...
local Core = CreateFrame("Frame", ADDON_NAME .. "Core")
CraftRoster.Core = Core

Core:RegisterEvent("ADDON_LOADED")
Core:SetScript("OnEvent", function(self, event, loadedAddon)
    if event == "ADDON_LOADED" and loadedAddon == ADDON_NAME then
        CraftRosterDB = CraftRosterDB or {}
        CraftRosterDB.settings = CraftRosterDB.settings or {
            enabled = true,
            autoUpdateRecipes = true,
        }
        CraftRosterDB.characters = CraftRosterDB.characters or {}
        CraftRosterDB.recipes = CraftRosterDB.recipes or {}

        local characterKey = UnitName("player") .. "-" .. (GetRealmName() or "")
        CraftRosterDB.characters[characterKey] = CraftRosterDB.characters[characterKey] or {
            recipes = {},
        }

        if CraftRoster.RecipeTracker then
            CraftRoster.RecipeTracker:Initialize()
        end

        if CraftRoster.Panel then
            CraftRoster.Panel:Initialize()
        end

        print("|cff00ff00CraftRoster|r loaded. Type /cr to open the panel.")
        self:UnregisterEvent("ADDON_LOADED")
    end
end)

SLASH_CRAFTROSTER1 = "/cr"
SLASH_CRAFTROSTER2 = "/craftroster"
SlashCmdList["CRAFTROSTER"] = function(msg)
    msg = (msg or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")

    if msg == "toggle" then
        local settings = CraftRosterDB.settings
        settings.enabled = not settings.enabled
        print(("CraftRoster is now %s."):format(
            settings.enabled and "|cff00ff00enabled|r" or "|cffff0000disabled|r"
        ))
    elseif CraftRoster.Panel then
        CraftRoster.Panel:Toggle()
    end
end
