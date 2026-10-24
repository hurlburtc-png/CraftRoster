local ADDON_NAME, CraftRoster = ...
local View = {}
CraftRoster.SelectedCraft = View
local timer

local function Visible()
	local directory=CraftRoster.Directory
	return directory and directory.frame and directory.frame:IsShown() and (not directory.activeTab or directory.activeTab==1)
end
local function Links()
	local recipe=CraftRoster.Directory.selectedRecipe
	return recipe and CraftRoster.Directory:GetSearchLinks(recipe.id)
end
local function Hover(button,link)
	if not link then return end
	GameTooltip:SetOwner(button,"ANCHOR_RIGHT")
	if not pcall(GameTooltip.SetHyperlink,GameTooltip,link) then GameTooltip:SetText("Item information is loading") end
	GameTooltip:Show()
end
local function Click(link,button,owner)
	if not link then return end
	if button=="RightButton" then StaticPopup_Show("CRAFTROSTER_COPY_LINK",nil,nil,link)
	elseif IsShiftKeyDown and IsShiftKeyDown() then
		if ChatEdit_InsertLink and ChatEdit_InsertLink(link) then return end
		if ChatFrame_OpenChat then ChatFrame_OpenChat(link) end
	elseif SetItemRef then
		local payload=link:match("|H(.-)|h")
		if payload and pcall(SetItemRef,payload,link,"LeftButton") then return end
		Hover(owner or UIParent,link)
	else Hover(owner or UIParent,link)
	end
end
local function Text(parent)
	local label=parent:CreateFontString(nil,"OVERLAY","GameFontHighlight")
	label:SetJustifyH("LEFT"); label:SetWordWrap(true)
	return label
