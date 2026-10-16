local ADDON_NAME, CraftRoster = ...

local button = CreateFrame("Button", "CraftRosterMinimapButton", Minimap)
button:SetSize(32, 32)
button:SetFrameStrata("MEDIUM")
button:SetMovable(true)
button:EnableMouse(true)
button:RegisterForDrag("LeftButton")
button:RegisterForClicks("AnyUp")

local icon = button:CreateTexture(nil, "ARTWORK")
icon:SetTexture("Interface\\Icons\\Trade_Engraving")
icon:SetAllPoints()
icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

local function UpdatePosition()
	if not CraftRosterDB or not CraftRosterDB.settings then return end
	local angle = CraftRosterDB.settings.minimapAngle or -math.pi / 4
	local radius = 80
	local x = math.cos(angle) * radius
	local y = math.sin(angle) * radius
	button:ClearAllPoints()
	button:SetPoint("CENTER", Minimap, "CENTER", x, y)
end

button:SetScript("OnClick", function()
	if CraftRoster.Directory then
		CraftRoster.Directory:Toggle()
	end
end)

button:SetScript("OnDragStart", function(self)
	self:LockHighlight()
	self:SetScript("OnUpdate", function()
		local mx, my = Minimap:GetCenter()
		local cx, cy = GetCursorPosition()
		local scale = Minimap:GetEffectiveScale()
		local angle = math.atan2(cy / scale - my, cx / scale - mx)
		if CraftRosterDB and CraftRosterDB.settings then
			CraftRosterDB.settings.minimapAngle = angle
		end
		UpdatePosition()
	end)
end)

button:SetScript("OnDragStop", function(self)
	self:UnlockHighlight()
	self:SetScript("OnUpdate", nil)
	UpdatePosition()
end)

button:SetScript("OnEnter", function(self)
	GameTooltip:SetOwner(self, "ANCHOR_BOTTOMLEFT")
	GameTooltip:SetText("CraftRoster")
	GameTooltip:AddLine("Click to open the crafting directory.", 1, 1, 1)
	GameTooltip:Show()
end)

button:SetScript("OnLeave", function() GameTooltip:Hide() end)

CraftRoster.MinimapButton = CraftRoster.MinimapButton or {}

function CraftRoster.MinimapButton:UpdateVisibility()
	if not CraftRosterDB or not CraftRosterDB.settings then return end
	if CraftRosterDB.settings.showMinimap == false then
		button:Hide()
	else
		button:Show()
	end
end

-- Defer init until ADDON_LOADED fires and CraftRosterDB is ready.
local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("ADDON_LOADED")
initFrame:SetScript("OnEvent", function(self, event, loadedAddon)
	if event == "ADDON_LOADED" and loadedAddon == ADDON_NAME and CraftRosterDB then
		UpdatePosition()
		CraftRoster.MinimapButton:UpdateVisibility()
		self:UnregisterEvent("ADDON_LOADED")
	end
end)
