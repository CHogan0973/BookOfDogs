-- Book of Dogs: guild sync over hidden addon messages.
-- One small message per change, sent through a slow queue that only runs while
-- it has something to send. When you log in, one online member (not everyone)
-- sends you what you missed.
local ADDON, NS = ...
local PREFIX = NS.PREFIX
local SEP = "\t"
local CHUNK = 240

------------------------------------------------------------------------
-- can we send right now?
------------------------------------------------------------------------
-- Like OpenMap, we don't trust the "restricted" flags up front: we just send and
-- read the game's answer. Only being outside a guild stops us.
local function blocked()
  if not IsInGuild() then return "not in a guild" end
  return nil
end
local resultNames
local function resultName(res)
  if type(res) ~= "number" then return tostring(res) end
  if not resultNames then
    resultNames = {}
    for k, v in pairs((Enum and Enum.SendAddonMessageResult) or {}) do resultNames[v] = k end
  end
  return resultNames[res] or tostring(res)
end
function NS.CommStatus()
  local b = blocked(); if b then return b end
  local st = NS.stats
  if (st.sent or 0) > 0 then return "on (" .. st.sent .. " sent)" end
  if (st.failed or 0) > 0 then return "failing: " .. resultName(st.lastRes) end
  return "on (nothing sent yet)"
end

------------------------------------------------------------------------
-- outgoing queue (a ticker that exists only while there is work)
------------------------------------------------------------------------
local queue, head, ticker = {}, 1, nil
NS.stats = {sent = 0, failed = 0, recv = 0, chat = 0, queued = 0}
local function pump()
  if head > #queue then
    wipe(queue); head = 1
    if ticker then ticker:Cancel(); ticker = nil end
    return
  end
  if blocked() then return end -- try again next tick
  local msg = queue[head]
  local ok, res = pcall(C_ChatInfo.SendAddonMessage, PREFIX, msg, "GUILD")
  local R = Enum and Enum.SendAddonMessageResult
  local st = NS.stats
  st.lastRes = ok and res or ("error: " .. tostring(res))
  if ok and R and (res == R.AddonMessageThrottle or res == R.ChannelThrottle) then return end -- retry the same message
  if ok and (res == nil or res == true or res == 0 or (R and res == R.Success)) then st.sent = st.sent + 1 else st.failed = st.failed + 1 end
  st.lastRes = ok and resultName(res) or st.lastRes
  head = head + 1
  st.queued = #queue - head + 1
