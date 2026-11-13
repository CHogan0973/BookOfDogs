-- Book of Dogs: one vote per BattleTag.
-- Every client reads its own BattleTag, turns it into a salted SHA-256 hash (the tag
-- itself is never sent or stored) and sends the hash with its votes. A vote is then
-- kept under the account ("#" + hash), so all of a person's characters share one vote.
-- Characters learn which account they belong to from their owner's own messages and
-- from guildmates' sync replies (db.acct). There is no server to check any of this,
-- so it stops casual alt-voting, not someone running a modified addon.
local ADDON, NS = ...

NS.ACCT_SALT = "BookOfDogs/Dog/votes/v1:"
local HASH_LEN = 16 -- hex characters kept from the SHA-256 (64 bits)

------------------------------------------------------------------------
-- SHA-256
------------------------------------------------------------------------
local K = {
  0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
  0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
  0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
  0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
  0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
  0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
  0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
  0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
}

-- 32-bit arithmetic with plain numbers. The game's bit library has no rotate and its
-- results can be signed, so none of it is used here.
local MOD = 4294967296
local function band(a, b)
  local r, p = 0, 1
  for _ = 1, 32 do
    local x, y = a % 2, b % 2
    if x == 1 and y == 1 then r = r + p end
    a, b, p = (a - x) / 2, (b - y) / 2, p * 2
  end
  return r
end
local function bxor(a, b)
  local r, p = 0, 1
  for _ = 1, 32 do
    local x, y = a % 2, b % 2
    if x ~= y then r = r + p end
    a, b, p = (a - x) / 2, (b - y) / 2, p * 2
  end
  return r
end
local function bnot(a) return MOD - 1 - a end
local function shr(a, n) return math.floor(a / 2 ^ n) end
local function ror(a, n) return shr(a, n) + (a * 2 ^ (32 - n)) % MOD end
local function hex32(x) return ("%04x%04x"):format(math.floor(x / 65536), x % 65536) end

local function sha256(msg)
  local len = #msg
  local bits = len * 8
  msg = msg .. "\128" .. string.rep("\0", (55 - len) % 64)
    .. string.char(0, 0, 0, 0,
      math.floor(bits / 16777216) % 256, math.floor(bits / 65536) % 256, math.floor(bits / 256) % 256, bits % 256)
  local h0, h1, h2, h3, h4, h5, h6, h7 =
    0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a, 0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19
  local w = {}
  for chunk = 1, #msg, 64 do
    for i = 0, 15 do
      local a, b, c, d = msg:byte(chunk + i * 4, chunk + i * 4 + 3)
      w[i] = a * 16777216 + b * 65536 + c * 256 + d
    end
    for i = 16, 63 do
      local w15, w2 = w[i - 15], w[i - 2]
      local s0 = bxor(bxor(ror(w15, 7), ror(w15, 18)), shr(w15, 3))
      local s1 = bxor(bxor(ror(w2, 17), ror(w2, 19)), shr(w2, 10))
      w[i] = (w[i - 16] + s0 + w[i - 7] + s1) % MOD
    end
    local a, b, c, d, e, f, g, h = h0, h1, h2, h3, h4, h5, h6, h7
    for i = 0, 63 do
      local S1 = bxor(bxor(ror(e, 6), ror(e, 11)), ror(e, 25))
      local ch = bxor(band(e, f), band(bnot(e), g))
      local t1 = (h + S1 + ch + K[i + 1] + w[i]) % MOD
      local S0 = bxor(bxor(ror(a, 2), ror(a, 13)), ror(a, 22))
      local maj = bxor(bxor(band(a, b), band(a, c)), band(b, c))
      local t2 = (S0 + maj) % MOD
      h, g, f, e, d, c, b, a = g, f, e, (d + t1) % MOD, c, b, a, (t1 + t2) % MOD
    end
    h0, h1, h2, h3 = (h0 + a) % MOD, (h1 + b) % MOD, (h2 + c) % MOD, (h3 + d) % MOD
    h4, h5, h6, h7 = (h4 + e) % MOD, (h5 + f) % MOD, (h6 + g) % MOD, (h7 + h) % MOD
  end
  return hex32(h0) .. hex32(h1) .. hex32(h2) .. hex32(h3) .. hex32(h4) .. hex32(h5) .. hex32(h6) .. hex32(h7)
end
NS.SHA256 = sha256

------------------------------------------------------------------------
-- my account
------------------------------------------------------------------------
-- my BattleTag, lowercase, or nil when the game won't tell us (not connected to Battle.net)
local function readTag()
  if not BNGetInfo then return nil end
  local ok, _, tag = pcall(BNGetInfo)
  if not ok or type(tag) ~= "string" or (issecretvalue and issecretvalue(tag)) then return nil end
  tag = tag:gsub("%s", ""):lower()
  if #tag < 3 or not tag:find("#", 1, true) then return nil end
  return tag
