local ADDON_NAME, CraftRoster = ...

local Directory = {}
CraftRoster.Directory = Directory

local PROFESSION_ICONS = {
    Alchemy = "Interface\\Icons\\Trade_Alchemy",
    Blacksmithing = "Interface\\Icons\\Trade_BlackSmithing",
    Enchanting = "Interface\\Icons\\Trade_Engraving",
    Engineering = "Interface\\Icons\\Trade_Engineering",
    Herbalism = "Interface\\Icons\\Trade_Herbalism",
    Inscription = "Interface\\Icons\\trade_inscription",
    Jewelcrafting = "Interface\\Icons\\Trade_Jewelcrafting",
    Leatherworking = "Interface\\Icons\\Trade_Leatherworking",
    Mining = "Interface\\Icons\\Trade_Mining",
    Skinning = "Interface\\Icons\\inv_misc_pelt_wolf_01",
    Tailoring = "Interface\\Icons\\Trade_Tailoring",
    Cooking = "Interface\\Icons\\Trade_Cooking",
    Fishing = "Interface\\Icons\\Trade_Fishing",
    Archaeology = "Interface\\Icons\\Trade_Archaeology",
}

local CLASS_COLORS = {
    WARRIOR = "C79C6E",
    PALADIN = "F58CBA",
    HUNTER = "ABD473",
    ROGUE = "FFF569",
    PRIEST = "FFFFFF",
    DEATHKNIGHT = "C41F3B",
    SHAMAN = "0070DE",
    MAGE = "69CCF0",
    WARLOCK = "9482C9",
    MONK = "00FF96",
    DRUID = "FF7D0A",
    DEMONHUNTER = "A330C9",
    EVOKER = "33937F",
}

local function GetCharacterKey()
    return UnitName("player") .. "-" .. (GetRealmName() or "")
end

local function GetProfessionIcon(profession)
    return PROFESSION_ICONS[profession] or "Interface\\Icons\\Trade_Tailoring"
end

local function GetRaceGenderAtlas(character)
    if not character or not character.raceFile or not character.gender then
        return nil
    end

    local gender = character.gender == 3 and "female" or "male"
    local atlas = "raceicon-" .. character.raceFile:lower() .. "-" .. gender

    if C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(atlas) then
        return atlas
    end

    return nil
end

local function GetColoredCharacterName(characterKey, character)
    local name = characterKey:gsub("%-.+$", "")
    local color = CLASS_COLORS[character and character.class] or "FFFFFF"
    return "|cff" .. color .. name .. "|r"
end

local function GetRecipeName(recipeID)
    local recipe = CraftRosterDB.recipes and CraftRosterDB.recipes[recipeID]
    if recipe and recipe.name then
        return recipe.name
    end

    local name = C_Item.GetItemNameByID(recipeID)
    return name or ("Recipe " .. tostring(recipeID))
end

local function BuildRecipeIndex()
    local index = {}

    for characterKey, character in pairs(CraftRosterDB.characters or {}) do
        for recipeID in pairs(character.recipes or {}) do
            local savedRecipe = CraftRosterDB.recipes[recipeID] or {}
            local profession = savedRecipe.profession or "Unknown"

            index[recipeID] = index[recipeID] or {
                id = recipeID,
                name = GetRecipeName(recipeID),
                profession = profession,
                icon = savedRecipe.icon or GetProfessionIcon(profession),
                crafters = {},
            }

            table.insert(index[recipeID].crafters, characterKey)
        end
    end

    local recipes = {}
    for _, recipe in pairs(index) do
        table.insert(recipes, recipe)
    end

    table.sort(recipes, function(a, b)
        if a.profession ~= b.profession then
            return a.profession < b.profession
        end
        return a.name < b.name
    end)

    return recipes
end

local function CreateRow(parent, width, height)
    local row = CreateFrame("Frame", nil, parent)
    row:SetSize(width, height)
    row:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 10,
        insets = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    row:SetBackdropColor(0, 0, 0, 0.35)
    row:SetBackdropBorderColor(0.8, 0.7, 0.4, 0.35)
    return row
end

local function CreateIcon(parent, texture, size)
    local icon = parent:CreateTexture(nil, "ARTWORK")
    icon:SetSize(size, size)
    icon:SetTexture(texture)
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    return icon
end

