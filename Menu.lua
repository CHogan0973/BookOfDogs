-- Book of Dogs: "Add to Book of Dogs" on player right-click menus, and the description popup.
local ADDON, NS = ...

local function secret(value)
  return issecretvalue and issecretvalue(value)
end

local function fullName(unit, short)
  if not (unit and C_TooltipInfo and C_TooltipInfo.GetUnit) then return nil end
  local ok, data = pcall(C_TooltipInfo.GetUnit, unit)
  local line = ok and data and data.lines and data.lines[1] and data.lines[1].leftText
  if type(line) ~= "string" or secret(line) then return nil end
  line = NS.Clean(line, 40)
  if line ~= short and line:find(short, 1, true) then return line end
end

local function matchesPlayer(unit, key)
  if not UnitExists(unit) or not UnitIsPlayer(unit) then return false end
  local name, realm = UnitName(unit)
  if secret(name) or secret(realm) or not name then return false end
  if NS.Key(name, realm) == key then return true end
  local full = fullName(unit, name)
  return full ~= nil and NS.Key(full, realm) == key
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
    local eb = self.EditBox or self.editBox or (self.GetEditBox and self:GetEditBox())
    local text = eb and eb:GetText() or ""
    if NS.Clean(text) == "" then return true end -- keep the popup open until something is written
    if NS.Blocked(text) then
      print("|cff" .. NS.GOLD .. "Book of Dogs|r: |cffff5555that description has language that isn't allowed in the Book. Please reword it.|r")
      return true -- keep the popup open so they can fix it
    end
    NS.Add(data.name, data.realm, data.guild, text, data.full, nil, data.class)
    print(("|cff%sBook of Dogs|r: added %s."):format(NS.GOLD, data.full or data.name))
  end,
  EditBoxOnEnterPressed = function(self)
    local p = self:GetParent()
    if StaticPopupDialogs.BOOKOFDOGS_ADD.OnAccept(p, p.data) ~= true then p:Hide() end
  end,
  EditBoxOnEscapePressed = function(self) self:GetParent():Hide() end,
}

function NS.ShowAddPopup(unit, name, realm)
  if not NS.InDog() then print("|cff" .. NS.GOLD .. "Book of Dogs|r: only members of <Dog> can add entries."); return end
  if unit and name == nil then name, realm = UnitName(unit) end
  if secret(name) or secret(realm) or not name or name == "" then return end
  local key = NS.Key(name, realm)
  if unit then
    if not matchesPlayer(unit, key) then unit = nil end
  else
    unit = unitFor(key)
  end
  local data = {name = name, realm = realm, guild = guildOf(unit, key), full = fullName(unit, name),
                class = unit and select(2, UnitClass(unit))}
  if not NS.ValidClass(data.class) then data.class = nil end
  -- a name typed or clicked with a surname already in it is the full name
  if not data.full and name:find(" ", 1, true) then data.full = name end

  local function finish()
    -- already in the Book: say so instead of adding again
    local hits = NS.FindEntries(key, data.full)
    if #hits > 0 then
      local e = NS.DB().e[hits[1]]
      print(("|cff%sBook of Dogs|r: |cffff4040DOG|r %s — %s"):format(NS.GOLD, e.f or e.n, e.d or ""))
      NS.ShowEntry(e.f or e.n)
      return
    end
    if NS.IsDogMember(data.full or key, data.guild) then
      UIErrorsFrame:AddMessage("Members of <Dog> can't be added to the Book of Dogs.", 1, 0.1, 0.1)
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
  if not unit or not NS.DB() or not UnitIsPlayer(unit) then return end
  local name, realm = UnitName(unit)
  if secret(name) or secret(realm) or not name then return end
  local hits = NS.FindEntries(NS.Key(name, realm), fullName(unit, name))
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
    if not NS.InDog() or not ctx then return end
    local unit, name, realm = ctx.unit, ctx.name, ctx.server
    if unit and not UnitIsPlayer(unit) then return end
    if unit and name == nil then name, realm = UnitName(unit) end
    if secret(name) or secret(realm) or not name or name == "" then return end
    local guid = unit and UnitGUID(unit)
    local g = unit and GetGuildInfo(unit)
    if NS.IsDogMember(NS.Key(name, realm), type(g) == "string" and not (issecretvalue and issecretvalue(g)) and g or nil) then return end
    root:CreateDivider()
    -- already in the Book: show "DOG" and their note instead of the add option
    local full = unit and fullName(unit, name)
    local hits = NS.FindEntries(NS.Key(name, realm), full)
    if #hits > 0 then
      for i = 1, math.min(#hits, 3) do
        local e = NS.DB().e[hits[i]]
        local note = e.d or ""
        if #note > 60 then note = note:sub(1, 57):gsub("[\192-\255][\128-\191]*$", "") .. "..." end
        local s = e.s or 0
        root:CreateButton(("|cffff4040DOG|r %s  |cff888888(%s%d)|r"):format(note, s > 0 and "+" or "", s), function()
          NS.ShowEntry(e.f or e.n)
        end)
      end
      return
    end
    root:CreateButton("|cffffcc33Add to Book of Dogs|r", function()
      local current = unit and UnitGUID(unit)
      local sameUnit = not secret(guid) and not secret(current) and guid and current == guid
      NS.ShowAddPopup(sameUnit and unit or nil, name, realm)
    end)
  end
  for _, tag in ipairs(tags) do pcall(Menu.ModifyMenu, tag, add) end
end
