-- Book of Dogs: a dog button on the minimap's edge. Left-click opens the Book,
-- drag moves it around the minimap. Uses no libraries and runs nothing until clicked or dragged.
local ADDON, NS = ...
local ICON = "Interface\\AddOns\\BookOfDogs\\dog"

local btn
local function place(angle)
  local r = (Minimap:GetWidth() / 2) + 5
  btn:ClearAllPoints()
  btn:SetPoint("CENTER", Minimap, "CENTER", math.cos(angle) * r, math.sin(angle) * r)
end

local function build()
  btn = CreateFrame("Button", "BookOfDogsMinimapButton", Minimap)
  btn:SetSize(31, 31); btn:SetFrameStrata("MEDIUM"); btn:SetFrameLevel(8)
  btn:RegisterForClicks("LeftButtonUp", "RightButtonUp"); btn:RegisterForDrag("LeftButton")
  btn:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
  local bg = btn:CreateTexture(nil, "BACKGROUND")
  bg:SetSize(20, 20); bg:SetPoint("CENTER", 0, 1); bg:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
  local icon = btn:CreateTexture(nil, "ARTWORK")
  icon:SetSize(20, 20); icon:SetPoint("CENTER", 0, 1); icon:SetTexture(ICON)
  if icon.SetMask then pcall(icon.SetMask, icon, "Interface\\CharacterFrame\\TempPortraitAlphaMask") end
  btn.icon = icon
  local border = btn:CreateTexture(nil, "OVERLAY")
  border:SetSize(53, 53); border:SetPoint("TOPLEFT"); border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")

  btn:SetScript("OnClick", function() NS.Toggle() end)
  btn:SetScript("OnMouseDown", function() icon:SetPoint("CENTER", 1, 0) end)
  btn:SetScript("OnMouseUp", function() icon:SetPoint("CENTER", 0, 1) end)
  btn:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:SetText("Book of Dogs", 1, 0.82, 0)
    GameTooltip:AddLine("Click to open the book", 1, 1, 1)
    GameTooltip:AddLine("Drag to move this button", 0.7, 0.7, 0.7)
    GameTooltip:Show()
  end)
  btn:SetScript("OnLeave", GameTooltip_Hide)
  btn:SetScript("OnDragStart", function(self)
    self:LockHighlight()
    self:SetScript("OnUpdate", function()
      local mx, my = Minimap:GetCenter()
      local cx, cy = GetCursorPosition()
      local s = Minimap:GetEffectiveScale()
      local a = math.atan2(cy / s - my, cx / s - mx)
      BookOfDogsDB.mm = a
      place(a)
    end)
  end)
  btn:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil); self:UnlockHighlight() end)
  place(BookOfDogsDB.mm or math.rad(200))
  btn:SetShown(not BookOfDogsDB.mmHide)
end

local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_LOGIN")
f:SetScript("OnEvent", function() if Minimap then build() end end)

function NS.ToggleMinimap()
  if not btn then return end
  BookOfDogsDB.mmHide = not BookOfDogsDB.mmHide
  btn:SetShown(not BookOfDogsDB.mmHide)
  print("|cff" .. NS.GOLD .. "Book of Dogs|r: minimap button " .. (BookOfDogsDB.mmHide and "hidden. /dogs minimap brings it back." or "shown."))
end
