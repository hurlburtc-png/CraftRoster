local ADDON_NAME, CraftRoster = ...
local Sources = {}
CraftRoster.RecipeSources = Sources

-- Spell IDs identify crafts; these separate item IDs identify the learnable
-- recipe scrolls. Never infer scroll binding from the crafted item's binding.
-- Source provenance and coverage are documented in docs/RECIPE_SOURCES.md.
local references = {
	[17635] = { name = "Flask of the Titans", profession = "Alchemy", itemID = 13519,
		itemName = "Recipe: Flask of the Titans", quality = 2, bindType = 0, skill = 300,
		kind = "Boss", npc = "General Drakkisath", zone = "Upper Blackrock Spire", chance = 4.60 },
	[20034] = { name = "Enchant Weapon - Crusader", profession = "Enchanting", itemID = 16252,
		itemName = "Formula: Enchant Weapon - Crusader", quality = 2, bindType = 0, skill = 300,
		kind = "Mob", npc = "Scarlet Spellbinder", zone = "Western Plaguelands", chance = 0.43 },
	[19054] = { name = "Red Dragonscale Breastplate", profession = "Leatherworking", itemID = 15730,
		itemName = "Pattern: Red Dragonscale Breastplate", quality = 3, bindType = 1, skill = 300,
		requirement = "Dragonscale Leatherworking",
		kind = "Boss", npc = "General Drakkisath", zone = "Upper Blackrock Spire", chance = 4.95 },
	[23081] = { name = "Hyper-Radiant Flame Reflector", profession = "Engineering", itemID = 18657,
		itemName = "Schematic: Hyper-Radiant Flame Reflector", quality = 2, bindType = 0, skill = 290,
		kind = "Boss", npc = "Solakar Flamewreath", zone = "Upper Blackrock Spire", chance = 8.08 },
}

local bindingNames = {
	[0] = "Does not bind (tradable)", [1] = "Binds when picked up",
	[2] = "Binds when equipped", [3] = "Binds when used", [4] = "Quest item",
}
local requested = {}

local function libraryCall(method, ...)
	if not LibStub then return end
	local ok, db = pcall(LibStub, "LibProfessionDB-1.0", true)
	if not ok or type(db) ~= "table" or type(db.IsReady) ~= "function" or type(db.GetGameVersion) ~= "function" then return end
	local readyOK, ready = pcall(db.IsReady, db)
	local versionOK, version = pcall(db.GetGameVersion, db)
	if not readyOK or not ready or not versionOK or version ~= "Forever" or type(db[method]) ~= "function" then return end
	local success, value, extra = pcall(db[method], db, ...)
	if success then return value, extra end
end

function Sources:SeedCatalog()
	local changed = false
	for id, reference in pairs(references) do
		local saved = CraftRosterDB.recipes[id]
		if not saved then
			CraftRosterDB.recipes[id] = { name = reference.name, profession = reference.profession }
			changed = true
		end
	end
	if changed and CraftRoster.GuildSync then CraftRoster.GuildSync:InvalidateData() end
end

