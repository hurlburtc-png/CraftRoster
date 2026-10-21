local ADDON_NAME, CraftRoster = ...
local Orders = {}
CraftRoster.WorkOrders = Orders

local MAX_ORDERS, ROW_HEIGHT = 500, 110
local professionIDs = {Alchemy=171,Blacksmithing=164,Cooking=185,Enchanting=333,Engineering=202,["First Aid"]=129,Leatherworking=165,Mining=186,Tailoring=197}
local professionSpells = {Alchemy=2259,Blacksmithing=2018,Cooking=2550,Enchanting=7411,Engineering=4036,["First Aid"]=3273,Leatherworking=2108,Mining=2575,Tailoring=3908}
local function Normalize(name)
	if type(name) ~= "string" or name == "" then return nil end
	if not name:find("-",1,true) then name = name .. "-" .. (GetRealmName() or "") end
	return name:lower():gsub("%s", "")
end
local function CleanCustomer(customer)
	if type(customer)~="string" then return end
	customer=customer:match("^%s*(.-)%s*$")
	local name,realm=customer:match("^([^%-]+)%-(.+)$")
	if name and realm then customer=name .. "-" .. realm:gsub("%s", "")
	elseif customer:find("-",1,true) then return end
	if #customer==0 or #customer>100 or not customer:match("^[^%s:|%-]+%-?[^%s:|]*$") then return end
	return customer
end
local function State()
	if not CraftRosterDB then return end
	CraftRosterDB.workOrders = CraftRosterDB.workOrders or {}
	local key = Normalize(UnitName("player"))
	CraftRosterDB.workOrders[key] = CraftRosterDB.workOrders[key] or {orders={},sequence=0}
	return CraftRosterDB.workOrders[key]
end
local function Active(order) return order.status ~= "completed" and order.status ~= "declined" and order.status ~= "cancelled" end
local function Recipe(order) return CraftRosterDB.recipes and CraftRosterDB.recipes[order.recipeID] end
local function Known(recipeID)
	local key = UnitName("player") .. "-" .. (GetRealmName() or "")
	local player = CraftRosterDB.characters and CraftRosterDB.characters[key]
	return player and player.recipes and player.recipes[recipeID] ~= nil
end
local function Say(message) print("|cff00ff00CraftRoster|r: " .. message) end
local function SafeCall(fn, ...)
	if type(fn) ~= "function" then return false end
	return pcall(fn, ...)
end

function Orders:GetOrders(customer,allCharacters)
	local state, out = State(), {}
	local current=Normalize(UnitName("player"))
	for _, order in ipairs(state and state.orders or {}) do
		if Active(order) and (not customer or Normalize(order.customer) == Normalize(customer)) then table.insert(out, order) end
	end
	if allCharacters then
		for owner,archive in pairs(CraftRosterDB.workOrders or {}) do
			if owner~=current and type(archive)=="table" and type(archive.orders)=="table" then
				for _,order in ipairs(archive.orders) do
					if Active(order) and (not customer or Normalize(order.customer)==Normalize(customer)) then
						-- View-only ownership tags never alter the saved order or current character.
						table.insert(out,setmetatable({ownerCharacter=owner,readOnly=true},{__index=order}))
					end
				end
			end
		end
	end
	table.sort(out,function(a,b)
		if a.at==b.at then
			if a.id==b.id then return (a.ownerCharacter or current)<(b.ownerCharacter or current) end
			return a.id<b.id
		end
		return a.at<b.at
	end)
	return out
end

function Orders:Find(id)
	for _, order in ipairs(State().orders) do if order.id == id then return order end end
end
function Orders:FindRequest(requestID,customer)
	for _,order in ipairs(State().orders) do
		if order.requestID==requestID and Normalize(order.customer)==Normalize(customer) then return order end
	end
end
function Orders:UpdateRequestStatus(requestID,customer,status)
	local order=self:FindRequest(requestID,customer)
	if order and Active(order) then
		order.status=status
		if status=="completed" then order.done=order.quantity end
		if status=="completed" or status=="declined" or status=="cancelled" then order.closedAt=time() end
		self:Refresh()
	end
