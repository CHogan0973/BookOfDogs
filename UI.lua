-- Book of Dogs: the book window, built from the game's own window templates so it
-- wears the Forever UI skin. Built the first time it's opened; a handful of row
-- frames are reused while scrolling, and nothing runs while it's closed.
local ADDON, NS = ...
local ROWH, W, H = 66, 600, 620
local MAXROWS = 20                 -- row frames built; how many show depends on the window height
local MINW, MINH, MAXW = 580, 280, 1100
local INSET_PAD = 8                -- space above the first row and below the last (inside the inset)
local SCROLLBAR_W = 28             -- room the scroll bar takes on the right when it is showing
local CHROME_H = 66 + 32           -- inset's top + bottom offsets inside the window
local MAXH = MAXROWS * ROWH + INSET_PAD + CHROME_H
local frame, rows, scroll, search, countText, list, inset
local visibleRows = 1

local function ago(t)
  local d = GetServerTime() - (t or 0)
  if d < 3600 then return math.max(1, math.floor(d / 60)) .. "m ago" end
  if d < 86400 then return math.floor(d / 3600) .. "h ago" end
  if d < 86400 * 60 then return math.floor(d / 86400) .. "d ago" end
  return date("%b %d, %Y", t)
end

local function setVoted(btn, on)
  local t = btn:GetNormalTexture()
  if t then t:SetDesaturated(not on); t:SetVertexColor(on and 1 or 0.7, on and 1 or 0.7, on and 1 or 0.7) end
end

