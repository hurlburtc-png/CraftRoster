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
	frame:SetSize(380, 558)
	frame:SetClampedToScreen(true)
	frame:SetPoint("CENTER")
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
	frame.StatusText:SetPoint("TOPLEFT", 16, -38)

	frame.RecipeCountText = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	frame.RecipeCountText:SetPoint("TOPLEFT", 16, -58)

	frame.LastUpdatedText = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	frame.LastUpdatedText:SetPoint("TOPLEFT", 16, -78)

	frame.SyncStatusText = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	frame.SyncStatusText:SetPoint("TOPLEFT", 16, -98)

	local toggleButton = CreateFrame("Button", nil, frame, "GameMenuButtonTemplate")
	toggleButton:SetSize(170, 26)
	toggleButton:SetPoint("TOPLEFT", 16, -124)
	toggleButton:SetText("Enable / Disable")
	toggleButton:SetScript("OnClick", function()
		CraftRosterDB.settings.enabled = not CraftRosterDB.settings.enabled
		if CraftRoster.WorkOrders then CraftRoster.WorkOrders:Refresh() end
		Panel:RefreshStatus()
	end)

	local updateButton = CreateFrame("Button", nil, frame, "GameMenuButtonTemplate")
	updateButton:SetSize(170, 26)
	updateButton:SetPoint("TOPLEFT", 16, -156)
	updateButton:SetText("Update My Recipes")
	updateButton:SetScript("OnClick", function()
		local added = CraftRoster.RecipeTracker:UpdateKnownRecipes()
		print(("|cff00ff00CraftRoster|r: recipe update complete. %d new recipe(s) added."):format(added or 0))
	end)

	local syncButton = CreateFrame("Button", nil, frame, "GameMenuButtonTemplate")
	syncButton:SetSize(170, 26)
	syncButton:SetPoint("TOPLEFT", 16, -188)
	syncButton:SetText("Sync Guild Recipes")
	syncButton:SetScript("OnClick", function()
		if CraftRoster.GuildSync then
			CraftRoster.GuildSync:SyncNow()
		end
		Panel:RefreshStatus()
	end)

	local resetButton = CreateFrame("Button", nil, frame, "GameMenuButtonTemplate")
	resetButton:SetSize(170, 26)
	resetButton:SetPoint("TOPLEFT", 16, -220)
	resetButton:SetText("Reset Window Position")
	resetButton:SetScript("OnClick", function()
		if CraftRoster.Directory then CraftRoster.Directory:ResetWindow() end
		print("|cff00ff00CraftRoster|r: directory window position reset.")
	end)

	frame.BugReportButton = self:CreateReportButton(frame)

	local autoCheck = CreateFrame("CheckButton", nil, frame, "UICheckButtonTemplate")
	autoCheck:SetPoint("TOPLEFT", 14, -254)
	autoCheck.Text:SetText("Auto-update new recipes")
	autoCheck:SetScript("OnClick", function(button)
		CraftRosterDB.settings.autoUpdateRecipes = button:GetChecked()
	end)

	local minimapCheck = CreateFrame("CheckButton", nil, frame, "UICheckButtonTemplate")
	minimapCheck:SetPoint("TOPLEFT", 14, -286)
	minimapCheck.Text:SetText("Show minimap icon")
	minimapCheck:SetScript("OnClick", function(button)
		CraftRosterDB.settings.showMinimap = button:GetChecked()
		if CraftRoster.MinimapButton then
			CraftRoster.MinimapButton:UpdateVisibility()
		end
	end)

	local appearance=frame:CreateFontString(nil,"OVERLAY","GameFontNormalLarge")
	appearance:SetPoint("TOPLEFT",16,-326); appearance:SetText("Appearance")
	CraftRoster.Theme:Heading(appearance)
	local scaleCheck=CreateFrame("CheckButton",nil,frame,"UICheckButtonTemplate")
	scaleCheck:SetPoint("TOPLEFT",14,-350); scaleCheck.Text:SetText("Use custom addon scale")
	self.scaleCheck=scaleCheck
	local scaleText=frame:CreateFontString(nil,"OVERLAY","GameFontHighlight")
	scaleText:SetPoint("TOPLEFT",32,-386); self.scaleText=scaleText
	local slider=CreateFrame("Slider","CraftRosterScaleSlider",frame,"OptionsSliderTemplate")
	slider:SetPoint("TOPLEFT",32,-416); slider:SetSize(292,18)
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
	local themeLabel=frame:CreateFontString(nil,"OVERLAY","GameFontHighlight")
	themeLabel:SetPoint("TOPLEFT",16,-462); themeLabel:SetText("Colour theme")
	local dropdown=CreateFrame("Frame",nil,frame,"UIDropDownMenuTemplate")
	dropdown:SetPoint("TOPLEFT",116,-450); UIDropDownMenu_SetWidth(dropdown,190)
	self.themeDropdown=dropdown
	UIDropDownMenu_Initialize(dropdown,function(_,level)
		for _,palette in ipairs(CraftRoster.Theme.palettes) do
			local info=UIDropDownMenu_CreateInfo()
			info.text=palette.name; info.checked=CraftRoster.Theme:Palette().key==palette.key
			info.func=function() CraftRoster.Theme:SetPalette(palette.key); UIDropDownMenu_SetText(dropdown,palette.name) end
			UIDropDownMenu_AddButton(info,level)
		end
	end)
	local resetAppearance=CreateFrame("Button",nil,frame,"UIPanelButtonTemplate")
	resetAppearance:SetPoint("TOPLEFT",16,-492); resetAppearance:SetSize(170,24); resetAppearance:SetText("Reset appearance")
	resetAppearance:SetScript("OnClick",function()
		CraftRoster.Theme:SetScale(false,1); CraftRoster.Theme:SetPalette("gold"); Panel:RefreshStatus()
	end)
	self.resetAppearance=resetAppearance
	local hint=frame:CreateFontString(nil,"OVERLAY","GameFontDisableSmall")
	hint:SetPoint("TOPLEFT",16,-526); hint:SetWidth(344); hint:SetText("Applies to CraftRoster windows; fits your screen.")

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
	errorFrame.Instructions:SetText("Press Ctrl+C (Cmd+C on Mac), then paste the report to us.")

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
	errorFrame:SetScript("OnHide", function() errorFrame.ErrorBox:ClearFocus() end)

	frame:SetScript("OnKeyDown", function(_, key)
		if key == "ESCAPE" then frame:Hide() end
	end)
	if frame.SetPropagateKeyboardInput then frame:SetPropagateKeyboardInput(true) end

	self.frame = frame
	self.errorFrame = errorFrame
	self.autoCheck = autoCheck
	self.minimapCheck = minimapCheck
	CraftRoster.Theme:Window(frame,title)
	CraftRoster.Theme:Window(errorFrame,errorTitle)
	for _,button in ipairs({toggleButton,updateButton,syncButton,resetButton,resetAppearance}) do CraftRoster.Theme:Button(button) end
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
	if self.scaleCheck then
		self.updatingAppearance=true
		self.scaleCheck:SetChecked(settings.uiScaleEnabled==true)
		self.scaleSlider:SetValue((tonumber(settings.uiScale) or 1)*100)
		self.scaleSlider:SetAlpha(settings.uiScaleEnabled and 1 or 0.45)
		self.scaleSlider:EnableMouse(settings.uiScaleEnabled and true or false)
		self.scaleText:SetText(settings.uiScaleEnabled and ("Addon scale: "..math.floor((tonumber(settings.uiScale) or 1)*100+0.5).."%") or "Addon scale: game default")
		UIDropDownMenu_SetText(self.themeDropdown,CraftRoster.Theme:Palette().name)
		self.updatingAppearance=false
	end
end
