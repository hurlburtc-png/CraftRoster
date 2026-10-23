local ADDON_NAME, CraftRoster = ...
local Classic = {}
CraftRoster.ClassicSources = Classic

-- Exact spell + teaching-item matches only. These are references, NEVER Forever
-- approvals. Per-record evidence and expansion notes live in docs/RECIPE_SOURCES.md.
Classic.records = {
 [17635]={spellID=17635,itemID=13519,checked="2026-10-19",sources={
  {kind="boss",npcID=10363,name="General Drakkisath",zone="Upper Blackrock Spire",instance=true,chance=4.60,
   provider="Forever Changes (Classic reference)",url="https://foreverchanges.pro/items/13519"}}},
 [20034]={spellID=20034,itemID=16252,checked="2026-10-19",sources={
  {kind="mob",npcID=4494,name="Scarlet Spellbinder",zone="Western Plaguelands",chance=0.43,
   provider="WoW Classic Database",url="https://wowclassicdatabase.com/item/formula-enchant-weapon---crusader"}}},
 [19054]={spellID=19054,itemID=15730,checked="2026-10-19",sources={
  {kind="boss",npcID=10363,name="General Drakkisath",zone="Upper Blackrock Spire",instance=true,chance=4.95,
   provider="Wowhead Classic",url="https://www.wowhead.com/classic/item=15730/pattern-red-dragonscale-breastplate"}}},
 [23081]={spellID=23081,itemID=18657,checked="2026-10-19",sources={
  {kind="boss",npcID=10264,name="Solakar Flamewreath",zone="Upper Blackrock Spire",instance=true,chance=8.08,
   provider="Wowhead Classic",url="https://www.wowhead.com/classic/item=18657/schematic-hyper-radiant-flame-reflector"}}},
}
-- Small factual reference subset from QuestieDB's Classic tables, not its code
-- or a second bundled database. Exact upstream revision is in each evidence URL.
local questieRoot="https://github.com/Questie/QuestieDB/blob/1f538335cfbb240c14a97c340f48c555fdc8a52b/data/Classic/"
local itemURL=questieRoot.."classicItemDB.lua"
local npcURL=questieRoot.."classicNpcDB.lua"
local crusader=Classic.records[20034]
crusader.sources[1].x=54.31; crusader.sources[1].y=35.51; crusader.sources[1].area=true
crusader.sources[1].coordinateURL=npcURL
crusader.sources[1].coordinateChecked="2026-10-22"
crusader.sources[2]={kind="mob",npcID=9451,name="Scarlet Archmage",zone="Eastern Plaguelands",
 x=85.71,y=82.92,area=true,provider="QuestieDB Classic",url=itemURL,coordinateURL=npcURL,checked="2026-10-22"}
crusader.examples=true
local function vendor(npcID,name,zone,x,y,faction)
 return {kind="vendor",npcID=npcID,name=name,zone=zone,x=x,y=y,faction=faction,
  provider="QuestieDB Classic",url=itemURL,coordinateURL=npcURL}
end
local function recipe(spell,item,sources)
 Classic.records[spell]={spellID=spell,itemID=item,checked="2026-10-22",examples=true,sources=sources}
end
recipe(3454,14634,{vendor(2480,"Bro'kin","Alterac Mountains",38.24,38.87,"Neutral")})
recipe(3449,6068,{vendor(2481,"Bliztik","Duskwood",18.04,54.36,"Neutral")})
recipe(7255,6053,{
 vendor(1685,"Xandar Goodbeard","Loch Modan",82.47,63.35,"Alliance"),
 vendor(3134,"Kzixx","Duskwood",81.82,19.77,"Neutral"),
 vendor(3490,"Hula'mahi","The Barrens",51.39,30.2,"Horde")})
recipe(7256,6054,{
 vendor(2393,"Christoph Jeffcoat","Hillsbrad Foothills",62.29,19.04,"Horde"),
 vendor(3956,"Harklan Moongrove","Ashenvale",50.84,67,"Alliance")})
