local ADDON_NAME = ...
local WowForeverAddons = CreateFrame("Frame", ADDON_NAME .. "Core")

WowForeverAddons:RegisterEvent("ADDON_LOADED")
WowForeverAddons:SetScript("OnEvent", function(self, event, loadedAddon)
    if event == "ADDON_LOADED" and loadedAddon == ADDON_NAME then
        WowForeverAddonsDB = WowForeverAddonsDB or {}
        WowForeverAddonsDB.settings = WowForeverAddonsDB.settings or {
            enabled = true,
            autoUpdateRecipes = true,
        }
        WowForeverAddonsDB.characters = WowForeverAddonsDB.characters or {}
        WowForeverAddonsDB.recipes = WowForeverAddonsDB.recipes or {}

        local characterKey = UnitName("player") .. "-" .. (GetRealmName() or "")
        WowForeverAddonsDB.characters[characterKey] = WowForeverAddonsDB.characters[characterKey] or {
            recipes = {},
        }

        if WowForeverAddons.RecipeTracker then
            WowForeverAddons.RecipeTracker:Initialize()
        end

        if WowForeverAddons.Panel then
            WowForeverAddons.Panel:Initialize()
        end

        print("|cff00ff00Wow Forever Addons|r loaded. Type /wfa to open the panel.")
        self:UnregisterEvent("ADDON_LOADED")
    end
end)

SLASH_WOWFOREVERADDONS1 = "/wfa"
SlashCmdList["WOWFOREVERADDONS"] = function(msg)
    msg = (msg or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")

    if msg == "toggle" then
        local settings = WowForeverAddonsDB and WowForeverAddonsDB.settings
        if settings then
            settings.enabled = not settings.enabled
            print(("Wow Forever Addons is now %s."):format(
                settings.enabled and "|cff00ff00enabled|r" or "|cffff0000disabled|r"
            ))
        end
    elseif WowForeverAddons.Panel then
        WowForeverAddons.Panel:Toggle()
    end
end
