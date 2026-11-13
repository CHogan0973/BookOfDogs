-- Book of Dogs: "Add to Book of Dogs" on player right-click menus, and the description popup.
local ADDON, NS = ...

local function secret(value)
  return issecretvalue and issecretvalue(value)
end

local function fullName(unit, short)
  if not unit or not short then return nil end
  local function ok(v)
    if type(v) ~= "string" or secret(v) then return nil end
    v = NS.Clean((v:match("^[^%-]+") or v), 40)
    -- the full name starts with the first name and adds a surname
    if v ~= short and v:find(short, 1, true) == 1 and v:find(" ", 1, true) then return v end
  end
  -- what the unit frames show ("Laquai Eudora"); works for both factions
  if GetUnitName then
    local f = ok((pcall(GetUnitName, unit, false)) and GetUnitName(unit, false))
    if f then return f end
  end
  -- the target frame's own name text
  if unit == "target" and TargetFrame then
    local fs = TargetFrame.name or (TargetFrame.TargetFrameContent and TargetFrame.TargetFrameContent.TargetFrameContentMain
               and TargetFrame.TargetFrameContent.TargetFrameContentMain.Name)
    local f = fs and fs.GetText and ok(fs:GetText())
    if f then return f end
  end
  -- the unit's tooltip
  if C_TooltipInfo and C_TooltipInfo.GetUnit then
    local okc, data = pcall(C_TooltipInfo.GetUnit, unit)
    local lines = okc and data and data.lines
    if lines then
      for i = 1, math.min(#lines, 2) do
        local t = lines[i] and lines[i].leftText
        if type(t) == "string" and not secret(t) then
          local f = t:find(short, 1, true) and ok(t:match("(" .. short:gsub("%p", "%%%0") .. "%s+%S+)"))
          if f then return f end
        end
      end
    end
  end
end

local function matchesPlayer(unit, key)
  if not UnitExists(unit) or not UnitIsPlayer(unit) then return false end
  local first, second = UnitName(unit)
  if secret(first) or secret(second) or not first then return false end
  local full = NS.FullFrom(first, second)
  return NS.Key(first) == key or NS.Key(full) == key or (fullName(unit, first) ~= nil and NS.Key(fullName(unit, first)) == key)
end

-- A first name alone cannot identify a Forever character without a unit token.
local function unitFor(key)
  if not key:find(" ", 1, true) then return end
  for _, unit in ipairs({"target", "mouseover", "focus"}) do
    if matchesPlayer(unit, key) then return unit end
  end
  local inRaid = IsInRaid()
  local prefix = inRaid and "raid" or "party"
  for i = 1, inRaid and 40 or 4 do
    local unit = prefix .. i
    if matchesPlayer(unit, key) then return unit end
  end
end

local function guildOf(unit, key)
  if unit then
    local g = GetGuildInfo(unit)
    if g and not (issecretvalue and issecretvalue(g)) then return g end
  end
  -- a guildmate? the roster knows them
  if key and IsInGuild() then
    for i = 1, (GetNumGuildMembers() or 0) do
      local full = GetGuildRosterInfo(i)
      if full and Ambiguate(full, "guild") == key then return (GetGuildInfo("player")) end
    end
  end
  return ""
end

StaticPopupDialogs.BOOKOFDOGS_ADD = {
  text = "|cffffcc33Book of Dogs|r\n\nAdd |cffffffff%s|r to the book.\nWhat should the guild know? (max 200)",
  button1 = "Add", button2 = CANCEL,
  hasEditBox = true, maxLetters = NS.MAXDESC, editBoxWidth = 340,
  timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
  OnShow = function(self)
    local eb = self.EditBox or self.editBox or (self.GetEditBox and self:GetEditBox())
    if eb then eb:SetText(""); eb:SetFocus() end
  end,
  OnAccept = function(self, data)
    if not data or data.revision ~= NS.FeedRevision or not NS.InGuildFeed() then return end
    local eb = self.EditBox or self.editBox or (self.GetEditBox and self:GetEditBox())
    local text = eb and eb:GetText() or ""
    if NS.Clean(text) == "" then return true end -- keep the popup open until something is written
    if NS.Blocked(text) then
      print("|cff" .. NS.GOLD .. "Book of Dogs|r: |cffff5555that description has language that isn't allowed in the Book. Please reword it.|r")
      return true -- keep the popup open so they can fix it
    end
    if NS.Add(data.name, data.realm, data.guild, text, data.full, nil, data.class) then
      print(("|cff%sBook of Dogs|r: added %s."):format(NS.GOLD, data.full or data.name))
    end
  end,
  EditBoxOnEnterPressed = function(self)
    local p = self:GetParent()
    if StaticPopupDialogs.BOOKOFDOGS_ADD.OnAccept(p, p.data) ~= true then p:Hide() end
  end,
  EditBoxOnEscapePressed = function(self) self:GetParent():Hide() end,
}

function NS.ShowAddPopup(unit, name, realm)
  if not NS.InGuildFeed() then print("|cff" .. NS.GOLD .. "Book of Dogs|r: join a guild to add entries."); return end
  if unit and name == nil then name, realm = UnitName(unit) end
  if secret(name) or secret(realm) or not name or name == "" then return end
  -- the second value is a surname on Forever, not a realm
  local fromPair = NS.FullFrom(name, realm)
  if fromPair ~= name then realm = nil end
  local key = NS.Key(name)
  if unit then
    if not matchesPlayer(unit, key) then unit = nil end
  else
    unit = unitFor(key)
  end
  local data = {name = name, realm = realm, guild = guildOf(unit, key), full = fullName(unit, name),
                class = unit and select(2, UnitClass(unit)), revision = NS.FeedRevision}
  if secret(data.class) or not NS.ValidClass(data.class) then data.class = nil end
  if secret(data.guild) then data.guild = "" end
  -- a name typed or clicked with a surname already in it is the full name
  if not data.full and fromPair:find(" ", 1, true) then data.full = fromPair end

  local function finish()
    if data.revision ~= NS.FeedRevision or not NS.InGuildFeed() then return end
    -- already in the Book: say so instead of adding again
    local hits = NS.FindEntries(key, data.full)
    if #hits > 0 then
      local e = NS.DB().e[hits[1]]
      -- an older entry missing the surname or class: admins/editors fill it in now
      if NS.CanDelete() and ((data.full and not (e.f or e.n):find(" ", 1, true)) or (data.class and not e.c)) then
        NS.Edit(hits[1], data.full or e.f or e.n, (e.g and e.g ~= "") and e.g or (data.guild or ""), e.d or "", e.c or data.class)
        print(("|cff%sBook of Dogs|r: updated %s with their full name and class."):format(NS.GOLD, data.full or e.n))
      end
      print(("|cff%sBook of Dogs|r: |cffff4040DOG|r %s — %s"):format(NS.GOLD, e.f or e.n, e.d or ""))
      NS.ShowEntry(e.f or e.n)
      return
    end
    if NS.IsGuildmate(data.full or key, data.guild) then
      UIErrorsFrame:AddMessage("Guildmates can't be added to the Book of Dogs.", 1, 0.1, 0.1)
      return
    end
    local cls = NS.ClassName(data.class)
    local shown = NS.ColorName(data.full or name, data.class) .. (cls and (" " .. NS.ColorName(cls, data.class)) or "")
                  .. ((data.guild or "") ~= "" and (" <" .. data.guild .. ">") or "")
    StaticPopup_Show("BOOKOFDOGS_ADD", shown, nil, data)
  end

  -- missing the surname or class (a name clicked in chat, or a unit the game won't
  -- describe): ask /who for the full name, class and guild first
  if (not data.full or not data.class) and NS.WhoLookup then
    NS.WhoLookup(data.full or name, function(info)
      if info then
        local wn = info.name and info.name:match("^[^%-]+")
        if wn and wn:find(" ", 1, true) and not data.full then data.full = wn end
        data.class = data.class or info.class
        if (data.guild or "") == "" and info.guild then data.guild = info.guild end
      end
      finish()
    end)
    return
  end
  finish()
end

-- right-click menus (modern menu system)
-- player tooltips: "DOG - note" for anyone in the Book
local function addDogLines(tooltip, unit)
  if not unit or not NS.InGuildFeed() or not UnitIsPlayer(unit) then return end
  local name, second = UnitName(unit)
  if secret(name) or secret(second) or not name then return end
  local full = fullName(unit, name) or NS.FullFrom(name, second)
  local hits = NS.FindEntries(NS.Key(name), full)
  for i = 1, math.min(#hits, 2) do
    local e = NS.DB().e[hits[i]]
    local s = e.s or 0
    tooltip:AddLine(("|cffff4040DOG|r - %s  |cff888888(%s%d)|r"):format(e.d or "", s > 0 and "+" or "", s), 1, 1, 1, true)
  end
  if #hits > 0 then tooltip:Show() end
end
if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType then
  TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Unit, function(tooltip)
    if tooltip ~= GameTooltip or not tooltip.GetUnit then return end
    local _, unit = tooltip:GetUnit()
    if unit and not secret(unit) then pcall(addDogLines, tooltip, unit) end
  end)
elseif GameTooltip and GameTooltip:HasScript("OnTooltipSetUnit") then
  GameTooltip:HookScript("OnTooltipSetUnit", function(tooltip)
    local _, unit = tooltip:GetUnit()
    if unit then pcall(addDogLines, tooltip, unit) end
  end)
end

if Menu and Menu.ModifyMenu then
  local tags = {"MENU_UNIT_PLAYER", "MENU_UNIT_TARGET", "MENU_UNIT_FOCUS", "MENU_UNIT_PARTY", "MENU_UNIT_RAID_PLAYER",
                "MENU_UNIT_ENEMY_PLAYER", "MENU_UNIT_FRIEND", "MENU_UNIT_GUILD", "MENU_UNIT_CHAT_ROSTER",
                "MENU_UNIT_COMMUNITIES_GUILD_MEMBER", "MENU_UNIT_COMMUNITIES_MEMBER", "MENU_UNIT_WORLD_STATE_SCORE"}
  local function add(owner, root, ctx)
    if not NS.InGuildFeed() or not ctx then return end
    local revision = NS.FeedRevision
    local unit, name, realm = ctx.unit, ctx.name, ctx.server
    if unit and not UnitIsPlayer(unit) then return end
    if unit and name == nil then name, realm = UnitName(unit) end
    if secret(name) or secret(realm) or not name or name == "" then return end
    local pairFull = NS.FullFrom(name, realm)
    if pairFull ~= name then realm = nil end -- a surname, not a realm
    local guid = unit and UnitGUID(unit)
    local g = unit and GetGuildInfo(unit)
    local full = (unit and fullName(unit, name)) or (pairFull:find(" ", 1, true) and pairFull) or nil
    if NS.IsGuildmate(full or NS.Key(name, realm), type(g) == "string" and not (issecretvalue and issecretvalue(g)) and g or nil) then return end
    root:CreateDivider()
    -- already in the Book: show "DOG" and their note instead of the add option
    local hits = NS.FindEntries(NS.Key(name, realm), full)
    if #hits > 0 then
      for i = 1, math.min(#hits, 3) do
        local e = NS.DB().e[hits[i]]
        local note = e.d or ""
        if #note > 60 then note = note:sub(1, 57):gsub("[\192-\255][\128-\191]*$", "") .. "..." end
        local s = e.s or 0
        root:CreateButton(("|cffff4040DOG|r %s  |cff888888(%s%d)|r"):format(note, s > 0 and "+" or "", s), function()
          if revision == NS.FeedRevision then NS.ShowEntry(e.f or e.n) end
        end)
      end
      return
    end
    root:CreateButton("|cffffcc33Add to Book of Dogs|r", function()
      if revision ~= NS.FeedRevision or not NS.InGuildFeed() then return end
      local current = unit and UnitGUID(unit)
      -- still the same player? (GUIDs can be hidden for the other faction; fall back to the name)
      local sameUnit
      if guid and current and not secret(guid) and not secret(current) then sameUnit = current == guid
      else sameUnit = unit ~= nil and UnitExists(unit) and not secret(UnitName(unit)) and UnitName(unit) == name end
      if sameUnit then NS.ShowAddPopup(unit, name, realm)
      else NS.ShowAddPopup(nil, full or name, realm) end
    end)
  end
  for _, tag in ipairs(tags) do pcall(Menu.ModifyMenu, tag, add) end
end

-- /dogs debug: what the game tells the addon about your target (for troubleshooting)
function NS.DebugTarget()
  local u = "target"
  local function show(label, ok, ...)
    local parts = {}
    for i = 1, select("#", ...) do
      local v = select(i, ...)
      parts[#parts + 1] = secret(v) and "<secret>" or tostring(v)
    end
    print(("|cff%sBoD debug|r %s: %s"):format(NS.GOLD, label, ok and table.concat(parts, ", ") or "<error>"))
  end
  if not UnitExists(u) then print("Book of Dogs: target a player first."); return end
  show("UnitName", pcall(UnitName, u))
  show("GetUnitName(false)", pcall(GetUnitName, u, false))
  show("GetUnitName(true)", pcall(GetUnitName, u, true))
  if UnitFullName then show("UnitFullName", pcall(UnitFullName, u)) end
  if UnitPVPName then show("UnitPVPName", pcall(UnitPVPName, u)) end
  show("UnitClass", pcall(UnitClass, u))
  show("GetGuildInfo", pcall(GetGuildInfo, u))
  show("UnitGUID", pcall(UnitGUID, u))
  show("UnitIsPlayer / Faction", pcall(function() return UnitIsPlayer(u), UnitFactionGroup(u) end))
  local fs = TargetFrame and (TargetFrame.name or (TargetFrame.TargetFrameContent and TargetFrame.TargetFrameContent.TargetFrameContentMain
             and TargetFrame.TargetFrameContent.TargetFrameContentMain.Name))
  show("TargetFrame name", pcall(function() return fs and fs:GetText() end))
  if C_TooltipInfo and C_TooltipInfo.GetUnit then
    local ok, data = pcall(C_TooltipInfo.GetUnit, u)
    for i = 1, 3 do
      local l = ok and data and data.lines and data.lines[i]
      if l then show("Tooltip line " .. i, true, l.leftText) end
    end
  end
  local name = UnitName(u)
  show("fullName() result", true, fullName(u, (not secret(name)) and name or nil))
end