local function refresh()
  if not frame or not frame:IsShown() then return end
  list = NS.Sorted(search:GetText())
  countText:SetText(#list .. (#list == 1 and " entry" or " entries"))
  visibleRows = math.min(MAXROWS, math.max(1, math.floor((frame:GetHeight() - CHROME_H - INSET_PAD) / ROWH)))
  local showBar = FauxScrollFrame_Update(scroll, #list, visibleRows, ROWH)
  local off = FauxScrollFrame_GetOffset(scroll)
  -- rows fill the full width unless the scroll bar is showing
  local rightPad = showBar and SCROLLBAR_W or 4
  local me, canDel = NS.MyId(), NS.CanDelete()
  if frame.newBtn then frame.newBtn:SetShown(canDel) end
  if frame.edBtn then frame.edBtn:SetShown(NS.IsMainAdmin()) end
  for i = 1, MAXROWS do
    local r, id = rows[i], list[off + i]
    local e = i <= visibleRows and id and NS.DB().e[id]
    r:SetPoint("RIGHT", inset, "RIGHT", -rightPad, 0)
    if e then
      local s = e.s or 0
      r.id = id
      r.rank:SetText("#" .. (off + i))
      r.score:SetText(s > 0 and ("+" .. s) or tostring(s))
      if s > 0 then r.score:SetTextColor(0.3, 1, 0.3) elseif s < 0 then r.score:SetTextColor(1, 0.4, 0.4) else r.score:SetTextColor(0.8, 0.8, 0.8) end
      local mine = e.v and e.v[me]
      setVoted(r.up, mine == 1); setVoted(r.down, mine == -1)
      -- name in class color, then the class, then the guild
      local cls = NS.ClassName(e.c)
      r.name:SetText(NS.ColorName(e.f or e.n, e.c)
        .. (cls and ("  " .. NS.ColorName(cls, e.c)) or "")
        .. (e.g and ("  |cff40c040<" .. e.g .. ">|r") or ""))
      r.desc:SetText(e.d or "")
      r.by:SetText(("added by %s  ·  %s%s"):format(NS.Display(e.a or "?"), ago(e.t), e.ed and ("  ·  edited by " .. NS.Display(e.ed)) or ""))
      r.del:SetShown(canDel); r.edit:SetShown(canDel)
      r:Show()
    else
      r.id = nil; r:Hide()
    end
  end
end
NS.listeners[#NS.listeners + 1] = function() if frame and frame:IsShown() then refresh() end end

local function arrow(parent, up)
  local b = CreateFrame("Button", nil, parent)
  b:SetSize(22, 22)
  local base = up and "Interface\\Buttons\\UI-ScrollBar-ScrollUpButton-" or "Interface\\Buttons\\UI-ScrollBar-ScrollDownButton-"
  b:SetNormalTexture(base .. "Up"); b:SetPushedTexture(base .. "Down"); b:SetHighlightTexture(base .. "Highlight", "ADD")
  b:SetScript("OnClick", function(self) local id = self:GetParent().id; if id then NS.Vote(id, up and 1 or -1) end end)
  b:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_LEFT"); GameTooltip:SetText(up and "Vote up" or "Vote down")
    GameTooltip:AddLine("One vote per person. If you already voted, clicking either arrow takes your vote back.", 0.8, 0.8, 0.8); GameTooltip:Show()
  end)
  b:SetScript("OnLeave", GameTooltip_Hide)
  return b
end

-- the window shell: Blizzard's ButtonFrameTemplate (portrait, title bar, close
-- button, inset). If a client lacks it, fall back to a plain bordered frame.
local function shell()
  local ok, f = pcall(CreateFrame, "Frame", "BookOfDogsFrame", UIParent, "ButtonFrameTemplate")
  if ok and f and f.Inset then
    if f.SetTitle then f:SetTitle("Book of Dogs") elseif f.TitleText then f.TitleText:SetText("Book of Dogs") end
    local icon = "Interface\\AddOns\\BookOfDogs\\dog"
    if f.SetPortraitToAsset then f:SetPortraitToAsset(icon)
    elseif f.portrait and SetPortraitToTexture then SetPortraitToTexture(f.portrait, icon)
    elseif f.PortraitContainer and f.PortraitContainer.portrait then f.PortraitContainer.portrait:SetTexture(icon) end
    return f, f.Inset
  end
  if not ok or type(f) ~= "table" then f = CreateFrame("Frame", "BookOfDogsFrame", UIParent, "BackdropTemplate") end
  if not f.SetBackdrop then Mixin(f, BackdropTemplateMixin) end
  f:SetBackdrop({bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark", edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
                 tile = true, tileSize = 32, edgeSize = 32, insets = {left = 8, right = 8, top = 8, bottom = 8}})
  local t = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge"); t:SetPoint("TOP", 0, -14); t:SetText("Book of Dogs")
  local c = CreateFrame("Button", nil, f, "UIPanelCloseButton"); c:SetPoint("TOPRIGHT", -4, -4)
  local inset = CreateFrame("Frame", nil, f)
  inset:SetPoint("TOPLEFT", 12, -62); inset:SetPoint("BOTTOMRIGHT", -12, 36)
  return f, inset
end

local function build()
  frame, inset = shell()
  local saved = NS.DB().ui or {}
  frame:SetSize(math.max(MINW, math.min(MAXW, saved.w or W)), math.max(MINH, math.min(MAXH, saved.h or H)))
  frame:ClearAllPoints(); frame:SetPoint("CENTER")
  -- resizable: the grip in the bottom-right corner; the rows re-fit as the window changes
  frame:SetResizable(true)
  if frame.SetResizeBounds then frame:SetResizeBounds(MINW, MINH, MAXW, MAXH)
  elseif frame.SetMinResize then frame:SetMinResize(MINW, MINH); frame:SetMaxResize(MAXW, MAXH) end
  frame:SetFrameStrata("HIGH"); frame:SetToplevel(true); frame:SetClampedToScreen(true)
  frame:SetMovable(true); frame:EnableMouse(true); frame:RegisterForDrag("LeftButton")
  frame:SetScript("OnDragStart", frame.StartMoving); frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
  tinsert(UISpecialFrames, "BookOfDogsFrame")
  inset:ClearAllPoints(); inset:SetPoint("TOPLEFT", 8, -66); inset:SetPoint("BOTTOMRIGHT", -8, 32)

  local sub = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  sub:SetPoint("TOPLEFT", 66, -38); sub:SetText("The guild's book of dogs")

  local okSearch
  okSearch, search = pcall(CreateFrame, "EditBox", "BookOfDogsSearch", frame, "SearchBoxTemplate")
  if not okSearch or not search then search = CreateFrame("EditBox", "BookOfDogsSearch", frame, "InputBoxTemplate") end
  search:SetSize(200, 20); search:SetPoint("TOPRIGHT", -14, -36); search:SetAutoFocus(false)
  search:HookScript("OnTextChanged", function() FauxScrollFrame_SetOffset(scroll, 0); scroll:SetVerticalScroll(0); refresh() end)

  scroll = CreateFrame("ScrollFrame", "BookOfDogsScroll", inset, "FauxScrollFrameTemplate")
  scroll:SetPoint("TOPLEFT", 0, -4); scroll:SetPoint("BOTTOMRIGHT", -26, 4)
  scroll:SetScript("OnVerticalScroll", function(self, off) FauxScrollFrame_OnVerticalScroll(self, off, ROWH, refresh) end)

  rows = {}
  for i = 1, MAXROWS do
    local r = CreateFrame("Frame", nil, inset)
    r:SetHeight(ROWH); r:SetPoint("TOPLEFT", 4, -4 - (i - 1) * ROWH); r:SetPoint("RIGHT", inset, "RIGHT", -4, 0)
    if i % 2 == 0 then local bg = r:CreateTexture(nil, "BACKGROUND"); bg:SetAllPoints(); bg:SetColorTexture(1, 1, 1, 0.03) end
    local hl = r:CreateTexture(nil, "HIGHLIGHT"); hl:SetAllPoints()
    hl:SetTexture("Interface\\FriendsFrame\\UI-FriendsFrame-HighlightBar-Blue"); hl:SetBlendMode("ADD"); hl:SetAlpha(0.6)
    local line = r:CreateTexture(nil, "BORDER"); line:SetPoint("BOTTOMLEFT"); line:SetPoint("BOTTOMRIGHT"); line:SetHeight(1)
    line:SetColorTexture(1, 1, 1, 0.06)
    r.rank = r:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall"); r.rank:SetPoint("TOPLEFT", 4, -4)
    r.up = arrow(r, true); r.up:SetPoint("TOPLEFT", 26, -2)
    r.score = r:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge"); r.score:SetPoint("TOP", r.up, "BOTTOM", 0, 1); r.score:SetWidth(44)
    r.down = arrow(r, false); r.down:SetPoint("TOP", r.score, "BOTTOM", 0, 1)
    r.name = r:CreateFontString(nil, "OVERLAY", "GameFontNormal"); r.name:SetPoint("TOPLEFT", 78, -6)
    r.name:SetPoint("RIGHT", -44, 0); r.name:SetJustifyH("LEFT"); r.name:SetWordWrap(false)
    r.desc = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    r.desc:SetPoint("TOPLEFT", r.name, "BOTTOMLEFT", 0, -3); r.desc:SetPoint("RIGHT", -24, 0)
    r.desc:SetJustifyH("LEFT"); r.desc:SetJustifyV("TOP"); r.desc:SetHeight(26); r.desc:SetWordWrap(true)
    if r.desc.SetMaxLines then r.desc:SetMaxLines(2) end
    r.by = r:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall"); r.by:SetPoint("BOTTOMLEFT", 78, 5)
    r.del = CreateFrame("Button", nil, r); r.del:SetSize(16, 16); r.del:SetPoint("TOPRIGHT", -2, -4)
    r.del:SetNormalTexture("Interface\\Buttons\\UI-GroupLoot-Pass-Up")
    r.del:SetPushedTexture("Interface\\Buttons\\UI-GroupLoot-Pass-Down")
    r.del:SetHighlightTexture("Interface\\Buttons\\UI-GroupLoot-Pass-Highlight", "ADD")
    r.del:SetScript("OnClick", function()
      if not r.id then return end
      local e = NS.DB().e[r.id]
      StaticPopup_Show("BOOKOFDOGS_DELETE", e and (e.f or e.n) or "?", nil, r.id)
    end)
    r.del:SetScript("OnEnter", function(self) GameTooltip:SetOwner(self, "ANCHOR_LEFT"); GameTooltip:SetText("Remove from the book"); GameTooltip:Show() end)
    r.del:SetScript("OnLeave", GameTooltip_Hide)
    r.edit = CreateFrame("Button", nil, r); r.edit:SetSize(16, 16); r.edit:SetPoint("RIGHT", r.del, "LEFT", -4, 0)
    r.edit:SetNormalTexture("Interface\\Buttons\\UI-GuildButton-PublicNote-Up")
    r.edit:SetPushedTexture("Interface\\Buttons\\UI-GuildButton-PublicNote-Down")
    r.edit:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
    r.edit:SetScript("OnClick", function() if r.id then NS.OpenEditor(r.id) end end)
    r.edit:SetScript("OnEnter", function(self) GameTooltip:SetOwner(self, "ANCHOR_LEFT"); GameTooltip:SetText("Edit entry"); GameTooltip:Show() end)
    r.edit:SetScript("OnLeave", GameTooltip_Hide)
    -- full text on hover
    r:EnableMouse(true)
    r:SetScript("OnEnter", function(self)
      local e = self.id and NS.DB().e[self.id]; if not e then return end
      GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
      GameTooltip:SetText(NS.ColorName(e.f or e.n, e.c) .. (e.g and (" |cff40c040<" .. e.g .. ">|r") or ""), 1, 0.82, 0)
      if NS.ClassName(e.c) then GameTooltip:AddLine(NS.ColorName(NS.ClassName(e.c), e.c)) end
      GameTooltip:AddLine(e.d or "", 1, 1, 1, true)
      local up, down = 0, 0
      if e.v then for _, v in pairs(e.v) do if v > 0 then up = up + 1 else down = down + 1 end end end
      GameTooltip:AddLine(("%d up  ·  %d down"):format(up, down), 0.7, 0.7, 0.7)
      GameTooltip:AddLine(NS.CanDelete() and "Right-click: who voted, set class" or "Right-click to see who voted", 0.5, 0.5, 0.5)
      GameTooltip:Show()
    end)
    r:SetScript("OnLeave", GameTooltip_Hide)
    r:SetScript("OnMouseUp", function(self, button) if button == "RightButton" and self.id then NS.ShowVoters(self, self.id) end end)
    r:SetScript("OnMouseWheel", function(_, d) local f = scroll:GetScript("OnMouseWheel"); if f then f(scroll, d) end end)
    rows[i] = r
  end

  countText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  countText:SetPoint("BOTTOMLEFT", 16, 10)
  local ver = (C_AddOns and C_AddOns.GetAddOnMetadata or GetAddOnMetadata)(ADDON, "Version") or "?"
  NS.VERSION = ver
  local verText = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  verText:SetPoint("LEFT", countText, "RIGHT", 10, 0); verText:SetText("v" .. ver)
  local credit = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  credit:SetPoint("RIGHT", search, "LEFT", -12, 0); credit:SetText("Created by CHogan")

  local sync = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
  sync:SetSize(80, 22); sync:SetPoint("BOTTOMRIGHT", -24, 5); sync:SetText("Sync")
  sync:SetScript("OnClick", function() NS.RequestSync(true) end)
  sync:SetScript("OnEnter", function(self) GameTooltip:SetOwner(self, "ANCHOR_TOP"); GameTooltip:SetText("Sync"); GameTooltip:AddLine("Ask online guildmates for the whole book.", 1, 1, 1, true); GameTooltip:Show() end)
  sync:SetScript("OnLeave", GameTooltip_Hide)
  local add = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
  add:SetSize(110, 22); add:SetPoint("RIGHT", sync, "LEFT", -4, 0); add:SetText("Add Target")
  add:SetScript("OnClick", function()
    if UnitExists("target") and UnitIsPlayer("target") then NS.ShowAddPopup("target")
    else UIErrorsFrame:AddMessage("Target a player first.", 1, 0.1, 0.1) end
  end)
  add:SetScript("OnEnter", function(self) GameTooltip:SetOwner(self, "ANCHOR_TOP"); GameTooltip:SetText("Add Target"); GameTooltip:AddLine("Add your current target. You can also right-click any player and choose Add to Book of Dogs.", 1, 1, 1, true); GameTooltip:Show() end)
  add:SetScript("OnLeave", GameTooltip_Hide)

  local new = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
  new:SetSize(100, 22); new:SetPoint("RIGHT", add, "LEFT", -4, 0); new:SetText("New Entry")
  new:SetScript("OnClick", function() NS.OpenEditor(nil) end)
  new:SetScript("OnEnter", function(self) GameTooltip:SetOwner(self, "ANCHOR_TOP"); GameTooltip:SetText("New Entry"); GameTooltip:AddLine("Admins: add a player by typing their name.", 1, 1, 1, true); GameTooltip:Show() end)
  new:SetScript("OnLeave", GameTooltip_Hide)
  frame.newBtn = new

  local eb = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
  eb:SetSize(80, 22); eb:SetPoint("RIGHT", new, "LEFT", -4, 0); eb:SetText("Editors")
  eb:SetScript("OnClick", function() NS.OpenEditors() end)
  eb:SetScript("OnEnter", function(self) GameTooltip:SetOwner(self, "ANCHOR_TOP"); GameTooltip:SetText("Editors"); GameTooltip:AddLine("Give guild members edit and delete rights.", 1, 1, 1, true); GameTooltip:Show() end)
  eb:SetScript("OnLeave", GameTooltip_Hide)
  frame.edBtn = eb

  local grip = CreateFrame("Button", nil, frame)
  grip:SetSize(16, 16); grip:SetPoint("BOTTOMRIGHT", -4, 4); grip:SetFrameLevel(frame:GetFrameLevel() + 10)
  grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
  grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
  grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
  grip:SetScript("OnMouseDown", function() frame:StartSizing("BOTTOMRIGHT") end)
  grip:SetScript("OnMouseUp", function()
    frame:StopMovingOrSizing()
    local db = NS.DB()
    db.ui = db.ui or {}
    db.ui.w, db.ui.h = math.floor(frame:GetWidth() + 0.5), math.floor(frame:GetHeight() + 0.5)
  end)
  grip:SetScript("OnEnter", function(self) GameTooltip:SetOwner(self, "ANCHOR_LEFT"); GameTooltip:SetText("Drag to resize"); GameTooltip:Show() end)
  grip:SetScript("OnLeave", GameTooltip_Hide)
  -- the list's height changes with the window, so re-fit the rows (and the scroll bar) when it does
  frame:HookScript("OnSizeChanged", function() refresh() end)

  frame:SetScript("OnShow", function() PlaySound(SOUNDKIT and SOUNDKIT.IG_SPELLBOOK_OPEN or 829); refresh() end)
  frame:SetScript("OnHide", function() PlaySound(SOUNDKIT and SOUNDKIT.IG_SPELLBOOK_CLOSE or 830) end)
  frame:Hide()
end

-- right-click an entry: who voted which way (each person's current vote only)
local function votersOf(id)
  local e = NS.DB().e[id]
  local ups, downs = {}, {}
  if e and e.v then
    for who, v in pairs(e.v) do
      local short = NS.Display(who)
      if v > 0 then ups[#ups + 1] = short else downs[#downs + 1] = short end
    end
  end
  table.sort(ups); table.sort(downs)
  return e, ups, downs
end
function NS.ShowVoters(owner, id)
  local e, ups, downs = votersOf(id)
  if not e then return end
  local title = NS.ColorName(e.f or e.n, e.c) .. "  (" .. ((e.s or 0) > 0 and "+" or "") .. (e.s or 0) .. ")"
  if MenuUtil and MenuUtil.CreateContextMenu then
    MenuUtil.CreateContextMenu(owner, function(_, root)
      root:CreateTitle(title)
      root:CreateDivider()
      if #ups == 0 and #downs == 0 then root:CreateTitle("|cff888888No votes yet|r") end
      if #ups > 0 then
        root:CreateTitle("|cff40ff40Voted up (" .. #ups .. ")|r")
        for _, n in ipairs(ups) do root:CreateTitle("|cffffffff" .. n .. "|r") end
      end
      if #downs > 0 then
        root:CreateTitle("|cffff5050Voted down (" .. #downs .. ")|r")
        for _, n in ipairs(downs) do root:CreateTitle("|cffffffff" .. n .. "|r") end
      end
      -- admins and editors: quick class change, and the full editor
      if NS.CanDelete() then
        root:CreateDivider()
        local sub = root:CreateButton("Set class")
        local function set(c) NS.Edit(id, e.f or e.n, e.g or "", e.d or "", c) end
        for _, c in ipairs(NS.CLASSES) do
          if NS.ValidClass(c) then
            sub:CreateButton(NS.ColorName(NS.ClassName(c), c) .. (e.c == c and "  |cffffffff(current)|r" or ""), function() set(c) end)
          end
        end
        root:CreateButton("Edit entry...", function() NS.OpenEditor(id) end)
      end
    end)
    return
  end
  -- older clients: show the same list as a tooltip
  GameTooltip:SetOwner(owner, "ANCHOR_CURSOR")
  GameTooltip:SetText(title, 1, 0.82, 0)
  if #ups == 0 and #downs == 0 then GameTooltip:AddLine("No votes yet", 0.6, 0.6, 0.6) end
  if #ups > 0 then GameTooltip:AddLine("Voted up (" .. #ups .. ")", 0.25, 1, 0.25); for _, n in ipairs(ups) do GameTooltip:AddLine("  " .. n, 1, 1, 1) end end
  if #downs > 0 then GameTooltip:AddLine("Voted down (" .. #downs .. ")", 1, 0.3, 0.3); for _, n in ipairs(downs) do GameTooltip:AddLine("  " .. n, 1, 1, 1) end end
  GameTooltip:Show()
end

-- /who lookup for a typed name. Must start from a click (the game requires it).
-- callback(info or nil); info = {name, guild, level, class}
local whoWait
function NS.WhoLookup(name, callback)
  local send = C_FriendList and C_FriendList.SendWho or SendWho
  if not send or not name or name == "" then callback(nil); return end
  local first = name:match("^%S+")
  local ev = CreateFrame("Frame")
  -- keep the Who window from popping open for our lookup
  local ff = FriendsFrame
  local hadEvent = ff and ff.IsEventRegistered and ff:IsEventRegistered("WHO_LIST_UPDATE")
  if hadEvent then ff:UnregisterEvent("WHO_LIST_UPDATE") end
  if C_FriendList and C_FriendList.SetWhoToUi then pcall(C_FriendList.SetWhoToUi, true) elseif SetWhoToUI then pcall(SetWhoToUI, 1) end
  local done = false
  local function finish(info)
    if done then return end
    done = true
    ev:UnregisterAllEvents(); ev:SetScript("OnEvent", nil)
    if hadEvent then ff:RegisterEvent("WHO_LIST_UPDATE") end
    callback(info)
  end
  ev:RegisterEvent("WHO_LIST_UPDATE")
  ev:SetScript("OnEvent", function()
    local n = (C_FriendList and C_FriendList.GetNumWhoResults or GetNumWhoResults)() or 0
    local best
    for i = 1, n do
      local w
      if C_FriendList and C_FriendList.GetWhoInfo then
        w = C_FriendList.GetWhoInfo(i)
        w = w and {name = w.fullName, guild = w.fullGuildName, level = w.level, class = w.filename}
      else
        local nm, gd, lv, _, _, _, file = GetWhoInfo(i)
        w = {name = nm, guild = gd, level = lv, class = file}
      end
      if w and type(w.name) == "string" and not (issecretvalue and issecretvalue(w.name)) then
        local wn = w.name:match("^[^%-]+")
        if wn == name then best = w; break end                       -- exact full name
        if not best and wn:match("^%S+") == first and not name:find(" ") then best = w end
      end
    end
    if best then
      if best.guild == "" then best.guild = nil end
      if not NS.ValidClass(best.class) then best.class = nil end
    end
    finish(best)
  end)
  C_Timer.After(4, function() finish(nil) end) -- no answer (offline, or /who on cooldown)
  local ok = pcall(send, 'n-"' .. name .. '"')
  if not ok then finish(nil) end
end

-- admin editor: new entry by typing a name, or edit an existing one
local editor
local function field(parent, label, y, width, max)
  local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  fs:SetPoint("TOPLEFT", 22, y); fs:SetText(label)
  local eb = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
  eb:SetSize(width, 20); eb:SetPoint("TOPLEFT", 26, y - 14); eb:SetAutoFocus(false); eb:SetMaxLetters(max)
  eb:SetScript("OnEscapePressed", function() parent:Hide() end)
  return eb
end
local function buildEditor()
  local ok, f = pcall(CreateFrame, "Frame", "BookOfDogsEditor", UIParent, "BackdropTemplate")
  editor = f
  editor:SetSize(400, 270); editor:SetPoint("CENTER", 0, 80)
  editor:SetFrameStrata("DIALOG"); editor:SetToplevel(true); editor:EnableMouse(true)
  editor:SetMovable(true); editor:RegisterForDrag("LeftButton")
  editor:SetScript("OnDragStart", editor.StartMoving); editor:SetScript("OnDragStop", editor.StopMovingOrSizing)
  editor:SetBackdrop({bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background", edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
                      tile = true, tileSize = 32, edgeSize = 32, insets = {left = 11, right = 12, top = 12, bottom = 11}})
  tinsert(UISpecialFrames, "BookOfDogsEditor")
  editor.title = editor:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge"); editor.title:SetPoint("TOP", 0, -18)
  editor.name = field(editor, "Name (Name or Name-Realm)", -46, 220, 60)
  editor.guild = field(editor, "Guild (optional)", -86, 220, 40)
  editor.desc = field(editor, "Description (max " .. NS.MAXDESC .. ")", -126, 340, NS.MAXDESC)
  -- class picker: click to choose (sets the name color in the Book)
  local cl = editor:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  cl:SetPoint("TOPLEFT", 22, -166); cl:SetText("Class")
  local pick = CreateFrame("Button", nil, editor, "UIPanelButtonTemplate")
  pick:SetSize(150, 22); pick:SetPoint("TOPLEFT", 24, -180)
  editor.classBtn = pick
  function editor.setClass(c)
    editor.class = NS.ValidClass(c) and c or nil
    local n = NS.ClassName(editor.class)
    pick:SetText(n and NS.ColorName(n, editor.class) or "Unknown")
  end
  pick:SetScript("OnClick", function(self)
    if MenuUtil and MenuUtil.CreateContextMenu then
      MenuUtil.CreateContextMenu(self, function(_, root)
        root:CreateTitle("Class")
        root:CreateButton("Unknown", function() editor.setClass(nil) end)
        for _, c in ipairs(NS.CLASSES) do
          if NS.ValidClass(c) then root:CreateButton(NS.ColorName(NS.ClassName(c), c), function() editor.setClass(c) end) end
        end
      end)
    else -- no menus on this client: cycle through the classes
      local i = 0
      for k, c in ipairs(NS.CLASSES) do if c == editor.class then i = k end end
      editor.setClass(NS.CLASSES[i + 1])
    end
  end)
  editor.name:SetScript("OnTabPressed", function() editor.guild:SetFocus() end)
  editor.guild:SetScript("OnTabPressed", function() editor.desc:SetFocus() end)
  editor.desc:SetScript("OnTabPressed", function() editor.name:SetFocus() end)
  local save = CreateFrame("Button", nil, editor, "UIPanelButtonTemplate")
  save:SetSize(110, 22); save:SetPoint("BOTTOMRIGHT", editor, "BOTTOM", -4, 18); save:SetText(SAVE or "Save")
  local cancel = CreateFrame("Button", nil, editor, "UIPanelButtonTemplate")
  cancel:SetSize(110, 22); cancel:SetPoint("BOTTOMLEFT", editor, "BOTTOM", 4, 18); cancel:SetText(CANCEL)
  cancel:SetScript("OnClick", function() editor:Hide() end)
  local function submit()
    local n, g, d = editor.name:GetText(), editor.guild:GetText(), editor.desc:GetText()
    if NS.Clean(n) == "" or NS.Clean(d) == "" then UIErrorsFrame:AddMessage("Name and description are required.", 1, 0.1, 0.1) return end
    if NS.Blocked(d) then
      print("|cff" .. NS.GOLD .. "Book of Dogs|r: |cffff5555that description has language that isn't allowed in the Book.|r")
      return
    end
    if editor.id then
      if NS.Edit(editor.id, n, g, d, editor.class) then editor:Hide() end
      return
    end
    -- new entry: look the player up with /who for their class (and guild if left blank)
    if editor.busy then return end
    editor.busy = true; save:SetText("Looking up..."); save:Disable()
    NS.WhoLookup(NS.Clean(n, 60), function(info)
      editor.busy = false; save:SetText(SAVE or "Save"); save:Enable()
      local class = editor.class or (info and info.class)
      if g == "" and info and info.guild then g = info.guild end
      if info and info.guild and info.guild:lower() == NS.GUILD then
        print("|cff" .. NS.GOLD .. "Book of Dogs|r: |cffff5555" .. n .. " is in <Dog> and can't be added.|r")
        return
      end
      if info then
        print(("|cff%sBook of Dogs|r: found %s: level %s %s%s."):format(NS.GOLD, info.name or n, info.level or "?",
          NS.ClassName(info.class) or "?", info.guild and (" <" .. info.guild .. ">") or ""))
      else
        print("|cff" .. NS.GOLD .. "Book of Dogs|r: /who didn't find " .. n .. " online, so the class is left unknown (you can set it later).")
      end
      if NS.Add(n, nil, g, d, nil, true, class) then editor:Hide() end
    end)
  end
  save:SetScript("OnClick", submit)
  editor.desc:SetScript("OnEnterPressed", submit)
  editor.name:SetScript("OnEnterPressed", function() editor.guild:SetFocus() end)
  editor.guild:SetScript("OnEnterPressed", function() editor.desc:SetFocus() end)
end
function NS.OpenEditor(id)
  if not NS.CanDelete() then return end
  if not editor then buildEditor() end
  local e = id and NS.DB().e[id]
  editor.id = e and id or nil
  editor.title:SetText(e and "Edit entry" or "New entry")
  editor.name:SetText(e and (e.f or e.n) or ""); editor.guild:SetText(e and e.g or ""); editor.desc:SetText(e and e.d or "")
  editor.setClass(e and e.c)
  editor:Show(); editor.name:SetFocus()
end

-- editors manager (main admin only)
local edWin
local ED_ROWS = 10
local function refreshEditors()
  if not edWin or not edWin:IsShown() then return end
  local names = NS.Editors()
  for i = 1, ED_ROWS do
    local r = edWin.rows[i]
    if names[i] then r.name:SetText(names[i]); r.who = names[i]; r:Show() else r.who = nil; r:Hide() end
  end
  edWin.empty:SetShown(#names == 0)
  edWin.note:SetText(#names > ED_ROWS and ("+" .. (#names - ED_ROWS) .. " more (see /dogs status)") or "Guild master and officers always have these rights.")
end
NS.listeners[#NS.listeners + 1] = refreshEditors
local function buildEditors()
  edWin = CreateFrame("Frame", "BookOfDogsEditors", UIParent, "BackdropTemplate")
  edWin:SetSize(320, 400); edWin:SetPoint("CENTER", 0, 40)
  edWin:SetFrameStrata("DIALOG"); edWin:SetToplevel(true); edWin:EnableMouse(true)
  edWin:SetMovable(true); edWin:RegisterForDrag("LeftButton")
  edWin:SetScript("OnDragStart", edWin.StartMoving); edWin:SetScript("OnDragStop", edWin.StopMovingOrSizing)
  edWin:SetBackdrop({bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background", edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
                     tile = true, tileSize = 32, edgeSize = 32, insets = {left = 11, right = 12, top = 12, bottom = 11}})
  tinsert(UISpecialFrames, "BookOfDogsEditors")
  local t = edWin:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge"); t:SetPoint("TOP", 0, -18); t:SetText("Book of Dogs Editors")
  local sub = edWin:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"); sub:SetPoint("TOP", 0, -40)
  sub:SetText("Editors can add, edit and delete entries.")
  local close = CreateFrame("Button", nil, edWin, "UIPanelCloseButton"); close:SetPoint("TOPRIGHT", -6, -6)
  local input = CreateFrame("EditBox", nil, edWin, "InputBoxTemplate")
  input:SetSize(170, 20); input:SetPoint("TOPLEFT", 30, -64); input:SetAutoFocus(false); input:SetMaxLetters(60)
  local hint = input:CreateFontString(nil, "ARTWORK", "GameFontDisable"); hint:SetPoint("LEFT", 2, 0); hint:SetText("Guild member name")
  input:SetScript("OnTextChanged", function(self) hint:SetShown(self:GetText() == "") end)
  local add = CreateFrame("Button", nil, edWin, "UIPanelButtonTemplate")
  add:SetSize(80, 22); add:SetPoint("LEFT", input, "RIGHT", 8, 0); add:SetText(ADD or "Add")
  local function doAdd() local n = input:GetText(); if NS.Clean(n) ~= "" and NS.SetEditor(n, true) then input:SetText(""); input:ClearFocus() end end
  add:SetScript("OnClick", doAdd); input:SetScript("OnEnterPressed", doAdd)
  input:SetScript("OnEscapePressed", function() edWin:Hide() end)
  edWin.rows = {}
  for i = 1, ED_ROWS do
    local r = CreateFrame("Frame", nil, edWin); r:SetSize(260, 24); r:SetPoint("TOPLEFT", 28, -96 - (i - 1) * 26)
    local bg = r:CreateTexture(nil, "BACKGROUND"); bg:SetAllPoints(); bg:SetColorTexture(1, 1, 1, i % 2 == 0 and 0.04 or 0.08)
    r.name = r:CreateFontString(nil, "OVERLAY", "GameFontHighlight"); r.name:SetPoint("LEFT", 8, 0)
    local rm = CreateFrame("Button", nil, r, "UIPanelButtonTemplate"); rm:SetSize(70, 20); rm:SetPoint("RIGHT", -2, 0); rm:SetText(REMOVE or "Remove")
    rm:SetScript("OnClick", function() if r.who then NS.SetEditor(r.who, false) end end)
    edWin.rows[i] = r
  end
  edWin.empty = edWin:CreateFontString(nil, "OVERLAY", "GameFontDisable"); edWin.empty:SetPoint("TOP", 0, -110); edWin.empty:SetText("No editors yet.")
  edWin.note = edWin:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall"); edWin.note:SetPoint("BOTTOM", 0, 20)
  edWin:SetScript("OnShow", refreshEditors)
end
function NS.OpenEditors()
  if not NS.IsMainAdmin() then return end
  if not edWin then buildEditors() end
  edWin:Show()
end

StaticPopupDialogs.BOOKOFDOGS_DELETE = {
  text = "Remove |cffffffff%s|r from the Book of Dogs for the whole guild?",
  button1 = DELETE or "Delete", button2 = CANCEL,
  timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
  OnAccept = function(_, id) NS.Delete(id) end,
}

-- open the Book searched to one player
function NS.ShowEntry(text)
  if not frame then build() end
  frame:Show()
  search:SetText(text or "")
end

function NS.Toggle()
  if not frame then build() end
  if frame:IsShown() then frame:Hide() else frame:Show() end
end