function Directory:Initialize()
    if self.frame then
        return
    end

    local frame = CreateFrame("Frame", "CraftRosterDirectory", UIParent, "BasicFrameTemplateWithInset")
    frame:SetSize(760, 500)
    frame:SetPoint("CENTER")
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    frame:SetFrameStrata("HIGH")
    frame:Hide()

    frame.TitleBar.TitleText:SetText("CraftRoster")

    frame.TabButtons = {}
    local tabNames = { "Professions", "Players", "My Recipes" }

    for index, tabName in ipairs(tabNames) do
        local tab = CreateFrame("Button", nil, frame, "CharacterFrameTabButtonTemplate")
        tab:SetText(tabName)
        tab:SetID(index)
        tab:SetPoint("TOPLEFT", frame, "BOTTOMLEFT", 12 + (index - 1) * 125, 0)
        tab:SetScript("OnClick", function()
            Directory:ShowTab(index)
        end)
        frame.TabButtons[index] = tab
    end

    local professionsTab = CreateFrame("Frame", nil, frame)
    professionsTab:SetAllPoints(frame.Inset)
    frame.ProfessionsTab = professionsTab

    professionsTab.SearchBox = CreateFrame("EditBox", nil, professionsTab, "SearchBoxTemplate")
    professionsTab.SearchBox:SetSize(230, 24)
    professionsTab.SearchBox:SetPoint("TOPLEFT", 18, -16)
    professionsTab.SearchBox:SetAutoFocus(false)
    professionsTab.SearchBox:SetScript("OnTextChanged", function()
        Directory:RefreshProfessions()
    end)

    professionsTab.ProfessionDropdown = CreateFrame("Frame", nil, professionsTab, "UIDropDownMenuTemplate")
    professionsTab.ProfessionDropdown:SetPoint("LEFT", professionsTab.SearchBox, "RIGHT", 4, -4)
    UIDropDownMenu_SetWidth(professionsTab.ProfessionDropdown, 160)
    UIDropDownMenu_Initialize(professionsTab.ProfessionDropdown, function(dropdown, level)
        local professions = { "All" }
        for profession in pairs(PROFESSION_ICONS) do
            table.insert(professions, profession)
        end
        table.sort(professions, function(a, b)
            if a == "All" then return true end
            if b == "All" then return false end
            return a < b
        end)

        for _, profession in ipairs(professions) do
            local info = UIDropDownMenu_CreateInfo()
            info.text = profession
            info.func = function()
                Directory.selectedProfession = profession
                UIDropDownMenu_SetText(dropdown, profession)
                Directory:RefreshProfessions()
            end
            UIDropDownMenu_AddButton(info, level)
        end
    end)
    UIDropDownMenu_SetText(professionsTab.ProfessionDropdown, "All")

    professionsTab.RecipeHeader = professionsTab:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    professionsTab.RecipeHeader:SetPoint("TOPLEFT", 18, -52)
    professionsTab.RecipeHeader:SetText("Recipes")

    professionsTab.Results = CreateFrame("ScrollFrame", nil, professionsTab, "UIPanelScrollFrameTemplate")
    professionsTab.Results:SetPoint("TOPLEFT", 14, -76)
    professionsTab.Results:SetPoint("BOTTOMRIGHT", -400, 16)

    professionsTab.ResultsChild = CreateFrame("Frame", nil, professionsTab.Results)
    professionsTab.ResultsChild:SetSize(310, 1)
    professionsTab.Results:SetScrollChild(professionsTab.ResultsChild)

    professionsTab.DetailsHeader = professionsTab:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    professionsTab.DetailsHeader:SetPoint("TOPLEFT", 380, -52)
    professionsTab.DetailsHeader:SetText("Selected Recipe")

    professionsTab.Details = CreateFrame("Frame", nil, professionsTab)
    professionsTab.Details:SetPoint("TOPLEFT", 376, -76)
    professionsTab.Details:SetSize(360, 160)
    professionsTab.Details:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 12,
    })
    professionsTab.Details:SetBackdropColor(0, 0, 0, 0.45)
    professionsTab.Details:SetBackdropBorderColor(0.8, 0.7, 0.4, 0.5)

    professionsTab.DetailsIcon = CreateIcon(professionsTab.Details, "Interface\\Icons\\Trade_Tailoring", 42)
    professionsTab.DetailsIcon:SetPoint("TOPLEFT", 12, -12)

    professionsTab.DetailsName = professionsTab.Details:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
    professionsTab.DetailsName:SetPoint("TOPLEFT", professionsTab.DetailsIcon, "TOPRIGHT", 10, -2)
    professionsTab.DetailsName:SetJustifyH("LEFT")
    professionsTab.DetailsName:SetWidth(280)

    professionsTab.DetailsProfession = professionsTab.Details:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    professionsTab.DetailsProfession:SetPoint("TOPLEFT", professionsTab.DetailsIcon, "BOTTOMLEFT", 0, -10)
    professionsTab.DetailsProfession:SetJustifyH("LEFT")

    professionsTab.CrafterHeader = professionsTab:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    professionsTab.CrafterHeader:SetPoint("TOPLEFT", 380, -250)
    professionsTab.CrafterHeader:SetText("Can Craft")

    professionsTab.CrafterList = CreateFrame("ScrollFrame", nil, professionsTab, "UIPanelScrollFrameTemplate")
    professionsTab.CrafterList:SetPoint("TOPLEFT", 376, -274)
    professionsTab.CrafterList:SetPoint("BOTTOMRIGHT", -18, -14)

    professionsTab.CrafterListChild = CreateFrame("Frame", nil, professionsTab.CrafterList)
    professionsTab.CrafterListChild:SetSize(350, 1)
    professionsTab.CrafterList:SetScrollChild(professionsTab.CrafterListChild)

    local playersTab = CreateFrame("Frame", nil, frame)
    playersTab:SetAllPoints(frame.Inset)
    frame.PlayersTab = playersTab

    playersTab.SearchBox = CreateFrame("EditBox", nil, playersTab, "SearchBoxTemplate")
    playersTab.SearchBox:SetSize(260, 24)
    playersTab.SearchBox:SetPoint("TOPLEFT", 18, -16)
    playersTab.SearchBox:SetAutoFocus(false)
    playersTab.SearchBox:SetScript("OnTextChanged", function()
        Directory:RefreshPlayers()
    end)

    playersTab.Results = CreateFrame("ScrollFrame", nil, playersTab, "UIPanelScrollFrameTemplate")
    playersTab.Results:SetPoint("TOPLEFT", 14, -50)
    playersTab.Results:SetPoint("BOTTOMRIGHT", -18, -14)

    playersTab.ResultsChild = CreateFrame("Frame", nil, playersTab.Results)
    playersTab.ResultsChild:SetSize(700, 1)
    playersTab.Results:SetScrollChild(playersTab.ResultsChild)

    local myRecipesTab = CreateFrame("Frame", nil, frame)
    myRecipesTab:SetAllPoints(frame.Inset)
    frame.MyRecipesTab = myRecipesTab

    myRecipesTab.Status = myRecipesTab:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
    myRecipesTab.Status:SetPoint("TOPLEFT", 18, -16)
    myRecipesTab.Status:SetJustifyH("LEFT")

    local updateButton = CreateFrame("Button", nil, myRecipesTab, "GameMenuButtonTemplate")
    updateButton:SetSize(190, 26)
    updateButton:SetPoint("TOPLEFT", 18, -44)
    updateButton:SetText("Update My Recipes")
    updateButton:SetScript("OnClick", function()
        local added = CraftRoster.RecipeTracker:UpdateKnownRecipes()
        print(("|cff00ff00CraftRoster|r: recipe update complete. %d new recipe(s) added."):format(added or 0))
        Directory:RefreshMyRecipes()
    end)

    myRecipesTab.Results = CreateFrame("ScrollFrame", nil, myRecipesTab, "UIPanelScrollFrameTemplate")
    myRecipesTab.Results:SetPoint("TOPLEFT", 14, -84)
    myRecipesTab.Results:SetPoint("BOTTOMRIGHT", -18, -14)

    myRecipesTab.ResultsChild = CreateFrame("Frame", nil, myRecipesTab.Results)
    myRecipesTab.ResultsChild:SetSize(700, 1)
    myRecipesTab.Results:SetScrollChild(myRecipesTab.ResultsChild)

    frame:SetScript("OnKeyDown", function(_, key)
        if key == "ESCAPE" then
            frame:Hide()
        end
    end)
    frame:SetPropagateKeyboardInput(true)

    self.frame = frame
    self.selectedProfession = "All"
    self.selectedRecipe = nil
    self:ShowTab(1)
