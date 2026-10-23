local ADDON_NAME, CraftRoster = ...
local Locations = {}
CraftRoster.RecipeLocations = Locations

-- Reviewed addon data only. Never accept coordinates/status from guild messages,
-- SavedVariables, free-form source text or NPC-name matching.
local granny = {
 kind="vendor", npcID=258306, name="Granny Finespindle", zone="Ironforge",
 x=39.3, y=33.7, faction="Alliance", status="reference",
 source="ATT Forever", revision="d5741058c49a767660f894aa434f3246cd57485b",
 url="https://github.com/ATTWoWAddon/AllTheThings/blob/d5741058c49a767660f894aa434f3246cd57485b/.contrib/.db/forever/zones/eastern%20kingdoms/1%20-%20ironforge.lua",
}
-- uiMapID is intentionally absent until checked against the target client.
Locations.bySpell = {[1255143]={granny}}
Locations.byItem = {}
for _,id in ipairs({252761,252762,252832,252764,252763,252826,252830,252831,252827,252828,252829}) do
 Locations.byItem[id]={granny}
end
local kinds={vendor="Vendor",trainer="Trainer",mob="Mob"}
local function valid(record)
 return type(record)=="table" and kinds[record.kind] and type(record.npcID)=="number" and record.npcID>0 and record.npcID<2147483647 and record.npcID==math.floor(record.npcID)
  and type(record.name)=="string" and record.name~="" and type(record.zone)=="string" and record.zone~=""
  and type(record.x)=="number" and record.x>=0 and record.x<=100
  and type(record.y)=="number" and record.y>=0 and record.y<=100
end
local function trainerEligible(record)
 if record.kind~="trainer" then return true end
 if type(record.requiredSkill)~="number" or record.requiredSkill<0 or record.requiredSkill>10000 or record.requiredSkill~=math.floor(record.requiredSkill)
  or type(record.profession)~="string" or record.profession=="" then return false end
 if record.faction=="Neutral" then return true end
 if record.faction~="Alliance" and record.faction~="Horde" then return false end
 if type(UnitFactionGroup)~="function" then return false end
 local ok,faction=pcall(UnitFactionGroup,"player")
 return ok and faction==record.faction
end
local function approved(record)
 return valid(record) and record.era~="Classic" and trainerEligible(record) and record.status=="confirmed" and type(record.url)=="string"
  and record.url:match("^https://") and type(record.revision)=="string" and record.revision~=""
  and type(record.checked)=="string" and record.checked:match("^%d%d%d%d%-%d%d%-%d%d$")
end
function Locations:Records(recipeID)
 local records=self.bySpell[recipeID]
 if not records then
  local item=CraftRoster.RecipeSources:Get(recipeID).itemID
  records=(item and self.byItem[item]) or {}
 end
 return records
end
function Locations:HasTrainerData(recipeID)
 for _,record in ipairs(self:Records(recipeID)) do
  if type(record)=="table" and record.kind=="trainer" then return true end
 end
 return false