end
function Orders:Add(customer, recipeID, quantity, requestID, source)
	customer=CleanCustomer(customer)
	if not customer then
		if source=="manual" or source==nil then Say("Enter a valid customer name, such as Name-Realm. Spaces in a realm name are allowed.") end
		return
	end
	if type(recipeID) ~= "number" or recipeID<=0 or recipeID~=math.floor(recipeID) then return end
	if type(quantity)~="number" or quantity<1 or quantity>999 or quantity~=math.floor(quantity) then return end
	local state = State()
	local identity = Normalize(customer)
	if not state or identity == Normalize(UnitName("player")) then return end
	if requestID then
		for _, order in ipairs(state.orders) do
			if order.requestID == requestID and Normalize(order.customer)==identity then return order end
		end
	end
	local needsReview=false
	-- Merge the addon request and its human-readable whisper, not two distinct orders.
	if source == "addon" or source == "whisper" then
		local other = source=="addon" and "whisper" or "addon"
		for _, order in ipairs(state.orders) do
			if not Active(order) and Normalize(order.customer)==identity and order.recipeID==recipeID and order.quantity==quantity
				and order.sources and order.sources[other] and not order.sources[source] and time()-(order.closedAt or order.at)<=30 then needsReview=true end
			if Active(order) and Normalize(order.customer)==identity and order.recipeID==recipeID and order.quantity==quantity
				and order.sources and order.sources[other] and not order.sources[source] then
				order.sources[source]=true; order.requestID=requestID or order.requestID
				if requestID and order.status=="accepted" and CraftRoster.Requests and CraftRoster.Requests.SetIncomingStatus then
					CraftRoster.Requests:SetIncomingStatus(requestID,order.customer,"accepted")
				end
				self:Refresh(); return order
			end
		end
	end
	-- Prune closed history only; never silently discard an outstanding order.
	while #state.orders >= MAX_ORDERS do
		local closed
		for i, order in ipairs(state.orders) do if not Active(order) then closed=i; break end end
		if not closed then Say("Work orders are full. Close old orders before adding more."); return end
		local retired=state.orders[closed].id
		if self.selected then self.selected[retired]=nil end
		if self.batchValues then self.batchValues[retired]=nil end
		if self.craftClicks then self.craftClicks[retired]=nil end
		table.remove(state.orders,closed)
	end
	state.sequence=state.sequence+1
	local order = {id=state.sequence,customer=customer,recipeID=recipeID,quantity=quantity,done=0,status=needsReview and "needs_review" or "requested",at=time(),requestID=requestID,sources={[source or "manual"]=true}}
	table.insert(state.orders,order)
	self.selected=self.selected or {}; self.selected[order.id]=true
	self:Refresh()
	if needsReview then Say("Possible duplicate order for " .. customer .. ". Review and Accept or Decline it before crafting.")
	else Say("Work order added for " .. customer .. ". Open /cr orders to review it.") end
	return order
end
function Orders:ReceiveRequest(request)
	local quantity=tonumber(request.recipe and request.recipe:match("^(%d+) crafts of ")) or 1
	return self:Add(request.target,request.recipeID,quantity,request.id,"addon")
end
function Orders:SetStatus(id,status)
	local order = self:Find(id)
	if not order or (status~="accepted" and status~="declined" and status~="completed") then return false end
	if not Active(order) then return false end
	order.status=status
	if status=="completed" then order.done=order.quantity end
	if status=="completed" or status=="declined" or status=="cancelled" then order.closedAt=time() end
	-- Request status remains local if guild transport is unavailable. It is never a chat whisper.
	if order.requestID and order.sources and order.sources.addon and CraftRoster.Requests and CraftRoster.Requests.SetIncomingStatus then
		CraftRoster.Requests:SetIncomingStatus(order.requestID,order.customer,status)
	end
	self:Refresh(); return true
end
function Orders:ConfirmDone(id,count)
	local order=self:Find(id)
	if not order or not Active(order) then return false end
	if order.status=="needs_review" then Say("Review and Accept this possible duplicate before updating its result."); return false end
	local remaining=order.quantity-(order.done or 0)
	if type(count)~="number" or count~=math.floor(count) or count<1 or count>remaining then
		Say("Enter the actual completed quantity from 1 to " .. remaining .. "."); return false
	end
	if (UnitCastingInfo and UnitCastingInfo("player")) or (UnitChannelInfo and UnitChannelInfo("player")) then
		Say("Wait until crafting finishes or is cancelled before confirming its results."); return false
	end
	order.done=(order.done or 0)+count; order.lastBatchCount=nil
	if order.done==order.quantity then self:SetStatus(id,"completed")
	elseif order.status~="accepted" then self:SetStatus(id,"accepted") else self:Refresh() end
	return true
