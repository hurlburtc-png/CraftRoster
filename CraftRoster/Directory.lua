local ADDON_NAME, CraftRoster = ...

local Directory = {}
CraftRoster.Directory = Directory

local DEFAULT_WINDOW = { width = 780, height = 520, x = 0, y = 0 }
local MIN_WIDTH, MIN_HEIGHT = 640, 440

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
	WARRIOR = "C79C6E", PALADIN = "F58CBA", HUNTER = "ABD473",
	ROGUE = "FFF569", PRIEST = "FFFFFF", DEATHKNIGHT = "C41F3B",
	SHAMAN = "0070DE", MAGE = "69CCF0", WARLOCK = "9482C9",
	MONK = "00FF96", DRUID = "FF7D0A", DEMONHUNTER = "A330C9",
	EVOKER = "33937F",
}

local SEARCH_WORD_ALIASES = {
	wrist = { "bracer" },
	bracer = { "bracer" },
	chest = { "chest", "chestpiece", "robe" },
	hands = { "gloves", "gauntlets" },
	gloves = { "gloves" },
	gauntlets = { "gauntlets" },
	feet = { "boots" },
	boots = { "boots" },
	legs = { "leg" },
	leg = { "leg" },
	weapon = { "weapon" },
	mail = { "mail" },
}

local SEARCH_PHRASE_ALIASES = {
	["mail chest"] = { "mail chest" },
	["mail chest piece"] = { "mail chest" },
	["wrist enchant"] = { "bracer" },
	["bracer enchant"] = { "bracer" },
}

local SORT_MODES = { "name", "crafters", "profession" }
local SORT_LABELS = {
	name = "Sort: Name",
	crafters = "Sort: Crafters",
	profession = "Sort: Profession",
}

local sortMode = "name"

local function GetSearchTerms(search)
	local terms = { search }

	for phrase, expansions in pairs(SEARCH_PHRASE_ALIASES) do
		if search:find(phrase, 1, true) then
			for _, expansion in ipairs(expansions) do
				table.insert(terms, expansion)
			end
		end
	end

	for word in search:gmatch("%a+") do
		local expansions = SEARCH_WORD_ALIASES[word]
		if expansions then
			for _, expansion in ipairs(expansions) do
				table.insert(terms, expansion)
			end
		end
	end

	return terms
end

local rowPools = {}
local onlineByName = {}

local function GetCharacterKey()
	return UnitName("player") .. "-" .. (GetRealmName() or "")
end

local function GetProfessionIcon(profession)
	return PROFESSION_ICONS[profession] or "Interface\\Icons\\Trade_Tailoring"
end

local function GetRaceGenderAtlas(character)
	if not character or not character.raceFile or not character.gender then return nil end
	local gender = character.gender == 3 and "female" or "male"
	local atlas = "raceicon-" .. character.raceFile:lower() .. "-" .. gender
	if C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(atlas) then return atlas end
	return nil
end

local function GetColoredName(characterKey, character, disabled)
	local name = characterKey:gsub("%-.+$", "")
	local color = CLASS_COLORS[character and character.class] or "FFFFFF"
	if disabled then color = "7F7F7F" end
	return "|cff" .. color .. name .. "|r"
end

local function GetRecipeName(recipeID)
	local recipe = CraftRosterDB.recipes and CraftRosterDB.recipes[recipeID]
	return recipe and recipe.name or ("Recipe " .. tostring(recipeID))
end

local function IsCharacterOnline(characterKey)
	local name = characterKey:gsub("%-.+$", "")
	return onlineByName[name:lower()] == true
end

