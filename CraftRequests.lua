local ADDON_NAME, CraftRoster = ...

local Requests = {}
CraftRoster.Requests = Requests

local pending = nil
local tradeCancel, mailCancel

local function Normalize(name)
	return (name or ""):lower()
end

local function GetRecipe(recipeID)
	return CraftRosterDB.recipes and CraftRosterDB.recipes[recipeID]
end

local function GetMaterials(recipeID)
	local recipe = GetRecipe(recipeID)
	return recipe and recipe.materials or {}
end

local function CopyMaterials(materials)
	local copy = {}
	for _, material in ipairs(materials) do
		table.insert(copy, {
			name = material.name,
			count = material.count,
			remaining = material.count,
		})
	end
	return copy
end

local function LogRequest(recipeID, target, mode)
	CraftRosterDB.requests = CraftRosterDB.requests or {}
	local recipe = GetRecipe(recipeID)
	table.insert(CraftRosterDB.requests, 1, {
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
	if tradeCancel then tradeCancel:Hide() end
	if mailCancel then mailCancel:Hide() end
	print("|cff00ff00CraftRoster|r: auto-fill request cancelled.")
end

function Requests:StartTradeRequest(recipeID, target)
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
		materials = CopyMaterials(materials),
	}

	LogRequest(recipeID, target, "trade")
	SendChatMessage("CraftRoster: requesting materials for " .. (recipe.name or "a recipe"), "WHISPER", nil, target)
	print(("|cff00ff00CraftRoster|r: trade auto-load armed for %s. Open a trade with them to load materials."):format(target))
end

function Requests:StartMailRequest(recipeID, target)
	local recipe = GetRecipe(recipeID)
	if not recipe then return end

	if not target:match("^[%a%p]+%-%[%a%p]+$") and not target:match("^[%a%p]+%-[%a%p]+$") then
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
		materials = CopyMaterials(materials),
	}

	LogRequest(recipeID, target, "mail")
	print(("|cff00ff00CraftRoster|r: mail auto-fill armed for %s. Open a mailbox to load materials."):format(target))
end

-- Safety: automation only fills the trade/mail window.
-- It never calls AcceptTrade() or SendMail(). The user must confirm both.
local function AttachMaterialsToTrade()
	if not pending or pending.mode ~= "trade" then return end

	for _, material in ipairs(pending.materials) do
		while material.remaining > 0 do
			local placed = false

			for bag = 0, 4 do
				for slot = 1, GetContainerNumSlots(bag) do
					local link = GetContainerItemLink(bag, slot)
					if link then
						local itemName = link:match("%[(.-)%]")
						if itemName == material.name then
							UseContainerItem(bag, slot)
							material.remaining = material.remaining - 1
							placed = true
							break
						end
					end
				end
				if placed then break end
			end

			if not placed then break end
		end
	end
end

local function AttachMaterialsToMail()
	if not pending or pending.mode ~= "mail" then return end

	local recipe = GetRecipe(pending.recipeID)
	if SendMailNameEditBox then
		SendMailNameEditBox:SetText(pending.targetName)
	end
	if SendMailSubjectEditBox then
		SendMailSubjectEditBox:SetText("Crafting mats: " .. (recipe and recipe.name or "recipe"))
	end

	local attachSlot = 1

	for _, material in ipairs(pending.materials) do
		local remaining = material.count

		while remaining > 0 do
			local attached = false

			for bag = 0, 4 do
				for slot = 1, GetContainerNumSlots(bag) do
					local link = GetContainerItemLink(bag, slot)
					if link then
						local itemName = link:match("%[(.-)%]")
						if itemName == material.name then
							PickupContainerItem(bag, slot)
							if ClickSendMailItemButton then
								ClickSendMailItemButton(attachSlot)
							end
							attachSlot = attachSlot + 1
							remaining = remaining - 1
							attached = true
							break
						end
					end
				end
				if attached then break end
			end

			if not attached then break end
		end
	end
end

