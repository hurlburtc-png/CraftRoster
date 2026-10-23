local ADDON_NAME, CraftRoster = ...
local Theme = {}
CraftRoster.Theme = Theme
local panels,headings,buttons,windows,rows = {},{},{},{},{}
Theme.palettes = {
	{key="gold",name="Classic Gold",description="The original warm gold and dark stone.",accent={1,0.82,0.32},border={0.55,0.43,0.22},background={0.035,0.035,0.04}},
	{key="dark",name="Dark",description="Neutral charcoal with soft silver accents.",accent={0.86,0.9,0.95},border={0.42,0.46,0.52},background={0.022,0.025,0.03}},
	{key="contrast",name="High Contrast",description="White on solid black with clear outlines.",accent={1,1,1},border={0.9,0.9,0.9},background={0,0,0}},
	{key="frost",name="Frost Blue",description="Cool slate with icy blue accents.",accent={0.48,0.83,1},border={0.25,0.52,0.68},background={0.025,0.045,0.07}},
	{key="forest",name="Emerald",description="Deep green with bright emerald accents.",accent={0.48,0.95,0.7},border={0.25,0.58,0.4},background={0.025,0.055,0.04}},
	{key="violet",name="Arcane Violet",description="Dark plum with violet highlights.",accent={0.82,0.65,1},border={0.51,0.36,0.68},background={0.05,0.03,0.065}},
	{key="fire",name="Ember Fire",description="Charcoal and ember-orange highlights.",accent={1,0.66,0.34},border={0.78,0.36,0.16},background={0.065,0.025,0.018}},
	{key="nature",name="Woodland Nature",shortName="Nature",description="Warm earth tones with soft moss green.",accent={0.8,0.9,0.52},border={0.48,0.55,0.28},background={0.055,0.055,0.025}},
	{key="demonic",name="Fel Chaos",description="Fel green, bruised purple and demonic accents.",accent={0.66,1,0.32},border={0.62,0.34,0.8},background={0.045,0.018,0.055},icon="Interface\\Icons\\Spell_Shadow_DemonForm"},
	{key="metal",name="Ironbound",description="Worn iron, steel borders and blood-red details.",accent={0.9,0.91,0.94},border={0.62,0.65,0.69},background={0.045,0.045,0.05},secondary={0.85,0.28,0.24},texture="Interface\\DialogFrame\\UI-DialogBox-Background",edge="Interface\\DialogFrame\\UI-DialogBox-Border",icon="Interface\\Icons\\INV_Misc_Bone_01"},
}

function Theme:Palette()
	local key=CraftRosterDB and CraftRosterDB.settings and CraftRosterDB.settings.theme
	for _,palette in ipairs(self.palettes) do if palette.key==key then return palette end end
	return self.palettes[1]
end

function Theme:PaintPanel(panel,palette)
	local p=palette or self:Palette()
	panel:SetBackdrop({bgFile=p.texture or "Interface\\Tooltips\\UI-Tooltip-Background",
		edgeFile=p.edge or "Interface\\Tooltips\\UI-Tooltip-Border",edgeSize=p.edge and 20 or 12,
		insets={left=3,right=3,top=3,bottom=3}})
	panel:SetBackdropColor(p.background[1],p.background[2],p.background[3],1)
	panel:SetBackdropBorderColor(p.border[1],p.border[2],p.border[3],0.95)
	if p.icon and not panel.ThemeMark then
		panel.ThemeMark=panel:CreateTexture(nil,"BACKGROUND")
		panel.ThemeMark:SetPoint("BOTTOMRIGHT",-12,12); panel.ThemeMark:SetSize(40,40); panel.ThemeMark:SetAlpha(0.12)
	end
	if panel.ThemeMark then
		if p.icon then
			panel.ThemeMark:SetTexture(p.icon)
			local tint=p.secondary or p.accent
			panel.ThemeMark:SetVertexColor(tint[1],tint[2],tint[3]); panel.ThemeMark:Show()
		else panel.ThemeMark:Hide() end
	end
end

function Theme:PaintWindow(frame)
	local p=self:Palette()
	local function Tint(texture)
		if texture and type(texture.SetVertexColor)=="function" then
			if p.key=="gold" then texture:SetVertexColor(1,1,1)
			else texture:SetVertexColor(p.background[1],p.background[2],p.background[3]) end
		end
	end
	-- These are regions of our own window instances, never shared UI objects.
	Tint(frame.Bg); Tint(frame.InsetBg)
	if frame.Inset and frame.Inset~=frame then Tint(frame.Inset.Bg) end
