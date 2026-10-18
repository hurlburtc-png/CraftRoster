local ADDON_NAME, CraftRoster = ...

local Panel = {}
CraftRoster.Panel = Panel

local function FormatTime(timestamp)
	return timestamp and date("%I:%M %p", timestamp) or "Never"
end

function Panel:Initialize()
	if self.frame then return end

	if CraftRosterDB.settings.showMinimap == nil then
		CraftRosterDB.settings.showMinimap = true
	end

	local frame = CreateFrame("Frame", "CraftRosterPanel", UIParent, "BasicFrameTemplateWithInset")
	frame:SetSize(300, 340)
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

	local bugButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
	bugButton:SetSize(26, 26)
	bugButton:SetPoint("TOPRIGHT", -34, -10)
	bugButton:SetNormalTexture("Interface\\Icons\\INV_Misc_Bug_01")
	bugButton:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square")
	bugButton:SetScript("OnClick", function() Panel:ShowError() end)
	bugButton:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_LEFT")
		GameTooltip:SetText("CraftRoster Error")
		GameTooltip:AddLine("Copy a bug report with recent Lua errors and client details.", 1, 1, 1)
		GameTooltip:Show()
	end)
	bugButton:SetScript("OnLeave", function() GameTooltip:Hide() end)

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

	local errorFrame = CreateFrame("Frame", "CraftRosterErrorPopup", UIParent, "BasicFrameTemplateWithInset")
	errorFrame:SetSize(560, 320)
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
end
