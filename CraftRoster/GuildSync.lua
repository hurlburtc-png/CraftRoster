local ADDON_NAME, CraftRoster = ...

local GuildSync = {}
CraftRoster.GuildSync = GuildSync

local PREFIX = "CRAFTROSTER"
local lastRequest = 0
local lastSend = 0
local REQUEST_THROTTLE = 30
local SEND_THROTTLE = 10

local function GetCharacterKey()
	return UnitName("player") .. "-" .. (GetRealmName() or "")
end

local function SendAddonData(message)
	if C_ChatInfo and C_ChatInfo.SendAddonMessage then
		C_ChatInfo.SendAddonMessage(PREFIX, message, "GUILD")
	elseif SendAddonMessage then
		SendAddonMessage(PREFIX, message, "GUILD")
	end
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
		table.insert(recipes, ("%d:%d"):format(recipeID, data.learnedAt or 0))
	end

	return table.concat(professions, ";") .. "|" .. table.concat(recipes, ";")
end

local function DeserializeCharacter(payload)
	local professionPart, recipePart = payload:match("^(.-)|(.*)$")
	local professions, recipes = {}, {}

	for entry in (professionPart or ""):gmatch("[^;]+") do
		local name, skill, max, rank = entry:match("^(.-):(%d+):(%d+):(%d+)")
		if name then
			professions[name] = {
				skill = tonumber(skill),
				max = tonumber(max),
				rank = tonumber(rank),
			}
		end
	end

	for entry in (recipePart or ""):gmatch("[^;]+") do
		local recipeID, learnedAt = entry:match("^(%d+):(%d+)")
		if recipeID then
			recipes[tonumber(recipeID)] = { learnedAt = tonumber(learnedAt) }
		end
	end

	return professions, recipes
end

function GuildSync:RequestSync()
	if time() - lastRequest < REQUEST_THROTTLE then return end
	lastRequest = time()
	SendAddonData("REQ")
end

function GuildSync:SyncNow()
	lastRequest = 0
	GuildSync:RequestSync()
	print("|cff00ff00CraftRoster|r: requesting guild recipe sync.")
end

function GuildSync:SendData()
	if time() - lastSend < SEND_THROTTLE then return end
	lastSend = time()

	local payload = SerializeCharacter()
	if not payload then return end

	SendAddonData(("DATA:%s:%d:%s"):format(GetCharacterKey(), time(), payload))
end

function GuildSync:GetStatusText()
	local synced = 0
	for _, character in pairs(CraftRosterDB.characters or {}) do
		if character.lastSync then synced = synced + 1 end
	end

	local lastSync = CraftRosterDB.lastGuildSync
	local timeText = lastSync and date("%l:%M %p", lastSync) or "Never"
	return ("Guild sync: %d crafter(s) · last sync: %s"):format(synced, timeText)
end

local function MergeCharacter(characterKey, updated, payload)
	local existing = CraftRosterDB.characters[characterKey]
	if existing and (existing.lastSync or 0) >= updated then return end

	local professions, recipes = DeserializeCharacter(payload)
	CraftRosterDB.characters[characterKey] = {
		recipes = recipes,
		professions = professions,
		lastSync = updated,
	}

	CraftRosterDB.lastGuildSync = time()

	if CraftRoster.Directory then
		CraftRoster.Directory:InvalidateIndex()
	end
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:RegisterEvent("CHAT_MSG_ADDON")
frame:RegisterEvent("NEW_RECIPE_LEARNED")

frame:SetScript("OnEvent", function(_, event, arg1, prefix, message)
	if event == "ADDON_LOADED" and arg1 == ADDON_NAME then
		if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
			C_ChatInfo.RegisterAddonMessagePrefix(PREFIX)
		elseif RegisterAddonMessagePrefix then
			RegisterAddonMessagePrefix(PREFIX)
		end

	elseif event == "PLAYER_ENTERING_WORLD" then
		-- One lightweight sync request per login; throttled and memory-cheap.
		GuildSync:RequestSync()

	elseif event == "NEW_RECIPE_LEARNED" then
		GuildSync:SendData()

	elseif event == "CHAT_MSG_ADDON" and prefix == PREFIX then
		if message == "REQ" then
			GuildSync:SendData()

		elseif message:sub(1, 5) == "DATA:" then
			local characterKey, updated, payload = message:match("^DATA:(.-):(%d+):(.*)$")
			if characterKey and payload then
				MergeCharacter(characterKey, tonumber(updated) or 0, payload)
			end
		end
	end
end)