end

local myAcct
function NS.MyAcct()
  if myAcct then return myAcct end
  local tag = readTag()
  if not tag then return nil end -- try again next time; Battle.net can connect after login
  local ok, h = pcall(sha256, NS.ACCT_SALT .. tag) -- a hashing problem must never break voting
  if not ok or type(h) ~= "string" then return nil end
  myAcct = h:sub(1, HASH_LEN)
  return myAcct
end

-- account keys: "#" followed by the hash. Anything else is a character.
function NS.ValidAcct(h) return type(h) == "string" and #h == HASH_LEN and h:match("^%x+$") ~= nil end
function NS.AcctKey(h) return "#" .. h end
function NS.IsAcctKey(k) return type(k) == "string" and #k == HASH_LEN + 1 and k:sub(1, 1) == "#" and NS.ValidAcct(k:sub(2)) end

------------------------------------------------------------------------
-- which account a character belongs to (db.acct[name key] = hash)
------------------------------------------------------------------------
-- a character's key here: lowercase name with spaces removed, realm ignored
local function nameKey(raw)
  local id = NS.Id(raw); if not id then return nil end
  return ((id:match("^[^%-]+") or ""):gsub("%s", ""):lower())
end

function NS.AcctOf(raw)
  local db = NS.DB()
  local map = db and db.acct
  if not map or type(raw) ~= "string" or NS.IsAcctKey(raw) then return nil end
  local id = NS.Id(raw); if not id then return nil end
  local nm = id:match("^[^%-]+") or ""
  local hit = map[(nm:gsub("%s", ""):lower())]
  if hit then return hit end
  -- a bare first name stands for the one full name it could be, if we know exactly one
  if not nm:find(" ", 1, true) then
    local full = NS.FullSigOf(nm)
    if full then return map[full] end
  end
  return nil
end

local function setKey(map, key, h, authoritative)
  if not key or key == "" or #key > 60 or key:find("[,=]") then return false end
  if map[key] == h or (map[key] and not authoritative) then return false end
  map[key] = h
  return true
end

-- A character's own message says which account it is (authoritative). Anything learned
-- second-hand from a sync reply only fills gaps. Returns true if something changed;
-- when it did, the book is re-counted so that account's votes collapse into one.
function NS.LearnAcct(raw, h, authoritative)
  local db = NS.DB()
  if not db or not NS.ValidAcct(h) or type(raw) ~= "string" then return false end
  db.acct = db.acct or {}
  local changed = setKey(db.acct, nameKey(raw), h, authoritative)
  -- a bare first name that stands for one known full name is that person too
  local id = NS.Id(raw)
  local nm = id and id:match("^[^%-]+")
  if nm and not nm:find(" ", 1, true) then
    local full = NS.FullSigOf(nm)
    if full and setKey(db.acct, full, h, authoritative) then changed = true end
  end
  if changed then NS.Normalize() end
  return changed
end

-- sync: the whole character -> account table, and a short fingerprint to compare
function NS.AcctList()
  local out = {}
  for k, h in pairs(NS.DB().acct or {}) do out[#out + 1] = k .. "=" .. h end
  table.sort(out)
  return table.concat(out, ",")
end
function NS.MergeAcctList(list)
  local db = NS.DB()
  if not db then return false end
  db.acct = db.acct or {}
  local changed = false
  for k, h in tostring(list or ""):gmatch("([^,=]+)=(%x+)") do
    if NS.ValidAcct(h) and setKey(db.acct, k, h, false) then changed = true end
  end
  if changed then NS.Normalize() end
  return changed
end
function NS.AcctDigest()
  local data, hash = NS.AcctList(), 0
  for i = 1, #data do hash = (hash * 31 + data:byte(i)) % 2147483647 end
  return tostring(hash)
end

-- tell the guild which account I am (so my characters' older votes collapse into one)
function NS.AnnounceAcct()
  local h = NS.MyAcct()
  if not h then return false end
  NS.LearnAcct(NS.MyFull(), h, true)
  NS.Send("I\t" .. h)
  return true
end

-- how to show a voter: a character's name, or for an account the characters we know on it
function NS.VoterName(who)
  if not NS.IsAcctKey(who) then return NS.Display(who) end
  local h, db, found = who:sub(2), NS.DB(), {}
  for _, disp in pairs(db and db.names or {}) do
    local k = (disp:gsub("%s", ""):lower())
    if db.acct[k] == h and not found[disp] then found[disp] = true end
  end
  local list = {}
  for disp in pairs(found) do list[#list + 1] = disp end
  table.sort(list)
  if #list == 0 then return "Unknown player" end
  -- several characters on one account: show one, and how many more
  return #list == 1 and list[1] or (list[1] .. " +" .. (#list - 1))
end
