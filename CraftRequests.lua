local ADDON_NAME, CraftRoster = ...

local Requests = {}
CraftRoster.Requests = Requests

local pending = nil
local AttachMaterials
local CaptureTradeOffer
local SaveTradeProgress
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

local function OwnRequest(request)
	return request.mode~="incoming" and (not request.ownerCharacter or request.ownerCharacter==Normalize(UnitName("player")))
end

local function GetRecipe(recipeID)
	return CraftRosterDB.recipes and CraftRosterDB.recipes[recipeID]
end

local function GetQuantity(recipeID)
	return CraftRoster.ShoppingList and CraftRoster.ShoppingList:GetQuantity(recipeID) or 1
end

local function GetMaterials(recipeID, quantity)
	local recipe = GetRecipe(recipeID)
	local materials = recipe and CraftRoster.RecipeSources and CraftRoster.RecipeSources:GetMaterials(recipeID) or (recipe and recipe.materials)
	if type(materials) ~= "table" then return {} end
	for _, material in ipairs(materials) do
		if type(material) ~= "table" or type(material.name) ~= "string"
			or type(material.count) ~= "number" or material.count <= 0
			or material.count > 1000000 or material.count ~= math.floor(material.count) then return {} end
	end
	local scaled = {}
	for _, material in ipairs(materials) do
		table.insert(scaled, {name=material.name, itemID=material.itemID, count=material.count * (quantity or GetQuantity(recipeID))})
	end
	return scaled
end

local function PlayerMaterials(recipeID, target, quantity)
	if CraftRoster.ShoppingList then return CraftRoster.ShoppingList:GetPlayerMaterials(recipeID, target, quantity) end
	return GetMaterials(recipeID, quantity)
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
		CraftRoster:WarnChatRestricted()
		return false
	end
	if C_ChatInfo and C_ChatInfo.InChatMessagingLockdown
		and C_ChatInfo.InChatMessagingLockdown() then
		CraftRoster:WarnChatRestricted()
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

function Requests:SetIncomingStatus(requestID,customer,status)
	if status~="accepted" and status~="completed" and status~="declined" then return false end
	for _,request in ipairs(CraftRosterDB.requests or {}) do
		if request.id==requestID and request.mode=="incoming" and Normalize(request.target)==Normalize(customer) then
			request.status=status
			return SendAddonData("RSTAT:" .. requestID .. ":" .. status)
		end
	end
	if CraftRoster.WorkOrders and CraftRoster.WorkOrders:FindRequest(requestID,customer) then
		return SendAddonData("RSTAT:" .. requestID .. ":" .. status)
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

function Requests:TrimHistory()
	local history=CraftRosterDB.requests or {}
	for index=#history,1,-1 do
		if #history<=50 then break end
		local request=history[index]
		local keep=request.deliveryPending or request.tradeUnresolved
		if request.materialLedger and not request.tradeAbandoned then
			for _,material in ipairs(request.materialLedger) do if material.remaining>0 then keep=true; break end end
		end
		if not keep then table.remove(history,index) end
	end
end

local function LogRequest(recipeID, target, mode, requestID)
	CraftRosterDB.requests = CraftRosterDB.requests or {}
	local recipe = GetRecipe(recipeID)
	table.insert(CraftRosterDB.requests, 1, {
		id = requestID,
		recipe = recipe and recipe.name or "Unknown recipe",
		recipeID = recipeID,
		quantity = GetQuantity(recipeID),
		ownerCharacter = Normalize(UnitName("player")),
		target = target,
		mode = mode,
		deliveryPending = mode == "trade",
		status = "requested",
		at = time(),
	})
	Requests:TrimHistory()
end

local function RequestRecord(requestID)
	for _, request in ipairs(CraftRosterDB.requests or {}) do
		if request.id == requestID and OwnRequest(request) then return request end
	end
end

function Requests:GetTradeProgress(requestID)
	local request = RequestRecord(requestID)
	if not request or not request.materialLedger then return nil end
	local delivered, remaining, stacks = 0, 0, 0
	for _, material in ipairs(request.materialLedger) do
		delivered = delivered + material.count - material.remaining
		remaining = remaining + material.remaining
		if material.remaining > 0 then stacks = stacks + 1 end
	end
	return {delivered=delivered, remaining=remaining, typesRemaining=stacks, needsReview=request.tradeUnresolved == true}
end

function Requests:GetDeliveredMaterials(recipeID,target,quantity)
	for _,request in ipairs(CraftRosterDB.requests or {}) do
		if OwnRequest(request) and request.mode=="trade" and not request.tradeAbandoned and request.recipeID==recipeID and Normalize(request.target)==Normalize(target)
			and request.quantity==quantity and request.materialLedger then
			local delivered={}
			for _,material in ipairs(request.materialLedger) do delivered[material.itemID or material.name]=math.max(0,material.count-material.remaining) end
			return delivered
		end
	end
	return {}
end

SaveTradeProgress = function(request)
	local record = request and RequestRecord(request.requestID)
	if record then record.materialLedger = request.materials; record.deliveryPending=nil end
	if CraftRoster.ShoppingList then CraftRoster.ShoppingList:ScheduleRefresh() end
end

local function CreateCancelButton(parent, key)
	local button = CreateFrame("Button", "CraftRosterCancel" .. key, parent, "UIPanelCloseButton")
	button:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -28, -2)
	button:SetScript("OnClick", function() Requests:Cancel() end)
	button:Hide()
	return button
end

