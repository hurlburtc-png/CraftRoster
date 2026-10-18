local ADDON_NAME, CraftRoster = ...

local Directory = {}
CraftRoster.Directory = Directory

local DEFAULT_WINDOW = { width = 760, height = 500, x = 0, y = 0 }
local MIN_WIDTH, MIN_HEIGHT = 620, 420

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

local function DebouncedRefresh(method)
	local timer
	return function()
		if timer then timer:Cancel(); timer = nil end
		if C_Timer and C_Timer.NewTimer then
			timer = C_Timer.NewTimer(0.25, function()
				timer = nil
				Directory[method](Directory)
			end)
		else
			Directory[method](Directory)
		end
	end
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

local function NormalizeCharacter(name)
	if not name:find("-", 1, true) then name = name .. "-" .. (GetRealmName() or "") end
	return (name:lower():gsub("%s", ""))
end

local function IsCharacterOnline(characterKey)
	local key = NormalizeCharacter(characterKey)
	return key == NormalizeCharacter(GetCharacterKey()) or onlineByName[key] == true
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
	self.professionCache = nil
	if not self.frame or not self.frame:IsShown() then return end
	if C_Timer and C_Timer.NewTimer then
		if self.refreshTimer then return end
		self.refreshTimer = C_Timer.NewTimer(0.05, function()
			self.refreshTimer = nil
			self:RefreshIfVisible()
		end)
	else self:RefreshIfVisible() end
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
					searchName = (saved.name or GetRecipeName(recipeID)):lower(),
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

	return recipes
end

local function GetRecipeIndex()
	if not Directory.recipeIndex then
		Directory.recipeIndex = BuildRecipeIndex()
	end
	return Directory.recipeIndex
end

local function CreateRow(child, width, height)
	local row = CreateFrame("Frame", nil, child, BackdropTemplateMixin and "BackdropTemplate" or nil)
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
	row.Label:SetJustifyH("LEFT"); row.Label:SetWordWrap(false)

	row.RightLabel = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	row.RightLabel:SetPoint("RIGHT", -10, 0)

	row:SetScript("OnEnter", function(self)
		self:SetBackdropColor(0.16, 0.16, 0.16, 0.65)
		self:SetBackdropBorderColor(0.9, 0.8, 0.5, 0.75)

		if self.hyperlink then
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			GameTooltip:SetHyperlink(self.hyperlink)
			GameTooltip:Show()
		elseif self.tooltipLines or self.materials then
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			GameTooltip:SetText(self.tooltipTitle or "")
			for _, line in ipairs(self.tooltipLines or {}) do
				GameTooltip:AddLine(line, 1, 1, 1)
			end
			for _, material in ipairs(self.materials or {}) do
				GameTooltip:AddLine(("%dx %s"):format(material.count or 0, material.name or "Unknown"), 1, 1, 1)
			end
			GameTooltip:Show()
		end
	end)

	row:SetScript("OnLeave", function(self)
		self:SetBackdropColor(0, 0, 0, 0.30)
		self:SetBackdropBorderColor(0.8, 0.7, 0.4, 0.25)
		GameTooltip:Hide()
	end)

	row:SetScript("OnMouseUp", function(self, button)
		if self.listClick and self.listEntry and (not button or button == "LeftButton") then self.listClick(self.listEntry) end
	end)

	return row
end

