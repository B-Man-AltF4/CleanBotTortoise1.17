--[[ GroupTab.lua - CleanBot-style tabbed window.
     Tabs: Manage | Individual | Group | Settings. The Group tab is a 3-pane
     layout (class filters . bot list . controls) wired to the real `.bot`
     commands only (no strategies - this server doesn't have them).
     Vanilla 1.12 / Lua 5.0.
]]--

local CB = CleanBotV

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

function CB.SetBotRole(unit, role)
  if not unit or not UnitExists(unit) then
    CB.Print("|cffff5555Select a bot first.|r")
    return
  end
  TargetUnit(unit)
  SendChatMessage(".bot setrole " .. role, "SAY")
  TargetLastTarget()
  CB.db.botRoles = CB.db.botRoles or {}
  CB.db.botRoles[UnitName(unit)] = role
  if CB.SetStatus then CB.SetStatus("setrole " .. role .. " -> " .. (UnitName(unit) or "?")) end
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
end

--------------------------------------------------------------------------------
-- Group tab refresh (filters + bot list + header)
--------------------------------------------------------------------------------

function CB.RefreshGroup()
  if not CB.win or not CB.win:IsShown() or CB.activeTab ~= "Group" then return end
  local units = BotUnits()

  -- Party bot list: all bots, sorted by level.
  local i
  local list = {}
  for i = 1, table.getn(units) do
    table.insert(list, units[i])
  end
  table.sort(list, function(a, b) return (UnitLevel(a) or 0) < (UnitLevel(b) or 0) end)

  for i = 1, table.getn(CB.botRows) do CB.botRows[i]:Hide() end
  for i = 1, table.getn(list) do
    local unit = list[i]
    local _, cls = UnitClass(unit)
    local row = CB.botRows[i]
    if not row then
      row = CreateFrame("Button", nil, CB.botPane)
      row:SetWidth(172); row:SetHeight(18)
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
      row.txt:SetPoint("LEFT", row, "LEFT", 58, 0); row.txt:SetWidth(110); row.txt:SetJustifyH("LEFT")
      row.hl = row:CreateTexture(nil, "BACKGROUND")
      row.hl:SetAllPoints(row); row.hl:SetTexture(0.3, 0.5, 0.9, 0.3); row.hl:Hide()
      row:SetScript("OnClick", function()
        CB.selectedBotUnit = row.unit
        CB.RefreshGroup()
      end)
      CB.botRows[i] = row
    end
    row:ClearAllPoints()
    row:SetPoint("TOPLEFT", CB.botPane, "TOPLEFT", 2, -20 - (i - 1) * 18)
    row.unit = unit
    local r, g, b = ClassColor(cls)
    row.lvl:SetText("|cffffd200" .. (UnitLevel(unit) or "?") .. "|r")
    row.txt:SetText(UnitName(unit) or "?")
    row.txt:SetTextColor(r, g, b)
    local role = CB.db.botRoles and CB.db.botRoles[UnitName(unit)]
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
    if CB.selectedBotUnit == unit then row.hl:Show() else row.hl:Hide() end
    row:Show()
  end

  CB.groupHeader:SetText("Managing: " .. table.getn(units) .. " bot" .. (table.getn(units) == 1 and "" or "s"))
  local selName = CB.selectedBotUnit and UnitExists(CB.selectedBotUnit) and UnitName(CB.selectedBotUnit)
  CB.groupSelected:SetText(selName and ("Selected: " .. selName) or "Selected: (none - click a bot)")

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
      CB.SetBotRole(CB.selectedBotUnit, roleKey)
    end
    UIDropDownMenu_AddButton(info)
  end
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

  local scroll = CreateFrame("ScrollFrame", "CleanBotVAvailScroll", ap, "FauxScrollFrameTemplate")
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

  local drop = CreateFrame("Frame", "CleanBotVRoleDrop", body, "UIDropDownMenuTemplate")
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

  -- Right: your Group / Raid bots (Lvl | Class | Name).
  local grx = 368
  local grLabel = body:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  grLabel:SetPoint("TOPLEFT", body, "TOPLEFT", grx + 2, -2)
  grLabel:SetText("Group / Raid")

  local bp = CreateFrame("Frame", nil, body)
  bp:SetWidth(184); bp:SetHeight(334)
  bp:SetPoint("TOPLEFT", body, "TOPLEFT", grx, -20)
  bp:SetBackdrop(BD); bp:SetBackdropColor(0, 0, 0, 0.4)
  CB.botPane = bp
  CB.botRows = {}

  local hLvl = bp:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  hLvl:SetPoint("TOPLEFT", bp, "TOPLEFT", 15, -4); hLvl:SetText("|cffffffffLvl|r")
  local hClass = bp:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  hClass:SetPoint("TOPLEFT", bp, "TOPLEFT", 38, -4); hClass:SetText("|cffffffffCls|r")
  local hName = bp:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  hName:SetPoint("TOPLEFT", bp, "TOPLEFT", 58, -4); hName:SetText("|cffffffffName|r")
end

local function BuildPlaceholder(body, text)
  local fs = body:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  fs:SetPoint("TOP", body, "TOP", 0, -40)
  fs:SetWidth(400); fs:SetJustifyH("CENTER")
  fs:SetText(text)
end

function CB.BuildGroup()  -- name kept for Core/minimap compatibility
  if CB.win then return end

  local w = CreateFrame("Frame", "CleanBotVWindow", UIParent)
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
  title:SetText("CleanBot")

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

  BuildGroupBody(CB.tabBody["Group"])
  BuildPlaceholder(CB.tabBody["Manage"], "Group management (create/rename bot groups) - coming soon.")
  BuildPlaceholder(CB.tabBody["Individual"], "Per-bot controls - coming soon.\nUse the Group tab's Role dropdown for now.")
  do
    local sbody = CB.tabBody["Settings"]
    BuildPlaceholder(sbody, "Bar orientation, show toggles and keybinds\nare in the standalone Settings window.")
    local ob = CreateFrame("Button", nil, sbody, "UIPanelButtonTemplate")
    ob:SetWidth(160); ob:SetHeight(24)
    ob:SetPoint("TOP", sbody, "TOP", 0, -90)
    ob:SetText("Open Settings")
    ob:SetScript("OnClick", function() CB.ToggleSettings() end)
  end

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

  CB.groupFilter = "All"
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