function Requests:SetAutoLoadItems(enabled)
	CraftRosterDB.settings.autoLoadItems = enabled == true
	local tab = CraftRoster.Directory and CraftRoster.Directory.frame and CraftRoster.Directory.frame.ProfessionsTab
	if tab and tab.CraftRosterAutoLoad then tab.CraftRosterAutoLoad:SetChecked(enabled == true) end
end

function Requests:Cancel()
	pending = nil
	tradeSession, lastTradeSession = nil, nil
	if tradeCancel then tradeCancel:Hide() end
	if mailCancel then mailCancel:Hide() end
	print("|cff00ff00CraftRoster|r: auto-fill request cancelled.")
end

-- Cancel only this character's outstanding orders for the selected recipe/crafter.
-- Keep trade snapshots: a trade already accepted may still complete after this click.
function Requests:CancelCurrentRequests(recipeID, target)
	if not recipeID then return 0 end
	local count, unsynced, cancelled = 0, 0, {}
	for _, request in ipairs(CraftRosterDB.requests or {}) do
		if OwnRequest(request) and request.recipeID==recipeID and (not target or Normalize(request.target)==Normalize(target))
			and request.status~="completed" and request.status~="declined" and request.status~="cancelled" then
			request.status="cancelled"; request.tradeAbandoned=true; request.deliveryPending=nil
			request.closedAt=time(); cancelled[request.id]=true; count=count+1
			if not SendAddonData("RSTAT:" .. request.id .. ":cancelled") then unsynced=unsynced+1 end
		end
	end
	if pending and cancelled[pending.requestID] then pending=nil end
	if count>0 then
		self.whisperDrafts=nil; self.whisperTarget=nil
		if CraftRoster.WhisperComposer then CraftRoster.WhisperComposer:CancelRequests(cancelled) end
		if tradeCancel then tradeCancel:Hide() end
		if mailCancel then mailCancel:Hide() end
		if CraftRoster.ShoppingList then CraftRoster.ShoppingList:ScheduleRefresh() end
		print("|cff00ff00CraftRoster|r: cancelled " .. count .. " request(s). Already traded or mailed items are not returned.")
		if unsynced>0 then print("|cffffd100CraftRoster|r: cancellation saved locally; crafter update unavailable. Tell the crafter directly.") end
	else print("|cff00ff00CraftRoster|r: no outstanding requests for this selection.") end
	return count
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

-- Only use output-item IDs here: recipe IDs identify spells, not crafted items.
local function ChatItemLink(name, itemID, savedLink)
	if type(savedLink) == "string" and savedLink:find("|Hitem:", 1, true) then return savedLink end
	local getInfo = C_Item and C_Item.GetItemInfo or GetItemInfo
	if getInfo and itemID then
		local ok, _, link = pcall(getInfo, itemID)
		if ok and type(link) == "string" and link:find("|Hitem:", 1, true) then return link end
	end
	if type(itemID) == "number" and itemID > 0 then
		return "|cffffffff|Hitem:" .. itemID .. ":0:0:0:0:0:0:0|h[" .. name .. "]|h|r"
	end
	return name
end