local function GetProfessionTotals(character)
	local recipeTotals = {}

	for recipeID in pairs(character.recipes or {}) do
		local saved = CraftRosterDB.recipes[recipeID]
		local profession = saved and saved.profession or "Unknown"
		recipeTotals[profession] = (recipeTotals[profession] or 0) + 1
	end

	local parts = {}

	for profession, data in pairs(character.professions or {}) do
		local count = recipeTotals[profession] or 0
		table.insert(parts, ("%s %d (%d recipe%s)"):format(
			profession, data.skill or 0, count, count == 1 and "" or "s"
		))
	end

	for profession, count in pairs(recipeTotals) do
		if not (character.professions and character.professions[profession]) then
			table.insert(parts, ("%s (%d recipe%s)"):format(
				profession, count, count == 1 and "" or "s"
			))
		end
	end

	table.sort(parts)
	return table.concat(parts, " · ")
end

function Directory:InvalidateIndex()
	self.recipeIndex = nil
	self:RefreshIfVisible()
end

local function BuildRecipeIndex()
	local index = {}

	for characterKey, character in pairs(CraftRosterDB.characters or {}) do
		for recipeID in pairs(character.recipes or {}) do
			local saved = CraftRosterDB.recipes[recipeID] or {}
			local profession = saved.profession or "Unknown"
			local recipe = index[recipeID]

			if not recipe then
				recipe = {
					id = recipeID,
					name = saved.name or GetRecipeName(recipeID),
					profession = profession,
					icon = saved.icon or GetProfessionIcon(profession),
					crafters = {},
				}
				index[recipeID] = recipe
			end

			table.insert(recipe.crafters, characterKey)
		end
	end

	local recipes = {}
	for _, recipe in pairs(index) do table.insert(recipes, recipe) end

	table.sort(recipes, function(a, b)
		if a.profession ~= b.profession then return a.profession < b.profession end
		return a.name < b.name
	end)

	return recipes
end

local function GetRecipeIndex()
	if not Directory.recipeIndex then
		Directory.recipeIndex = BuildRecipeIndex()
	end
	return Directory.recipeIndex
end

local function CreateRow(child, width, height)
	local row = CreateFrame("Frame", nil, child)
	row:SetSize(width, height)
	row:SetBackdrop({
		bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
		edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
		edgeSize = 10,
		insets = { left = 2, right = 2, top = 2, bottom = 2 },
	})
	row:SetBackdropColor(0, 0, 0, 0.30)
	row:SetBackdropBorderColor(0.8, 0.7, 0.4, 0.25)

	row.Icon = row:CreateTexture(nil, "ARTWORK")
	row.Icon:SetSize(24, 24)
	row.Icon:SetPoint("LEFT", 7, 0)
	row.Icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

	row.Label = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	row.Label:SetPoint("LEFT", row.Icon, "RIGHT", 8, 0)
	row.Label:SetJustifyH("LEFT")

	row.RightLabel = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	row.RightLabel:SetPoint("RIGHT", -10, 0)

	row:SetScript("OnEnter", function(self)
		self:SetBackdropColor(0.16, 0.16, 0.16, 0.65)
		self:SetBackdropBorderColor(0.9, 0.8, 0.5, 0.75)

		if self.hyperlink then
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			GameTooltip:SetHyperlink(self.hyperlink)
			GameTooltip:Show()
		elseif self.tooltipLines then
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			GameTooltip:SetText(self.tooltipTitle or "")
			for _, line in ipairs(self.tooltipLines) do
				GameTooltip:AddLine(line, 1, 1, 1)
			end
			GameTooltip:Show()
		end
	end)

	row:SetScript("OnLeave", function(self)
		self:SetBackdropColor(0, 0, 0, 0.30)
		self:SetBackdropBorderColor(0.8, 0.7, 0.4, 0.25)
		GameTooltip:Hide()
	end)

	return row
end

local function AcquireRow(child, width, height)
	local pool = rowPools[child]
	if not pool then pool = {}; rowPools[child] = pool end

	local row
	for _, candidate in ipairs(pool) do
		if not candidate:IsShown() then row = candidate break end
	end

	if not row then
		row = CreateRow(child, width, height)
		table.insert(pool, row)
	end

	row:SetSize(width, height)
	row:ClearAllPoints()
	row:Show()
	return row
