-- Book of Dogs: a dog icon above the nameplate of anyone who is in the Book,
-- whether or not you are targeting them. Works with the default nameplates and
-- with nameplate addons (the icon hangs off the base nameplate, not Blizzard's
-- UnitFrame, which replacement addons often hide). In dungeons and raids the game
-- locks friendly nameplates, so the icon shows on party and raid frames there.
--   /dogs icons          show / hide the icons (nameplates and party/raid frames)
--   /dogs frames         show / hide just the party/raid frame icons
--   /dogs plates         turn on nameplates for all nearby players (so every dog gets an icon)
--   /dogs icon 32 10     icon size and height above the plate (defaults 28 and 18)
local ADDON, NS = ...
local ICON = "Interface\\AddOns\\BookOfDogs\\dog_head"
local DEF_SIZE, DEF_Y = 28, 18

local function secret(v) return issecretvalue and issecretvalue(v) end
local function size() return (BookOfDogsDB and BookOfDogsDB.npSize) or DEF_SIZE end
local function yoff() return (BookOfDogsDB and BookOfDogsDB.npY) or DEF_Y end

local function isDog(unit)
  local ok, hits = pcall(NS.UnitEntries, unit)
  return ok and #hits > 0
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

------------------------------------------------------------------------
-- party and raid frames. Inside dungeons and raids the game locks friendly
-- nameplates (addons can't touch them), so the dog shows on group frames instead.
------------------------------------------------------------------------
local groupFrames = setmetatable({}, {__mode = "k"})

local function isPlateUnit(unit) return type(unit) == "string" and unit:find("^nameplate") ~= nil end

local function updateGroup(frame)
  if not frame or (frame.IsForbidden and frame:IsForbidden()) then return end
  local unit = frame.unit or frame.displayedUnit or (frame.GetAttribute and frame:GetAttribute("unit"))
  if isPlateUnit(unit) then return end
  groupFrames[frame] = true
  local holder = frame.BookOfDogsGroupIcon
  local show = not (BookOfDogsDB and (BookOfDogsDB.npHide or BookOfDogsDB.frameHide)) and frame:IsShown() and isDog(unit)
  if not show then
    if holder then holder:Hide() end
    return
  end
  if not holder then
    holder = CreateFrame("Frame", nil, frame)
    holder:SetFrameLevel((frame:GetFrameLevel() or 1) + 10)
    holder:SetSize(16, 16)
    holder:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -2, -2)
    local tex = holder:CreateTexture(nil, "OVERLAY")
    tex:SetAllPoints()
    tex:SetTexture(ICON)
    frame.BookOfDogsGroupIcon = holder
  end
  holder:Show()
end

local function eachGroupFrame(fn)
  local seen = {}
  local function each(frame) if frame and not seen[frame] then seen[frame] = true; fn(frame) end end
  -- classic party frames, and the newer PartyFrame.MemberFrame1-4
  for i = 1, 4 do
    each(_G["PartyMemberFrame" .. i])
    if PartyFrame then each(PartyFrame["MemberFrame" .. i]) end
  end
  if PartyFrame and PartyFrame.PartyMemberFramePool and PartyFrame.PartyMemberFramePool.EnumerateActive then
    for pf in PartyFrame.PartyMemberFramePool:EnumerateActive() do each(pf) end
  end
  -- raid-style frames: party, raid ("keep groups together" names them by group), and pets skipped
  for i = 1, 5 do each(_G["CompactPartyFrameMember" .. i]) end
  for i = 1, 40 do each(_G["CompactRaidFrame" .. i]) end
  for gr = 1, 8 do for m = 1, 5 do each(_G["CompactRaidGroup" .. gr .. "Member" .. m]) end end
  if CompactRaidFrameContainer and CompactRaidFrameContainer.ApplyToFrames then
    pcall(CompactRaidFrameContainer.ApplyToFrames, CompactRaidFrameContainer, "normal", each)
  end
  for frame in pairs(groupFrames) do each(frame) end
end

local function refreshGroups()
  eachGroupFrame(function(frame) pcall(updateGroup, frame) end)
end