function Requests:BuildWhisperDrafts(recipeID, target, quantity)
	quantity = quantity or GetQuantity(recipeID)
	local recipe = GetRecipe(recipeID)
	if not recipe then return end
	local name = recipe.name or ("recipe " .. recipeID)
	if #name > 100 then name = "recipe " .. recipeID end
	local outputID = type(recipe.itemLink) == "string" and tonumber(recipe.itemLink:match("item:(%d+)")) or recipe.itemID or (CraftRoster.RecipeSources and CraftRoster.RecipeSources:GetOutputItemID(recipeID))
	local prefix = "CraftRoster: Could you craft " .. (quantity > 1 and (quantity .. " crafts of ") or "") .. ChatItemLink(name, outputID, recipe.itemLink) .. "? Materials: "
	local limit = math.max(80, 255 - #("/w " .. target .. " "))
	local materials = CopyMaterials(GetMaterials(recipeID, quantity))
	local playerCounts = {}
	for _, material in ipairs(PlayerMaterials(recipeID, target, quantity)) do playerCounts[material.itemID or material.name] = material.count end
	local drafts, parts = {}, {}
	for _, material in ipairs(materials) do
		local text = ("%dx %s"):format(material.count, ChatItemLink(material.name, material.itemID))
		local ownCount = playerCounts[material.itemID or material.name] or 0
		if ownCount < material.count then text = text .. (" (I bring %d; crafter provides %d)"):format(ownCount, material.count - ownCount) end
		if #prefix + #table.concat(parts, ", ") + #text + 4 > limit and #parts > 0 then
			table.insert(drafts, prefix .. "[" .. table.concat(parts, ", ") .. "]")
			prefix, parts = "CraftRoster materials (continued): ", {}
		end
		if #prefix + #text + 2 > limit and #parts == 0 and prefix ~= "CraftRoster materials (continued): " then
			if #prefix > limit then
				print("|cffff0000CraftRoster|r: the item link exceeds the whisper limit. Check the shopping list.")
				return
			end
			table.insert(drafts, prefix)
			prefix = "CraftRoster materials (continued): "
		end
		if #prefix + #text + 2 > limit then
			print("|cffff0000CraftRoster|r: a material name exceeds the whisper limit. Check the shopping list.")
			return
		end
		table.insert(parts, text)
	end
	if #parts == 0 then parts[1] = "Materials not recorded; please confirm with the crafter" end
	table.insert(drafts, prefix .. "[" .. table.concat(parts, ", ") .. "]")
	return drafts
end

function Requests:PrepareWhisper(recipeID,target,quantity)
	if CraftRoster.WhisperComposer and CraftRoster.WhisperComposer:Handles(recipeID,target) then
		return CraftRoster.WhisperComposer:OnPrepared(recipeID,target,quantity or GetQuantity(recipeID))
	end
	local drafts=self:BuildWhisperDrafts(recipeID,target,quantity)
	if not drafts then return end
	self.whisperDrafts,self.whisperTarget=drafts,target
	self:NextWhisper()
	if #drafts>0 then print("|cff00ff00CraftRoster|r: /crwhisper opens the next materials draft. Press Enter to send each whisper.") end
end

SLASH_CRAFTROSTERWHISPER1 = "/crwhisper"
SlashCmdList["CRAFTROSTERWHISPER"] = function() Requests:NextWhisper() end

function Requests:WhisperPlayer(recipeID, target)
	if #GetMaterials(recipeID) > 0 then self:StartTradeRequest(recipeID, target)
	else self:RequestCraft(recipeID, target) end
end

function Requests:CanPrepareMail(recipeID,target)
	for _,request in ipairs(CraftRosterDB.requests or {}) do
		if OwnRequest(request) and request.mode=="trade" and not request.tradeAbandoned and request.status~="completed" and request.status~="declined" and request.status~="cancelled" and request.recipeID==recipeID and Normalize(request.target)==Normalize(target) and request.materialLedger then
			local progress=self:GetTradeProgress(request.id)
			if progress.needsReview or (progress.delivered>0 and progress.remaining>0) then
				print("|cffffd100CraftRoster|r: an earlier material trade is partial or unconfirmed. Finish that transfer or review /crtrade before preparing craft mail, to avoid sending the same materials twice.")
				return false
			end
			if progress.remaining>0 and progress.delivered==0 then request.tradeAbandoned=true end
		end
	end
	return true
end

function Requests:MailPlayer(recipeID, target)
	if not CraftRosterDB.settings.enabled or type(target) ~= "string" then return end
	target = CleanTarget(target)
	if not target:match("^[^%s:|%-]+%-[^%s:|]+$") then
		print("|cffff0000CraftRoster|r: select a crafter or enter their full Name-Realm before preparing mail.")
		return
	end
	if not self:CanPrepareMail(recipeID,target) then return end
	if #GetMaterials(recipeID) > 0 then self:StartMailRequest(recipeID, target); return end
	if not GetRecipe(recipeID) then return end
	pending = { mode = "mail", target = Normalize(target), targetName = target, recipeID = recipeID, quantity = GetQuantity(recipeID), materials = {} }
	pending.requestID = self:RequestCraft(recipeID, target, "mail")
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
	local recipeName = (GetQuantity(recipeID) > 1 and (GetQuantity(recipeID) .. " crafts of ") or "") .. (recipe.name or ("Recipe " .. recipeID))
	LogRequest(recipeID, target, mode or "craft", requestID)
	local sent = SendAddonData(("ORDER:%d:%s:%s:%s"):format(recipeID, Encode(requestID), Encode(target), Encode(recipeName)))
	if mode ~= "mail" then self:PrepareWhisper(recipeID, target) end
	print(("|cff00ff00CraftRoster|r: craft request for %s %s."):format(recipeName, sent and "sent" or "logged locally; guild delivery unavailable"))
	return requestID
end

local function CanResumeRecord(record)
	return record and record.mode=="trade" and not record.tradeAbandoned and not record.tradeUnresolved and record.status~="completed" and record.status~="declined" and record.status~="cancelled" and not tradeSession
end
function Requests:ResumeTrade(record,recipeID,target)
	if not CanResumeRecord(record) then print("|cffffd100CraftRoster|r: this order changed while the dialog was open. Review it before continuing."); return false end
	pending={mode="trade",target=Normalize(target),targetName=target,recipeID=recipeID,quantity=record.quantity or 1,requestID=record.id,materials=record.materialLedger}
	if CraftRoster.ShoppingList then CraftRoster.ShoppingList:SetQuantity(recipeID,pending.quantity) end
	if CraftRoster.Directory then CraftRoster.Directory:RefreshDetails() end
	self:PrepareWhisper(recipeID,target,pending.quantity)
	print("|cff00ff00CraftRoster|r: resuming outstanding materials for " .. pending.quantity .. " crafts; delivered items will not be loaded again.")
end
StaticPopupDialogs.CRAFTROSTER_RESUME_TRADE={
	text="An outstanding request has %s crafts; the new quantity is %s. Resume its remaining materials or replace the old request? Previously delivered materials stay recorded.",button1="Resume old",button2="Cancel",button3="Replace old",
	OnCancel=function() if CraftRoster.WhisperComposer then CraftRoster.WhisperComposer.pending=nil end end,
	timeout=0,whileDead=true,hideOnEscape=true,
	OnAccept=function(self)
		local data=self.data; local record=data and RequestRecord(data.requestID)
		if CanResumeRecord(record) then Requests:ResumeTrade(record,data.recipeID,data.target) end
		if CraftRoster.WhisperComposer then CraftRoster.WhisperComposer.pending=nil end
	end,
	OnAlt=function(self)
		local data=self.data; local record=data and RequestRecord(data.requestID)
		if CanResumeRecord(record) then
			record.tradeAbandoned=true; record.status="declined"
			SendAddonData("RSTAT:" .. record.id .. ":declined")
			if pending and pending.requestID==record.id then pending=nil end
			CraftRoster.ShoppingList:SetQuantity(data.recipeID,data.quantity)
			Requests:StartTradeRequest(data.recipeID,data.target)
		end
	end,
}

function Requests:StartTradeRequest(recipeID, target)
	if not CraftRosterDB.settings.enabled or type(target) ~= "string" or target:match("^%s*$") then return end
	local recipe = GetRecipe(recipeID)
	if not recipe then return end
	if tradeSession then
		print("|cffffd100CraftRoster|r: finish or close the current trade before preparing another request.")
		return
	end

	for _, record in ipairs(CraftRosterDB.requests or {}) do
		if OwnRequest(record) and record.mode == "trade" and not record.tradeAbandoned and record.status~="completed" and record.status~="declined" and record.status~="cancelled" and record.recipeID == recipeID and Normalize(record.target) == Normalize(target) and record.materialLedger then
			local progress = self:GetTradeProgress(record.id)
			if progress and progress.remaining > 0 then
				if record.tradeUnresolved then
					print("|cffffd100CraftRoster|r: the last trade outcome is unconfirmed. Check /crtrade before loading more materials.")
					return
				end
				if (record.quantity or 1)~=GetQuantity(recipeID) then
					self.composerDeferred=true
					StaticPopup_Show("CRAFTROSTER_RESUME_TRADE",tostring(record.quantity or 1),tostring(GetQuantity(recipeID)),{requestID=record.id,recipeID=recipeID,target=target,quantity=GetQuantity(recipeID)})
				else self:ResumeTrade(record,recipeID,target) end
				return
			end
		end
	end

	local openTransfers=0
	for _,request in ipairs(CraftRosterDB.requests or {}) do
		if OwnRequest(request) and request.mode=="trade" and not request.tradeAbandoned and request.status~="completed" and request.status~="declined" and request.status~="cancelled" then
			local active=request.tradeUnresolved or request.deliveryPending
			for _,material in ipairs(request.materialLedger or {}) do if material.remaining>0 then active=true; break end end
			if active then openTransfers=openTransfers+1 end
		end
	end
	if openTransfers>=100 then
		print("|cffffd100CraftRoster|r: 100 material transfers are still outstanding for this character. Resolve old requests before adding more; their progress was kept.")
		return
	end

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
		quantity = GetQuantity(recipeID),
		materials = CopyMaterials(PlayerMaterials(recipeID, target)),
	}

	pending.requestID = self:RequestCraft(recipeID, target, "trade")
	SaveTradeProgress(pending)
	if CraftRosterDB.settings.autoLoadItems == false then
		print("|cff00ff00CraftRoster|r: request prepared. Auto-load items is disabled; place trade materials manually.")
	else
		print(("|cff00ff00CraftRoster|r: trade auto-load armed for %s. Open a trade with them to load materials."):format(target))
	end