end
local function Height(label,text,width)
	label:SetWidth(width)
 -- Remove the prior fixed height before measuring a different wrapped string.
 label:SetHeight(0);label:SetText(text)
	local measured=label.GetStringHeight and label:GetStringHeight()
 if type(measured)~="number" or measured<=0 then measured=nil end
	text=text:gsub("|T.-|t", "XX"):gsub("|H.-|h(.-)|h", "%1"):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
	local lines=0
	for line in (text.."\n"):gmatch("([^\n]*)\n") do lines=lines+math.max(1,math.ceil(#line/math.max(8,math.floor(width/7)))) end
	return math.max(18,tonumber(measured) or lines*15)
end


function View:Initialize(tab)
	self.tab=tab
	local scroll=CreateFrame("ScrollFrame",nil,tab,"UIPanelScrollFrameTemplate")
	tab.SelectedCraftScroll=scroll
	scroll:SetPoint("TOPLEFT",tab,"TOP",12,-76); scroll:SetPoint("BOTTOMRIGHT",tab,"BOTTOMRIGHT",-28,14)
	local content=CreateFrame("Frame",nil,scroll)
	tab.SelectedCraftContent=content; scroll:SetScrollChild(content); content:SetSize(300,540)
	content:SetPoint("TOPLEFT",scroll,"TOPLEFT",0,0)
	tab.Details:SetParent(content); tab.Details:ClearAllPoints()
	tab.Details:SetPoint("TOPLEFT",content,"TOPLEFT",0,0); tab.Details:SetPoint("TOPRIGHT",content,"TOPRIGHT",0,0)
	tab.CrafterList:SetParent(content); tab.CrafterList:ClearAllPoints()
	tab.CrafterList:SetPoint("TOPLEFT",tab.Details,"BOTTOMLEFT",0,-12)
	tab.CrafterList:SetPoint("TOPRIGHT",tab.Details,"BOTTOMRIGHT",-4,-12); tab.CrafterList:SetHeight(180)
	tab.CrafterList.outerScroll=scroll
 tab.RecipeSource:SetParent(tab.Details)
 tab.RecipeSource:ClearAllPoints()
 local toggle=CreateFrame("Button",nil,tab.RecipeSource)
 toggle:SetHeight(22); toggle:SetPoint("TOPLEFT",0,0)
 toggle:SetPoint("TOPRIGHT",0,0)
 local title=Text(toggle); title:SetAllPoints(); toggle:SetFontString(title)
 self.sourceTitle=title
 toggle:SetScript("OnClick",function() View.sourcesExpanded=not View.sourcesExpanded; View:Refresh() end)
 self.sourceToggle=toggle
 for _,frame in ipairs({tab.Details,tab.CrafterList,tab.RecipeSource}) do
  frame:EnableMouseWheel(true); frame:SetScript("OnMouseWheel",function(_,delta) View:Scroll(delta) end)
 end
	local header=CreateFrame("Button",nil,tab.Details)
	header:SetPoint("TOPLEFT",10,-8); header:SetPoint("TOPRIGHT",-10,-8); header:SetHeight(44)
	header:SetScript("OnEnter",function(button) local links=Links(); Hover(button,links and links.craft) end)
	header:SetScript("OnLeave",function() GameTooltip:Hide() end)
	header:RegisterForClicks("LeftButtonUp","RightButtonUp")
	header:SetScript("OnClick",function(owner,button) local links=Links(); Click(links and links.craft,button,owner) end)
	tab.CraftItemHover=header
	self.recipeButton=CreateFrame("Button",nil,tab.Details)
	self.recipeButton:SetPoint("TOPLEFT",12,-92); self.recipeButton:SetHeight(22)
	local recipeLabel=Text(self.recipeButton); recipeLabel:SetAllPoints()
	self.recipeButton:SetFontString(recipeLabel)
	self.recipeButton:RegisterForClicks("LeftButtonUp","RightButtonUp")
	self.recipeButton:SetScript("OnEnter",function(button) local links=Links(); Hover(button,links and links.recipe) end)
	self.recipeButton:SetScript("OnLeave",function() GameTooltip:Hide() end)
	self.recipeButton:SetScript("OnClick",function(owner,button) local links=Links(); Click(links and links.recipe,button,owner) end)
	self.recipeTitle=Text(tab.Details); self.recipeTitle:SetText("Recipe"); CraftRoster.Theme:Heading(self.recipeTitle)
	self.recipeIcon=self.recipeButton:CreateTexture(nil,"ARTWORK")
	self.recipeIcon:SetSize(32,32); self.recipeIcon:SetPoint("RIGHT",self.recipeButton,"LEFT",-8,0)
	self.materialTitle=Text(tab.Details); self.materialTitle:SetText("Materials")
	CraftRoster.Theme:Heading(self.materialTitle)
	self.crafterTitle=Text(content); self.crafterTitle:SetText("Crafters"); CraftRoster.Theme:Heading(self.crafterTitle)
	self.rows={}
 self.locationRows={}
 self.versionButton=CreateFrame("Button",nil,tab.Details,"UIPanelButtonTemplate")
 CraftRoster.Theme:Button(self.versionButton)
 self.versionButton:SetScript("OnClick",function()
  local recipe=CraftRoster.Directory.selectedRecipe
  local versions=recipe and recipe.versions
  if not versions then return end
  for index,version in ipairs(versions) do
   if version.id==recipe.id then
    CraftRoster.Directory.selectedRecipe=versions[index%#versions+1]
    CraftRoster.Directory.selectedCrafter=nil;CraftRoster.Directory.professionCache=nil
    CraftRoster.Directory:RefreshProfessions();return
   end
  end
 end)
 self.versionButton:SetScript("OnEnter",function(button)
  local recipe=CraftRoster.Directory.selectedRecipe
  if not recipe then return end
  GameTooltip:SetOwner(button,"ANCHOR_TOP");GameTooltip:SetText("Recipe versions")
  GameTooltip:AddLine("Spell "..recipe.id..". Click to view another version. Crafters, materials and sources stay separate.",1,1,1,true);GameTooltip:Show()
 end)
 self.versionButton:SetScript("OnLeave",function() GameTooltip:Hide() end)
	self.craftButton=CreateFrame("Button",nil,tab.Details,"UIPanelButtonTemplate")
	CraftRoster.Theme:Button(self.craftButton)
	self.craftButton:SetScript("OnClick",function()
		local recipe=CraftRoster.Directory.selectedRecipe
		if not recipe or not CraftRosterDB.settings.enabled then return end
		local character=CraftRosterDB.characters[UnitName("player").."-"..(GetRealmName() or "")]
		if character and character.recipes[recipe.id] then
			CraftRoster.WorkOrders:CraftSelected(recipe.id,CraftRoster.ShoppingList:GetQuantity(recipe.id))
		elseif CraftRoster.Directory.selectedCrafter then
			CraftRoster.Requests:WhisperPlayer(recipe.id,CraftRoster.Directory.selectedCrafter)
		end
	end)
	self.craftButton:SetScript("OnEnter",function(button)
		GameTooltip:SetOwner(button,"ANCHOR_TOP"); GameTooltip:SetText(button:GetText())
		GameTooltip:AddLine("Craft a recipe you have scanned as learned, using the selected quantity. Guild recipes prepare a whisper to your selected crafter.",1,1,1,true)
		GameTooltip:AddLine("The game checks materials and profession access. Enchants require selecting the target item.",1,1,1,true); GameTooltip:Show()
	end)
	self.craftButton:SetScript("OnLeave",function() GameTooltip:Hide() end)
	for _,button in ipairs({header,self.recipeButton,self.sourceToggle}) do
	 button:EnableMouseWheel(true); button:SetScript("OnMouseWheel",function(_,delta) View:Scroll(delta) end)
	end
	scroll:HookScript("OnVerticalScroll",function() GameTooltip:Hide();if tab.CrafterListChild.drawRows then tab.CrafterListChild.drawRows() end end)
 scroll:EnableMouseWheel(true)
	scroll:SetScript("OnMouseWheel",function(_,delta) View:Scroll(delta) end)
	scroll:HookScript("OnSizeChanged",function() View:Refresh() end)
	scroll:HookScript("OnShow",function() View:Refresh() end)
	local events=CreateFrame("Frame")
	pcall(events.RegisterEvent,events,"BAG_UPDATE_DELAYED"); events:RegisterEvent("BAG_UPDATE")
	pcall(events.RegisterEvent,events,"GET_ITEM_INFO_RECEIVED")
 pcall(events.RegisterEvent,events,"NEUTRAL_FACTION_SELECT_RESULT")
 events:RegisterEvent("PLAYER_ENTERING_WORLD")
	events:SetScript("OnEvent",function(_,event,_,success)
		if event=="GET_ITEM_INFO_RECEIVED" then
			if not success then return end
			View.cachedLink=nil
		end
		View:ScheduleRefresh()
	end)
end

function View:LayoutActions()
	local tab=self.tab
	if not tab or not tab.CraftRosterTradeButton or not tab.ActionBar then return end
	local bar=tab.ActionBar
	local width=math.max(220,bar:GetWidth())
	local wide=width>=520
	local columns=wide and 4 or 2
	local buttonWidth=(width-8-(columns-1)*6)/columns
	local buttons={tab.CraftRosterTradeButton,tab.CraftRosterMailButton,tab.CraftRosterShoppingButton,tab.CraftRosterFavoriteButton}
	for i,button in ipairs(buttons) do
		button:SetParent(bar); button:ClearAllPoints(); button:SetSize(buttonWidth,26)
		button:SetPoint("TOPLEFT",bar,"TOPLEFT",4+((i-1)%columns)*(buttonWidth+6),-4-math.floor((i-1)/columns)*30)
	end
	for _,button in ipairs({tab.CraftRosterAutoLoad,tab.CraftRosterCancelRequestButton}) do button:SetParent(bar); button:ClearAllPoints() end
	tab.CraftRosterAutoLoad:SetPoint("BOTTOMLEFT",bar,"BOTTOMLEFT",2,0)
	tab.CraftRosterCancelRequestButton:SetSize(104,20)
	tab.CraftRosterCancelRequestButton:SetPoint("BOTTOMRIGHT",bar,"BOTTOMRIGHT",-2,2)
	local quantity=tab.CraftRosterQuantity
	quantity:ClearAllPoints(); quantity:SetPoint("TOPLEFT",tab.Details,"TOPLEFT",112,-68); quantity:SetSize(52,30)
	if tab.CraftRosterQuantityLabel then tab.CraftRosterQuantityLabel:SetText("Quantity:") end
	for _,spec in ipairs({{tab.CraftRosterQuantityUp,"TOPLEFT","TOPRIGHT"},
		{tab.CraftRosterQuantityDown,"BOTTOMLEFT","BOTTOMRIGHT"}}) do
		local button=spec[1]; button:ClearAllPoints(); button:SetSize(18,14)
		button:SetPoint(spec[2],quantity,spec[3],4,0)
		-- Preserve the native arrow textures created by CraftRequests across themes.
	end
	if tab.CraftRosterQuantityLabel then
		tab.CraftRosterQuantityLabel:ClearAllPoints()
		tab.CraftRosterQuantityLabel:SetPoint("TOPLEFT",tab.Details,"TOPLEFT",12,-77)
	end
end

function View:RefreshMaterials()
	if not self.tab or not Visible() then return end
	local tab=self.tab
	local recipe=CraftRoster.Directory.selectedRecipe
	local width=math.max(220,tab.SelectedCraftScroll:GetWidth())
	tab.SelectedCraftContent:SetWidth(width)
	tab.DetailsIcon:ClearAllPoints(); tab.DetailsIcon:SetPoint("TOPLEFT",12,-12); tab.DetailsIcon:SetSize(56,56)
	tab.DetailsName:ClearAllPoints(); tab.DetailsName:SetPoint("TOPLEFT",tab.Details,"TOPLEFT",88,-12)
	tab.DetailsName:SetWidth(math.max(100,width-104)); tab.DetailsName:SetHeight(34)
	tab.DetailsName:SetFontObject("GameFontNormalHuge")
	tab.DetailsProfession:ClearAllPoints(); tab.DetailsProfession:SetPoint("TOPLEFT",tab.Details,"TOPLEFT",88,-48)
	tab.CraftItemHover:SetHeight(58)
	self:LayoutActions()
	self.sourceY=164
	self:RefreshSources()
	local column=self.column or math.floor((width-36)/2)
	local materialX=self.stacked and 12 or column+24
	local materialY=self.stacked and (self.sourceY+(self.sourceHeight or 0)+8) or 102
	self.materialTitle:ClearAllPoints(); self.materialTitle:SetPoint("TOPLEFT",tab.Details,"TOPLEFT",materialX,-materialY)
	self.materialTitle:SetWidth(column); self.materialTitle:SetHeight(22)
	local entries=recipe and CraftRoster.ShoppingList:GetMaterialStatus(recipe.id,CraftRoster.Directory.selectedCrafter)
	self.entries=entries or {}
	local y=materialY+26
	for index,entry in ipairs(self.entries) do
		local row=self.rows[index]
		if not row then
			row=CreateFrame("Button",nil,tab.Details); self.rows[index]=row
			row.Label=Text(row); row.Label:SetPoint("TOPLEFT",34,-2); row.Label:SetPoint("BOTTOMRIGHT",0,2); row:SetFontString(row.Label)
			row.Count=Text(row); row.Count:SetJustifyH("RIGHT"); row.Count:SetWordWrap(false)
			row.Count:SetPoint("TOPRIGHT",row,"TOPRIGHT",0,-2); row.Count:SetSize(76,32)
			row.Icon=row:CreateTexture(nil,"ARTWORK"); row.Icon:SetSize(32,32); row.Icon:SetPoint("TOPLEFT",0,-2)
			row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
			row:SetScript("OnEnter",function(button)
				local material=button.entry
				Hover(button,material.itemID and ("item:"..material.itemID))
				if not material.itemID then GameTooltip:SetOwner(button,"ANCHOR_RIGHT"); GameTooltip:SetText(material.name) end
				GameTooltip:AddLine(("In bags: %s · still needed: %d · total: %d"):format(material.owned or "?",material.required,material.recipeRequired),1,1,1,true)
				CraftRoster.ShoppingList:AddBankTooltip(material)
				GameTooltip:AddLine(("Delivered: %d · crafter provides: %d"):format(material.delivered,material.crafterProvides),1,1,1,true)
				GameTooltip:AddLine("Click: insert whisper/chat link, or fill AH search",1,1,1); GameTooltip:Show()
			end)
			row:EnableMouseWheel(true); row:SetScript("OnMouseWheel",function(_,delta) View:Scroll(delta) end)
			row:SetScript("OnLeave",function() GameTooltip:Hide() end)
			row:SetScript("OnClick",function(button) CraftRoster.ItemDisplay:Click(button.entry) end)
		end
		row.entry=entry
		local icon=entry.icon
		if entry.itemID and (not icon or icon=="Interface\\Icons\\INV_Misc_QuestionMark") then
			if C_Item and C_Item.GetItemIconByID then
				local ok,result=pcall(C_Item.GetItemIconByID,entry.itemID)
				if ok and result then icon=result end
			end
			if (not icon or icon=="Interface\\Icons\\INV_Misc_QuestionMark") and GetItemIcon then
				local ok,result=pcall(GetItemIcon,entry.itemID)
				if ok and result then icon=result end
			end
		end
		row.Icon:SetTexture(icon or "Interface\\Icons\\INV_Misc_QuestionMark")
		local color=entry.owned and entry.owned>=entry.required and "|cff33ff66" or "|cffffd166"
		local count=color..tostring(entry.owned or "?").." / "..entry.required.."|r"
		-- Reserve a fixed count column even on narrow panels. Wrapping the
		-- quantity under the name made every material consume two lines.
		-- The tooltip retains the full material name and inventory breakdown.
		row.Count:SetText(count)
		-- On a narrow pane, reclaim room for material names while retaining
		-- a dedicated quantity column and the full tooltip on hover.
		local countWidth=column<260 and 62 or 76
		row.Count:SetWidth(countWidth)
		row.Label:ClearAllPoints(); row.Label:SetPoint("TOPLEFT",34,-2)
		row.Label:SetPoint("BOTTOMRIGHT",row,"BOTTOMRIGHT",-(countWidth+4),2)
		row.Label:SetWordWrap(false)
		row.Label:SetText(entry.name)
		local height=32
		row.Icon:SetSize(28,28)
		row.Count:SetHeight(28)
		row:SetSize(column,height); row:ClearAllPoints(); row:SetPoint("TOPLEFT",tab.Details,"TOPLEFT",materialX,-y); row:Show()
		-- Keep a modest gap so icons and counts remain individually clickable.
		y=y+height+1
	end
	for index=#self.entries+1,#self.rows do self.rows[index]:Hide() end
	self.materialTitle:SetText(entries and "Materials" or "Materials unavailable")
	local bottom=math.max(y+8,self.sourceY+(self.sourceHeight or 0)+8)
	local own=CraftRosterDB.characters[UnitName("player").."-"..(GetRealmName() or "")]
	local known=recipe and own and own.recipes[recipe.id]
	self.craftButton:ClearAllPoints(); self.craftButton:SetPoint("TOPRIGHT",tab.Details,"TOPRIGHT",-12,-bottom)
	self.craftButton:SetSize(math.min(160,width-24),32)
	-- Keep the action visible at narrow widths without overlapping the source
	-- and materials sections; the unified scroll still handles long recipes.
	self.craftButton:SetText(known and "Craft" or "Request craft")
	self.craftButton:SetEnabled(recipe and CraftRosterDB.settings.enabled and (known or CraftRoster.Directory.selectedCrafter) and true or false)
	bottom=bottom+44
	tab.Details:SetHeight(bottom)
	self.crafterTitle:ClearAllPoints(); self.crafterTitle:SetPoint("TOPLEFT",tab.SelectedCraftContent,"TOPLEFT",12,-(bottom+8))
	self.crafterTitle:SetSize(math.max(100,width-160),24)
	tab.OnlineCheck:SetParent(tab.SelectedCraftContent); tab.OnlineCheck:ClearAllPoints()
	tab.OnlineCheck:SetPoint("TOPRIGHT",tab.SelectedCraftContent,"TOPRIGHT",-112,-(bottom+4)); tab.OnlineCheck:SetSize(24,24)
	tab.CrafterList:ClearAllPoints()
	tab.CrafterList:SetPoint("TOPLEFT",tab.SelectedCraftContent,"TOPLEFT",0,-(bottom+38))
	tab.CrafterList:SetPoint("TOPRIGHT",tab.SelectedCraftContent,"TOPRIGHT",-4,-(bottom+38))
	tab.CrafterList.contentOffset=bottom+38
	tab.SelectedCraftContent:SetHeight(bottom+38+tab.CrafterListChild:GetHeight())
	tab.CrafterList:SetHeight(tab.CrafterListChild:GetHeight())
	local maximum=math.max(0,tab.SelectedCraftContent:GetHeight()-tab.SelectedCraftScroll:GetHeight())
	if tab.SelectedCraftScroll:GetVerticalScroll()>maximum then tab.SelectedCraftScroll:SetVerticalScroll(maximum) end
end

function View:Refresh()
	if not self.tab or not Visible() then return end
	local recipe=CraftRoster.Directory.selectedRecipe
	if self.recipeID~=(recipe and recipe.id) then
		self.sourcesExpanded=false; self.recipeID=recipe and recipe.id
  GameTooltip:Hide()
		self.tab.SelectedCraftScroll:SetVerticalScroll(0)
	end
	local width=math.max(220,self.tab.SelectedCraftScroll:GetWidth())
	-- Two readable columns fit from 400px; stacking at 460px made the
	-- default 1000px window needlessly tall.
	self.stacked=width<400
	local column=self.stacked and width-24 or math.floor((width-36)/2)
	self.column=column
	self.recipeTitle:ClearAllPoints(); self.recipeTitle:SetPoint("TOPLEFT",12,-102); self.recipeTitle:SetSize(column,26)
	self.recipeButton:ClearAllPoints(); self.recipeButton:SetPoint("TOPLEFT",52,-128); self.recipeButton:SetSize(column-40,32)
	local versions=recipe and recipe.versions
 self.versionButton:ClearAllPoints();self.versionButton:SetSize(112,22)
 self.versionButton:SetPoint("TOPRIGHT",self.tab.Details,"TOPLEFT",column+12,-102)
 if versions then
  for index,version in ipairs(versions) do if version.id==recipe.id then self.versionButton:SetText("Version "..index.." / "..#versions) end end
  self.versionButton:Show();self.recipeTitle:SetWidth(math.max(50,column-120))
 else self.versionButton:Hide() end
 local data=recipe and CraftRoster.RecipeSources:Get(recipe.id)
	local links=Links()
	self.recipeButton:SetText(links and (data and data.label or "View recipe") or "Select a recipe")
	self.recipeIcon:SetTexture(data and data.icon or "Interface\\Icons\\INV_Scroll_03")
	self:RefreshMaterials()
end

function View:ScheduleRefresh()
	if not Visible() or timer then return end
	if C_Timer and C_Timer.NewTimer then
		timer=C_Timer.NewTimer(0.1,function() timer=nil; View:Refresh() end)
	else self:Refresh() end
end

function View:Scroll(delta)
 local tab=self.tab
 local scroll=tab.SelectedCraftScroll
 scroll:SetVerticalScroll(math.max(0,math.min(math.max(0,tab.SelectedCraftContent:GetHeight()-scroll:GetHeight()),scroll:GetVerticalScroll()-delta*36)))
 if tab.CrafterListChild.drawRows then tab.CrafterListChild.drawRows() end
end

function View:RefreshSources()
 if not self.tab then return end
 local source=self.tab.RecipeSource
 local recipe=CraftRoster.Directory.selectedRecipe
 if not recipe then source:Hide(); self.sourceHeight=0; return end
 source:Show(); source.Link:Hide(); source.Output:Hide(); source.Status:Hide()
 local column=self.column or math.max(196,self.tab.SelectedCraftScroll:GetWidth()-24)
 source:ClearAllPoints(); source:SetPoint("TOPLEFT",self.tab.Details,"TOPLEFT",12,-(self.sourceY or 164))
 source:SetWidth(column); source.Child:SetWidth(column)
 local sourceLocations=CraftRoster.RecipeLocations and CraftRoster.RecipeLocations:Get(recipe.id) or {}
 local confirmed=false
 for _,location in ipairs(sourceLocations) do
  if location.confirmed then confirmed=true; break end
 end
 local sourceLabel=confirmed and "Where to get it" or "Where to get it (unverified)"
 self.sourceToggle:SetText(sourceLabel..(self.sourcesExpanded and " −" or " +"))
 CraftRoster.Theme:Heading(self.sourceTitle,true)
 local text=self.sourcesExpanded and CraftRoster.RecipeSources:Format(recipe.id,nil,false) or CraftRoster.RecipeSources:Summary(recipe.id)
 text=text:gsub("^|cffffd100Where to get it|r\n","")
 source.Text:ClearAllPoints(); source.Text:SetPoint("TOPLEFT",0,-26)
 local height=Height(source.Text,text,column); source.Text:SetHeight(height)
 local y=height+32
 local locations=CraftRoster.RecipeLocations:Get(recipe.id)
 -- Only create the map/copy controls when acquisition details are expanded.
 -- Otherwise these controls consume the entire recipe pane on recipes with
 -- multiple possible vendors or trainers.
 if not self.sourcesExpanded then
  for _,row in ipairs(self.locationRows) do row:Hide() end
  self.sourceHeight=y+4; source:SetHeight(self.sourceHeight); source.Child:SetHeight(self.sourceHeight)
  return
 end
 -- The source text already describes unverified references. Do not add
 -- empty rows with disabled copy/map buttons for those references.
 local visibleRows=0
 for _,record in ipairs(locations) do
  if record.confirmed then
  visibleRows=visibleRows+1
  local index=visibleRows
  local row=self.locationRows[index]
  if not row then
   row=CreateFrame("Frame",nil,source); self.locationRows[index]=row
   row.Label=Text(row); row.Label:SetPoint("TOPLEFT",0,0)
   row.Copy=CreateFrame("Button",nil,row,"UIPanelButtonTemplate")
   row.Map=CreateFrame("Button",nil,row,"UIPanelButtonTemplate")
   CraftRoster.Theme:Button(row.Copy); CraftRoster.Theme:Button(row.Map)
   row.Copy:SetText("Copy coords"); row.Map:SetText("Map marker")
   row.Copy:SetScript("OnClick",function()
    local value=CraftRoster.RecipeLocations:CopyText(row.record)
    if value then StaticPopup_Show("CRAFTROSTER_COPY_LOCATION",nil,nil,value) end
   end)
   row.Map:SetScript("OnClick",function()
    local ok,message=CraftRoster.RecipeLocations:Navigate(row.record)
    if not ok then DEFAULT_CHAT_FRAME:AddMessage("CraftRoster: "..message) end
   end)
   for _,button in ipairs({row.Copy,row.Map}) do
    button:SetScript("OnEnter",function(owner)
     GameTooltip:SetOwner(owner,"ANCHOR_RIGHT")
     GameTooltip:SetText(row.record.source or "Recipe location")
     GameTooltip:AddLine(row.record.confirmed and "Copy coordinates, or place a waypoint using compatible map support." or "This reference has not been confirmed. Navigation is disabled.",1,1,1,true)
     GameTooltip:AddLine("Revision: "..(row.record.revision or "unknown"),1,1,1,true)
     GameTooltip:AddLine(row.record.url or "",1,1,1,true); GameTooltip:Show()
    end)
    button:SetScript("OnLeave",function() GameTooltip:Hide() end)
    button:EnableMouseWheel(true); button:SetScript("OnMouseWheel",function(_,delta) View:Scroll(delta) end)
   end
  end
  row.record=record; row:ClearAllPoints(); row:SetPoint("TOPLEFT",source,"TOPLEFT",0,-y); row:SetWidth(column)
  local labelHeight=0
  row.Label:SetText("")
  if visibleRows>1 then labelHeight=Height(row.Label,record.name.." · "..record.zone,column) end
  row.Label:SetHeight(labelHeight)
  row.Copy:SetSize(math.min(104,(column-6)/2),24); row.Map:SetSize(math.min(104,(column-6)/2),24)
  row.Copy:ClearAllPoints(); row.Copy:SetPoint("TOPLEFT",0,-labelHeight-4)
  row.Map:ClearAllPoints(); row.Map:SetPoint("LEFT",row.Copy,"RIGHT",6,0)
  -- Only verified locations reach this row; do not offer a waypoint if
  -- the current client has no compatible navigation backend.
  row.Copy:SetEnabled(true)
  row.Map:SetEnabled(CraftRoster.RecipeLocations:Backend(record)~=nil)
  local rowHeight=labelHeight+36; row:SetHeight(rowHeight); row:Show(); y=y+rowHeight+4
  end
 end
 for index=visibleRows+1,#self.locationRows do self.locationRows[index]:Hide() end
 self.sourceHeight=y+4; source:SetHeight(self.sourceHeight); source.Child:SetHeight(self.sourceHeight)
end