end
local function push(raw)
  queue[#queue + 1] = raw
  NS.stats.queued = #queue - head + 1
  if not ticker then ticker = C_Timer.NewTicker(0.3, pump) end
end

-- split long messages: "+" = more parts follow, "." = last (or only) part
function NS.Send(msg)
  if not NS.InDog() then return end
  local i, n = 1, #msg
  while n - i + 1 > CHUNK do
    local j = i + CHUNK - 1
    while j > i and msg:byte(j + 1) and msg:byte(j + 1) >= 128 and msg:byte(j + 1) < 192 do j = j - 1 end -- keep UTF-8 letters whole
    push("+" .. msg:sub(i, j)); i = j + 1
  end
  push("." .. msg:sub(i))
end

local function esc(s) return (tostring(s or ""):gsub(SEP, " ")) end
local function entryMsg(id, e)
  return table.concat({"A", id, e.t or 0, e.m or 0, esc(e.n), esc(e.g), esc(e.a), esc(e.d), esc(e.f), esc(e.ed), esc(e.c)}, SEP)
end
function NS.SendEntry(id)
  local e = NS.DB().e[id]; if e and not e.x then NS.Send(entryMsg(id, e)) end
end
local function sendVotes(id, e)
  if not e.v then return end
  local parts = {}
  for who, v in pairs(e.v) do parts[#parts + 1] = esc(who) .. "=" .. v end
  NS.Send(table.concat({"W", id, e.m or 0, table.concat(parts, ",")}, SEP))
end

------------------------------------------------------------------------
-- catching up
------------------------------------------------------------------------
local pendingReply = {}   -- requester -> timer

-- fingerprint of the whole book: live entries and their last-changed times
local function digest()
  local n, sum = 0, 0
  for _, e in pairs(NS.DB().e) do if not e.x then n = n + 1; sum = sum + (e.m or 0) end end
  for _, r in pairs(NS.DB().ed or {}) do sum = sum + (r.m or 0) end
  return n .. ":" .. sum
end
NS.Digest = digest

-- Class backfills can leave modification times unchanged. Compare a separate
-- fingerprint so the entry digest still matches on older clients.
local function classDigest()
  local classes = {}
  for id, e in pairs(NS.DB().e) do
    if not e.x and e.c then classes[#classes + 1] = id .. ":" .. e.c end
  end
  table.sort(classes)
  local data, hash = table.concat(classes, ","), 0
  for i = 1, #data do hash = (hash * 31 + data:byte(i)) % 2147483647 end
  return tostring(hash)
end

-- followup: "1" asks the other side to compare back (only for the first round)
local function myVersion()
  return (C_AddOns and C_AddOns.GetAddOnMetadata or GetAddOnMetadata)(ADDON, "Version") or "0"
end
local function hello(since, followup)
  NS.Send(table.concat({"H", since, digest(), followup and "1" or "0", myVersion(), classDigest()}, SEP))
end
function NS.RequestSync(full)
  -- replies to our own request are trusted for 10 minutes (vote lists, deletes, editors)
  NS.askedAt = GetTime()
  hello(full and 0 or (NS.DB().maxM or 0), true)
  if full then print("|cff" .. NS.GOLD .. "Book of Dogs|r: asked the guild for the whole book.") end
end
function NS.SendEditors()
  local eds = {}
  for name, r in pairs(NS.DB().ed or {}) do eds[#eds + 1] = esc(name) .. "=" .. r.v .. ":" .. r.m end
  if #eds > 0 then NS.Send(table.concat({"L", table.concat(eds, ",")}, SEP)) end
end
local function reply(requester, since, followup)
  pendingReply[requester] = nil
  NS.Send(table.concat({"R", requester}, SEP)) -- tells everyone else to stand down
  for id, e in pairs(NS.DB().e) do
    if (e.m or 0) > since then
      if e.x then NS.Send(table.concat({"D", id, e.x}, SEP))
      else NS.Send(entryMsg(id, e)); sendVotes(id, e) end
    end
  end
  -- the editors list (small) goes with every reply
  NS.SendEditors()
  -- after a full send, say hello back so they can return anything we were missing
  if since == 0 and followup then hello(0, false) end
end

------------------------------------------------------------------------
-- incoming
------------------------------------------------------------------------
local buffers = {}
local handlers = {}
-- a new entry sent live must be authored by its sender, and each sender gets
-- at most 6 new entries a minute (sync replies carry other people's entries)
local recent = {}
local function inReply(sender)
  if NS.inReplyFrom == sender and GetTime() < (NS.inReplyUntil or 0) then return true end
  return NS.askedAt ~= nil and GetTime() - NS.askedAt < 600
end
handlers.A = function(sender, id, t, m, n, g, a, d, f, ed, class)
  local canEdit, canFillClass = inReply(sender), false
  if not canEdit then
    local now, r = GetTime(), recent[sender] or {}
    local keep = {} for _, ts in ipairs(r) do if now - ts < 60 then keep[#keep + 1] = ts end end
    if #keep >= 6 then return end
    keep[#keep + 1] = now; recent[sender] = keep
    a = NS.senderDisplay or sender
    -- Guild chat can create the entry before the queued addon message arrives.
    local e = NS.DB().e[id]
    canFillClass = e and NS.Id(e.a) == sender and e.t == tonumber(t)
                   and (e.n == NS.Clean(n, 60) or e.n == NS.Clean(f, 40))
  end
  NS.ApplyEntry(id, t, m, n, g, a, d, f, canEdit, ed, class, canFillClass)
end
-- editor granted/removed: only the main admin can do this
handlers.G = function(sender, name, v, m)
  if NS.IsMainAdmin(sender) then NS.ApplyEditor(name, v, m) end
end
-- editors list inside a sync reply: trusted only from someone who already has rights
handlers.L = function(sender, list)
  if not (NS.IsMainAdmin(sender) or (inReply(sender) and NS.CanDelete(sender))) then return end
  for name, v, m in (list or ""):gmatch("([^,=]+)=(%d):(%d+)") do NS.ApplyEditor(name, v, m) end
end
-- an admin's edit of an existing entry
handlers.E = function(sender, id, m, n, g, d)
  if not NS.CanDelete(sender) then return end
  local e = NS.DB().e[id]; if not e or e.x then return end
  NS.ApplyEntry(id, e.t, m, n, g, e.a, d, "", true, NS.senderDisplay or sender)
end
handlers.V = function(sender, id, val, m) NS.ApplyVote(id, sender, val, m) end
handlers.W = function(sender, id, m, list)
  if not inReply(sender) then return end -- vote lists only come as part of a sync reply
  local e = NS.DB().e[id]
  if not e or e.x then return end
  m = tonumber(m) or 0
  local seen = {}
  for who, v in (list or ""):gmatch("([^,=]+)=(%-?%d)") do
    local k = NS.VoterKey(who)
    if k then seen[k] = true; NS.ApplyVote(id, k, v, m) end
  end
  -- the sender's list is at least as new as ours: votes missing from it were taken back
  if e.v and m >= (e.m or 0) then
    for who in pairs(e.v) do if not seen[who] then NS.ApplyVote(id, who, 0, m) end end
  end
end
handlers.D = function(sender, id, x)
  -- live deletes must come from an admin; deletes inside a sync reply were already checked by whoever made them
  if NS.CanDelete(sender) or inReply(sender) then NS.ApplyDelete(id, x) end
end
-- tell the player once if a guildmate has a newer version
local function vnum(v)
  local a, b, c = tostring(v or ""):match("^(%d+)%.?(%d*)%.?(%d*)$")
  if not a then return nil end
  return tonumber(a) * 1e6 + (tonumber(b) or 0) * 1e3 + (tonumber(c) or 0)
end
local toldNewer
local function checkVersion(v)
  local theirs, mine = vnum(v), vnum(myVersion())
  if theirs and mine and theirs > mine and not toldNewer then
    toldNewer = true
    print(("|cff%sBook of Dogs|r: a guildmate has version |cffffffff%s|r (you have %s). Ask an officer for the new zip."):format(NS.GOLD, v, myVersion()))
  end
end

handlers.H = function(sender, since, theirDigest, followup, ver, theirClassDigest)
  checkVersion(ver)
  since = tonumber(since) or 0
  if pendingReply[sender] then return end
  local follow = followup == "1"
  if (theirDigest and theirDigest ~= "" and theirDigest ~= digest())
     or (theirClassDigest and theirClassDigest ~= "" and theirClassDigest ~= classDigest()) then
    since = 0 -- our books differ somewhere: send everything, then compare back
  elseif (NS.DB().maxM or 0) <= since then
    return -- nothing they don't have
  end
  -- wait a random moment; whoever answers first, the rest stay quiet
  pendingReply[sender] = C_Timer.NewTimer(1 + math.random() * 4, function() reply(sender, since, follow) end)
end
handlers.R = function(sender, requester)
  local t = pendingReply[requester]
  if t then t:Cancel(); pendingReply[requester] = nil end
  if NS.Id(requester) == NS.MyId() then NS.inReplyFrom, NS.inReplyUntil = sender, GetTime() + 600 end
end

local function handle(sender, msg)
  local f = {strsplit(SEP, msg)}
  local h = handlers[f[1]]
  if h then h(sender, unpack(f, 2)) end
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("CHAT_MSG_ADDON")
frame:SetScript("OnEvent", function(_, _, prefix, msg, channel, sender)
  if prefix ~= PREFIX or channel ~= "GUILD" or not NS.DB() then return end
  -- everyone is handled by one id per character ("First-Realm"); their full
  -- in-game name ("First Last") is remembered for display
  NS.LearnName(sender)
  NS.senderDisplay = NS.Display(sender)
  sender = NS.Id(sender)
  if not sender or sender == NS.MyId() then return end
  NS.stats.recv = NS.stats.recv + 1
  local kind, body = msg:sub(1, 1), msg:sub(2)
  if kind == "+" then
    local b = (buffers[sender] or "") .. body
    buffers[sender] = #b <= 4096 and b or nil -- nothing we send is this long; drop junk
    return
  end
  if kind ~= "." then return end
  if buffers[sender] then body = buffers[sender] .. body; buffers[sender] = nil end
  local ok, err = pcall(handle, sender, body)
  if not ok and BookOfDogsDB and BookOfDogsDB.debug then print("Book of Dogs:", err) end
end)

-- fallback: pick up new entries from the guild chat announcement
-- "[Book of Dogs] Ellise added Bob Smith <Some Guild>: "desc" #6b49d20b64"
local chatFrame = CreateFrame("Frame")
chatFrame:RegisterEvent("CHAT_MSG_GUILD")
chatFrame:SetScript("OnEvent", function(_, _, text, sender)
  if not NS.DB() or type(text) ~= "string" or (issecretvalue and issecretvalue(text)) then return end
  if text:sub(1, 15) ~= "[Book of Dogs] " then return end
  NS.LearnName(sender)
  local disp = NS.Display(sender)
  sender = NS.Id(sender)
  if not sender or sender == NS.MyId() then return end
  local by, who, desc, id = text:match('^%[Book of Dogs%] (.-) added (.-): "(.*)" #(%x+)$')
  if not id or NS.DB().e[id] then return end
  local name, guild = who:match("^(.-) <(.-)>$")
  name = name or who
  local t = tonumber(id:sub(1, -3), 16) or GetServerTime()
  if NS.ApplyEntry(id, t, t, name, guild or "", disp, desc, "", false) then NS.stats.chat = NS.stats.chat + 1 end
end)

function NS.CommStart()
  if C_ChatInfo.RegisterAddonMessagePrefix then C_ChatInfo.RegisterAddonMessagePrefix(PREFIX) end
  -- give the guild roster a moment to load, then ask what we missed
  C_Timer.After(10, function()
    if not NS.InDog() then return end
    NS.RequestSync(false)
    if NS.IsMainAdmin() then NS.SendEditors() end -- the main admin keeps everyone's editor list current
  end)
end
