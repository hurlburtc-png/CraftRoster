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
			onlineOnly = true,
		}
		CraftRosterDB.characters = CraftRosterDB.characters or {}
		CraftRosterDB.recipes = CraftRosterDB.recipes or {}

		local characterKey = UnitName("player") .. "-" .. (GetRealmName() or "")
		local character = CraftRosterDB.characters[characterKey] or {}
		character.recipes = character.recipes or {}
		character.professions = character.professions or {}
		character.class = select(2, UnitClass("player"))
		character.raceName, character.raceFile = UnitRace("player")
		character.gender = UnitSex("player")
		CraftRosterDB.characters[characterKey] = character

		if CraftRoster.RecipeTracker then
			CraftRoster.RecipeTracker:Initialize()
			CraftRoster.RecipeTracker:UpdateProfessions()
		end

		if CraftRoster.Panel then CraftRoster.Panel:Initialize() end
		if CraftRoster.Directory then CraftRoster.Directory:Initialize() end

		print("|cff00ff00CraftRoster|r loaded. Type /cr to open the directory.")
		self:UnregisterEvent("ADDON_LOADED")
	end
end)

SLASH_CRAFTROSTER1 = "/cr"
SLASH_CRAFTROSTER2 = "/craftroster"
SlashCmdList["CRAFTROSTER"] = function(msg)
	msg = (msg or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")

	if msg == "toggle" then
		CraftRosterDB.settings.enabled = not CraftRosterDB.settings.enabled
		print(("CraftRoster is now %s."):format(
			CraftRosterDB.settings.enabled and "|cff00ff00enabled|r" or "|cffff0000disabled|r"
		))
	elseif msg == "reset" and CraftRoster.Directory then
		CraftRoster.Directory:ResetWindow()
	elseif msg == "settings" and CraftRoster.Panel then
		CraftRoster.Panel:Toggle()
	elseif CraftRoster.Directory then
		CraftRoster.Directory:Toggle()
	end
end
