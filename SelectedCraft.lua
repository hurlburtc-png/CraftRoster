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
	label:SetWidth(width); label:SetText(text)
	local measured=label.GetStringHeight and label:GetStringHeight()
	text=text:gsub("|T.-|t", "XX"):gsub("|H.-|h(.-)|h", "%1"):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
	local lines=0
	for line in (text.."\n"):gmatch("([^\n]*)\n") do lines=lines+math.max(1,math.ceil(#line/math.max(8,math.floor(width/7)))) end
	return math.max(18,tonumber(measured) or lines*15)
end

-- Read the client's native pattern/spell tooltip, then wrap its text within the
-- recipe column. No fabricated item stats and no tooltip scaling on small windows.
function View:RecipeText(link)
	if link and self.cachedLink==link then return self.cachedText or "" end
	local lines={}
	if link then
		self.scanner=self.scanner or CreateFrame("GameTooltip","CraftRosterRecipePreviewScanner",UIParent,"GameTooltipTemplate")
		local scan=self.scanner
		local ok=pcall(function()
			scan:SetOwner(UIParent,"ANCHOR_NONE"); scan:ClearLines(); scan:SetHyperlink(link)
		end)
		if ok and scan.GetNumLines then
			for index=1,math.min(40,scan:GetNumLines() or 0) do
				local parts={}
				for _,side in ipairs({"Left","Right"}) do
					local field=_G["CraftRosterRecipePreviewScannerText"..side..index]
					local value=field and field:GetText()
					if value and value~="" then
						if field.GetTextColor then
							local r,g,b=field:GetTextColor()
							value=("|cff%02x%02x%02x%s|r"):format(math.floor((r or 1)*255),math.floor((g or 1)*255),math.floor((b or 1)*255),value)
						end
						table.insert(parts,value)
					end
				end
				if #parts>0 then table.insert(lines,table.concat(parts,"  ")) end
			end
		end
		scan:Hide()
	end
	local recipe=CraftRoster.Directory.selectedRecipe
	if #lines==0 and recipe then
		local saved=CraftRosterDB.recipes[recipe.id] or {}
		local data=CraftRoster.RecipeSources:Get(recipe.id)
		lines={data.name or recipe.name,saved.description or "Recipe tooltip is loading. Hover the recipe to inspect it in game."}
	end
	self.cachedLink,self.cachedText=link,table.concat(lines,"\n")
	return self.cachedText
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
	self.recipeBody=Text(tab.Details); self.recipeBody:SetPoint("TOPLEFT",12,-120)
	self.materialTitle=Text(tab.Details); self.materialTitle:SetText("Materials")
	self.rows={}
	for _,button in ipairs({header,self.recipeButton,self.sourceToggle}) do
	 button:EnableMouseWheel(true); button:SetScript("OnMouseWheel",function(_,delta) View:Scroll(delta) end)
	end
	scroll:EnableMouseWheel(true)
	scroll:SetScript("OnMouseWheel",function(_,delta) View:Scroll(delta) end)
	scroll:HookScript("OnSizeChanged",function() View:Refresh() end)
	scroll:HookScript("OnShow",function() View:Refresh() end)
	local events=CreateFrame("Frame")
	pcall(events.RegisterEvent,events,"BAG_UPDATE_DELAYED"); events:RegisterEvent("BAG_UPDATE")
	pcall(events.RegisterEvent,events,"GET_ITEM_INFO_RECEIVED")
	events:SetScript("OnEvent",function(_,event,_,success)
		if event=="GET_ITEM_INFO_RECEIVED" then
			if not success then return end
			View.cachedLink=nil
		end
		View:ScheduleRefresh()
	end)
end

function View:RefreshMaterials()
	if not self.tab or not Visible() then return end
	local tab=self.tab
	local recipe=CraftRoster.Directory.selectedRecipe
	local width=math.max(220,tab.SelectedCraftScroll:GetWidth())
	tab.SelectedCraftContent:SetWidth(width)
	tab.DetailsName:SetWidth(math.max(100,width-78))
	if tab.CraftRosterResizeActions then tab.CraftRosterResizeActions() end
	local column=math.floor((width-36)/2)
	self.materialTitle:ClearAllPoints(); self.materialTitle:SetPoint("TOPLEFT",tab.Details,"TOPLEFT",column+24,-92)
	self.materialTitle:SetWidth(column); self.materialTitle:SetHeight(26)
	local entries=recipe and CraftRoster.ShoppingList:GetMaterialStatus(recipe.id,CraftRoster.Directory.selectedCrafter)
	self.entries=entries or {}
	local y=124
	for index,entry in ipairs(self.entries) do
		local row=self.rows[index]
		if not row then
			row=CreateFrame("Button",nil,tab.Details); self.rows[index]=row
			row.Label=Text(row); row.Label:SetPoint("TOPLEFT",38,-2); row.Label:SetPoint("BOTTOMRIGHT",0,2); row:SetFontString(row.Label)
			row.Icon=row:CreateTexture(nil,"ARTWORK"); row.Icon:SetSize(32,32); row.Icon:SetPoint("TOPLEFT",0,-2)
			row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
			row:SetScript("OnEnter",function(button)
				local material=button.entry
				Hover(button,material.itemID and ("item:"..material.itemID))
				if not material.itemID then GameTooltip:SetOwner(button,"ANCHOR_RIGHT"); GameTooltip:SetText(material.name) end
				GameTooltip:AddLine(("In bags: %s · still needed: %d · total: %d"):format(material.owned or "?",material.required,material.recipeRequired),1,1,1,true)
				GameTooltip:AddLine(("Delivered: %d · crafter provides: %d"):format(material.delivered,material.crafterProvides),1,1,1,true)
				GameTooltip:AddLine("Click: insert whisper/chat link, or fill AH search",1,1,1); GameTooltip:Show()
			end)
			row:EnableMouseWheel(true); row:SetScript("OnMouseWheel",function(_,delta) View:Scroll(delta) end)
			row:SetScript("OnLeave",function() GameTooltip:Hide() end)
			row:SetScript("OnClick",function(button) CraftRoster.ItemDisplay:Click(button.entry) end)
		end
		row.entry=entry
		row.Icon:SetTexture(entry.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
		local color=entry.owned and entry.owned>=entry.required and "|cff33ff66" or "|cffffd166"
		local text=entry.name.."\n"..color..tostring(entry.owned or "?").." / "..entry.required.."|r"
		local height=math.max(38,Height(row.Label,text,column-38))
		row:SetSize(column,height); row:ClearAllPoints(); row:SetPoint("TOPLEFT",tab.Details,"TOPLEFT",column+24,-y); row:Show()
		y=y+height+2
	end
	for index=#self.entries+1,#self.rows do self.rows[index]:Hide() end
	self.materialTitle:SetText(entries and "Materials" or "Materials unavailable")
	self:RefreshSources()
	local bottom=math.max(y,120+(self.recipeHeight or 80)+(self.sourceHeight or 0))+98
	tab.Details:SetHeight(bottom)
	tab.CrafterList.contentOffset=bottom+12
	tab.SelectedCraftContent:SetHeight(bottom+12+tab.CrafterListChild:GetHeight())
	tab.CrafterList:SetHeight(tab.CrafterListChild:GetHeight())
	local maximum=math.max(0,tab.SelectedCraftContent:GetHeight()-tab.SelectedCraftScroll:GetHeight())
	if tab.SelectedCraftScroll:GetVerticalScroll()>maximum then tab.SelectedCraftScroll:SetVerticalScroll(maximum) end
end

function View:Refresh()
	if not self.tab or not Visible() then return end
	local recipe=CraftRoster.Directory.selectedRecipe
	local links=Links()
	if self.recipeID~=(recipe and recipe.id) then
		self.cachedLink=nil; self.sourcesExpanded=false; self.recipeID=recipe and recipe.id
		self.tab.SelectedCraftScroll:SetVerticalScroll(0)
	end
	local width=math.max(220,self.tab.SelectedCraftScroll:GetWidth())
	local column=math.floor((width-36)/2)
	self.recipeButton:SetWidth(column)
	self.recipeButton:SetText(links and "Recipe" or "Select a recipe")
	self.recipeHeight=Height(self.recipeBody,self:RecipeText(links and links.recipe),column)
	self.recipeBody:SetHeight(self.recipeHeight)
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
 local column=math.floor((math.max(220,self.tab.SelectedCraftScroll:GetWidth())-36)/2)
 source:ClearAllPoints(); source:SetPoint("TOPLEFT",self.tab.Details,"TOPLEFT",12,-(128+(self.recipeHeight or 80)))
 source:SetWidth(column); source.Child:SetWidth(column)
 self.sourceToggle:SetText(self.sourcesExpanded and "Recipe source / location −" or "Recipe source / location +")
 local text=CraftRoster.RecipeSources:Format(recipe.id)
 if not self.sourcesExpanded then
  local lines={}
  for line in text:gmatch("[^\n]+") do
   if not line:find("Description:",1,true) then lines[#lines+1]=line end
   if #lines==3 then break end
  end
  text=table.concat(lines,"\n")
 end
 source.Text:ClearAllPoints(); source.Text:SetPoint("TOPLEFT",0,-26)
 local height=Height(source.Text,text,column); source.Text:SetHeight(height)
 self.sourceHeight=height+36; source:SetHeight(self.sourceHeight); source.Child:SetHeight(self.sourceHeight)
end
