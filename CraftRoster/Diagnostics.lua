local ADDON_NAME, CraftRoster = ...

local Diagnostics = {}
CraftRoster.Diagnostics = Diagnostics

local function Check(name, fn)
	local ok = type(fn) == "function"
	return ("%s: %s"):format(name, ok and "|cff00ff00OK|r" or "|cffff0000MISSING|r")
end

SLASH_CRAFTROSTERDIAGNOSTICS1 = "/crdiagnostics"
SlashCmdList["CRAFTROSTERDIAGNOSTICS"] = function()
	local build, interface = "?", "?"
	if type(GetBuildInfo) == "function" then
		local version, _, _, api = GetBuildInfo()
		build, interface = version, api
	end
	print(("|cff00ff00CraftRoster|r diagnostics — build %s, interface %s"):format(build or "?", interface or "?"))

	print(Check("C_TradeSkillUI.GetRecipeInfo", C_TradeSkillUI and C_TradeSkillUI.GetRecipeInfo))
	print(Check("C_Container.GetContainerNumSlots", C_Container and C_Container.GetContainerNumSlots))
	print(Check("C_GuildInfo.GuildRoster", C_GuildInfo and C_GuildInfo.GuildRoster))
	print(Check("C_ChatInfo.SendAddonMessage", C_ChatInfo and C_ChatInfo.SendAddonMessage))

	local initialized = CraftRoster.Directory and CraftRoster.Directory.frame ~= nil
	print(("Initialized: %s"):format(initialized and "|cff00ff00yes|r" or "|cffff0000no|r"))

	local recipeCount = 0
	for _ in pairs(CraftRosterDB.recipes or {}) do recipeCount = recipeCount + 1 end
	local characterCount = 0
	for _ in pairs(CraftRosterDB.characters or {}) do characterCount = characterCount + 1 end
	print(("Saved recipes: %d · saved characters: %d"):format(recipeCount, characterCount))

	local lastSync = CraftRosterDB.lastGuildSync
	print(("Last guild sync: %s"):format(lastSync and date("%I:%M %p", lastSync) or "Never"))
end

return Diagnostics