function Sources:Get(recipeID)
	local saved = CraftRosterDB.recipes[recipeID] or {}
	local reference = references[recipeID]
	-- External curated entries may explicitly provide a teaching-item ID/link.
	local itemID = saved.recipeItemID or (reference and reference.itemID)
	if not itemID and type(saved.recipeItemLink) == "string" then
		itemID = tonumber(saved.recipeItemLink:match("item:(%d+)"))
	end
	if not itemID then
		local mapped, rankBook = libraryCall("GetRecipeItem", recipeID)
		if not rankBook then itemID = mapped end
	end
	if type(itemID) ~= "number" or itemID <= 0 or itemID ~= math.floor(itemID) then itemID = nil end
	local result = { itemID = itemID, reference = reference }
	if not itemID then return result end
	local getInfo = C_Item and C_Item.GetItemInfo or GetItemInfo
	if type(getInfo) == "function" then
		local ok, name, link, quality, _, _, _, _, _, _, icon, _, _, _, bindType = pcall(getInfo, itemID)
		if ok and type(name) == "string" and name ~= "" then
			result.name, result.link, result.quality, result.icon = name, link, quality, icon
			result.bindType = bindType
		end
	end
	if not result.name and not requested[itemID] and C_Item and type(C_Item.RequestLoadItemDataByID) == "function" then
		requested[itemID] = true
		pcall(C_Item.RequestLoadItemDataByID, itemID)
	end
	result.name = result.name or (reference and reference.itemName) or ("Recipe item " .. itemID)
	local colors = { [0] = "ff9d9d9d", [1] = "ffffffff", [2] = "ff1eff00", [3] = "ff0070dd", [4] = "ffa335ee", [5] = "ffff8000", [6] = "ffe6cc80", [7] = "ff00ccff" }
	local color = colors[result.quality or (reference and reference.quality)] or "ffffffff"
	result.link = result.link or ("|c" .. color .. "|Hitem:" .. itemID .. "|h[" .. result.name .. "]|h|r")
	result.label = result.link
	result.binding = bindingNames[result.bindType]
	if not result.binding and result.bindType ~= nil then result.binding = "Unknown binding (check item tooltip)" end
	if not result.binding and reference and bindingNames[reference.bindType] then
		result.binding = bindingNames[reference.bindType] .. " (Classic reference; verify in game)"
	end
	result.binding = result.binding or "Unknown (item data not loaded)"
	return result
end

function Sources:Format(recipeID, data)
	data = data or self:Get(recipeID)
	local saved = CraftRosterDB.recipes[recipeID] or {}
	local reference = data.reference
	local lines = { "|cffffd100Where to get it|r" }
	if saved.sourceText then
		table.insert(lines, saved.sourceText)
	end
	if not saved.sourceText then
		local sources = libraryCall("GetRecipeSources", recipeID)
		if type(sources) == "table" then
			local labels = { trainer = "Trainer", vendor = "Vendor", quest = "Quest", container = "Container", drop = "Mob/boss drop" }
			local added = false
			for _, kind in ipairs({ "trainer", "vendor", "quest", "container", "drop" }) do
				if type(sources[kind]) == "table" then
					for _, source in ipairs(sources[kind]) do
						if type(source) == "table" and type(source.name) == "string" then
							table.insert(lines, labels[kind] .. ": " .. source.name)
							added = true
						end
					end
				end
			end
			if added then
				local borrowed = libraryCall("IsBorrowed", recipeID, "sources")
				table.insert(lines, borrowed and (tostring(borrowed) .. " reference - Forever source unconfirmed.") or "LibProfessionDB source; verify in game.")
			else sources = nil end
			data.hasLibrarySource = sources ~= nil
		end
	end
	if reference then
		if saved.sourceText then table.insert(lines, "\nAdditional Classic reference:") end
		table.insert(lines, reference.kind .. " drop: " .. reference.npc)
		table.insert(lines, "Location: " .. reference.zone)
		table.insert(lines, ("Estimated drop chance: ~%.2f%% per kill"):format(reference.chance))
		table.insert(lines, "Classic estimate - Forever source/rate unconfirmed.")
	elseif not saved.sourceText and not data.hasLibrarySource then
		table.insert(lines, "Source unknown: no acquisition details available.")
	end
	if not reference then table.insert(lines, "Drop chance: unknown (no verified estimate)") end
	table.insert(lines, "\n|cffffd100Recipe item binding|r")
	table.insert(lines, data.binding or "Unknown: learnable recipe item not mapped.")
	if reference then
		table.insert(lines, ("Requires %s (%d) (Classic reference)"):format(reference.profession, reference.skill))
		if reference.requirement then table.insert(lines, "Requires " .. reference.requirement) end
	end
	if saved.description then table.insert(lines, "\n" .. saved.description) end
	return table.concat(lines, "\n")
end

local frame = CreateFrame("Frame")
pcall(frame.RegisterEvent, frame, "GET_ITEM_INFO_RECEIVED")
frame:SetScript("OnEvent", function(_, _, itemID, success)
	if not success then return end
	requested[itemID] = nil
	local directory = CraftRoster.Directory
	if not directory or not directory.frame or not directory.frame:IsShown() or not directory.selectedRecipe then return end
	local expected = Sources:Get(directory.selectedRecipe.id).itemID
	if expected == itemID then directory:RefreshRecipeSource() end
end)
