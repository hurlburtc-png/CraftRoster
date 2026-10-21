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
local function Click(link,button)
	if not link then return end
	if button=="RightButton" then StaticPopup_Show("CRAFTROSTER_COPY_LINK",nil,nil,link)
	elseif IsShiftKeyDown and IsShiftKeyDown() then
		if ChatEdit_InsertLink and ChatEdit_InsertLink(link) then return end
		if ChatFrame_OpenChat then ChatFrame_OpenChat(link) end
	elseif SetItemRef then
		local payload=link:match("|H(.-)|h")
		if payload then pcall(SetItemRef,payload,link,"LeftButton") end
	end
end
local function Text(parent)
	local label=parent:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
	label:SetJustifyH("LEFT"); label:SetWordWrap(true)
	return label
end
local function Height(label,text,width)
	label:SetWidth(width); label:SetText(text)
	local measured=label.GetStringHeight and label:GetStringHeight()
	return math.max(18,tonumber(measured) or (math.ceil(#text/math.max(8,math.floor(width/7)))*15))
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
	tab.RecipeSource:SetParent(content)
	local header=CreateFrame("Button",nil,tab.Details)
	header:SetPoint("TOPLEFT",10,-8); header:SetPoint("TOPRIGHT",-10,-8); header:SetHeight(44)
	header:SetScript("OnEnter",function(button) local links=Links(); Hover(button,links and links.craft) end)
	header:SetScript("OnLeave",function() GameTooltip:Hide() end)
	header:RegisterForClicks("LeftButtonUp","RightButtonUp")
	header:SetScript("OnClick",function(_,button) local links=Links(); Click(links and links.craft,button) end)
	tab.CraftItemHover=header
	self.recipeButton=CreateFrame("Button",nil,tab.Details)
	self.recipeButton:SetPoint("TOPLEFT",12,-92); self.recipeButton:SetHeight(22)
	local recipeLabel=Text(self.recipeButton); recipeLabel:SetAllPoints()
	self.recipeButton:SetFontString(recipeLabel)
	self.recipeButton:RegisterForClicks("LeftButtonUp","RightButtonUp")
	self.recipeButton:SetScript("OnEnter",function(button) local links=Links(); Hover(button,links and links.recipe) end)
	self.recipeButton:SetScript("OnLeave",function() GameTooltip:Hide() end)
	self.recipeButton:SetScript("OnClick",function(_,button) local links=Links(); Click(links and links.recipe,button) end)
	self.recipeBody=Text(tab.Details); self.recipeBody:SetPoint("TOPLEFT",12,-120)
	self.materialTitle=Text(tab.Details); self.materialTitle:SetText("Materials · in bags / needed")
	self.rows={}
	scroll:EnableMouseWheel(true)
	scroll:SetScript("OnMouseWheel",function(frame,delta)
		frame:SetVerticalScroll(math.max(0,math.min(math.max(0,content:GetHeight()-frame:GetHeight()),frame:GetVerticalScroll()-delta*36)))
	end)
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
			row.Label=Text(row); row.Label:SetAllPoints(); row:SetFontString(row.Label)
			row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
			row:SetScript("OnEnter",function(button)
				local material=button.entry
				Hover(button,material.itemID and ("item:"..material.itemID))
				if not material.itemID then GameTooltip:SetOwner(button,"ANCHOR_RIGHT"); GameTooltip:SetText(material.name) end
				GameTooltip:AddLine(("In bags: %s · still needed: %d · total: %d"):format(material.owned or "?",material.required,material.recipeRequired),1,1,1,true)
				GameTooltip:AddLine(("Delivered: %d · crafter provides: %d"):format(material.delivered,material.crafterProvides),1,1,1,true)
				GameTooltip:AddLine("Click: fill Auction House search",1,1,1); GameTooltip:Show()
			end)
			row:SetScript("OnLeave",function() GameTooltip:Hide() end)
			row:SetScript("OnClick",function(button) CraftRoster.ShoppingList:SearchAuctions(button.entry) end)
		end
		row.entry=entry
		local icon="Interface\\Icons\\INV_Misc_QuestionMark"
		local getIcon=C_Item and C_Item.GetItemIconByID or GetItemIcon
		if entry.itemID and type(getIcon)=="function" then local ok,value=pcall(getIcon,entry.itemID); if ok and value then icon=value end end
		local color=entry.owned and entry.owned>=entry.required and "|cff33ff66" or "|cffffd166"
		local text="|T"..tostring(icon)..":18:18|t "..entry.name.."\n"..color..tostring(entry.owned or "?").." / "..entry.required.."|r"
		local height=math.max(42,Height(row.Label,text,column))
		row:SetSize(column,height); row:ClearAllPoints(); row:SetPoint("TOPLEFT",tab.Details,"TOPLEFT",column+24,-y); row:Show()
		y=y+height+6
	end
	for index=#self.entries+1,#self.rows do self.rows[index]:Hide() end
	self.materialTitle:SetText(entries and "Materials · in bags / needed" or "Materials unavailable")
	local bottom=math.max(y,120+(self.recipeHeight or 80))+98
	tab.Details:SetHeight(bottom)
	tab.SelectedCraftContent:SetHeight(bottom+210)
	local maximum=math.max(0,tab.SelectedCraftContent:GetHeight()-tab.SelectedCraftScroll:GetHeight())
	if tab.SelectedCraftScroll:GetVerticalScroll()>maximum then tab.SelectedCraftScroll:SetVerticalScroll(maximum) end
end

function View:Refresh()
	if not self.tab or not Visible() then return end
	local recipe=CraftRoster.Directory.selectedRecipe
	local links=Links()
	if self.recipeID~=(recipe and recipe.id) then
		self.cachedLink=nil; self.recipeID=recipe and recipe.id
		self.tab.SelectedCraftScroll:SetVerticalScroll(0)
	end
	local width=math.max(220,self.tab.SelectedCraftScroll:GetWidth())
	local column=math.floor((width-36)/2)
	self.recipeButton:SetWidth(column)
	self.recipeButton:SetText(links and links.recipe or "Select a recipe")
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
