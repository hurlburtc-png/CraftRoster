local ADDON_NAME, CraftRoster = ...

local Directory = {}
CraftRoster.Directory = Directory

local DEFAULT_WINDOW = { width = 760, height = 500, x = 0, y = 0 }
local MIN_WIDTH, MIN_HEIGHT = 620, 420

local PROFESSION_ICONS = {
	["First Aid"] = "Interface\\Icons\\Spell_Holy_SealOfSacrifice",
	Alchemy = "Interface\\Icons\\Trade_Alchemy",
	Blacksmithing = "Interface\\Icons\\Trade_BlackSmithing",
	Enchanting = "Interface\\Icons\\Trade_Engraving",
	Engineering = "Interface\\Icons\\Trade_Engineering",
	Herbalism = "Interface\\Icons\\Trade_Herbalism",
	Inscription = "Interface\\\\Icons\\\\trade_inscription",
	Jewelcrafting = "Interface\\Icons\\Trade_Jewelcrafting",
	Leatherworking = "Interface\\Icons\\Trade_Leatherworking",
	Mining = "Interface\\Icons\\Trade_Mining",
	Skinning = "Interface\\Icons\\inv_misc_pelt_wolf_01",
	Tailoring = "Interface\\Icons\\Trade_Tailoring",
	Cooking = "Interface\\Icons\\Trade_Cooking",
	Fishing = "Interface\\Icons\\Trade_Fishing",
	Archaeology = "Interface\\Icons\\Trade_Archaeology",
}

local CLASS_COLORS = {
	WARRIOR = "C79C6E", PALADIN = "F58CBA", HUNTER = "ABD473",
	ROGUE = "FFF569", PRIEST = "FFFFFF", DEATHKNIGHT = "C41F3B",
	SHAMAN = "0070DE", MAGE = "69CCF0", WARLOCK = "9482C9",
	MONK = "00FF96", DRUID = "FF7D0A", DEMONHUNTER = "A330C9",
	EVOKER = "33937F",
}

local SEARCH_WORD_ALIASES = {
	wrist = { "bracer" },
	bracer = { "bracer" },
	chest = { "chest", "chestpiece", "robe" },
	hands = { "gloves", "gauntlets" },
	gloves = { "gloves" },
	gauntlets = { "gauntlets" },
	feet = { "boots" },
	boots = { "boots" },
	legs = { "leg" },
	leg = { "leg" },
	weapon = { "weapon" },
	mail = { "mail" },
}

local SEARCH_PHRASE_ALIASES = {
	["mail chest"] = { "mail chest" },
	["mail chest piece"] = { "mail chest" },
	["wrist enchant"] = { "bracer" },
	["bracer enchant"] = { "bracer" },
}

local SORT_MODES = { "name", "crafters", "profession" }
local SORT_LABELS = {
	name = "Sort: Name",
	crafters = "Sort: Crafters",
	profession = "Sort: Profession",
}

local sortMode = "name"

local function GetSearchTerms(search)
	local terms = { search }

	for phrase, expansions in pairs(SEARCH_PHRASE_ALIASES) do
		if search:find(phrase, 1, true) then
			for _, expansion in ipairs(expansions) do
				table.insert(terms, expansion)
			end
		end
	end

	for word in search:gmatch("%a+") do
		local expansions = SEARCH_WORD_ALIASES[word]
		if expansions then
			for _, expansion in ipairs(expansions) do
				table.insert(terms, expansion)
			end
		end
	end

	return terms
end

local function DebouncedRefresh(method)
	local timer
	return function()
		if timer then timer:Cancel(); timer = nil end
		if C_Timer and C_Timer.NewTimer then
			timer = C_Timer.NewTimer(0.25, function()
				timer = nil
				Directory[method](Directory)
			end)
		else
			Directory[method](Directory)
		end
	end
end

local rowPools = {}
local onlineByName = {}

local function GetCharacterKey()
	return UnitName("player") .. "-" .. (GetRealmName() or "")
end

local function GetProfessionIcon(profession)
	return PROFESSION_ICONS[profession] or "Interface\\Icons\\Trade_Tailoring"
end

local function GetRaceGenderAtlas(character)
	if not character or not character.raceFile or not character.gender then return nil end
	local gender = character.gender == 3 and "female" or "male"
	local atlas = "raceicon-" .. character.raceFile:lower() .. "-" .. gender
	if C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(atlas) then return atlas end
	return nil
end

local function GetColoredName(characterKey, character, disabled)
	local name = characterKey:gsub("%-.+$", "")
	local color = CLASS_COLORS[character and character.class] or "FFFFFF"
	if disabled then color = "7F7F7F" end
	return "|cff" .. color .. name .. "|r"
end

local function GetRecipeName(recipeID)
	local recipe = CraftRosterDB.recipes and CraftRosterDB.recipes[recipeID]
	return recipe and recipe.name or ("Recipe " .. tostring(recipeID))
end

local function NormalizeCharacter(name)
	if not name:find("-", 1, true) then name = name .. "-" .. (GetRealmName() or "") end
	return (name:lower():gsub("%s", ""))
end

local function IsCharacterOnline(characterKey)
	local key = NormalizeCharacter(characterKey)
	return key == NormalizeCharacter(GetCharacterKey()) or onlineByName[key] == true
end

local function GetProfessionTotals(character)
	local recipeTotals = {}

	for recipeID in pairs(character.recipes or {}) do
		local saved = CraftRosterDB.recipes[recipeID]
		local profession = saved and saved.profession or "Unknown"
		recipeTotals[profession] = (recipeTotals[profession] or 0) + 1
	end

	local parts = {}

	for profession, data in pairs(character.professions or {}) do
		local count = recipeTotals[profession] or 0
		table.insert(parts, ("%s %d (%d recipe%s)"):format(
			profession, data.skill or 0, count, count == 1 and "" or "s"
		))
	end

	for profession, count in pairs(recipeTotals) do
		if not (character.professions and character.professions[profession]) then
			table.insert(parts, ("%s (%d recipe%s)"):format(
				profession, count, count == 1 and "" or "s"
			))
		end
	end

	table.sort(parts)
	return table.concat(parts, " · ")
end

function Directory:InvalidateIndex()
	self.recipeIndex = nil
	self.professionCache = nil
	if not self.frame or not self.frame:IsShown() then return end
	if C_Timer and C_Timer.NewTimer then
		if self.refreshTimer then return end
		self.refreshTimer = C_Timer.NewTimer(0.05, function()
			self.refreshTimer = nil
			self:RefreshIfVisible()
		end)
	else self:RefreshIfVisible() end
end

