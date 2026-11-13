-- Book of Dogs: puts a little dog head next to the chat message of anyone in the Book.
--   /dogs chat     show / hide the chat icons
-- Chat frames build "[Name]: message" themselves, so the icon goes at the start of the
-- message text, right after the name.
local ADDON, NS = ...
local ICON = "|TInterface\\AddOns\\BookOfDogs\\dog_head:14:14|t "

local function secret(v) return issecretvalue and issecretvalue(v) end

local cache = {}   -- author -> true / false, cleared whenever the Book changes
local function isDog(author)
  local c = cache[author]
  if c ~= nil then return c end
  local res = false
  if NS.DB() then
    local key = NS.Key(author)
    local full = key and key:find(" ", 1, true) and key or nil
    res = key ~= nil and #NS.FindEntries(key, full) > 0
  end
  cache[author] = res
  return res
end
NS.listeners[#NS.listeners + 1] = function() wipe(cache) end

local function filter(_, _, msg, author, ...)
  if BookOfDogsDB and BookOfDogsDB.chatHide then return false end
  if type(msg) ~= "string" or type(author) ~= "string" or author == "" then return false end
  if secret(msg) or secret(author) then return false end
  local ok, dog = pcall(isDog, author)
  if ok and dog then return false, ICON .. msg, author, ... end
  return false
end

local EVENTS = {"CHAT_MSG_SAY", "CHAT_MSG_YELL", "CHAT_MSG_WHISPER", "CHAT_MSG_WHISPER_INFORM",
  "CHAT_MSG_GUILD", "CHAT_MSG_OFFICER", "CHAT_MSG_PARTY", "CHAT_MSG_PARTY_LEADER",
  "CHAT_MSG_RAID", "CHAT_MSG_RAID_LEADER", "CHAT_MSG_RAID_WARNING", "CHAT_MSG_INSTANCE_CHAT",
  "CHAT_MSG_INSTANCE_CHAT_LEADER", "CHAT_MSG_CHANNEL"}
local addFilter = (ChatFrameUtil and ChatFrameUtil.AddMessageEventFilter) or ChatFrame_AddMessageEventFilter
if addFilter then
  for _, ev in ipairs(EVENTS) do addFilter(ev, filter) end
end

function NS.ToggleChatIcons()
  BookOfDogsDB.chatHide = not BookOfDogsDB.chatHide
  print(("|cff%sBook of Dogs|r: chat icons %s."):format(NS.GOLD, BookOfDogsDB.chatHide and "hidden" or "shown"))
end