-- Blizzard's raid-style frames (party and raid) all pass through this when a name changes
if hooksecurefunc then
  for _, fn in ipairs({"CompactUnitFrame_UpdateName", "CompactUnitFrame_SetUnit", "CompactUnitFrame_UpdateAll"}) do
    if _G[fn] then hooksecurefunc(fn, function(frame) pcall(updateGroup, frame) end) end
  end
end

local g = CreateFrame("Frame")
g:RegisterEvent("GROUP_ROSTER_UPDATE")
g:RegisterEvent("PLAYER_ENTERING_WORLD")
g:RegisterEvent("UNIT_NAME_UPDATE")
g:SetScript("OnEvent", function()
  -- let Blizzard lay out its frames first (and again a little later: frames can be built late)
  if C_Timer and C_Timer.After then
    C_Timer.After(0.5, refreshGroups); C_Timer.After(3, refreshGroups)
  else
    refreshGroups()
  end
end)

-- /dogs debug frames: what the addon sees for each group member, their frames and nameplates
function NS.DebugFrames()
  local function p(msg) print("|cff" .. NS.GOLD .. "BoD frames|r " .. msg) end
  local raid = IsInRaid and IsInRaid()
  local n = raid and (GetNumGroupMembers() or 0) or ((GetNumSubgroupMembers and GetNumSubgroupMembers()) or 0)
  local inInst, instType = IsInInstance()
  p(("in group: %s, members: %d, instance: %s, icons hidden: %s, frame icons hidden: %s"):format(
    tostring(IsInGroup and IsInGroup()), n, inInst and tostring(instType) or "no",
    tostring(BookOfDogsDB.npHide and true or false), tostring(BookOfDogsDB.frameHide and true or false)))
  local byUnit = {}
  eachGroupFrame(function(frame)
    if frame.IsForbidden and frame:IsForbidden() then return end
    local u = frame.unit or frame.displayedUnit or (frame.GetAttribute and frame:GetAttribute("unit"))
    if type(u) == "string" and not isPlateUnit(u) then
      local name = (frame.GetName and frame:GetName()) or "unnamed frame"
      local icon = frame.BookOfDogsGroupIcon and frame.BookOfDogsGroupIcon:IsShown() and "icon ON" or "no icon"
      byUnit[u] = (byUnit[u] and (byUnit[u] .. ", ") or "") .. name .. (frame:IsShown() and "" or " (hidden)") .. " " .. icon
    end
  end)
  for i = 1, n do
    local unit = raid and ("raid" .. i) or ("party" .. i)
    local ok, hits, shown, why = pcall(NS.UnitEntries, unit)
    local plate = C_NamePlate and C_NamePlate.GetNamePlateForUnit and C_NamePlate.GetNamePlateForUnit(unit)
    p(("%s: %s -> %s | frames: %s | nameplate: %s"):format(unit, tostring(shown or "?"),
      not ok and ("error: " .. tostring(hits)) or (#hits > 0 and "|cff40ff40IN BOOK|r" or ("|cffff6060" .. tostring(why) .. "|r")),
      byUnit[unit] or "none found", plate and "available" or "not available (locked or off)"))
  end
  if n == 0 then p("not in a group. Target a player and try /dogs debug for name details.") end
  refreshGroups(); refreshAll()
end

-- icons update when the Book changes (new entry, delete, sync)
NS.listeners[#NS.listeners + 1] = refreshAll
NS.listeners[#NS.listeners + 1] = refreshGroups

local function say(msg) print(("|cff%sBook of Dogs|r: %s"):format(NS.GOLD, msg)) end

function NS.NameplateCmd(msg)
  msg = msg or ""
  if msg == "frames" then
    BookOfDogsDB.frameHide = not BookOfDogsDB.frameHide
    refreshGroups()
    say("party/raid frame icons " .. (BookOfDogsDB.frameHide and "hidden (nameplate icons unchanged)." or "shown."))
  elseif msg == "icons" then
    BookOfDogsDB.npHide = not BookOfDogsDB.npHide
    refreshAll()
    refreshGroups()
    say("dog icons " .. (BookOfDogsDB.npHide and "hidden" or "shown") .. " (nameplates and party/raid frames).")
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
