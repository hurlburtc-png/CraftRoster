local ADDON_NAME, CraftRoster = ...
local colors={[0]="ff9d9d9d",[1]="ffffffff",[2]="ff1eff00",[3]="ff0070dd",[4]="ffa335ee",[5]="ffff8000",[6]="ffe6cc80",[7]="ffe6cc80"}
local Items = { pending = {}, loaded = {} }
CraftRoster.ItemDisplay = Items

-- GetItemInfo texture is return #10; pcall adds a leading success value.
function Items:Resolve(id, fallback)
 local name,link,icon,quality
 -- Hybrid clients may expose C_Item while its cache is still empty.
 -- Fall back to legacy APIs when modern calls fail or return no usable data.
 local modernInfo=C_Item and C_Item.GetItemInfo
 if id and type(modernInfo)=="function" then
  local ok,n,l,q,_,_,_,_,_,_,texture=pcall(modernInfo,id)
  if ok then name,link,icon,quality=n,l,texture,q end
 end
 if id and (not name or not icon) and type(GetItemInfo)=="function"
   and GetItemInfo~=modernInfo then
  local ok,n,l,q,_,_,_,_,_,_,texture=pcall(GetItemInfo,id)
  if ok then
   name=name or n; link=link or l; quality=quality or q; icon=icon or texture
  end
 end
 local modernIcon=C_Item and (C_Item.GetItemIconByID or C_Item.GetItemIcon)
 if not icon and id and type(modernIcon)=="function" then
  local ok,value=pcall(modernIcon,id); if ok then icon=value end
 end
 if not icon and id and type(GetItemIcon)=="function" and GetItemIcon~=modernIcon then
  local ok,value=pcall(GetItemIcon,id); if ok then icon=value end
 end
 if id and (not name or not icon) and not self.pending[id] and not self.loaded[id] then
  -- Only mark a request pending when the client actually accepts it.
  -- Legacy clients without an async loader must remain retryable.
  if C_Item and type(C_Item.RequestLoadItemDataByID)=="function" then
   local ok,accepted=pcall(C_Item.RequestLoadItemDataByID,id)
   -- A protected call can succeed even when the API explicitly rejects
   -- the request. Do not permanently suppress retries in that case.
   if ok and accepted~=false then self.pending[id]=true end
  end
 end
 if fallback and fallback:match("^Item %d+$") then fallback=nil end
 return name or fallback or "Material loading…",link or (id and ("|cffffffff|Hitem:"..id..":0:0:0:0:0:0:0|h["..(name or fallback or "Material loading…").."]|h|r")),icon,quality
end

function Items:RecipeLabel(recipeID,fallback)
 local source=CraftRoster.RecipeSources
 local output=source and source:GetOutputItemID(recipeID)
 local _,link,_,quality=self:Resolve(output,fallback)
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
  -- The dedicated whisper composer takes priority over stale active chat boxes.
  -- Otherwise shopping-list clicks can insert into the wrong chat destination.
  local composer=CraftRoster.WhisperComposer
  if composer and composer.frame and composer.frame:IsShown() then
   -- Never fall through to an unrelated chat or AH search while a whisper
   -- composer is visible. A failed insert should remain in that context.
   if composer.InsertMaterialLink then
    local ok,inserted=pcall(composer.InsertMaterialLink,composer,link)
    if ok and inserted then return true end
   end
   return false
  end
  local active
  if type(ChatEdit_GetActiveWindow)=="function" then
   local ok,editor=pcall(ChatEdit_GetActiveWindow)
   -- If the hybrid chat API errors, an editor may still be active.
   -- Do not guess that the user wanted an Auction House search.
   if not ok then return false end
   active=editor
  end
  if active then
   if ChatEdit_InsertLink then
    local ok,inserted=pcall(ChatEdit_InsertLink,link)
    if ok and inserted then return true end
   end
   if type(active.Insert)=="function" then
    local ok=pcall(active.Insert,active,link)
    if ok then return true end
   end
   -- A visible chat editor owns this click even if its insert API fails.
   -- Never silently turn a failed chat insertion into an AH search.
   return false
  end
  if IsShiftKeyDown and IsShiftKeyDown() then
   if ChatEdit_InsertLink then local ok,inserted=pcall(ChatEdit_InsertLink,link); if ok and inserted then return true end end
   -- An absent editor lookup is not evidence that chat is closed.
   -- Do not open a second chat window after an uncertain insert.
   if type(ChatEdit_GetActiveWindow)~="function" then return false end
   if type(ChatFrame_OpenChat)=="function" then
    local ok,opened=pcall(ChatFrame_OpenChat,link)
    if ok and opened~=false then return true end
   end
   -- Shift-click explicitly means chat, not an Auction House search.
   -- If the chat API fails, leave the material untouched for a retry.
   return false
  end
 end
 if IsShiftKeyDown and IsShiftKeyDown() then return false end
 return CraftRoster.ShoppingList:SearchAuctions(entry)
end

local events=CreateFrame("Frame")
pcall(events.RegisterEvent,events,"GET_ITEM_INFO_RECEIVED")
pcall(events.RegisterEvent,events,"ITEM_DATA_LOAD_RESULT")
events:SetScript("OnEvent",function(_,_,id,success)
 if not Items.pending[id] then return end
 Items.pending[id]=nil
 -- A failed load is not permanent; the next Resolve may retry.
 if success==false then return end
 -- Avoid an endless request/refresh loop if the client reports success
 -- but still has no texture. Resolve continues checking the local cache.
 Items.loaded[id]=true
 if CraftRoster.SelectedCraft then CraftRoster.SelectedCraft.cachedLink=nil end
 if CraftRoster.ShoppingList then CraftRoster.ShoppingList:ScheduleRefresh() end
 local directory=CraftRoster.Directory
 if directory then if directory.InvalidateIndex then directory:InvalidateIndex() end end
end)
