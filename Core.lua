-- Book of Dogs: core data, voting, permissions.
-- Saved data is kept small: one short table per entry, short keys,
-- descriptions capped, deleted entries shrink to a tombstone and are purged.
local ADDON, NS = ...

NS.PREFIX     = "BookOfDogs"
local LEGACY_GUILD = "dog"
local DEFAULT_FEED = "default"
NS.MAXDESC    = 200
NS.MAXENTRIES = 500
NS.TOMB_DAYS  = 30
NS.GOLD, NS.RED = "ffcc33", "993333"
-- Votes are counted per BattleTag account (see Account.lua). While this is false, a
-- client that can't read its BattleTag, and older versions that don't send it, still
-- vote per character. Turn it on once the whole guild is on a version that sends it:
-- untagged votes are then ignored and a client without a BattleTag can't vote.
NS.REQUIRE_BTAG = false

local db, activeGuild, activeSeed, guildName
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
-- On Forever, UnitName(unit) returns the first name and the SURNAME ("Baeth",
-- "Warbreaker"), not name and realm. Turn that pair into the full name; a second
-- value that is our own realm is treated as a realm.
function NS.FullFrom(first, second)
  if type(first) ~= "string" or first == "" then return nil end
  if type(second) == "string" and second ~= "" and (second:gsub("[%s%-]", "")) ~= NS.MyRealm() then
    return first .. " " .. second
  end
  return first
end

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
  local a, b = UnitName("player")
  local f = NS.FullFrom(a, b)
  if f and f:find(" ", 1, true) then myFull = f; return myFull end
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
local firstIdx -- lowercase first name -> voter signature (see NS.VoterSig); rebuilt when a new name is learned
function NS.LearnName(raw)
  if not db or type(raw) ~= "string" or (issecretvalue and issecretvalue(raw)) then return end
  local id = NS.Id(raw); if not id then return end
  local nm = id:match("^[^%-]+") -- the realm is never shown
  if names()[id] ~= nm then names()[id] = nm; firstIdx = nil end
end
-- how to show a person: their full in-game name, without the realm
function NS.Display(who)
  local id = NS.Canon and db and NS.Canon(who) or NS.Id(who)
  local n = id and db and db.names and db.names[id] or (id or tostring(who or "?"))
  return (n:match("^[^%-]+") or n)
end

-- One person = one vote. The same player can show up under several keys (just the
-- first name, the full name, the full name squashed together, or a differently
-- formatted realm), so voters are compared by a signature instead of the raw key:
-- the lowercase name with spaces removed. A bare first name takes the signature of
-- the one full name we know that starts with it; if two known players share that
-- first name it stays on its own, since it can't be told apart.
local function squashLower(s) return (s:gsub("%s", ""):lower()) end
local function hasSpace(id) return ((id or ""):match("^[^%-]+") or ""):find(" ", 1, true) ~= nil end
local function buildFirstIdx()
  firstIdx = {}
  for id in pairs(names()) do
    local nm = id:match("^[^%-]+")
    if nm and nm:find(" ", 1, true) then
      local first, sig = nm:match("^%S+"):lower(), squashLower(nm)
      local cur = firstIdx[first]
      if cur == nil then firstIdx[first] = sig elseif cur ~= sig then firstIdx[first] = false end
    end
  end
end
-- the one full name (as a signature) a bare first name stands for, if we know exactly one
function NS.FullSigOf(first)
  if not firstIdx then buildFirstIdx() end
  return firstIdx[first:lower()] or nil
end
function NS.VoterSig(raw)
  if NS.IsAcctKey(raw) then return raw end       -- already an account
  local acct = NS.AcctOf(raw)                     -- a character we know belongs to an account
  if acct then return NS.AcctKey(acct) end
  local id = NS.Id(raw); if not id then return nil end
  local nm = id:match("^[^%-]+")
  if nm:find(" ", 1, true) then return squashLower(nm) end
  local lo = nm:lower()
  if not firstIdx then buildFirstIdx() end
  return firstIdx[lo] or lo
