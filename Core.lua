-- Book of Dogs: core data, voting, permissions.
-- Saved data is kept small: one short table per entry, short keys,
-- descriptions capped, deleted entries shrink to a tombstone and are purged.
local ADDON, NS = ...

NS.PREFIX     = "BookOfDogs"
NS.GUILD      = "dog"                -- compared lowercase
NS.ADMINS     = {["chogan seventythree"] = true} -- full in-game names (lowercase, no realm) with full rights
NS.MAXDESC    = 200
NS.MAXENTRIES = 500
NS.TOMB_DAYS  = 30
NS.GOLD, NS.RED = "ffcc33", "993333"

local db
NS.dirty = true      -- sorted list needs rebuilding
NS.listeners = {}    -- UI refresh callbacks

local now = GetServerTime

------------------------------------------------------------------------
-- names
------------------------------------------------------------------------
local myRealm
function NS.MyRealm()
  myRealm = myRealm or (GetNormalizedRealmName and GetNormalizedRealmName()) or (GetRealmName() or ""):gsub("[%s%-]", "")
  return myRealm
end
-- "Name" for my realm, "Name-Realm" otherwise (the same form chat and the roster use)
function NS.Key(name, realm)
  if not name or name == "" then return nil end
  if name:find("-", 1, true) then return Ambiguate(name, "guild") end
  realm = realm and realm:gsub("[%s%-]", "") or ""
  if realm == "" or realm == NS.MyRealm() then return name end
  return name .. "-" .. realm
end
function NS.Me() return UnitName("player") end

-- One identity per character: the full in-game name ("Oasli Mage") plus realm.
-- Forever lets characters share a first name ("Oasli Mage", "Oasli Bank"), so the
-- surname is part of who someone is. UnitName("player") only gives the first name,
-- so my own full name comes from the guild roster (matched by GUID) or my tooltip.
function NS.Id(name)
  name = tostring(name or "")
  local nm, realm = name:match("^([^%-]*)%-?(.*)$")
  nm = (nm or ""):gsub("%s+", " "):match("^%s*(.-)%s*$")
  if nm == "" then return nil end
  realm = (realm or ""):gsub("[%s%-]", "")
  if realm == "" then realm = NS.MyRealm() end
  return nm .. "-" .. realm
end
NS.VoterKey = NS.Id

local myFull
function NS.MyFull()
  if myFull then return myFull end
  local guid = UnitGUID("player")
  if guid and not (issecretvalue and issecretvalue(guid)) and GetNumGuildMembers then
    for i = 1, GetNumGuildMembers() do
      local info = {GetGuildRosterInfo(i)}
      if info[17] == guid and type(info[1]) == "string" then
        myFull = info[1]:match("^[^%-]+"); return myFull
      end
    end
  end
  if C_TooltipInfo and C_TooltipInfo.GetUnit then
    local ok, data = pcall(C_TooltipInfo.GetUnit, "player")
    local line = ok and data and data.lines and data.lines[1] and data.lines[1].leftText
    local me = UnitName("player")
    if type(line) == "string" and not (issecretvalue and issecretvalue(line)) and me then
      local full = line:match("(" .. me:gsub("%p", "%%%0") .. "%s+%S+)")
      if full then myFull = full; return myFull end
    end
  end
  return UnitName("player")
end
function NS.MyId() return NS.Id(NS.MyFull()) end

-- full in-game names ("Chogan Seventythree") learned from chat and the roster
local function names() db.names = db.names or {}; return db.names end
function NS.LearnName(raw)
  if not db or type(raw) ~= "string" or (issecretvalue and issecretvalue(raw)) then return end
  local id = NS.Id(raw); if not id then return end
  names()[id] = id:match("^[^%-]+") -- the realm is never shown
end
-- how to show a person: their full in-game name, without the realm
function NS.Display(who)
  local id = NS.Canon and db and NS.Canon(who) or NS.Id(who)
  local n = id and db and db.names and db.names[id] or (id or tostring(who or "?"))
  return (n:match("^[^%-]+") or n)
end
local function base(name) local id = NS.Id(name); return id and id:match("^[^%-]+"):lower() or "" end
local function firstId(id) local nm, realm = id:match("^(%S+).-%-(.*)$"); return nm and (nm .. "-" .. realm) or id end

