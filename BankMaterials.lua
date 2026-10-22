local ADDON_NAME, CraftRoster = ...
local Bank = {}
CraftRoster.BankMaterials = Bank
local pending

local function Character()
	local key=UnitName("player").."-"..(GetRealmName() or "")
	return CraftRosterDB and CraftRosterDB.characters and CraftRosterDB.characters[key]
end

function Bank:Snapshot()
	local character=Character()
	local snapshot=character and character.bankMaterials
	if type(snapshot)=="table" and type(snapshot.counts)=="table" and type(snapshot.scannedAt)=="number" then return snapshot end
end

function Bank:GetCount(key,snapshot)
	if snapshot==nil then snapshot=self:Snapshot() end
	if not snapshot or snapshot.dirty then return nil end
	local count=snapshot.counts[key]
	if count==nil then return 0 end
	if type(count)=="number" and count>=0 and count<=1000000000 and count==math.floor(count) then return count end
end

-- Personal bank only. Never scan another character, a guild bank or account storage.
-- Commit a complete snapshot atomically; unavailable/partial scans retain the last one.
function Bank:Scan()
	if not self.isOpen or not Character() then return false end
	local slots=C_Container and C_Container.GetContainerNumSlots or GetContainerNumSlots
	local info=C_Container and C_Container.GetContainerItemInfo or GetContainerItemInfo
	local link=C_Container and C_Container.GetContainerItemLink or GetContainerItemLink
	if type(slots)~="function" or type(info)~="function" then return false end
	local bankID=BANK_CONTAINER or -1
	local ok,base=pcall(slots,bankID)
	if not ok or type(base)~="number" or base<=0 then return false end
	local counts={}
	local containers={bankID}
	local first=(NUM_BAG_SLOTS or 4)+1
	for bag=first,first+math.min(NUM_BANKBAGSLOTS or 7,16)-1 do containers[#containers+1]=bag end
	for _,bag in ipairs(containers) do
		local valid,size=pcall(slots,bag)
		if not valid or type(size)~="number" or size<0 or size>500 or size~=math.floor(size) then return false end
		for slot=1,size do
			local success,item,count=pcall(info,bag,slot)
			if not success then return false end
			local itemLink
			if link then
				local read,value=pcall(link,bag,slot)
				if not read then return false end
				itemLink=value
			end
			local id
			if type(item)=="table" then
				count=item.stackCount; id=item.itemID; itemLink=item.hyperlink or itemLink
			end
			if item or itemLink then
				if type(itemLink)=="string" then id=id or tonumber(itemLink:match("item:(%d+)")) end
				if type(id)~="number" or type(count)~="number" or count<0 or count~=math.floor(count) then return false end
				counts[id]=(counts[id] or 0)+count
				local name=type(itemLink)=="string" and itemLink:match("%[(.-)%]")
				if name then counts[name]=(counts[name] or 0)+count end
			end
		end
	end
	Character().bankMaterials={counts=counts,scannedAt=time()}
	return true
end

local function Refresh()
	if CraftRoster.ShoppingList then CraftRoster.ShoppingList:ScheduleRefresh() end
end

function Bank:ScheduleScan()
	if not self.isOpen then return end
	local snapshot=self:Snapshot()
	if snapshot then snapshot.dirty=true end
	if pending then return end
	if C_Timer and C_Timer.NewTimer then
		pending=C_Timer.NewTimer(0.1,function() pending=nil; Bank:Scan(); Refresh() end)
	else self:Scan(); Refresh() end
end

local events=CreateFrame("Frame")
for _,event in ipairs({"BANKFRAME_OPENED","BANKFRAME_CLOSED","PLAYERBANKSLOTS_CHANGED","PLAYERBANKBAGSLOTS_CHANGED","BAG_UPDATE","BAG_UPDATE_DELAYED"}) do
	pcall(events.RegisterEvent,events,event)
end
events:SetScript("OnEvent",function(_,event,bag)
	if event=="BANKFRAME_OPENED" then
		Bank.isOpen=true
		if Bank:Scan() then Refresh()
		else Bank:ScheduleScan() end -- Retry only if container data wasn't ready.
	elseif event=="BANKFRAME_CLOSED" then
		Bank.isOpen=false
		if pending then pending:Cancel(); pending=nil end
		Refresh() -- Never read closed-bank containers or overwrite the last snapshot with zeros.
	elseif Bank.isOpen then
		local first=(NUM_BAG_SLOTS or 4)+1
		if event=="PLAYERBANKSLOTS_CHANGED" or event=="PLAYERBANKBAGSLOTS_CHANGED"
			or (event=="BAG_UPDATE" and type(bag)=="number" and
				(bag==(BANK_CONTAINER or -1) or (bag>=first and bag<first+(NUM_BANKBAGSLOTS or 7)))) then
			Bank:ScheduleScan()
		end
	end
end)
