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

function RecipeTracker:Initialize()
	self:RegisterEvent("NEW_RECIPE_LEARNED")
	self:RegisterEvent("PLAYER_ENTERING_WORLD")
	self:RegisterEvent("TRADE_SKILL_SHOW")
	self:SetScript("OnEvent", function(_, event, recipeID)
		if event == "NEW_RECIPE_LEARNED" then
			RecipeTracker:RecordRecipe(recipeID)
		elseif event == "TRADE_SKILL_SHOW" then
			RecipeTracker:UpdateProfessions()
			RecipeTracker:ImportEnchantingRecipes()
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

function RecipeTracker:ImportEnchantingRecipes()
	if GetTradeSkillLine() ~= "Enchanting" then return 0 end

	local character = GetCharacterData()
	local added = 0

	for i = 1, GetNumTradeSkills() do
		local name, skillType = GetTradeSkillInfo(i)
		if name and skillType ~= "header" then
			local link = GetTradeSkillRecipeLink(i)
			local recipeID = link and link:match("%d+")
			recipeID = recipeID and tonumber(recipeID)

			if recipeID and not character.recipes[recipeID] then
				character.recipes[recipeID] = { learnedAt = time() }

				CraftRosterDB.recipes[recipeID] = CraftRosterDB.recipes[recipeID] or {
					name = name,
					profession = "Enchanting",
					icon = PROFESSION_ICONS.Enchanting,
					firstSeenBy = GetCharacterKey(),
					firstSeenAt = time(),
				}

				added = added + 1
			end
		end
	end

	if added > 0 then
		CraftRosterDB.lastRecipeUpdate = time()
		if CraftRoster.Directory then
			CraftRoster.Directory:InvalidateIndex()
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
		icon = PROFESSION_ICONS[profession],
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
	added = added + self:ImportEnchantingRecipes()

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
