-- Book of Dogs: a dog icon above the nameplate of anyone who is in the Book,
-- whether or not you are targeting them. Works with the default nameplates and
-- with nameplate addons (the icon hangs off the base nameplate, not Blizzard's
-- UnitFrame, which replacement addons often hide).
--   /dogs icons          show / hide the icons
--   /dogs plates         turn on nameplates for all nearby players (so every dog gets an icon)
--   /dogs icon 32 10     icon size and height above the plate (defaults 28 and 18)
local ADDON, NS = ...
local ICON = "Interface\\AddOns\\BookOfDogs\\dog_head"
local DEF_SIZE, DEF_Y = 28, 18

local function secret(v) return issecretvalue and issecretvalue(v) end
local function size() return (BookOfDogsDB and BookOfDogsDB.npSize) or DEF_SIZE end
local function yoff() return (BookOfDogsDB and BookOfDogsDB.npY) or DEF_Y end

local function isDog(unit)
  if not unit or not UnitExists(unit) or not UnitIsPlayer(unit) or not NS.InGuildFeed() then return false end
  local name, second = UnitName(unit)
  if not name or secret(name) or secret(second) then return false end
  return #NS.FindEntries(NS.Key(name), NS.FullFrom(name, second)) > 0
end

local function place(holder, plate)
  holder:ClearAllPoints()
  holder:SetSize(size(), size())
  holder:SetPoint("BOTTOM", plate, "TOP", 0, yoff())
end

local function update(plate, unit)
  if not plate then return end
  local holder = plate.BookOfDogsIcon
  local show = not (BookOfDogsDB and BookOfDogsDB.npHide) and isDog(unit)
  if not show then
    if holder then holder:Hide() end
    return
  end
  if not holder then
    holder = CreateFrame("Frame", nil, plate)
    holder:SetFrameLevel((plate:GetFrameLevel() or 1) + 25) -- above custom health bars and text
    local tex = holder:CreateTexture(nil, "OVERLAY")
    tex:SetAllPoints()
    tex:SetTexture(ICON)
    plate.BookOfDogsIcon = holder
  end
  place(holder, plate)
  holder:Show()
end

local function unitOf(plate)
  return plate.namePlateUnitToken or (plate.UnitFrame and plate.UnitFrame.unit)
end

local function refreshAll()
  if not (C_NamePlate and C_NamePlate.GetNamePlates) then return end
  for _, plate in ipairs(C_NamePlate.GetNamePlates()) do
    pcall(update, plate, unitOf(plate))
  end
end

local f = CreateFrame("Frame")
f:RegisterEvent("NAME_PLATE_UNIT_ADDED")
f:RegisterEvent("NAME_PLATE_UNIT_REMOVED")
f:RegisterEvent("UNIT_NAME_UPDATE")
f:SetScript("OnEvent", function(_, event, unit)
  if not (C_NamePlate and C_NamePlate.GetNamePlateForUnit) or not unit then return end
  if not tostring(unit):find("^nameplate") then return end
  local plate = C_NamePlate.GetNamePlateForUnit(unit)
  if not plate then return end
  if event == "NAME_PLATE_UNIT_REMOVED" then
    if plate.BookOfDogsIcon then plate.BookOfDogsIcon:Hide() end
  else
    pcall(update, plate, unit)
  end
end)

-- icons update when the Book changes (new entry, delete, sync)
NS.listeners[#NS.listeners + 1] = refreshAll

local function say(msg) print(("|cff%sBook of Dogs|r: %s"):format(NS.GOLD, msg)) end

function NS.NameplateCmd(msg)
  msg = msg or ""
  if msg == "icons" then
    BookOfDogsDB.npHide = not BookOfDogsDB.npHide
    refreshAll()
    say("nameplate icons " .. (BookOfDogsDB.npHide and "hidden" or "shown") .. ".")
  elseif msg == "plates" then
    if InCombatLockdown() then say("can't change nameplate settings in combat."); return end
    for _, cv in ipairs({"nameplateShowAll", "nameplateShowEnemies", "nameplateShowFriends"}) do
      pcall(SetCVar, cv, 1)
    end
    say("nameplates turned on for all nearby units, so every dog in range gets an icon.")
  else
    local s, y = msg:match("^icon%s+(%d+)%s*(%-?%d*)")
    if not s then say("use |cffffffff/dogs icon <size> <height>|r, for example /dogs icon 32 10."); return end
    BookOfDogsDB.npSize = math.max(8, math.min(96, tonumber(s)))
    if y and y ~= "" then BookOfDogsDB.npY = math.max(-50, math.min(100, tonumber(y))) end
    refreshAll()
    say(("icon size %d, height %d."):format(size(), yoff()))
  end
end