end
function Orders:OneDone(id) return self:ConfirmDone(id,1) end
function Orders:PromptDone(id)
	local order=self:Find(id)
	if not order or not Active(order) then return end
	if (order.lastBatchCount or 1)>1 then
		local recipe=Recipe(order)
		local remaining=order.quantity-(order.done or 0)
		StaticPopup_Show("CRAFTROSTER_CONFIRM_BATCH",recipe and recipe.name or ("Recipe "..order.recipeID),tostring(remaining),{id=id,count=math.min(order.lastBatchCount,remaining)})
	else self:OneDone(id) end
end

local function CurrentCustomer()
	local name,realm
	if UnitFullName then name,realm=UnitFullName("NPC") else name,realm=UnitName("NPC") end
	if name then return name .. "-" .. (realm and realm~="" and realm or (GetRealmName() or "")) end
end
function Orders:OpenProfession(recipe)
	local id=recipe.professionID or professionIDs[recipe.profession]
	if C_TradeSkillUI and C_TradeSkillUI.OpenTradeSkill and id then
		local ok,opened=SafeCall(C_TradeSkillUI.OpenTradeSkill,id)
		if ok and opened~=false then Say("Profession opened. Click this order's craft button again when loaded."); return true end
	end
	local spell=professionSpells[recipe.profession]
	local name=recipe.profession
	if spell then
		if C_Spell and C_Spell.GetSpellInfo then
			local ok,info=SafeCall(C_Spell.GetSpellInfo,spell); if ok and info then name=info.name or name end
		elseif GetSpellInfo then local ok,value=SafeCall(GetSpellInfo,spell); if ok and value then name=value end end
	end
	if CastSpellByName and name then
		local ok=SafeCall(CastSpellByName,name)
		if ok then Say("Profession opened. Click the order again when loaded."); return true end
	end
	Say("Open " .. (recipe.profession or "the profession") .. " once, then click this order. No manual recipe search is needed.")
	return false
end
function Orders:IsEnchant(order)
	local recipe=Recipe(order)
	if not recipe then return false end
	if CraftRoster.RecipeSources and CraftRoster.RecipeSources:IsEnchant(order.recipeID) then return true end
	return (recipe.professionID==333 or recipe.profession=="Enchanting") and not (CraftRoster.RecipeSources and CraftRoster.RecipeSources:GetOutputItemID(order.recipeID))