end

function Theme:ApplyScale(frame)
	local settings=CraftRosterDB.settings
	local scale=settings.uiScaleEnabled and tonumber(settings.uiScale) or 1
	if not scale or scale~=scale then scale=1 end
	scale=math.max(0.75,math.min(1.5,scale))
	-- Scale is relative to the player's existing WoW UI scale. Large custom
	-- windows fit the viewport instead of putting their controls offscreen.
	local w,h=UIParent:GetWidth(),UIParent:GetHeight()
	if w>100 and h>100 then
		scale=math.min(scale,(w-24)/math.max(1,frame:GetWidth()),(h-24)/math.max(1,frame:GetHeight()))
	end
	frame:SetScale(scale)
	frame:SetClampedToScreen(true)
end

function Theme:Opacity()
	local value=tonumber(CraftRosterDB.settings.windowOpacity)
	if not value or value~=value then return 1 end
	return math.max(0.4,math.min(1,value))
end

function Theme:ApplyOpacity(frame)
	frame:SetAlpha(windows[frame]=="solid" and 1 or self:Opacity())
end

function Theme:SetOpacity(value)
	if type(value)~="number" or value~=value then return false end
	CraftRosterDB.settings.windowOpacity=math.max(0.4,math.min(1,math.floor(value*100+0.5)/100))
	for frame in pairs(windows) do self:ApplyOpacity(frame) end
	if CraftRoster.Panel and CraftRoster.Panel.themePreview then
		CraftRoster.Panel.themePreview:SetAlpha(self:Opacity())
	end
	return true
end

function Theme:Window(frame,title,keepSolid)
	if not windows[frame] then
		windows[frame]=keepSolid and "solid" or true
		frame:HookScript("OnShow",function() Theme:ApplyScale(frame); Theme:ApplyOpacity(frame) end)
		frame:HookScript("OnSizeChanged",function() Theme:ApplyScale(frame) end)
	end
	if title then self:Heading(title) end
	self:PaintWindow(frame)
	self:ApplyScale(frame)
	self:ApplyOpacity(frame)
end

local displayEvents=CreateFrame("Frame")
pcall(displayEvents.RegisterEvent,displayEvents,"DISPLAY_SIZE_CHANGED")
pcall(displayEvents.RegisterEvent,displayEvents,"UI_SCALE_CHANGED")
displayEvents:SetScript("OnEvent",function()
	for frame in pairs(windows) do Theme:ApplyScale(frame) end
end)

function Theme:SetScale(enabled,value)
	if type(value)~="number" or value~=value then return false end
	CraftRosterDB.settings.uiScale=math.max(0.75,math.min(1.5,math.floor(value*100+0.5)/100))
	CraftRosterDB.settings.uiScaleEnabled=enabled and true or false
	for frame in pairs(windows) do self:ApplyScale(frame) end
	return true
end

function Theme:SetPalette(key)
	local found
	for _,p in ipairs(self.palettes) do if p.key==key then found=true end end
	if not found then return false end
	CraftRosterDB.settings.theme=key
	local p=self:Palette()
	for panel in pairs(panels) do self:PaintPanel(panel) end
	for label in pairs(headings) do label:SetTextColor(p.accent[1],p.accent[2],p.accent[3]) end
	for button in pairs(buttons) do self:TintButton(button) end
	for frame in pairs(windows) do self:PaintWindow(frame) end
	for row in pairs(rows) do self:Selection(row,row.selected) end
	-- Appearance changes repaint existing widgets without rebuilding recipe lists,
	-- querying bags, changing a selection, or moving either scrollbar.
	if CraftRoster.Panel and CraftRoster.Panel.themePreview then CraftRoster.Panel:RefreshAppearance() end
	return true
end

-- Native textures only: no external skin or library is required.
function Theme:Panel(parent)
	local panel = CreateFrame("Frame", nil, parent, BackdropTemplateMixin and "BackdropTemplate" or nil)
	panel:SetAllPoints(parent)
	panel:SetFrameLevel(math.max(0, parent:GetFrameLevel() - 1))
	panel:SetBackdrop({bgFile="Interface\\Tooltips\\UI-Tooltip-Background",
		edgeFile="Interface\\Tooltips\\UI-Tooltip-Border", edgeSize=12,
		insets={left=3,right=3,top=3,bottom=3}})
	self:TrackPanel(panel)
	return panel
