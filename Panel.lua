local ADDON_NAME, CraftRoster = ...

local Panel = {}
CraftRoster.Panel = Panel

local function FormatTime(timestamp)
	return timestamp and date("%I:%M %p", timestamp) or "Never"
end

function Panel:CreateReportButton(parent)
	local button = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
	button:SetSize(88, 20)
	button:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -30, -2)
	button:SetText("Bug Report")
	button:SetScript("OnClick", function() Panel:ShowError() end)
	return button
end

function Panel:Initialize()
	if self.frame then return end

	if CraftRosterDB.settings.showMinimap == nil then
		CraftRosterDB.settings.showMinimap = true
	end

	local frame = CreateFrame("Frame", "CraftRosterPanel", UIParent, "BasicFrameTemplateWithInset")
	frame:SetSize(680, 558)
	frame:SetClampedToScreen(true)
	frame:SetPoint("TOPRIGHT",UIParent,"TOPRIGHT",-24,-72)
	frame:SetMovable(true)
	frame:EnableMouse(true)
	frame:RegisterForDrag("LeftButton")
	frame:SetScript("OnDragStart", frame.StartMoving)
	frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
	frame:SetFrameStrata("HIGH")
	frame:Hide()

	local title = frame.TitleText or frame.TitleBar.TitleText
	title:SetText("CraftRoster Settings")
	title:ClearAllPoints()
	title:SetPoint("TOPLEFT", frame, "TOPLEFT", 12, -5)
	title:SetWidth(220)
	title:SetJustifyH("LEFT")

	frame.StatusText = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	frame.StatusText:SetPoint("TOPLEFT", 16, -66)

	frame.RecipeCountText = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	frame.RecipeCountText:SetPoint("TOPLEFT", 16, -86)

	frame.LastUpdatedText = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	frame.LastUpdatedText:SetPoint("TOPLEFT", 16, -106)

	frame.SyncStatusText = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	frame.SyncStatusText:SetPoint("TOPLEFT", 16, -126)
	frame.SyncStatusText:SetWidth(330)
	frame.SyncStatusText:SetHeight(20)
	local general=frame:CreateFontString(nil,"OVERLAY","GameFontNormalLarge")
	general:SetPoint("TOPLEFT",16,-38); general:SetText("General & recipes")
	CraftRoster.Theme:Heading(general)

	local toggleButton = CreateFrame("Button", nil, frame, "GameMenuButtonTemplate")
	toggleButton:SetSize(170, 26)
	toggleButton:SetPoint("TOPLEFT", 16, -156)
	toggleButton:SetText("Enable / Disable")
	toggleButton:SetScript("OnClick", function()
		CraftRosterDB.settings.enabled = not CraftRosterDB.settings.enabled
		if CraftRoster.WorkOrders then CraftRoster.WorkOrders:Refresh() end
		Panel:RefreshStatus()
	end)

	local updateButton = CreateFrame("Button", nil, frame, "GameMenuButtonTemplate")
	updateButton:SetSize(156, 26)
	updateButton:SetPoint("TOPLEFT", 16, -190)
	updateButton:SetText("Update My Recipes")
	updateButton:SetScript("OnClick", function()
		local added = CraftRoster.RecipeTracker:UpdateKnownRecipes()
		print(("|cff00ff00CraftRoster|r: recipe update complete. %d new recipe(s) added."):format(added or 0))
	end)

	local syncButton = CreateFrame("Button", nil, frame, "GameMenuButtonTemplate")
	syncButton:SetSize(156, 26)
	syncButton:SetPoint("TOPLEFT", 182, -190)
	syncButton:SetText("Sync Guild Recipes")
	syncButton:SetScript("OnClick", function()
		if CraftRoster.GuildSync then
			CraftRoster.GuildSync:SyncNow()
		end
		Panel:RefreshStatus()
	end)

	local resetButton = CreateFrame("Button", nil, frame, "GameMenuButtonTemplate")
	resetButton:SetSize(156, 26)
	resetButton:SetPoint("TOPLEFT", 182, -512)
	resetButton:SetText("Reset Window Position")
	resetButton:SetScript("OnClick", function()
		if CraftRoster.Directory then CraftRoster.Directory:ResetWindow() end
		print("|cff00ff00CraftRoster|r: directory window position reset.")
	end)

	frame.BugReportButton = self:CreateReportButton(frame)

	local autoCheck = CreateFrame("CheckButton", nil, frame, "UICheckButtonTemplate")
	autoCheck:SetPoint("TOPLEFT", 14, -224)
	autoCheck:SetSize(32,32)
	autoCheck.Text:SetText("Auto-update new recipes")
	autoCheck:SetScript("OnClick", function(button)
		CraftRosterDB.settings.autoUpdateRecipes = button:GetChecked()
	end)

	local minimapCheck = CreateFrame("CheckButton", nil, frame, "UICheckButtonTemplate")
	minimapCheck:SetPoint("TOPLEFT", 14, -260)
	minimapCheck:SetSize(32,32)
	minimapCheck.Text:SetText("Show minimap icon")
	minimapCheck:SetScript("OnClick", function(button)
		CraftRosterDB.settings.showMinimap = button:GetChecked()
		if CraftRoster.MinimapButton then
			CraftRoster.MinimapButton:UpdateVisibility()
		end
	end)
	local autoLoad=CreateFrame("CheckButton",nil,frame,"UICheckButtonTemplate")
	autoLoad:SetPoint("TOPLEFT",180,-260); autoLoad:SetSize(32,32)
	autoLoad.Text:SetText("Auto-load items")
	autoLoad:SetScript("OnClick",function(button)
		CraftRoster.Requests:SetAutoLoadItems(button:GetChecked())
	end)
	self.autoLoadCheck=autoLoad

	local appearance=frame:CreateFontString(nil,"OVERLAY","GameFontNormalLarge")
	appearance:SetPoint("TOPLEFT",372,-38); appearance:SetText("Appearance")
	CraftRoster.Theme:Heading(appearance)
	local themeHelp=frame:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
	themeHelp:SetPoint("TOPLEFT",372,-66); themeHelp:SetWidth(276)
	themeHelp:SetText("Pick a look. Your open windows change immediately.")
	local windowHeading=frame:CreateFontString(nil,"OVERLAY","GameFontNormalLarge")
	windowHeading:SetPoint("TOPLEFT",16,-300); windowHeading:SetText("Window controls")
	CraftRoster.Theme:Heading(windowHeading)
	local scaleCheck=CreateFrame("CheckButton",nil,frame,"UICheckButtonTemplate")
	scaleCheck:SetPoint("TOPLEFT",14,-324); scaleCheck.Text:SetText("Use custom addon scale")
	scaleCheck:SetSize(32,32)
	self.scaleCheck=scaleCheck
	local scaleText=frame:CreateFontString(nil,"OVERLAY","GameFontHighlight")
	scaleText:SetPoint("TOPLEFT",32,-360); self.scaleText=scaleText
	local slider=CreateFrame("Slider","CraftRosterScaleSlider",frame,"OptionsSliderTemplate")
	slider:SetPoint("TOPLEFT",32,-382); slider:SetSize(284,18)
	slider:SetMinMaxValues(75,150); slider:SetValueStep(5)
	if slider.SetObeyStepOnDrag then slider:SetObeyStepOnDrag(true) end
	local low=slider.Low or _G.CraftRosterScaleSliderLow
	local high=slider.High or _G.CraftRosterScaleSliderHigh
	if low then low:SetText("75%") end
	if high then high:SetText("150%") end
	self.scaleSlider=slider
	local function ScaleLabel()
		local settings=CraftRosterDB.settings
		local percent=math.floor((tonumber(settings.uiScale) or 1)*100+0.5)
		scaleText:SetText(settings.uiScaleEnabled and ("Addon scale: "..percent.."%") or "Addon scale: game default")
		slider:SetAlpha(settings.uiScaleEnabled and 1 or 0.45)
		slider:EnableMouse(settings.uiScaleEnabled and true or false)
	end
	scaleCheck:SetScript("OnClick",function(button)
		CraftRoster.Theme:SetScale(button:GetChecked(),tonumber(CraftRosterDB.settings.uiScale) or 1)
		ScaleLabel()
	end)
	slider:SetScript("OnValueChanged",function(_,value)
		if Panel.updatingAppearance or not CraftRosterDB.settings.uiScaleEnabled then return end
		local percent=math.max(75,math.min(150,math.floor(value/5+0.5)*5))
		CraftRoster.Theme:SetScale(true,percent/100); ScaleLabel()
	end)
	local opacityText=frame:CreateFontString(nil,"OVERLAY","GameFontHighlight")
	opacityText:SetPoint("TOPLEFT",32,-420); self.opacityText=opacityText
	local opacity=CreateFrame("Slider","CraftRosterOpacitySlider",frame,"OptionsSliderTemplate")
	opacity:SetPoint("TOPLEFT",32,-444); opacity:SetSize(284,18)
	opacity:SetMinMaxValues(40,100); opacity:SetValueStep(5)
	if opacity.SetObeyStepOnDrag then opacity:SetObeyStepOnDrag(true) end
	local opacityLow=opacity.Low or _G.CraftRosterOpacitySliderLow
	local opacityHigh=opacity.High or _G.CraftRosterOpacitySliderHigh
	if opacityLow then opacityLow:SetText("40%") end
	if opacityHigh then opacityHigh:SetText("100%") end
	opacity:SetScript("OnValueChanged",function(_,value)
		if Panel.updatingAppearance then return end
		local percent=math.max(40,math.min(100,math.floor(value/5+0.5)*5))
		CraftRoster.Theme:SetOpacity(percent/100)
		opacityText:SetText("Window opacity: "..percent.."%")
	end)
	self.opacitySlider=opacity
	local opacityHelp=frame:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
	opacityHelp:SetPoint("TOPLEFT",16,-480); opacityHelp:SetWidth(322)
	opacityHelp:SetText("Lower opacity fades windows and text. Settings stays solid.")
	local openMain=CreateFrame("Button",nil,frame,"UIPanelButtonTemplate")
	openMain:SetPoint("TOPLEFT",16,-512); openMain:SetSize(156,26)
	openMain:SetText("Open main window")
	openMain:SetScript("OnClick",function() Panel:ShowMainWindow() end)
	self.openMainButton=openMain
	self.resetWindowButton=resetButton
	self.generalButtons={toggleButton,updateButton,syncButton,resetButton,openMain}
	local themeLabel=frame:CreateFontString(nil,"OVERLAY","GameFontHighlight")
	themeLabel:SetPoint("TOPLEFT",372,-108); self.themeNameText=themeLabel
	self.themeButtons={}
	for index,palette in ipairs(CraftRoster.Theme.palettes) do
		local tile=CreateFrame("Button",nil,frame,BackdropTemplateMixin and "BackdropTemplate" or nil)
		tile:SetSize(134,30); tile:SetPoint("TOPLEFT",372+((index-1)%2)*142,-132-math.floor((index-1)/2)*34)
		tile.themeKey=palette.key
		tile.Label=tile:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
		tile.Label:SetPoint("LEFT",8,0); tile.Label:SetWidth(106); tile.Label:SetJustifyH("LEFT")
		tile.Label:SetText(palette.shortName or palette.name)
		tile.Label:SetTextColor(palette.accent[1],palette.accent[2],palette.accent[3])
		tile.Check=tile:CreateTexture(nil,"OVERLAY")
		tile.Check:SetTexture("Interface\\Buttons\\UI-CheckBox-Check")
		tile.Check:SetPoint("RIGHT",-2,0); tile.Check:SetSize(18,18)
		tile:SetScript("OnClick",function() CraftRoster.Theme:SetPalette(palette.key) end)
		tile:SetScript("OnEnter",function(button)
			GameTooltip:SetOwner(button,"ANCHOR_RIGHT"); GameTooltip:SetText(palette.name)
			GameTooltip:AddLine(palette.description,1,1,1,true)
			GameTooltip:AddLine("Click to apply immediately.",1,1,1); GameTooltip:Show()
		end)
		tile:SetScript("OnLeave",function() GameTooltip:Hide() end)
		self.themeButtons[index]=tile
	end
	local preview=CreateFrame("Frame",nil,frame,BackdropTemplateMixin and "BackdropTemplate" or nil)
	preview:SetPoint("TOPLEFT",372,-318); preview:SetSize(276,90)
	preview.Title=preview:CreateFontString(nil,"OVERLAY","GameFontNormal")
	preview.Title:SetPoint("TOPLEFT",10,-10); preview.Title:SetText("Theme preview")
	CraftRoster.Theme:Heading(preview.Title,true)
	preview.Selected=CreateFrame("Frame",nil,preview,BackdropTemplateMixin and "BackdropTemplate" or nil)
	preview.Selected:SetPoint("TOPLEFT",8,-32); preview.Selected:SetSize(260,22)
	preview.Selected:SetBackdrop({bgFile="Interface\\Buttons\\WHITE8X8",edgeFile="Interface\\Tooltips\\UI-Tooltip-Border",edgeSize=8})
	preview.Selected.Label=preview.Selected:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
	preview.Selected.Label:SetPoint("LEFT",6,0); preview.Selected.Label:SetText("Example selected recipe")
	preview.Material=preview:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
	preview.Material:SetPoint("TOPLEFT",10,-64); preview.Material:SetText("Example materials: 24 / 30 (Need 6)")
	self.themePreview=preview
	CraftRoster.Theme:TrackPanel(preview)
	local resetAppearance=CreateFrame("Button",nil,frame,"UIPanelButtonTemplate")
	resetAppearance:SetPoint("TOPLEFT",372,-424); resetAppearance:SetSize(170,24); resetAppearance:SetText("Reset appearance")
	resetAppearance:SetScript("OnClick",function()
		CraftRoster.Theme:SetScale(false,1); CraftRoster.Theme:SetOpacity(1)
		CraftRoster.Theme:SetPalette("gold"); Panel:RefreshStatus()
	end)
	self.resetAppearance=resetAppearance
	local hint=frame:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
	hint:SetPoint("TOPLEFT",372,-466); hint:SetWidth(276)
	hint:SetText("Drag either window to compare changes. Resize the main window with its bottom-right corner. All preferences save automatically.")

	local errorFrame = CreateFrame("Frame", "CraftRosterErrorPopup", UIParent, "BasicFrameTemplateWithInset")
	errorFrame:SetSize(560, 320)
	errorFrame:SetClampedToScreen(true)
	errorFrame:SetPoint("CENTER")
	errorFrame:SetMovable(true)
	errorFrame:EnableMouse(true)
	errorFrame:RegisterForDrag("LeftButton")
	errorFrame:SetScript("OnDragStart", errorFrame.StartMoving)
	errorFrame:SetScript("OnDragStop", errorFrame.StopMovingOrSizing)
	errorFrame:SetFrameStrata("TOOLTIP")
	errorFrame:Hide()
	local errorTitle = errorFrame.TitleText or errorFrame.TitleBar.TitleText
	errorTitle:SetText("CraftRoster — Copy Bug Report")

	errorFrame.Instructions = errorFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	errorFrame.Instructions:SetPoint("TOPLEFT", 16, -38)
	errorFrame.Instructions:SetText("Text is selected automatically. Press Ctrl+C, then paste it to the developer.")

	errorFrame.Scroll = CreateFrame("ScrollFrame", nil, errorFrame, "UIPanelScrollFrameTemplate")
	errorFrame.Scroll:SetPoint("TOPLEFT", 16, -64)
	errorFrame.Scroll:SetPoint("BOTTOMRIGHT", -34, 16)
	errorFrame.ErrorBox = CreateFrame("EditBox", nil, errorFrame.Scroll)
	errorFrame.ErrorBox:SetMultiLine(true)
	errorFrame.ErrorBox:SetAutoFocus(false)
	errorFrame.ErrorBox:SetFontObject("ChatFontNormal")
	errorFrame.ErrorBox:SetSize(490, 220)
	errorFrame.ErrorBox:SetMaxLetters(0)
	errorFrame.Scroll:SetScrollChild(errorFrame.ErrorBox)
	errorFrame.ErrorBox:SetScript("OnEscapePressed", function() errorFrame:Hide() end)
	local selectAll = CreateFrame("Button", nil, errorFrame, "UIPanelButtonTemplate")
	selectAll:SetSize(90, 22)
	selectAll:SetPoint("TOPRIGHT", errorFrame, "TOPRIGHT", -34, -35)
	selectAll:SetText("Select all")
	selectAll:SetScript("OnClick", function()
		errorFrame.ErrorBox:SetFocus()
		errorFrame.ErrorBox:HighlightText()
	end)
	errorFrame:SetScript("OnHide", function() errorFrame.ErrorBox:ClearFocus() end)

	frame:SetScript("OnKeyDown", function(_, key)
		if key == "ESCAPE" then frame:Hide() end
	end)
	if frame.SetPropagateKeyboardInput then frame:SetPropagateKeyboardInput(true) end

	self.frame = frame
	self.errorFrame = errorFrame
	self.autoCheck = autoCheck
	self.minimapCheck = minimapCheck
	CraftRoster.Theme:Window(frame,title,true)
	CraftRoster.Theme:Window(errorFrame,errorTitle,true)
	for _,button in ipairs({toggleButton,updateButton,syncButton,resetButton,resetAppearance,openMain}) do CraftRoster.Theme:Button(button) end
	self:RefreshStatus()