------------------------------------------------------------------------
-- guild membership and ranks
------------------------------------------------------------------------
function NS.InDog()
  if not IsInGuild() then return false end
  local g = GetGuildInfo("player")
  return g ~= nil and g:lower() == NS.GUILD
end

local rankOf, officerRank = {}, {}
local firstCount, rosterHasSurnames = {}, false
-- guild rank for an id, or nil if not in the guild
local function rankFor(id)
  if not id then return nil end
  local r = rankOf[id]
  if r ~= nil then return r end
  local nm = id:match("^[^%-]+") or ""
  if not rosterHasSurnames then return rankOf[firstId(id)] end -- roster shows first names only
  if not nm:find(" ") and firstCount[id] == 1 then -- just a first name, and only one of them
    for k, v in pairs(rankOf) do if firstId(k) == id then return v end end
  end
  return nil
end
NS.RankFor = rankFor
local function rankIsOfficer(rankIndex)
  if rankIndex == 0 then return true end
  local flags
  if C_GuildInfo and C_GuildInfo.GuildControlGetRankFlags then
    local ok, f = pcall(C_GuildInfo.GuildControlGetRankFlags, rankIndex + 1)
    if ok and type(f) == "table" then flags = f end
  end
  if not flags and GuildControlGetRankFlags then
    local ok, r = pcall(function() return {GuildControlGetRankFlags(rankIndex + 1)} end)
    if ok and r and #r > 0 then flags = r end
  end
  if flags then return flags[3] and true or false end -- officer chat listen
  return rankIndex <= 1
end
function NS.ScanRoster()
  wipe(rankOf); wipe(firstCount); rosterHasSurnames = false
  local n = GetNumGuildMembers and GetNumGuildMembers() or 0
  for i = 1, n do
    local full, _, rankIndex = GetGuildRosterInfo(i)
    if full then
      local id = NS.Id(full)
      rankOf[id] = rankIndex; NS.LearnName(full)
      if (id:match("^[^%-]+") or ""):find(" ") then rosterHasSurnames = true end
      local f = firstId(id); firstCount[f] = (firstCount[f] or 0) + 1
    end
  end
  wipe(officerRank)
  if db then NS.Normalize() end
