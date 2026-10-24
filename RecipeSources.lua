local ADDON_NAME, CraftRoster = ...
local Sources = {}
CraftRoster.RecipeSources = Sources

-- Spell IDs identify crafts; these separate item IDs identify the learnable
-- recipe scrolls. Never infer scroll binding from the crafted item's binding.
-- Source provenance and coverage are documented in docs/RECIPE_SOURCES.md.
local references = {
	[17635] = { name = "Flask of the Titans", profession = "Alchemy", itemID = 13519,
		itemName = "Recipe: Flask of the Titans", quality = 2, bindType = 0, skill = 300,
	},
	[20034] = { name = "Enchant Weapon - Crusader", profession = "Enchanting", itemID = 16252,
		itemName = "Formula: Enchant Weapon - Crusader", quality = 2, bindType = 0, skill = 300,
	},
	[19054] = { name = "Red Dragonscale Breastplate", profession = "Leatherworking", itemID = 15730,
		itemName = "Pattern: Red Dragonscale Breastplate", quality = 3, bindType = 1, skill = 300,
		requirement = "Dragonscale Leatherworking",
	},
	[23081] = { name = "Hyper-Radiant Flame Reflector", profession = "Engineering", itemID = 18657,
		itemName = "Schematic: Hyper-Radiant Flame Reflector", quality = 2, bindType = 0, skill = 290,
	},
}

local bindingNames = {
	[0] = "Does not bind (tradable)", [1] = "Binds when picked up",
	[2] = "Binds when equipped", [3] = "Binds when used", [4] = "Quest item",
}
-- Acquisition additions absent from the pinned ProfessionDB source payload.
-- Checked against ATT's Forever data; exact upstream revision is in docs/RECIPE_SOURCES.md.
local granny={vendor="Granny Finespindle",zone="Ironforge",coordinates="39.3, 33.7",faction="Alliance"}
local acquisitionReferences = {[1255143]=granny}
local grannyPatterns = {[252761]=true,[252762]=true,[252832]=true,[252764]=true,[252763]=true,
	[252826]=true,[252830]=true,[252831]=true,[252827]=true,[252828]=true,[252829]=true}
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
 local itemID=not cachedOnly and self:GetOutputItemID(recipeID)
 if itemID and CraftRoster.ItemDisplay then
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

