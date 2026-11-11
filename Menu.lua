-- Book of Dogs: "Add to Book of Dogs" on player right-click menus, and the description popup.
local ADDON, NS = ...

-- find a unit token for a player name (target, mouseover, party, raid)
local function unitFor(name)
  local function is(u) return UnitExists(u) and UnitIsPlayer(u) and NS.Key(UnitName(u)) == name end
  for _, u in ipairs({"target", "mouseover", "focus"}) do if is(u) then return u end end
  if IsInRaid() then for i = 1, 40 do if is("raid" .. i) then return "raid" .. i end end
  else for i = 1, 4 do if is("party" .. i) then return "party" .. i end end end
end

local function fullName(unit, short)
  if not (unit and C_TooltipInfo and C_TooltipInfo.GetUnit) then return nil end
  local ok, data = pcall(C_TooltipInfo.GetUnit, unit)
  local line = ok and data and data.lines and data.lines[1] and data.lines[1].leftText
  if type(line) ~= "string" or (issecretvalue and issecretvalue(line)) then return nil end
  line = NS.Clean(line, 40)
  if line ~= short and line:find(short, 1, true) then return line end
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
    NS.Add(data.name, data.realm, data.guild, text, data.full)
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
  if unit and not name then name, realm = UnitName(unit) end
  if not name or name == "" then return end
  local key = NS.Key(name, realm)
  unit = unit or unitFor(key)
  local data = {name = name, realm = realm, guild = guildOf(unit, key), full = fullName(unit, name)}
  if NS.IsDogMember(data.full or key, data.guild) then
    UIErrorsFrame:AddMessage("Members of <Dog> can't be added to the Book of Dogs.", 1, 0.1, 0.1)
    return
  end
  local shown = (data.full or name) .. (data.guild ~= "" and (" <" .. data.guild .. ">") or "")
  StaticPopup_Show("BOOKOFDOGS_ADD", shown, nil, data)
end

-- right-click menus (modern menu system)
if Menu and Menu.ModifyMenu then
  local tags = {"MENU_UNIT_PLAYER", "MENU_UNIT_TARGET", "MENU_UNIT_FOCUS", "MENU_UNIT_PARTY", "MENU_UNIT_RAID_PLAYER",
                "MENU_UNIT_ENEMY_PLAYER", "MENU_UNIT_FRIEND", "MENU_UNIT_GUILD", "MENU_UNIT_CHAT_ROSTER",
                "MENU_UNIT_COMMUNITIES_GUILD_MEMBER", "MENU_UNIT_COMMUNITIES_MEMBER", "MENU_UNIT_WORLD_STATE_SCORE"}
  local function add(owner, root, ctx)
    if not NS.InDog() or not ctx then return end
    local unit, name, realm = ctx.unit, ctx.name, ctx.server
    if unit and not UnitIsPlayer(unit) then return end
    if not name and unit then name, realm = UnitName(unit) end
    if not name or name == "" then return end
    local g = unit and GetGuildInfo(unit)
    if NS.IsDogMember(NS.Key(name, realm), type(g) == "string" and not (issecretvalue and issecretvalue(g)) and g or nil) then return end
    root:CreateDivider()
    root:CreateButton("|cffffcc33Add to Book of Dogs|r", function() NS.ShowAddPopup(unit, name, realm) end)
  end
  for _, tag in ipairs(tags) do pcall(Menu.ModifyMenu, tag, add) end
end