end
function Orders:Craft(id, requestedCount)
	local order=self:Find(id)
	if not CraftRosterDB.settings.enabled then Say("CraftRoster is disabled. Enable it before crafting."); return false end
	if not order or not Active(order) or (self.selected and self.selected[id]==false) then return false end
	if order.status=="needs_review" then Say("Review and Accept this possible duplicate before crafting."); return false end
	local remaining=math.max(0,order.quantity-(order.done or 0))
	local count=requestedCount=="all" and remaining or (requestedCount==nil and 1 or requestedCount)
	if type(count)~="number" or count~=math.floor(count) or count<1 or count>remaining then
		Say("Enter a whole craft quantity from 1 to " .. remaining .. "."); return false
	end
	if InCombatLockdown and InCombatLockdown() then Say("Crafting is unavailable in combat."); return false end
	if UnitCastingInfo and UnitCastingInfo("player") then Say("Finish the current craft first."); return false end
	if UnitChannelInfo and UnitChannelInfo("player") then Say("Finish the current channel first."); return false end
	if SpellIsTargeting and SpellIsTargeting() then Say("Finish or cancel the current item targeting before choosing another enchant."); return false end
	local recipe=Recipe(order)
	if not recipe or not Known(order.recipeID) then Say("This recipe is not confirmed learned. Scan your profession before crafting."); return false end
	if self.tradeOpen and Normalize(CurrentCustomer())~=Normalize(order.customer) then
		Say("This order belongs to another customer. Finish this trade before crafting it."); return false
	end
	local enchant=self:IsEnchant(order)
	if enchant and count~=1 then Say("Apply enchants one at a time to the selected item."); return false end
	local now=GetTime and GetTime() or time()
	self.craftClicks=self.craftClicks or {}
	if self.craftClicks[id] and now-self.craftClicks[id]<0.35 then Say("Craft request pending. Wait for the game to respond before clicking again."); return false end
	local modern=C_TradeSkillUI
	if modern and modern.GetRecipeInfo then
		for _,method in ipairs({"IsTradeSkillLinked","IsTradeSkillGuild","IsNPCCrafting"}) do
			if modern[method] then
				local ok,remote=SafeCall(modern[method])
				if ok and remote then Say("Close the linked or remote profession and open your own profession first."); return false end
			end
		end
		if modern.IsTradeSkillReady then
			local ok,ready=SafeCall(modern.IsTradeSkillReady)
			if not ok or not ready then self:OpenProfession(recipe); return false end
		end
		if modern.GetBaseProfessionInfo then
			local ok,base=SafeCall(modern.GetBaseProfessionInfo)
			local expected=recipe.professionID or professionIDs[recipe.profession]
			local actual=ok and base and (base.parentProfessionID or base.professionID)
			if not actual or (expected and actual~=expected) then self:OpenProfession(recipe); return false end
		end
		local ok,info=SafeCall(modern.GetRecipeInfo,order.recipeID)
		if ok and info and info.learned==true then
			local fn=enchant and modern.CraftEnchant or modern.CraftRecipe
			-- Some clients use the generic recipe entry point for enchants.
			if not fn and enchant then fn=modern.CraftRecipe end
			if type(fn)=="function" then
				local success, result=SafeCall(fn,order.recipeID,count)
				if success and result~=false then
					self.craftClicks[id]=now; order.lastBatchCount=count; self:Refresh()
					Say(enchant and "Enchant selected. Click the customer's correct item in the trade window, then review before accepting." or ("Craft batch requested (" .. count .. "). Mark results done only after checking them."))
					return true
				end
				Say("The client rejected this craft. Check materials, profession access and the game's error message."); return false
			end
		end
	end
	-- Re-find the index every click: sorted/filtered profession lists can change.
	if GetNumTradeSkills and GetTradeSkillRecipeLink and DoTradeSkill then
		local ok,listCount=SafeCall(GetNumTradeSkills)
		if ok and type(listCount)=="number" then
			for index=1,listCount do
				local linkOK,link=SafeCall(GetTradeSkillRecipeLink,index)
				local found=linkOK and type(link)=="string" and tonumber(link:match("enchant:(%d+)") or link:match("spell:(%d+)"))
				if found==order.recipeID then
					local success,result=SafeCall(DoTradeSkill,index,count)
					if not success or result==false then Say("Craft rejected. Check the game's error message."); return false end
					self.craftClicks[id]=now; order.lastBatchCount=count; self:Refresh()
					Say(enchant and "Enchant selected. Click the correct traded item before accepting." or ("Craft batch requested (" .. count .. "). Confirm results before marking done."))
					return true
				end
			end
		end
	end
	-- Vanilla-style enchanting uses CraftFrame rather than TradeSkillFrame.
	if GetNumCrafts and GetCraftRecipeLink and DoCraft then
		local ok,count=SafeCall(GetNumCrafts)
		if ok and type(count)=="number" then
			for index=1,count do
				local linkOK,link=SafeCall(GetCraftRecipeLink,index)
				local found=linkOK and type(link)=="string" and tonumber(link:match("enchant:(%d+)") or link:match("spell:(%d+)"))
				if found==order.recipeID then
					local success,result=SafeCall(DoCraft,index)
					if success and result~=false then self.craftClicks[id]=now; order.lastBatchCount=1; self:Refresh(); Say("Enchant selected. Click the correct traded item before accepting."); return true end
					return false
				end
			end
		end
	end
	Say("If the correct profession is already open, clear its search filters and expand collapsed categories so this recipe is visible.")
	self:OpenProfession(recipe)
	return false
end