local function RenderList(child, entries, width, normalHeight, headerHeight, onClick)
	width = math.max(80, child:GetParent():GetWidth() - 4)
	local pool = rowPools[child]
	if not pool then pool = {}; rowPools[child] = pool end
	local offsets, y = {}, 6
	for i, entry in ipairs(entries) do
		offsets[i] = y
		y = y + (entry.isHeader and headerHeight or normalHeight) + 6
	end
	child:SetHeight(math.max(56, y + 12))
	local scroll = child:GetParent()
	local function Draw()
		width = math.max(80, scroll:GetWidth() - 4)
		local top = scroll.GetVerticalScroll and scroll:GetVerticalScroll() or 0
		local maximum = math.max(0, y + 12 - math.max(1, scroll:GetHeight()))
		if top > maximum then top = maximum; scroll:SetVerticalScroll(top) end
		local bottom = top + math.max(1, scroll:GetHeight()) + normalHeight
		-- Binary search avoids walking thousands of offscreen entries on each scroll.
		local low, high = 1, #entries
		while low <= high do
			local mid = math.floor((low + high) / 2)
			if offsets[mid] < top - normalHeight - 6 then low = mid + 1 else high = mid - 1 end
		end
		local used = 0
		local function Row()
			used = used + 1
			local row = pool[used]
			if not row then row = CreateRow(child, width, normalHeight); pool[used] = row end
			row:ClearAllPoints()
			row.listClick, row.listEntry = nil, nil
			row.materials, row.tooltipLines, row.hyperlink = nil, nil, nil
			row:SetBackdropColor(0, 0, 0, 0.30)
			row:SetBackdropBorderColor(0.8, 0.7, 0.4, 0.25)
			row:Show()
			return row
		end
		for i = low, #entries do
			if offsets[i] > bottom or used >= 128 then break end
			local entry = entries[i]
			local row = Row()
			row:SetSize(width, entry.isHeader and headerHeight or normalHeight)
			row:SetPoint("TOPLEFT", 0, -offsets[i])
			if entry.atlas and row.Icon.SetAtlas then row.Icon:SetAtlas(entry.atlas)
			else row.Icon:SetTexture(entry.icon or "Interface\\Icons\\Trade_Tailoring") end
			row.Label:SetWidth(math.max(40, width - 140))
			row.Label:SetText(entry.text or "")
			row.RightLabel:SetText(entry.rightText or "")
			row.Label:SetFontObject(entry.isHeader and "GameFontNormal" or "GameFontHighlight")
			row.tooltipTitle, row.tooltipLines = entry.tooltipTitle or entry.text, entry.tooltipLines
			row.materials, row.hyperlink = entry.materials, entry.hyperlink
			row:EnableMouse(not entry.isHeader and (onClick ~= nil or row.tooltipLines ~= nil or row.materials ~= nil or row.hyperlink ~= nil))
			if onClick and not entry.isHeader then
				row.listClick, row.listEntry = onClick, entry
			end
		end
		if #entries == 0 then
			local row = Row()
			row:SetSize(width, 44); row:SetPoint("TOPLEFT", 0, -6)
			row.Icon:SetTexture("Interface\\Icons\\Trade_Tailoring")
			row.Label:SetText("No matching entries."); row.RightLabel:SetText("")
			row:EnableMouse(false)
		end
		for i = used + 1, #pool do pool[i]:Hide() end
	end
	child.drawRows = Draw
	if not child.scrollHooked and scroll.HookScript then
		scroll:HookScript("OnVerticalScroll", function() child.drawRows() end)
		scroll:HookScript("OnSizeChanged", function() child.drawRows() end)
		child.scrollHooked = true
	end
	Draw()
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
	if not frame then CraftRosterDB.settings.window = nil; return end

	frame:ClearAllPoints()
	frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
	frame:SetSize(DEFAULT_WINDOW.width, DEFAULT_WINDOW.height)
	CraftRosterDB.settings.window = nil
	SaveGeometry()
	self:RefreshIfVisible()
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
	for _, mode in ipairs(SORT_MODES) do if CraftRosterDB.settings.sortMode == mode then sortMode = mode end end

	if CraftRosterDB.settings.onlineOnly == nil then
		CraftRosterDB.settings.onlineOnly = true
	end

	local frame = CreateFrame("Frame", "CraftRosterDirectory", UIParent, "BasicFrameTemplateWithInset")
	frame:SetFrameStrata("HIGH")
	frame:SetMovable(true)
	frame:SetResizable(true)
	frame:EnableMouse(true)
	frame:RegisterForDrag("LeftButton")
	frame:SetScript("OnDragStart", frame.StartMoving)
	frame:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		SaveGeometry()
	end)
	frame:SetScript("OnHide", function()
		SaveGeometry()
		if Directory.refreshTimer then Directory.refreshTimer:Cancel(); Directory.refreshTimer = nil end
	end)
	frame:Hide()

	self.frame = frame
	RestoreGeometry(frame)
	local title = frame.TitleText or frame.TitleBar.TitleText
	title:SetText("CraftRoster")

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
	professionsTab.SearchBox:HookScript("OnTextChanged", DebouncedRefresh("RefreshProfessions"))

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
		CraftRosterDB.settings.sortMode = sortMode
		self:SetText(SORT_LABELS[sortMode])
		Directory:RefreshProfessions()
	end)

	professionsTab.FavoritesCheck = CreateFrame("CheckButton", nil, professionsTab, "UICheckButtonTemplate")
	professionsTab.FavoritesCheck:SetPoint("TOPLEFT", 270, -44)
	professionsTab.FavoritesCheck.Text:SetText("Favorites only")
	professionsTab.FavoritesCheck:SetChecked(CraftRosterDB.settings.favoritesOnly == true)
	professionsTab.FavoritesCheck:SetScript("OnClick", function(button)
		CraftRosterDB.settings.favoritesOnly = button:GetChecked() and true or false
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
	professionsTab.Results:SetPoint("BOTTOMRIGHT", professionsTab, "BOTTOM", -12, 16)
	professionsTab.ResultsChild = CreateFrame("Frame", nil, professionsTab.Results)
	professionsTab.ResultsChild:SetSize(320, 1)
	professionsTab.Results:SetScrollChild(professionsTab.ResultsChild)

	professionsTab.Details = CreateFrame("Frame", nil, professionsTab, BackdropTemplateMixin and "BackdropTemplate" or nil)
	professionsTab.Details:SetPoint("TOPLEFT", professionsTab, "TOP", 12, -76)
	professionsTab.Details:SetPoint("TOPRIGHT", -14, -76)
	professionsTab.Details:SetHeight(170)
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
	professionsTab.DetailsName:SetWidth(math.max(100, professionsTab.Details:GetWidth() - 78))
	professionsTab.Details:HookScript("OnSizeChanged", function(self)
		professionsTab.DetailsName:SetWidth(math.max(100, self:GetWidth() - 78))
	end)

	professionsTab.DetailsProfession = professionsTab.Details:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	professionsTab.DetailsProfession:SetPoint("TOPLEFT", professionsTab.DetailsIcon, "BOTTOMLEFT", 0, -10)

	professionsTab.CrafterList = CreateFrame("ScrollFrame", nil, professionsTab, "UIPanelScrollFrameTemplate")
	professionsTab.CrafterList:SetPoint("TOPLEFT", professionsTab, "TOP", 12, -270)
	professionsTab.CrafterList:SetPoint("BOTTOMRIGHT", -18, -14)
	professionsTab.CrafterListChild = CreateFrame("Frame", nil, professionsTab.CrafterList)
	professionsTab.CrafterListChild:SetSize(350, 1)
	professionsTab.CrafterList:SetScrollChild(professionsTab.CrafterListChild)

	local playersTab = CreateTab("PlayersTab")
	playersTab.SearchBox = CreateFrame("EditBox", nil, playersTab, "SearchBoxTemplate")
	playersTab.SearchBox:SetSize(260, 24)
	playersTab.SearchBox:SetPoint("TOPLEFT", 18, -16)
	playersTab.SearchBox:SetAutoFocus(false)
	playersTab.SearchBox:HookScript("OnTextChanged", DebouncedRefresh("RefreshPlayers"))

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
	if frame.SetPropagateKeyboardInput then frame:SetPropagateKeyboardInput(true) end

	self.frame = frame
	self.selectedProfession = "All"
	self.selectedRecipe = nil
end

local function BuildProfessionEntries()
	local tab = Directory.frame.ProfessionsTab
	local search = (tab.SearchBox:GetText() or ""):lower()
	local cacheKey = search .. "\001" .. (Directory.selectedProfession or "All") .. "\001" .. sortMode
		.. tostring(CraftRosterDB.settings.favoritesOnly)
	if Directory.professionCache and Directory.professionCache.key == cacheKey then return Directory.professionCache.entries end
	local searchTerms = GetSearchTerms(search)
	local matching = {}

	for _, recipe in ipairs(GetRecipeIndex()) do
		local professionOK = Directory.selectedProfession == "All" or recipe.profession == Directory.selectedProfession
		local searchOK = search == ""

		if not searchOK then
			local recipeName = recipe.searchName
			for _, term in ipairs(searchTerms) do
				if recipeName:find(term, 1, true) then
					searchOK = true
					break
				end
			end
		end

		if professionOK and searchOK and (not CraftRosterDB.settings.favoritesOnly or (CraftRosterDB.favorites or {})[recipe.id]) then
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
		if sortMode == "profession" and recipe.profession ~= lastProfession then
			table.insert(entries, {
				isHeader = true,
				text = recipe.profession,
				icon = GetProfessionIcon(recipe.profession),
			})
			lastProfession = recipe.profession
		end

		local saved = CraftRosterDB.recipes and CraftRosterDB.recipes[recipe.id]
		table.insert(entries, {
			id = recipe.id,
			text = recipe.name,
			icon = recipe.icon,
			rightText = ("%d crafter%s"):format(#recipe.crafters, #recipe.crafters == 1 and "" or "s"),
			materials = saved and saved.materials,
			hyperlink = saved and saved.itemLink,
			recipe = recipe,
		})
	end

	Directory.professionCache = { key = cacheKey, entries = entries }
	return entries
end

function Directory:RefreshProfessions()
	if not self.frame or not self.frame:IsShown() then return end
	local tab = self.frame.ProfessionsTab
	local entries = BuildProfessionEntries()
	local selected
	for _, entry in ipairs(entries) do
		if self.selectedRecipe and entry.id == self.selectedRecipe.id then selected = entry.recipe end
	end
	self.selectedRecipe = selected
	self:RefreshDetails()
	self:RefreshCrafters()
	RenderList(tab.ResultsChild, entries, 320, 34, 28, function(entry)
		Directory.selectedRecipe = entry.recipe
		Directory.selectedCrafter = nil
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
	local selectedValid = false
	for _, key in ipairs(self.selectedRecipe and self.selectedRecipe.crafters or {}) do
		if key == self.selectedCrafter then selectedValid = true end
	end
	if not selectedValid then self.selectedCrafter = nil end

	if self.selectedRecipe then
		local onlineOnly = CraftRosterDB.settings.onlineOnly
		local online, offline = {}, {}

		for _, characterKey in ipairs(self.selectedRecipe.crafters) do
			local character = CraftRosterDB.characters[characterKey] or {}
			local isOnline = IsCharacterOnline(characterKey)
			local entry = {
				text = GetColoredName(characterKey, character, not isOnline),
				atlas = GetRaceGenderAtlas(character),
				icon = "Interface\\Icons\\Achievement_Character_Human_Male",
				offline = not isOnline,
				characterKey = characterKey,
				tooltipLines = { characterKey, "Select for Whisper Player or Mail Player." },
				rightText = self.selectedCrafter == characterKey and "Selected" or "",
			}

			if isOnline then
				table.insert(online, entry)
			else
				table.insert(offline, entry)
			end
		end

		table.sort(online, function(a, b) return a.characterKey < b.characterKey end)
		table.sort(offline, function(a, b) return a.characterKey < b.characterKey end)
		if onlineOnly then
			for _, entry in ipairs(online) do table.insert(entries, entry) end


		else
			for _, entry in ipairs(online) do table.insert(entries, entry) end
			for _, entry in ipairs(offline) do table.insert(entries, entry) end
		end
	end

	RenderList(child, entries, 350, 38, 28, function(entry)
		if Directory.selectedRecipe and CraftRoster.Requests then
			Directory.selectedCrafter = entry.characterKey
			Directory:RefreshCrafters()
		end
	end)
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
				key = characterKey,
				atlas = GetRaceGenderAtlas(character),
				icon = "Interface\\Icons\\Achievement_Character_Human_Male",
				rightText = GetProfessionTotals(character),
			})
		end
	end

	table.sort(entries, function(a, b) return a.key < b.key end)
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

	table.sort(entries, function(a, b) return a.text < b.text end)
	RenderList(tab.ResultsChild, entries, 720, 36, 28)
	tab.Status:SetText(("Your saved recipes: %d"):format(#entries))
end

function Directory:RefreshIfVisible()
	if not self.frame or not self.frame:IsShown() then return end
	if self.activeTab == 2 then self:RefreshPlayers()
	elseif self.activeTab == 3 then self:RefreshMyRecipes()
	else self:RefreshProfessions() end
end

function Directory:ShowTab(index)
	self.activeTab = index
	self.frame.ProfessionsTab:Hide()
	self.frame.PlayersTab:Hide()
	self.frame.MyRecipesTab:Hide()

	for _, tab in ipairs(self.frame.TabButtons) do
		if PanelTemplates_SelectTab and PanelTemplates_DeselectTab then
			if index == tab:GetID() then PanelTemplates_SelectTab(tab) else PanelTemplates_DeselectTab(tab) end
		elseif PanelTemplates_SetTabState then
			PanelTemplates_SetTabState(self.frame, tab, index == tab:GetID() and "SELECTED" or "NORMAL")
		end
	end

	if index == 1 then
		self.frame.ProfessionsTab:Show()
		self:RefreshProfessions()
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
		self.frame:Show()
		self:ShowTab(self.activeTab or 1)
	end
end

local rosterFrame = CreateFrame("Frame")
rosterFrame:RegisterEvent("GUILD_ROSTER_UPDATE")
rosterFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
rosterFrame:SetScript("OnEvent", function(_, event)
	if event == "PLAYER_ENTERING_WORLD" then
		if C_GuildInfo and C_GuildInfo.GuildRoster then
			C_GuildInfo.GuildRoster()
		elseif C_GuildInfo and C_GuildInfo.RequestGuildRoster then
			C_GuildInfo.RequestGuildRoster()
		elseif RequestGuildRoster then
			RequestGuildRoster()
		end
		return
	end

	wipe(onlineByName)

	if C_GuildInfo and C_GuildInfo.GetGuildRoster then
		local roster = C_GuildInfo.GetGuildRoster()
		if roster then
			for _, member in ipairs(roster) do
				if member and member.name and member.online then
					onlineByName[NormalizeCharacter(member.name)] = true
				end
			end
		end
	elseif GetNumGuildMembers and GetGuildRosterInfo then
		for i = 1, GetNumGuildMembers() do
			local name, _, _, _, _, _, _, _, isOnline = GetGuildRosterInfo(i)
			if name and isOnline then
				onlineByName[NormalizeCharacter(name)] = true
			end
		end
	end

	if Directory.activeTab == 1 then Directory:RefreshCrafters() end
end)
