local ADDON_NAME, CraftRoster = ...
local Core = CreateFrame("Frame", ADDON_NAME .. "Core")
CraftRoster.Core = Core

local lastChatWarning = -60
function CraftRoster:WarnChatRestricted()
	if time() - lastChatWarning < 60 then return end
	lastChatWarning = time()
	print("|cffffd100CraftRoster|r: the client is blocking addon messages. Guild sync/status cannot send; local search and manual whispers still work. This does not mean guildmates lack CraftRoster.")
end

Core:RegisterEvent("ADDON_LOADED")
Core:SetScript("OnEvent", function(self, event, loadedAddon)
	if event == "ADDON_LOADED" and loadedAddon == ADDON_NAME then
		CraftRosterDB = CraftRosterDB or {}
		CraftRosterDB.settings = CraftRosterDB.settings or {}
		for key, value in pairs({ enabled = true, autoUpdateRecipes = true, onlineOnly = true, autoLoadItems = true, windowOpacity = 1 }) do
			if CraftRosterDB.settings[key] == nil then CraftRosterDB.settings[key] = value end
		end
		CraftRosterDB.characters = CraftRosterDB.characters or {}
		CraftRosterDB.recipes = CraftRosterDB.recipes or {}

		if CraftRoster.ErrorReporter then CraftRoster.ErrorReporter:Restore() end

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

		if CraftRoster.ShoppingList then CraftRoster.ShoppingList:Restore() end

		-- Build UI frames only when the player opens the directory or settings.

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
		if CraftRoster.WorkOrders then CraftRoster.WorkOrders:Refresh() end
		print(("CraftRoster is now %s."):format(
			CraftRosterDB.settings.enabled and "|cff00ff00enabled|r" or "|cffff0000disabled|r"
		))
	elseif (msg == "bug" or msg == "errors") and CraftRoster.Panel then
		CraftRoster.Panel:ShowError()
	elseif (msg == "orders" or msg == "workorders") and CraftRoster.WorkOrders then
		CraftRoster.WorkOrders:Toggle()
	elseif msg == "shopping" and CraftRoster.ShoppingList then
		CraftRoster.ShoppingList:Toggle()
	elseif msg == "reset" and CraftRoster.Directory then
		CraftRoster.Directory:ResetWindow()
	elseif msg == "settings" and CraftRoster.Panel then
		CraftRoster.Panel:Toggle()
	elseif CraftRoster.Directory then
		CraftRoster.Directory:Toggle()
	end
end