end
-- the key this person already votes under on an entry (or the key given, if none)
local function voterKeyIn(votes, voter)
  if not votes or votes[voter] ~= nil then return voter end
  local sig = NS.VoterSig(voter)
  for k in pairs(votes) do if NS.VoterSig(k) == sig then return k end end
  return voter
end
-- someone's current vote on an entry: 1, -1 or nil
function NS.VoteOf(e, who)
  if not e or not e.v then return nil end
  local id = NS.Canon and NS.Canon(who) or NS.Id(who)
  return id and e.v[voterKeyIn(e.v, id)] or nil
end

local function base(name) local id = NS.Id(name); return id and id:match("^[^%-]+"):lower() or "" end
local function firstId(id) local nm, realm = id:match("^(%S+).-%-(.*)$"); return nm and (nm .. "-" .. realm) or id end

------------------------------------------------------------------------
-- guild membership and ranks
------------------------------------------------------------------------
local function currentGuild()
  if not IsInGuild() then return end
  local name, _, _, realm = GetGuildInfo("player")
  if (issecretvalue and (issecretvalue(name) or issecretvalue(realm))) or not name or name == "" then return end
  realm = realm and realm:gsub("[%s%-]", "") or ""
  if realm == "" then realm = NS.MyRealm() end
  return realm:lower() .. ":" .. name:lower(), name
end

function NS.InGuildFeed()
  return activeGuild ~= nil and activeGuild == currentGuild()
end

function NS.LegacyFeed()
  return activeGuild ~= nil and activeGuild == BookOfDogsDB.legacyGuild and activeSeed == DEFAULT_FEED
end

function NS.FeedPrefix()
  return NS.LegacyFeed() and "" or activeSeed .. "\t"
end

function NS.FeedName() return activeSeed end

function NS.FeedLabel(seed)
  local profile = activeGuild and BookOfDogsDB.feeds[activeGuild]
  return profile and profile.labels and profile.labels[seed or activeSeed]
end

function NS.SetFeedLabel(label)
  if not NS.InGuildFeed() then return false, "Join a guild to label a feed." end
  label = NS.Clean(label)
  local _, length = label:gsub("[^\128-\191]", "")
  if length > 32 then return false, "Enter a label of up to 32 characters." end
  local profile = BookOfDogsDB.feeds[activeGuild]
  profile.labels = profile.labels or {}
  profile.labels[activeSeed] = label ~= "" and label or nil
  NS.Changed()
  return true
end

