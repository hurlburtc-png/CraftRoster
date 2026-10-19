local ADDON_NAME, CraftRoster = ...

local Requests = {}
CraftRoster.Requests = Requests

local pending = nil
local AttachMaterials
local tradeSession, lastTradeSession
local tradeCancel, mailCancel

local PREFIX = "CRAFTROSTER"
local requestSequence = 0

local function Encode(value)
	return value:gsub("[%%:;|]", function(char) return ("%%%02X"):format(char:byte()) end)
end

local function Decode(value)
	return value:gsub("%%(%x%x)", function(hex) return string.char(tonumber(hex, 16)) end)
end

local function Normalize(name)
	if type(name) ~= "string" then return "" end
	if name ~= "" and not name:find("-", 1, true) then name = name .. "-" .. (GetRealmName() or "") end
	return name:lower():gsub("%s", "")
end

local function CleanTarget(target)
	target = target:match("^%s*(.-)%s*$")
	local name, realm = target:match("^([^%-]+)%-(.+)$")
	if name and realm then target = name .. "-" .. realm:gsub("%s", "") end
	return target
end

local function GetRecipe(recipeID)
	return CraftRosterDB.recipes and CraftRosterDB.recipes[recipeID]
end

local function GetMaterials(recipeID)
	local recipe = GetRecipe(recipeID)
	local materials = recipe and recipe.materials
	if type(materials) ~= "table" then return {} end
	for _, material in ipairs(materials) do
		if type(material) ~= "table" or type(material.name) ~= "string"
			or type(material.count) ~= "number" or material.count <= 0
			or material.count > 1000000 or material.count ~= math.floor(material.count) then return {} end
	end
	return materials
end

local function PlayerMaterials(recipeID, target)
	if CraftRoster.ShoppingList then return CraftRoster.ShoppingList:GetPlayerMaterials(recipeID, target) end
	return GetMaterials(recipeID)
end

local function CopyMaterials(materials)
	local copy, byKey = {}, {}
	for _, material in ipairs(materials) do
		local key = material.itemID or material.name
		local saved = byKey[key]
		if saved then saved.count = saved.count + material.count; saved.remaining = saved.count
		else
			saved = { name = material.name, count = material.count, remaining = material.count, itemID = material.itemID }
			byKey[key] = saved; table.insert(copy, saved)
		end
	end
	return copy
end

local function SendAddonData(message)
	if not CraftRosterDB.settings.enabled or #message > 255 then return false end
	if C_ChatInfo and C_ChatInfo.AreOutgoingAddonChatMessagesRestricted
		and C_ChatInfo.AreOutgoingAddonChatMessagesRestricted() then
		print("|cffff0000CraftRoster|r: addon chat is restricted; status not sent.")
		return false
	end
	if C_ChatInfo and C_ChatInfo.InChatMessagingLockdown
		and C_ChatInfo.InChatMessagingLockdown() then
		print("|cffff0000CraftRoster|r: chat is in lockdown; status not sent.")
		return false
	end
	if IsInGuild and not IsInGuild() then return false end
	local send = C_ChatInfo and C_ChatInfo.SendAddonMessage or SendAddonMessage
	if type(send) == "function" then
		local result = send(PREFIX, message, "GUILD")
		if result == false then return false end
		local success = Enum and Enum.SendAddonMessageResult and Enum.SendAddonMessageResult.Success
		return result == nil or result == true or success == nil or result == success
	end
	return false
end

local function GetNumSlots(bag)
	if C_Container and C_Container.GetContainerNumSlots then
		return C_Container.GetContainerNumSlots(bag)
	end
	return GetContainerNumSlots and GetContainerNumSlots(bag) or 0
end

local function GetItemLink(bag, slot)
	if C_Container and C_Container.GetContainerItemLink then
		return C_Container.GetContainerItemLink(bag, slot)
	end
	return GetContainerItemLink and GetContainerItemLink(bag, slot)
end

