local _, addon = ...
local Pricing = {}
addon.Pricing = Pricing

-- Read optional addons' existing databases only. No scans, network requests,
-- persistent price database, or per-frame work belong in this module.
local cache, slots, nextSlot = {}, {}, 1
local identities = {}
local LIMIT, TTL, MAX = 128, 30, 9007199254740991
local function Positive(value)
 return type(value)=="number" and value==value and value>0 and value<math.huge and value<=1000000000000
end
local function Count(value)
 return type(value)=="number" and value==value and value>=0 and value<=1000000000 and value==math.floor(value)
end
local function Now() return (GetTime and GetTime()) or (time and time()) or 0 end
function Pricing:Clear()
 cache, slots, nextSlot = {}, {}, 1
end
local function Providers()
 local auc=type(Auctioneer)=="table" and Auctioneer or nil
 local modern=type(TSM_API)=="table" and TSM_API or nil
 local legacy=type(TSMAPI)=="table" and TSMAPI or nil
 local current={auc or false,auc and auc.Statistics or false,
  modern or false,modern and modern.GetCustomPriceValue or false,
  legacy or false,legacy and legacy.GetItemValue or false}
 for i=1,6 do
  if identities[i]~=current[i] then Pricing:Clear();identities=current;break end
 end
 return auc,modern,legacy
end
function Pricing:UnitPrice(itemID)
 if not Count(itemID) or itemID==0 then return nil end
 local auc,modern,legacy=Providers()
 local now=Now()
 local cached=cache[itemID]
 if cached and now>=cached.at and now-cached.at<TTL then return cached.value,cached.source end
 local value,source
 if auc and type(auc.Statistics)=="function" then
  local ok,stats=pcall(auc.Statistics,auc,itemID)
  if ok and type(stats)=="table" then
   for i,stat in ipairs(stats) do
    if i>16 then break end
    if type(stat)=="table" and type(stat.Best)=="function" then
     local success,price=pcall(stat.Best,stat)
     if success and Positive(price) then value=price;source="Auctioneer statistics";break end
    end
   end
  end
 end
 if not value and modern and type(modern.GetCustomPriceValue)=="function" then
  local ok,price=pcall(modern.GetCustomPriceValue,"dbmarket","i:"..itemID)
  if ok and Positive(price) then value=price;source="TSM DBMarket" end
 end
 if not value and legacy and type(legacy.GetItemValue)=="function" then
  local ok,price=pcall(legacy.GetItemValue,legacy,"item:"..itemID,"DBMarket")
  if ok and Positive(price) then value=price;source="TSM DBMarket (legacy)" end
 end
 -- Refresh an existing slot in place: expiring entries must not create
 -- duplicate ring slots which could evict a newer copy prematurely.
 if not cached then
  local previous=slots[nextSlot]
  if previous then cache[previous]=nil end
  slots[nextSlot]=itemID;nextSlot=nextSlot%LIMIT+1
 end
 cache[itemID]={value=value,source=source,at=now}
 return value,source
end
function Pricing:Estimate(entries)
 if type(entries)~="table" or #entries==0 then return nil end
 local result={full=0,buy=0,fullMissing=0,buyMissing=0,bagUnknown=0,priced=0,total=#entries,sources={}}
 for _,entry in ipairs(entries) do
  local full,required=entry.recipeRequired,entry.required
  local price,source=self:UnitPrice(entry.itemID)
  entry.unitPrice,entry.priceSource=price,source
  if price then result.priced=result.priced+1;result.sources[source]=true end
  if not Count(full) then result.fullMissing=result.fullMissing+1
  elseif full>0 then
   if price and price*full<=MAX-result.full then result.full=result.full+price*full
   else result.fullMissing=result.fullMissing+1 end
  end
  local missing
  if not Count(required) then result.bagUnknown=result.bagUnknown+1
  elseif required==0 then missing=0
  elseif Count(entry.owned) then missing=math.max(0,required-entry.owned)
  else result.bagUnknown=result.bagUnknown+1 end
  -- Bank snapshots never count as bag stock. 'required' already subtracts
  -- confirmed deliveries and the selected crafter's contribution.
  if missing and missing>0 then
   if price and price*missing<=MAX-result.buy then result.buy=result.buy+price*missing
   else result.buyMissing=result.buyMissing+1 end
  end
 end
 return result
end
function Pricing:Money(value)
 value=math.ceil(value)
 return ("%.0fg %ds %dc"):format(math.floor(value/10000),math.floor(value/100)%100,value%100)
end
function Pricing:Summary(result)
 if not result then return "" end
 if result.priced==0 and result.fullMissing>0 then
  if result.buyMissing==0 and result.bagUnknown==0 and result.buy==0 then return "Full mats: ?\nTo buy: 0g 0s 0c" end
  return "Prices unavailable"
 end
 local full=self:Money(result.full)..(result.fullMissing>0 and " + ?" or "")
 local buy=result.bagUnknown>0 and "? (bag count)" or self:Money(result.buy)..(result.buyMissing>0 and " + ?" or "")
 return "Full mats: "..full.."\nTo buy: "..buy
end
function Pricing:Tooltip(result)
 local lines={"Material cost estimate"}
 if not result then return lines end
 lines[#lines+1]=self:Summary(result)
 local names={};for name in pairs(result.sources) do names[#names+1]=name end;table.sort(names)
 lines[#lines+1]=#names>0 and ("Source: "..table.concat(names,", ")) or "No supported price data. Use Auctioneer or TSM with local price data."
 lines[#lines+1]=("Priced material types: %d / %d"):format(result.priced,result.total)
 if result.fullMissing>0 or result.buyMissing>0 then lines[#lines+1]="+ ? means incomplete pricing; the shown amount is only the known subtotal." end
 if result.bagUnknown>0 then lines[#lines+1]="Bag counts unavailable: the amount to buy cannot be determined." end
 lines[#lines+1]="Full mats values all raw materials for the selected craft quantity. To buy subtracts bags, confirmed deliveries and crafter-provided materials; saved bank stock is excluded."
 lines[#lines+1]="Market estimates are not current offers or guaranteed purchase prices. Scan age is controlled by your pricing addon."
 lines[#lines+1]="Click to reread local prices. CraftRoster does not scan or purchase items."
 return lines
end
