local ADDON_NAME, CraftRoster = ...

local RecipeTracker = {}
local scanTimer

local function DataChanged()
	if CraftRoster.ShoppingList then CraftRoster.ShoppingList:ScheduleRefresh() end
	if CraftRoster.Directory then CraftRoster.Directory:InvalidateIndex() end
	if CraftRoster.GuildSync then CraftRoster.GuildSync:InvalidateData() end
end
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
	if C_Spell and C_Spell.GetSpellInfo then
		local info = C_Spell.GetSpellInfo(recipeID)
		if info and info.iconID then return info.iconID end
	end
	if GetSpellInfo then
		local icon = select(3, GetSpellInfo(recipeID))
		if icon then return icon end
	end
	return PROFESSION_ICONS[profession]
end

local function GetCurrentProfession()
	if C_TradeSkillUI and C_TradeSkillUI.GetBaseProfessionInfo then
		local info = C_TradeSkillUI.GetBaseProfessionInfo()
		if info and info.professionName then return info.professionName end
	end
	if C_TradeSkillUI and C_TradeSkillUI.GetTradeSkillLine then
		local info = C_TradeSkillUI.GetTradeSkillLine()
		if type(info) == "table" and info.professionName then return info.professionName end
	end
	if GetTradeSkillLine then
		local name = GetTradeSkillLine()
		if name then return name end
	end
	return "Unknown"
end

local function ExtractMaterialsFromSchematic(schematic)
	if not schematic or not schematic.reagentSlotSchematics then return nil end
	local materials = {}
	for _, slot in ipairs(schematic.reagentSlotSchematics) do
		local quantity = slot.quantityRequired or slot.quantity or 0
		local reagent = (slot.reagents or {})[1]
		if slot.required ~= false and reagent and quantity > 0 then
			local itemID = reagent.itemID or (reagent.item and reagent.item.itemID)
			local name = reagent.name
			local getItemInfo = C_Item and C_Item.GetItemInfo or GetItemInfo
			if itemID and not name and getItemInfo then name = getItemInfo(itemID) end
			if not name then return nil end
			table.insert(materials, { name = name, count = quantity, itemID = itemID })
		end
	end
	return materials
end

local function SameMaterials(a, b)
	if not a or #a ~= #b then return false end
	for i, material in ipairs(b) do
		local old = a[i]
		if old.name ~= material.name or old.itemID ~= material.itemID or old.count ~= material.count then return false end
	end
	return true
end

local function SaveRecipe(character, recipeID, name, profession, icon, itemLink, materials)
	local isNew = not character.recipes[recipeID]
	local changed = isNew
	if isNew then
		character.recipes[recipeID] = { learnedAt = time() }
	end

	local saved = CraftRosterDB.recipes[recipeID]
	if not saved then
		changed = true
		saved = {
			name = name,
			profession = profession,
			icon = icon or GetRecipeIcon(recipeID, profession),
			firstSeenBy = GetCharacterKey(),
			firstSeenAt = time(),
		}
		CraftRosterDB.recipes[recipeID] = saved
	else
		if name and saved.name ~= name then saved.name = name; changed = true end
		if profession and profession ~= "Unknown" and saved.profession ~= profession then
			saved.profession = profession; changed = true
		end
		if icon and saved.icon ~= icon then saved.icon = icon; changed = true end
	end
	if itemLink and saved.itemLink ~= itemLink then saved.itemLink = itemLink; changed = true end
	if materials and not SameMaterials(saved.materials, materials) then
		saved.materials = materials; changed = true
	end

	return isNew, changed
end

function RecipeTracker:ScheduleScan()
	if scanTimer then return end
	local function Scan()
		scanTimer = nil
		if not CraftRosterDB.settings.enabled or not CraftRosterDB.settings.autoUpdateRecipes then return end
		RecipeTracker:UpdateProfessions()
		RecipeTracker:ImportTradeSkillRecipes()
	end
	if C_Timer and C_Timer.NewTimer then scanTimer = C_Timer.NewTimer(0.25, Scan) else Scan() end
end

function RecipeTracker:Initialize()
	if self.eventFrame then return end
	-- Dedicated event frame; RecipeTracker itself is a plain table.
	local frame = CreateFrame("Frame")
	self.eventFrame = frame
	frame:RegisterEvent("NEW_RECIPE_LEARNED")
	frame:RegisterEvent("PLAYER_ENTERING_WORLD")
	frame:RegisterEvent("TRADE_SKILL_SHOW")
	pcall(function() frame:RegisterEvent("TRADE_SKILL_LIST_UPDATE") end)
	pcall(function() frame:RegisterEvent("TRADE_SKILL_DATA_UPDATE") end)

	frame:SetScript("OnEvent", function(_, event, recipeID)
		if not CraftRosterDB.settings.enabled or not CraftRosterDB.settings.autoUpdateRecipes then return end
		if event == "NEW_RECIPE_LEARNED" then
			RecipeTracker:RecordRecipe(recipeID)
		elseif event == "TRADE_SKILL_SHOW"
			or event == "TRADE_SKILL_LIST_UPDATE"
			or event == "TRADE_SKILL_DATA_UPDATE" then
			RecipeTracker:ScheduleScan()
		else
			RecipeTracker:UpdateProfessions()
		end
	end)
end