end
-- is this player one of us? (their guild says Dog, or they're on our roster)
function NS.IsDogMember(key, guild)
  if guild and guild:lower() == NS.GUILD then return true end
  return rankFor(key and NS.Id(key)) ~= nil
end

function NS.IsMainAdmin(who) return NS.ADMINS[base(who or NS.MyFull())] == true end

-- editors: guild members the main admin has given edit/delete rights
-- db.ed[name] = {v = 1 (editor) or 0 (removed), m = when}
function NS.IsEditor(who) local id = NS.Id(who); local r = id and db and db.ed and db.ed[id]; return r ~= nil and r.v == 1 end
function NS.Editors()
  local out = {}
  for id, r in pairs(db.ed) do if r.v == 1 then out[#out + 1] = NS.Display(id) end end
  table.sort(out); return out
end
function NS.ApplyEditor(name, v, m)
  name = NS.Canon(NS.Clean(name, 60)); v = tonumber(v) == 1 and 1 or 0; m = tonumber(m) or 0
  if not name or name:find("[,=:]") then return false end
  local r = db.ed[name]
  if r and r.m >= m then return false end
  db.ed[name] = {v = v, m = m}
  if m > (db.maxM or 0) then db.maxM = m end
  NS.Changed(); return true
end
function NS.SetEditor(name, on)
  if not NS.IsMainAdmin() then return end
  local typed = NS.Clean(name, 60)
  local key = NS.Id(typed)
  if not key then return end
  if on and not typed:find(" ") and (firstCount[key] or 0) > 1 then
    print("|cff" .. NS.GOLD .. "Book of Dogs|r: |cffff5555more than one " .. typed .. " is in <Dog>. Type the full name, like \"" .. typed .. " Surname\".|r")
    return
  end
  if on and rankOf[key] == nil then
    -- a first name alone: use the one guild member with it
    if not typed:find(" ") and firstCount[key] == 1 then
      for k in pairs(rankOf) do if firstId(k) == key then key = k; break end end
    end
  end
  if on and rankOf[key] == nil and next(rankOf) ~= nil then
    print("|cff" .. NS.GOLD .. "Book of Dogs|r: |cffff5555" .. NS.Clean(name, 60) .. " isn't in <Dog>. Check the spelling.|r")
    return
  end
  local m = math.max(now(), ((db.ed[key] or {}).m or 0) + 1)
  if NS.ApplyEditor(key, on and 1 or 0, m) then
    NS.Send(table.concat({"G", key, on and 1 or 0, m}, "\t"))
    print(("|cff%sBook of Dogs|r: %s %s."):format(NS.GOLD, NS.Display(key), on and "can now edit and delete entries" or "is no longer an editor"))
  end
  return true
end

function NS.CanDelete(who)
  who = NS.Id(who or NS.MyFull())
  if not who then return false end
  if NS.ADMINS[base(who)] then return true end
  if NS.IsEditor(who) then return true end
  local r = rankFor(who)
  if r == nil and who == NS.MyId() then
    if C_GuildInfo and C_GuildInfo.IsGuildOfficer and C_GuildInfo.IsGuildOfficer() then return true end
    if IsGuildLeader and IsGuildLeader() then return true end
    return false
  end
  if r == nil then return false end
  if officerRank[r] == nil then officerRank[r] = rankIsOfficer(r) end
  return officerRank[r]
end

------------------------------------------------------------------------
-- text
------------------------------------------------------------------------
function NS.Clean(s, max)
  s = tostring(s or "")
  s = s:gsub("|[cC]%x%x%x%x%x%x%x%x", ""):gsub("|[rR]", ""):gsub("|H.-|h(.-)|h", "%1")
       :gsub("|[TtAaKk].-|[tak]", ""):gsub("|", ""):gsub("[%c]", " "):gsub("%s+", " ")
  s = s:match("^%s*(.-)%s*$")
  if max and #s > max then
    s = s:sub(1, max)
    s = s:gsub("[\192-\255][\128-\191]*$", "") -- never cut a UTF-8 letter in half
  end
  return s
end

------------------------------------------------------------------------
-- entries
-- e = {n=name, f=full name, g=guild, c=class, d=desc, a=author, t=created, m=modified,
--      s=score, v={[voter]=1|-1}, x=deleted-at}
------------------------------------------------------------------------
function NS.DB() return db end
local function changed() NS.dirty = true; for _, fn in ipairs(NS.listeners) do fn() end end
NS.Changed = changed

local function bump(m) if m and m > (db.maxM or 0) then db.maxM = m end end

function NS.NewId()
  return string.format("%x%02x", now(), math.random(0, 255))
end

-- returns true if anything changed
-- ids are short hex strings; anything else is ignored
function NS.ValidId(id) return type(id) == "string" and #id <= 12 and id:match("^%x+$") ~= nil end

function NS.ClassColor(class)
  if (issecretvalue and issecretvalue(class)) or type(class) ~= "string" then return end
  local color = RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
  if color then return color end
  if C_ClassColor and C_ClassColor.GetClassColor then return C_ClassColor.GetClassColor(class) end
end

-- canEdit: may this change an existing entry? (admin edits, or a sync reply)
-- ed: who last edited it
-- canFillClass: a live announcement from the author can fill a missing class
function NS.ApplyEntry(id, t, m, n, g, a, d, f, canEdit, ed, class, canFillClass)
  t, m = tonumber(t) or 0, tonumber(m) or 0
  ed = ed and NS.Clean(ed, 60) or ""
  if not NS.ClassColor(class) then class = nil end
  if not NS.ValidId(id) then return false end
  -- everything from the network is cleaned and length-capped before it is stored or shown
  n, g, a, f = NS.Clean(n, 60), NS.Clean(g, 40), NS.Clean(a, 60), NS.Clean(f, 40)
  d = NS.Clean(d, NS.MAXDESC)
  if n == "" or d == "" then return false end
  if NS.Blocked(d) or NS.Blocked(f) or NS.Blocked(n) or NS.Blocked(g) then return false end
  if NS.IsDogMember(n, g) then return false end -- guildmates can't be added
  local e = db.e[id]
  if e then
    if e.x then return false end -- deleted stays deleted
    if not canEdit or m <= (e.m or 0) then
      -- A sync reply may predate a local edit or vote. Keep that newer data.
      if class and not e.c and (canEdit or canFillClass) then
        e.c = class
        changed(); return true
      end
      return false
    end
    class = class or e.c -- older clients and ordinary edits omit the class
    local same = e.n == n and e.d == d and (e.g or "") == g and (e.f or "") == f and e.c == class
    e.n, e.d, e.g, e.f = n, d, g ~= "" and g or nil, f ~= "" and f or nil
    e.c = class
    if ed ~= "" then e.ed = ed end
    e.m = m
    if same then bump(m); return false end
  else
    db.e[id] = {n = n, f = (f ~= "" and f) or nil, g = (g ~= "" and g) or nil, d = d,
                a = a ~= "" and a or "?", t = t, m = m, s = 0, ed = ed ~= "" and ed or nil, c = class}
  end
  bump(m); changed(); return true
end

function NS.ApplyVote(id, voter, val, m)
  local e = db.e[id]
  if not e or e.x or type(voter) ~= "string" then return false end
  voter = NS.Canon(NS.Clean(voter, 60))
  if not voter then return false end
  val, m = tonumber(val) or 0, tonumber(m) or now()
  if val > 0 then val = 1 elseif val < 0 then val = -1 else val = nil end
  e.v = e.v or {}
  local old = e.v[voter]
  if old == val then if m > (e.m or 0) then e.m = m; bump(m) end return false end
  e.s = (e.s or 0) - (old or 0) + (val or 0)
  e.v[voter] = val
  if not next(e.v) then e.v = nil end
  if m > (e.m or 0) then e.m = m end
  bump(m); changed(); return true
end

function NS.ApplyDelete(id, x)
  if not NS.ValidId(id) then return false end
  local e = db.e[id]
  x = tonumber(x) or now()
  if e and e.x then return false end
  -- keep only a tombstone so an out-of-date member can't sync it back in
  db.e[id] = {x = x, m = x}
  bump(x); changed(); return true
end

-- local actions ---------------------------------------------------------
function NS.Add(name, realm, guild, desc, full, manual, class)
  if manual and not NS.CanDelete() then return end
  if not NS.InDog() then print("|cff" .. NS.GOLD .. "Book of Dogs|r: only members of <Dog> can add entries."); return end
  local n = NS.Key(name, realm)
  desc = NS.Clean(desc, NS.MAXDESC)
  if not n or desc == "" then return end
  if NS.IsDogMember(n, guild) then
    print("|cff" .. NS.GOLD .. "Book of Dogs|r: |cffff5555members of <Dog> can't be added. The Book is for players from other guilds.|r")
    return
  end
  if NS.Blocked(desc) then
    print("|cff" .. NS.GOLD .. "Book of Dogs|r: |cffff5555that description has language that isn't allowed in the Book.|r")
    return
  end
  local id, t = NS.NewId(), now()
  full = full and full ~= name and NS.Clean(full, 40) or ""
  guild = NS.Clean(guild or "", 40)
  NS.ApplyEntry(id, t, t, n, guild, NS.Display(NS.MyId()), desc, full, nil, nil, class)
  NS.SendEntry(id)
  -- announce in guild chat (this runs from the popup's button click)
  local who = full ~= "" and full or n
  -- the #id at the end lets other copies of the addon pick the entry up from guild chat
  -- even when addon messages aren't getting through
  local head = ("[Book of Dogs] %s added %s%s: \""):format(NS.Display(NS.MyId()), who, guild ~= "" and (" <" .. guild .. ">") or "")
  local tail = "\" #" .. id
  local room = 255 - #head - #tail
  local body = desc
  if #body > room then body = body:sub(1, room - 3):gsub("[\192-\255][\128-\191]*$", "") .. "..." end
  local msg = head .. body .. tail
  pcall(SendChatMessage, msg, "GUILD")
  return id
end

-- admins (GM, officers, CHogan) can edit any entry; votes are kept
function NS.Edit(id, name, guild, desc)
  local e = db.e[id]
  if not e or e.x or not NS.CanDelete() then return end
  name, guild, desc = NS.Clean(name, 60), NS.Clean(guild, 40), NS.Clean(desc, NS.MAXDESC)
  if name == "" or desc == "" then return end
  local function no(msg) print("|cff" .. NS.GOLD .. "Book of Dogs|r: |cffff5555" .. msg .. "|r") end
  if NS.IsDogMember(name, guild) then return no("members of <Dog> can't be in the Book.") end
  if NS.Blocked(desc) or NS.Blocked(name) or NS.Blocked(guild) then return no("that has language that isn't allowed in the Book.") end
  local m = math.max(now(), (e.m or 0) + 1)
  -- the full name is dropped on edit: the name field is what shows
  if NS.ApplyEntry(id, e.t, m, name, guild, e.a, desc, "", true, NS.Display(NS.MyId())) then
    NS.Send(table.concat({"E", id, m, name, guild, desc}, "\t"))
  end
  return true
end

function NS.Vote(id, val)
  if not NS.InDog() then return end
  local e = db.e[id]; if not e or e.x then return end
  local me = NS.MyId()
  local mine = e.v and e.v[me]
  -- every click moves the score by exactly 1: clicking either arrow while you
  -- already have a vote takes your vote back first
  if mine then val = 0 end
  local m = math.max(now(), (e.m or 0) + 1)
  if NS.ApplyVote(id, me, val, m) then NS.Send(("V\t%s\t%d\t%d"):format(id, val, m)) end
end

function NS.Delete(id)
  if not NS.CanDelete() then return end
  local x = now()
  if NS.ApplyDelete(id, x) then NS.Send(("D\t%s\t%d"):format(id, x)) end
end

------------------------------------------------------------------------
-- sorted view: score high to low, then newest
------------------------------------------------------------------------
local sorted = {}
function NS.Sorted(filter)
  if NS.dirty then
    wipe(sorted)
    for id, e in pairs(db.e) do if not e.x then sorted[#sorted + 1] = id end end
    local E = db.e
    table.sort(sorted, function(a, b)
      local x, y = E[a], E[b]
      if (x.s or 0) ~= (y.s or 0) then return (x.s or 0) > (y.s or 0) end
      return (x.t or 0) > (y.t or 0)
    end)
    NS.dirty = false
  end
  if not filter or filter == "" then return sorted end
  filter = filter:lower()
  local out = {}
  for _, id in ipairs(sorted) do
    local e = db.e[id]
    if (e.n or ""):lower():find(filter, 1, true) or (e.f or ""):lower():find(filter, 1, true)
       or (e.d or ""):lower():find(filter, 1, true) or (e.g or ""):lower():find(filter, 1, true) then
      out[#out + 1] = id
    end
  end
  return out
end

------------------------------------------------------------------------
-- housekeeping: purge old tombstones, cap the book size
------------------------------------------------------------------------
local function prune()
  local cutoff, live = now() - NS.TOMB_DAYS * 86400, {}
  for id, e in pairs(db.e) do
    if e.x then
      if e.x < cutoff then db.e[id] = nil end
    else
      live[#live + 1] = id
    end
  end
  if #live > NS.MAXENTRIES then
    table.sort(live, function(a, b)
      local x, y = db.e[a], db.e[b]
      if (x.s or 0) ~= (y.s or 0) then return (x.s or 0) < (y.s or 0) end
      return (x.t or 0) < (y.t or 0)
    end)
    for i = 1, #live - NS.MAXENTRIES do db.e[live[i]] = nil end
  end
  NS.Normalize()
end

------------------------------------------------------------------------
-- one key per person: merge "Chogan", "Chogan-Realm", "Chogan Seventythree" and
-- the squashed "ChoganSeventythree" (an older version's key) into one, then recount
------------------------------------------------------------------------
-- any form of a name -> the one id, including the squashed "ChoganSeventythree"
function NS.Canon(k)
  local id = NS.Id(k)
  if not id then return nil end
  local nm, realm = id:match("^([^%-]+)%-(.*)$")
  if nm and not nm:find(" ") then
    -- an older version's key: just a first name, or the squashed "ChoganSeventythree"
    local d = db and db.names and db.names[id]
    if d and d:find(" ") then return NS.Id(d .. "-" .. realm) end
    for _, disp in pairs(db and db.names or {}) do
      if disp:find(" ") and (disp:gsub("%s", "")) == nm then return NS.Id(disp .. "-" .. realm) end
    end
  end
  return id
end
function NS.Normalize()
  local fix = NS.Canon
  for _, e in pairs(db.e) do
    if not e.x then
      if e.v then
        local merged = {}
        for who, v in pairs(e.v) do local k = fix(who); if k and merged[k] == nil then merged[k] = v end end
        e.v = next(merged) and merged or nil
      end
      local s = 0
      if e.v then for _, v in pairs(e.v) do s = s + v end end
      e.s = s
    end
  end
  if db.ed then
    local merged = {}
    for who, r in pairs(db.ed) do
      local k = (tostring(who):match("^[^%-]+") or ""):find(" ") and NS.Id(who) or nil
      if k and (not merged[k] or merged[k].m < r.m) then merged[k] = r end
    end
    db.ed = merged
  end
  NS.dirty = true
end

------------------------------------------------------------------------
-- startup
------------------------------------------------------------------------
local f = CreateFrame("Frame")
f:RegisterEvent("ADDON_LOADED")
f:RegisterEvent("PLAYER_LOGIN")
f:RegisterEvent("GUILD_ROSTER_UPDATE")
f:SetScript("OnEvent", function(_, event, arg)
  if event == "ADDON_LOADED" and arg == ADDON then
    BookOfDogsDB = BookOfDogsDB or {}
    db = BookOfDogsDB
    db.e = db.e or {}
    db.maxM = db.maxM or 0
    db.ed = db.ed or {}
    prune()
    NS.dirty = true
  elseif event == "PLAYER_LOGIN" then
    NS.LearnName(NS.MyFull() .. "-" .. NS.MyRealm())
    if C_GuildInfo and C_GuildInfo.GuildRoster then C_GuildInfo.GuildRoster() elseif GuildRoster then GuildRoster() end
    if NS.CommStart then NS.CommStart() end
  elseif event == "GUILD_ROSTER_UPDATE" then
    NS.ScanRoster()
  end
end)

SLASH_BOOKOFDOGS1, SLASH_BOOKOFDOGS2 = "/dogs", "/bookofdogs"
SlashCmdList.BOOKOFDOGS = function(msg)
  msg = (msg or ""):lower():match("^%s*(.-)%s*$")
  if msg == "sync" then
    NS.RequestSync(true)
  elseif msg == "rebuild" then
    -- start over from the guild's copy: clears this book (not the editors list) and asks for everything
    wipe(db.e); db.maxM = 0; NS.dirty = true; NS.Changed()
    print("|cff" .. NS.GOLD .. "Book of Dogs|r: cleared your copy; pulling the whole book from guildmates online...")
    NS.RequestSync(true)
  elseif msg == "minimap" then
    NS.ToggleMinimap()
  elseif msg == "add" then
    if UnitExists("target") and UnitIsPlayer("target") then NS.ShowAddPopup("target") else print("|cff" .. NS.GOLD .. "Book of Dogs|r: target a player first.") end
  elseif msg == "status" then
    local n = 0; for _, e in pairs(db.e) do if not e.x then n = n + 1 end end
    print(("|cff%sBook of Dogs|r v" .. ((C_AddOns and C_AddOns.GetAddOnMetadata or GetAddOnMetadata)(ADDON, "Version") or "?") .. ": %d entries. In <Dog>: %s. Can delete: %s. Guild sync: %s."):format(NS.GOLD, n,
      NS.InDog() and "yes" or "no", NS.CanDelete() and "yes" or "no", NS.CommStatus()))
    local st = NS.stats or {}
    local r1 = C_ChatInfo.AreOutgoingAddonChatMessagesRestricted and tostring(C_ChatInfo.AreOutgoingAddonChatMessagesRestricted()) or "n/a"
    local r2 = C_ChatInfo.InChatMessagingLockdown and tostring(C_ChatInfo.InChatMessagingLockdown()) or "n/a"
    print(("|cff%sBook of Dogs|r debug: sent %d, failed %d (last result %s), queued %d, received %d, from chat %d. Restricted=%s Lockdown=%s"):format(
      NS.GOLD, st.sent or 0, st.failed or 0, tostring(st.lastRes), st.queued or 0, st.recv or 0, st.chat or 0, r1, r2))
    local eds = NS.Editors()
    if #eds > 0 then print("|cff" .. NS.GOLD .. "Book of Dogs|r editors: " .. table.concat(eds, ", ")) end
  else
    NS.Toggle()
  end
end
