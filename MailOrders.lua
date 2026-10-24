local ADDON_NAME, CraftRoster = ...
local MailOrders = {}
CraftRoster.MailOrders = MailOrders

local MAX_BODY, MAX_RECEIPTS, MAX_RECEIPT_BYTES = 16384, 1000, 1024*1024
local originalGetInboxText
local reading = false
local warned = {}

local function Trim(value) return value:match("^%s*(.-)%s*$") end
local function Normalize(name)
	if type(name)~="string" or name=="" then return end
	name=Trim(name)
	local player,realm=name:match("^([^%-]+)%-(.+)$")
	if player then name=player .. "-" .. realm:gsub("%s", "") end
	if not name:find("-",1,true) then name=name .. "-" .. (GetRealmName() or "") end
	return name:lower():gsub("%s", "")
end
local function SayOnce(key,message)
	if warned[key] then return end
	warned[key]=true
	print("|cffffd100CraftRoster|r: " .. message)
end
local function Receipts()
	CraftRosterDB.mailOrderReceipts=CraftRosterDB.mailOrderReceipts or {}
	local key=Normalize(UnitName("player"))
	CraftRosterDB.mailOrderReceipts[key]=CraftRosterDB.mailOrderReceipts[key] or {}
	return CraftRosterDB.mailOrderReceipts[key]