end

function Requests:StartMailRequest(recipeID, target)
	if not CraftRosterDB.settings.enabled or type(target) ~= "string" or target:match("^%s*$") then return end
	if not self:CanPrepareMail(recipeID,target) then return end
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
		quantity = GetQuantity(recipeID),
		materials = CopyMaterials(PlayerMaterials(recipeID, target)),
	}

	pending.requestID = self:RequestCraft(recipeID, target, "mail")
	if MailFrame and MailFrame:IsShown() then AttachMaterials("mail") end
	if CraftRosterDB.settings.autoLoadItems == false then
		print("|cff00ff00CraftRoster|r: mail text prepared. Auto-load items is disabled; attach materials manually.")
	else
		print(("|cff00ff00CraftRoster|r: mail auto-fill armed for %s. Open a mailbox to load materials."):format(target))
	end
end

-- Safety: automation only fills the trade/mail window.
-- It never calls AcceptTrade() or SendMail(). The user must confirm both.
AttachMaterials = function(mode)
	if not pending or pending.mode ~= mode or not CraftRosterDB.settings.enabled then return end
	if mode == "mail" then
		if not pending.mailTextPrepared then
			local money=GetSendMailMoney and GetSendMailMoney() or 0
			local cod=GetSendMailCOD and GetSendMailCOD() or 0
			local subject=SendMailSubjectEditBox and SendMailSubjectEditBox:GetText() or ""
			local body=SendMailBodyEditBox and SendMailBodyEditBox:GetText() or ""
			if money>0 or cod>0 or subject~="" or body~="" then
				print("|cffffd100CraftRoster|r: this mail already contains text, gold or COD. Clear or send the draft first; it was left untouched.")
				return
			end
		end
		if not pending.mailTextPrepared and GetSendMailItem then
			for slot=1,12 do
				if GetSendMailItem(slot) then
					print("|cffffd100CraftRoster|r: this mail already has attachments. Clear or send the existing draft before preparing craft mail; its fields and items were left untouched.")
					return
				end
			end
		end
		if not pending.mailPrepared then
			pending.materials = CopyMaterials(PlayerMaterials(pending.recipeID, pending.targetName, pending.quantity))
			pending.mailPrepared = true
		end
		if not pending.mailTextPrepared then
			local recipe = GetRecipe(pending.recipeID)
			local name = recipe and recipe.name or "Unknown item"
			local lines = {"Hi! Could you craft " .. name .. " for me?", "", "Requested item: " .. name, "Number of crafts: " .. (pending.quantity or 1), "", "Materials needed (total):"}
			local materials = CopyMaterials(GetMaterials(pending.recipeID, pending.quantity))
			for _, material in ipairs(materials) do
				table.insert(lines, tostring(material.count) .. " x " .. material.name)
			end
			if #materials == 0 then table.insert(lines, "Materials not recorded; please confirm the requirements.") end
			table.insert(lines, "")
			table.insert(lines, "Thank you")
			if SendMailNameEditBox then SendMailNameEditBox:SetText(pending.targetName) end
			if SendMailSubjectEditBox then
				local suffix = " craft requested"
				local limit = SendMailSubjectEditBox.GetMaxLetters and SendMailSubjectEditBox:GetMaxLetters() or 64
				if not limit or limit <= 0 then limit = 64 end
				-- Trim whole UTF-8 characters so the required suffix fits the client limit.
				local title = ((pending.quantity or 1) > 1 and (pending.quantity .. " crafts of ") or "") .. name
				while #title + #suffix > limit and #title > 0 do
					local shorter=title:gsub("[%z\1-\127\194-\244][\128-\191]*$", "")
					-- A malformed trailing byte must not create an infinite trim loop.
					title=shorter~=title and shorter or title:sub(1,-2)
				end
				SendMailSubjectEditBox:SetText(title .. suffix)
			end
			if SendMailBodyEditBox then SendMailBodyEditBox:SetText(table.concat(lines, "\n")) end
			pending.mailTextPrepared = true
		end
	end
	if CraftRosterDB.settings.autoLoadItems == false then return end
	local loadingMaterials = mode == "trade" and tradeSession and tradeSession.materials or pending.materials
	if #loadingMaterials == 0 then return end
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
	if mode=="trade" then
		for slot=1,6 do
			if slotInfo(slot) then
				print("|cffffd100CraftRoster|r: this trade already contains items. Auto-load skipped this window; check the amounts or fill it manually.")
				return
			end
		end
	end

	local used = {}
	local function EmptySlot()
		for slot = 1, (mode == "trade" and 6 or 12) do
			if not used[slot] and not slotInfo(slot) then return slot end
		end
	end
	local byID, byName = {}, {}
	for _, material in ipairs(loadingMaterials) do
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

