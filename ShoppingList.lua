local ADDON_NAME, CraftRoster = ...
local ShoppingList = {}
CraftRoster.ShoppingList = ShoppingList

local ROW_HEIGHT = 64
local refreshTimer

local function GetState()
	if not CraftRosterDB then return nil end
	local key = UnitName("player") .. "-" .. (GetRealmName() or "")
	local character = CraftRosterDB.characters[key]
	if not character then return nil end
	character.shoppingList = character.shoppingList or {}
	return character.shoppingList
end

local function Materials(recipe, quantity)
	quantity = quantity or 1
	if not recipe or type(recipe.materials) ~= "table" or #recipe.materials == 0 then return nil end
	local entries, byKey = {}, {}
	for _, material in ipairs(recipe.materials) do
		if type(material) ~= "table" or type(material.name) ~= "string"
			or type(material.count) ~= "number" or material.count <= 0
			or material.count > 1000000 or material.count ~= math.floor(material.count) then return nil end
		local key = material.itemID or material.name
		local entry = byKey[key]
		if entry then entry.required = entry.required + material.count * quantity
		else
			entry = { name = material.name, itemID = material.itemID, required = material.count * quantity, link=material.link, icon=material.icon }
			byKey[key] = entry; table.insert(entries, entry)
		end
	end
	return entries
end

-- Quantities count recipe executions; recipes may produce more than one item per craft.
function ShoppingList:GetQuantity(recipeID)
	local state = GetState()
	local value = state and state.quantities and state.quantities[recipeID]
	if type(value) ~= "number" or value < 1 or value > 999 or value ~= math.floor(value) then return 1 end
	return value
end

function ShoppingList:SetQuantity(recipeID, quantity)
	if type(quantity) ~= "number" or quantity < 1 or quantity > 999 or quantity ~= math.floor(quantity) then return false end
	local state = GetState()
	if not state or not CraftRosterDB.recipes[recipeID] then return false end
	state.quantities = state.quantities or {}
	state.quantities[recipeID] = quantity
	self:ScheduleRefresh()
	return true
end

local function NormalizeTarget(target)
	if type(target) ~= "string" or target == "" then return nil end
	if not target:find("-", 1, true) then target = target .. "-" .. (GetRealmName() or "") end
	return (target:lower():gsub("%s", ""))
end

local function Contribution(recipeID, target)
	local state = GetState()
	local recipes = state and state.contributions
	local byCrafter = recipes and recipes[recipeID]
	return byCrafter and byCrafter[NormalizeTarget(target)] or {}
end

function ShoppingList:GetPlayerMaterials(recipeID, target, quantity)
	local entries = Materials({materials = CraftRoster.RecipeSources and CraftRoster.RecipeSources:GetMaterials(recipeID)}, quantity or self:GetQuantity(recipeID)) or {}
	local contribution = Contribution(recipeID, target)
	local materials = {}
	for _, entry in ipairs(entries) do
		local shared = math.min(entry.required, contribution[entry.itemID or entry.name] or 0)
		local count = entry.required - shared
		if count > 0 then table.insert(materials, {name=entry.name, itemID=entry.itemID, count=count}) end
	end
	return materials
end

function ShoppingList:SetCrafterShare(recipeID, target, key, count)
	local crafter = NormalizeTarget(target)
	if not crafter or type(count) ~= "number" or count < 0 or count ~= math.floor(count) then return false end
	local found
	for _, entry in ipairs(Materials({materials = CraftRoster.RecipeSources and CraftRoster.RecipeSources:GetMaterials(recipeID)}, self:GetQuantity(recipeID)) or {}) do
		if (entry.itemID or entry.name) == key then found = entry end
	end
	if not found or count > found.required then return false end
	local state = GetState()
	state.contributions = state.contributions or {}
	state.contributions[recipeID] = state.contributions[recipeID] or {}
	state.contributions[recipeID][crafter] = state.contributions[recipeID][crafter] or {}
	state.contributions[recipeID][crafter][key] = count
	if state.recipeID == recipeID then state.crafter = target end
	self:ScheduleRefresh()
	return true
end

function ShoppingList:EditCrafterShare(entry)
	local state = GetState()
	if not state or not state.crafter then
		print("|cff00ff00CraftRoster|r: select a crafter, then reopen this recipe's shopping list to set their share.")
		return
	end
	StaticPopup_Show("CRAFTROSTER_CRAFTER_SHARE", entry.name, tostring(entry.recipeRequired), {
		recipeID=state.recipeID, target=state.crafter, key=entry.itemID or entry.name,
		count=entry.crafterProvides or 0,
	})