end
local function Fingerprint(signature)
	-- Both multiplications remain exactly representable by Lua 5.1 doubles.
	local first,second=5381,7919
	for index=1,#signature do
		local byte=signature:byte(index)
		first=(first*33+byte)%2147483647
		second=(second*65599+byte)%2147483629
	end
	return ("%d:%d:%d"):format(first,second,#signature)
end
local function OpenIndex()
	if not OpenMailFrame or type(OpenMailFrame.IsShown)~="function" then return end
	local ok,shown=pcall(OpenMailFrame.IsShown,OpenMailFrame)
	if not ok or not shown then return end
	local function valid(index)
		return type(index)=="number" and index>0 and index==math.floor(index)
	end
	-- Some clients leave InboxFrame.openMailID at 0 while the visible reader
	-- tracks its actual message on OpenMailFrame. Lua treats 0 as truthy.
	local index=InboxFrame and InboxFrame.openMailID
	if not valid(index) then index=OpenMailFrame.openMailID end
	if valid(index) then return index end
end
local function PlainName(value)
	local itemID=tonumber(value:match("|Hitem:(%d+)"))
	return Trim(value:match("|h%[(.-)%]|h") or value),itemID
end
local function Parse(subject,body)
	local requested=subject:match("^(.-) craft requested$")
	if not requested or requested=="" then return end
	local quantity,subjectName=requested:match("^(%d+) crafts of (.+)$")
	local explicitQuantity=quantity~=nil
	quantity=tonumber(quantity) or 1
	subjectName=Trim(subjectName or requested)
	local bodyName,bodyQuantity
	for line in body:gmatch("[^\r\n]+") do
		line=Trim(line)
		local name=line:match("^Requested item:%s*(.-)%s*$")
		local count=line:match("^Number of crafts:%s*(.-)%s*$")
		if name then
			if name=="" or (bodyName and bodyName~=name) then return false,"conflicting item names" end
			bodyName=name
		end
		if count then
			local value=tonumber(count)
			if not count:match("^%d+$") or not value or (bodyQuantity and bodyQuantity~=value) then return false,"invalid craft quantity" end
			bodyQuantity=value
		end
	end
	if explicitQuantity and bodyQuantity and bodyQuantity~=quantity then return false,"conflicting craft quantities" end
	quantity=bodyQuantity or quantity
	if quantity<1 or quantity>999 or quantity~=math.floor(quantity) then return false,"invalid craft quantity" end
	local name,itemID=PlainName(bodyName or subjectName)
	local titleName=PlainName(subjectName)
	-- Generated subjects may be truncated to fit the mail subject limit. The
	-- complete body item name is authoritative, but an unrelated title is rejected.
	if bodyName and name:lower():sub(1,#titleName)~=titleName:lower() then return false,"subject and body request different items" end
	if name=="" then return false,"missing item name" end
	return {name=name,itemID=itemID,quantity=quantity}
end
local function MatchRecipe(parsed)
	local own=CraftRosterDB.characters and CraftRosterDB.characters[UnitName("player") .. "-" .. (GetRealmName() or "")]
	local matches,known={},{}
	for id,recipe in pairs(CraftRosterDB.recipes or {}) do
		local matchesItem=parsed.itemID and CraftRoster.RecipeSources and CraftRoster.RecipeSources:GetOutputItemID(id)==parsed.itemID
		local matchesName=not parsed.itemID and type(recipe.name)=="string" and recipe.name:lower()==parsed.name:lower()
		if matchesItem or matchesName then
			matches[#matches+1]=id
			if own and own.recipes and own.recipes[id]~=nil then known[#known+1]=id end
		end
	end
	if #known==1 then return known[1] end
	if #known>1 or #matches>1 then return nil,"ambiguous" end
	if #matches==1 then return matches[1] end
	return nil,"unknown"
end

-- Reads only the mail the player has already opened. It never scans the inbox,
-- takes attachments, sends mail, or invokes any work-order crafting action.
function MailOrders:Capture(index)
	if reading or not CraftRosterDB or not CraftRosterDB.settings or not CraftRosterDB.settings.enabled then return end
	if type(index)~="number" or index~=OpenIndex() or not CraftRoster.WorkOrders then return end
	if type(GetInboxHeaderInfo)~="function" then return end
	local read=originalGetInboxText or GetInboxText
	if type(read)~="function" then return end
	reading=true
	local headerOK,_,_,sender,subject=pcall(GetInboxHeaderInfo,index)
	local bodyOK,body=pcall(read,index)
	reading=false
	if not headerOK or not bodyOK or type(sender)~="string" or type(subject)~="string" or type(body)~="string" then return end
	if #sender>100 or #subject>256 or #body>MAX_BODY then return end
	local normalizedSender=Normalize(sender)
	if not normalizedSender or normalizedSender==Normalize(UnitName("player")) then return end
	local signature=normalizedSender .. "\031" .. subject .. "\031" .. body
	local fingerprint=Fingerprint(signature)
	local parsed,problem=Parse(subject,body)
	if not parsed then
		if problem then SayOnce(fingerprint,"Crafting mail could not be recorded (" .. problem .. "). Add the selected recipe order manually.") end
		return
	end
	local receipts=Receipts()
	-- A second full signature check prevents an accidental hash collision from
	-- suppressing a different mail. Identical sender/subject/body copies are
	-- inherently ambiguous without a native mail ID; add intentional copies manually.
	local key=fingerprint
	local collision=0
	while receipts[key] and receipts[key].signature~=signature do collision=collision+1; key=fingerprint .. ":" .. collision end
	if receipts[key] then
		return CraftRoster.WorkOrders:Find(receipts[key].orderID)
	end
	local recipeID,reason=MatchRecipe(parsed)
	if not recipeID then
		SayOnce(key,"The mailed craft is " .. reason .. ". Select its recipe and add a work order manually.")
		return
	end
	local count,signatureBytes=0,0
	for _,receipt in pairs(receipts) do
		count=count+1
		if type(receipt)=="table" and type(receipt.signature)=="string" then signatureBytes=signatureBytes+#receipt.signature end
	end
	if count>=MAX_RECEIPTS or signatureBytes+#signature>MAX_RECEIPT_BYTES then
		SayOnce("receipts-full","Mail receipt tracking reached its storage limit. Add this work order manually; old receipts were kept to prevent duplicates.")
		return
	end
	local order=CraftRoster.WorkOrders:Add(sender,recipeID,parsed.quantity,nil,"mail")
	if not order then SayOnce(key,"The crafting mail could not be added. Check the customer name and work-order capacity, then add it manually."); return end
	order.mailFingerprint=key
	order.mailSubject=subject
	receipts[key]={signature=signature,orderID=order.id,at=time()}
	return order
end
function MailOrders:CaptureOpened()
	local index=OpenIndex()
	if index then return self:Capture(index) end
end
function MailOrders:InstallHooks()
	if not self.textHooked and type(GetInboxText)=="function" and type(hooksecurefunc)=="function" then
		local read=GetInboxText
		local ok=pcall(hooksecurefunc,"GetInboxText",function(index)
			if not reading then MailOrders:Capture(index) end
		end)
		if ok then originalGetInboxText=read; self.textHooked=true end
	end
	if OpenMailFrame and self.hookedFrame~=OpenMailFrame and type(OpenMailFrame.HookScript)=="function" then
		OpenMailFrame:HookScript("OnShow",function() MailOrders:CaptureOpened() end)
		self.hookedFrame=OpenMailFrame
	end
end
local events=CreateFrame("Frame")
for _,event in ipairs({"ADDON_LOADED","MAIL_SHOW","MAIL_INBOX_UPDATE"}) do events:RegisterEvent(event) end
events:SetScript("OnEvent",function(_,event)
	MailOrders:InstallHooks()
	if event=="MAIL_INBOX_UPDATE" then MailOrders:CaptureOpened() end
end)