local function BuildRecipeIndex()
	if CraftRoster.RecipeSources then CraftRoster.RecipeSources:SeedCatalog() end
	local index = {}

	for characterKey, character in pairs(CraftRosterDB.characters or {}) do
		for recipeID in pairs(character.recipes or {}) do
			local saved = CraftRosterDB.recipes[recipeID] or {}
			local profession = saved.profession or "Unknown"
			local recipe = index[recipeID]

			if not recipe then
				recipe = {
					id = recipeID,
					name = saved.name or GetRecipeName(recipeID),
					searchName = (saved.name or GetRecipeName(recipeID)):lower(),
					profession = profession,
					icon = (CraftRoster.RecipeSources and CraftRoster.RecipeSources:GetRecipeIcon(recipeID, GetProfessionIcon(profession),true)) or GetProfessionIcon(profession),
					crafters = {},
				}
				index[recipeID] = recipe
			end

			table.insert(recipe.crafters, characterKey)
		end
	end

	-- Include catalogue recipes even when no saved character knows them.
	for recipeID, saved in pairs(CraftRosterDB.recipes or {}) do
		if not index[recipeID] then
			local profession = saved.profession or "Unknown"
			index[recipeID] = { id = recipeID, name = saved.name or GetRecipeName(recipeID),
				searchName = (saved.name or GetRecipeName(recipeID)):lower(), profession = profession,
				icon = (CraftRoster.RecipeSources and CraftRoster.RecipeSources:GetRecipeIcon(recipeID, GetProfessionIcon(profession),true)) or GetProfessionIcon(profession), crafters = {} }
		end
	end

	local recipes = {}
	for _, recipe in pairs(index) do table.insert(recipes, recipe) end

	return recipes
end

local function GetRecipeIndex()
	if not Directory.recipeIndex then
		Directory.recipeIndex = BuildRecipeIndex()
	end
	return Directory.recipeIndex
end

local function FullItemLink(itemID,name,existing)
	if type(existing)=="string" and existing:find("|Hitem:",1,true) then return existing end
	local getInfo=C_Item and C_Item.GetItemInfo or GetItemInfo
	if itemID and getInfo then
		local ok,itemName,link=pcall(getInfo,itemID)
		if ok and type(link)=="string" and link:find("|Hitem:",1,true) then return link end
		if ok and type(itemName)=="string" then name=itemName end
	end
	if itemID then return "|cffffffff|Hitem:"..itemID..":0:0:0:0:0:0:0|h["..(name or ("Item "..itemID)).."]|h|r" end
end
function Directory:GetSearchLinks(recipeID)
	local saved=CraftRosterDB.recipes[recipeID]
	if not saved then return end
	local spell="|cff71d5ff|Hspell:"..recipeID.."|h["..(saved.name or ("Recipe "..recipeID)).."]|h|r"
	local data=CraftRoster.RecipeSources and CraftRoster.RecipeSources:Get(recipeID)
	local recipeLink=data and data.itemID and FullItemLink(data.itemID,data.name,data.link) or spell
	local outputID=CraftRoster.RecipeSources and CraftRoster.RecipeSources:GetOutputItemID(recipeID)
	local output=FullItemLink(outputID,saved.name,saved.itemLink) or spell
	return {recipe=recipeLink,craft=output,hasRecipeItem=data and data.itemID~=nil,hasOutputItem=outputID~=nil}
end
StaticPopupDialogs.CRAFTROSTER_COPY_LINK={
	text="Copy this WoW link (Ctrl+C). Paste into chat as needed.",button1="Close",hasEditBox=true,timeout=0,whileDead=true,hideOnEscape=true,
	OnShow=function(self)
		local edit=self.editBox or self.EditBox
		edit:SetNumeric(false); edit:SetMaxLetters(0); edit:SetText(self.data or ""); edit:HighlightText(); edit:SetFocus()
	end,
}
local function ResolveLink(button)
	local links=button.recipeID and Directory:GetSearchLinks(button.recipeID)
	return links and links[button.linkKind]
end
local function LinkTooltip(button)
	local link=ResolveLink(button)
	if not link then return end
	GameTooltip:SetOwner(button,"ANCHOR_RIGHT")
	local ok=pcall(GameTooltip.SetHyperlink,GameTooltip,link)
	if not ok then
		local saved=CraftRosterDB.recipes[button.recipeID] or {}
		GameTooltip:SetText(saved.name or "Item information")
	end
	GameTooltip:AddLine((not ok and "Tooltip unavailable; open the profession and try again. " or "") .. "Click: inspect · Shift-click: chat · Right-click: copy",1,1,1,true)
	GameTooltip:Show()
end
local function UpdateLinkDisplay(button)
	local link=ResolveLink(button)
	if not link then return end
	local itemID=tonumber(link:match("|Hitem:(%d+)"))
	local getIcon=C_Item and C_Item.GetItemIconByID or GetItemIcon
	local icon
	if itemID and type(getIcon)=="function" then
		local ok,value=pcall(getIcon,itemID)
		if ok then icon=value end
	end
	local saved=CraftRosterDB.recipes[button.recipeID] or {}
	if not icon and button.linkKind=="recipe" and itemID then
		local data=CraftRoster.RecipeSources and CraftRoster.RecipeSources:Get(button.recipeID)
		icon=data and data.icon or "Interface\\Icons\\INV_Scroll_03"
	end
	if not icon and CraftRoster.RecipeSources then icon=CraftRoster.RecipeSources:GetRecipeIcon(button.recipeID,GetProfessionIcon(saved.profession)) end
	button:SetText("|T" .. tostring(icon or GetProfessionIcon(saved.profession)) .. ":16:16|t " .. link)
end
local function CreateRecipeLinkButton(parent,kind)
	local button=CreateFrame("Button",nil,parent)
	button.linkKind=kind; button:SetSize(100,18); button:RegisterForClicks("LeftButtonUp","RightButtonUp")
	local label=button:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
	label:SetPoint("TOPLEFT",0,0); label:SetPoint("BOTTOMRIGHT",0,0)
	label:SetJustifyH("LEFT"); label:SetWordWrap(false)
	button:SetFontString(label)
	button:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
	button:SetScript("OnEnter",LinkTooltip); button:SetScript("OnLeave",function() GameTooltip:Hide() end)
	button:SetScript("OnClick",function(self,mouseButton)
		local link=ResolveLink(self)
		if not link then return end
		if mouseButton=="RightButton" then StaticPopup_Show("CRAFTROSTER_COPY_LINK",nil,nil,link); return end
		if IsShiftKeyDown and IsShiftKeyDown() then
			if ChatEdit_InsertLink then
				local ok,inserted=pcall(ChatEdit_InsertLink,link)
				if ok and inserted then return end
			end
			if ChatFrame_OpenChat then ChatFrame_OpenChat(link,DEFAULT_CHAT_FRAME); return end
			StaticPopup_Show("CRAFTROSTER_COPY_LINK",nil,nil,link); return
		end
		if SetItemRef then
			local payload=link:match("|H(.-)|h")
			local ok=payload and pcall(SetItemRef,payload,link,"LeftButton")
			if ok then return end
		end
		LinkTooltip(self)
	end)
	return button