end

StaticPopupDialogs["CRAFTROSTER_CRAFTER_SHARE"] = {
	text = "How many %s will the crafter provide? (0–%s)",
	button1 = "Save", button2 = "Cancel", hasEditBox = true, timeout = 0, whileDead = true, hideOnEscape = true,
	OnShow = function(self)
		local edit = self.editBox or self.EditBox
		edit:SetNumeric(true); edit:SetText(tostring(self.data and self.data.count or 0)); edit:HighlightText()
	end,
	OnAccept = function(self)
		local data = self.data
		local edit = self.editBox or self.EditBox
		if data and not ShoppingList:SetCrafterShare(data.recipeID, data.target, data.key, tonumber(edit:GetText())) then
			print("|cffff0000CraftRoster|r: enter a whole quantity between zero and the recipe requirement.")
		end
	end,
}

-- Build one inventory index only when a count API is unavailable.
local function BagCounts()
	local slots = C_Container and C_Container.GetContainerNumSlots or GetContainerNumSlots
	local link = C_Container and C_Container.GetContainerItemLink or GetContainerItemLink
	local info = C_Container and C_Container.GetContainerItemInfo or GetContainerItemInfo
	if not slots or not link or not info then return nil end
	local counts = {}
	for bag = 0, (NUM_BAG_SLOTS or 4) do
		for slot = 1, slots(bag) do
			local itemLink = link(bag, slot)
			if itemLink then
				local item, count = info(bag, slot)
				if type(item) == "table" then count = item.stackCount end
				if type(count) == "number" and count >= 0 then
					local id = tonumber(itemLink:match("item:(%d+)"))
					local name = itemLink:match("%[(.-)%]")
					if id then counts[id] = (counts[id] or 0) + count end
					if name then counts[name] = (counts[name] or 0) + count end
				end
			end
		end
	end
	return counts
end

-- Fill the native auction search field without submitting a query or purchase.
function ShoppingList:SearchAuctions(entry)
	local search = AuctionFrameBrowse and AuctionFrameBrowse.SearchBox or BrowseName
	local auction = AuctionFrame or AuctionHouseFrame
	if not search and AuctionHouseFrame and AuctionHouseFrame.SearchBar then
		search = AuctionHouseFrame.SearchBar.SearchBox
	end
	if not auction or not auction:IsShown() or not search or not search.SetText then
		print("|cff00ff00CraftRoster|r: open the Auction House, then click the material again to fill its search field.")
		return false
	end
	search:SetText(entry.name)
	if search.SetFocus then search:SetFocus() end
	if search.HighlightText then search:HighlightText() end
	return true
end