-- Only these CraftRoster dialogs become draggable; pooled Blizzard popups are
-- restored on hide so unrelated confirmation dialogs retain their behavior.
local function ShowMovableRequest(self)
	self.CraftRosterWasMovable = self:IsMovable()
	self:SetMovable(true)
	self:SetClampedToScreen(true)
	local handle = self.CraftRosterDragHandle
	if not handle then
		handle = CreateFrame("Frame", nil, self)
		handle:SetPoint("TOPLEFT", self, "TOPLEFT", 0, 0)
		handle:SetPoint("TOPRIGHT", self, "TOPRIGHT", 0, 0)
		handle:SetHeight(24)
		handle:EnableMouse(true)
		handle:RegisterForDrag("LeftButton")
		handle:SetScript("OnDragStart", function() self:StartMoving() end)
		handle:SetScript("OnDragStop", function() self:StopMovingOrSizing() end)
		self.CraftRosterDragHandle = handle
	end
	handle:Show()
end
local function HideMovableRequest(self)
	self:StopMovingOrSizing()
	self:SetMovable(self.CraftRosterWasMovable or false)
	if self.CraftRosterDragHandle then self.CraftRosterDragHandle:Hide() end
end

StaticPopupDialogs["CRAFTROSTER_TRADE_MATS"] = {
	OnShow = ShowMovableRequest,
	OnHide = HideMovableRequest,
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
	OnShow = ShowMovableRequest,
	OnHide = HideMovableRequest,
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
	button:SetSize(170, 22)
	button:SetPoint(point, relativeTo, relativePoint, x or 0, y or -8)
	button:SetText(text)
	button:SetScript("OnClick", function()
		local recipe = CraftRoster.Directory and CraftRoster.Directory.selectedRecipe
		if not recipe then
			print("|cffff0000CraftRoster|r: select a recipe first.")
			return
		end
		local target = CraftRoster.Directory.selectedCrafter
		if dialog=="CRAFTROSTER_TRADE_MATS" and CraftRoster.WhisperComposer then
			CraftRoster.WhisperComposer:Open(recipe.id,target); return
		end
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

	tab.CraftRosterTradeButton = CreateRequestButton(tab.Details, "Whisper", "CRAFTROSTER_TRADE_MATS", "BOTTOMLEFT", tab.Details, "BOTTOMLEFT", 12, 58)
	tab.CraftRosterMailButton = CreateRequestButton(tab.Details, "Mail", "CRAFTROSTER_MAIL_MATS", "BOTTOMRIGHT", tab.Details, "BOTTOMRIGHT", -12, 58)

	local quantity = CreateFrame("EditBox", nil, tab.Details, "InputBoxTemplate")
	quantity:SetSize(42, 20); quantity:SetPoint("TOPRIGHT", -36, -59)
	quantity:SetAutoFocus(false); quantity:SetNumeric(true); quantity:SetMaxLetters(3)
	quantity:SetText("1")
	tab.CraftRosterQuantity = quantity
	local quantityLabel = tab.Details:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	quantityLabel:SetPoint("RIGHT", quantity, "LEFT", -8, 0); quantityLabel:SetText("Crafts:")
	local function SaveQuantity(self)
		local recipe = directory.selectedRecipe
		if recipe and CraftRoster.ShoppingList then
			CraftRoster.ShoppingList:SetQuantity(recipe.id, tonumber(self:GetText()))
			self:SetText(tostring(CraftRoster.ShoppingList:GetQuantity(recipe.id)))
		end
		self:ClearFocus()
	end
	quantity:SetScript("OnTextChanged", function(self, userInput)
		if userInput and directory.selectedRecipe and CraftRoster.ShoppingList then
			CraftRoster.ShoppingList:SetQuantity(directory.selectedRecipe.id, tonumber(self:GetText()))
		end
	end)
	quantity:SetScript("OnEnterPressed", SaveQuantity)
	quantity:SetScript("OnEditFocusLost", function(self)
		local recipe = directory.selectedRecipe
		if recipe and CraftRoster.ShoppingList then
			CraftRoster.ShoppingList:SetQuantity(recipe.id, tonumber(self:GetText()))
			self:SetText(tostring(CraftRoster.ShoppingList:GetQuantity(recipe.id)))
		end
	end)
	quantity:SetScript("OnEscapePressed", function(self)
		local recipe = directory.selectedRecipe
		self:SetText(tostring(recipe and GetQuantity(recipe.id) or 1)); self:ClearFocus()
	end)

	local function StepQuantity(delta)
		local recipe = directory.selectedRecipe
		if not recipe or not CraftRoster.ShoppingList then return end
		local value = tonumber(quantity:GetText())
		if not value or value < 1 or value > 999 or value ~= math.floor(value) then value = GetQuantity(recipe.id) end
		value = math.max(1, math.min(999, value + delta))
		CraftRoster.ShoppingList:SetQuantity(recipe.id, value)
		quantity:SetText(tostring(value)); quantity:ClearFocus()
	end
	local function QuantityArrow(direction, delta, point, y)
		local button = CreateFrame("Button", nil, tab.Details)
		button:SetSize(18, 12)
		button:SetPoint(point, quantity, point == "TOPLEFT" and "TOPRIGHT" or "BOTTOMRIGHT", 4, y)
		local texture = "Interface\\Buttons\\UI-ScrollBar-Scroll" .. direction .. "Button-"
		button:SetNormalTexture(texture .. "Up")
		button:SetPushedTexture(texture .. "Down")
		button:SetHighlightTexture(texture .. "Highlight")
		button:SetScript("OnClick", function() StepQuantity(delta) end)
		return button
	end
	tab.CraftRosterQuantityUp = QuantityArrow("Up", 1, "TOPLEFT", 2)
	tab.CraftRosterQuantityDown = QuantityArrow("Down", -1, "BOTTOMLEFT", -2)

	local autoLoad = CreateFrame("CheckButton", nil, tab.Details, "UICheckButtonTemplate")
	autoLoad:SetSize(22, 22); autoLoad:SetPoint("BOTTOMLEFT", 10, 34)
	autoLoad:SetChecked(CraftRosterDB.settings.autoLoadItems ~= false)
	local autoLoadLabel = autoLoad.Text or autoLoad:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	if autoLoadLabel == autoLoad then autoLoadLabel = autoLoad:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall") end
	autoLoadLabel:ClearAllPoints(); autoLoadLabel:SetPoint("LEFT", autoLoad, "RIGHT", 2, 0)
	autoLoadLabel:SetText("Auto-load items")
	autoLoad:SetScript("OnClick", function(self) Requests:SetAutoLoadItems(self:GetChecked() and true or false) end)
	autoLoad:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT"); GameTooltip:SetText("Auto-load items")
		GameTooltip:AddLine("Place requested materials in a trade you open with the crafter, or attach them when you open a mailbox. Uncheck to load items manually. Mail and whisper text still prepare.", 1, 1, 1, true)
		GameTooltip:Show()
	end)
	autoLoad:SetScript("OnLeave", function() GameTooltip:Hide() end)
	tab.CraftRosterAutoLoad = autoLoad

	local cancelRequest = CreateFrame("Button", nil, tab.Details, "GameMenuButtonTemplate")
	cancelRequest:SetSize(112, 20)
	cancelRequest:SetPoint("BOTTOMRIGHT", tab.Details, "BOTTOMRIGHT", -12, 34)
	cancelRequest:SetText("Cancel request")
	cancelRequest:SetScript("OnClick", function()
		local recipe=directory.selectedRecipe
		Requests:CancelCurrentRequests(recipe and recipe.id,directory.selectedCrafter)
	end)
	cancelRequest:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self,"ANCHOR_RIGHT"); GameTooltip:SetText("Cancel request")
		GameTooltip:AddLine("Cancel outstanding requests for the selected recipe and crafter (all crafters if none selected). Stops further auto-loading and updates connected crafters' work orders. Items already placed in a trade or mail stay there.",1,1,1,true)
		GameTooltip:Show()
	end)
	cancelRequest:SetScript("OnLeave", function() GameTooltip:Hide() end)
	tab.CraftRosterCancelRequestButton=cancelRequest

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
	favoriteButton:SetSize(120, 22)
	favoriteButton:SetPoint("BOTTOMLEFT", tab.Details, "BOTTOMLEFT", 12, 10)
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
	shoppingButton:SetSize(120, 22)
	shoppingButton:SetPoint("BOTTOMRIGHT", tab.Details, "BOTTOMRIGHT", -12, 10)
	shoppingButton:SetText("Shopping List")
	shoppingButton:SetScript("OnClick", function()
		local recipe = directory.selectedRecipe
		if recipe and CraftRoster.ShoppingList then CraftRoster.ShoppingList:Open(recipe.id)
		else print("|cff00ff00CraftRoster|r: select a recipe first.") end
	end)
	tab.CraftRosterShoppingButton = shoppingButton
	local function ResizeActions()
		local width = math.max(90, (tab.Details:GetWidth() - 28) / 2)
		tab.CraftRosterTradeButton:SetWidth(width)
		tab.CraftRosterMailButton:SetWidth(width)
		tab.CraftRosterFavoriteButton:SetWidth(width)
		tab.CraftRosterShoppingButton:SetWidth(width)
	end
	tab.CraftRosterResizeActions=ResizeActions
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
			if request.mode=="incoming" and CraftRoster.WorkOrders then CraftRoster.WorkOrders:UpdateRequestStatus(requestID,request.target,status) end
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

