local ADDON_NAME, CraftRoster = ...

local button = CreateFrame("Button", "CraftRosterMinimapButton", UIParent)
button:SetSize(32, 32)
button:SetFrameStrata("MEDIUM")
button:SetFrameLevel(Minimap:GetFrameLevel() + 8)
button:SetMovable(true)
button:EnableMouse(true)
button:RegisterForDrag("LeftButton")
button:RegisterForClicks("AnyUp")

local icon = button:CreateTexture(nil, "ARTWORK")
icon:SetTexture("Interface\\Icons\\INV_Potion_97")
icon:SetSize(20, 20)
icon:SetPoint("CENTER", button, "CENTER", 0, 0)
icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

if button.CreateMaskTexture and icon.AddMaskTexture then
	local mask = button:CreateMaskTexture(nil, "ARTWORK")
	mask:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
	mask:SetAllPoints(icon)
	icon:AddMaskTexture(mask)
end

local border = button:CreateTexture(nil, "OVERLAY")
border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
border:SetSize(54, 54)
border:SetPoint("TOPLEFT", button, "TOPLEFT", 0, 0)
button:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

local function UpdatePosition()
	if not CraftRosterDB or not CraftRosterDB.settings then return end
	local angle = CraftRosterDB.settings.minimapAngle or -math.pi / 4
	local radius = math.max(Minimap:GetWidth(), Minimap:GetHeight()) / 2 + 12
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
		if not mx or not my or not cx or not cy or not scale or scale <= 0 then return end
		local angle = math.atan2(cy / scale - my, cx / scale - mx)
		if CraftRosterDB and CraftRosterDB.settings then
			CraftRosterDB.settings.minimapAngle = angle
		end
		UpdatePosition()
	end)
end)

button:SetScript("OnHide", function(self)
	self:SetScript("OnUpdate", nil)
	if self.UnlockHighlight then self:UnlockHighlight() end
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