recipe(7258,6056,{
 vendor(2812,"Drovnar Strongbrew","Arathi Highlands",46.32,47.04,"Alliance"),
 vendor(2848,"Glyx Brewright","Stranglethorn Vale",28.14,78.11,"Neutral")})
recipe(7259,6057,{
 vendor(2848,"Glyx Brewright","Stranglethorn Vale",28.14,78.11,"Neutral"),
 vendor(5594,"Alchemist Pestlezugg","Tanaris",50.89,26.96,"Neutral"),
 vendor(8157,"Logannas","Feralas",32.67,44.03,"Alliance"),
 vendor(8158,"Bronk","Feralas",76.06,43.28,"Horde")})
-- Enchanting vendor examples use the same pinned Classic item/NPC evidence.
local dalria=vendor(3954,"Dalria","Ashenvale",35.12,52.12,"Alliance")
local kulwia=vendor(12043,"Kulwia","Stonetalon Mountains",45.39,59.33,"Horde")
local mythrin=vendor(4229,"Mythrin'dir","Darnassus",60.96,17.67,"Alliance")
local lorelae=vendor(12022,"Lorelae Wintersong","Moonglade",48.24,40.14,"Neutral")
recipe(7443,6342,{vendor(1318,"Jessara Cordell","Stormwind City",42.81,64.39,"Alliance"),
 vendor(3346,"Kithas","Orgrimmar",53.88,38.02,"Horde")})
recipe(7793,6349,{vendor(5158,"Tilli Thistlefuzz","Ironforge",61.03,44,"Alliance"),
 vendor(3012,"Nata Dawnstrider","Thunder Bluff",44.99,38.75,"Horde")})
recipe(13419,11039,{dalria,kulwia})
recipe(13536,11101,{dalria,kulwia})
recipe(13646,11163,{vendor(2381,"Micha Yance","Hillsbrad Foothills",48.94,55.03,"Alliance"),
 vendor(2821,"Keena","Arathi Highlands",74.09,32.73,"Horde")})
recipe(13931,11223,{mythrin,vendor(989,"Banalash","Swamp of Sorrows",44.77,56.63,"Horde")})
recipe(20015,16224,{lorelae})
recipe(20017,16217,{mythrin,vendor(4561,"Daniel Bartlett","Undercity",64.05,37.37,"Horde")})
recipe(20026,16221,{vendor(11189,"Qia","Winterspring",61.2,37.21,"Neutral")})
recipe(20051,16243,{lorelae})
local kinds={mob="Mob",boss="Boss",vendor="Vendor",trainer="Trainer",quest="Quest"}
local function text(value) return type(value)=="string" and value~="" end
local function id(value) return type(value)=="number" and value>0 and value<2147483647 and value==math.floor(value) end
local function percent(value) return type(value)=="number" and value>=0 and value<=100 end
local function evidence(value) return text(value) and value:match("^https://") end
local function factionAllowed(source)
 if source.kind~="trainer" and source.kind~="vendor" then return true end
 if source.kind=="vendor" and source.faction==nil then return true end
 if source.kind=="trainer" and (not text(source.profession) or type(source.requiredSkill)~="number" or source.requiredSkill<0
  or source.requiredSkill>10000 or source.requiredSkill~=math.floor(source.requiredSkill)) then return false end
 if source.faction=="Neutral" then return true end
 if source.faction~="Alliance" and source.faction~="Horde" then return false end
 if type(UnitFactionGroup)~="function" then return false end
 local ok,faction=pcall(UnitFactionGroup,"player")
 return ok and faction==source.faction
end
function Classic:Get(recipeID,itemID)
 local record=self.records[recipeID]
 if type(record)~="table" or record.spellID~=recipeID or type(record.sources)~="table" then return nil end
 if record.trainerOnly then
  if itemID~=nil then return nil end
 elseif not id(record.itemID) or itemID~=record.itemID then return nil end
 return record
end
function Classic:ForeverRate(location)
 local rate=location.dropRate
 if location.era=="Classic" or location.kind~="mob" or not location.confirmed or type(rate)~="table" or rate.era~="Forever" or rate.confirmed~=true or not percent(rate.percent)
  or not evidence(rate.url) or not text(rate.revision) or not text(rate.checked)
  or not rate.checked:match("^%d%d%d%d%-%d%d%-%d%d$") then return nil end
 return rate.percent