end

local function ClearChild(child)
    for _, region in ipairs({ child:GetChildren() }) do
        region:Hide()
        region:SetParent(nil)
    end
end

function Directory:RefreshProfessions()
    local tab = self.frame.ProfessionsTab
    local child = tab.ResultsChild
    ClearChild(child)

    local search = (tab.SearchBox:GetText() or ""):lower()
    local recipes = BuildRecipeIndex()
    local yOffset = -6
    local lastProfession = nil
    local matchCount = 0

    for _, recipe in ipairs(recipes) do
        local professionMatches = self.selectedProfession == "All" or recipe.profession == self.selectedProfession
        local searchMatches = search == "" or recipe.name:lower():find(search, 1, true)

        if professionMatches and searchMatches then
            if recipe.profession ~= lastProfession then
                local header = CreateRow(child, 310, 28)
                header:SetPoint("TOPLEFT", 0, yOffset)

                local headerIcon = CreateIcon(header, GetProfessionIcon(recipe.profession), 20)
                headerIcon:SetPoint("LEFT", 6, 0)

                local headerText = header:CreateFontString(nil, "OVERLAY", "GameFontNormal")
                headerText:SetPoint("LEFT", headerIcon, "RIGHT", 8, 0)
                headerText:SetText(recipe.profession)

                yOffset = yOffset - 34
                lastProfession = recipe.profession
            end

            local row = CreateRow(child, 310, 34)
            row:SetPoint("TOPLEFT", 0, yOffset)

            local icon = CreateIcon(row, recipe.icon, 24)
            icon:SetPoint("LEFT", 6, 0)

            local label = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
            label:SetPoint("LEFT", icon, "RIGHT", 8, 0)
            label:SetText(recipe.name)
            label:SetJustifyH("LEFT")

            row:SetScript("OnMouseUp", function()
                Directory.selectedRecipe = recipe
                Directory:RefreshDetails()
                Directory:RefreshCrafters()
            end)
            row:EnableMouse(true)

            yOffset = yOffset - 40
            matchCount = matchCount + 1
        end
    end

    if matchCount == 0 then
        local empty = child:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        empty:SetPoint("TOPLEFT", 8, yOffset)
        empty:SetText("No recipes saved yet.\nUse My Recipes to update your recipe list.")
        yOffset = yOffset - 50
    end

    child:SetHeight(math.max(1, -yOffset + 20))