function RecipeTracker:UpdateProfessions()
	local character = GetCharacterData()
	character.professions = character.professions or {}
	local changed = false

	local professionIDs = GetProfessions and { GetProfessions() } or {}
	for _, professionID in pairs(professionIDs) do
		if professionID and GetProfessionInfo then
			local name, icon, skill, max, _, _, _, rank = GetProfessionInfo(professionID)
			if name then
				local old = character.professions[name]
				if not old or old.skill ~= (skill or 0) or old.max ~= (max or 0) or old.rank ~= rank or old.icon ~= icon then
					changed = true
					character.professions[name] = {
						skill = skill or 0,
						max = max or 0,
						rank = rank,
						icon = icon,
					}
				end
			end
		end
	end

	CraftRosterDB.lastProfessionUpdate = time()

	if changed then DataChanged() end
end

local function ImportForeverRecipes(character, profession)
	local added, changed = 0, false
	local recipeIDs = C_TradeSkillUI.GetAllRecipeIDs and C_TradeSkillUI.GetAllRecipeIDs() or {}

	for _, recipeID in ipairs(recipeIDs) do
		local info = C_TradeSkillUI.GetRecipeInfo and C_TradeSkillUI.GetRecipeInfo(recipeID)
		if info and info.learned then
			local schematic = C_TradeSkillUI.GetRecipeSchematic
				and C_TradeSkillUI.GetRecipeSchematic(recipeID, false)
			local materials = ExtractMaterialsFromSchematic(schematic)
			local itemLink = schematic and schematic.outputItemLink or info.hyperlink

			local isNew, updated = SaveRecipe(
				character,
				recipeID,
				info.name or ("Recipe " .. recipeID),
				profession,
				info.icon or GetRecipeIcon(recipeID, profession),
				itemLink,
				materials
			)

			if isNew then added = added + 1 end
			if updated then changed = true end
		end
	end

	return added, changed
end

local function ImportLegacyRecipes(character, profession)
	local added, changed = 0, false

	for i = 1, GetNumTradeSkills() do
		local name, skillType = GetTradeSkillInfo(i)
		if name and skillType ~= "header" then
			local link = GetTradeSkillRecipeLink(i)
			local recipeID = link and (link:match("enchant:(%d+)") or link:match("spell:(%d+)"))
			recipeID = recipeID and tonumber(recipeID)

			if recipeID then
				local itemLink = GetTradeSkillItemLink and GetTradeSkillItemLink(i)
				local materials = GetTradeSkillNumReagents and GetTradeSkillReagentInfo and {} or nil
				local numReagents = GetTradeSkillNumReagents and GetTradeSkillReagentInfo and GetTradeSkillNumReagents(i) or 0
				for j = 1, numReagents do
					local reagentName, _, reagentCount = GetTradeSkillReagentInfo(i, j)
					if reagentName and reagentCount then
						table.insert(materials, { name = reagentName, count = reagentCount })
					end
				end

				local isNew, updated = SaveRecipe(
					character,
					recipeID,
					name,
					profession,
					GetRecipeIcon(recipeID, profession),
					itemLink,
					materials
				)

				if isNew then added = added + 1 end
				if updated then changed = true end
			end
		end
	end

	return added, changed
end

function RecipeTracker:ImportTradeSkillRecipes()
	if not CraftRosterDB.settings.enabled then return 0 end
	if C_TradeSkillUI then
		if C_TradeSkillUI.IsTradeSkillLinked and C_TradeSkillUI.IsTradeSkillLinked() then return 0 end
		if C_TradeSkillUI.IsTradeSkillGuild and C_TradeSkillUI.IsTradeSkillGuild() then return 0 end
	end
	if IsTradeSkillLinked and IsTradeSkillLinked() then return 0 end
	local profession = GetCurrentProfession()
	local character = GetCharacterData()
	local added, changed = 0, false

	if C_TradeSkillUI and C_TradeSkillUI.GetAllRecipeIDs and C_TradeSkillUI.GetRecipeInfo then
		added, changed = ImportForeverRecipes(character, profession)
	elseif GetNumTradeSkills and GetTradeSkillInfo and GetTradeSkillRecipeLink then
		added, changed = ImportLegacyRecipes(character, profession)
	else
		print("|cffff0000CraftRoster|r: no supported recipe enumeration API found; skipping import.")
	end

	if changed then
		CraftRosterDB.lastRecipeUpdate = time()
		DataChanged()
		if CraftRoster.GuildSync then CraftRoster.GuildSync:SendData() end
	end

	return added
end

function RecipeTracker:RecordRecipe(recipeID, profession, recipeName)
	if type(recipeID) ~= "number" or recipeID <= 0 then return false end

	local settings = CraftRosterDB.settings
	local character = GetCharacterData()

	if not settings.enabled or (not settings.autoUpdateRecipes and not self.manualUpdateInProgress) then return false end
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

	DataChanged()
	if CraftRoster.GuildSync then CraftRoster.GuildSync:SendData() end

	return true
end

function RecipeTracker:UpdateKnownRecipes()
	if scanTimer then scanTimer:Cancel(); scanTimer = nil end
	self.manualUpdateInProgress = true
	local ok, added = pcall(function()
		self:UpdateProfessions()
		return self:ImportTradeSkillRecipes()
	end)
	self.manualUpdateInProgress = nil
	if not ok then error(added) end
	return added
end

function RecipeTracker:GetKnownRecipeCount()
	local character = GetCharacterData()
	local count = 0
	for _ in pairs(character.recipes or {}) do count = count + 1 end
	return count
end
