local ADDON_NAME, CraftRoster = ...

local Panel = {}
CraftRoster.Panel = Panel

local lastError = nil

local function FormatTime(timestamp)
	return timestamp and date("%l:%M %p", timestamp) or "Never"
end

local function CaptureError(err)
	if err and err:find("CraftRoster", 1, true) then
		lastError = err
		print("|cffff0000CraftRoster|r error captured. Click the beetle button in /cr settings to view or copy it.")
	end
end

local originalErrorHandler = geterrorhandler()
seterrorhandler(function(err)
	CaptureError(err)
	return originalErrorHandler(err)
end)

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

	frame.TitleBar.TitleText:SetText("CraftRoster Settings")

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
		GameTooltip:AddLine("View or copy the last CraftRoster error.", 1, 1, 1)
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
	errorFrame.TitleBar.TitleText:SetText("CraftRoster — Last Error")

	errorFrame.Instructions = errorFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	errorFrame.Instructions:SetPoint("TOPLEFT", 16, -38)
	errorFrame.Instructions:SetText("Press Ctrl+C to copy the selected error for Discord.")

	errorFrame.ErrorBox = CreateFrame("EditBox", nil, errorFrame, "InputBoxTemplate")
	errorFrame.ErrorBox:SetMultiLine(true)
	errorFrame.ErrorBox:SetAutoFocus(false)
	errorFrame.ErrorBox:SetPoint("TOPLEFT", 16, -64)
	errorFrame.ErrorBox:SetPoint("BOTTOMRIGHT", -18, 16)
	errorFrame.ErrorBox:SetScript("OnEscapePressed", function(box) box:ClearFocus() end)

	frame:SetScript("OnKeyDown", function(_, key)
		if key == "ESCAPE" then frame:Hide() end
	end)
	frame:SetPropagateKeyboardInput(true)

	self.frame = frame
	self.errorFrame = errorFrame
	self.autoCheck = autoCheck
	self.minimapCheck = minimapCheck
	self:RefreshStatus()
end

function Panel:ShowError()
	if not self.errorFrame then return end

	self.errorFrame.ErrorBox:SetText(lastError or "No CraftRoster error has been captured.")
	self.errorFrame.ErrorBox:SetFocus()
	self.errorFrame.ErrorBox:HighlightText()
	self.errorFrame:Show()
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