end
function Classic:Format(recipeID,itemID,locations,compact,summary)
 local record=self:Get(recipeID,itemID)
 if not record then return nil end
 local confirmed,matching={},{}
 for _,location in ipairs(locations or {}) do
  if type(location)=="table" and location.confirmed and id(location.npcID) then
   confirmed[#confirmed+1]=location
   local previous=matching[location.npcID]
   if not previous or (location.kind=="mob" and (previous.kind~="mob" or self:ForeverRate(location)~=nil)) then
    matching[location.npcID]=location
   end
  end
 end
 local entries={}
 for _,source in ipairs(record.sources) do
  if type(source)=="table" and kinds[source.kind] and id(source.npcID) and text(source.name)
   and text(source.zone) and evidence(source.url) and factionAllowed(source) then
   -- Once Forever has an approved source/location, never replace it with an
   -- old Classic location. A rate fallback must match that exact approved NPC.
   local live=matching[source.npcID]
   if #confirmed==0 or (live and (source.kind=="mob" or source.kind=="boss")
    and (live.kind=="mob") and self:ForeverRate(live)==nil and percent(source.chance)) then
    entries[#entries+1]={source=source,live=live}
   end
  end
 end
 if #entries==0 then return nil end
 local lines={"|cffffd100Classic reference — unconfirmed in Forever|r"}
 if record.examples and not summary then lines[#lines+1]="Source examples, not a complete source list." end
 local hasDrops=false
 local limit=summary and 1 or (compact and 2 or 12)
 for index,entry in ipairs(entries) do
  if index>limit then break end
  local source=entry.source
  if source.kind=="mob" or source.kind=="boss" then hasDrops=true end
  if #confirmed==0 then
   lines[#lines+1]=kinds[source.kind]..((source.kind=="mob" or source.kind=="boss") and " drop: " or ": ")..source.name
   lines[#lines+1]="Classic location: "..source.zone..(source.instance and " (instance)" or "")
   if percent(source.x) and percent(source.y) and evidence(source.coordinateURL) then
    lines[#lines+1]="Classic coordinates: "..source.x..", "..source.y..(source.area and " (spawn area)" or "")
   elseif not summary then lines[#lines+1]="Classic coordinates: unknown" end
   if text(source.faction) then lines[#lines+1]="Classic availability: "..source.faction end
   if source.kind=="trainer" then lines[#lines+1]="Classic training skill: "..source.profession.." "..source.requiredSkill end
   if text(source.requirements) then lines[#lines+1]="Classic requirements: "..source.requirements end
  end
  if source.kind=="mob" or source.kind=="boss" then
   lines[#lines+1]=percent(source.chance) and ("Classic drop estimate: ~%.2f%% per kill (%s)"):format(source.chance,source.name)
    or "Classic drop estimate: unknown"
  end
  if not summary then lines[#lines+1]="Source: "..(text(source.provider) and source.provider or "Classic database").." · checked "..(text(source.checked) and source.checked or (text(record.checked) and record.checked or "date unknown")) end
  if not compact then
   if text(source.coordinateChecked) then lines[#lines+1]="Coordinates checked: "..source.coordinateChecked end
   lines[#lines+1]=source.url
   if evidence(source.coordinateURL) and source.coordinateURL~=source.url then lines[#lines+1]="Coordinates: "..source.coordinateURL end
  end
 end
 if #entries>limit and not summary then lines[#lines+1]="and "..(#entries-limit).." more Classic references (expand for details)." end
 if not summary and #confirmed==0 then
  lines[#lines+1]=hasDrops and "Forever location and drop rate: unknown." or "Forever location: unknown."
  lines[#lines+1]=hasDrops and "Classic estimate - Forever source/rate unconfirmed." or "Classic source — Forever availability unconfirmed."
 elseif not summary then lines[#lines+1]="Forever location confirmed; Forever drop rate unknown." end
 if not summary then lines[#lines+1]="Classic reference navigation is disabled." end
 return table.concat(lines,"\n")
end
