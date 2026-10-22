
function print() end
function GetBuildInfo() return '1.60.1', '70450', 'today', 16001 end
function GetLocale() return 'enUS' end
clock = 100000; frames = {}; sent = {}; timers = {}; SlashCmdList = {}; StaticPopupDialogs = {}
local methods = {}
function methods:SetBackdrop(data)
 if apiProfile=='modern' then assert(self.template=='BackdropTemplate', 'missing BackdropTemplate') end
end
function methods:SetScript(k,v) self.scripts[k]=v end
function methods:RegisterEvent(k) self.events[k]=true end
function methods:UnregisterAllEvents() self.events={} end
function methods:UnregisterEvent(k) self.events[k]=nil end
function methods:SetSize(w,h) self.width=w; self.height=h end
function methods:SetScale(value) self.scale=value end
function methods:SetAlpha(value) self.alpha=value end
function methods:GetAlpha() return rawget(self,'alpha') or 1 end
function methods:GetScale() return rawget(self,'scale') or 1 end
function methods:SetChecked(value) self.checked=value end
function methods:GetChecked() return rawget(self,'checked') or false end
function methods:SetBackdropColor(...) self.backdropColor={...} end
function methods:SetBackdropBorderColor(...) self.borderColor={...} end
function methods:GetFrameLevel() return 1 end
function methods:IsMovable() return self.movable == true end
function methods:GetWidth() return rawget(self,'width') or 100 end
function methods:GetHeight() return rawget(self,'height') or 100 end
function methods:SetText(t) self.text=t end
function methods:GetNumLines() local _,n=(rawget(self,'text') or ''):gsub('\n',''); return n+1 end
function methods:SetFocus() self.focused=true end
function methods:ClearFocus() self.focused=false end
function methods:HighlightText() self.highlighted=true end
function methods:GetText() return rawget(self,'text') or '' end
function methods:GetPoint() return 'CENTER',nil,'CENTER',0,0 end
function methods:Show() self.shown=true end
function methods:Hide() self.shown=false; if self.scripts.OnHide then self.scripts.OnHide(self) end end
function methods:IsShown() return self.shown ~= false end
function methods:SetID(id) self.id=id end
function methods:GetID() return self.id end
function methods:SetEnabled(enabled) self.enabled=not not enabled end
function methods:IsEnabled() return self.enabled~=false end
function methods:HookScript(name, callback)
 local old=self.scripts[name]
 self.scripts[name]=function(...) if old then old(...) end; callback(...) end
end
function methods:SetVerticalScroll(offset) self.scroll=offset end
function methods:GetVerticalScroll() return rawget(self,'scroll') or 0 end
function methods:GetParent() return self.parent end
function methods:SetParent(parent) self.parent=parent end
function CreateFrame(kind,name,parent,template)
 local f=setmetatable({scripts={},events={},parent=parent}, {__index=function(_,k) return methods[k] or (k:match('^[A-Z]') and (k:match('^Set') or k:match('^Enable') or k:match('^Register') or k:match('^Clear') or k:match('^Start') or k:match('^Stop')) and function() end) or nil end})
 table.insert(frames,f)
 local title=setmetatable({scripts={},events={},parent=f},getmetatable(f))
 if apiProfile == "modern" then f.TitleText=title else f.TitleBar={TitleText=title} end
 f.Inset=f; f.Text=f; f.template=template
 if name then _G[name]=f end
 return f