end

local function ReleaseRows(child)
	for _, row in ipairs(rowPools[child] or {}) do row:Hide() end
end

local function RenderList(child, entries, width, normalHeight, headerHeight, onClick)
	ReleaseRows(child)
	local yOffset = -6

	for _, entry in ipairs(entries) do
		local height = entry.isHeader and headerHeight or normalHeight
		local row = AcquireRow(child, width, height)
		row:SetPoint("TOPLEFT", 0, yOffset)

		if entry.atlas then
			row.Icon:SetAtlas(entry.atlas)
		else
			row.Icon:SetTexture(entry.icon or "Interface\\Icons\\Trade_Tailoring")
		end

		row.Label:SetText(entry.text or "")
		row.RightLabel:SetText(entry.rightText or "")
		row.tooltipTitle = entry.text
		row.tooltipLines = entry.tooltipLines
		row.hyperlink = entry.hyperlink

		if entry.isHeader then
			row.Label:SetFontObject("GameFontNormal")
			row:SetBackdropColor(0, 0, 0, 0.45)
			row:EnableMouse(false)
		else
			row.Label:SetFontObject("GameFontHighlight")
			row:EnableMouse(onClick ~= nil)

			if onClick then
				row:SetScript("OnMouseUp", function() onClick(entry) end)
			else
				row:SetScript("OnMouseUp", nil)
			end
		end

		yOffset = yOffset - height - 6
	end

	if #entries == 0 then
		local empty = AcquireRow(child, width, 44)
		empty:SetPoint("TOPLEFT", 0, yOffset)
		empty.Icon:SetTexture("Interface\\Icons\\Trade_Tailoring")
		empty.Label:SetText("No entries saved yet.")
		empty.RightLabel:SetText("")
		empty.Label:SetFontObject("GameFontHighlight")
		empty:EnableMouse(false)
		empty.tooltipLines = nil
		empty.hyperlink = nil
		yOffset = yOffset - 50
	end

	child:SetHeight(math.max(1, -yOffset + 12))
end

local function SaveGeometry()
	local frame = Directory.frame
	if not frame then return end

	local point, _, _, x, y = frame:GetPoint()
	CraftRosterDB.settings.window = {
		point = point, x = x, y = y,
		width = frame:GetWidth(), height = frame:GetHeight(),
	}
end

function Directory:ResetWindow()
	local frame = self.frame
	if not frame then return end

	frame:ClearAllPoints()
	frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
	frame:SetSize(DEFAULT_WINDOW.width, DEFAULT_WINDOW.height)
	CraftRosterDB.settings.window = nil
	SaveGeometry()
end

local function RestoreGeometry(frame)
	local saved = CraftRosterDB.settings.window
	if saved then
		frame:ClearAllPoints()
		frame:SetPoint(saved.point or "CENTER", UIParent, "CENTER", saved.x or 0, saved.y or 0)
		frame:SetSize(
			math.max(MIN_WIDTH, saved.width or DEFAULT_WINDOW.width),
			math.max(MIN_HEIGHT, saved.height or DEFAULT_WINDOW.height)
		)
	else
		Directory:ResetWindow()
	end
end

