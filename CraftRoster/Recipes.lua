local ADDON_NAME, CraftRoster = ...

local RecipeTracker = {}
CraftRoster.RecipeTracker = RecipeTracker

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

local function GetCharacterKey()
	return UnitName("player") .. "-" .. (GetRealmName() or "")
end

local function GetCharacterData()
	local key = GetCharacterKey()
	CraftRosterDB.characters[key] = CraftRosterDB.characters[key] or { recipes = {} }
	return CraftRosterDB.characters[key]
end

local function GetRecipeIcon(recipeID, profession)
	if GetSpellInfo then
		local icon = select(3, GetSpellInfo(recipeID))
		if icon then return icon end
	end
	return PROFESSION_ICONS[profession]
end

local function GetCurrentProfession()
	if GetTradeSkillLine then
		local name = GetTradeSkillLine()
		if name then return name end
	end
	return "Unknown"
end

local function ExtractMaterialsFromSchematic(schematic)
	local materials = {}
	if not schematic or not schematic.reagentSlotSchematics then return materials end

	for _, slot in ipairs(schematic.reagentSlotSchematics) do
		local quantity = slot.quantityRequired or slot.quantity or 0
		local reagents = slot.reagents or {}

		for _, reagent in ipairs(reagents) do
			local itemID = reagent.itemID or (reagent.item and reagent.item.itemID)
			local name = reagent.name
			if itemID and not name and GetItemInfo then
				name = GetItemInfo(itemID)
			end
			if name and quantity and quantity > 0 then
				table.insert(materials, { name = name, count = quantity, itemID = itemID })
			end
		end
	end

	return materials
end

local function SaveRecipe(character, recipeID, name, profession, icon, itemLink, materials)
	local isNew = not character.recipes[recipeID]
	if isNew then
		character.recipes[recipeID] = { learnedAt = time() }
	end

	local saved = CraftRosterDB.recipes[recipeID]
	if not saved then
		saved = {
			name = name,
			profession = profession,
			icon = icon or GetRecipeIcon(recipeID, profession),
			firstSeenBy = GetCharacterKey(),
			firstSeenAt = time(),
		}
		CraftRosterDB.recipes[recipeID] = saved
	else
		-- Repair incomplete metadata when authoritative info arrives.
		if not saved.name and name then saved.name = name end
		if (not saved.profession or saved.profession == "Unknown") and profession and profession ~= "Unknown" then
			saved.profession = profession
		end
		if not saved.icon and icon then saved.icon = icon end
	end

	if itemLink then saved.itemLink = itemLink end
	-- Only overwrite materials when we actually got data (avoid wiping with empty).
	if materials and #materials > 0 then
		saved.materials = materials
	end

	return isNew
end

function RecipeTracker:Initialize()
	-- Dedicated event frame; RecipeTracker itself is a plain table.
	local frame = CreateFrame("Frame")
	frame:RegisterEvent("NEW_RECIPE_LEARNED")
	frame:RegisterEvent("PLAYER_ENTERING_WORLD")
	frame:RegisterEvent("TRADE_SKILL_SHOW")
	pcall(function() frame:RegisterEvent("TRADE_SKILL_LIST_UPDATE") end)
	pcall(function() frame:RegisterEvent("TRADE_SKILL_DATA_UPDATE") end)

	frame:SetScript("OnEvent", function(_, event, recipeID)
		if event == "NEW_RECIPE_LEARNED" then
			RecipeTracker:RecordRecipe(recipeID)
		elseif event == "TRADE_SKILL_SHOW"
			or event == "TRADE_SKILL_LIST_UPDATE"
			or event == "TRADE_SKILL_DATA_UPDATE" then
			RecipeTracker:UpdateProfessions()
			RecipeTracker:ImportTradeSkillRecipes()
		else
			RecipeTracker:UpdateProfessions()
		end
	end)
end

function RecipeTracker:UpdateProfessions()
	local character = GetCharacterData()
	character.professions = character.professions or {}

	for i = 1, GetNumProfessions() do
		local professionID = select(i, GetProfessions())
		if professionID then
			local name, icon, skill, max, _, _, _, rank = GetProfessionInfo(professionID)
			if name then
				character.professions[name] = {
					skill = skill or 0,
					max = max or 0,
					rank = rank,
					icon = icon,
				}
			end
		end
	end

	CraftRosterDB.lastProfessionUpdate = time()

	if CraftRoster.Directory then
		CraftRoster.Directory:InvalidateIndex()
	end