end
local function BindRecipeLinks(row,recipeID)
	row.Label:ClearAllPoints()
	if recipeID then
		if not row.RecipeLink then
			row.RecipeLink=CreateRecipeLinkButton(row,"recipe"); row.RecipeLink:SetPoint("BOTTOMLEFT",39,3)
			row.CraftLink=CreateRecipeLinkButton(row,"craft"); row.CraftLink:SetPoint("TOPLEFT",row.Icon,"TOPLEFT",0,0)
		end
		row.RecipeLink.recipeID=recipeID; row.CraftLink.recipeID=recipeID
		local width=math.max(24,row:GetWidth()-55)
		row.RecipeLink:SetWidth(width); row.CraftLink:SetSize(24,24)
		UpdateLinkDisplay(row.RecipeLink); row.CraftLink:SetText("")
		row.RightLabel:ClearAllPoints(); row.RightLabel:SetPoint("TOPRIGHT",row,"TOPRIGHT",-10,-5)
		row.RecipeLink:Show(); row.CraftLink:Show()
		row.Label:SetPoint("TOPLEFT",39,-5); row.Label:SetHeight(16)
	else
		if row.RecipeLink then row.RecipeLink:Hide(); row.CraftLink:Hide(); row.RecipeLink.recipeID=nil; row.CraftLink.recipeID=nil end
		row.Label:SetPoint("LEFT",row.Icon,"RIGHT",8,0); row.Label:SetHeight(16)
		row.RightLabel:ClearAllPoints(); row.RightLabel:SetPoint("RIGHT",row,"RIGHT",-10,0)
	end
end

local function CreateRow(child, width, height)
	local row = CreateFrame("Frame", nil, child, BackdropTemplateMixin and "BackdropTemplate" or nil)
	row:SetSize(width, height)
	row:SetBackdrop({
		bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
		edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
		edgeSize = 10,
		insets = { left = 2, right = 2, top = 2, bottom = 2 },
	})
	row:SetBackdropColor(0, 0, 0, 0.30)
	row:SetBackdropBorderColor(0.8, 0.7, 0.4, 0.25)

	row.Icon = row:CreateTexture(nil, "ARTWORK")
	row.Icon:SetSize(24, 24)
	row.Icon:SetPoint("LEFT", 7, 0)
	row.Icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

	row.Label = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	row.Label:SetPoint("LEFT", row.Icon, "RIGHT", 8, 0)
	row.Label:SetJustifyH("LEFT"); row.Label:SetWordWrap(false)

	row.RightLabel = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	row.RightLabel:SetPoint("RIGHT", -10, 0)
	row.RightLabel:SetHeight(16)
	row.RightLabel:SetWordWrap(false)
	row.RightLabel:SetJustifyH("RIGHT")

	row:SetScript("OnEnter", function(self)
		self:SetBackdropColor(0.16, 0.16, 0.16, 0.65)
		self:SetBackdropBorderColor(0.9, 0.8, 0.5, 0.75)

		if self.hyperlink then
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			GameTooltip:SetHyperlink(self.hyperlink)
			GameTooltip:Show()
		elseif self.tooltipLines or self.materials then
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			GameTooltip:SetText(self.tooltipTitle or "")
			for _, line in ipairs(self.tooltipLines or {}) do
				GameTooltip:AddLine(line, 1, 1, 1)
			end
			for _, material in ipairs(self.materials or {}) do
				GameTooltip:AddLine(("%dx %s"):format(material.count or 0, material.name or "Unknown"), 1, 1, 1)
			end
			GameTooltip:Show()
		end
	end)

	row:SetScript("OnLeave", function(self)
		self:SetBackdropColor(0, 0, 0, 0.30)
		self:SetBackdropBorderColor(0.8, 0.7, 0.4, 0.25)
		GameTooltip:Hide()
	end)

	row:SetScript("OnMouseUp", function(self, button)
		if button=="RightButton" and self.listEntry and self.listEntry.onRightClick then self.listEntry.onRightClick()
		elseif self.listClick and self.listEntry and (not button or button == "LeftButton") then self.listClick(self.listEntry) end
	end)

	return row
end

local function RenderList(child, entries, width, normalHeight, headerHeight, onClick)
	width = math.max(80, child:GetParent():GetWidth() - 4)
	local pool = rowPools[child]
	if not pool then pool = {}; rowPools[child] = pool end
	local offsets, y = {}, 6
	for i, entry in ipairs(entries) do
		offsets[i] = y
		y = y + (entry.isHeader and headerHeight or normalHeight) + 6
	end
	child:SetHeight(math.max(56, y + 12))
	local scroll = child:GetParent()
 local outer=scroll.outerScroll
 if outer then scroll:SetHeight(child:GetHeight()) end
	local function Draw()
		width = math.max(80, scroll:GetWidth() - 4)
		child:SetWidth(width)
		local top = outer and math.max(0,outer:GetVerticalScroll()-(scroll.contentOffset or 0)) or (scroll.GetVerticalScroll and scroll:GetVerticalScroll() or 0)
		local maximum = math.max(0, y + 12 - math.max(1, scroll:GetHeight()))
		if not outer and top > maximum then top = maximum; scroll:SetVerticalScroll(top) end
		local bottom = top + math.max(1, (outer or scroll):GetHeight()) + normalHeight
		-- Binary search avoids walking thousands of offscreen entries on each scroll.
		local low, high = 1, #entries
		while low <= high do
			local mid = math.floor((low + high) / 2)
			if offsets[mid] < top - normalHeight - 6 then low = mid + 1 else high = mid - 1 end
		end
		local used = 0
		local function Row()
			used = used + 1
			local row = pool[used]
			if not row then
			 row = CreateRow(child, width, normalHeight); pool[used] = row
			 if outer then row:EnableMouseWheel(true); row:SetScript("OnMouseWheel",function(_,delta) CraftRoster.SelectedCraft:Scroll(delta) end) end
			end
			row:ClearAllPoints()
			row.listClick, row.listEntry = nil, nil
			row.materials, row.tooltipLines, row.hyperlink = nil, nil, nil
			row:SetBackdropColor(0, 0, 0, 0.30)
			row:SetBackdropBorderColor(0.8, 0.7, 0.4, 0.25)
			row:Show()
			return row
		end
		for i = low, #entries do
			if offsets[i] > bottom or used >= 128 then break end
			local entry = entries[i]
			local row = Row()
			row:SetSize(width, entry.isHeader and headerHeight or normalHeight)
			row:SetPoint("TOPLEFT", 0, -offsets[i])
			if entry.atlas and row.Icon.SetAtlas then row.Icon:SetAtlas(entry.atlas)
			else
			 local icon=entry.recipe and CraftRoster.RecipeSources:GetRecipeIcon(entry.recipe.id,entry.icon) or entry.icon
			 row.Icon:SetTexture(icon or "Interface\\Icons\\Trade_Tailoring")
			end
			local rightWidth = entry.rightText and entry.rightText ~= "" and math.max(30, math.min(120, width * 0.35)) or 0
			row.Label:SetWidth(math.max(1, width - 59 - rightWidth))
			row.Label:SetText(entry.text or "")
			row.RightLabel:SetWidth(math.max(1, rightWidth))
			row.RightLabel:SetText(entry.rightText or "")
			row.Label:SetFontObject(entry.isHeader and "GameFontNormal" or "GameFontHighlight")
			row.tooltipTitle, row.tooltipLines = entry.tooltipTitle or entry.text, entry.tooltipLines
			row.materials, row.hyperlink = entry.materials, entry.hyperlink
			if entry.recipe then row.hyperlink=(Directory:GetSearchLinks(entry.recipe.id) or {}).craft end
			BindRecipeLinks(row,not entry.isHeader and (entry.linkRecipeID or entry.recipeID or (entry.recipe and entry.recipe.id)) or nil)
			row:EnableMouse(not entry.isHeader and (onClick ~= nil or row.tooltipLines ~= nil or row.materials ~= nil or row.hyperlink ~= nil))
			if onClick and not entry.isHeader then
				row.listClick, row.listEntry = onClick, entry
			end
		end
		if #entries == 0 then
			local row = Row()
			row:SetSize(width, 44); row:SetPoint("TOPLEFT", 0, -6)
			row.Icon:SetTexture("Interface\\Icons\\Trade_Tailoring")
			BindRecipeLinks(row,nil)
			row.Label:SetText("No matching entries."); row.RightLabel:SetText("")
			row:EnableMouse(false)
		end
		for i = used + 1, #pool do pool[i]:Hide() end
	end
	child.drawRows = Draw
	child.scrollToEntry = function(id)
		for i, entry in ipairs(entries) do
			if not entry.isHeader and entry.id == id then
				local top = scroll.GetVerticalScroll and scroll:GetVerticalScroll() or 0
				local height = math.max(1, scroll:GetHeight())
				local rowTop, rowBottom = offsets[i], offsets[i] + normalHeight
				if rowTop < top then top = rowTop
				elseif rowBottom > top + height then top = rowBottom - height end
				scroll:SetVerticalScroll(math.max(0, math.min(top, math.max(0, y + 12 - height))))
				Draw()
				return
			end
		end
	end
	if not child.scrollHooked and scroll.HookScript then
		(outer or scroll):HookScript("OnVerticalScroll", function() child.drawRows() end)
		scroll:HookScript("OnSizeChanged", function() child.drawRows() end)
		child.scrollHooked = true
	end
	Draw()
