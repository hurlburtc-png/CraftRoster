local ADDON_NAME, CraftRoster = ...
local Items = { pending = {} }
CraftRoster.ItemDisplay = Items

-- Legacy clients expose the icon as the tenth GetItemInfo return value.
function Items:Resolve(id, fallback)
 local name,link,icon,quality
 local getInfo=C_Item and C_Item.GetItemInfo or GetItemInfo
 if id and type(getInfo)=="function" then
  local ok,n,l,q,_,_,_,_,_,_,texture=pcall(getInfo,id)
  if ok then name,link,icon,quality=n,l,texture,q end
 end
 local getIcon=C_Item and (C_Item.GetItemIconByID or C_Item.GetItemIcon) or GetItemIcon
 if not icon and id and type(getIcon)=="function" then
  local ok,value=pcall(getIcon,id); if ok then icon=value end
 end
 if id and not name and not self.pending[id] then
  self.pending[id]=true
  if C_Item and C_Item.RequestLoadItemDataByID then pcall(C_Item.RequestLoadItemDataByID,id) end
 end
 if fallback and fallback:match("^Item %d+$") then fallback=nil end
 return name or fallback or "Material loading…",link or (id and ("|cffffffff|Hitem:"..id..":0:0:0:0:0:0:0|h["..(name or fallback or "Material loading…").."]|h|r")),icon,quality
end

function Items:RecipeLabel(recipeID,fallback)
 local source=CraftRoster.RecipeSources
 local output=source and source:GetOutputItemID(recipeID)
 local _,link,_,quality=self:Resolve(output,fallback)
 local colors={[0]="ff9d9d9d",[1]="ffffffff",[2]="ff1eff00",[3]="ff0070dd",[4]="ffa335ee",[5]="ffff8000",[6]="ffe6cc80",[7]="ffe6cc80"}
 local color=colors[quality]
 local saved=CraftRosterDB.recipes and CraftRosterDB.recipes[recipeID]
 if not color and saved and type(saved.itemLink)=="string" then color=saved.itemLink:match("^|c(%x%x%x%x%x%x%x%x)") end
 -- The teaching scroll's rarity is independent of the crafted item. Unknown
 -- output quality stays neutral; never copy the pattern's colour onto it.
 color=color or "ffffffff"
 local label=tostring(fallback or "Recipe"):gsub("|c%x%x%x%x%x%x%x%x",""):gsub("|r","")
 return "|c"..color..label.."|r"
end

function Items:Click(entry)
 local _,link=self:Resolve(entry.itemID,entry.name)
 if link then
  local active=ChatEdit_GetActiveWindow and ChatEdit_GetActiveWindow()
  if active then
   if ChatEdit_InsertLink then local ok,inserted=pcall(ChatEdit_InsertLink,link); if ok and inserted then return true end end
   if active.Insert then active:Insert(link); return true end
  end
  local composer=CraftRoster.WhisperComposer
  if composer and composer.frame and composer.frame:IsShown() then return composer:InsertMaterialLink(link) end
  if IsShiftKeyDown and IsShiftKeyDown() then
   if ChatEdit_InsertLink then local ok,inserted=pcall(ChatEdit_InsertLink,link); if ok and inserted then return true end end
   if ChatFrame_OpenChat then ChatFrame_OpenChat(link); return true end
  end
 end
 return CraftRoster.ShoppingList:SearchAuctions(entry)
end

local events=CreateFrame("Frame")
pcall(events.RegisterEvent,events,"GET_ITEM_INFO_RECEIVED")
pcall(events.RegisterEvent,events,"ITEM_DATA_LOAD_RESULT")
events:SetScript("OnEvent",function(_,_,id,success)
 if not success or not Items.pending[id] then return end
 Items.pending[id]=nil
 if CraftRoster.SelectedCraft then CraftRoster.SelectedCraft.cachedLink=nil end
 if CraftRoster.ShoppingList then CraftRoster.ShoppingList:ScheduleRefresh() end
 local directory=CraftRoster.Directory
 if directory then if directory.InvalidateIndex then directory:InvalidateIndex() end end
end)