function Orders:CaptureWhisper(text,customer)
	if type(text)~="string" or #text>1024 then return end
	local requested=text:match("^CraftRoster: Could you craft (.-)%? Materials:")
	if not requested then return end
	local quantity,body=requested:match("^(%d+) crafts of (.*)$")
	quantity=tonumber(quantity) or 1; body=body or requested
	local itemID=tonumber(body:match("|Hitem:(%d+)"))
	local name=body:match("|h%[(.-)%]|h") or body
	local recipeID
	for id,recipe in pairs(CraftRosterDB.recipes or {}) do
		if Known(id) and ((itemID and CraftRoster.RecipeSources and CraftRoster.RecipeSources:GetOutputItemID(id)==itemID)
			or (type(recipe.name)=="string" and recipe.name:lower()==name:lower())) then
			if recipeID and recipeID~=id then Say("Ambiguous whisper recipe; add this order manually."); return end
			recipeID=id
		end
	end
	if recipeID then return self:Add(customer,recipeID,quantity,nil,"whisper") end
end

function Orders:Initialize()
	if self.frame then return end
	local frame=CreateFrame("Frame","CraftRosterWorkOrders",UIParent,"BasicFrameTemplateWithInset")
	self.frame=frame; self.selected=self.selected or {}; self.batchValues=self.batchValues or {}
	frame:SetSize(640,450); frame:SetPoint("CENTER"); frame:SetClampedToScreen(true); frame:SetFrameStrata("HIGH")
	frame:SetMovable(true); frame:EnableMouse(true); frame:RegisterForDrag("LeftButton")
	frame:SetScript("OnDragStart",frame.StartMoving); frame:SetScript("OnDragStop",frame.StopMovingOrSizing)
	local title=frame.TitleText or frame.TitleBar.TitleText
	title:SetText("CraftRoster — Work Orders")
	local close=CreateFrame("Button",nil,frame,"UIPanelCloseButton"); close:SetPoint("TOPRIGHT",-3,-3)
	close:SetScript("OnClick",function() frame:Hide() end)
	frame.Status=frame:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
	frame.Status:SetPoint("TOPLEFT",14,-34); frame.Status:SetWidth(608); frame.Status:SetJustifyH("LEFT")
	local filter=CreateFrame("Button",nil,frame,"UIPanelButtonTemplate"); frame.Filter=filter
	filter:SetSize(150,22); filter:SetPoint("TOPLEFT",14,-58)
	filter:SetScript("OnClick",function() self.customerFilter=nil; self:Refresh() end); filter:SetText("Show all customers")
	local add=CreateFrame("Button",nil,frame,"UIPanelButtonTemplate"); add:SetSize(190,22); add:SetPoint("LEFT",filter,"RIGHT",8,0)
	add:SetText("Add selected recipe order")
	add:SetScript("OnClick",function()
		local recipe=CraftRoster.Directory and CraftRoster.Directory.selectedRecipe
		if not recipe then Say("Select a recipe in the directory, then click Add order."); return end
		StaticPopup_Show("CRAFTROSTER_ADD_ORDER",recipe.name,nil,{recipeID=recipe.id,quantity=CraftRoster.ShoppingList:GetQuantity(recipe.id)})
	end)
	frame.CharacterFilter=CreateFrame("Button",nil,frame,"UIPanelButtonTemplate")
	frame.CharacterFilter:SetSize(146,22); frame.CharacterFilter:SetPoint("LEFT",add,"RIGHT",8,0)
	frame.CharacterFilter:SetText("This character")
	frame.CharacterFilter:SetScript("OnClick",function()
		self.allCharacters=not self.allCharacters; frame.Scroll:SetVerticalScroll(0); self:Refresh()
	end)
	frame.Scroll=CreateFrame("ScrollFrame",nil,frame,"UIPanelScrollFrameTemplate")
	frame.Scroll:SetPoint("TOPLEFT",12,-88); frame.Scroll:SetPoint("BOTTOMRIGHT",-30,42)
	frame.Content=CreateFrame("Frame",nil,frame.Scroll); frame.Content:SetSize(592,1); frame.Scroll:SetScrollChild(frame.Content)
	frame.Rows={}
	frame.Scroll:HookScript("OnVerticalScroll",function() self:DrawRows() end)
	frame.Empty=frame:CreateFontString(nil,"OVERLAY","GameFontHighlight")
	frame.Empty:SetPoint("TOPLEFT",18,-98); frame.Empty:SetText("No outstanding orders for this customer.")
	local hint=frame:CreateFontString(nil,"OVERLAY","GameFontDisableSmall")
	hint:SetPoint("BOTTOMLEFT",14,13); hint:SetWidth(606)
	hint:SetText("Choose any order. Craft 1, a number, or the remaining quantity. Enchants apply once. Mark results done after checking them.")
	frame:Hide()
