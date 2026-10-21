local ADDON_NAME, CraftRoster = ...

local GuildSync = {}
CraftRoster.GuildSync = GuildSync

local PREFIX = "CRAFTROSTER"
local REQUEST_THROTTLE = 30
local SEND_THROTTLE = 10
local lastRequest, lastSend = -30, -10
local transfers = {}
local sequence = 0
local sending = false
local cachedPayload, lastPayload
local retryTimer, pendingSend, pendingForce

function GuildSync:InvalidateData()
	cachedPayload = nil
end

local function GetCharacterKey()
	return UnitName("player") .. "-" .. (GetRealmName() or "")
end

local function SendAddonData(message)
	if not CraftRosterDB or not CraftRosterDB.settings.enabled then return false end
	if #message > 255 or (IsInGuild and not IsInGuild()) then return false end
	if C_ChatInfo and C_ChatInfo.AreOutgoingAddonChatMessagesRestricted
		and C_ChatInfo.AreOutgoingAddonChatMessagesRestricted() then
		CraftRoster:WarnChatRestricted()
		return false
	end
	if C_ChatInfo and C_ChatInfo.InChatMessagingLockdown
		and C_ChatInfo.InChatMessagingLockdown() then
		CraftRoster:WarnChatRestricted()
		return false
	end
	local send = C_ChatInfo and C_ChatInfo.SendAddonMessage or SendAddonMessage
	if type(send) == "function" then
		local result = send(PREFIX, message, "GUILD")
		if result == false then return false end
		local success = Enum and Enum.SendAddonMessageResult and Enum.SendAddonMessageResult.Success
		if success ~= nil then
			return result == success or result == true
		end
		-- Legacy clients may return no value on a successful send.
		return result == nil or result == true
	end
	return false
end

local function Encode(value)
	return (value or ""):gsub("[%%:;|]", function(char) return ("%%%02X"):format(char:byte()) end)
end

local function Decode(value)
	return (value or ""):gsub("%%(%x%x)", function(hex) return string.char(tonumber(hex, 16)) end)
end

local function SerializeCharacter()
	local key = GetCharacterKey()
	local character = CraftRosterDB.characters and CraftRosterDB.characters[key]
	if not character then return nil end

	local professions = {}
	for name, data in pairs(character.professions or {}) do
		table.insert(professions, ("%s:%d:%d:%d"):format(name, data.skill or 0, data.max or 0, data.rank or 0))
	end

	local recipes = {}
	for recipeID, data in pairs(character.recipes or {}) do
		local saved = CraftRosterDB.recipes[recipeID] or {}
		table.insert(recipes, ("%d:%d:%s:%s"):format(recipeID, data.learnedAt or 0, Encode(saved.name), Encode(saved.profession)))
	end

	table.sort(professions)
	table.sort(recipes)
	return table.concat(professions, ";") .. "|" .. table.concat(recipes, ";")
end

local function DeserializeCharacter(payload)
	local professionPart, recipePart = payload:match("^(.-)|(.*)$")
	if not professionPart then return nil end
	local professions, recipes, metadata = {}, {}, {}

	for entry in (professionPart or ""):gmatch("[^;]+") do
		local name, skill, max, rank = entry:match("^([^:]+):(%d+):(%d+):(%d+)$")
		if not name then return nil end
		if name then
			professions[name] = {
				skill = tonumber(skill),
				max = tonumber(max),
				rank = tonumber(rank),
			}
		end
	end

	for entry in (recipePart or ""):gmatch("[^;]+") do
		local recipeID, learnedAt, name, profession = entry:match("^(%d+):(%d+):([^:]*):([^:]*)$")
		if not recipeID then recipeID, learnedAt = entry:match("^(%d+):(%d+)$") end
		if not recipeID or tonumber(recipeID) <= 0 then return nil end
		if recipeID then
			recipes[tonumber(recipeID)] = { learnedAt = tonumber(learnedAt) }
			if name and name ~= "" then metadata[tonumber(recipeID)] = { name = Decode(name), profession = Decode(profession) } end
		end
	end

	return professions, recipes, metadata
end

function GuildSync:RequestSync()
	if time() - lastRequest < REQUEST_THROTTLE then return end
	if SendAddonData("REQ") then lastRequest = time(); return true end
	return false
end

function GuildSync:SyncNow()
	local requested = self:RequestSync()
	self:SendData(true)
	if requested then
		print("|cff00ff00CraftRoster|r: requesting guild recipe sync.")
	end
end

