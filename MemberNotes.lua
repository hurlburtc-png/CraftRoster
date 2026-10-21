local _,CraftRoster=...
local Notes={}
CraftRoster.MemberNotes=Notes
local function OwnKey() return UnitName("player").."-"..(GetRealmName() or "") end
function Notes:Clean(text)
	if type(text)~="string" then return "" end
	text=text:gsub("|",""):gsub("[%c]"," "):match("^%s*(.-)%s*$")
	if #text>240 then
		text=text:sub(1,240)
		while #text>0 do
			local start=#text
			while start>1 and text:byte(start)>=128 and text:byte(start)<192 do start=start-1 end
			local lead=text:byte(start)
			local length=lead>=240 and 4 or lead>=224 and 3 or lead>=192 and 2 or 1
			if #text-start+1>=length then break end
			text=text:sub(1,start-1)
		end
	end
	return text
end
function Notes:Get(key)
	local character=CraftRosterDB.characters[key]
	local private=CraftRosterDB.memberNotes and CraftRosterDB.memberNotes[key]
	return character and character.note or "",private or ""
end
function Notes:Save(key,text,published)
	text=self:Clean(text)
	if published then
		if key~=OwnKey() then return false end
		CraftRosterDB.characters[key].note=text
		if CraftRoster.GuildDetails then CraftRoster.GuildDetails:SendProfile() end
	else
		if not CraftRosterDB.characters[key] then return false end
		CraftRosterDB.memberNotes=CraftRosterDB.memberNotes or {}
		CraftRosterDB.memberNotes[key]=text~="" and text or nil
	end
	if CraftRoster.Directory then CraftRoster.Directory:RefreshIfVisible() end
	return true
end
function Notes:Edit(key,published)
	key=key or OwnKey()
	local public,private=self:Get(key)
	StaticPopup_Show("CRAFTROSTER_MEMBER_NOTE",key,published and "Shared with guild" or "Private; only saved on this account",{key=key,published=published,text=published and public or private})
end
StaticPopupDialogs.CRAFTROSTER_MEMBER_NOTE={
	text="Note for %s\n%s",button1="Save",button2="Cancel",hasEditBox=true,timeout=0,whileDead=true,hideOnEscape=true,
	OnShow=function(dialog)
		local edit=dialog.editBox or dialog.EditBox
		edit:SetNumeric(false); edit:SetMaxLetters(240); edit:SetText(dialog.data.text or ""); edit:SetFocus()
	end,
	OnAccept=function(dialog)
		Notes:Save(dialog.data.key,(dialog.editBox or dialog.EditBox):GetText(),dialog.data.published)
	end,
}