end

function Panel:ShowError()
	if not self.frame then self:Initialize() end
	local report = CraftRoster.ErrorReporter and CraftRoster.ErrorReporter:GetReport() or "Error reporting is unavailable on this client."
	self.errorFrame:Show()
	self.errorFrame.ErrorBox:SetText(report)
	self.errorFrame.ErrorBox:SetHeight(math.max(220, self.errorFrame.ErrorBox:GetNumLines() * 16 + 20))
	self.errorFrame.Scroll:SetVerticalScroll(0)
	self.errorFrame.ErrorBox:SetFocus()
	self.errorFrame.ErrorBox:HighlightText()
end

function Panel:Toggle()
	if not self.frame then self:Initialize() end
	if self.frame:IsShown() then self.frame:Hide() else self:RefreshStatus() self.frame:Show() end
end

function Panel:ShowMainWindow()
	local directory=CraftRoster.Directory
	if not directory then return end
	if not directory.frame or not directory.frame:IsShown() then directory:Toggle() end
end

function Panel:RefreshAppearance()
	local theme=CraftRoster.Theme
	local current=theme:Palette()
	self.themeNameText:SetText("Theme: "..current.name)
	for index,tile in ipairs(self.themeButtons) do
		local palette=theme.palettes[index]
		theme:PaintPanel(tile,palette)
		-- Tiny tiles use colour samples; decorative marks belong in the preview.
		if tile.ThemeMark then tile.ThemeMark:Hide() end
		if tile.themeKey==current.key then
			tile.Check:Show()
			tile:SetBackdropBorderColor(palette.accent[1],palette.accent[2],palette.accent[3],1)
		else tile.Check:Hide() end
	end
	theme:PaintPanel(self.themePreview)
	theme:Selection(self.themePreview.Selected,true)
	self.themePreview:SetAlpha(theme:Opacity())