end

local function ImportForeverRecipes(character, profession)
	local added = 0
	local recipeIDs = C_TradeSkillUI.GetAllRecipeIDs and C_TradeSkillUI.GetAllRecipeIDs() or {}

	for _, recipeID in ipairs(recipeIDs) do
		local info = C_TradeSkillUI.GetRecipeInfo and C_TradeSkillUI.GetRecipeInfo(recipeID)
		if info and info.learned then
			local schematic = C_TradeSkillUI.GetRecipeSchematic
				and C_TradeSkillUI.GetRecipeSchematic(recipeID, false)
			local materials = ExtractMaterialsFromSchematic(schematic)
			local itemLink = schematic and schematic.outputItemLink or info.hyperlink

			local isNew = SaveRecipe(
				character,
				recipeID,
				info.name or ("Recipe " .. recipeID),
				profession,
				info.icon or GetRecipeIcon(recipeID, profession),
				itemLink,
				materials
			)

			if isNew then added = added + 1 end
		end
	end

	return added
end

local function ImportLegacyRecipes(character, profession)
	local added = 0

	for i = 1, GetNumTradeSkills() do
		local name, skillType = GetTradeSkillInfo(i)
		if name and skillType ~= "header" then
			local link = GetTradeSkillRecipeLink(i)
			local recipeID = link and link:match("%d+")
			recipeID = recipeID and tonumber(recipeID)

			if recipeID then
				local itemLink = GetTradeSkillItemLink and GetTradeSkillItemLink(i)
				local materials = {}
				local numReagents = GetTradeSkillNumReagents and GetTradeSkillNumReagents(i) or 0
				for j = 1, numReagents do
					local reagentName, _, _, reagentCount = GetTradeSkillReagentInfo(i, j)
					if reagentName and reagentCount then
						table.insert(materials, { name = reagentName, count = reagentCount })
					end
				end

				local isNew = SaveRecipe(
					character,
					recipeID,
					name,
					profession,
					GetRecipeIcon(recipeID, profession),
					itemLink,
					materials
				)

				if isNew then added = added + 1 end
			end
		end
	end

	return added
end

function RecipeTracker:ImportTradeSkillRecipes()
	local profession = GetCurrentProfession()
	local character = GetCharacterData()
	local added = 0

	if C_TradeSkillUI and C_TradeSkillUI.GetAllRecipeIDs and C_TradeSkillUI.GetRecipeInfo then
		added = ImportForeverRecipes(character, profession)
	elseif GetNumTradeSkills then
		added = ImportLegacyRecipes(character, profession)
	else
		print("|cffff0000CraftRoster|r: no supported recipe enumeration API found; skipping import.")
	end

	if added > 0 then
		CraftRosterDB.lastRecipeUpdate = time()
		if CraftRoster.Directory then
			CraftRoster.Directory:InvalidateIndex()
		end
		if CraftRoster.GuildSync then
			CraftRoster.GuildSync:SendData()
		end
	end

	return added
end

function RecipeTracker:RecordRecipe(recipeID, profession, recipeName)
	if not recipeID then return false end

	local settings = CraftRosterDB.settings
	local character = GetCharacterData()

	if not settings.autoUpdateRecipes and not self.manualUpdateInProgress then return false end
	if character.recipes[recipeID] then return false end

	character.recipes[recipeID] = { learnedAt = time() }
	profession = profession or "Unknown"

	CraftRosterDB.recipes[recipeID] = CraftRosterDB.recipes[recipeID] or {
		name = recipeName,
		profession = profession,
		icon = GetRecipeIcon(recipeID, profession),
		firstSeenBy = GetCharacterKey(),
		firstSeenAt = time(),
	}

	CraftRosterDB.lastRecipeUpdate = time()

	if CraftRoster.Directory then
		CraftRoster.Directory:InvalidateIndex()
	end

	return true
end

function RecipeTracker:UpdateKnownRecipes()
	self.manualUpdateInProgress = true
	local added = 0

	self:UpdateProfessions()
	added = added + self:ImportTradeSkillRecipes()

	self.manualUpdateInProgress = nil
	CraftRosterDB.lastRecipeUpdate = time()

	if CraftRoster.Directory then
		CraftRoster.Directory:InvalidateIndex()
	end

	return added
end

function RecipeTracker:GetKnownRecipeCount()
	local character = GetCharacterData()
	local count = 0
	for _ in pairs(character.recipes or {}) do count = count + 1 end
	return count
end