end

function Directory:RefreshDetails()
    local tab = self.frame.ProfessionsTab
    local recipe = self.selectedRecipe

    if not recipe then
        tab.DetailsIcon:SetTexture("Interface\\Icons\\Trade_Tailoring")
        tab.DetailsName:SetText("Select a recipe")
        tab.DetailsProfession:SetText("")
        return
    end

    tab.DetailsIcon:SetTexture(recipe.icon)
    tab.DetailsName:SetText(recipe.name)
    tab.DetailsProfession:SetText(recipe.profession)
end

function Directory:RefreshCrafters()
    local tab = self.frame.ProfessionsTab
    local child = tab.CrafterListChild
    ClearChild(child)

    local yOffset = -6

    if not self.selectedRecipe then
        local empty = child:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        empty:SetPoint("TOPLEFT", 8, yOffset)
        empty:SetText("Select a recipe to see crafters.")
        yOffset = yOffset - 30
    else
        for _, characterKey in ipairs(self.selectedRecipe.crafters) do
            local character = CraftRosterDB.characters[characterKey] or {}
            local row = CreateRow(child, 350, 38)
            row:SetPoint("TOPLEFT", 0, yOffset)

            local atlas = GetRaceGenderAtlas(character)
            local iconSize = 24
            local xOffset = 7

            if atlas then
                local raceIcon = row:CreateTexture(nil, "ARTWORK")
                raceIcon:SetSize(iconSize, iconSize)
                raceIcon:SetPoint("LEFT", xOffset, 0)
                raceIcon:SetAtlas(atlas)
                xOffset = xOffset + iconSize + 7
            end

            local name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
            name:SetPoint("LEFT", xOffset, 0)
            name:SetText(GetColoredCharacterName(characterKey, character))

            yOffset = yOffset - 44
        end
    end

    child:SetHeight(math.max(1, -yOffset + 20))