function Sources:NormalizeRecipeKeys()
 local function normalize(rows)
  if type(rows)~="table" then return end
  local changes={}
  for key,value in pairs(rows) do
   local id=type(key)=="string" and tonumber(key)
   if id and id>0 and id==math.floor(id) then changes[#changes+1]={key,id,value} end
  end
  for _,change in ipairs(changes) do
   local old,id,value=change[1],change[2],change[3]
   if rows[id]==nil then rows[id]=value
   elseif type(rows[id])=="table" and type(value)=="table" then
    for field,detail in pairs(value) do if rows[id][field]==nil then rows[id][field]=detail end end
   end
   rows[old]=nil
  end
 end
 normalize(CraftRosterDB.recipes)
 for _,character in pairs(CraftRosterDB.characters or {}) do normalize(character.recipes) end
end

function Sources:SeedCatalog()
 self:NormalizeRecipeKeys()
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
	if reference and itemID~=reference.itemID then reference=nil end
	local result = { itemID = itemID, reference = reference }
	if not itemID then return result end
	-- A hybrid client may expose C_Item before its cache is populated. Use
	-- legacy item metadata for the same ID if modern data is incomplete.
	local modern = C_Item and C_Item.GetItemInfo
	local function readInfo(fn)
		if type(fn)~="function" then return end
		local ok, name, link, quality, _, _, _, _, _, _, icon, _, _, _, bindType = pcall(fn,itemID)
		if ok and type(name)=="string" and name~="" then
			result.name=result.name or name
			result.link=result.link or link
			if result.quality==nil then result.quality=quality end
			result.icon=result.icon or icon
			if result.bindType==nil then result.bindType=bindType end
		end
	end
	readInfo(modern)
	if (not result.name or not result.icon) and GetItemInfo~=modern then readInfo(GetItemInfo) end
	if not result.name and not requested[itemID] and C_Item and type(C_Item.RequestLoadItemDataByID) == "function" then
		local ok,accepted=pcall(C_Item.RequestLoadItemDataByID,itemID)
		-- A rejected/throwing async request must remain retryable.
		if ok and accepted~=false then requested[itemID]=true end
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

function Sources:Format(recipeID, data, compact)
	data = data or self:Get(recipeID)
	local saved = CraftRosterDB.recipes[recipeID] or {}
	local reference = data.reference
	local acquisition=acquisitionReferences[recipeID] or (grannyPatterns[data.itemID] and granny)
	local lines = { "|cffffd100Where to get it|r" }
 local locations=CraftRoster.RecipeLocations and CraftRoster.RecipeLocations:Get(recipeID) or {}
 local hasConfirmed=false
 for _,location in ipairs(locations) do if location.confirmed then hasConfirmed=true end end
 local fallback=CraftRoster.ClassicSources and CraftRoster.ClassicSources:Format(recipeID,data.itemID,locations,compact)
 -- Exact Classic references are the default when no confirmed Forever record
 -- exists. Do not bury usable locations below older name-only source lists.
 local classicDefault=fallback and not hasConfirmed
 if classicDefault then table.insert(lines,fallback) end
 local sources=libraryCall("GetRecipeSources",recipeID)
 local hasTrainers=(type(sources)=="table" and type(sources.trainer)=="table" and #sources.trainer>0)
  or (CraftRoster.RecipeLocations and CraftRoster.RecipeLocations:HasTrainerData(recipeID))
 -- Free-form text cannot be faction-filtered safely for trainer recipes.
 if saved.sourceText and not hasTrainers and not hasConfirmed and not classicDefault then
		local native=saved.sourceText:gsub("([Vv]endor%s*:%s*)%d+", "%1name unavailable (source details not recorded)")
  table.insert(lines,native)
	end
 if #locations>0 and not classicDefault then
  for _,location in ipairs(locations) do
   table.insert(lines,CraftRoster.RecipeLocations:Label(location))
   local rate=CraftRoster.ClassicSources and CraftRoster.ClassicSources:ForeverRate(location)
   if rate~=nil then table.insert(lines,("Forever drop chance: %.2f%% per kill"):format(rate)) end
   table.insert(lines,(location.source or "Database")..(location.confirmed and " · confirmed source record" or " reference; verify vendor stock in game."))
  end
 elseif acquisition and not saved.sourceText and not classicDefault then
  table.insert(lines,"Vendor: "..acquisition.vendor)
  table.insert(lines,"Location: "..acquisition.zone.." ("..acquisition.coordinates..")")
  table.insert(lines,"Availability: "..acquisition.faction)
  table.insert(lines,"ATT Forever reference; verify vendor stock in game.")
 end
 if hasTrainers and not classicDefault then
  local listed=false
  for _,location in ipairs(locations) do if location.kind=="trainer" then listed=true end end
  if not listed then table.insert(lines,"Trainer listings withheld: faction or training skill not verified for your character.") end
 end
	data.hasLibrarySource=not not (hasTrainers or classicDefault)
	if type(sources)=="table" and not hasConfirmed and not classicDefault then
		local labels={trainer="Trainer",vendor="Vendor",quest="Quest",container="Container",drop="Mob/boss drop"}
		if saved.sourceText then table.insert(lines,"\nAdditional database sources:") end
		for _,kind in ipairs({"trainer","vendor","quest","container","drop"}) do
			local list=sources[kind]
			if type(list)=="table" and #list>0 and kind~="trainer" then
				data.hasLibrarySource=true
				local total=type(list.total)=="number" and math.max(#list,list.total) or #list
				table.insert(lines,labels[kind].." sources: "..total)
				local limit=compact and 2 or 12
				for index,source in ipairs(list) do
					if index>limit then break end
					if type(source)=="table" then
						table.insert(lines,labels[kind]..": "..(type(source.name)=="string" and not source.name:match("^%s*%d+%s*$") and source.name or "Name unavailable — source details not recorded"))
					end
				end
				if total>math.min(limit,#list) then table.insert(lines,"and "..(total-math.min(limit,#list)).." more (database examples are capped).") end
			end
		end
		if data.hasLibrarySource then
			local borrowed=libraryCall("IsBorrowed",recipeID,"sources")
			table.insert(lines,borrowed and (tostring(borrowed).." reference - Forever source unconfirmed.") or "LibProfessionDB source; verify in game.")
			if not compact then table.insert(lines,"Source names are English. Provenance: bundled LibProfessionDB v1.9.1; emulator reference databases, not verified Forever loot rates.") end
		end
	end
 if data.hasLibrarySource and #locations==0 and not classicDefault then
  table.insert(lines,"Coordinates unavailable: no confirmed Forever position recorded.")
 end
	if not data.hasLibrarySource and libraryCall("IsAutoTaughtRecipe",recipeID) then
		data.hasLibrarySource=true; table.insert(lines,"Learned with profession (database reference; verify in game).")
	end
	local skill=libraryCall("GetRequiredSkill",saved.professionID or professionIDs[saved.profession],recipeID)
	if type(skill)=="number" and skill>0 then
		local borrowed=libraryCall("IsBorrowed",recipeID,"requiredSkill")
		table.insert(lines,"Required skill: "..skill..(borrowed and (" ("..tostring(borrowed).." reference; unconfirmed)") or " (database reference)"))
	end
 if fallback and not classicDefault then table.insert(lines,"\n"..fallback)
 elseif not saved.sourceText and not data.hasLibrarySource and not acquisition and #locations==0 then
  table.insert(lines,"Source unknown: no acquisition details available.")
 end
 local knownRate=false
 for _,location in ipairs(locations) do
  if CraftRoster.ClassicSources and CraftRoster.ClassicSources:ForeverRate(location)~=nil then knownRate=true end
 end
 local hasDrop=type(sources)=="table" and type(sources.drop)=="table" and #sources.drop>0
 for _,location in ipairs(locations) do if location.kind=="mob" then hasDrop=true end end
 if not fallback and not knownRate and (hasDrop or (#locations==0 and not data.hasLibrarySource)) then
  table.insert(lines,"Drop chance: unknown (no verified estimate)")
 end
 local gaps=CraftRoster.ClassicSourceData and CraftRoster.ClassicSourceData.gaps
 if not fallback and not hasConfirmed and gaps and gaps[recipeID] then
  table.insert(lines,gaps[recipeID]=="no_exact_classic_spell"
   and "Classic lookup: no exact Classic counterpart. This recipe needs a Forever-specific acquisition record."
   or "Classic lookup: no detailed acquisition record available in the bundled sources.")
 end
	if compact then return table.concat(lines,"\n") end
	table.insert(lines, "\n|cffffd100Recipe item binding|r")
	table.insert(lines, data.binding or "Unknown: learnable recipe item not mapped.")
	if reference then
		table.insert(lines, ("Requires %s (%d) (Classic reference)"):format(reference.profession, reference.skill))
		if reference.requirement then table.insert(lines, "Requires " .. reference.requirement) end
	end
	if saved.description then table.insert(lines, "\n" .. saved.description) end
	return table.concat(lines, "\n")
end

-- Keep the acquisition overview useful on the main pane. Full provenance,
-- secondary sources and unknown-field explanations remain one click away.
function Sources:Summary(recipeID)
 local data=self:Get(recipeID)
 local locations=CraftRoster.RecipeLocations and CraftRoster.RecipeLocations:Get(recipeID) or {}
 local lines={}
 local confirmed=false
 for _,location in ipairs(locations) do if location.confirmed then confirmed=true end end
 if not confirmed then
  local classic=CraftRoster.ClassicSources and CraftRoster.ClassicSources:Format(recipeID,data.itemID,{},true,true)
  if classic then return classic end
 end
 if #locations>0 then
  lines[#lines+1]=CraftRoster.RecipeLocations:Label(locations[1])
  if locations[1].source and not locations[1].confirmed then lines[#lines+1]=locations[1].source.." reference" end
  local rate=CraftRoster.ClassicSources and CraftRoster.ClassicSources:ForeverRate(locations[1])
  if rate~=nil then lines[#lines+1]=("Forever drop chance: %.2f%% per kill"):format(rate)
  elseif locations[1].confirmed and CraftRoster.ClassicSources then
   local estimate=CraftRoster.ClassicSources:Format(recipeID,data.itemID,locations,true,true)
   if estimate then lines[#lines+1]=estimate end
  end
  if #locations>1 then lines[#lines+1]="More locations in source details." end
  return table.concat(lines,"\n")
 end
 local classic=CraftRoster.ClassicSources and CraftRoster.ClassicSources:Format(recipeID,data.itemID,{},true,true)
 if classic then return classic end
 local full=self:Format(recipeID,data,true)
 for line in full:gmatch("[^\n]+") do
  if not line:find("Where to get it",1,true) and not line:find("sources:",1,true)
   and not line:find("Source:",1,true) and not line:find("Coordinates unavailable",1,true)
   and not line:find("Provenance:",1,true) and not line:find("Additional database",1,true) then
   lines[#lines+1]=line
  end
 end
 if #lines>6 then
  local brief={}
  for index=1,5 do brief[index]=lines[index] end
  brief[6]="More sources and provenance in source details."
  -- A compact display must never drop the provenance warning below the cut.
  if full:find("reference",1,true) then brief[#brief+1]="Database reference — unconfirmed in Forever." end
  return table.concat(brief,"\n")
 end
 return table.concat(lines,"\n")
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
