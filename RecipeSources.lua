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


local professionIDs={Alchemy=171,Blacksmithing=164,Cooking=185,Enchanting=333,Engineering=202,["First Aid"]=129,Fishing=356,Leatherworking=165,Mining=186,Tailoring=197}
function Sources:GetOutputItemID(recipeID)
 local saved=CraftRosterDB.recipes and CraftRosterDB.recipes[recipeID]
 if not saved then return end
 local itemID=type(saved.itemLink)=="string" and tonumber(saved.itemLink:match("item:(%d+)"))
 return itemID or libraryCall("GetCraftedItemID",(saved.professionID or professionIDs[saved.profession]),recipeID)
end
function Sources:IsEnchant(recipeID)
 local saved=CraftRosterDB.recipes and CraftRosterDB.recipes[recipeID]
 return saved and libraryCall("GetEnchantId",(saved.professionID or professionIDs[saved.profession]),recipeID)~=nil or false
end
local function RawMaterials(self,recipeID)
 local saved=CraftRosterDB.recipes and CraftRosterDB.recipes[recipeID]
 if not saved then return nil end
 if type(saved.materials)=="table" and #saved.materials>0 then return saved.materials end
 if CraftRoster.GuildDetails then
  local peer=CraftRoster.GuildDetails:GetMaterials(recipeID)
  if peer then return peer end
 end
 local profID=(saved.professionID or professionIDs[saved.profession])
 if not profID then return nil end
 local reagents=libraryCall("GetReagents",profID,recipeID)
 if type(reagents)~="table" then return nil end
 local out={}
 for itemID,count in pairs(reagents) do
  if type(itemID)~="number" or type(count)~="number" or count<=0 then return nil end
  local name
  if GetItemInfo then local ok,n=pcall(GetItemInfo,itemID); if ok then name=n end end
  out[#out+1]={itemID=itemID,name=name or ("Item "..itemID),count=count}
 end
 table.sort(out,function(a,b) return a.itemID<b.itemID end)
 return #out>0 and out or nil
end
-- Resolve cached names for every consumer, including whisper and mail drafts.
function Sources:GetMaterials(recipeID)
 local raw=RawMaterials(self,recipeID)
 if not raw then return end
 local result={}
 for _,material in ipairs(raw) do
  local name,link,icon=CraftRoster.ItemDisplay:Resolve(material.itemID,material.name)
  result[#result+1]={itemID=material.itemID,name=name,count=material.count,link=link,icon=icon}
 end
 return result
end
function Sources:GetRecipeIcon(recipeID,fallback,cachedOnly)
 local saved=CraftRosterDB.recipes and CraftRosterDB.recipes[recipeID]
 local itemID=self:GetOutputItemID(recipeID)
 if not cachedOnly and itemID and CraftRoster.ItemDisplay then
  local _,_,icon=CraftRoster.ItemDisplay:Resolve(itemID)
  if icon then return icon end
 end
 if saved and saved.icon then return saved.icon end
 if C_Spell and C_Spell.GetSpellInfo then
  local ok,info=pcall(C_Spell.GetSpellInfo,recipeID)
  if ok and info and info.iconID then return info.iconID end
 end
 if GetSpellInfo then local ok,_,_,icon=pcall(GetSpellInfo,recipeID); if ok and icon then return icon end end
 return fallback
end

function Sources:SeedCatalog()
	local changed = false
	-- Import the bundled catalogue locally; never claim that a character knows it.
	if not self.catalogLoaded then
		local hits = libraryCall("Search", { max = 100000 })
		if type(hits) == "table" then
			local professions = { [171] = "Alchemy", [164] = "Blacksmithing",
				[185] = "Cooking", [333] = "Enchanting", [202] = "Engineering",
				[129] = "First Aid", [356] = "Fishing", [165] = "Leatherworking",
				[186] = "Mining", [197] = "Tailoring" }
			for _, hit in ipairs(hits) do
				if professions[hit.profId] and type(hit.name) == "string" and hit.name ~= "" then
					local saved = CraftRosterDB.recipes[hit.recipeId] or {}
					if saved.professionID~=hit.profId then saved.professionID=hit.profId; changed=true end
					if not saved.name then saved.name = hit.name; changed = true end
					if not saved.profession or saved.profession == "Unknown" then
						saved.profession = professions[hit.profId]; changed = true
					end
					if not saved.description then saved.description = hit.effect end
					CraftRosterDB.recipes[hit.recipeId] = saved
				end
			end
			self.catalogLoaded = true
		end
	end
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
	local itemID = saved.recipeItemID
	if not itemID and type(saved.recipeItemLink) == "string" then
		itemID = tonumber(saved.recipeItemLink:match("item:(%d+)"))
	end
	if not itemID then
		local mapped, rankBook = libraryCall("GetRecipeItem", recipeID)
		if not rankBook then itemID = mapped end
	end
	itemID = itemID or (reference and reference.itemID)
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
	local sources=libraryCall("GetRecipeSources",recipeID)
	data.hasLibrarySource=false
	if type(sources)=="table" then
		local labels={trainer="Trainer",vendor="Vendor",quest="Quest",container="Container",drop="Mob/boss drop"}
		if saved.sourceText then table.insert(lines,"\nAdditional database sources:") end
		for _,kind in ipairs({"trainer","vendor","quest","container","drop"}) do
			local list=sources[kind]
			if type(list)=="table" and #list>0 then
				data.hasLibrarySource=true
				local total=type(list.total)=="number" and math.max(#list,list.total) or #list
				table.insert(lines,labels[kind].." sources: "..total)
				for index,source in ipairs(list) do
					if index>12 then break end
					if type(source)=="table" then
						table.insert(lines,labels[kind]..": "..(type(source.name)=="string" and source.name or "Name unavailable"))
					end
				end
				if total>math.min(12,#list) then table.insert(lines,"and "..(total-math.min(12,#list)).." more (database examples are capped).") end
			end
		end
		if data.hasLibrarySource then
			local borrowed=libraryCall("IsBorrowed",recipeID,"sources")
			table.insert(lines,borrowed and (tostring(borrowed).." reference - Forever source unconfirmed.") or "LibProfessionDB source; verify in game.")
			table.insert(lines,"Source names are English. Provenance: bundled LibProfessionDB v1.9.1; emulator reference databases, not verified Forever loot rates.")
		end
	end
	if not data.hasLibrarySource and libraryCall("IsAutoTaughtRecipe",recipeID) then
		data.hasLibrarySource=true; table.insert(lines,"Learned with profession (database reference; verify in game).")
	end
	local skill=libraryCall("GetRequiredSkill",saved.professionID or professionIDs[saved.profession],recipeID)
	if type(skill)=="number" and skill>0 then
		local borrowed=libraryCall("IsBorrowed",recipeID,"requiredSkill")
		table.insert(lines,"Required skill: "..skill..(borrowed and (" ("..tostring(borrowed).." reference; unconfirmed)") or " (database reference)"))
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