function NS.FeedChoices()
  if not NS.InGuildFeed() then return {} end
  local seeds = {}
  for seed in pairs(BookOfDogsDB.feeds[activeGuild].books) do
    if seed ~= DEFAULT_FEED then seeds[#seeds + 1] = seed end
  end
  table.sort(seeds)
  table.insert(seeds, 1, DEFAULT_FEED)
  return seeds
end

local rankOf, officerRank = {}, {}
local firstCount, rosterHasSurnames, rosterReady = {}, false, false
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
  rosterReady = n > 0
  for i = 1, n do
    local full, _, rankIndex = GetGuildRosterInfo(i)
    local id = full and NS.Id(full)
    if id and rankIndex ~= nil then
      rankOf[id] = rankIndex; NS.LearnName(full)
      if (id:match("^[^%-]+") or ""):find(" ") then rosterHasSurnames = true end
      local f = firstId(id); firstCount[f] = (firstCount[f] or 0) + 1
    else
      rosterReady = false
    end
  end
  wipe(officerRank)
  if db then NS.Normalize() end
end
-- Check the active guild's name and roster.
function NS.IsGuildmate(key, guild)
  if guildName and guild and guild:lower() == guildName:lower() then return true end
  return rankFor(key and NS.Id(key)) ~= nil
end

function NS.IsMainAdmin(who)
  if not NS.InGuildFeed() then return false end
  local id = NS.Id(who or NS.MyFull())
  if NS.LegacyFeed() then return base(id) == "chogan seventythree" end
  return (id ~= nil and rankOf[id] == 0)
         or ((not who or id == NS.MyId()) and IsGuildLeader and IsGuildLeader())
end

-- editors: guild members the main admin has given edit/delete rights
-- db.ed[name] = {v = 1 (editor) or 0 (removed), m = when}
local function editorId(name)
  local id = NS.Id(name)
  if not id or id:match("^[^%-]+"):find(" ", 1, true) or not rosterReady then return id end
  -- Older clients stored the first name or the full name without spaces.
  -- Keep the original record until the roster identifies exactly one match.
  local match
  for member in pairs(rankOf) do
    local memberName, realm = member:match("^([^%-]+)%-(.*)$")
    if firstId(member) == id or memberName:gsub(" ", "") .. "-" .. realm == id then
      if match then return id end
      match = member
    end
  end
  return match or id
end

local function editorUpdateWins(v, m, previous)
  return not previous or m > previous.m or (m == previous.m and v == 0 and previous.v == 1)
end

function NS.IsEditor(who)
  local id = NS.Id(who)
  local r = id and db and db.ed and db.ed[id]
  if not r or r.v ~= 1 then return false end
  if id:match("^[^%-]+"):find(" ", 1, true) then return true end
  -- Single-name characters are valid on Classic. An unresolved Forever alias
  -- must never grant rights to someone who only shares the first name.
  return rosterReady and not rosterHasSurnames and rankOf[id] ~= nil
         and not (RegionalUniqueNamesEnabled and RegionalUniqueNamesEnabled())
end
function NS.Editors()
  local out = {}
  for id, r in pairs(db.ed) do
    if r.v == 1 then
      local name, realm = id:match("^([^%-]+)%-(.*)$")
      out[#out + 1] = realm == NS.MyRealm() and name or id
    end
  end
  table.sort(out); return out
end
function NS.ApplyEditor(name, v, m)
  name = editorId(NS.Clean(name, 60)); v = tonumber(v) == 1 and 1 or 0; m = tonumber(m) or 0
  if not name or name:find("[,=:]") then return false end
  local r = db.ed[name]
  if not editorUpdateWins(v, m, r) then return false end
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
  key = editorId(key)
  local m = math.max(now(), ((db.ed[key] or {}).m or 0) + 1)
  if NS.ApplyEditor(key, on and 1 or 0, m) then
    NS.Send(table.concat({"G", key, on and 1 or 0, m}, "\t"))
    print(("|cff%sBook of Dogs|r: %s %s."):format(NS.GOLD, NS.Display(key), on and "can now edit and delete entries" or "is no longer an editor"))
  end
  return true
end

function NS.CanDelete(who)
  if not NS.InGuildFeed() then return false end
  who = NS.Id(who or NS.MyFull())
  if not who then return false end
  if NS.IsMainAdmin(who) then return true end
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

local function cleanDescription(desc)
  desc = NS.Clean(desc)
  if NS.Blocked(desc) then return end
  desc = NS.Clean(desc, NS.MAXDESC)
  if not NS.Blocked(desc) then return desc end
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

-- canEdit: may this change an existing entry? (admin edits, or a sync reply)
-- ed: who last edited it
-- canFillClass: a live announcement from the author can fill a missing class
function NS.ApplyEntry(id, t, m, n, g, a, d, f, canEdit, ed, class, canFillClass)
  if not NS.InGuildFeed() then return false end
  t, m = tonumber(t) or 0, tonumber(m) or 0
  ed = ed and NS.Clean(ed, 60) or ""
  if (issecretvalue and issecretvalue(class)) or type(class) ~= "string"
     or not (RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]) then
    class = nil
  end
  if not NS.ValidId(id) then return false end
  -- everything from the network is cleaned and length-capped before it is stored or shown
  n, g, a, f = NS.Clean(n, 60), NS.Clean(g, 40), NS.Clean(a, 60), NS.Clean(f, 40)
  d = cleanDescription(d)
  if n == "" or not d or d == "" then return false end
  if NS.Blocked(f) or NS.Blocked(n) or NS.Blocked(g) or NS.Blocked(a) or NS.Blocked(ed) then return false end
  if NS.IsGuildmate(n, g) then return false end -- guildmates can't be added
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
  -- a voter is a BattleTag account key ("#" + hash) when known, else a character
  if not NS.IsAcctKey(voter) then
    voter = NS.Canon(NS.Clean(voter, 60))
    if not voter then return false end
    local acct = NS.AcctOf(voter) -- a character we know belongs to an account votes as that account
    if acct then voter = NS.AcctKey(acct) end
  end
  -- only a real vote (1, -1) or taking one back (0) is accepted; anything else is junk
  val = tonumber(val)
  if val ~= 1 and val ~= -1 and val ~= 0 then return false end
  m = tonumber(m) or now()
  if val == 0 then val = nil end
  -- everything already recorded for this person (the same account or character under any key)
  local sig, keys, sum = NS.VoterSig(voter), {}, 0
  if e.v then
    for k, v in pairs(e.v) do
      if k == voter or NS.VoterSig(k) == sig then keys[#keys + 1] = k; sum = sum + v end
    end
  end
  table.sort(keys)
  -- the key the vote is kept under: an account key as is; a bare first name gives way
  -- to the full-name key already on file
  local target = voter
  if not NS.IsAcctKey(voter) and not hasSpace(voter) then
    for _, k in ipairs(keys) do if hasSpace(k) then target = k; break end end
  end
  local cur
  if e.v and e.v[target] ~= nil then cur = e.v[target] elseif keys[1] then cur = e.v[keys[1]] end
  if cur == val and #keys <= 1 then
    -- already recorded this way: just make sure it sits under the preferred key
    if keys[1] and keys[1] ~= target then e.v[keys[1]] = nil; e.v[target] = val end
    if m > (e.m or 0) then e.m = m; bump(m) end
    return false
  end
  -- one person, one vote: replace everything they had with this one
  e.v = e.v or {}
  for _, k in ipairs(keys) do e.v[k] = nil end
  e.s = (e.s or 0) - sum + (val or 0)
  e.v[target] = val
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
  if not NS.InGuildFeed() then print("|cff" .. NS.GOLD .. "Book of Dogs|r: join a guild to add entries."); return end
  local n = NS.Key(name, realm)
  desc = cleanDescription(desc)
  if not n or desc == "" then return end
  if NS.IsGuildmate(n, guild) then
    print("|cff" .. NS.GOLD .. "Book of Dogs|r: |cffff5555guildmates can't be added. The Book is for players from other guilds.|r")
    return
  end
  if not desc then
    print("|cff" .. NS.GOLD .. "Book of Dogs|r: |cffff5555that description has language that isn't allowed in the Book.|r")
    return
  end
  local id, t = NS.NewId(), now()
  full = full and full ~= name and NS.Clean(full, 40) or ""
  guild = NS.Clean(guild or "", 40)
  if not NS.ApplyEntry(id, t, t, n, guild, NS.Display(NS.MyId()), desc, full, nil, nil, class) then return end
  NS.SendEntry(id)
  if not NS.LegacyFeed() then return id end
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

-- classes: the game's own tokens, colors and names
NS.CLASSES = {"WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "SHAMAN", "MAGE", "WARLOCK", "DRUID"}
function NS.ValidClass(c) return type(c) == "string" and RAID_CLASS_COLORS ~= nil and RAID_CLASS_COLORS[c] ~= nil end
-- "ffRRGGBB" for a class (built from r/g/b if the game's table has no colorStr)
function NS.ClassColor(c)
  local col = NS.ValidClass(c) and RAID_CLASS_COLORS[c]
  if not col then return nil end
  if col.colorStr then return col.colorStr end
  return string.format("ff%02x%02x%02x", (col.r or 1) * 255, (col.g or 1) * 255, (col.b or 1) * 255)
end
function NS.ClassName(c)
  if not NS.ValidClass(c) then return nil end
  local n = (LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[c])
  return n or (c:sub(1, 1) .. c:sub(2):lower())
end
-- "Name" in class color (plain when the class isn't known)
function NS.ColorName(name, c)
  local hex = NS.ClassColor(c)
  return hex and ("|c" .. hex .. name .. "|r") or name
end

-- admins (GM, officers, CHogan) can edit any entry; votes are kept
function NS.Edit(id, name, guild, desc, class)
  local e = db.e[id]
  if not e or e.x or not NS.CanDelete() then return end
  name, guild, desc = NS.Clean(name, 60), NS.Clean(guild, 40), cleanDescription(desc)
  if name == "" or desc == "" then return end
  local function no(msg) print("|cff" .. NS.GOLD .. "Book of Dogs|r: |cffff5555" .. msg .. "|r") end
  if NS.IsGuildmate(name, guild) then return no("guildmates can't be in the Book.") end
  if not desc or NS.Blocked(name) or NS.Blocked(guild) then return no("that has language that isn't allowed in the Book.") end
  local m = math.max(now(), (e.m or 0) + 1)
  -- the full name is dropped on edit: the name field is what shows
  if not NS.ValidClass(class) then class = nil end
  if NS.ApplyEntry(id, e.t, m, name, guild, e.a, desc, "", true, NS.Display(NS.MyId()), class) then
    NS.Send(table.concat({"E", id, m, name, guild, desc, class or ""}, "\t"))
  end
  return true
end

function NS.Vote(id, val)
  if not NS.InGuildFeed() then return end
  local e = db.e[id]; if not e or e.x then return end
  if val ~= 1 and val ~= -1 and val ~= 0 then return end -- 0 takes my vote back
  local me = NS.MyId()
  if not me then return end
  local acct = NS.MyAcct()
  if acct then
    NS.LearnAcct(NS.MyFull(), acct, true) -- my characters all vote as this one account
  elseif NS.REQUIRE_BTAG then
    print("|cff" .. NS.GOLD .. "Book of Dogs|r: |cffff5555couldn't read your BattleTag, so you can't vote right now. Make sure you're connected to Battle.net.|r")
    return
  elseif not NS.toldNoTag then
    NS.toldNoTag = true
    print("|cff" .. NS.GOLD .. "Book of Dogs|r: couldn't read your BattleTag, so your votes count per character instead of per account.")
  end
  -- one vote per person: voting the way you already have does nothing, the other arrow
  -- changes your vote (the score moves by 2), and 0 takes your vote back
  if (NS.VoteOf(e, me) or 0) == val then return end
  local m = math.max(now(), (e.m or 0) + 1)
  if NS.ApplyVote(id, acct and NS.AcctKey(acct) or me, val, m) then
    NS.Send(("V\t%s\t%d\t%d\t%s"):format(id, val, m, acct or ""))
  end
end

function NS.Delete(id)
  if not NS.CanDelete() then return end
  local x = now()
  if NS.ApplyDelete(id, x) then NS.Send(("D\t%s\t%d"):format(id, x)) end
end

-- entries about a player (by full name when known, else by name), best score first
function NS.FindEntries(key, full)
  local out = {}
  if not key or not db then return out end
  local fullCand = (full and full ~= "" and full) or (key:find(" ", 1, true) and key) or nil
  for id, e in pairs(db.e) do
    if not e.x then
      local hit
      if fullCand then
        hit = e.f == fullCand or e.n == fullCand or (not e.f and e.n == fullCand:match("^%S+"))
      else
        hit = e.n == key or (e.f ~= nil and e.f:match("^%S+") == key)
      end
      if hit then out[#out + 1] = id end
    end
  end
  table.sort(out, function(a, b) return (db.e[a].s or 0) > (db.e[b].s or 0) end)
  return out
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
-- Also the duplicate-vote purge: every entry's votes are regrouped one per person
-- (see NS.VoterSig), invalid votes are dropped, and the scores are recounted. It is
-- safe to run any number of times, and runs on load and on every roster update, so
-- a book that already holds duplicates cleans itself up as soon as this version loads.
local purgedTotal, purgeNoticeQueued = 0, false
local function purgeNotice(removed)
  purgedTotal = purgedTotal + removed
  if purgeNoticeQueued then return end
  purgeNoticeQueued = true
  C_Timer.After(6, function() -- let the chat frames come up first
    purgeNoticeQueued = false
    if purgedTotal > 0 then
      print(("|cff%sBook of Dogs|r: cleaned up %d duplicate vote%s."):format(NS.GOLD, purgedTotal, purgedTotal == 1 and "" or "s"))
    end
    purgedTotal = 0
  end)
end
function NS.Normalize()
  local fix = NS.Canon
  local touched, removed = false, 0
  for _, e in pairs(db.e) do
    if not e.x then
      if e.v then
        local before, groups = 0, {}
        for who, v in pairs(e.v) do
          before = before + 1
          local sig = (v == 1 or v == -1) and NS.VoterSig(who) or nil
          if sig then
            groups[sig] = groups[sig] or {}
            table.insert(groups[sig], who)
          end
        end
        local merged, after = {}, 0
        for sig, keys in pairs(groups) do
          table.sort(keys)
          local rep = keys[1]
          for _, k in ipairs(keys) do if hasSpace(k) then rep = k; break end end -- the full-name key is the real one
          for _, k in ipairs(keys) do if NS.IsAcctKey(k) then rep = k; break end end -- an account key beats any character
          -- an account's votes all live under its account key, whichever characters cast them
          local key, vote = NS.IsAcctKey(sig) and sig or (fix(rep) or rep), e.v[rep]
          if merged[key] == nil then merged[key] = vote; after = after + 1 end
        end
        local same = before == after
        if same then for k in pairs(merged) do if e.v[k] == nil then same = false; break end end end
        if not same then
          removed = removed + math.max(0, before - after)
          touched = true
          e.v = next(merged) and merged or nil
        end
      end
      local s = 0
      if e.v then for _, v in pairs(e.v) do s = s + v end end
      if e.s ~= s then e.s = s; touched = true end
    end
  end
  if removed > 0 then purgeNotice(removed) end
  if touched then NS.Changed() end
  if db.ed then
    local merged = {}
    for who, r in pairs(db.ed) do
      local k = editorId(who)
      if k and editorUpdateWins(r.v, r.m, merged[k]) then merged[k] = r end
      bump(r.m)
    end
    db.ed = merged
  end
  NS.dirty = true
end

------------------------------------------------------------------------
-- startup
------------------------------------------------------------------------
local loggedIn
local function refreshFeed()
  local key, name = currentGuild()
  local profile
  if key then
    local guilds = BookOfDogsDB.feeds
    profile = guilds[key] or {seed = DEFAULT_FEED, books = {}}
    guilds[key] = profile
    if name:lower() == LEGACY_GUILD and not BookOfDogsDB.legacyGuild then
      BookOfDogsDB.legacyGuild = key
    end
  end
  local seed = profile and profile.seed
  if db and activeGuild == key and activeSeed == seed then return end
  local guildChanged = activeGuild ~= key
  if guildChanged then
    wipe(rankOf); wipe(firstCount); wipe(officerRank)
    rosterHasSurnames, rosterReady = false, false
  end
  activeGuild, activeSeed, guildName = key, seed, name
  if NS.LegacyFeed() then
    db = BookOfDogsDB -- keep the original Dog data readable by older releases
  elseif profile then
    db = profile.books[seed] or {}
    profile.books[seed] = db
  else
    db = {}
  end
  db.e, db.ed, db.acct = db.e or {}, db.ed or {}, db.acct or {}
  db.maxM = db.maxM or 0
  NS.FeedRevision = (NS.FeedRevision or 0) + 1
  if loggedIn then NS.CommFeedChanged() end
  prune()
  if loggedIn and key then
    NS.ScanRoster()
    NS.LearnName(NS.MyFull() .. "-" .. NS.MyRealm())
  end
  if NS.CloseFeedDialogs then NS.CloseFeedDialogs(guildChanged) end
  NS.Changed()
  return true
end

function NS.SelectFeed(seed)
  if not NS.InGuildFeed() then
    return false, "Join a guild to select a feed."
  end
  seed = (seed or ""):lower():match("^%s*(.-)%s*$")
  if #seed > 64 or not seed:match("^[%w][%w%-]*$") then
    return false, "Enter a seed of up to 64 letters, numbers, and hyphens."
  end
  BookOfDogsDB.feeds[activeGuild].seed = seed
  refreshFeed()
  return true
end

local function feedCommand(seed)
  refreshFeed()
  if seed then
    local ok, reason = NS.SelectFeed(seed)
    if not ok then print("Book of Dogs: " .. reason); return end
  elseif not NS.InGuildFeed() then
    print("Book of Dogs: join a guild to select a feed.")
    return
  end
  print(("Book of Dogs: %s feed for <%s>. Use /dogs feed <guid> or /dogs feed default."):format(activeSeed, guildName))
end

local f = CreateFrame("Frame")
f:RegisterEvent("ADDON_LOADED")
f:RegisterEvent("PLAYER_LOGIN")
f:RegisterEvent("GUILD_ROSTER_UPDATE")
f:RegisterEvent("PLAYER_GUILD_UPDATE")
f:SetScript("OnEvent", function(_, event, arg)
  if event == "ADDON_LOADED" and arg == ADDON then
    BookOfDogsDB = BookOfDogsDB or {}
    BookOfDogsDB.feeds = BookOfDogsDB.feeds or {}
    refreshFeed()
  elseif event == "PLAYER_LOGIN" then
    refreshFeed()
    loggedIn = true
    if NS.InGuildFeed() then NS.LearnName(NS.MyFull() .. "-" .. NS.MyRealm()) end
    if C_GuildInfo and C_GuildInfo.GuildRoster then C_GuildInfo.GuildRoster() elseif GuildRoster then GuildRoster() end
    if NS.CommStart then NS.CommStart() end
  elseif event == "PLAYER_GUILD_UPDATE" then
    refreshFeed()
  elseif event == "GUILD_ROSTER_UPDATE" then
    local switched = refreshFeed()
    if NS.InGuildFeed() and (not switched or not loggedIn) then NS.ScanRoster() end
  end
end)

SLASH_BOOKOFDOGS1, SLASH_BOOKOFDOGS2 = "/dogs", "/bookofdogs"
SlashCmdList.BOOKOFDOGS = function(msg)
  msg = (msg or ""):lower():match("^%s*(.-)%s*$")
  if msg == "feed" or msg:match("^feed%s") then
    feedCommand(msg:match("^feed%s+(.+)$"))
  elseif msg == "sync" then
    NS.RequestSync(true)
  elseif msg == "rebuild" then
    if not NS.InGuildFeed() then return end
    -- start over from the guild's copy: clears this book (not the editors list) and asks for everything
    wipe(db.e); db.maxM = 0; NS.dirty = true; NS.Changed()
    print("|cff" .. NS.GOLD .. "Book of Dogs|r: cleared your copy; pulling the whole book from guildmates online...")
    NS.RequestSync(true)
  elseif msg == "debug" then
    NS.DebugTarget()
  elseif msg == "minimap" then
    NS.ToggleMinimap()
  elseif msg == "icons" or msg == "plates" or msg == "icon" or msg:match("^icon%s") then
    NS.NameplateCmd(msg)
  elseif msg == "chat" then
    NS.ToggleChatIcons()
  elseif msg == "add" then
    if UnitExists("target") and UnitIsPlayer("target") then NS.ShowAddPopup("target") else print("|cff" .. NS.GOLD .. "Book of Dogs|r: target a player first.") end
  elseif msg == "status" then
    local n = 0; for _, e in pairs(db.e) do if not e.x then n = n + 1 end end
    print(("|cff%sBook of Dogs|r v" .. ((C_AddOns and C_AddOns.GetAddOnMetadata or GetAddOnMetadata)(ADDON, "Version") or "?") .. ": %d entries. Guild: %s. Feed: %s. Can delete: %s. Guild sync: %s."):format(NS.GOLD, n,
      guildName or "none", activeSeed or "none", NS.CanDelete() and "yes" or "no", NS.CommStatus()))
    local known = 0; for _ in pairs(db.acct or {}) do known = known + 1 end
    print(("|cff%sBook of Dogs|r votes: BattleTag %s; %d characters linked to accounts; untagged votes %s."):format(
      NS.GOLD, NS.MyAcct() and "read (votes count per account)" or "NOT readable (your votes count per character)",
      known, NS.REQUIRE_BTAG and "rejected" or "still accepted"))
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