local function LogRequest(recipeID, target, mode, requestID)
	CraftRosterDB.requests = CraftRosterDB.requests or {}
	local recipe = GetRecipe(recipeID)
	table.insert(CraftRosterDB.requests, 1, {
		id = requestID,
		recipe = recipe and recipe.name or "Unknown recipe",
		target = target,
		mode = mode,
		status = "requested",
		at = time(),
	})
	if #CraftRosterDB.requests > 50 then
		table.remove(CraftRosterDB.requests)
	end
end

local function CreateCancelButton(parent, key)
	local button = CreateFrame("Button", "CraftRosterCancel" .. key, parent, "UIPanelCloseButton")
	button:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -28, -2)
	button:SetScript("OnClick", function() Requests:Cancel() end)
	button:Hide()
	return button
end

function Requests:Cancel()
	pending = nil
	tradeSession, lastTradeSession = nil, nil
	if tradeCancel then tradeCancel:Hide() end
	if mailCancel then mailCancel:Hide() end
	print("|cff00ff00CraftRoster|r: auto-fill request cancelled.")
end

function Requests:NextWhisper()
	if not self.whisperDrafts or #self.whisperDrafts == 0 then return false end
	local text = self.whisperDrafts[1]
	if type(ChatFrame_SendTell) == "function" and type(ChatEdit_ChooseBoxForSend) == "function" then
		ChatFrame_SendTell(self.whisperTarget)
		local edit = ChatEdit_ChooseBoxForSend()
		if edit then
			edit:SetAttribute("chatType", "WHISPER"); edit:SetAttribute("tellTarget", self.whisperTarget)
			edit:SetText(text); edit:SetFocus()
			table.remove(self.whisperDrafts, 1)
			return true
		end
	end
	if type(ChatFrame_OpenChat) == "function" then
		-- The portable signature takes text and frame, not chat type/recipient arguments.
		ChatFrame_OpenChat("/w " .. self.whisperTarget .. " " .. text, DEFAULT_CHAT_FRAME)
		table.remove(self.whisperDrafts, 1)
		return true
	end
	print("|cffff0000CraftRoster|r: this client cannot open a whisper draft.")
	return false
end