end
methods.CreateTexture=function(self) return CreateFrame('Texture',nil,self) end
methods.CreateFontString=methods.CreateTexture
UIParent=CreateFrame(); Minimap=CreateFrame(); GameTooltip=CreateFrame()
function GameTooltip:AddLine() end
function UnitName(unit) return unit == 'NPC' and 'Crafter' or 'Tester' end
function GetRealmName() return 'Realm' end
function UnitClass() return 'Mage','MAGE' end
function UnitRace() return 'Human','Human' end
function UnitSex() return 2 end
function time() return math.floor(clock) end
function date() return '12:00' end
function GetNumProfessions() return 0 end
originalErrors = {}
local errorHandler = function(err, ...) table.insert(originalErrors, {err, ...}); return "forwarded" end
function geterrorhandler() return errorHandler end
function seterrorhandler(fn) errorHandler = fn end
function wipe(t) for k in pairs(t) do t[k]=nil end end
function UIDropDownMenu_SetWidth() end
function UIDropDownMenu_Initialize() end
function UIDropDownMenu_SetText() end
function PanelTemplates_SetTabState() end
function StaticPopup_Show() end
function StaticPopup_Hide() end
C_ChatInfo={RegisterAddonMessagePrefix=function() end, SendAddonMessage=function(p,m,c) table.insert(sent,{p,m,c}) end}
C_Timer={NewTimer=function(delay,fn)
 local t={callback=fn, delay=delay, due=clock+delay, Cancel=function(self) self.cancelled=true end}; table.insert(timers,t); return t
end}
function dispatch(event,...)
 local count=#frames
 for i=1,count do local f=frames[i]; if f.events[event] and f.scripts.OnEvent then f.scripts.OnEvent(f,event,...) end end
end

function flushTimers()
 local limit=0
 while #timers>0 do
  table.sort(timers,function(a,b) return a.due<b.due end)
  local t=table.remove(timers,1)
  if not t.cancelled then clock=math.max(clock,t.due); t.callback() end
  limit=limit+1; assert(limit<2000)
 end
end
function configure(profile)
 apiProfile=profile
 if profile == 'legacy' then
  SendAddonMessage=C_ChatInfo.SendAddonMessage; RegisterAddonMessagePrefix=C_ChatInfo.RegisterAddonMessagePrefix; C_ChatInfo=nil
 elseif profile == 'minimal' then
  C_ChatInfo=nil; C_Timer=nil
 else
  BackdropTemplateMixin={}
 end
end

-- Model bag stacks, cursor transfers and occupied attachment slots separately.
function inventoryFixture(locked, splitAvailable)
 inventory={[1]={count=20,locked=locked},[2]={count=4,locked=false}}
 attachments={}; cursor=nil; moved=0
 CraftRosterDB.recipes[42]={name='Potion',materials={{name='Herb',itemID=7,count=3}}}
 local function slots(bag) return bag==0 and 2 or 0 end
 local function link(bag,slot) return inventory[slot] and inventory[slot].count>0 and '|Hitem:7|h[Herb]|h' end
 local function pickup(bag,slot)
  assert(not cursor); cursor=inventory[slot].count; inventory[slot].count=0
 end
 local function split(bag,slot,amount)
  assert(not cursor); assert(amount<=inventory[slot].count)
  inventory[slot].count=inventory[slot].count-amount; cursor=amount
 end
 function CursorHasItem() return cursor~=nil end
 local function click(slot)
  assert(cursor and not attachments[slot]); attachments[slot]=cursor; moved=moved+cursor; cursor=nil
 end
 function GetTradePlayerItemInfo(slot) return attachments[slot] and 'Herb', 'icon', attachments[slot] end
 function GetTradePlayerItemLink(slot) return attachments[slot] and '|Hitem:7|h[Herb]|h' end
 GetSendMailItem=GetTradePlayerItemInfo; ClickTradeButton=click; ClickSendMailItemButton=click
 if apiProfile=='modern' then
  C_Container={GetContainerNumSlots=slots, GetContainerItemLink=link, PickupContainerItem=pickup,
   SplitContainerItem=splitAvailable and split or nil,
   GetContainerItemInfo=function(bag,slot) local i=inventory[slot]; return {stackCount=i.count,isLocked=i.locked} end}
 else
  GetContainerNumSlots=slots; GetContainerItemLink=link; PickupContainerItem=pickup
  SplitContainerItem=splitAvailable and split or nil
  function GetContainerItemInfo(bag,slot) return 'icon',inventory[slot].count,inventory[slot].locked end
 end
 function AcceptTrade() error('must not accept trade') end
 function SendMail() error('must not send mail') end
end

