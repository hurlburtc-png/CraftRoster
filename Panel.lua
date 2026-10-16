local ADDON_NAME, CraftRoster = ...

local Panel = {}
CraftRoster.Panel = Panel

local function FormatTime(timestamp)
    if not timestamp then
        return "Never"
    end

    return date("%l:%M %p", timestamp)
end

function Panel:Initialize()
    if self.frame then
        return
    end

    local frame = CreateFrame("Frame", "CraftRosterPanel", UIParent, "BasicFrameTemplateWithInset")
    frame:SetSize(300, 190)
    frame:SetPoint("CENTER")
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    frame:SetFrameStrata("HIGH")
    frame:Hide()

    frame.TitleBar.TitleText:SetText("CraftRoster")

    frame.StatusText = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    frame.StatusText:SetPoint("TOPLEFT", 16, -38)
    frame.StatusText:SetJustifyH("LEFT")

    frame.RecipeCountText = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    frame.RecipeCountText:SetPoint("TOPLEFT", 16, -58)
    frame.RecipeCountText:SetJustifyH("LEFT")

    frame.LastUpdatedText = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    frame.LastUpdatedText:SetPoint("TOPLEFT", 16, -78)
    frame.LastUpdatedText:SetJustifyH("LEFT")

    local toggleButton = CreateFrame("Button", nil, frame, "GameMenuButtonTemplate")
    toggleButton:SetSize(170, 26)
    toggleButton:SetPoint("TOPLEFT", 16, -104)
    toggleButton:SetText("Enable / Disable")
    toggleButton:SetScript("OnClick", function()
        local settings = CraftRosterDB.settings
        settings.enabled = not settings.enabled
        Panel:RefreshStatus()
    end)

    local updateButton = CreateFrame("Button", nil, frame, "GameMenuButtonTemplate")
    updateButton:SetSize(170, 26)
    updateButton:SetPoint("TOPLEFT", 16, -136)
    updateButton:SetText("Update My Recipes")
    updateButton:SetScript("OnClick", function()
        local added = CraftRoster.RecipeTracker:UpdateKnownRecipes()
        print(("|cff00ff00CraftRoster|r: recipe update complete. %d new recipe(s) added."):format(added or 0))
    end)

    local autoCheck = CreateFrame("CheckButton", nil, frame, "UICheckButtonTemplate")
    autoCheck:SetPoint("TOPLEFT", 14, -168)
    autoCheck.Text:SetText("Auto-update new recipes")
    autoCheck:SetScript("OnClick", function(button)
        CraftRosterDB.settings.autoUpdateRecipes = button:GetChecked()
    end)

    frame:SetScript("OnKeyDown", function(_, key)
        if key == "ESCAPE" then
            frame:Hide()
        end
    end)
    frame:SetPropagateKeyboardInput(true)

    self.frame = frame
    self.autoCheck = autoCheck
    self:RefreshStatus()
end

function Panel:Toggle()
    if not self.frame then
        self:Initialize()
    end

    if self.frame:IsShown() then
        self.frame:Hide()
    else
        self:RefreshStatus()
        self.frame:Show()
    end
end

function Panel:RefreshStatus()
    if not self.frame then
        return
    end

    local settings = CraftRosterDB.settings
    local enabled = settings.enabled
    local auto = settings.autoUpdateRecipes
    local count = CraftRoster.RecipeTracker:GetKnownRecipeCount()

    self.frame.StatusText:SetText(("Status: %s"):format(
        enabled and "|cff00ff00Enabled|r" or "|cffff0000Disabled|r"
    ))
    self.frame.RecipeCountText:SetText(("Known recipes saved: %d"):format(count))
    self.frame.LastUpdatedText:SetText(("Last updated: %s"):format(
        FormatTime(CraftRosterDB.lastRecipeUpdate)
    ))

    self.autoCheck:SetChecked(auto)
end