end

function Theme:Heading(label,compact)
	headings[label]=true
	local color=self:Palette().accent
	label:SetTextColor(color[1],color[2],color[3])
	label:SetFontObject(compact and "GameFontNormal" or "GameFontNormalLarge")
end

function Theme:TrackPanel(panel)
	panels[panel]=true; self:PaintPanel(panel)
end

function Theme:Selection(row, selected)
	rows[row]=true
	row.selected = selected and true or false
	local p=self:Palette()
	local color=selected and p.accent or p.border
	row:SetBackdropColor(selected and color[1]*0.22 or p.background[1],selected and color[2]*0.22 or p.background[2],selected and color[3]*0.22 or p.background[3],0.95)
	row:SetBackdropBorderColor(color[1],color[2],color[3],selected and 1 or 0.4)
end

function Theme:Button(button)
	buttons[button]=true
	button:SetNormalFontObject("GameFontNormal")
	button:SetHighlightFontObject("GameFontHighlight")
	button:SetNormalTexture("Interface\\Buttons\\UI-Panel-Button-Up")
	button:SetPushedTexture("Interface\\Buttons\\UI-Panel-Button-Down")
	button:SetHighlightTexture("Interface\\Buttons\\UI-Panel-Button-Highlight")
	self:TintButton(button)
end

function Theme:TintButton(button)
	local p=self:Palette()
	local classic=p.key=="gold"
	button:SetNormalTexture(classic and "Interface\\Buttons\\UI-Panel-Button-Up" or "Interface\\Buttons\\WHITE8X8")
	button:SetPushedTexture(classic and "Interface\\Buttons\\UI-Panel-Button-Down" or "Interface\\Buttons\\WHITE8X8")
	local texture=button.GetNormalTexture and button:GetNormalTexture()
	if texture and texture.SetVertexColor then
		if classic then texture:SetVertexColor(p.accent[1],p.accent[2],p.accent[3])
		else texture:SetVertexColor(p.background[1]+0.07,p.background[2]+0.07,p.background[3]+0.07) end
	end
	local pushed=button.GetPushedTexture and button:GetPushedTexture()
	if pushed and pushed.SetVertexColor then
		if classic then pushed:SetVertexColor(1,1,1)
		else pushed:SetVertexColor(p.accent[1]*0.24,p.accent[2]*0.24,p.accent[3]*0.24) end
	end
	if not classic and not button.ThemeBorder then
		local border=CreateFrame("Frame",nil,button,BackdropTemplateMixin and "BackdropTemplate" or nil)
		border:SetAllPoints(button); border:SetFrameLevel(button:GetFrameLevel())
		border:SetBackdrop({edgeFile="Interface\\Tooltips\\UI-Tooltip-Border",edgeSize=10})
		button.ThemeBorder=border
	end
	if button.ThemeBorder then
		if classic then button.ThemeBorder:Hide() else button.ThemeBorder:Show() end
		button.ThemeBorder:SetBackdropBorderColor(p.border[1],p.border[2],p.border[3],1)
	end
	local label=button.GetFontString and button:GetFontString()
	if label and label.SetTextColor then label:SetTextColor(p.accent[1],p.accent[2],p.accent[3]) end
end