end

function Panel:RefreshStatus()
	if not self.frame then return end
	local settings = CraftRosterDB.settings

	self.frame.StatusText:SetText(("Status: %s"):format(
		settings.enabled and "|cff00ff00Enabled|r" or "|cffff0000Disabled|r"
	))
	self.frame.RecipeCountText:SetText(("Known recipes saved: %d"):format(
		CraftRoster.RecipeTracker:GetKnownRecipeCount()
	))
	self.frame.LastUpdatedText:SetText(("Last updated: %s"):format(
		FormatTime(CraftRosterDB.lastRecipeUpdate)
	))

	if CraftRoster.GuildSync then
		self.frame.SyncStatusText:SetText(CraftRoster.GuildSync:GetStatusText())
	end

	self.autoCheck:SetChecked(settings.autoUpdateRecipes)
	self.minimapCheck:SetChecked(settings.showMinimap ~= false)
	self.autoLoadCheck:SetChecked(settings.autoLoadItems ~= false)
	if self.scaleCheck then
		self.updatingAppearance=true
		self.scaleCheck:SetChecked(settings.uiScaleEnabled==true)
		self.scaleSlider:SetValue((tonumber(settings.uiScale) or 1)*100)
		self.scaleSlider:SetAlpha(settings.uiScaleEnabled and 1 or 0.45)
		self.scaleSlider:EnableMouse(settings.uiScaleEnabled and true or false)
		self.scaleText:SetText(settings.uiScaleEnabled and ("Addon scale: "..math.floor((tonumber(settings.uiScale) or 1)*100+0.5).."%") or "Addon scale: game default")
		local opacity=math.floor(CraftRoster.Theme:Opacity()*100+0.5)
		self.opacitySlider:SetValue(opacity)
		self.opacityText:SetText("Window opacity: "..opacity.."%")
		self:RefreshAppearance()
		self.updatingAppearance=false
	end
end