end
function Orders:DrawRows()
	local frame=self.frame
	if not frame then return end
	local entries=self.visibleOrders or {}
	local offset=frame.Scroll:GetVerticalScroll()
	local max=math.max(0,#entries*ROW_HEIGHT-frame.Scroll:GetHeight())
	if offset>max then offset=max; frame.Scroll:SetVerticalScroll(offset) end
	local first=math.max(1,math.floor(offset/ROW_HEIGHT)+1)
	local last=math.min(#entries,first+math.ceil(frame.Scroll:GetHeight()/ROW_HEIGHT))
	local used=0
	for index=first,last do
		used=used+1
		local row=frame.Rows[used]
		if not row then
			row=CreateFrame("Frame",nil,frame.Content); row:SetSize(592,ROW_HEIGHT-4)
			row.Select=CreateFrame("CheckButton",nil,row,"UICheckButtonTemplate"); row.Select:SetSize(22,22); row.Select:SetPoint("TOPLEFT",0,-4)
			row.Select:SetScript("OnClick",function(button)
				if row.order.readOnly then return end
				self.selected[row.order.id]=button:GetChecked() and true or false; self:DrawRows()
			end)
			row.Text=row:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall"); row.Text:SetPoint("TOPLEFT",28,-5); row.Text:SetWidth(390); row.Text:SetHeight(30); row.Text:SetJustifyH("LEFT")
			if row.Text.SetMaxLines then row.Text:SetMaxLines(2) end
			row.Craft=CreateFrame("Button",nil,row,"UIPanelButtonTemplate"); row.Craft:SetSize(120,26); row.Craft:SetPoint("TOPRIGHT",-4,-4)
			row.Craft:SetScript("OnClick",function() if not row.order.readOnly then self:Craft(row.order.id) end end)
			row.Craft:SetScript("OnEnter",function(button)
				local recipe=Recipe(row.order)
				GameTooltip:SetOwner(button,"ANCHOR_RIGHT"); GameTooltip:SetText(recipe and recipe.name or "Unknown recipe")
				GameTooltip:AddLine("Craft 1 makes one; batch controls request a number of recipe executions. Enchants target one item. The client may require opening the profession first.",1,1,1,true)
				for _,material in ipairs(CraftRoster.RecipeSources:GetMaterials(row.order.recipeID) or {}) do
					GameTooltip:AddLine(("%d x %s per craft"):format(material.count,material.name),1,1,1)
				end
				GameTooltip:Show()
			end)
			row.Craft:SetScript("OnLeave",function() GameTooltip:Hide() end)
			row.BatchLabel=row:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
			row.BatchLabel:SetPoint("TOPLEFT",28,-44); row.BatchLabel:SetText("Number:")
			row.Batch=CreateFrame("EditBox",nil,row,"InputBoxTemplate"); row.Batch:SetSize(42,22); row.Batch:SetPoint("TOPLEFT",90,-38)
			row.Batch:SetAutoFocus(false); row.Batch:SetNumeric(true); row.Batch:SetMaxLetters(3)
			row.Batch:SetScript("OnTextChanged",function(edit,userInput)
				if userInput and row.order and not row.order.readOnly then self.batchValues[row.order.id]=edit:GetText() end
			end)
			row.Batch:SetScript("OnEnterPressed",function(edit) edit:ClearFocus() end)
			row.Batch:SetScript("OnEditFocusLost",function(edit)
				if row.order and not row.order.readOnly then self.batchValues[row.order.id]=edit:GetText() end
			end)
			row.BatchCraft=CreateFrame("Button",nil,row,"UIPanelButtonTemplate"); row.BatchCraft:SetSize(116,24); row.BatchCraft:SetPoint("TOPLEFT",146,-37)
			row.BatchCraft:SetText("Craft number")
			row.BatchCraft:SetScript("OnClick",function() if not row.order.readOnly then self:Craft(row.order.id,tonumber(row.Batch:GetText()) or false) end end)
			row.CraftAll=CreateFrame("Button",nil,row,"UIPanelButtonTemplate"); row.CraftAll:SetSize(146,24); row.CraftAll:SetPoint("TOPLEFT",274,-37)
			row.CraftAll:SetText("Craft remaining")
			row.CraftAll:SetScript("OnClick",function() if not row.order.readOnly then self:Craft(row.order.id,"all") end end)
			local function Action(text,x,width,fn)
				local button=CreateFrame("Button",nil,row,"UIPanelButtonTemplate"); button:SetSize(width,22); button:SetPoint("BOTTOMLEFT",x,6); button:SetText(text)
				button:SetScript("OnClick",function() if not row.order.readOnly then fn(row.order.id) end end); return button
			end
			row.Accept=Action("Accept",28,74,function(id) self:SetStatus(id,"accepted") end)
			row.Decline=Action("Decline",108,74,function(id) self:SetStatus(id,"declined") end)
			row.Done=Action("+1 done",468,120,function(id) self:PromptDone(id) end)
			frame.Rows[used]=row
		end
		local order=entries[index]
		local rowChanged=not row.order or row.order.id~=order.id or row.order.ownerCharacter~=order.ownerCharacter
		if rowChanged and row.Batch then row.Batch:ClearFocus() end
		row.order=order
		if self.selected[order.id]==nil then self.selected[order.id]=true end
		row.Select:SetChecked(self.selected[order.id])
		local recipe=Recipe(order)
		row.Text:SetText(order.customer .. " · " .. order.status:gsub("_"," ") .. (order.readOnly and (" · " .. order.ownerCharacter) or "") .. "\n" .. (recipe and recipe.name or ("Recipe "..order.recipeID)) .. " · " .. (order.done or 0) .. "/" .. order.quantity .. " crafts")
		local enchant=self:IsEnchant(order)
		local enabled=not not (not order.readOnly and order.status~="needs_review" and CraftRosterDB.settings.enabled and self.selected[order.id] and Known(order.recipeID) and not (InCombatLockdown and InCombatLockdown()))
		row.Craft:SetText(order.readOnly and "Other character" or order.status=="needs_review" and "Review order" or not CraftRosterDB.settings.enabled and "Addon disabled" or not Known(order.recipeID) and "Scan needed" or enchant and "Enchant" or "Craft 1")
		row.Craft:SetEnabled(enabled)
		if rowChanged or not (row.Batch.HasFocus and row.Batch:HasFocus()) then row.Batch:SetText(self.batchValues[order.id] or "1") end
		row.BatchCraft:SetEnabled(enabled and not enchant)
		row.CraftAll:SetEnabled(enabled and not enchant)
		if order.readOnly then row.BatchLabel:SetText("Switch to this character to craft or update this order")
		elseif enchant then row.BatchLabel:SetText("Enchants apply one at a time") else row.BatchLabel:SetText("Number:") end
		if enchant or order.readOnly then row.Batch:Hide(); row.BatchCraft:Hide(); row.CraftAll:Hide()
		else row.Batch:Show(); row.BatchCraft:Show(); row.CraftAll:Show() end
		if order.readOnly then row.Select:Hide() else row.Select:Show() end
		row.Accept:SetEnabled(not order.readOnly and order.status~="accepted")
		row.Decline:SetEnabled(not order.readOnly)
		row.Done:SetText((order.lastBatchCount or 1)>1 and "Confirm batch" or "+1 done")
		row.Done:SetEnabled(not order.readOnly and order.status~="needs_review")
		row:ClearAllPoints(); row:SetPoint("TOPLEFT",0,-(index-1)*ROW_HEIGHT); row:Show()
	end
	for index=used+1,#frame.Rows do frame.Rows[index]:Hide() end
end
function Orders:Refresh()
	if not self.frame or not self.frame:IsShown() then return end
	self.visibleOrders=self.tradeOpen and not self.tradeCustomer and {} or self:GetOrders(self.customerFilter,self.allCharacters)
	self.frame.CharacterFilter:SetText(self.allCharacters and "All characters" or "This character")
	local status
	if self.tradeOpen and not self.tradeCustomer then status="Trade partner unavailable — reopen the trade before choosing an order."
	elseif self.customerFilter then status=(self.tradeOpen and "Trading with " or "Orders for ") .. self.customerFilter .. " — choose any requested craft or enchant"
	else status="Outstanding orders — select any craft, in any order" end
	if self.allCharacters then status="All characters (other characters are read-only). " .. status end
	if not CraftRosterDB.settings.enabled then status="Addon disabled — enable CraftRoster to craft. " .. status end
	self.frame.Status:SetText(status)
	if #self.visibleOrders==0 then self.frame.Empty:Show() else self.frame.Empty:Hide() end
	self.frame.Content:SetHeight(math.max(1,#self.visibleOrders*ROW_HEIGHT))
	self:DrawRows()
end
function Orders:Open(customer)
	self:Initialize(); self.allCharacters=false; self.customerFilter=customer or (self.tradeOpen and self.tradeCustomer or nil); self.frame:Show(); self.frame.Scroll:SetVerticalScroll(0); self:Refresh()
end
function Orders:Toggle()
	if self.frame and self.frame:IsShown() then self.frame:Hide() else self:Open() end
end
StaticPopupDialogs.CRAFTROSTER_CONFIRM_BATCH={
	text="Confirm completed crafts for %s. After crafting has finished, enter how many actually succeeded (1–%s).",button1="Confirm results",button2="Cancel",hasEditBox=true,timeout=0,whileDead=true,hideOnEscape=true,
	OnShow=function(self)
		local edit=self.editBox or self.EditBox
		edit:SetNumeric(true); edit:SetMaxLetters(3); edit:SetText(tostring(self.data and self.data.count or 1)); edit:HighlightText()
	end,
	OnAccept=function(self)
		local edit=self.editBox or self.EditBox
		if self.data then Orders:ConfirmDone(self.data.id,tonumber(edit:GetText())) end
	end,
}
StaticPopupDialogs.CRAFTROSTER_ADD_ORDER={
	text="Customer requesting %s (Name-Realm). The directory's Crafts quantity will be used.",button1="Add order",button2="Cancel",hasEditBox=true,timeout=0,whileDead=true,hideOnEscape=true,
	OnShow=function(self) local edit=self.editBox or self.EditBox; edit:SetNumeric(false); edit:SetText(Orders.customerFilter or ""); edit:HighlightText() end,
	OnAccept=function(self)
		local edit=self.editBox or self.EditBox
		local customer=edit:GetText():match("^%s*(.-)%s*$")
		if self.data then Orders:Add(customer,self.data.recipeID,self.data.quantity,nil,"manual") end
	end,
}
SLASH_CRAFTROSTERORDERS1="/crorders"
SlashCmdList.CRAFTROSTERORDERS=function() Orders:Toggle() end
local events=CreateFrame("Frame")
for _,event in ipairs({"ADDON_LOADED","TRADE_SHOW","TRADE_CLOSED","CHAT_MSG_WHISPER","PLAYER_REGEN_ENABLED","PLAYER_REGEN_DISABLED"}) do events:RegisterEvent(event) end
events:SetScript("OnEvent",function(_,event,...)
	local arg1,arg2=...
	if event=="ADDON_LOADED" and arg1==ADDON_NAME then
		State()
		for _,request in ipairs(CraftRosterDB.requests or {}) do if request.mode=="incoming" and request.status~="completed" and request.status~="declined" and request.status~="cancelled" then Orders:ReceiveRequest(request) end end
	elseif event=="TRADE_SHOW" then
		Orders.tradeOpen=true
		local customer=CurrentCustomer()
		Orders.tradeCustomer=customer; Orders.customerFilter=customer
		if CraftRosterDB.settings.enabled and customer and #Orders:GetOrders(customer)>0 then Orders:Open(customer)
		elseif Orders.frame and Orders.frame:IsShown() then Orders.frame.Scroll:SetVerticalScroll(0); Orders:Refresh() end
	elseif event=="TRADE_CLOSED" then Orders.tradeOpen=false; Orders.tradeCustomer=nil; Orders:Refresh()
	elseif event=="CHAT_MSG_WHISPER" and CraftRosterDB and CraftRosterDB.settings.enabled then Orders:CaptureWhisper(arg1,arg2)
	elseif event=="PLAYER_REGEN_ENABLED" or event=="PLAYER_REGEN_DISABLED" then Orders:Refresh() end
end)