function Directory:Initialize()
	if self.frame then return end

	if CraftRosterDB.settings.onlineOnly == nil then
		CraftRosterDB.settings.onlineOnly = true
	end

	local frame = CreateFrame("Frame", "CraftRosterDirectory", UIParent, "BasicFrameTemplateWithInset")
	frame:SetFrameStrata("HIGH")
	frame:SetMovable(true)
	frame:EnableMouse(true)
	frame:RegisterForDrag("LeftButton")
	frame:SetScript("OnDragStart", frame.StartMoving)
	frame:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		SaveGeometry()
	end)
	frame:SetScript("OnHide", SaveGeometry)
	frame:Hide()

	RestoreGeometry(frame)
	frame.TitleBar.TitleText:SetText("CraftRoster")

	local resize = CreateFrame("Frame", nil, frame)
	resize:SetSize(16, 16)
	resize:SetPoint("BOTTOMRIGHT", -4, 4)
	resize:EnableMouse(true)
	resize:RegisterForDrag("LeftButton")
	resize:SetScript("OnDragStart", function() frame:StartSizing("BOTTOMRIGHT") end)
	resize:SetScript("OnDragStop", function()
		frame:StopMovingOrSizing()
		frame:SetSize(math.max(MIN_WIDTH, frame:GetWidth()), math.max(MIN_HEIGHT, frame:GetHeight()))
		SaveGeometry()
		Directory:RefreshIfVisible()
	end)

	local resizeTexture = resize:CreateTexture(nil, "OVERLAY")
	resizeTexture:SetAllPoints()
	resizeTexture:SetTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")

	frame.TabButtons = {}
	for index, tabName in ipairs({ "Professions", "Players", "My Recipes" }) do
		local tab = CreateFrame("Button", nil, frame, "CharacterFrameTabButtonTemplate")
		tab:SetText(tabName)
		tab:SetID(index)
		tab:SetPoint("TOPLEFT", frame, "BOTTOMLEFT", 12 + (index - 1) * 125, 0)
		tab:SetScript("OnClick", function() Directory:ShowTab(index) end)
		frame.TabButtons[index] = tab
	end

	local function CreateTab(name)
		local tab = CreateFrame("Frame", nil, frame)
		tab:SetAllPoints(frame.Inset)
		frame[name] = tab
		return tab
	end

	local professionsTab = CreateTab("ProfessionsTab")
	professionsTab.SearchBox = CreateFrame("EditBox", nil, professionsTab, "SearchBoxTemplate")
	professionsTab.SearchBox:SetSize(210, 24)
	professionsTab.SearchBox:SetPoint("TOPLEFT", 18, -16)
	professionsTab.SearchBox:SetAutoFocus(false)
	professionsTab.SearchBox:SetScript("OnTextChanged", function() Directory:RefreshProfessions() end)

	professionsTab.SortButton = CreateFrame("Button", nil, professionsTab, "GameMenuButtonTemplate")
	professionsTab.SortButton:SetSize(140, 22)
	professionsTab.SortButton:SetPoint("TOPLEFT", 18, -48)
	professionsTab.SortButton:SetText(SORT_LABELS[sortMode])
	professionsTab.SortButton:SetScript("OnClick", function(self)
		local currentIndex = 1
		for i, mode in ipairs(SORT_MODES) do
			if mode == sortMode then currentIndex = i break end
		end
		sortMode = SORT_MODES[(currentIndex % #SORT_MODES) + 1]
		self:SetText(SORT_LABELS[sortMode])
		Directory:RefreshProfessions()
	end)

	professionsTab.Dropdown = CreateFrame("Frame", nil, professionsTab, "UIDropDownMenuTemplate")
	professionsTab.Dropdown:SetPoint("LEFT", professionsTab.SearchBox, "RIGHT", 4, -4)
	UIDropDownMenu_SetWidth(professionsTab.Dropdown, 150)
	UIDropDownMenu_Initialize(professionsTab.Dropdown, function(dropdown, level)
		local professions = { "All" }
		for profession in pairs(PROFESSION_ICONS) do table.insert(professions, profession) end
		table.sort(professions)

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
	UIDropDownMenu_SetText(professionsTab.Dropdown, "All")

	professionsTab.OnlineCheck = CreateFrame("CheckButton", nil, professionsTab, "UICheckButtonTemplate")
	professionsTab.OnlineCheck:SetPoint("LEFT", professionsTab.Dropdown, "RIGHT", 0, 0)
	professionsTab.OnlineCheck.Text:SetText("Online only")
	professionsTab.OnlineCheck:SetChecked(CraftRosterDB.settings.onlineOnly)
	professionsTab.OnlineCheck:SetScript("OnClick", function(button)
		CraftRosterDB.settings.onlineOnly = button:GetChecked()
		Directory:RefreshProfessions()
		Directory:RefreshCrafters()
	end)

	professionsTab.Results = CreateFrame("ScrollFrame", nil, professionsTab, "UIPanelScrollFrameTemplate")
	professionsTab.Results:SetPoint("TOPLEFT", 14, -76)
	professionsTab.Results:SetPoint("BOTTOMRIGHT", -400, 16)
	professionsTab.ResultsChild = CreateFrame("Frame", nil, professionsTab.Results)
	professionsTab.ResultsChild:SetSize(320, 1)
	professionsTab.Results:SetScrollChild(professionsTab.ResultsChild)

	professionsTab.Details = CreateFrame("Frame", nil, professionsTab)
	professionsTab.Details:SetPoint("TOPLEFT", 376, -76)
	professionsTab.Details:SetSize(360, 150)
	professionsTab.Details:SetBackdrop({
		bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
		edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
		edgeSize = 12,
	})
	professionsTab.Details:SetBackdropColor(0, 0, 0, 0.45)
	professionsTab.Details:SetBackdropBorderColor(0.8, 0.7, 0.4, 0.5)

	professionsTab.DetailsIcon = professionsTab.Details:CreateTexture(nil, "ARTWORK")
	professionsTab.DetailsIcon:SetSize(42, 42)
	professionsTab.DetailsIcon:SetPoint("TOPLEFT", 12, -12)

	professionsTab.DetailsName = professionsTab.Details:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
	professionsTab.DetailsName:SetPoint("TOPLEFT", professionsTab.DetailsIcon, "TOPRIGHT", 10, -2)
	professionsTab.DetailsName:SetJustifyH("LEFT")
	professionsTab.DetailsName:SetWidth(280)

	professionsTab.DetailsProfession = professionsTab.Details:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	professionsTab.DetailsProfession:SetPoint("TOPLEFT", professionsTab.DetailsIcon, "BOTTOMLEFT", 0, -10)

	professionsTab.CrafterList = CreateFrame("ScrollFrame", nil, professionsTab, "UIPanelScrollFrameTemplate")
	professionsTab.CrafterList:SetPoint("TOPLEFT", 376, -250)
	professionsTab.CrafterList:SetPoint("BOTTOMRIGHT", -18, -14)
	professionsTab.CrafterListChild = CreateFrame("Frame", nil, professionsTab.CrafterList)
	professionsTab.CrafterListChild:SetSize(350, 1)
	professionsTab.CrafterList:SetScrollChild(professionsTab.CrafterListChild)

	local playersTab = CreateTab("PlayersTab")
	playersTab.SearchBox = CreateFrame("EditBox", nil, playersTab, "SearchBoxTemplate")
	playersTab.SearchBox:SetSize(260, 24)
	playersTab.SearchBox:SetPoint("TOPLEFT", 18, -16)
	playersTab.SearchBox:SetAutoFocus(false)
	playersTab.SearchBox:SetScript("OnTextChanged", function() Directory:RefreshPlayers() end)

	playersTab.Results = CreateFrame("ScrollFrame", nil, playersTab, "UIPanelScrollFrameTemplate")
	playersTab.Results:SetPoint("TOPLEFT", 14, -50)
	playersTab.Results:SetPoint("BOTTOMRIGHT", -18, -14)
	playersTab.ResultsChild = CreateFrame("Frame", nil, playersTab.Results)
	playersTab.ResultsChild:SetSize(720, 1)
	playersTab.Results:SetScrollChild(playersTab.ResultsChild)

	local myRecipesTab = CreateTab("MyRecipesTab")
	myRecipesTab.Status = myRecipesTab:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
	myRecipesTab.Status:SetPoint("TOPLEFT", 18, -16)

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
	myRecipesTab.ResultsChild:SetSize(720, 1)
	myRecipesTab.Results:SetScrollChild(myRecipesTab.ResultsChild)

	frame:SetScript("OnKeyDown", function(_, key)
		if key == "ESCAPE" then frame:Hide() end
	end)
	frame:SetPropagateKeyboardInput(true)

	self.frame = frame
	self.selectedProfession = "All"
	self.selectedRecipe = nil
	self:ShowTab(1)
end

local function BuildProfessionEntries()
	local tab = Directory.frame.ProfessionsTab
	local search = (tab.SearchBox:GetText() or ""):lower()
	local searchTerms = GetSearchTerms(search)
	local matching = {}

	for _, recipe in ipairs(GetRecipeIndex()) do
		local professionOK = Directory.selectedProfession == "All" or recipe.profession == Directory.selectedProfession
		local searchOK = search == ""

		if not searchOK then
			local recipeName = recipe.name:lower()
			for _, term in ipairs(searchTerms) do
				if recipeName:find(term, 1, true) then
					searchOK = true
					break
				end
			end
		end

		if professionOK and searchOK then
			table.insert(matching, recipe)
		end
	end

	table.sort(matching, function(a, b)
		if sortMode == "crafters" then
			if #a.crafters ~= #b.crafters then return #a.crafters > #b.crafters end
			return a.name < b.name
		elseif sortMode == "profession" then
			if a.profession ~= b.profession then return a.profession < b.profession end
			return a.name < b.name
		end
		return a.name < b.name
	end)

	local entries = {}
	local lastProfession = nil

	for _, recipe in ipairs(matching) do
		if recipe.profession ~= lastProfession then
			table.insert(entries, {
				isHeader = true,
				text = recipe.profession,
				icon = GetProfessionIcon(recipe.profession),
			})
			lastProfession = recipe.profession
		end

		local saved = CraftRosterDB.recipes and CraftRosterDB.recipes[recipe.id]
		local tooltipLines = {}

		if saved and saved.materials and #saved.materials > 0 then
			for _, material in ipairs(saved.materials) do
				table.insert(tooltipLines, ("%dx %s"):format(material.count, material.name))
			end
		else
			table.insert(tooltipLines, "No material data saved yet.")
		end

		table.insert(entries, {
			id = recipe.id,
			text = recipe.name,
			icon = recipe.icon,
			rightText = ("%d crafter%s"):format(#recipe.crafters, #recipe.crafters == 1 and "" or "s"),
			tooltipLines = tooltipLines,
			hyperlink = saved and saved.itemLink,
			recipe = recipe,
		})
	end

	return entries
end

function Directory:RefreshProfessions()
	if not self.frame or not self.frame:IsShown() then return end
	local tab = self.frame.ProfessionsTab
	RenderList(tab.ResultsChild, BuildProfessionEntries(), 320, 34, 28, function(entry)
		Directory.selectedRecipe = entry.recipe
		Directory:RefreshDetails()
		Directory:RefreshCrafters()
	end)
end

function Directory:RefreshDetails()
	if not self.frame or not self.frame:IsShown() then return end
	local tab = self.frame.ProfessionsTab
	local recipe = self.selectedRecipe

	if recipe then
		tab.DetailsIcon:SetTexture(recipe.icon)
		tab.DetailsName:SetText(recipe.name)
		tab.DetailsProfession:SetText(recipe.profession)
	else
		tab.DetailsIcon:SetTexture("Interface\\Icons\\Trade_Tailoring")
		tab.DetailsName:SetText("Select a recipe")
		tab.DetailsProfession:SetText("")
	end
end

function Directory:RefreshCrafters()
	if not self.frame or not self.frame:IsShown() then return end
	local child = self.frame.ProfessionsTab.CrafterListChild
	local entries = {}

	if self.selectedRecipe then
		local onlineOnly = CraftRosterDB.settings.onlineOnly
		local online, offline = {}, {}

		for _, characterKey in ipairs(self.selectedRecipe.crafters) do
			local character = CraftRosterDB.characters[characterKey] or {}
			local entry = {
				text = GetColoredName(characterKey, character, not IsCharacterOnline(characterKey)),
				atlas = GetRaceGenderAtlas(character),
				icon = "Interface\\Icons\\Achievement_Character_Human_Male",
				offline = not IsCharacterOnline(characterKey),
			}

			if IsCharacterOnline(characterKey) then
				table.insert(online, entry)
			else
				table.insert(offline, entry)
			end
		end

		if onlineOnly then
			for _, entry in ipairs(online) do table.insert(entries, entry) end

			if #online == 0 then
				for _, entry in ipairs(offline) do table.insert(entries, entry) end
			end
		else
			for _, entry in ipairs(online) do table.insert(entries, entry) end
			for _, entry in ipairs(offline) do table.insert(entries, entry) end
		end
	end

	RenderList(child, entries, 350, 38, 28)
end

function Directory:RefreshPlayers()
	if not self.frame or not self.frame:IsShown() then return end
	local tab = self.frame.PlayersTab
	local search = (tab.SearchBox:GetText() or ""):lower()
	local entries = {}

	for characterKey, character in pairs(CraftRosterDB.characters or {}) do
		if search == "" or characterKey:lower():find(search, 1, true) then
			table.insert(entries, {
				text = GetColoredName(characterKey, character),
				atlas = GetRaceGenderAtlas(character),
				icon = "Interface\\Icons\\Achievement_Character_Human_Male",
				rightText = GetProfessionTotals(character),
			})
		end
	end

	RenderList(tab.ResultsChild, entries, 720, 42, 28)
end

function Directory:RefreshMyRecipes()
	if not self.frame or not self.frame:IsShown() then return end
	local tab = self.frame.MyRecipesTab
	local character = CraftRosterDB.characters[GetCharacterKey()]
	local entries = {}

	if character then
		for recipeID in pairs(character.recipes or {}) do
			local saved = CraftRosterDB.recipes[recipeID] or {}
			local profession = saved.profession or "Unknown"
			table.insert(entries, {
				text = GetRecipeName(recipeID),
				icon = saved.icon or GetProfessionIcon(profession),
			})
		end
	end

	RenderList(tab.ResultsChild, entries, 720, 36, 28)
	tab.Status:SetText(("Your saved recipes: %d"):format(#entries))
end

function Directory:RefreshIfVisible()
	if self.frame and self.frame:IsShown() then
		self:RefreshProfessions()
		self:RefreshPlayers()
		self:RefreshMyRecipes()
		self:RefreshDetails()
		self:RefreshCrafters()
	end
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
	if not self.frame then self:Initialize() end

	if self.frame:IsShown() then
		self.frame:Hide()
	else
		self:RefreshIfVisible()
		self:ShowTab(1)
		self.frame:Show()
	end
end

local rosterFrame = CreateFrame("Frame")
rosterFrame:RegisterEvent("GUILD_ROSTER_UPDATE")
rosterFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
rosterFrame:SetScript("OnEvent", function(_, event)
	if event == "PLAYER_ENTERING_WORLD" then
		if C_GuildInfo and C_GuildInfo.RequestGuildRoster then
			C_GuildInfo.RequestGuildRoster()
		elseif RequestGuildRoster then
			RequestGuildRoster()
		end
		return
	end

	wipe(onlineByName)

	local roster = C_GuildInfo and C_GuildInfo.GetGuildRoster and C_GuildInfo.GetGuildRoster()
	if roster then
		for _, member in ipairs(roster) do
			if member and member.name and member.online then
				onlineByName[member.name:lower()] = true
			end
		end
	elseif GetNumGuildMembers then
		for i = 1, GetNumGuildMembers() do
			local name, _, _, _, _, _, _, _, _, _, _, _, _, _, _, isOnline = GetGuildRosterInfo(i)
			if name and isOnline then
				onlineByName[name:lower()] = true
			end
		end
	end

	Directory:RefreshIfVisible()
end)
