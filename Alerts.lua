-- Book of Dogs: heads-up messages when someone in the Book
--   * joins your party or raid, or invites you to one
--   * whispers you, or opens a trade with you
-- Each person is mentioned once per kind of event every 10 minutes.
--   /dogs alerts   turn these messages on / off
local ADDON, NS = ...
local COOLDOWN = 600

local function secret(v) return issecretvalue and issecretvalue(v) end
local function say(msg) print(("|cff%sBook of Dogs|r: %s"):format(NS.GOLD, msg)) end

-- entries for a name as the game gives it: "First", "First Last" or "First Last-Realm"
local function entriesFor(name, full)
  if type(name) ~= "string" or name == "" or secret(name) or not NS.InGuildFeed() then return {} end
  local nm = name:match("^[^%-]+") or name
  full = full or (nm:find(" ", 1, true) and nm) or nil
  return NS.FindEntries(NS.Key(nm:match("^%S+")), full)
end

-- entries for a unit (party1, raid3, NPC = trade partner); see NS.UnitEntries
local function entriesForUnit(unit)
  local hits, shown = NS.UnitEntries(unit)
  return hits, shown
end

local told = {} -- "kind|name" -> time
local function warn(kind, hits, shown, what)
  if #hits == 0 or (BookOfDogsDB and BookOfDogsDB.alertsOff) then return end
  local e = NS.DB().e[hits[1]]
  if not e then return end
  local who = e.f or e.n or shown or "?"
  local key = kind .. "|" .. who:lower()
  local now = GetTime()
  if told[key] and now - told[key] < COOLDOWN then return end
  told[key] = now
  local s = e.s or 0
  say(("|cffff4040Heads up:|r %s %s  |cffff4040DOG|r %s- %s  |cff888888(%s%d)|r"):format(
    NS.ColorName(who, e.c), what, e.k and (NS.TagText(e.k) .. " ") or "", e.d or "", s > 0 and "+" or "", s))
end

-- group: warn about each new member once while you're in the group
local inGroup = {}
local function scanGroup()
  if not IsInGroup or not IsInGroup() then wipe(inGroup); return end
  local raid = IsInRaid and IsInRaid()
  local n = raid and (GetNumGroupMembers() or 0) or ((GetNumSubgroupMembers and GetNumSubgroupMembers()) or 4)
  local now = {}
  for i = 1, n do
    local unit = raid and ("raid" .. i) or ("party" .. i)
    if not UnitIsUnit or not UnitIsUnit(unit, "player") then
      local hits, shown = entriesForUnit(unit)
      if shown then
        now[shown] = true
        if not inGroup[shown] then warn("group", hits, shown, "just joined your group.") end
      end
    end
  end
  inGroup = now
end

local f = CreateFrame("Frame")
f:RegisterEvent("GROUP_ROSTER_UPDATE")
f:RegisterEvent("PARTY_INVITE_REQUEST")
f:RegisterEvent("CHAT_MSG_WHISPER")
f:RegisterEvent("TRADE_SHOW")
f:SetScript("OnEvent", function(_, event, a1, a2)
  if not NS.InGuildFeed() then return end
  if event == "GROUP_ROSTER_UPDATE" then
    pcall(scanGroup)
  elseif event == "PARTY_INVITE_REQUEST" then
    pcall(function() warn("invite", entriesFor(a1), a1, "invited you to a group.") end)
  elseif event == "CHAT_MSG_WHISPER" then
    pcall(function()
      if secret(a2) then return end
      warn("whisper", entriesFor(a2), a2, "whispered you.")
    end)
  elseif event == "TRADE_SHOW" then
    pcall(function()
      local hits, shown = entriesForUnit("NPC") -- the trade partner
      warn("trade", hits, shown, "opened a trade with you.")
    end)
  end
end)

function NS.ToggleAlerts()
  BookOfDogsDB.alertsOff = not BookOfDogsDB.alertsOff
  say("heads-up alerts " .. (BookOfDogsDB.alertsOff and "off." or "on (group, invites, whispers and trades)."))
end