-- Read actual trade slots, including manual changes, instead of assuming every
-- item picked up by auto-load will still be present when the trade succeeds.
CaptureTradeOffer = function(session)
	if not session or session.closedAt or session.succeeded or session.cancelled then return end
	if not GetTradePlayerItemInfo or not GetTradePlayerItemLink then session.offerVerified = false; return end
	local offered = {}
	for slot = 1, 6 do
		local ok, name, _, count = pcall(GetTradePlayerItemInfo, slot)
		if not ok then session.offerVerified = false; return end
		if name then
			local linkOK, link = pcall(GetTradePlayerItemLink, slot)
			local itemID = linkOK and type(link) == "string" and tonumber(link:match("item:(%d+)"))
			if not itemID or type(count) ~= "number" or count <= 0 or count ~= math.floor(count) then
				session.offerVerified = false; return
			end
			offered[itemID] = (offered[itemID] or 0) + count
			offered[name] = (offered[name] or 0) + count
		end
	end
	session.actualOffer, session.offerVerified = offered, true
end

local function TradeSucceeded()
	local session = tradeSession or lastTradeSession
	if not session or session.completed or session.cancelled or (session.closedAt and time() - session.closedAt > 2) then return end
	session.completed = true
	local offered = session.acceptedOffer or (not session.sawAcceptance and session.offerVerified and session.actualOffer)
	if not offered then
		MaterialStatus(session, "needs_review")
		print("|cffffd100CraftRoster|r: trade completed, but its items could not be verified. Auto-load paused; check /crtrade.")
		return
	end
	session.succeeded = true
	local request, record = session.request, RequestRecord(session.requestID)
	for _, material in ipairs(request.materials) do
		local count = offered[material.itemID or material.name] or 0
		material.remaining = math.max(0, material.remaining - math.min(material.remaining, count))
	end
	if record then record.tradeUnresolved = false end
	SaveTradeProgress(request)
	MaterialStatus(session, "trade_succeeded")
	local progress = Requests:GetTradeProgress(session.requestID)
	if record and record.status=="cancelled" then
		print("|cff00ff00CraftRoster|r: trade completed after request cancellation. Delivered materials are recorded; the request remains cancelled.")
		return
	end
	if progress and progress.remaining == 0 then
		if pending and pending.requestID == session.requestID then pending = nil end
		print("|cff00ff00CraftRoster|r: all requested materials delivered. Craft completion is still unconfirmed.")
	else
		print(("|cff00ff00CraftRoster|r: trade confirmed; %d material units across %d types remain. Reopen a trade with the same crafter to continue."):format(progress and progress.remaining or 0, progress and progress.typesRemaining or 0))
	end