function ShoppingList:DrawRows()
	local frame = self.frame
	local entries = self.entries or {}
	local offset = frame.Scroll:GetVerticalScroll()
	local maximum = math.max(0, #entries * ROW_HEIGHT - frame.Scroll:GetHeight())
	if offset > maximum then offset = maximum; frame.Scroll:SetVerticalScroll(offset) end
	local first = math.max(1, math.floor(offset / ROW_HEIGHT) + 1)
	local last = math.min(#entries, first + math.min(19, math.ceil(frame.Scroll:GetHeight() / ROW_HEIGHT)))
	local used = 0
	for index = first, last do
		used = used + 1
		local row = frame.Rows[used]
		if not row then
			row = CreateFrame("Button", nil, frame.Content)
			local label = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
			label:SetPoint("TOPLEFT",38,-3); label:SetPoint("BOTTOMRIGHT",0,3); label:SetJustifyH("LEFT"); label:SetWordWrap(true)
			label:SetMaxLines(4)
			row.Icon=row:CreateTexture(nil,"ARTWORK"); row.Icon:SetSize(32,32); row.Icon:SetPoint("LEFT",2,0)
			row:SetFontString(label); row:SetSize(296, ROW_HEIGHT)
			row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
			row:SetScript("OnClick", function(self, button)
				if button == "RightButton" then ShoppingList:EditCrafterShare(self.entry)
				else CraftRoster.ItemDisplay:Click(self.entry) end
			end)
			row:SetScript("OnEnter", function(self)
				local material = self.entry
				GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
				local shown = material.itemID and type(GameTooltip.SetHyperlink)=="function"
					and pcall(GameTooltip.SetHyperlink, GameTooltip, "item:" .. material.itemID)
				if not shown then GameTooltip:SetText(material.name) end
				GameTooltip:AddLine(("Recipe requires: %d · crafter provides: %d"):format(material.recipeRequired, material.crafterProvides or 0), 1, 1, 1)
				GameTooltip:AddLine(("Your share: %d · in bags: %s"):format(material.required, material.owned and tostring(material.owned) or "?"), 1, 1, 1)
				ShoppingList:AddBankTooltip(material)
				if (material.delivered or 0)>0 then GameTooltip:AddLine("Already delivered: "..material.delivered,1,1,1) end
				GameTooltip:AddLine("Click: whisper/chat link, or AH search. Right-click: crafter share.", 1, 1, 1); GameTooltip:Show()
			end)
			row:SetScript("OnLeave", function() GameTooltip:Hide() end)
			frame.Rows[used] = row
		end
		local entry = entries[index]
		row.entry = entry
		local count = entry.owned
		local ready = count and count >= entry.required
		row.Icon:SetTexture(entry.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
		local text = ("%s\n%s/%d"):format(entry.name, count and tostring(count) or "?", entry.required)
		if count and not ready then text = text .. ("  (need %d in bags)"):format(entry.required - count) end
		local bank=self:BankSummary(entry,true)
		if bank and bank~="" then text=text.."\n"..bank end
		row:SetText((ready and "|cff33ff66" or "|cffffd166") .. text .. "|r")
		row:ClearAllPoints(); row:SetPoint("TOPLEFT", 0, -(index - 1) * ROW_HEIGHT)
		row:Show()
	end
	for index = used + 1, #frame.Rows do frame.Rows[index]:Hide() end
end

function ShoppingList:GetMaterialStatus(recipeID, crafter)
	local entries=Materials({materials=CraftRoster.RecipeSources and CraftRoster.RecipeSources:GetMaterials(recipeID)},self:GetQuantity(recipeID))
	if not entries then return nil,0,false end
	local getCount=C_Item and C_Item.GetItemCount or GetItemCount
	local counts=not getCount and BagCounts() or nil
	local ready,unavailable=0,false
	local contribution=Contribution(recipeID,crafter)
	local delivered=crafter and CraftRoster.Requests and CraftRoster.Requests:GetDeliveredMaterials(recipeID,crafter,self:GetQuantity(recipeID)) or {}
	local snapshot=CraftRoster.BankMaterials:Snapshot()
	for _,entry in ipairs(entries) do
		entry.recipeRequired=entry.required
		entry.crafterProvides=math.min(entry.required,contribution[entry.itemID or entry.name] or 0)
		entry.delivered=math.min(entry.required-entry.crafterProvides,delivered[entry.itemID or entry.name] or 0)
		entry.required=math.max(0,entry.required-entry.crafterProvides-entry.delivered)
		if getCount then
			local ok,value=pcall(getCount,entry.itemID or entry.name,false,false,false,false)
			if ok and type(value)=="number" and value>=0 then entry.owned=value end
		elseif counts then entry.owned=counts[entry.itemID or entry.name] or 0 end
		entry.bank=CraftRoster.BankMaterials:GetCount(entry.itemID or entry.name,snapshot or false)
		entry.bankDirty=snapshot and snapshot.dirty
		entry.bankScannedAt=snapshot and snapshot.scannedAt
		if entry.owned~=nil and entry.bank~=nil then
			entry.totalOwned=entry.owned+entry.bank
			entry.withdraw=math.min(entry.bank,math.max(0,entry.required-entry.owned))
			entry.missing=math.max(0,entry.required-entry.totalOwned)
		end
		if entry.owned==nil then unavailable=true
		elseif entry.owned>=entry.required then ready=ready+1 end
	end
	return entries,ready,unavailable
end

function ShoppingList:BankSummary(entry,compact)
	if entry.bankDirty then return "Bank: ? (reopen to refresh)" end
	if entry.bank==nil then return "Bank: ? (visit bank to scan)" end
	if compact then return "Bank: "..entry.bank.." (saved)" end
	local text="Bank: "..entry.bank.." (last seen)"
	if entry.withdraw and entry.withdraw>0 then text=text.." · withdraw "..entry.withdraw end
	if entry.missing and entry.missing>0 then text=text.." · missing "..entry.missing end
	return text
end

function ShoppingList:AddBankTooltip(entry)
	GameTooltip:AddLine(self:BankSummary(entry),1,1,1,true)
	if entry.bankScannedAt then
		GameTooltip:AddLine("Personal bank last scanned: "..date("%b %d, %I:%M %p",entry.bankScannedAt),1,1,1,true)
		GameTooltip:AddLine("Withdraw bank materials before trading or mailing. Bank counts are private.",1,1,1,true)
	end
end

function ShoppingList:Refresh()
	local state = GetState()
	if not state or not self.frame or not self.frame:IsShown() then return end
	if not state.recipeID then self:Clear();return end
 self.frame.Clear:SetEnabled(true)
 local recipe = CraftRosterDB.recipes[state.recipeID]
 local title = (recipe and recipe.name or ("Recipe " .. tostring(state.recipeID))) .. " · " .. self:GetQuantity(state.recipeID) .. (self:GetQuantity(state.recipeID) == 1 and " craft" or " crafts")
	if state.crafter then title = title .. "\nCrafter: " .. state.crafter end
	self.frame.Recipe:SetText(title)
	local entries,ready,unavailable=self:GetMaterialStatus(state.recipeID,state.crafter)
	self.entries=entries or {}
	if not entries then
		self.frame.Message:SetText("No material data yet.\nScan this recipe locally.")
		self.frame.Message:Show(); self.frame.Summary:SetText("Waiting for recipe data")
	else
		self.frame.Message:Hide()
		self.frame.Summary:SetText(unavailable and "Inventory counts unavailable" or ("%d of %d materials ready in bags"):format(ready,#entries))
	end
	self.frame:SetHeight(math.min(312, math.max(160, 144 + #self.entries * ROW_HEIGHT)))
	self.frame.Content:SetHeight(math.max(1, #self.entries * ROW_HEIGHT))
	self:DrawRows()
end

function ShoppingList:ScheduleRefresh()
	if CraftRoster.SelectedCraft then CraftRoster.SelectedCraft:ScheduleRefresh() end
	if not self.frame or not self.frame:IsShown() or refreshTimer then return end
	if C_Timer and C_Timer.NewTimer then
		refreshTimer = C_Timer.NewTimer(0.1, function() refreshTimer = nil; self:Refresh() end)
	else self:Refresh() end
end

function ShoppingList:Clear()
 local state=GetState()
 if not state then return false end
 state.recipeID=nil;state.crafter=nil;state.visible=false
 -- Clearing the active list does not change craft quantities, deliveries or
 -- saved contributions, which belong to craft/request workflows.
 self.entries={}
 if refreshTimer then refreshTimer:Cancel();refreshTimer=nil end
 if self.frame then
  for _,row in ipairs(self.frame.Rows or {}) do row:Hide() end
  self.frame.Scroll:SetVerticalScroll(0);self.frame.Content:SetHeight(1)
  self.frame.Recipe:SetText("Shopping list is empty")
  self.frame.Summary:SetText("");self.frame.Message:SetText("Choose a recipe to start a new list.");self.frame.Message:Show()
  self.frame.Clear:SetEnabled(false)
 end
 return true
end

function ShoppingList:Close()
	local state = GetState()
	if state then state.visible = false end
	if self.frame then self.frame:Hide() end
end

function ShoppingList:Initialize()
	if self.frame then return end
	local frame = CreateFrame("Frame", "CraftRosterShoppingList", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
	self.frame = frame
	frame:Hide(); frame:SetSize(340, 150)
	frame:SetFrameStrata("HIGH"); frame:SetMovable(true); frame:SetClampedToScreen(true)
	frame:EnableMouse(true); frame:RegisterForDrag("LeftButton")
	frame:SetBackdrop({bgFile = "Interface\\Tooltips\\UI-Tooltip-Background", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 12})
	frame:SetBackdropColor(0.03, 0.03, 0.03, 0.92)
	frame:SetBackdropBorderColor(0.55,0.43,0.22,0.9)
	frame:SetScript("OnDragStart", frame.StartMoving)
	frame:SetScript("OnDragStop", function()
		frame:StopMovingOrSizing()
		local state = GetState()
		if state then
			local point, _, _, x, y = frame:GetPoint()
			state.point, state.x, state.y = point, x, y
		end
	end)
	frame.Title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	frame.Title:SetPoint("TOPLEFT", 12, -10); frame.Title:SetText("Shopping List")
	CraftRoster.Theme:Heading(frame.Title)
	CraftRoster.Theme:TrackPanel(frame)
	CraftRoster.Theme:Window(frame)
	frame.Recipe = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	frame.Recipe:SetPoint("TOPLEFT", 12, -34); frame.Recipe:SetWidth(296)
	frame.Recipe:SetHeight(36)
	frame.Recipe:SetWordWrap(false)
	if frame.Recipe.SetMaxLines then frame.Recipe:SetMaxLines(2) end
	frame.Close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
	frame.Close:SetSize(22, 22); frame.Close:SetPoint("TOPRIGHT", -2, -2)
	frame.Close:SetScript("OnClick", function() self:Close() end)
	frame.Scroll = CreateFrame("ScrollFrame", nil, frame, "UIPanelScrollFrameTemplate")
	frame.Scroll:SetPoint("TOPLEFT", 12, -78); frame.Scroll:SetPoint("BOTTOMRIGHT", -28, 56)
	frame.Content = CreateFrame("Frame", nil, frame.Scroll)
	frame.Content:SetSize(296, 1); frame.Scroll:SetScrollChild(frame.Content)
	frame.Rows = {}
	frame.Scroll:HookScript("OnVerticalScroll", function() self:DrawRows() end)
	frame.Scroll:HookScript("OnSizeChanged", function() self:DrawRows() end)
	frame.Message = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	frame.Message:SetPoint("TOPLEFT", 12, -80); frame.Message:SetWidth(296)
	frame.Summary = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	frame.Summary:SetPoint("BOTTOMLEFT", 12, 34);frame.Summary:SetWidth(296)
 frame.Clear=CreateFrame("Button",nil,frame,"UIPanelButtonTemplate")
 frame.Clear:SetSize(82,22);frame.Clear:SetPoint("BOTTOMRIGHT",-12,6);frame.Clear:SetText("Clear list")
 CraftRoster.Theme:Button(frame.Clear)
 frame.Clear:SetScript("OnClick",function() self:Clear() end)
	frame.Hint = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	frame.Hint:SetPoint("BOTTOMLEFT", 12, 10);frame.Hint:SetWidth(202)
	frame.Hint:SetText("Click: chat / AH · Right: share")
	frame:SetScript("OnEvent", function() self:ScheduleRefresh() end)
	frame:SetScript("OnHide", function()
		frame:UnregisterAllEvents()
		if refreshTimer then refreshTimer:Cancel(); refreshTimer = nil end
	end)
	local state = GetState()
	local points = {CENTER=true, TOP=true, BOTTOM=true, LEFT=true, RIGHT=true, TOPLEFT=true, TOPRIGHT=true, BOTTOMLEFT=true, BOTTOMRIGHT=true}
	local point = state and points[state.point] and state.point or "CENTER"
	frame:SetPoint(point, UIParent, point, state and tonumber(state.x) or 300, state and tonumber(state.y) or 0)
end

function ShoppingList:Open(recipeID)
	local state = GetState()
	if not state or type(recipeID) ~= "number" or not CraftRosterDB.recipes[recipeID] then return end
	local selected = CraftRoster.Directory and CraftRoster.Directory.selectedRecipe
	local crafter = selected and selected.id == recipeID and CraftRoster.Directory.selectedCrafter
	if crafter then state.crafter = crafter elseif state.recipeID ~= recipeID then state.crafter = nil end
	state.recipeID, state.visible = recipeID, true
	self:Initialize(); self.frame:Show(); self.frame.Scroll:SetVerticalScroll(0)
	-- Some older clients lack BAG_UPDATE_DELAYED, so support both event paths.
	pcall(function() self.frame:RegisterEvent("BAG_UPDATE_DELAYED") end)
	self.frame:RegisterEvent("BAG_UPDATE")
	self:Refresh()
end

function ShoppingList:Restore()
	local state = GetState()
	if state and state.visible and state.recipeID then self:Open(state.recipeID) end
end

function ShoppingList:Toggle()
	if self.frame and self.frame:IsShown() then self:Close(); return end
	local state = GetState()
	if state and state.recipeID then self:Open(state.recipeID)
	else print("|cff00ff00CraftRoster|r: select a recipe, then click Shopping List.") end
end