end

function Directory:RefreshPlayers()
    local tab = self.frame.PlayersTab
    local child = tab.ResultsChild
    ClearChild(child)

    local search = (tab.SearchBox:GetText() or ""):lower()
    local yOffset = -6
    local matchCount = 0

    for characterKey, character in pairs(CraftRosterDB.characters or {}) do
        if search == "" or characterKey:lower():find(search, 1, true) then
            local recipeCount = 0
            for _ in pairs(character.recipes or {}) do
                recipeCount = recipeCount + 1
            end

            local row = CreateRow(child, 700, 42)
            row:SetPoint("TOPLEFT", 0, yOffset)

            local atlas = GetRaceGenderAtlas(character)
            local xOffset = 8

            if atlas then
                local raceIcon = row:CreateTexture(nil, "ARTWORK")
                raceIcon:SetSize(26, 26)
                raceIcon:SetPoint("LEFT", xOffset, 0)
                raceIcon:SetAtlas(atlas)
                xOffset = xOffset + 33
            end

            local name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
            name:SetPoint("LEFT", xOffset, 0)
            name:SetText(GetColoredCharacterName(characterKey, character))

            local count = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
            count:SetPoint("RIGHT", -12, 0)
            count:SetText(("%d recipe(s)"):format(recipeCount))

            yOffset = yOffset - 48
            matchCount = matchCount + 1
        end
    end

    if matchCount == 0 then
        local empty = child:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        empty:SetPoint("TOPLEFT", 8, yOffset)
        empty:SetText("No players saved yet.")
        yOffset = yOffset - 40
    end

    child:SetHeight(math.max(1, -yOffset + 20))
end

function Directory:RefreshMyRecipes()
    local tab = self.frame.MyRecipesTab
    local child = tab.ResultsChild
    ClearChild(child)

    local character = CraftRosterDB.characters[GetCharacterKey()]
    local yOffset = -6
    local count = 0

    if character then
        for recipeID in pairs(character.recipes or {}) do
            local savedRecipe = CraftRosterDB.recipes[recipeID] or {}
            local profession = savedRecipe.profession or "Unknown"

            local row = CreateRow(child, 700, 36)
            row:SetPoint("TOPLEFT", 0, yOffset)

            local icon = CreateIcon(row, savedRecipe.icon or GetProfessionIcon(profession), 24)
            icon:SetPoint("LEFT", 7, 0)

            local label = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
            label:SetPoint("LEFT", icon, "RIGHT", 8, 0)
            label:SetText(GetRecipeName(recipeID))

            yOffset = yOffset - 42
            count = count + 1
        end
    end

    if count == 0 then
        local empty = child:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        empty:SetPoint("TOPLEFT", 8, yOffset)
        empty:SetText("No recipes saved for this character yet.")
        yOffset = yOffset - 40
    end

    tab.Status:SetText(("Your saved recipes: %d"):format(count))
    child:SetHeight(math.max(1, -yOffset + 20))
end

function Directory:ShowTab(index)
    self.frame.ProfessionsTab:Hide()
    self.frame.PlayersTab:Hide()
    self.frame.MyRecipesTab:Hide()

    for _, tab in ipairs(self.frame.TabButtons) do
        PanelTemplates_SetTabState(self.frame, tab, index == tab:GetID() and "SELECTED" or "NORMAL")
    end

    if index == 1 then
        self.frame.ProfessionsTab:Show()
        self:RefreshProfessions()
        self:RefreshDetails()
        self:RefreshCrafters()
    elseif index == 2 then
        self.frame.PlayersTab:Show()
        self:RefreshPlayers()
    else
        self.frame.MyRecipesTab:Show()
        self:RefreshMyRecipes()
    end
end

function Directory:Toggle()
    if not self.frame then
        self:Initialize()
    end

    if self.frame:IsShown() then
        self.frame:Hide()
    else
        self:RefreshProfessions()
        self:RefreshPlayers()
        self:RefreshMyRecipes()
        self:ShowTab(1)
        self.frame:Show()
    end
end