end

local function TradeCancelled(reason)
	local session = tradeSession or lastTradeSession
	if not session or session.completed or (session.closedAt and time() - session.closedAt > 2) then return end
	session.cancelled = true
	local record = RequestRecord(session.requestID)
	if record then record.tradeUnresolved = false end
	MaterialStatus(session, reason or "cancelled")
	print("|cffffd100CraftRoster|r: trade did not complete. No materials counted as delivered; retry after correcting the problem.")
end

-- Unknown outcomes require an explicit human check. Never blindly replay them.
SLASH_CRAFTROSTERTRADE1 = "/crtrade"
SlashCmdList.CRAFTROSTERTRADE = function()
	local record
	for _, request in ipairs(CraftRosterDB.requests or {}) do
		if OwnRequest(request) and request.materialLedger then record = request; break end
	end
	if not record then print("|cff00ff00CraftRoster|r: no material delivery recorded."); return end
	for _, material in ipairs(record.materialLedger) do
		print(("%s: %d delivered / %d required; %d remaining"):format(material.name, material.count-material.remaining, material.count, material.remaining))
	end
	if record.tradeUnresolved then
		if tradeSession and tradeSession.requestID == record.id then
			print("|cffffd100CraftRoster|r: close the current trade before reviewing its outcome.")
		else StaticPopup_Show("CRAFTROSTER_TRADE_REVIEW", nil, nil, record.id) end
	end
end
StaticPopupDialogs.CRAFTROSTER_TRADE_REVIEW = {
	text="The last trade outcome is unclear. Check your bags and confirm with the crafter. Choose Nothing delivered ONLY if no materials changed hands in that last trade. Otherwise keep auto-load paused and finish manually.",
	button1="Nothing delivered", button2="Keep paused", timeout=0, whileDead=true, hideOnEscape=true,
	OnAccept=function(self)
		local record = RequestRecord(self.data)
		if record and record.tradeUnresolved then
			if tradeSession and tradeSession.requestID == record.id then return end
			record.tradeUnresolved=false; record.materialStatus="reviewed_no_delivery"
			if lastTradeSession and lastTradeSession.requestID==record.id then lastTradeSession.cancelled=true end
			if tradeSession and tradeSession.requestID==record.id then tradeSession.cancelled=true end
			print("|cff00ff00CraftRoster|r: no delivery confirmed by you. Click Whisper again to resume the remaining materials.")
		end
	end,
}

