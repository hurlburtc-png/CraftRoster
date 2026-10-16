local ADDON_NAME, CraftRoster = ...

local CraftRequests = {}
CraftRoster.CraftRequests = CraftRequests

local REQUEST_PREFIX = "CRAFTREQ"

local function SendRequestMessage(message)
	if C_ChatInfo and C_ChatInfo.SendAddonMessage then
		C_ChatInfo.SendAddonMessage(REQUEST_PREFIX, message, "GUILD")
	end
end

function CraftRequests.CreateRequest(recipeID, quantity, notes)
	local payload = ("NEW:%d:%d:%s"):format(recipeID, quantity or 1, notes or "")
	SendRequestMessage(payload)
	print(("|cff00ff00CraftRoster|r: Craft request sent for recipe %d x%d."):format(recipeID, quantity or 1))
end

function CraftRequests.HandleMessage(prefix, message, channel, sender)
	if prefix ~= REQUEST_PREFIX then return end

	if message:sub(1, 4) == "NEW:" then
		local recipeID, quantity, notes = message:match("^NEW:(%d+):(%d+):(.*)$")
		if recipeID then
			recipeID = tonumber(recipeID)
			quantity = tonumber(quantity) or 1
			CraftRosterDB.requests = CraftRosterDB.requests or {}
			table.insert(CraftRosterDB.requests, {
				recipeID = recipeID,
				quantity = quantity,
				notes = notes,
				requester = sender,
				time = time(),
			})
			print(("|cff00ff00CraftRoster|r: New craft request from %s for recipe %d x%d."):format(sender or "?", recipeID, quantity))
		end
	end
end

CraftRoster.requestEventFrame = CraftRoster.requestEventFrame or CreateFrame("Frame")
CraftRoster.requestEventFrame:RegisterEvent("CHAT_MSG_ADDON")

CraftRoster.requestEventFrame:SetScript("OnEvent", function(self, event, ...)
	if event == "CHAT_MSG_ADDON" then
		local prefix, message, channel, sender = ...
		CraftRequests.HandleMessage(prefix, message, channel, sender)
	end
end)

if C_ChatInfo and C_ChatInfo.AddAddonMessageFilter then
	C_ChatInfo.AddAddonMessageFilter(REQUEST_PREFIX)
end

return CraftRequests
