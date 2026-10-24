local _,CraftRoster=...
local Composer={}
CraftRoster.WhisperComposer=Composer
local function Normalize(name)
	if not name then return "" end
	if not name:find("-",1,true) then name=name.."-"..(GetRealmName() or "") end
	return name:lower():gsub("%s","")
end
local function Escape(text) return text:gsub("&","&amp;"):gsub("<","&lt;"):gsub(">","&gt;"):gsub('"',"&quot;") end
function Composer:Status(text) if self.frame then self.frame.Status:SetText(text) end end
function Composer:Initialize()
	if self.frame then return end
	local frame=CreateFrame("Frame","CraftRosterWhisperComposer",UIParent,BackdropTemplateMixin and "BackdropTemplate" or nil)
	self.frame=frame; frame:Hide(); frame:SetSize(480,360)
	frame:SetPoint("CENTER",UIParent,"CENTER",0,0); frame:SetFrameStrata("DIALOG")
	frame:SetMovable(true); frame:SetClampedToScreen(true); frame:EnableMouse(true); frame:RegisterForDrag("LeftButton")
	frame:SetScript("OnDragStart",frame.StartMoving)
	frame:SetScript("OnDragStop",function(self)
		self:StopMovingOrSizing()
		local point,_,_,x,y=self:GetPoint()
		CraftRosterDB.whisperComposerPosition={point=point,x=x,y=y}
	end)
	frame:SetBackdrop({bgFile="Interface\\Tooltips\\UI-Tooltip-Background",edgeFile="Interface\\Tooltips\\UI-Tooltip-Border",edgeSize=12})
	frame:SetBackdropColor(0.03,0.03,0.03,0.98)
	local position=CraftRosterDB.whisperComposerPosition
	local valid={CENTER=true,TOP=true,BOTTOM=true,LEFT=true,RIGHT=true,TOPLEFT=true,TOPRIGHT=true,BOTTOMLEFT=true,BOTTOMRIGHT=true}
	if position and valid[position.point] then frame:ClearAllPoints(); frame:SetPoint(position.point,UIParent,position.point,tonumber(position.x) or 0,tonumber(position.y) or 0) end
	frame.Title=frame:CreateFontString(nil,"OVERLAY","GameFontNormalLarge")
	frame.Title:SetPoint("TOPLEFT",14,-12); frame.Title:SetText("Craft whisper")
	CraftRoster.Theme:Window(frame,frame.Title); CraftRoster.Theme:TrackPanel(frame)
	local close=CreateFrame("Button",nil,frame,"UIPanelCloseButton")
	close:SetSize(24,24); close:SetPoint("TOPRIGHT",-3,-3); close:SetScript("OnClick",function() frame:Hide() end)
	frame.Status=frame:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
	frame.Status:SetPoint("TOPLEFT",14,-42); frame.Status:SetWidth(450); frame.Status:SetHeight(30); frame.Status:SetJustifyH("LEFT")
	local previewScroll=CreateFrame("ScrollFrame",nil,frame,"UIPanelScrollFrameTemplate")
	previewScroll:SetPoint("TOPLEFT",14,-78); previewScroll:SetPoint("TOPRIGHT",-32,-78); previewScroll:SetHeight(90)
	local preview=CreateFrame("SimpleHTML",nil,previewScroll)
	preview:SetSize(430,100); preview:SetFontObject("GameFontHighlightSmall"); previewScroll:SetScrollChild(preview)
	preview:SetScript("OnHyperlinkEnter",function(self,link)
		GameTooltip:SetOwner(self,"ANCHOR_RIGHT")
		if not pcall(GameTooltip.SetHyperlink,GameTooltip,link) then GameTooltip:SetText("Item information is loading") end
		GameTooltip:Show()
	end)
	preview:SetScript("OnHyperlinkLeave",function() GameTooltip:Hide() end)
	preview:SetScript("OnHyperlinkClick",function(_,link,text,button)
		if not text:find("|H",1,true) then
			local name=text:gsub("^%[",""):gsub("%]$","")
			text="|cffffffff|H"..link.."|h["..name.."]|h|r"
		end
		if IsShiftKeyDown and IsShiftKeyDown() and ChatEdit_InsertLink and ChatEdit_InsertLink(text) then return end
		if SetItemRef then pcall(SetItemRef,link,text,button) end
	end)
	frame.Preview=preview
	local scroll=CreateFrame("ScrollFrame",nil,frame,"UIPanelScrollFrameTemplate")
	scroll:SetPoint("TOPLEFT",14,-180); scroll:SetPoint("BOTTOMRIGHT",-32,58)
	local edit=CreateFrame("EditBox",nil,scroll)
	edit:SetMultiLine(true); edit:SetFontObject("ChatFontNormal"); edit:SetAutoFocus(false)
	edit:SetSize(430,120); edit:SetMaxLetters(6000); scroll:SetScrollChild(edit)
	edit:SetScript("OnEscapePressed",function() edit:ClearFocus() end)
	edit:SetScript("OnTextChanged",function()
		local count=edit.GetNumLines and edit:GetNumLines() or 1
		edit:SetHeight(math.max(120,count*18))
	end)
	frame.Edit=edit
	local send=CreateFrame("Button",nil,frame,"UIPanelButtonTemplate")
	send:SetSize(280,26); send:SetPoint("BOTTOMLEFT",14,14)
	send:SetScript("OnClick",function() if Composer.queue and #Composer.queue>0 then Composer:SendNext() elseif Composer.target then Composer:SendTo(Composer.target) end end)
	frame.Send=send
	local copy=CreateFrame("Button",nil,frame,"UIPanelButtonTemplate")
	copy:SetSize(150,26); copy:SetPoint("BOTTOMRIGHT",-14,14); copy:SetText("Select text to copy")
	copy:SetScript("OnClick",function() edit:SetFocus(); edit:HighlightText() end)
	frame.Copy=copy
	frame:SetScript("OnHide",function() Composer.pending=nil; Composer.queue=nil; edit:ClearFocus(); GameTooltip:Hide() end)
end
function Composer:Open(recipeID,target)
	if not CraftRosterDB.settings.enabled or not CraftRosterDB.recipes[recipeID] then return false end
	self:Initialize()
	self.recipeID,self.target=recipeID,target
	self.quantity=CraftRoster.ShoppingList:GetQuantity(recipeID)
	self.pending,self.queue=nil,nil
	self.sentText,self.sentTarget=nil,nil
	local drafts=CraftRoster.Requests:BuildWhisperDrafts(recipeID,target or "Crafter-Realm",self.quantity)
	if not drafts then return false end
	self.frame.Edit:SetText(table.concat(drafts,"\n"))
	local links={}
	for _,draft in ipairs(drafts) do
		for payload,name in draft:gmatch("|H(.-)|h%[(.-)%]|h") do links[#links+1]='<a href="'..Escape(payload)..'">['..Escape(name)..']</a>' end
	end
	self.frame.Preview:SetText("<html><body><p>"..table.concat(links," · ").."</p></body></html>")
	self.frame.Preview:SetHeight(math.max(90,#links*20))
	self:Status("Click a known crafter to send, or select the text to copy for someone outside the guild. Each line is one whisper.")
	self.frame.Send:SetText(target and ("Send to "..target) or "Choose a crafter")
	self.frame.Send:SetEnabled(target~=nil); self.frame:Show()
	return true
end
function Composer:Choose(recipeID,target)
	if self.frame and self.frame:IsShown() and self.recipeID==recipeID then return self:SendTo(target) end
end
function Composer:SendTo(target)
	if self.sentTarget==target and self.sentText==self.frame.Edit:GetText() then self:Status("This whisper was already sent. Reopen Whisper to prepare another request."); return false end
	if not CraftRosterDB.settings.enabled then self:Status("Enable CraftRoster before sending."); return false end
	local character=CraftRosterDB.characters[target]
	if not character or not character.recipes or not character.recipes[self.recipeID] then self:Status("Choose a player known to have this recipe, or copy the text."); return false end
	if self.quantity~=CraftRoster.ShoppingList:GetQuantity(self.recipeID) then
		self:Open(self.recipeID,target); self:Status("Craft quantity changed. Review the updated text and click Send."); return false
	end
	local parts={}
	local limit=math.max(80,255-#("/w "..target.." "))
	for line in self.frame.Edit:GetText():gmatch("[^\r\n]+") do
		if #line>limit or line:find("%z") then self:Status("One line is too long. Shorten it or add a line break without splitting an item link."); return false end
		parts[#parts+1]=line
	end
	if #parts==0 or #parts>32 then self:Status("Enter 1–32 message lines before sending."); return false end
	self.target=target
	self.pending={recipeID=self.recipeID,target=target,quantity=self.quantity,parts=parts}
	CraftRoster.Requests.composerDeferred=false
	CraftRoster.Requests:WhisperPlayer(self.recipeID,target)
	if self.pending and not CraftRoster.Requests.composerDeferred then
		self.pending=nil; self:Status("Request could not be prepared. Resolve any active or unconfirmed trade before retrying."); return false
	end
	return true
end
function Composer:Handles(recipeID,target)
	return self.pending and self.pending.recipeID==recipeID and Normalize(self.pending.target)==Normalize(target)
end
function Composer:OnPrepared(recipeID,target,quantity)
	local data=self.pending
	if not data or data.recipeID~=recipeID or Normalize(data.target)~=Normalize(target) then return end
	self.pending=nil
	if data.quantity~=quantity then self:Open(recipeID,target); self:Status("An earlier quantity was resumed. Review its text before sending."); return end
	self.queue=data.parts; self.target=target
	self:SendNext()
end
function Composer:SendNext()
	if not self.queue or #self.queue==0 then return false end
	local message=self.queue[1]
	if not CraftRosterDB.settings.enabled then self:Status("Enable CraftRoster before sending."); return false end
	if type(SendChatMessage)~="function" then
		CraftRoster.Requests.whisperDrafts=self.queue; CraftRoster.Requests.whisperTarget=self.target
		local ok,opened=pcall(CraftRoster.Requests.NextWhisper,CraftRoster.Requests)
		if not ok or not opened then
			-- A missing or broken chat editor must not discard the only copy
			-- of the request. Keep the composer queue for a manual retry.
			CraftRoster.Requests.whisperDrafts=nil; CraftRoster.Requests.whisperTarget=nil
			self:Status("Whisper draft could not open. Message kept for retry or copying.")
			return false
		end
		self.queue=nil
		self:Status("Whisper draft opened. Press Enter to send; /crwhisper opens any remaining lines.")
		return false
	end
	local ok,result=pcall(SendChatMessage,message,"WHISPER",nil,self.target)
	if not ok or result==false then self:Status("Whisper could not send. The message is kept for retry or copying."); return false end
	table.remove(self.queue,1)
	if #self.queue==0 then self.sentText,self.sentTarget=self.frame.Edit:GetText(),self.target end
	self:Status(#self.queue>0 and "First line sent. Click Send next for the remaining material links." or ("Whisper sent to "..self.target..". Delivery depends on the player's online status."))
	self.frame.Send:SetText(#self.queue>0 and ("Send next · "..#self.queue.." left") or "Sent")
	self.frame.Send:SetEnabled(#self.queue>0)
	return true
end
function Composer:CancelRequests(cancelled)
	if not self.frame or not self.frame:IsShown() then return end
	for _,request in ipairs(CraftRosterDB.requests or {}) do
		if cancelled[request.id] and request.recipeID==self.recipeID and (not self.target or Normalize(request.target)==Normalize(self.target)) then
			self.pending,self.queue=nil,nil; self.frame.Send:SetEnabled(false); self:Status("Request cancelled. Reopen Whisper to prepare a new request."); return
		end
	end
end

-- Insertion edits the draft only; sending remains an explicit player action.
function Composer:InsertMaterialLink(link)
 if not self.frame or not self.frame:IsShown() then return false end
 self.queue=nil; self.pending=nil; self.sentText=nil; self.sentTarget=nil
 local edit=self.frame.Edit
 if edit.Insert then edit:Insert(" "..link) else edit:SetText((edit:GetText() or "").." "..link) end
 self.frame.Send:SetText(self.target and ("Whisper "..self.target) or "Select a crafter")
 if self.target then self.frame.Send:Enable() end
 return true
end