local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("TRADE_SHOW")
frame:RegisterEvent("TRADE_CLOSED")
frame:RegisterEvent("TRADE_PLAYER_ITEM_CHANGED")
frame:RegisterEvent("TRADE_ACCEPT_UPDATE")
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
		if tradeSession then return end -- duplicate show events must never refill a window
		-- Late terminal events after a new window cannot be attributed to the old one.
		lastTradeSession=nil
		if pending and pending.mode == "trade" and Normalize(partner) == pending.target then
			local record = RequestRecord(pending.requestID)
			if record and record.tradeUnresolved then
				print("|cffffd100CraftRoster|r: prior trade outcome unconfirmed. Auto-load paused; check /crtrade.")
				return
			end
			lastTradeSession = nil
			local materials = {}
			for _, material in ipairs(pending.materials) do
				if material.remaining > 0 then table.insert(materials, {name=material.name,itemID=material.itemID,count=material.remaining,remaining=material.remaining}) end
			end
			tradeSession = {requestID=pending.requestID,request=pending,materials=materials,offered=0}
			if record then record.tradeUnresolved = true end
			AttachMaterials("trade")
			CaptureTradeOffer(tradeSession)
			local partial = false
			for _, material in ipairs(materials) do if material.remaining > 0 then partial = true end end
			tradeSession.partial = partial
			MaterialStatus(tradeSession, tradeSession.offered > 0 and "offered" or "not_offered")
			if partial then print("|cff00ff00CraftRoster|r: some materials are not in this trade. Check available bag items, locked stacks and the six trade slots before accepting.") end
			if tradeCancel then tradeCancel:Show() end
		end

	elseif event == "TRADE_PLAYER_ITEM_CHANGED" then
		if tradeSession then tradeSession.acceptedOffer=nil end
		CaptureTradeOffer(tradeSession)
	elseif event == "TRADE_ACCEPT_UPDATE" then
		CaptureTradeOffer(tradeSession)
		if tradeSession and not tradeSession.closedAt then
			local playerAccepted,targetAccepted=...
			tradeSession.sawAcceptance=true
			if (playerAccepted==1 or playerAccepted==true) and (targetAccepted==1 or targetAccepted==true) and tradeSession.offerVerified then
				tradeSession.acceptedOffer=tradeSession.actualOffer
			else tradeSession.acceptedOffer=nil end
		end

	elseif event == "TRADE_CLOSED" then
		if tradeSession then
			tradeSession.closedAt = time()
			if not tradeSession.completed and not tradeSession.cancelled then MaterialStatus(tradeSession, "trade_closed_unconfirmed") end
			lastTradeSession, tradeSession = tradeSession, nil
		end
		if tradeCancel then tradeCancel:Hide() end

	elseif event == "TRADE_REQUEST_CANCEL" then
		TradeCancelled()

	elseif event == "UI_INFO_MESSAGE" or event == "UI_ERROR_MESSAGE" then
		local code, message = ...
		if type(code) == "string" then message = code end
		if (ERR_TRADE_COMPLETE and message == ERR_TRADE_COMPLETE)
			or (LE_GAME_ERR_TRADE_COMPLETE and code == LE_GAME_ERR_TRADE_COMPLETE) then TradeSucceeded()
		elseif ERR_TRADE_CANCELLED and message == ERR_TRADE_CANCELLED then TradeCancelled()
		elseif event == "UI_ERROR_MESSAGE" and (tradeSession or lastTradeSession) then
			-- Unknown errors are visible but never treated as cancellation or success:
			-- some describe only a failed item placement while the trade stays open.
			local session = tradeSession or lastTradeSession
			if not session.completed and not session.cancelled then
				MaterialStatus(session, "trade_error")
				print("|cffffd100CraftRoster|r: " .. tostring(message or "Trade error") .. " Materials remain unconfirmed until the game reports trade complete.")
			end
		end

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
			for _, request in ipairs(CraftRosterDB.requests or {}) do if request.id == id and Normalize(request.target)==Normalize(sender) then return end end
			CraftRosterDB.requests = CraftRosterDB.requests or {}
			table.insert(CraftRosterDB.requests, 1, { id = id, recipe = Decode(recipeName), recipeID = tonumber(recipeID),
				target = sender, mode = "incoming", status = "requested", at = time() })
			if CraftRoster.WorkOrders then CraftRoster.WorkOrders:ReceiveRequest(CraftRosterDB.requests[1]) end
			Requests:TrimHistory()
			print("|cff00ff00CraftRoster|r: new crafting request. Use /cr orders to view work orders.")
			return
		end
		local requestID, status = message:match("^RSTAT:(.+):(%a+)$")
		if requestID and (status == "accepted" or status == "completed" or status == "declined" or status == "cancelled") then
			for _, request in ipairs(CraftRosterDB.requests or {}) do
				if request.id == requestID and Normalize(request.target) == Normalize(sender)
					and ((request.status ~= "completed" and request.status ~= "declined" and request.status ~= "cancelled") or status == request.status) then
					request.status = status
					if (status=="completed" or status=="declined" or status=="cancelled") and pending and pending.requestID==requestID then pending=nil end
					print(("|cff00ff00CraftRoster|r: request for %s is now %s."):format(request.recipe, status))
					break
				end
			end
			if CraftRoster.WorkOrders then CraftRoster.WorkOrders:UpdateRequestStatus(requestID,sender,status) end
		end
	end
end)