function GuildSync:SendData(force)
	if not CraftRosterDB.settings.enabled then return end
	if sending then pendingSend = true; pendingForce = pendingForce or force; return end
	if time() - lastSend < SEND_THROTTLE then
		pendingForce = pendingForce or force
		if not retryTimer and C_Timer and C_Timer.NewTimer then
			retryTimer = C_Timer.NewTimer(SEND_THROTTLE - (time() - lastSend), function()
				retryTimer = nil
				local requested = pendingForce; pendingForce = nil
				GuildSync:SendData(requested)
			end)
		end
		return
	end
	local payload = cachedPayload or SerializeCharacter()
	if not payload then return end
	cachedPayload = payload
	if not force and payload == lastPayload then return end
	local message = ("DATA:%s:%d:%s"):format(GetCharacterKey(), time(), payload)
	if #message <= 255 then
		if SendAddonData(message) then lastSend = time(); lastPayload = payload end
		return
	end
	-- Bounded, paced chunks keep every addon message below the client byte limit.
	local total = math.ceil(#message / 200)
	if total > 256 or not (C_Timer and C_Timer.NewTimer) then
		print("|cffff0000CraftRoster|r: recipe sync is too large or this client lacks a timer API.")
		return
	end
	sequence = sequence + 1
	local transferID = tostring(time()) .. "-" .. sequence
	local function SendPart(index)
		local chunk = message:sub((index - 1) * 200 + 1, index * 200)
		if not SendAddonData(("PART:%s:%d:%d:%s"):format(transferID, index, total, chunk)) then
			sending = false
			print("|cffff0000CraftRoster|r: guild sync interrupted. Use Refresh to retry.")
			return
		end
		if index < total then
			C_Timer.NewTimer(0.2, function() SendPart(index + 1) end)
		else
			sending = false; lastPayload = payload
			if pendingSend then
				pendingSend = nil
				local requested = pendingForce; pendingForce = nil
				GuildSync:SendData(requested)
			end
		end
	end
	lastSend = time()
	sending = true
	SendPart(1)
end

function GuildSync:GetStatusText()
	local synced = 0
	for _, character in pairs(CraftRosterDB.characters or {}) do
		if character.lastSync then synced = synced + 1 end
	end

	local lastSync = CraftRosterDB.lastGuildSync
	local timeText = lastSync and date("%I:%M %p", lastSync) or "Never"
	return ("Guild sync: %d crafter(s) · last sync: %s"):format(synced, timeText)
end

local function SameRecipes(a, b)
	for id in pairs(a or {}) do if not b[id] then return false end end
	for id in pairs(b) do if not a or not a[id] then return false end end
	return true
end

local function SameProfessions(a, b)
	for name, data in pairs(a or {}) do
		local other = b[name]
		if not other or data.skill ~= other.skill or data.max ~= other.max or data.rank ~= other.rank then return false end
	end
	for name in pairs(b) do if not a or not a[name] then return false end end
	return true
end

local function MergeCharacter(characterKey, updated, payload)
	if not updated or updated > time() + 300 then return end
	local existing = CraftRosterDB.characters[characterKey]
	if existing and (existing.lastSync or 0) >= updated then return end

	local professions, recipes, metadata = DeserializeCharacter(payload)
	if not professions then return end
	local changed = not existing or not SameRecipes(existing.recipes, recipes) or not SameProfessions(existing.professions, professions)
	for recipeID, data in pairs(metadata) do
		local saved = CraftRosterDB.recipes[recipeID] or {}
		if not saved.name then saved.name = data.name; changed = true end
		if not saved.profession or saved.profession == "Unknown" then saved.profession = data.profession; changed = true end
		CraftRosterDB.recipes[recipeID] = saved
	end
	existing = existing or {}
	existing.recipes = recipes
	existing.professions = professions
	existing.lastSync = updated
	CraftRosterDB.characters[characterKey] = existing

	CraftRosterDB.lastGuildSync = time()

	if changed and CraftRoster.ShoppingList then CraftRoster.ShoppingList:ScheduleRefresh() end
	if changed and CraftRoster.Directory then
		CraftRoster.Directory:InvalidateIndex()
	end
end

local function NormalizeCharacter(name)
	if type(name) ~= "string" or name == "" then return nil end
	if not name:find("-", 1, true) then name = name .. "-" .. (GetRealmName() or "") end
	return name:lower():gsub("%s", "")
end

local function HandleData(message, sender)
	local characterKey, updated, payload = message:match("^DATA:([^:]+):(%d+):(.*)$")
	if characterKey and NormalizeCharacter(characterKey) == NormalizeCharacter(sender)
		and NormalizeCharacter(sender) ~= NormalizeCharacter(GetCharacterKey()) then
		local senderKey = sender:find("-", 1, true) and sender or sender .. "-" .. (GetRealmName() or "")
		MergeCharacter(senderKey, tonumber(updated), payload)
	end
end

local function ReceivePart(message, sender)
	local id, index, total, chunk = message:match("^PART:([%d%-]+):(%d+):(%d+):(.*)$")
	index, total = tonumber(index), tonumber(total)
	if not id or #id > 32 or not index or not total or total < 1 or total > 256
		or index < 1 or index > total or #chunk > 200 then return end
	local count = 0
	for key, transfer in pairs(transfers) do
		if time() - transfer.started > 60 then transfers[key] = nil else count = count + 1 end
	end
	local transfer = transfers[sender]
	if not transfer or transfer.id ~= id then
		if not transfer and count >= 8 then return end
		transfer = { id = id, total = total, parts = {}, count = 0, started = time() }
		transfers[sender] = transfer
	end
	if transfer.total ~= total then return end
	if not transfer.parts[index] then transfer.parts[index] = chunk; transfer.count = transfer.count + 1 end
	if transfer.count == total then
		transfers[sender] = nil
		HandleData(table.concat(transfer.parts), sender)
	end
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:RegisterEvent("CHAT_MSG_ADDON")

frame:SetScript("OnEvent", function(_, event, ...)
	local arg1 = ...
	local prefix, message, channel, sender = ...
	if event == "ADDON_LOADED" and arg1 == ADDON_NAME then
		if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
			C_ChatInfo.RegisterAddonMessagePrefix(PREFIX)
		elseif RegisterAddonMessagePrefix then
			RegisterAddonMessagePrefix(PREFIX)
		end

	elseif event == "PLAYER_ENTERING_WORLD" then
		-- One lightweight sync request per login; throttled and memory-cheap.
		GuildSync:RequestSync()

	elseif event == "CHAT_MSG_ADDON" and prefix == PREFIX and channel == "GUILD" then
		if not CraftRosterDB or not CraftRosterDB.settings.enabled
			or type(sender) ~= "string" or sender == "" or type(message) ~= "string" or #message > 255 then return end
		if message == "REQ" then
			GuildSync:SendData(true)
		elseif message:sub(1, 5) == "PART:" then
			ReceivePart(message, sender)
		else
			HandleData(message, sender)
		end
	end
end)
