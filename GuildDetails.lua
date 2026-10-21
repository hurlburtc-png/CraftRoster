local ADDON_NAME,CraftRoster=...
local Details={}
CraftRoster.GuildDetails=Details
local PREFIX="CRDETAILS"
local queue,receiving,requested,responded={}, {}, {}, {}
local running,sequence=false,0
local function OwnKey() return UnitName("player").."-"..(GetRealmName() or "") end
local function Normalize(name)
	if type(name)~="string" or #name>100 or name=="" then return end
	if not name:find("-",1,true) then name=name.."-"..(GetRealmName() or "") end
	return name:lower():gsub("%s","")
end
local function Encode(text) return tostring(text or ""):gsub("[%%:;,|]",function(c) return ("%%%02X"):format(c:byte()) end) end
local function Decode(text) return text:gsub("%%(%x%x)",function(h) return string.char(tonumber(h,16)) end) end
local function Send(message)
	if not CraftRosterDB or not CraftRosterDB.settings.enabled or (IsInGuild and not IsInGuild()) then return false end
	if C_ChatInfo and ((C_ChatInfo.AreOutgoingAddonChatMessagesRestricted and C_ChatInfo.AreOutgoingAddonChatMessagesRestricted()) or (C_ChatInfo.InChatMessagingLockdown and C_ChatInfo.InChatMessagingLockdown())) then return false end
	local fn=C_ChatInfo and C_ChatInfo.SendAddonMessage or SendAddonMessage
	if not fn or #message>255 then return false end
	local ok,result=pcall(fn,PREFIX,message,"GUILD")
	local success=Enum and Enum.SendAddonMessageResult and Enum.SendAddonMessageResult.Success
	return ok and result~=false and (result==nil or result==true or not success or result==success)
end
local function Pump()
	local message=table.remove(queue,1)
	if not message then running=false; return end
	if not Send(message) then
		queue={}; running=false
		print("|cffffd100CraftRoster|r: guild details could not send. Use Refresh to retry.")
		return
	end
	if #queue==0 then running=false
	elseif C_Timer and C_Timer.NewTimer then C_Timer.NewTimer(0.2,Pump)
	else queue={}; running=false end
