local ADDON_NAME, CraftRoster = ...

local GuildSync = {}
CraftRoster.GuildSync = GuildSync

local GUILD_SYNC_PREFIX = "CRAFTROSTER"

local function SendSyncMessage(message)
	if C_ChatInfo and C_ChatInfo.SendAddonMessage then
		C_ChatInfo.SendAddonMessage(GUILD_SYNC_PREFIX, message, "GUILD")
	end
end

function GuildSync.RequestSync()
	SendSyncMessage("SYNC_REQUEST")
	print("|cff00ff00CraftRoster|r: Requested guild recipe sync.")
end

function GuildSync.HandleMessage(prefix, message, channel, sender)
	if prefix ~= GUILD_SYNC_PREFIX then return end

	if message == "SYNC_REQUEST" then
		-- Respond with our known recipes
		for recipeID, data in pairs(CraftRosterDB.recipes or {}) do
			local payload = ("RECIPE:%d:%s:%s:%s"):format(
				recipeID,
				data.name or "",
				data.profession or "",
				data.crafter or ""
			)
			SendSyncMessage(payload)
		end
	elseif message:sub(1, 7) == "RECIPE:" then
		local recipeID, name, profession, crafter = message:match("^RECIPE:(%d+):(.*):(.*):(.*)$")
		if recipeID then
			recipeID = tonumber(recipeID)
			CraftRosterDB.recipes = CraftRosterDB.recipes or {}
			CraftRosterDB.recipes[recipeID] = {
				name = name,
				profession = profession,
				crafter = crafter,
			}
		end
	end
end

CraftRoster.eventFrame = CraftRoster.eventFrame or CreateFrame("Frame")
CraftRoster.eventFrame:RegisterEvent("CHAT_MSG_ADDON")
CraftRoster.eventFrame:RegisterEvent("GUILD_ROSTER_UPDATE")

CraftRoster.eventFrame:SetScript("OnEvent", function(self, event, ...)
	if event == "CHAT_MSG_ADDON" then
		local prefix, message, channel, sender = ...
		GuildSync.HandleMessage(prefix, message, channel, sender)
	elseif event == "GUILD_ROSTER_UPDATE" then
		-- Guild roster updated; nothing to do for now
	end
end)

if C_ChatInfo and C_ChatInfo.AddAddonMessageFilter then
	C_ChatInfo.AddAddonMessageFilter(GUILD_SYNC_PREFIX)
end

return GuildSync