end
function Locations:Get(recipeID)
 local out={}
 for _,record in ipairs(self:Records(recipeID)) do
  if valid(record) and (record.kind~="trainer" or approved(record)) then
   local copy={}
   for key,value in pairs(record) do copy[key]=value end
   copy.confirmed=not not approved(record)
   out[#out+1]=copy
  end
 end
 return out
end
function Locations:Label(record)
 local text=("%s: %s\n%s (%s, %s)"):format(kinds[record.kind],record.name,record.zone,tostring(record.x),tostring(record.y))
 if record.kind=="mob" then text=text.." · "..(record.area and "spawn area" or "reported spawn point") end
 if record.subzone then text=text.." · "..record.subzone end
 if record.faction then text=text.." · "..record.faction end
 if record.kind=="trainer" then text=text.."\nRequires "..record.profession.." "..record.requiredSkill end
 if record.requirements then text=text.."\nRequirements: "..record.requirements end
 return text.."\n"..(approved(record) and ("Confirmed · checked "..record.checked) or "Unverified reference · navigation unavailable")
end
function Locations:CopyText(record)
 if not approved(record) then return nil end
 local id=record.uiMapID
 -- Explicit map IDs prevent a command from putting a point in the player's
 -- current zone. Don't guess IDs or map an NPC's name to an unrelated zone.
 if type(id)=="number" and id>0 and id==math.floor(id) then
  return ("/way #%d %s %s %s"):format(id,tostring(record.x),tostring(record.y),record.name)
 end
 return ("%s: %s, %s — %s"):format(record.zone,tostring(record.x),tostring(record.y),record.name)
end
local function usableMap(record)
 local id=record.uiMapID
 if type(id)~="number" or id<=0 or id~=math.floor(id) then return false end
 if not C_Map or type(C_Map.GetMapInfo)~="function" then return false end
 local ok,info=pcall(C_Map.GetMapInfo,id)
 return ok and type(info)=="table" and type(info.name)=="string" and info.name~=""
end
function Locations:Backend(record)
 if not approved(record) then return nil end
 if usableMap(record) then
  if TomTom and type(TomTom.AddWaypoint)=="function" then return "tomtom" end
  if type(C_Map.SetUserWaypoint)=="function" and UiMapPoint and type(UiMapPoint.CreateFromCoordinates)=="function" then
   if type(C_Map.CanSetUserWaypointOnMap)=="function" then
    local ok,can=pcall(C_Map.CanSetUserWaypointOnMap,record.uiMapID)
    if not ok or not can then return nil end
   end
   return "native"
  end
 end
 -- Legacy TomTom resolves its own continent/zone indices from the zone name.
 -- Never pass a modern map ID to this API.
 if TomTom and type(TomTom.GetZoneInfo)=="function" and type(TomTom.AddMFWaypoint)=="function" then
  local ok,continent,zone=pcall(TomTom.GetZoneInfo,TomTom,record.zone)
  if ok and type(continent)=="number" and continent>0 and type(zone)=="number" and zone>0 then
   return "legacy",continent,zone
  end
 end
end
function Locations:Navigate(record)
 local backend,continent,zone=self:Backend(record)
 if not backend then return false,"No compatible map support, or location is unverified. Copy confirmed coordinates instead." end
 local ok,result
 if backend=="tomtom" then
  ok,result=pcall(TomTom.AddWaypoint,TomTom,record.uiMapID,record.x/100,record.y/100,
   {title=record.name.." · CraftRoster",persistent=false,source="CraftRoster"})
 elseif backend=="legacy" then
  ok,result=pcall(TomTom.AddMFWaypoint,TomTom,continent,zone,record.x/100,record.y/100,
   {title=record.name.." · CraftRoster",persistent=false})
 else
  local created,point=pcall(UiMapPoint.CreateFromCoordinates,record.uiMapID,record.x/100,record.y/100)
  if not created or not point then return false,"Unable to create a waypoint on this client." end
  ok,result=pcall(C_Map.SetUserWaypoint,point)
  if ok and result~=false then
   if type(OpenWorldMap)=="function" then pcall(OpenWorldMap,record.uiMapID) end
   return true
  end
 end
 if ok and result then return true end
 return false,"Waypoint could not be created. Copy the coordinates instead."
end
StaticPopupDialogs.CRAFTROSTER_COPY_LOCATION={
 text="Copy location (Ctrl+C). /way #mapID commands require a compatible TomTom version. Other coordinate addons may use different commands.",
 button1="Close",hasEditBox=true,timeout=0,whileDead=true,hideOnEscape=true,
 OnShow=function(self)
  local edit=self.editBox or self.EditBox
  edit:SetNumeric(false); edit:SetMaxLetters(0); edit:SetText(self.data or ""); edit:HighlightText(); edit:SetFocus()
 end,
}