StaticPopupDialogs["CRAFTROSTER_TRADE_MATS"] = {
	text = "Enter the character to whisper and trade materials with:",
	button1 = "Whisper & Arm Trade",
	button2 = "Cancel",
	OnAccept = function(self)
		local target = self.editBox:GetText()
		if target and target ~= "" then
			Requests:StartTradeRequest(self.data, target)
		end
	end,
	EditBoxOnEnterPressed = function(self)
		local target = self:GetText()
		if target and target ~= "" then
			Requests:StartTradeRequest(self:GetParent().data, target)
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
	button1 = "Arm Mail Fill",
	button2 = "Cancel",
	OnAccept = function(self)
		local target = self.editBox:GetText()
		if target and target ~= "" then
			Requests:StartMailRequest(self.data, target)
		end
	end,
	EditBoxOnEnterPressed = function(self)
		local target = self:GetText()
		if target and target ~= "" then
			Requests:StartMailRequest(self:GetParent().data, target)
		end
		self:GetParent():Hide()
	end,
	hasEditBox = true,
	timeout = 0,
	whileDead = true,
	hideOnEscape = true,
}

local function CreateRequestButton(parent, text, dialog, point, relativeTo, relativePoint)
	local button = CreateFrame("Button", nil, parent, "GameMenuButtonTemplate")
	button:SetSize(170, 26)
	button:SetPoint(point, relativeTo, relativePoint, 0, -8)
	button:SetText(text)
	button:SetScript("OnClick", function()
		local recipe = CraftRoster.Directory and CraftRoster.Directory.selectedRecipe
		if not recipe then
			print("|cffff0000CraftRoster|r: select a recipe first.")
			return
		end
		StaticPopup_Hide(dialog)
		StaticPopupDialogs[dialog].data = recipe.id
		StaticPopup_Show(dialog)
	end)
	return button
end

local function AddDirectoryButtons()
	local directory = CraftRoster.Directory
	if not directory or not directory.frame then return end

	local tab = directory.frame.ProfessionsTab
	if tab.CraftRosterTradeButton then return end

	tab.CraftRosterTradeButton = CreateRequestButton(tab, "Whisper & Trade Mats", "CRAFTROSTER_TRADE_MATS", "TOPRIGHT", tab, "TOPRIGHT", -18, -16)
	tab.CraftRosterMailButton = CreateRequestButton(tab, "Mail Crafter Mats", "CRAFTROSTER_MAIL_MATS", "TOPRIGHT", tab.CraftRosterTradeButton, "BOTTOMRIGHT", -18, -16)

	local refreshButton = CreateFrame("Button", nil, tab, "GameMenuButtonTemplate")
	refreshButton:SetSize(90, 22)
	refreshButton:SetPoint("TOPLEFT", tab, "TOPLEFT", 170, -48)
	refreshButton:SetText("Refresh")
	refreshButton:SetScript("OnClick", function()
		if CraftRoster.GuildSync then
			CraftRoster.GuildSync:SyncNow()
		end
		if CraftRoster.Directory then
			CraftRoster.Directory:RefreshIfVisible()
		end
	end)
	tab.CraftRosterRefreshButton = refreshButton
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
		print(("%s → %s (%s) [%s]"):format(request.recipe, request.target, request.mode, request.status))
	end
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("TRADE_SHOW")
frame:RegisterEvent("TRADE_CLOSED")
frame:RegisterEvent("MAIL_SHOW")
frame:RegisterEvent("MAIL_CLOSED")

frame:SetScript("OnEvent", function(_, event, arg1)
	if event == "ADDON_LOADED" and arg1 == ADDON_NAME then
		if TradeFrame then
			tradeCancel = CreateCancelButton(TradeFrame, "Trade")
		end
		if MailFrame then
			mailCancel = CreateCancelButton(MailFrame, "Mail")
		end

		local originalToggle = CraftRoster.Directory.Toggle
		function CraftRoster.Directory:Toggle(...)
			AddDirectoryButtons()
			return originalToggle(self, ...)
		end

	elseif event == "TRADE_SHOW" then
		if pending and pending.mode == "trade" and Normalize(UnitName("NPC")) == pending.target then
			AttachMaterialsToTrade()
			if tradeCancel then tradeCancel:Show() end
		end

	elseif event == "TRADE_CLOSED" then
		if pending and pending.mode == "trade" then
			Requests:Cancel()
		end

	elseif event == "MAIL_SHOW" then
		if pending and pending.mode == "mail" then
			AttachMaterialsToMail()
			if mailCancel then mailCancel:Show() end
		end

	elseif event == "MAIL_CLOSED" then
		if pending and pending.mode == "mail" then
			Requests:Cancel()
		end
	end
end)