end
function Details:Queue(body)
	if #body>6400 then return false end
	local total=math.ceil(#body/200)
	if total>1 and not (C_Timer and C_Timer.NewTimer) then return false end
	if #queue+total>128 then return false end
	sequence=sequence+1
	local id=time().."-"..sequence
	for index=1,total do queue[#queue+1]="P:"..id..":"..index..":"..total..":"..body:sub((index-1)*200+1,index*200) end
	if not running then running=true; Pump() end
	return true
end
function Details:SendProfile()
	local character=CraftRosterDB.characters[OwnKey()]
	if not character or character.note==nil then return end
	return self:Queue("N:"..Encode(OwnKey())..":"..Encode(CraftRoster.MemberNotes:Clean(character.note)))
end
function Details:RequestMaterials(recipeID,target)
	if not target or not CraftRosterDB.settings.enabled then return false end
	local identity=Normalize(target)
	local character=CraftRosterDB.characters[target]
	if not identity or identity==Normalize(OwnKey()) or not character or not character.recipes or not character.recipes[recipeID] then return false end
	local saved=CraftRosterDB.recipes[recipeID]
	if saved and type(saved.materials)=="table" and #saved.materials>0 then return false end
	local cached=saved and saved.peerSchematics and saved.peerSchematics[identity]
	if cached and time()-cached.at<300 then return false end
	local key=identity..":"..recipeID
	if requested[key] and time()-requested[key]<30 then return false end
	local count=0
	for old,at in pairs(requested) do if time()-at>60 then requested[old]=nil else count=count+1 end end
	if count>=100 then return false end
	if not Send("Q:"..recipeID..":"..Encode(target)) then return false end
	requested[key]=time(); return true
end
function Details:GetMaterials(recipeID)
	local saved=CraftRosterDB.recipes[recipeID]
	local peers=saved and saved.peerSchematics
	if not peers then return end
	local directory=CraftRoster.Directory
	local target=directory and directory.selectedRecipe and directory.selectedRecipe.id==recipeID and Normalize(directory.selectedCrafter)
	if target and peers[target] then return peers[target].materials end
	local newest
	for _,data in pairs(peers) do if not newest or data.at>newest.at then newest=data end end
	return newest and newest.materials
end
local function ValidInteger(value,max)
	value=tonumber(value)
	return value and value>=0 and value<=max and value==math.floor(value) and value or nil
end
local function Handle(body,sender)
	local owner,note=body:match("^N:([^:]+):(.*)$")
	if owner then
		owner=Decode(owner)
		if Normalize(owner)~=Normalize(sender) or Normalize(sender)==Normalize(OwnKey()) then return end
		note=Decode(note); if #note>240 then return end
		local key=sender:find("-",1,true) and sender or sender.."-"..(GetRealmName() or "")
		local character=CraftRosterDB.characters[key] or {recipes={},professions={}}
		character.note=CraftRoster.MemberNotes:Clean(note); CraftRosterDB.characters[key]=character
		if CraftRoster.Directory then CraftRoster.Directory:RefreshIfVisible() end
		return
	end
	local target,id,output,profession,materials=body:match("^S:([^:]+):(%d+):(%d+):(%d+):(.*)$")
	id=tonumber(id)
	if not id or Normalize(Decode(target))~=Normalize(OwnKey()) then return end
	local requestKey=Normalize(sender)..":"..id
	if not requested[requestKey] or time()-requested[requestKey]>60 then return end
	local character=CraftRosterDB.characters[sender] or CraftRosterDB.characters[sender.."-"..(GetRealmName() or "")]
	if not character or not character.recipes or not character.recipes[id] then return end
	output,profession=ValidInteger(output,10000000),ValidInteger(profession,10000)
	if not output or not profession then return end
	local parsed={}
	for entry in materials:gmatch("[^;]+") do
		local itemID,count,name=entry:match("^(%d+),(%d+),(.+)$")
		itemID,count=ValidInteger(itemID,10000000),ValidInteger(count,1000000)
		if not itemID or not count or count<1 or #parsed>=32 or not name then return end
		name=Decode(name)
		if #name>160 or #name==0 or name:find("[%c|]") then return end
		parsed[#parsed+1]={itemID=itemID>0 and itemID or nil,count=count,name=name}
	end
	if #parsed==0 then return end
	local saved=CraftRosterDB.recipes[id] or {}
	saved.peerSchematics=saved.peerSchematics or {}
	local peers,count=saved.peerSchematics,0
	for _ in pairs(peers) do count=count+1 end
	if count>=8 and not peers[Normalize(sender)] then
		local oldest
		for key,value in pairs(peers) do if not oldest or value.at<peers[oldest].at then oldest=key end end
		peers[oldest]=nil
	end
	peers[Normalize(sender)]={materials=parsed,at=time(),outputItemID=output,professionID=profession,source="Guild crafter scan"}
	if not saved.itemLink and output>0 then saved.itemLink="item:"..output end
	if not saved.professionID and profession>0 then saved.professionID=profession end
	CraftRosterDB.recipes[id]=saved
	requested[requestKey]=nil
	if CraftRoster.ShoppingList then CraftRoster.ShoppingList:ScheduleRefresh() end
	if CraftRoster.Directory then CraftRoster.Directory:RefreshDetails() end
end
local function Answer(recipeID,target,sender)
	if Normalize(Decode(target))~=Normalize(OwnKey()) or Normalize(sender)==Normalize(OwnKey()) then return end
	local key=Normalize(sender)..":"..recipeID
	if responded[key] and time()-responded[key]<10 then return end
	local n=0; for old,at in pairs(responded) do if time()-at>60 then responded[old]=nil else n=n+1 end end
	if n>=100 then return end
	local character=CraftRosterDB.characters[OwnKey()]
	local known=character and character.recipes and character.recipes[recipeID]
	local saved=CraftRosterDB.recipes[recipeID]
	if not known or type(known.materials)~="table" or not saved or #known.materials==0 or #known.materials>32 then return end
	local rows={}
	for _,material in ipairs(known.materials) do
		if not ValidInteger(material.count,1000000) or material.count<1 or type(material.name)~="string" or #material.name>160 or material.name:find("[%c|]") then return end
		rows[#rows+1]=(material.itemID or 0)..","..material.count..","..Encode(material.name)
	end
	if Details:Queue("S:"..Encode(sender)..":"..recipeID..":"..(known.outputItemID or 0)..":"..(saved.professionID or 0)..":"..table.concat(rows,";")) then responded[key]=time() end
end
local events=CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED"); events:RegisterEvent("CHAT_MSG_ADDON")
events:SetScript("OnEvent",function(_,event,prefix,message,channel,sender)
	if event=="ADDON_LOADED" and prefix==ADDON_NAME then
		local register=C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix or RegisterAddonMessagePrefix
		if register then register(PREFIX) end
		return
	end
	if event~="CHAT_MSG_ADDON" or channel~="GUILD" or not CraftRosterDB or not CraftRosterDB.settings.enabled or not Normalize(sender) or type(message)~="string" or #message>255 then return end
	if prefix=="CRAFTROSTER" and message=="REQ" then Details:SendProfile(); return end
	if prefix~=PREFIX then return end
	local id,target=message:match("^Q:(%d+):([^:]+)$")
	if id then Answer(tonumber(id),target,sender); return end
	local transfer,index,total,chunk=message:match("^P:([%d%-]+):(%d+):(%d+):(.*)$")
	index,total=tonumber(index),tonumber(total)
	if not transfer or #transfer>32 or not index or not total or total<1 or total>32 or index<1 or index>total or #chunk>200 then return end
	local n=0
	for key,value in pairs(receiving) do if time()-value.at>60 then receiving[key]=nil else n=n+1 end end
	local data=receiving[sender]
	if not data or data.id~=transfer then
		if not data and n>=8 then return end
		data={id=transfer,parts={},count=0,total=total,at=time()}; receiving[sender]=data
	end
	if data.total~=total then return end
	if not data.parts[index] then data.parts[index]=chunk; data.count=data.count+1 end
	if data.count==total then receiving[sender]=nil; Handle(table.concat(data.parts),sender) end
end)