function Requests:PrepareWhisper(recipeID, target)
	local recipe = GetRecipe(recipeID)
	if not recipe then return end
	local name = recipe.name or ("recipe " .. recipeID)
	if #name > 100 then name = "recipe " .. recipeID end
	local prefix = "CraftRoster: Could you craft " .. name .. "? Materials: "
	local limit = math.max(80, 255 - #("/w " .. target .. " "))
	local materials = CopyMaterials(GetMaterials(recipeID))
	local playerCounts = {}
	for _, material in ipairs(PlayerMaterials(recipeID, target)) do playerCounts[material.itemID or material.name] = material.count end
	local drafts, parts = {}, {}
	for _, material in ipairs(materials) do
		local text = ("%dx %s"):format(material.count, material.name)
		local ownCount = playerCounts[material.itemID or material.name] or 0
		if ownCount < material.count then text = text .. (" (I bring %d; crafter provides %d)"):format(ownCount, material.count - ownCount) end
		if #prefix + #table.concat(parts, ", ") + #text + 4 > limit and #parts > 0 then
			table.insert(drafts, prefix .. "[" .. table.concat(parts, ", ") .. "]")
			prefix, parts = "CraftRoster materials (continued): ", {}
		end
		if #prefix + #text + 2 > limit then
			print("|cffff0000CraftRoster|r: a material name exceeds the whisper limit. Check the shopping list.")
			return
		end
		table.insert(parts, text)
	end
	if #parts == 0 then parts[1] = "Materials not recorded; please confirm with the crafter" end
	table.insert(drafts, prefix .. "[" .. table.concat(parts, ", ") .. "]")
	self.whisperDrafts, self.whisperTarget = drafts, target
	self:NextWhisper()
	if #drafts > 0 then print("|cff00ff00CraftRoster|r: /crwhisper opens the next materials draft. Press Enter to send each whisper.") end
end

SLASH_CRAFTROSTERWHISPER1 = "/crwhisper"
SlashCmdList["CRAFTROSTERWHISPER"] = function() Requests:NextWhisper() end

function Requests:WhisperPlayer(recipeID, target)
	if #GetMaterials(recipeID) > 0 then self:StartTradeRequest(recipeID, target)
	else self:RequestCraft(recipeID, target) end
end

function Requests:MailPlayer(recipeID, target)
	if not CraftRosterDB.settings.enabled or type(target) ~= "string" then return end
	target = CleanTarget(target)
	if not target:match("^[^%s:|%-]+%-[^%s:|]+$") then
		print("|cffff0000CraftRoster|r: select a crafter or enter their full Name-Realm before preparing mail.")
		return
	end
	if #GetMaterials(recipeID) > 0 then self:StartMailRequest(recipeID, target); return end
	if not GetRecipe(recipeID) then return end
	pending = { mode = "mail", target = Normalize(target), targetName = target, recipeID = recipeID, materials = {} }
	self:RequestCraft(recipeID, target, "mail")
	if MailFrame and MailFrame:IsShown() then AttachMaterials("mail") end
	print("|cff00ff00CraftRoster|r: mail recipient and subject prepared; open a mailbox. Materials are not recorded yet.")
end

function Requests:RequestCraft(recipeID, target, mode)
	if not CraftRosterDB.settings.enabled or type(target) ~= "string" or target:match("^%s*$") then return end
	local recipe = GetRecipe(recipeID)
	if not recipe then return end
	target = CleanTarget(target)
	requestSequence = requestSequence + 1
	local requestID = ("%d:%s:%d:%d"):format(recipeID, Normalize(UnitName("player")), time(), requestSequence)
	local recipeName = recipe.name or ("Recipe " .. recipeID)
	LogRequest(recipeID, target, mode or "craft", requestID)
	local sent = SendAddonData(("ORDER:%d:%s:%s:%s"):format(recipeID, Encode(requestID), Encode(target), Encode(recipeName)))
	if mode ~= "mail" then self:PrepareWhisper(recipeID, target) end
	print(("|cff00ff00CraftRoster|r: craft request for %s %s."):format(recipeName, sent and "sent" or "logged locally; guild delivery unavailable"))
	return requestID
end

function Requests:StartTradeRequest(recipeID, target)
	if not CraftRosterDB.settings.enabled or type(target) ~= "string" or target:match("^%s*$") then return end
	local recipe = GetRecipe(recipeID)
	if not recipe then return end

	local materials = GetMaterials(recipeID)
	if #materials == 0 then
		print("|cffff0000CraftRoster|r: no material data saved for this recipe yet. Open the crafting window for it once to record materials.")
		return
	end


	pending = {
		mode = "trade",
		target = Normalize(target),
		targetName = target,
		recipeID = recipeID,
		materials = CopyMaterials(PlayerMaterials(recipeID, target)),
	}

	pending.requestID = self:RequestCraft(recipeID, target, "trade")
	print(("|cff00ff00CraftRoster|r: trade auto-load armed for %s. Open a trade with them to load materials."):format(target))
end

function Requests:StartMailRequest(recipeID, target)
	if not CraftRosterDB.settings.enabled or type(target) ~= "string" or target:match("^%s*$") then return end
	local recipe = GetRecipe(recipeID)
	if not recipe then return end
	target = CleanTarget(target)

	if not target:match("^[^%s:|%-]+%-[^%s:|]+$") then
		print("|cffff0000CraftRoster|r: enter the full character name including server, for example: Bob-Illidan")
		return
	end

	local materials = GetMaterials(recipeID)
	if #materials == 0 then
		print("|cffff0000CraftRoster|r: no material data saved for this recipe yet. Open the crafting window for it once to record materials.")
		return
	end


	pending = {
		mode = "mail",
		target = Normalize(target),
		targetName = target,
		recipeID = recipeID,
		materials = CopyMaterials(PlayerMaterials(recipeID, target)),
	}

	self:RequestCraft(recipeID, target, "mail")
	if MailFrame and MailFrame:IsShown() then AttachMaterials("mail") end
	print(("|cff00ff00CraftRoster|r: mail auto-fill armed for %s. Open a mailbox to load materials."):format(target))
end

-- Safety: automation only fills the trade/mail window.
-- It never calls AcceptTrade() or SendMail(). The user must confirm both.
AttachMaterials = function(mode)
	if not pending or pending.mode ~= mode or not CraftRosterDB.settings.enabled then return end
	if mode == "mail" then
		if not pending.mailPrepared then
			pending.materials = CopyMaterials(PlayerMaterials(pending.recipeID, pending.targetName))
			pending.mailPrepared = true
		end
		local recipe = GetRecipe(pending.recipeID)
		if SendMailNameEditBox then SendMailNameEditBox:SetText(pending.targetName) end
		if SendMailSubjectEditBox then SendMailSubjectEditBox:SetText("CraftRoster: " .. (recipe and recipe.name or "recipe")) end
	end
	if #pending.materials == 0 then return end
	local getInfo = C_Container and C_Container.GetContainerItemInfo or GetContainerItemInfo
	local split = C_Container and C_Container.SplitContainerItem or SplitContainerItem
	local slotInfo, click
	if mode == "trade" then slotInfo, click = GetTradePlayerItemInfo, ClickTradeButton
	else slotInfo, click = GetSendMailItem, ClickSendMailItemButton end
	local pickup = C_Container and C_Container.PickupContainerItem or PickupContainerItem
	if not getInfo or not slotInfo or not click or not pickup or not CursorHasItem then
		print("|cffff0000CraftRoster|r: this client lacks the APIs needed for exact material auto-fill.")
		return
	end
	if CursorHasItem() then return end

	local used = {}
	local function EmptySlot()
		for slot = 1, (mode == "trade" and 6 or 12) do
			if not used[slot] and not slotInfo(slot) then return slot end
		end
	end
	local byID, byName = {}, {}
	for _, material in ipairs(pending.materials) do
		if material.remaining > 0 then
			if material.itemID then byID[material.itemID] = material else byName[material.name] = material end
		end
	end
	if not next(byID) and not next(byName) then return end
	-- Walk inventory once, regardless of the number of reagent types.
	for bag = 0, (NUM_BAG_SLOTS or 4) do
		for slot = 1, GetNumSlots(bag) do
			local link = GetItemLink(bag, slot)
			local material = link and (byID[tonumber(link:match("item:(%d+)")) or 0] or byName[link:match("%[(.-)%]") or ""])
			if material and material.remaining > 0 then
				local info, count, locked = getInfo(bag, slot)
				if type(info) == "table" then count, locked = info.stackCount, info.isLocked end
				local targetSlot = EmptySlot()
				if not targetSlot then return end
				if not locked and type(count) == "number" and count > 0 then
					local amount = math.min(count, material.remaining)
					if amount == count then pickup(bag, slot)
					elseif split then split(bag, slot, amount)
					else return end
					if not CursorHasItem() then return end
					click(targetSlot)
					if CursorHasItem() then return end
					used[targetSlot] = true
					if mode == "trade" and tradeSession then tradeSession.offered = tradeSession.offered + amount end
					material.remaining = material.remaining - amount
				end
			end
		end
	end
end

StaticPopupDialogs["CRAFTROSTER_TRADE_MATS"] = {
	text = "Enter the character to whisper and trade materials with:",
	button1 = "Prepare Whisper",
	button2 = "Cancel",
	OnAccept = function(self)
		local target = (self.editBox or self.EditBox):GetText()
		if target and target ~= "" then
			Requests:WhisperPlayer(self.data, target)
		end
	end,
	EditBoxOnEnterPressed = function(self)
		local target = self:GetText()
		if target and target ~= "" then
			Requests:WhisperPlayer(self:GetParent().data, target)
		end
		self:GetParent():Hide()
	end,
	hasEditBox = true,
	timeout = 0,
	whileDead = true,
	hideOnEscape = true,
}

StaticPopupDialogs["CRAFTROSTER_MAIL_MATS"] = {
	text = "Enter the FULL character name including server, for example: Bob-Illidan",
	button1 = "Prepare Mail",
	button2 = "Cancel",
	OnAccept = function(self)
		local target = (self.editBox or self.EditBox):GetText()
		if target and target ~= "" then
			Requests:MailPlayer(self.data, target)
		end
	end,
	EditBoxOnEnterPressed = function(self)
		local target = self:GetText()
		if target and target ~= "" then
			Requests:MailPlayer(self:GetParent().data, target)
		end
		self:GetParent():Hide()
	end,
	hasEditBox = true,
	timeout = 0,
	whileDead = true,
	hideOnEscape = true,
}

local function CreateRequestButton(parent, text, dialog, point, relativeTo, relativePoint, x, y)
	local button = CreateFrame("Button", nil, parent, "GameMenuButtonTemplate")
	button:SetSize(170, 26)
	button:SetPoint(point, relativeTo, relativePoint, x or 0, y or -8)
	button:SetText(text)
	button:SetScript("OnClick", function()
		local recipe = CraftRoster.Directory and CraftRoster.Directory.selectedRecipe
		if not recipe then
			print("|cffff0000CraftRoster|r: select a recipe first.")
			return
		end
		local target = CraftRoster.Directory.selectedCrafter
		if target then
			if dialog == "CRAFTROSTER_TRADE_MATS" then Requests:WhisperPlayer(recipe.id, target)
			else Requests:MailPlayer(recipe.id, target) end
			return
		end
		StaticPopup_Hide(dialog)
		StaticPopup_Show(dialog, nil, nil, recipe.id)
	end)
	return button
end

local function AddDirectoryButtons()
	local directory = CraftRoster.Directory
	if not directory or not directory.frame then return end

	local tab = directory.frame.ProfessionsTab
	if tab.CraftRosterTradeButton then return end

	tab.CraftRosterTradeButton = CreateRequestButton(tab.Details, "Whisper Player", "CRAFTROSTER_TRADE_MATS", "BOTTOMLEFT", tab.Details, "BOTTOMLEFT", 12, 12)
	tab.CraftRosterMailButton = CreateRequestButton(tab.Details, "Mail Player", "CRAFTROSTER_MAIL_MATS", "BOTTOMRIGHT", tab.Details, "BOTTOMRIGHT", -12, 12)

	local refreshButton = CreateFrame("Button", nil, tab, "GameMenuButtonTemplate")
	refreshButton:SetSize(90, 22)
	refreshButton:SetPoint("TOPLEFT", tab, "TOPLEFT", 170, -48)
	refreshButton:SetText("Refresh")
	refreshButton:SetScript("OnClick", function()
		if CraftRoster.Directory then CraftRoster.Directory:RequestRoster() end
		if CraftRoster.GuildSync then
			CraftRoster.GuildSync:SyncNow()
		end
		if CraftRoster.Directory then
			CraftRoster.Directory:RefreshIfVisible()
		end
	end)
	tab.CraftRosterRefreshButton = refreshButton

	local favoriteButton = CreateFrame("Button", nil, tab.Details, "GameMenuButtonTemplate")
	favoriteButton:SetSize(120, 26)
	favoriteButton:SetPoint("BOTTOMLEFT", tab.Details, "BOTTOMLEFT", 12, 46)
	favoriteButton:SetText("Favorite")
	favoriteButton:SetScript("OnClick", function()
		local recipe = CraftRoster.Directory and CraftRoster.Directory.selectedRecipe
		if not recipe then
			print("|cffff0000CraftRoster|r: select a recipe first.")
			return
		end
		CraftRosterDB.favorites = CraftRosterDB.favorites or {}
		CraftRosterDB.favorites[recipe.id] = not CraftRosterDB.favorites[recipe.id] or nil
		CraftRoster.Directory.professionCache = nil
		CraftRoster.Directory:RefreshProfessions()
		local state = CraftRosterDB.favorites[recipe.id] and "added to" or "removed from"
		print(("|cff00ff00CraftRoster|r: %s %s favorites."):format(recipe.name, state))
	end)
	tab.CraftRosterFavoriteButton = favoriteButton
	local shoppingButton = CreateFrame("Button", nil, tab.Details, "GameMenuButtonTemplate")
	shoppingButton:SetSize(120, 26)
	shoppingButton:SetPoint("BOTTOMRIGHT", tab.Details, "BOTTOMRIGHT", -12, 46)
	shoppingButton:SetText("Shopping List")
	shoppingButton:SetScript("OnClick", function()
		local recipe = directory.selectedRecipe
		if recipe and CraftRoster.ShoppingList then CraftRoster.ShoppingList:Open(recipe.id)
		else print("|cff00ff00CraftRoster|r: select a recipe first.") end
	end)
	tab.CraftRosterShoppingButton = shoppingButton
	local function ResizeActions()
		local width = math.max(90, (tab.Details:GetWidth() - 36) / 2)
		tab.CraftRosterTradeButton:SetWidth(width)
		tab.CraftRosterMailButton:SetWidth(width)
		tab.CraftRosterFavoriteButton:SetWidth(width)
		tab.CraftRosterShoppingButton:SetWidth(width)
	end
	tab.Details:HookScript("OnSizeChanged", ResizeActions)
	ResizeActions()

	local credit = directory.frame:CreateFontString(nil, "OVERLAY", "GameFontDisable")
	credit:SetPoint("BOTTOMLEFT", directory.frame, "BOTTOMLEFT", 8, 4)
	credit:SetText("Made by Triggles")
	credit:SetAlpha(0.5)
end

SLASH_CRAFTROSTERREQUESTS1 = "/crrequests"
SlashCmdList["CRAFTROSTERREQUESTS"] = function()
	local requests = CraftRosterDB.requests or {}
	if #requests == 0 then
		print("|cff00ff00CraftRoster|r: no crafting requests logged yet.")
		return
	end

	print("|cff00ff00CraftRoster|r recent crafting requests:")
	for i, request in ipairs(requests) do
		if i > 10 then break end
		local materialState = request.materialStatus and (" [materials: " .. request.materialStatus:gsub("_", " ") .. (request.autoFillPartial and "; partial auto-fill" or "") .. "]") or ""
		print(("%s → %s (%s) [%s] (%s)%s"):format(request.recipe, request.target, request.mode, request.status, request.id, materialState))
	end
	print("Update a request with: /crstatus <id> <accepted|completed>")
end

SLASH_CRAFTROSTERSTATUS1 = "/crstatus"
SlashCmdList["CRAFTROSTERSTATUS"] = function(msg)
	local requestID, status = (msg or ""):match("^(%S+)%s+(%S+)$")
	if not requestID or not status then
		print("Usage: /crstatus <requestID> <accepted|completed>")
		return
	end

	status = status:lower()
	if status ~= "accepted" and status ~= "completed" then
		print("|cffff0000CraftRoster|r: status must be accepted or completed.")
		return
	end

	local requests = CraftRosterDB.requests or {}
	for _, request in ipairs(requests) do
		if request.id == requestID then
			if request.status == "completed" and status ~= "completed" then return end
			request.status = status
			local synced = SendAddonData("RSTAT:" .. requestID .. ":" .. status)
			print(("|cff00ff00CraftRoster|r: request %s marked %s (%s)."):format(requestID, status, synced and "synced to guild" or "saved locally; sync unavailable"))
			return
		end
	end

	print("|cffff0000CraftRoster|r: request not found: " .. requestID)
end

SLASH_CRAFTROSTERFAVORITES1 = "/crfavorites"
SlashCmdList["CRAFTROSTERFAVORITES"] = function()
	local favorites = CraftRosterDB.favorites or {}
	local count = 0
	print("|cff00ff00CraftRoster|r favorite recipes:")
	for recipeID in pairs(favorites) do
		local recipe = CraftRosterDB.recipes and CraftRosterDB.recipes[recipeID]
		if recipe then
			count = count + 1
			print(("%s (%s)"):format(recipe.name, recipe.profession))
		end
	end
	if count == 0 then
		print("No favorites saved yet. Select a recipe and click Favorite.")
	end
end

SLASH_CRAFTROSTERDISCORD1 = "/crdiscord"
SlashCmdList["CRAFTROSTERDISCORD"] = function()
	local recipes = {}
	for recipeID, recipe in pairs(CraftRosterDB.recipes or {}) do
		local crafters = 0
		for _, character in pairs(CraftRosterDB.characters or {}) do
			if character.recipes and character.recipes[recipeID] then
				crafters = crafters + 1
			end
		end
		if crafters > 0 then
			table.insert(recipes, {
				profession = recipe.profession or "Unknown",
				name = recipe.name or ("Recipe " .. recipeID),
				crafters = crafters,
			})
		end
	end

	table.sort(recipes, function(a, b)
		if a.profession ~= b.profession then return a.profession < b.profession end
		return a.name < b.name
	end)

	print("|cff00ff00CraftRoster|r Discord export (copy from chat):")
	print("**Guild Crafting Directory**")
	local lastProfession = nil
	for _, recipe in ipairs(recipes) do
		if recipe.profession ~= lastProfession then
			print(("**%s**"):format(recipe.profession))
			lastProfession = recipe.profession
		end
		print(("- %s (%d crafter%s)"):format(recipe.name, recipe.crafters, recipe.crafters == 1 and "" or "s"))
	end
end

local function MaterialStatus(session, status)
	if not session then return end
	for _, request in ipairs(CraftRosterDB.requests or {}) do
		if request.id == session.requestID then request.materialStatus = status; request.autoFillPartial = session.partial end
	end
end

local function TradeSucceeded()
	local session = tradeSession or lastTradeSession
	if not session or (session.closedAt and time() - session.closedAt > 2) then return end
	session.succeeded = true
	MaterialStatus(session, "trade_succeeded")
	if pending and pending.requestID == session.requestID then pending = nil end
	-- This confirms a trade, not completion or delivery of the crafted item.
end

local function TradeCancelled()
	local session = tradeSession or lastTradeSession
	if not session or session.succeeded or (session.closedAt and time() - session.closedAt > 2) then return end
	session.cancelled = true
	MaterialStatus(session, "cancelled")
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("TRADE_SHOW")
frame:RegisterEvent("TRADE_CLOSED")
frame:RegisterEvent("TRADE_REQUEST_CANCEL")
frame:RegisterEvent("UI_INFO_MESSAGE")
frame:RegisterEvent("UI_ERROR_MESSAGE")
frame:RegisterEvent("MAIL_SHOW")
frame:RegisterEvent("MAIL_CLOSED")
frame:RegisterEvent("CHAT_MSG_ADDON")

frame:SetScript("OnEvent", function(_, event, ...)
	local arg1 = ...
	local prefix, message, channel, sender = ...
	if event == "ADDON_LOADED" and arg1 == ADDON_NAME then
		if TradeFrame then
			tradeCancel = CreateCancelButton(TradeFrame, "Trade")
		end
		if MailFrame then
			mailCancel = CreateCancelButton(MailFrame, "Mail")
		end

		local originalToggle = CraftRoster.Directory.Toggle
		function CraftRoster.Directory:Toggle(...)
			if not self.frame then self:Initialize() end
			AddDirectoryButtons()
			return originalToggle(self, ...)
		end

		local originalPanelToggle = CraftRoster.Panel.Toggle
		function CraftRoster.Panel:Toggle(...)
			if not self.frame then self:Initialize() end
			if self.frame and not self.credit then
				self.credit = self.frame:CreateFontString(nil, "OVERLAY", "GameFontDisable")
				self.credit:SetPoint("BOTTOMLEFT", self.frame, "BOTTOMLEFT", 8, 4)
				self.credit:SetText("Made by Triggles")
				self.credit:SetAlpha(0.5)
			end
			return originalPanelToggle(self, ...)
		end

	elseif event == "TRADE_SHOW" then
		if not tradeCancel and TradeFrame then tradeCancel = CreateCancelButton(TradeFrame, "Trade") end
		local name, realm
		if UnitFullName then name, realm = UnitFullName("NPC") else name, realm = UnitName("NPC") end
		local partner = name and (name .. (realm and realm ~= "" and "-" .. realm or ""))
		lastTradeSession = nil
		if pending and pending.mode == "trade" and Normalize(partner) == pending.target then
			if not tradeSession then
				pending.materials = CopyMaterials(PlayerMaterials(pending.recipeID, pending.targetName))
				tradeSession = {requestID=pending.requestID, offered=0}
			end
			AttachMaterials("trade")
			local partial = false
			for _, material in ipairs(pending.materials) do if material.remaining > 0 then partial = true end end
			tradeSession.partial = partial
			MaterialStatus(tradeSession, tradeSession.offered > 0 and "offered" or "not_offered")
			if partial then print("|cff00ff00CraftRoster|r: only available materials were offered. Review the missing amounts before confirming the trade.") end
			if tradeCancel then tradeCancel:Show() end
		end

	elseif event == "TRADE_CLOSED" then
		if tradeSession then
			tradeSession.closedAt = time()
			if not tradeSession.succeeded and not tradeSession.cancelled then MaterialStatus(tradeSession, "trade_closed_unconfirmed") end
			lastTradeSession, tradeSession = tradeSession, nil
		end
		if tradeCancel then tradeCancel:Hide() end
		-- On an unconfirmed close, keep the request armed so the same player can retry.
		-- A later explicit success message disarms it; a close alone never completes it.

	elseif event == "TRADE_REQUEST_CANCEL" then
		TradeCancelled()

	elseif event == "UI_INFO_MESSAGE" or event == "UI_ERROR_MESSAGE" then
		local code, message = ...
		if type(code) == "string" then message = code end
		if (ERR_TRADE_COMPLETE and message == ERR_TRADE_COMPLETE)
			or (LE_GAME_ERR_TRADE_COMPLETE and code == LE_GAME_ERR_TRADE_COMPLETE) then TradeSucceeded()
		elseif ERR_TRADE_CANCELLED and message == ERR_TRADE_CANCELLED then TradeCancelled() end

	elseif event == "MAIL_SHOW" then
		if not mailCancel and MailFrame then mailCancel = CreateCancelButton(MailFrame, "Mail") end
		if pending and pending.mode == "mail" then
			AttachMaterials("mail")
			if mailCancel then mailCancel:Show() end
		end

	elseif event == "MAIL_CLOSED" then
		if pending and pending.mode == "mail" then
			Requests:Cancel()
		end

	elseif event == "CHAT_MSG_ADDON" and prefix == PREFIX and channel == "GUILD" then
		if not CraftRosterDB or not CraftRosterDB.settings.enabled or type(sender) ~= "string" or sender == "" or type(message) ~= "string" or #message > 255 then return end

		local recipeID, id, target, recipeName = message:match("^ORDER:(%d+):([^:]+):([^:]+):([^:]*)$")
		if recipeID and tonumber(recipeID) > 0 and #message <= 255
			and Normalize(Decode(target)) == Normalize(UnitName("player"))
			and Normalize(sender) ~= Normalize(UnitName("player")) then
			id = Decode(id)
			for _, request in ipairs(CraftRosterDB.requests or {}) do if request.id == id then return end end
			CraftRosterDB.requests = CraftRosterDB.requests or {}
			table.insert(CraftRosterDB.requests, 1, { id = id, recipe = Decode(recipeName), recipeID = tonumber(recipeID),
				target = sender, mode = "incoming", status = "requested", at = time() })
			if #CraftRosterDB.requests > 50 then table.remove(CraftRosterDB.requests) end
			print("|cff00ff00CraftRoster|r: new crafting request. Use /crrequests to view it.")
			return
		end
		local requestID, status = message:match("^RSTAT:(.+):(%a+)$")
		if requestID and (status == "accepted" or status == "completed") then
			for _, request in ipairs(CraftRosterDB.requests or {}) do
				if request.id == requestID and Normalize(request.target) == Normalize(sender)
					and (request.status ~= "completed" or status == "completed") then
					request.status = status
					print(("|cff00ff00CraftRoster|r: request for %s is now %s."):format(request.recipe, status))
					break
				end
			end
		end
	end
end)