end

local function SaveGeometry()
	local frame = Directory.frame
	if not frame then return end

	local point, _, _, x, y = frame:GetPoint()
	CraftRosterDB.settings.window = {
		point = point, x = x, y = y,
		width = frame:GetWidth(), height = frame:GetHeight(),
	}
end

function Directory:ResetWindow()
	local frame = self.frame
	if not frame then CraftRosterDB.settings.window = nil; return end

	frame:ClearAllPoints()
	frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
	frame:SetSize(DEFAULT_WINDOW.width, DEFAULT_WINDOW.height)
	CraftRosterDB.settings.window = nil
	SaveGeometry()
	self:RefreshIfVisible()
end

local function RestoreGeometry(frame)
	local saved = CraftRosterDB.settings.window
	if saved then
		frame:ClearAllPoints()
		frame:SetPoint(saved.point or "CENTER", UIParent, "CENTER", saved.x or 0, saved.y or 0)
		frame:SetSize(
			math.max(MIN_WIDTH, saved.width or DEFAULT_WINDOW.width),
			math.max(MIN_HEIGHT, saved.height or DEFAULT_WINDOW.height)
		)
	else
		Directory:ResetWindow()
	end
end

function Directory:Initialize()
	if self.frame then return end
	for _, mode in ipairs(SORT_MODES) do if CraftRosterDB.settings.sortMode == mode then sortMode = mode end end

	if CraftRosterDB.settings.onlineOnly == nil then
		CraftRosterDB.settings.onlineOnly = true
	end

	local frame = CreateFrame("Frame", "CraftRosterDirectory", UIParent, "BasicFrameTemplateWithInset")
	frame:SetFrameStrata("HIGH")
	frame:SetMovable(true)
	frame:SetResizable(true)
	frame:SetClampedToScreen(true)
	if frame.SetResizeBounds then frame:SetResizeBounds(MIN_WIDTH, MIN_HEIGHT)
	elseif frame.SetMinResize then frame:SetMinResize(MIN_WIDTH, MIN_HEIGHT) end
	frame:EnableMouse(true)
	frame:RegisterForDrag("LeftButton")
	frame:SetScript("OnDragStart", frame.StartMoving)
	frame:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		SaveGeometry()
	end)
	frame:SetScript("OnHide", function()
		frame:StopMovingOrSizing()
		SaveGeometry()
		if Directory.refreshTimer then Directory.refreshTimer:Cancel(); Directory.refreshTimer = nil end
	end)
	frame:Hide()

	self.frame = frame
	RestoreGeometry(frame)
	local title = frame.TitleText or frame.TitleBar.TitleText
	title:SetText("CraftRoster")
	frame.BugReportButton = CraftRoster.Panel:CreateReportButton(frame)

	frame.MoveHandles={}
	local function MoveHandle(name,point,relativePoint,x,y,width,height,secondPoint,secondRelative,secondX,secondY)
		local handle=CreateFrame("Frame",nil,frame)
		frame.MoveHandles[name]=handle
		if width then handle:SetWidth(width) end
		if height then handle:SetHeight(height) end
		handle:SetPoint(point,frame,relativePoint,x,y)
		if secondPoint then handle:SetPoint(secondPoint,frame,secondRelative,secondX,secondY) end
		handle:EnableMouse(true); handle:RegisterForDrag("LeftButton")
		handle:SetFrameLevel(frame:GetFrameLevel()+5)
		handle:SetScript("OnDragStart",function() frame:StartMoving() end)
		handle:SetScript("OnDragStop",function() frame:StopMovingOrSizing(); SaveGeometry() end)
		return handle
	end
	MoveHandle("left","TOPLEFT","TOPLEFT",0,-8,6,nil,"BOTTOMLEFT","BOTTOMLEFT",0,8)
	MoveHandle("right","TOPRIGHT","TOPRIGHT",0,-8,6,nil,"BOTTOMRIGHT","BOTTOMRIGHT",0,26)
	MoveHandle("top","TOPLEFT","TOPLEFT",8,0,nil,5,"TOPRIGHT","TOPRIGHT",-145,0)
	MoveHandle("bottom","BOTTOMLEFT","BOTTOMLEFT",8,0,nil,6,"BOTTOMRIGHT","BOTTOMRIGHT",-26,0)
	MoveHandle("title","TOPLEFT","TOPLEFT",12,-6,nil,18,"TOPRIGHT","TOPRIGHT",-145,-6)
	local resize = CreateFrame("Frame", nil, frame)
	frame.ResizeHandle=resize
	resize:SetSize(22, 22)
	resize:SetPoint("BOTTOMRIGHT", -2, 2)
	resize:SetFrameLevel(frame:GetFrameLevel()+6)
	resize:EnableMouse(true)
	resize:RegisterForDrag("LeftButton")
	resize:SetScript("OnDragStart", function() frame:StartSizing("BOTTOMRIGHT") end)
	resize:SetScript("OnEnter",function(self) GameTooltip:SetOwner(self,"ANCHOR_TOP"); GameTooltip:SetText("Drag to resize CraftRoster"); GameTooltip:Show() end)
	resize:SetScript("OnLeave",function() GameTooltip:Hide() end)
	resize:SetScript("OnDragStop", function()
		frame:StopMovingOrSizing()
		frame:SetSize(math.max(MIN_WIDTH, frame:GetWidth()), math.max(MIN_HEIGHT, frame:GetHeight()))
		SaveGeometry()
		Directory:RefreshIfVisible()
	end)

	local resizeTexture = resize:CreateTexture(nil, "OVERLAY")
	resizeTexture:SetAllPoints()
	resizeTexture:SetTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")

	frame.TabButtons = {}
	for index, tabName in ipairs({ "Professions", "Players", "My Recipes" }) do
		local tab = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
		tab:SetSize(120, 26)
		tab:SetText(tabName)
		tab:SetID(index)
		tab:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 12 + (index - 1) * 125, 18)
		tab:SetScript("OnClick", function() Directory:ShowTab(index) end)
		frame.TabButtons[index] = tab
	end

	local ordersButton=CreateFrame("Button",nil,frame,"UIPanelButtonTemplate")
	ordersButton:SetSize(112,26); ordersButton:SetPoint("BOTTOMLEFT",frame,"BOTTOMLEFT",387,18)
	ordersButton:SetText("Work Orders")
	ordersButton:SetScript("OnClick",function() if CraftRoster.WorkOrders then CraftRoster.WorkOrders:Toggle() end end)
	frame.WorkOrdersButton=ordersButton

	local function CreateTab(name)
		local tab = CreateFrame("Frame", nil, frame)
		-- Explicit content bounds avoid client-specific inset template geometry.
		tab:SetPoint("TOPLEFT", frame, "TOPLEFT", 8, -30)
		tab:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -8, 50)
		frame[name] = tab
		return tab
	end

	local professionsTab = CreateTab("ProfessionsTab")
	professionsTab.SearchBox = CreateFrame("EditBox", nil, professionsTab, "SearchBoxTemplate")
	professionsTab.SearchBox:SetSize(210, 24)
	professionsTab.SearchBox:SetPoint("TOPLEFT", 18, -16)
	professionsTab.SearchBox:SetAutoFocus(false)
	professionsTab.SearchBox:HookScript("OnTextChanged", DebouncedRefresh("RefreshProfessions"))

	professionsTab.SortButton = CreateFrame("Button", nil, professionsTab, "GameMenuButtonTemplate")
	professionsTab.SortButton:SetSize(140, 22)
	professionsTab.SortButton:SetPoint("TOPLEFT", 18, -48)
	professionsTab.SortButton:SetText(SORT_LABELS[sortMode])
	professionsTab.SortButton:SetScript("OnClick", function(self)
		local currentIndex = 1
		for i, mode in ipairs(SORT_MODES) do
			if mode == sortMode then currentIndex = i break end
		end
		sortMode = SORT_MODES[(currentIndex % #SORT_MODES) + 1]
		CraftRosterDB.settings.sortMode = sortMode
		self:SetText(SORT_LABELS[sortMode])
		Directory:RefreshProfessions()
	end)

	professionsTab.FavoritesCheck = CreateFrame("CheckButton", nil, professionsTab, "UICheckButtonTemplate")
	professionsTab.FavoritesCheck:SetPoint("TOPLEFT", 270, -44)
	professionsTab.FavoritesCheck.Text:SetText("Favorites only")
	professionsTab.FavoritesCheck:SetChecked(CraftRosterDB.settings.favoritesOnly == true)
	professionsTab.FavoritesCheck:SetScript("OnClick", function(button)
		CraftRosterDB.settings.favoritesOnly = button:GetChecked() and true or false
		Directory:RefreshProfessions()
	end)

	professionsTab.Dropdown = CreateFrame("Frame", nil, professionsTab, "UIDropDownMenuTemplate")
	professionsTab.Dropdown:SetPoint("LEFT", professionsTab.SearchBox, "RIGHT", 4, -4)
	UIDropDownMenu_SetWidth(professionsTab.Dropdown, 150)
	UIDropDownMenu_Initialize(professionsTab.Dropdown, function(dropdown, level)
		local professions = {}
		for profession in pairs(PROFESSION_ICONS) do table.insert(professions, profession) end
		table.sort(professions)
		table.insert(professions, 1, "All")

		for _, profession in ipairs(professions) do
			local info = UIDropDownMenu_CreateInfo()
			info.text = profession
			info.func = function()
				Directory.selectedProfession = profession
				UIDropDownMenu_SetText(dropdown, profession)
				Directory:RefreshProfessions()
			end
			UIDropDownMenu_AddButton(info, level)
			if profession == "All" then
				local spacer = UIDropDownMenu_CreateInfo()
				spacer.text = " "
				spacer.disabled = true
				spacer.notCheckable = true
				UIDropDownMenu_AddButton(spacer, level)
			end
		end
	end)
	UIDropDownMenu_SetText(professionsTab.Dropdown, "All")

	professionsTab.OnlineCheck = CreateFrame("CheckButton", nil, professionsTab, "UICheckButtonTemplate")
	professionsTab.OnlineCheck:SetPoint("TOPLEFT", professionsTab, "TOPLEFT", 420, -44)
	professionsTab.OnlineCheck.Text:SetText("Online only")
	professionsTab.OnlineCheck:SetChecked(CraftRosterDB.settings.onlineOnly)
	professionsTab.OnlineCheck:SetScript("OnClick", function(button)
		CraftRosterDB.settings.onlineOnly = button:GetChecked()
		Directory:RefreshProfessions()
		Directory:RefreshCrafters()
	end)

	professionsTab.Results = CreateFrame("ScrollFrame", nil, professionsTab, "UIPanelScrollFrameTemplate")
	professionsTab.Results:SetPoint("TOPLEFT", 14, -76)
	professionsTab.Results:SetPoint("BOTTOMRIGHT", professionsTab, "BOTTOM", -24, 14)
	professionsTab.ResultsChild = CreateFrame("Frame", nil, professionsTab.Results)
	professionsTab.ResultsChild:SetSize(320, 1)
	professionsTab.Results:SetScrollChild(professionsTab.ResultsChild)

	professionsTab.Details = CreateFrame("Frame", nil, professionsTab, BackdropTemplateMixin and "BackdropTemplate" or nil)
	professionsTab.Details:SetPoint("TOPLEFT", professionsTab, "TOP", 12, -76)
	professionsTab.Details:SetPoint("TOPRIGHT", -28, -76)
	professionsTab.Details:SetHeight(168)
	professionsTab.Details:SetBackdrop({
		bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
		edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
		edgeSize = 12,
	})
	professionsTab.Details:SetBackdropColor(0, 0, 0, 0.45)
	professionsTab.Details:SetBackdropBorderColor(0.8, 0.7, 0.4, 0.5)

	professionsTab.DetailsIcon = professionsTab.Details:CreateTexture(nil, "ARTWORK")
	professionsTab.DetailsIcon:SetSize(42, 42)
	professionsTab.DetailsIcon:SetPoint("TOPLEFT", 12, -12)

	professionsTab.DetailsName = professionsTab.Details:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
	professionsTab.DetailsName:SetPoint("TOPLEFT", professionsTab.DetailsIcon, "TOPRIGHT", 10, -2)
	professionsTab.DetailsName:SetJustifyH("LEFT")
	professionsTab.DetailsName:SetHeight(38)
	if professionsTab.DetailsName.SetMaxLines then professionsTab.DetailsName:SetMaxLines(2) end
	professionsTab.DetailsName:SetWidth(math.max(100, professionsTab.Details:GetWidth() - 78))
	professionsTab.Details:HookScript("OnSizeChanged", function(self)
		professionsTab.DetailsName:SetWidth(math.max(100, self:GetWidth() - 78))
	end)

	professionsTab.DetailsProfession = professionsTab.Details:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	professionsTab.DetailsProfession:SetPoint("TOPLEFT", professionsTab.DetailsIcon, "BOTTOMLEFT", 0, -10)
	professionsTab.DetailsProfession:SetWordWrap(false)
	professionsTab.DetailsProfession:SetPoint("TOPRIGHT", professionsTab.Details, "TOPRIGHT", -152, -64)
	professionsTab.Details:SetScript("OnEnter", function(self)
		local recipe = Directory.selectedRecipe
		if not recipe then return end
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		local links=Directory:GetSearchLinks(recipe.id)
		local ok=links and pcall(GameTooltip.SetHyperlink,GameTooltip,links.craft)
		if not ok then GameTooltip:SetText(recipe.name) end
		GameTooltip:Show()
	end)
	professionsTab.Details:SetScript("OnLeave", function() GameTooltip:Hide() end)
	professionsTab.Details:EnableMouse(true)

	professionsTab.CrafterList = CreateFrame("Frame", nil, professionsTab)
	professionsTab.CrafterList:SetPoint("TOPLEFT", professionsTab, "TOP", 12, -256)
	professionsTab.CrafterList:SetPoint("BOTTOMRIGHT", -32, 14)
	professionsTab.CrafterListChild = CreateFrame("Frame", nil, professionsTab.CrafterList)
	professionsTab.CrafterListChild:SetSize(350, 1)
	professionsTab.CrafterListChild:SetPoint("TOPLEFT",0,0)

	-- Reuse the lower right area; long acquisition descriptions scroll instead
	-- of pushing the action buttons out of the smallest supported window.
	local source = CreateFrame("Frame", nil, professionsTab)
	professionsTab.RecipeSource = source
	source:SetPoint("TOPLEFT", professionsTab.CrafterList, "TOPLEFT", 0, 0)
	source:SetPoint("BOTTOMRIGHT", professionsTab.CrafterList, "BOTTOMRIGHT", 0, 0)
	source.Child = CreateFrame("Frame", nil, source)
	source.Child:SetPoint("TOPLEFT",0,0)
	source.Status = source.Child:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	source.Status:SetPoint("TOPLEFT", 4, -4)
	source.Status:SetJustifyH("LEFT")
	source.Status:SetWordWrap(true)
	source.Link = CreateRecipeLinkButton(source.Child,"recipe")
	source.Link:SetPoint("TOPLEFT",4,-48); source.Link:SetHeight(34)
	source.Output=CreateRecipeLinkButton(source.Child,"craft")
	source.Output:SetPoint("TOPLEFT",4,-96); source.Output:SetHeight(34)
	source.Output:SetScript("OnEnter",function(button) button.recipeID=Directory.selectedRecipe and Directory.selectedRecipe.id; LinkTooltip(button) end)
	source.Text = source.Child:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	source.Text:SetPoint("TOPLEFT", 4, -144)
	source.Text:SetJustifyH("LEFT")
	source.Text:SetWordWrap(true)

	source:Hide()
	if CraftRoster.SelectedCraft then CraftRoster.SelectedCraft:Initialize(professionsTab) end

	local playersTab = CreateTab("PlayersTab")
	playersTab.SearchBox = CreateFrame("EditBox", nil, playersTab, "SearchBoxTemplate")
	playersTab.SearchBox:SetSize(260, 24)
	playersTab.SearchBox:SetPoint("TOPLEFT", 18, -16)
	playersTab.SearchBox:SetAutoFocus(false)
	playersTab.SearchBox:HookScript("OnTextChanged", DebouncedRefresh("RefreshPlayers"))

	local myNote=CreateFrame("Button",nil,playersTab,"UIPanelButtonTemplate")
	myNote:SetSize(100,24); myNote:SetPoint("TOPRIGHT",-20,-16); myNote:SetText("My guild note")
	myNote:SetScript("OnClick",function() CraftRoster.MemberNotes:Edit(nil,true) end)
	playersTab.NoteButton=myNote

	playersTab.Results = CreateFrame("ScrollFrame", nil, playersTab, "UIPanelScrollFrameTemplate")
	playersTab.Results:SetPoint("TOPLEFT", 14, -50)
	playersTab.Results:SetPoint("BOTTOMRIGHT", -32, 14)
	playersTab.ResultsChild = CreateFrame("Frame", nil, playersTab.Results)
	playersTab.ResultsChild:SetSize(720, 1)
	playersTab.Results:SetScrollChild(playersTab.ResultsChild)

	local myRecipesTab = CreateTab("MyRecipesTab")
	myRecipesTab.Status = myRecipesTab:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
	myRecipesTab.Status:SetPoint("TOPLEFT", 18, -16)

	local updateButton = CreateFrame("Button", nil, myRecipesTab, "GameMenuButtonTemplate")
	updateButton:SetSize(190, 26)
	updateButton:SetPoint("TOPLEFT", 18, -44)
	updateButton:SetText("Update My Recipes")
	updateButton:SetScript("OnClick", function()
		local added = CraftRoster.RecipeTracker:UpdateKnownRecipes()
		print(("|cff00ff00CraftRoster|r: recipe update complete. %d new recipe(s) added."):format(added or 0))
		Directory:RefreshMyRecipes()
	end)

	myRecipesTab.Results = CreateFrame("ScrollFrame", nil, myRecipesTab, "UIPanelScrollFrameTemplate")
	myRecipesTab.Results:SetPoint("TOPLEFT", 14, -84)
	myRecipesTab.Results:SetPoint("BOTTOMRIGHT", -32, 14)
	myRecipesTab.ResultsChild = CreateFrame("Frame", nil, myRecipesTab.Results)
	myRecipesTab.ResultsChild:SetSize(720, 1)
	myRecipesTab.Results:SetScrollChild(myRecipesTab.ResultsChild)

	frame:SetScript("OnKeyDown", function(_, key)
		if key == "ESCAPE" then frame:Hide() end
	end)
	if frame.SetPropagateKeyboardInput then frame:SetPropagateKeyboardInput(true) end

	self.frame = frame
	self.selectedProfession = "All"
	self.selectedRecipe = nil
end

local function BuildProfessionEntries()
	local tab = Directory.frame.ProfessionsTab
	local search = (tab.SearchBox:GetText() or ""):lower()
	local cacheKey = search .. "\001" .. (Directory.selectedProfession or "All") .. "\001" .. sortMode
		.. tostring(CraftRosterDB.settings.favoritesOnly)
	if Directory.professionCache and Directory.professionCache.key == cacheKey then return Directory.professionCache.entries end
	local searchTerms = GetSearchTerms(search)
	local matching = {}

	for _, recipe in ipairs(GetRecipeIndex()) do
		local professionOK = Directory.selectedProfession == "All" or recipe.profession == Directory.selectedProfession
		local searchOK = search == ""

		if not searchOK then
			local recipeName = recipe.searchName
			for _, term in ipairs(searchTerms) do
				if recipeName:find(term, 1, true) then
					searchOK = true
					break
				end
			end
		end

		if professionOK and searchOK and (not CraftRosterDB.settings.favoritesOnly or (CraftRosterDB.favorites or {})[recipe.id]) then
			table.insert(matching, recipe)
		end
	end

	table.sort(matching, function(a, b)
		if sortMode == "crafters" then
			if #a.crafters ~= #b.crafters then return #a.crafters > #b.crafters end
			return a.name < b.name
		elseif sortMode == "profession" then
			if a.profession ~= b.profession then return a.profession < b.profession end
			return a.name < b.name
		end
		return a.name < b.name
	end)

	local entries = {}
	local lastProfession = nil

	for _, recipe in ipairs(matching) do
		if sortMode == "profession" and recipe.profession ~= lastProfession then
			table.insert(entries, {
				isHeader = true,
				text = recipe.profession,
				icon = GetProfessionIcon(recipe.profession),
			})
			lastProfession = recipe.profession
		end

		local saved = CraftRosterDB.recipes and CraftRosterDB.recipes[recipe.id]
		table.insert(entries, {
			id = recipe.id,
			text = recipe.name,
			icon = recipe.icon,
			rightText = #recipe.crafters == 0 and "No crafter" or ("%d crafter%s"):format(#recipe.crafters, #recipe.crafters == 1 and "" or "s"),
			-- Native item links and icons are resolved only for visible rows.
			recipe = recipe,
		})
	end

	Directory.professionCache = { key = cacheKey, entries = entries }
	return entries
end

function Directory:RefreshProfessions()
	if not self.frame or not self.frame:IsShown() then return end
	local tab = self.frame.ProfessionsTab
	local entries = BuildProfessionEntries()
	local selected
	for _, entry in ipairs(entries) do
		if self.selectedRecipe and entry.id == self.selectedRecipe.id then selected = entry.recipe end
	end
	self.selectedRecipe = selected
	self:RefreshDetails()
	self:RefreshCrafters()
	RenderList(tab.ResultsChild, entries, 320, 48, 28, function(entry)
		Directory.selectedRecipe = entry.recipe
		Directory.selectedCrafter = nil
		Directory:RefreshDetails()
		Directory:RefreshCrafters()
	end)
end

function Directory:RefreshDetails()
	if not self.frame or not self.frame:IsShown() then return end
	local tab = self.frame.ProfessionsTab
	local recipe = self.selectedRecipe
	if tab.CraftRosterQuantity and CraftRoster.ShoppingList then
		tab.CraftRosterQuantity:SetText(tostring(recipe and CraftRoster.ShoppingList:GetQuantity(recipe.id) or 1))
	end
	if tab.CraftRosterFavoriteButton then
		tab.CraftRosterFavoriteButton:SetText(recipe and (CraftRosterDB.favorites or {})[recipe.id] and "Unfavorite" or "Favorite")
	end

	if recipe then
		tab.DetailsIcon:SetTexture(CraftRoster.RecipeSources:GetRecipeIcon(recipe.id,recipe.icon))
		tab.DetailsName:SetText(recipe.name)
		tab.DetailsProfession:SetText(recipe.profession)
	else
		tab.DetailsIcon:SetTexture("Interface\\Icons\\Trade_Tailoring")
		tab.DetailsName:SetText("Select a recipe")
		tab.DetailsProfession:SetText("")
	end
	if CraftRoster.SelectedCraft then CraftRoster.SelectedCraft:Refresh() end
end

function Directory:RefreshRecipeSource()
 if CraftRoster.SelectedCraft then CraftRoster.SelectedCraft:RefreshSources() end
end

function Directory:RefreshCrafters()
	if not self.frame or not self.frame:IsShown() then return end
	local child = self.frame.ProfessionsTab.CrafterListChild
	local entries = {}
	local selectedValid = false
	for _, key in ipairs(self.selectedRecipe and self.selectedRecipe.crafters or {}) do
		if key == self.selectedCrafter and (not CraftRosterDB.settings.onlineOnly or IsCharacterOnline(key)) then
			selectedValid = true
		end
	end
	if not selectedValid then self.selectedCrafter = nil end
	self:RefreshRecipeSource()
	if CraftRoster.SelectedCraft then CraftRoster.SelectedCraft:RefreshMaterials() end


	if self.selectedRecipe then
		local onlineOnly = CraftRosterDB.settings.onlineOnly
		local online, offline = {}, {}

		for _, characterKey in ipairs(self.selectedRecipe.crafters) do
			local character = CraftRosterDB.characters[characterKey] or {}
			local isOnline = IsCharacterOnline(characterKey)
			local profession = self.selectedRecipe.profession or "Unknown"
			local skill = character.professions and character.professions[profession]
			local professionText = skill and ("%s: %d/%d"):format(profession, skill.skill or 0, skill.max or 0) or profession
			local entry = {
				text = GetColoredName(characterKey, character, not isOnline),
				atlas = GetRaceGenderAtlas(character),
				icon = "Interface\\Icons\\Achievement_Character_Human_Male",
				offline = not isOnline,
				characterKey = characterKey,
				tooltipLines = { characterKey, professionText, self.selectedRecipe.name or "Unknown recipe", "Select for Whisper Player or Mail Player." },
				rightText = self.selectedCrafter == characterKey and "Selected" or "",
			}

			if isOnline then
				table.insert(online, entry)
			else
				table.insert(offline, entry)
			end
		end

		table.sort(online, function(a, b) return a.characterKey < b.characterKey end)
		table.sort(offline, function(a, b) return a.characterKey < b.characterKey end)
		if onlineOnly then
			for _, entry in ipairs(online) do table.insert(entries, entry) end
			if #online == 0 and #offline > 0 then
				table.insert(entries, { isHeader = true, text = "Known crafters are offline.",
					tooltipLines = { "Uncheck Online only to see saved crafters." } })
			end
		else
			for _, entry in ipairs(online) do table.insert(entries, entry) end
			for _, entry in ipairs(offline) do table.insert(entries, entry) end
		end
	end

	if self.selectedRecipe and self.selectedCrafter and CraftRoster.GuildDetails then
		CraftRoster.GuildDetails:RequestMaterials(self.selectedRecipe.id,self.selectedCrafter)
	end
	if self.selectedRecipe and #self.selectedRecipe.crafters==0 then
	 entries={{isHeader=true,text="No synced crafter · try Refresh"}}
	end
	RenderList(child, entries, 350, 38, 28, function(entry)
		if Directory.selectedRecipe then
			Directory.selectedCrafter = entry.characterKey
			Directory:RefreshCrafters()
			if CraftRoster.WhisperComposer then CraftRoster.WhisperComposer:Choose(Directory.selectedRecipe.id,entry.characterKey) end
		end
	end)
	if CraftRoster.SelectedCraft then CraftRoster.SelectedCraft:RefreshMaterials() end
end

function Directory:RefreshPlayers()
	if not self.frame or not self.frame:IsShown() then return end
	local tab = self.frame.PlayersTab
	local search = (tab.SearchBox:GetText() or ""):lower()
	local entries, players = {}, {}
	self.expandedPlayers = self.expandedPlayers or {}

	for characterKey, character in pairs(CraftRosterDB.characters or {}) do
		if search == "" or characterKey:lower():find(search, 1, true) then
			local public,private="",""
			if CraftRoster.MemberNotes then public,private=CraftRoster.MemberNotes:Get(characterKey) end
			local tooltip={characterKey,GetProfessionTotals(character),"Click: recipes. Right-click: your private note."}
			if public~="" then table.insert(tooltip,"Guild note: "..public) end
			if private~="" then table.insert(tooltip,"Your private note: "..private) end
			table.insert(players, {
				text = (self.expandedPlayers[characterKey] and "[-] " or "[+] ") .. GetColoredName(characterKey, character, not IsCharacterOnline(characterKey)),
				key = characterKey,
				atlas = GetRaceGenderAtlas(character),
				icon = "Interface\\Icons\\Achievement_Character_Human_Male",
				rightText = GetProfessionTotals(character),
			tooltipLines = { characterKey, GetProfessionTotals(character), "Click to show or hide known recipes." },
			})
		end
	end

	table.sort(players, function(a, b) return a.key < b.key end)
	for _, player in ipairs(players) do
		table.insert(entries, player)
		if self.expandedPlayers[player.key] then
			local recipes = {}
			local character = CraftRosterDB.characters[player.key]
			for recipeID in pairs(character.recipes or {}) do
				local saved = CraftRosterDB.recipes[recipeID] or {}
				table.insert(recipes, { id = recipeID, text = "    " .. GetRecipeName(recipeID),
					rightText = saved.profession or "Unknown",
					icon = GetProfessionIcon(saved.profession),
					tooltipLines = { GetRecipeName(recipeID), saved.profession or "Unknown", "Click to view this recipe and its crafters." } })
			end
			table.sort(recipes, function(a, b)
				if a.rightText ~= b.rightText then return a.rightText < b.rightText end
				if a.text ~= b.text then return a.text < b.text end
				return tostring(a.id) < tostring(b.id)
			end)
			for _, recipe in ipairs(recipes) do table.insert(entries, recipe) end
			if #recipes == 0 then table.insert(entries, { isHeader = true, text = "    No recipes synced yet." }) end
		end
	end
	RenderList(tab.ResultsChild, entries, 720, 42, 28, function(entry)
		if entry.key then
			Directory.expandedPlayers[entry.key] = not Directory.expandedPlayers[entry.key]
			Directory:RefreshPlayers()
		elseif entry.id then
			local target
			for _, recipe in ipairs(GetRecipeIndex()) do if recipe.id == entry.id then target = recipe; break end end
			if target then
				local professions = Directory.frame.ProfessionsTab
				professions.SearchBox:SetText("")
				Directory.selectedProfession = "All"
				UIDropDownMenu_SetText(professions.Dropdown, "All")
				CraftRosterDB.settings.favoritesOnly = false
				professions.FavoritesCheck:SetChecked(false)
				Directory:ShowTab(1)
				Directory.selectedRecipe, Directory.selectedCrafter = target, nil
				Directory:RefreshDetails()
				Directory:RefreshCrafters()
				professions.ResultsChild.scrollToEntry(target.id)
			end
		end
	end)
end

function Directory:RefreshMyRecipes()
	if not self.frame or not self.frame:IsShown() then return end
	local tab = self.frame.MyRecipesTab
	local character = CraftRosterDB.characters[GetCharacterKey()]
	local entries = {}

	if character then
		for recipeID in pairs(character.recipes or {}) do
			local saved = CraftRosterDB.recipes[recipeID] or {}
			local profession = saved.profession or "Unknown"
			table.insert(entries, {
				linkRecipeID = recipeID,
				text = GetRecipeName(recipeID),
				icon = (CraftRoster.RecipeSources and CraftRoster.RecipeSources:GetRecipeIcon(recipeID, GetProfessionIcon(profession))) or GetProfessionIcon(profession),
			})
		end
	end

	table.sort(entries, function(a, b) return a.text < b.text end)
	RenderList(tab.ResultsChild, entries, 720, 48, 28)
	tab.Status:SetText(("Your saved recipes: %d"):format(#entries))
end

function Directory:RefreshIfVisible()
	if not self.frame or not self.frame:IsShown() then return end
	if self.activeTab == 2 then self:RefreshPlayers()
	elseif self.activeTab == 3 then self:RefreshMyRecipes()
	else self:RefreshProfessions() end
end

function Directory:ShowTab(index)
	self.activeTab = index
	self.frame.ProfessionsTab:Hide()
	self.frame.PlayersTab:Hide()
	self.frame.MyRecipesTab:Hide()

	for _, tab in ipairs(self.frame.TabButtons) do
		local selected = index == tab:GetID()
		tab:SetEnabled(not selected)
		tab:SetNormalFontObject(selected and "GameFontHighlight" or "GameFontNormal")
	end

	if index == 1 then
		self.frame.ProfessionsTab:Show()
		self:RefreshProfessions()
	elseif index == 2 then
		self.frame.PlayersTab:Show()
		self:RefreshPlayers()
	else
		self.frame.MyRecipesTab:Show()
		self:RefreshMyRecipes()
	end
end

function Directory:Toggle()
	if not self.frame then self:Initialize() end

	if self.frame:IsShown() then
		self.frame:Hide()
	else
		self.frame:Show()
		self:ShowTab(self.activeTab or 1)
	end
end

function Directory:RequestRoster()
	if C_GuildInfo and C_GuildInfo.GuildRoster then
		pcall(C_GuildInfo.GuildRoster)
	elseif C_GuildInfo and C_GuildInfo.RequestGuildRoster then
		pcall(C_GuildInfo.RequestGuildRoster)
	elseif RequestGuildRoster then
		pcall(RequestGuildRoster)
	elseif GuildRoster then
		pcall(GuildRoster)
	end
end

local rosterFrame = CreateFrame("Frame")
rosterFrame:RegisterEvent("GUILD_ROSTER_UPDATE")
rosterFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
rosterFrame:SetScript("OnEvent", function(_, event)
	if event == "PLAYER_ENTERING_WORLD" then
		Directory:RequestRoster()
		return
	end

	wipe(onlineByName)

	local rosterAvailable = false
	if C_GuildInfo and C_GuildInfo.GetGuildRoster then
		local ok, roster = pcall(C_GuildInfo.GetGuildRoster)
		if ok and type(roster) == "table" then
			rosterAvailable = true
			for _, member in ipairs(roster) do
				if member and member.name and member.online then
					onlineByName[NormalizeCharacter(member.name)] = true
				end
			end
		end
	end
	if not rosterAvailable and GetNumGuildMembers and GetGuildRosterInfo then
		local ok, count = pcall(GetNumGuildMembers)
		for i = 1, (ok and type(count) == "number" and count or 0) do
			local success, name, _, _, _, _, _, _, _, isOnline = pcall(GetGuildRosterInfo, i)
			if success and type(name) == "string" and isOnline then
				onlineByName[NormalizeCharacter(name)] = true
			end
		end
	end

	if Directory.activeTab == 1 then Directory:RefreshCrafters()
	elseif Directory.activeTab == 2 then Directory:RefreshPlayers() end
end)