function Theme:LayoutDirectory(frame)
	local tab=frame.ProfessionsTab
	local width=tab:GetWidth()
	local left=math.max(228,math.min(280,math.floor(width*0.27)))
	tab.CatalogueWidth=left
	tab.CataloguePanel:ClearAllPoints()
	tab.CataloguePanel:SetPoint("TOPLEFT",tab,"TOPLEFT",4,0)
	tab.CataloguePanel:SetPoint("BOTTOMRIGHT",tab,"BOTTOMLEFT",left+4,4)
	tab.SearchBox:ClearAllPoints(); tab.SearchBox:SetPoint("TOPLEFT",18,-12)
	tab.SearchBox:SetSize(left-28,26)
	tab.GuildKnownCheck:ClearAllPoints();tab.GuildKnownCheck:SetPoint("TOPLEFT",14,-40)
 tab.GuildKnownCheck.Text:SetWidth(left-52);tab.GuildKnownCheck.Text:SetJustifyH("LEFT")
 tab.Dropdown:ClearAllPoints(); tab.Dropdown:SetPoint("TOPLEFT",0,-72)
	-- Native dropdown caps extend beyond the text width. Reserve that chrome
 -- so the refresh button does not sit on top of its arrow/hit rectangle.
 UIDropDownMenu_SetWidth(tab.Dropdown,math.max(78,left-150))
 tab.Dropdown:SetWidth(left-110);tab.Dropdown:SetHeight(32)
	if tab.CraftRosterRefreshButton then
		tab.CraftRosterRefreshButton:ClearAllPoints()
		tab.CraftRosterRefreshButton:SetPoint("TOPLEFT",left-92,-74)
		tab.CraftRosterRefreshButton:SetSize(78,26)
	end
	tab.SortButton:ClearAllPoints(); tab.SortButton:SetPoint("TOPLEFT",16,-110); tab.SortButton:SetSize(100,24)
	tab.FavoritesCheck:ClearAllPoints(); tab.FavoritesCheck:SetPoint("TOPLEFT",120,-106)
	tab.FavoritesCheck.Text:SetText("Favorites")
	tab.Results:ClearAllPoints(); tab.Results:SetPoint("TOPLEFT",14,-144)
	tab.Results:SetPoint("BOTTOMRIGHT",tab,"BOTTOMLEFT",left-22,14)
	tab.SelectedCraftScroll:ClearAllPoints()
	tab.SelectedCraftScroll:SetPoint("TOPLEFT",tab,"TOPLEFT",left+18,-4)
	local actionHeight=(width-left-46)>=520 and 60 or 90
 tab.SelectedCraftScroll:SetPoint("BOTTOMRIGHT",tab,"BOTTOMRIGHT",-28,actionHeight+18)
 for _,scroll in ipairs({tab.Results,tab.SelectedCraftScroll}) do if scroll.SetClipsChildren then scroll:SetClipsChildren(true) end end
	tab.ActionBar:ClearAllPoints()
	tab.ActionBar:SetPoint("TOPLEFT",tab.SelectedCraftScroll,"BOTTOMLEFT",0,0)
	tab.ActionBar:SetPoint("BOTTOMRIGHT",tab,"BOTTOMRIGHT",-28,12)

	local gap=4
	local buttonWidth=math.min(120, math.floor((frame:GetWidth()-32-gap*5)/6))
	local controls={frame.TabButtons[1],frame.TabButtons[2],frame.TabButtons[3],frame.WorkOrdersButton,frame.ShoppingButton,frame.SettingsButton}
	for index,button in ipairs(controls) do
		button:ClearAllPoints(); button:SetSize(buttonWidth,28)
		if index<=3 then button:SetPoint("BOTTOMLEFT",frame,"BOTTOMLEFT",12+(index-1)*(buttonWidth+gap),16)
		else button:SetPoint("BOTTOMRIGHT",frame,"BOTTOMRIGHT",-12-(6-index)*(buttonWidth+gap),16) end
	end
	if CraftRoster.SelectedCraft and CraftRoster.SelectedCraft.tab then CraftRoster.SelectedCraft:Refresh() end
end

function Theme:Directory(frame)
	frame.ThemePanel=self:Panel(frame)
	local title=frame.TitleText or frame.TitleBar.TitleText
	self:Window(frame,title)
	local tab=frame.ProfessionsTab
	tab.CataloguePanel=self:Panel(tab)
	tab.ActionBar=CreateFrame("Frame",nil,tab,BackdropTemplateMixin and "BackdropTemplate" or nil)
 -- Footer is above scroll descendants and paints its own opaque background.
 -- This also protects clients whose frame clipping differs from our mocks.
 tab.ActionBar:SetFrameLevel(tab.SelectedCraftScroll:GetFrameLevel()+20)
 self:TrackPanel(tab.ActionBar)
	self:TrackPanel(tab.Details)
	self:Heading(tab.DetailsName)
	for _,spec in ipairs({{"ShoppingButton","Shopping List",function() CraftRoster.ShoppingList:Toggle() end},
		{"SettingsButton","Settings",function() CraftRoster.Panel:Toggle() end}}) do
		local button=CreateFrame("Button",nil,frame,"UIPanelButtonTemplate")
		button:SetText(spec[2]); button:SetScript("OnClick",spec[3]); self:Button(button); frame[spec[1]]=button
	end
	for _,button in ipairs(frame.TabButtons) do self:Button(button) end
	self:Button(frame.WorkOrdersButton); self:Button(tab.SortButton)
	frame:HookScript("OnSizeChanged",function() Theme:LayoutDirectory(frame) end)
	self:LayoutDirectory(frame)
end
