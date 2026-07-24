--[[ GroupTab.lua - CleanBot-style tabbed window.
     Tabs: Manage | Individual | Group | Settings. The Group tab is a 3-pane
     layout (class filters . bot list . controls) wired to the real `.bot`
     commands only (no strategies - this server doesn't have them).
     Vanilla 1.12 / Lua 5.0.
]]--

local CB = CleanBotTortoise

local TABS = { "Manage", "Individual", "Group", "Settings" }

-- setrole args - verify with `.bot setrole`; adjust here if different.
local ROLES = {
  { key = "tank",   name = "Tank" },
  { key = "healer", name = "Healer" },
  { key = "dps",    name = "DPS" },
}

local CLASS_ORDER = {
  "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "SHAMAN", "MAGE", "WARLOCK", "DRUID",
}
local CLASS_NAME = {
  WARRIOR = "Warrior", PALADIN = "Paladin", HUNTER = "Hunter", ROGUE = "Rogue",
  PRIEST = "Priest", SHAMAN = "Shaman", MAGE = "Mage", WARLOCK = "Warlock", DRUID = "Druid",
}

-- Right-pane action buttons (broadcast .bot commands).
local ACTIONS = {
  { label = "Come to Me",  kind = "cmd",   arg = "cometome" },
  { label = "Attack",      kind = "cmd",   arg = "attackstart" },
  { label = "Stop",        kind = "cmd",   arg = "attackstop" },
  { label = "Pull",        kind = "cmd",   arg = "pull" },
  { label = "AoE",         kind = "cmd",   arg = "aoe" },
  { label = "Use Object",  kind = "cmd",   arg = "usegobject" },
  { label = "Pause",       kind = "cmd",   arg = "pause" },
  { label = "Unpause",     kind = "cmd",   arg = "unpause" },
  { label = "Focus",       kind = "mark",  arg = "focusmark", icon = 8 },
  { label = "CC",          kind = "mark",  arg = "ccmark",    icon = 7 },
  { label = "Clear Marks", kind = "clear" },
}

--------------------------------------------------------------------------------
-- Roster helpers
--------------------------------------------------------------------------------

local function BotUnits()
  local units = {}
  local n = GetNumRaidMembers()
  local i
  if n > 0 then
    for i = 1, n do
      local u = "raid" .. i
      if UnitExists(u) and not UnitIsUnit(u, "player") then table.insert(units, u) end
    end
  else
    n = GetNumPartyMembers()
    for i = 1, n do table.insert(units, "party" .. i) end
  end
  return units
end

local function ClassColor(class)
  local c = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
  if c then return c.r, c.g, c.b end
  return 1, 1, 1
end

-- unit-level primitive: sends the real command. skipRefresh lets batch callers
-- (ApplyRoleToSelected) avoid redrawing the list after every single bot.
function CB.SetBotRole(unit, role, skipRefresh)
  if not unit or not UnitExists(unit) then return end
  TargetUnit(unit)
  SendChatMessage(".bot setrole " .. role, "SAY")
  TargetLastTarget()
  CB.db.botRoles = CB.db.botRoles or {}
  CB.db.botRoles[UnitName(unit)] = role
  if not skipRefresh then CB.RefreshGroup() end
end

-- Apply a role to every currently selected bot (shift-click multi-select).
function CB.ApplyRoleToSelected(role)
  local units = BotUnits()
  local i, count = 1, 0
  for i = 1, table.getn(units) do
    local name = UnitName(units[i])
    if name and CB.selectedBots[name] then
      CB.SetBotRole(units[i], role, true)
      count = count + 1
    end
  end
  if count == 0 then
    CB.Print("|cffff5555Select at least one bot first (click a row; shift-click for more).|r")
  else
    if CB.SetStatus then CB.SetStatus("setrole " .. role .. " -> " .. count .. " bot(s)") end
  end
  CB.RefreshGroup()
end

-- Clear the (client-side) role for every selected bot.
function CB.ClearSelectedRoles()
  CB.db.botRoles = CB.db.botRoles or {}
  local name
  local count = 0
  for name in pairs(CB.selectedBots) do
    CB.db.botRoles[name] = nil
    count = count + 1
  end
  if CB.SetStatus then CB.SetStatus("cleared role -> " .. count .. " bot(s)") end
  CB.RefreshGroup()
end

-- Clear the (client-side) role for every bot, selected or not.
function CB.ClearAllRoles()
  CB.db.botRoles = {}
  if CB.SetStatus then CB.SetStatus("cleared all roles") end
  CB.RefreshGroup()
end

-- LFG-style role icon per stored role (shield=tank, +=healer, sword=dps).
local ROLE_ICON = {
  tank   = "Interface\\Icons\\INV_Shield_06",
  healer = "Interface\\Icons\\Spell_ChargePositive",
  dps    = "Interface\\Icons\\INV_Sword_04",
}

-- Class icons: WoW's class atlas + CleanBot's tex-coord table.
local CLASS_ICON_TEX = "Interface\\WorldStateFrame\\Icons-Classes"
local CLASS_ICON_COORDS = {
  WARRIOR = { 0, 0.25, 0, 0.25 },    MAGE = { 0.25, 0.5, 0, 0.25 },
  ROGUE   = { 0.5, 0.75, 0, 0.25 },  DRUID = { 0.75, 1.0, 0, 0.25 },
  HUNTER  = { 0, 0.25, 0.25, 0.5 },  SHAMAN = { 0.25, 0.5, 0.25, 0.5 },
  PRIEST  = { 0.5, 0.75, 0.25, 0.5 }, WARLOCK = { 0.75, 1.0, 0.25, 0.5 },
  PALADIN = { 0, 0.25, 0.5, 0.75 },  DEATHKNIGHT = { 0.25, 0.5, 0.5, 0.75 },
}

local GROUP_ROW_H = 18
local GROUP_VISIBLE = 16

local function DoAction(spec)
  if spec.kind == "mark" then CB.BotMark(spec.icon, spec.arg)
  elseif spec.kind == "clear" then CB.BotClearMarks()
  else CB.Bot(spec.arg) end
end

--------------------------------------------------------------------------------
-- Recruit: /who available playerbots (+-5 levels), invite by name
--------------------------------------------------------------------------------

local LOCALIZED_TO_TOKEN = {
  Warrior = "WARRIOR", Mage = "MAGE", Rogue = "ROGUE", Druid = "DRUID",
  Hunter = "HUNTER", Shaman = "SHAMAN", Priest = "PRIEST",
  Warlock = "WARLOCK", Paladin = "PALADIN",
}

CB.available = {}
local scanPending = false
local scanTime = 0
local scanStage = 0 -- 1 = zone query, 2 = level-range query

local AVAIL_ROW_H = 15
local AVAIL_VISIBLE = 21

local function InPartyByName(name)
  local i, n = nil, GetNumRaidMembers()
  if n > 0 then
    for i = 1, n do if UnitName("raid" .. i) == name then return true end end
  else
    n = GetNumPartyMembers()
    for i = 1, n do if UnitName("party" .. i) == name then return true end end
  end
  return name == UnitName("player")
end

local function IssueWho(filter)
  scanPending = true
  scanTime = GetTime()
  SetWhoToUI(1)
  SendWho(filter)
end

-- Prefer bots in the current zone; if none, +-3 levels; at level 60, only 60.
function CB.ScanWho()
  if scanPending and (GetTime() - scanTime) < 2 then return end
  local lvl = UnitLevel("player") or 1
  if lvl >= 60 then
    scanStage = 0
    IssueWho("60")
    return
  end
  local zone = GetRealZoneText()
  if zone and zone ~= "" then
    scanStage = 1
    IssueWho('z-"' .. zone .. '"')
  else
    scanStage = 2
    IssueWho((lvl - 3) .. "-" .. (lvl + 3))
  end
end

local function CollectWho()
  CB.available = {}
  local n = GetNumWhoResults()
  local i
  for i = 1, n do
    local name, _, level, _, classLoc, zone = GetWhoInfo(i)
    if name and not InPartyByName(name) then
      -- string.upper turns the localized class ("Warrior") into the token ("WARRIOR").
      table.insert(CB.available, {
        name = name, level = level or 0,
        class = classLoc and string.upper(classLoc), zone = zone,
      })
    end
  end
  table.sort(CB.available, function(a, b) return a.level < b.level end)
end

function CB.OnWhoUpdate()
  if not scanPending then return end
  -- Our SetWhoToUI(1) query opens the Who UI; close it since we read it silently.
  if FriendsFrame and FriendsFrame:IsShown() then HideUIPanel(FriendsFrame) end
  -- Zone query returned nothing -> fall back to a +-3 level range.
  if scanStage == 1 and GetNumWhoResults() == 0 then
    scanStage = 2
    local lvl = UnitLevel("player") or 1
    IssueWho((lvl - 3) .. "-" .. (lvl + 3))
    return
  end
  scanPending = false
  SetWhoToUI(0)
  CollectWho()
  CB.RefreshAvailable()
end

local function OnAvailClick()
  if this.botName then
    InviteByName(this.botName)
    if CB.SetStatus then CB.SetStatus("invited " .. this.botName) end
  end
end

-- Virtual scrolling: fixed pool of AVAIL_VISIBLE rows + FauxScrollFrame offset.
function CB.RefreshAvailable()
  if not CB.availRows or not CB.availScroll then return end
  local num = table.getn(CB.available)
  FauxScrollFrame_Update(CB.availScroll, num, AVAIL_VISIBLE, AVAIL_ROW_H)
  local offset = FauxScrollFrame_GetOffset(CB.availScroll)
  local line
  for line = 1, AVAIL_VISIBLE do
    local row = CB.availRows[line]
    local idx = line + offset
    if idx <= num then
      local b = CB.available[idx]
      row.botName = b.name
      row.lvl:SetText("|cffffd200" .. b.level .. "|r")
      row.txt:SetText(b.name)
      row.zone:SetText(b.zone or "")
      local rr, gg, bb = ClassColor(b.class)
      row.txt:SetTextColor(rr, gg, bb)
      local coords = b.class and CLASS_ICON_COORDS[b.class]
      if coords then
        row.cico:SetTexture(CLASS_ICON_TEX)
        row.cico:SetTexCoord(coords[1], coords[2], coords[3], coords[4]); row.cico:Show()
      else
        row.cico:Hide()
      end
      row:Show()
    else
      row:Hide()
    end
  end
  if CB.availHeader then CB.availHeader:SetText("Available (" .. num .. ")") end
end

--------------------------------------------------------------------------------
-- Tab switching
--------------------------------------------------------------------------------

function CB.SelectTab(name)
  CB.activeTab = name
  local i
  for i = 1, table.getn(TABS) do
    local t = TABS[i]
    if CB.tabBody[t] then
      if t == name then CB.tabBody[t]:Show() else CB.tabBody[t]:Hide() end
    end
    if CB.tabButton[t] then
      if t == name then CB.tabButton[t]:LockHighlight() else CB.tabButton[t]:UnlockHighlight() end
    end
  end
  if name == "Group" then CB.RefreshGroup(); CB.ScanWho() end
  if name == "Settings" then CB.RefreshKeybinds() end
end

--------------------------------------------------------------------------------
-- Group tab refresh (filters + bot list + header)
--------------------------------------------------------------------------------

-- Virtual scrolling, matching the Available list's pattern: a fixed pool of
-- GROUP_VISIBLE row buttons, repositioned/relabeled from FauxScrollFrame's offset.
function CB.RefreshGroup()
  if not CB.win or not CB.win:IsShown() or CB.activeTab ~= "Group" then return end
  local units = BotUnits()

  local i
  local list = {}
  for i = 1, table.getn(units) do table.insert(list, units[i]) end
  table.sort(list, function(a, b) return (UnitLevel(a) or 0) < (UnitLevel(b) or 0) end)
  local num = table.getn(list)

  if CB.groupScroll then
    FauxScrollFrame_Update(CB.groupScroll, num, GROUP_VISIBLE, GROUP_ROW_H)
    local offset = FauxScrollFrame_GetOffset(CB.groupScroll)
    for i = 1, GROUP_VISIBLE do
      local row = CB.botRows[i]
      local idx = i + offset
      if idx <= num then
        local unit = list[idx]
        local _, cls = UnitClass(unit)
        local name = UnitName(unit)
        row.unit = unit
        local r, g, b = ClassColor(cls)
        row.lvl:SetText("|cffffd200" .. (UnitLevel(unit) or "?") .. "|r")
        row.txt:SetText(name or "?")
        row.txt:SetTextColor(r, g, b)
        local role = name and CB.db.botRoles and CB.db.botRoles[name]
        if role and ROLE_ICON[role] then
          row.roleIcon:SetTexture(ROLE_ICON[role]); row.roleIcon:Show()
        else
          row.roleIcon:Hide()
        end
        local coords = cls and CLASS_ICON_COORDS[cls]
        if coords then
          row.classIcon:SetTexture(CLASS_ICON_TEX)
          row.classIcon:SetTexCoord(coords[1], coords[2], coords[3], coords[4])
          row.classIcon:Show()
        else
          row.classIcon:Hide()
        end
        if name and CB.selectedBots[name] then row.hl:Show() else row.hl:Hide() end
        row:Show()
      else
        row:Hide()
      end
    end
  end

  CB.groupHeader:SetText("Managing: " .. num .. " bot" .. (num == 1 and "" or "s"))

  local selCount, selList = 0, {}
  for nm in pairs(CB.selectedBots) do
    selCount = selCount + 1
    table.insert(selList, nm)
  end
  if selCount == 0 then
    CB.groupSelected:SetText("Selected: (none - click a bot)")
  elseif selCount <= 3 then
    CB.groupSelected:SetText("Selected: " .. table.concat(selList, ", "))
  else
    CB.groupSelected:SetText("Selected: " .. selCount .. " bots")
  end

  -- Show "Convert to Raid" once the party is full (5) and not yet a raid.
  if CB.convertBtn then
    if GetNumRaidMembers() == 0 and GetNumPartyMembers() >= 4 then
      CB.convertBtn:Show()
    else
      CB.convertBtn:Hide()
    end
  end
end

--------------------------------------------------------------------------------
-- Window construction
--------------------------------------------------------------------------------

local function RoleDropInit()
  for i = 1, table.getn(ROLES) do
    local roleKey = ROLES[i].key
    local roleName = ROLES[i].name
    local info = {}
    info.text = roleName
    info.notCheckable = 1
    info.func = function()
      UIDropDownMenu_SetText(roleName, CB.roleDrop)  -- 1.12 order: (text, frame)
      CB.ApplyRoleToSelected(roleKey)
    end
    UIDropDownMenu_AddButton(info)
  end

  local clr = {}
  clr.text = "Clear Role"
  clr.notCheckable = 1
  clr.func = function()
    UIDropDownMenu_SetText("Set Role...", CB.roleDrop)
    CB.ClearSelectedRoles()
  end
  UIDropDownMenu_AddButton(clr)

  local clrAll = {}
  clrAll.text = "Clear All"
  clrAll.notCheckable = 1
  clrAll.func = function()
    UIDropDownMenu_SetText("Set Role...", CB.roleDrop)
    CB.ClearAllRoles()
  end
  UIDropDownMenu_AddButton(clrAll)
end

local function BuildGroupBody(body)
  local BD = { bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", tile = true, tileSize = 16,
    edgeSize = 12, insets = { left = 3, right = 3, top = 3, bottom = 3 } }

  -- Left: available bots (/who) - scrollable, click a name to invite.
  CB.availHeader = body:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  CB.availHeader:SetPoint("TOPLEFT", body, "TOPLEFT", 2, -2)
  CB.availHeader:SetText("Available (0)")

  local rescan = CreateFrame("Button", nil, body, "UIPanelButtonTemplate")
  rescan:SetWidth(60); rescan:SetHeight(18)
  rescan:SetPoint("TOPLEFT", body, "TOPLEFT", 182, -1)
  rescan:SetText("Rescan")
  rescan:SetScript("OnClick", function() CB.ScanWho() end)

  local ap = CreateFrame("Frame", nil, body)
  ap:SetPoint("TOPLEFT", body, "TOPLEFT", 0, -22)
  ap:SetPoint("BOTTOMLEFT", body, "BOTTOMLEFT", 0, 4)
  ap:SetWidth(244)
  ap:SetBackdrop(BD); ap:SetBackdropColor(0, 0, 0, 0.4)
  CB.availPane = ap

  local scroll = CreateFrame("ScrollFrame", "CleanBotTortoiseAvailScroll", ap, "FauxScrollFrameTemplate")
  scroll:SetPoint("TOPLEFT", ap, "TOPLEFT", 5, -5)
  scroll:SetPoint("BOTTOMRIGHT", ap, "BOTTOMRIGHT", -26, 5)
  scroll:SetScript("OnVerticalScroll", function()
    FauxScrollFrame_OnVerticalScroll(AVAIL_ROW_H, function() CB.RefreshAvailable() end)
  end)
  CB.availScroll = scroll

  CB.availRows = {}
  local line
  for line = 1, AVAIL_VISIBLE do
    local row = CreateFrame("Button", nil, ap)
    row:SetHeight(AVAIL_ROW_H)
    row:SetPoint("TOPLEFT", scroll, "TOPLEFT", 0, -(line - 1) * AVAIL_ROW_H)
    row:SetPoint("RIGHT", scroll, "RIGHT", 0, 0)
    row.lvl = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    row.lvl:SetPoint("LEFT", row, "LEFT", 3, 0); row.lvl:SetWidth(20)
    row.cico = row:CreateTexture(nil, "OVERLAY")
    row.cico:SetWidth(12); row.cico:SetHeight(12); row.cico:SetPoint("LEFT", row, "LEFT", 24, 0)
    row.txt = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    row.txt:SetPoint("LEFT", row, "LEFT", 40, 0); row.txt:SetWidth(94); row.txt:SetJustifyH("LEFT")
    row.zone = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    row.zone:SetPoint("LEFT", row, "LEFT", 136, 0); row.zone:SetPoint("RIGHT", row, "RIGHT", -2, 0)
    row.zone:SetJustifyH("LEFT")
    row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
    row:SetScript("OnClick", OnAvailClick)
    row:Hide()
    CB.availRows[line] = row
  end

  -- Center: controls for the selected bot + convert-to-raid.
  local cx = 254
  CB.groupHeader = body:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  CB.groupHeader:SetPoint("TOPLEFT", body, "TOPLEFT", cx, -4)
  CB.groupHeader:SetText("Managing: 0 bots")

  CB.groupSelected = body:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  CB.groupSelected:SetPoint("TOPLEFT", body, "TOPLEFT", cx, -24)
  CB.groupSelected:SetWidth(104); CB.groupSelected:SetJustifyH("LEFT")
  CB.groupSelected:SetText("Selected: (none)")

  local roleLabel = body:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  roleLabel:SetPoint("TOPLEFT", body, "TOPLEFT", cx, -52)
  roleLabel:SetText("Role:")

  local drop = CreateFrame("Frame", "CleanBotTortoiseRoleDrop", body, "UIDropDownMenuTemplate")
  drop:SetPoint("TOPLEFT", body, "TOPLEFT", cx - 14, -64)
  UIDropDownMenu_Initialize(drop, RoleDropInit)
  UIDropDownMenu_SetWidth(96, drop)
  UIDropDownMenu_SetText("Set Role...", drop)
  CB.roleDrop = drop

  local convert = CreateFrame("Button", nil, body, "UIPanelButtonTemplate")
  convert:SetWidth(104); convert:SetHeight(22)
  convert:SetPoint("TOPLEFT", body, "TOPLEFT", cx, -104)
  convert:SetText("Convert to Raid")
  convert:SetScript("OnClick", function() ConvertToRaid() end)
  convert:Hide()
  CB.convertBtn = convert

  -- Right: your Group / Raid bots (Lvl | Name).
  local grx = 368
  local grLabel = body:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  grLabel:SetPoint("TOPLEFT", body, "TOPLEFT", grx + 2, -2)
  grLabel:SetText("Group / Raid")

  local bp = CreateFrame("Frame", nil, body)
  bp:SetWidth(184); bp:SetHeight(334)
  bp:SetPoint("TOPLEFT", body, "TOPLEFT", grx, -20)
  bp:SetBackdrop(BD); bp:SetBackdropColor(0, 0, 0, 0.4)
  CB.botPane = bp

  local hLvl = bp:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  hLvl:SetPoint("TOPLEFT", bp, "TOPLEFT", 15, -4); hLvl:SetText("|cffffffffLvl|r")
  local hName = bp:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  hName:SetPoint("TOPLEFT", bp, "TOPLEFT", 58, -4); hName:SetText("|cffffffffName|r")

  local gscroll = CreateFrame("ScrollFrame", "CleanBotTortoiseGroupScroll", bp, "FauxScrollFrameTemplate")
  gscroll:SetPoint("TOPLEFT", bp, "TOPLEFT", 2, -20)
  gscroll:SetPoint("BOTTOMRIGHT", bp, "BOTTOMRIGHT", -24, 4)
  gscroll:SetScript("OnVerticalScroll", function()
    FauxScrollFrame_OnVerticalScroll(GROUP_ROW_H, function() CB.RefreshGroup() end)
  end)
  CB.groupScroll = gscroll

  CB.botRows = {}
  local line
  for line = 1, GROUP_VISIBLE do
    local row = CreateFrame("Button", nil, bp)
    row:SetHeight(GROUP_ROW_H)
    row:SetPoint("TOPLEFT", gscroll, "TOPLEFT", 0, -(line - 1) * GROUP_ROW_H)
    row:SetPoint("RIGHT", gscroll, "RIGHT", 0, 0)
    row.roleIcon = row:CreateTexture(nil, "OVERLAY")
    row.roleIcon:SetWidth(12); row.roleIcon:SetHeight(12)
    row.roleIcon:SetPoint("LEFT", row, "LEFT", 1, 0)
    row.roleIcon:Hide()
    row.lvl = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    row.lvl:SetPoint("LEFT", row, "LEFT", 15, 0); row.lvl:SetWidth(22); row.lvl:SetJustifyH("LEFT")
    row.classIcon = row:CreateTexture(nil, "OVERLAY")
    row.classIcon:SetWidth(14); row.classIcon:SetHeight(14)
    row.classIcon:SetPoint("LEFT", row, "LEFT", 40, 0)
    row.classIcon:Hide()
    row.txt = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    row.txt:SetPoint("LEFT", row, "LEFT", 58, 0); row.txt:SetWidth(100); row.txt:SetJustifyH("LEFT")
    row.hl = row:CreateTexture(nil, "BACKGROUND")
    row.hl:SetAllPoints(row); row.hl:SetTexture(0.3, 0.5, 0.9, 0.3); row.hl:Hide()
    row:SetScript("OnClick", function()
      local name = row.unit and UnitName(row.unit)
      if not name then return end
      if IsShiftKeyDown() then
        if CB.selectedBots[name] then CB.selectedBots[name] = nil else CB.selectedBots[name] = true end
      else
        CB.selectedBots = {}
        CB.selectedBots[name] = true
      end
      CB.RefreshGroup()
    end)
    row:SetScript("OnDoubleClick", function()
      local name = row.unit and UnitName(row.unit)
      if not name then return end
      UninviteUnit(name)
      CB.selectedBots[name] = nil
      if CB.SetStatus then CB.SetStatus("removed " .. name .. " from group") end
      CB.RefreshGroup()
    end)
    row:Hide()
    CB.botRows[line] = row
  end
end

local function BuildPlaceholder(body, text)
  local fs = body:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  fs:SetPoint("TOP", body, "TOP", 0, -40)
  fs:SetWidth(400); fs:SetJustifyH("CENTER")
  fs:SetText(text)
end

function CB.BuildGroup()  -- name kept for Core/minimap compatibility
  if CB.win then return end

  local w = CreateFrame("Frame", "CleanBotTortoiseWindow", UIParent)
  w:SetWidth(580); w:SetHeight(432)
  w:SetBackdrop({ bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", tile = true, tileSize = 16,
    edgeSize = 16, insets = { left = 4, right = 4, top = 4, bottom = 4 } })
  w:SetPoint(CB.db.groupPoint, UIParent, CB.db.groupPoint, CB.db.groupX, CB.db.groupY)
  w:SetMovable(true); w:EnableMouse(true)
  w:RegisterForDrag("LeftButton")
  w:SetScript("OnDragStart", function() this:StartMoving() end)
  w:SetScript("OnDragStop", function()
    this:StopMovingOrSizing()
    local p, _, _, x, y = this:GetPoint()
    CB.db.groupPoint, CB.db.groupX, CB.db.groupY = p, x, y
  end)
  w:SetFrameStrata("DIALOG")
  w:Hide()

  local title = w:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  title:SetPoint("TOP", w, "TOP", 0, -12)
  title:SetText("CleanBotTortoise")

  local close = CreateFrame("Button", nil, w, "UIPanelCloseButton")
  close:SetPoint("TOPRIGHT", w, "TOPRIGHT", -4, -4)
  close:SetScript("OnClick", function() w:Hide() end)

  -- Tabs.
  CB.tabButton = {}
  CB.tabBody = {}
  local i
  for i = 1, table.getn(TABS) do
    local name = TABS[i]
    local tb = CreateFrame("Button", nil, w, "UIPanelButtonTemplate")
    tb:SetWidth(96); tb:SetHeight(22)
    tb:SetPoint("TOPLEFT", w, "TOPLEFT", 14 + (i - 1) * 100, -36)
    tb:SetText(name)
    tb:SetScript("OnClick", function() CB.SelectTab(name) end)
    CB.tabButton[name] = tb

    local body = CreateFrame("Frame", nil, w)
    body:SetPoint("TOPLEFT", w, "TOPLEFT", 14, -66)
    body:SetPoint("BOTTOMRIGHT", w, "BOTTOMRIGHT", -14, 12)
    body:Hide()
    CB.tabBody[name] = body
  end

  -- Each tab builds independently: a bug in one tab's builder must not stop
  -- this function short of `CB.win = w` below, or the whole window (every
  -- entry point: minimap menu, /cbv, Settings, Party Bot Roster) breaks.
  local function SafeBuild(label, fn)
    local ok, err = pcall(fn)
    if not ok then
      CB.Print("|cffff5555" .. label .. " tab failed to build: " .. tostring(err) .. "|r")
    end
  end

  SafeBuild("Group", function() BuildGroupBody(CB.tabBody["Group"]) end)
  SafeBuild("Manage", function()
    BuildPlaceholder(CB.tabBody["Manage"],
      "Group management (create/rename bot groups) - coming soon.\n" ..
      "|cff808080Requires a server-side change to bring offline bots online.|r")
  end)
  SafeBuild("Individual", function()
    BuildPlaceholder(CB.tabBody["Individual"],
      "Per-bot controls - coming soon.\nUse the Group tab's Role dropdown for now.\n" ..
      "|cff808080Requires a server-side change for inventory / quest management.|r")
  end)
  SafeBuild("Settings", function() CB.BuildSettings(CB.tabBody["Settings"]) end)

  -- Roster refresh events (only act while the Group tab is visible).
  w:RegisterEvent("PARTY_MEMBERS_CHANGED")
  w:RegisterEvent("RAID_ROSTER_UPDATE")
  w:RegisterEvent("WHO_LIST_UPDATE")
  w:SetScript("OnEvent", function()
    if event == "WHO_LIST_UPDATE" then CB.OnWhoUpdate() else CB.RefreshGroup() end
  end)
  w.elapsed = 0
  w:SetScript("OnUpdate", function()
    w.elapsed = w.elapsed + arg1
    if w.elapsed >= 0.5 then w.elapsed = 0; CB.RefreshGroup() end
  end)

  CB.selectedBots = {}
  CB.db.botRoles = CB.db.botRoles or {}
  CB.win = w
end

function CB.ToggleGroup()
  if not CB.win then CB.BuildGroup() end
  if CB.win:IsShown() then
    CB.win:Hide()
  else
    CB.win:Show()
    CB.SelectTab("Group")
  end
end
