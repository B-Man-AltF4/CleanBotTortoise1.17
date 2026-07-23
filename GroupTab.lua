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

local function DoAction(spec)
  if spec.kind == "mark" then CB.BotMark(spec.icon, spec.arg)
  elseif spec.kind == "clear" then CB.BotClearMarks()
  else CB.Bot(spec.arg) end
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
  if name == "Group" then CB.RefreshGroup() end
end

--------------------------------------------------------------------------------
-- Group tab refresh (filters + bot list + header)
--------------------------------------------------------------------------------

function CB.RefreshGroup()
  if not CB.win or not CB.win:IsShown() or CB.activeTab ~= "Group" then return end
  local units = BotUnits()

  -- Which classes are present (for the left filter list).
  local present = {}
  local i
  for i = 1, table.getn(units) do
    local _, cls = UnitClass(units[i])
    if cls then present[cls] = true end
  end

  -- Left filter buttons: "All" + present classes.
  local filters = { { key = "All", label = "All", r = 1, g = 1, b = 1 } }
  for i = 1, table.getn(CLASS_ORDER) do
    local cls = CLASS_ORDER[i]
    if present[cls] then
      local r, g, b = ClassColor(cls)
      table.insert(filters, { key = cls, label = CLASS_NAME[cls], r = r, g = g, b = b })
    end
  end
  for i = 1, table.getn(CB.filterButtons) do CB.filterButtons[i]:Hide() end
  for i = 1, table.getn(filters) do
    local fb = CB.filterButtons[i]
    if not fb then
      fb = CreateFrame("Button", nil, CB.filterPane)
      fb:SetWidth(120); fb:SetHeight(18)
      fb:SetPoint("TOPLEFT", CB.filterPane, "TOPLEFT", 4, -4 - (i - 1) * 19)
      fb.txt = fb:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
      fb.txt:SetPoint("LEFT", fb, "LEFT", 2, 0)
      fb:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
      fb:SetScript("OnClick", function() CB.groupFilter = fb.filterKey; CB.RefreshGroup() end)
      CB.filterButtons[i] = fb
    end
    fb.filterKey = filters[i].key
    fb.txt:SetText(filters[i].label)
    fb.txt:SetTextColor(filters[i].r, filters[i].g, filters[i].b)
    if CB.groupFilter == filters[i].key then fb.txt:SetText("> " .. filters[i].label) end
    fb:Show()
  end

  -- Middle bot list, filtered.
  for i = 1, table.getn(CB.botRows) do CB.botRows[i]:Hide() end
  local shown = 0
  for i = 1, table.getn(units) do
    local unit = units[i]
    local _, cls = UnitClass(unit)
    if CB.groupFilter == "All" or CB.groupFilter == cls then
      shown = shown + 1
      local row = CB.botRows[shown]
      if not row then
        row = CreateFrame("Button", nil, CB.botPane)
        row:SetWidth(150); row:SetHeight(18)
        row:SetPoint("TOPLEFT", CB.botPane, "TOPLEFT", 2, -2 - (shown - 1) * 18)
        row.roleIcon = row:CreateTexture(nil, "OVERLAY")
        row.roleIcon:SetWidth(14); row.roleIcon:SetHeight(14)
        row.roleIcon:SetPoint("LEFT", row, "LEFT", 3, 0)
        row.roleIcon:Hide()
        row.txt = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        row.txt:SetPoint("LEFT", row, "LEFT", 20, 0)
        row.txt:SetWidth(108); row.txt:SetJustifyH("LEFT")
        row.hl = row:CreateTexture(nil, "BACKGROUND")
        row.hl:SetAllPoints(row); row.hl:SetTexture(0.3, 0.5, 0.9, 0.3); row.hl:Hide()
        row:SetScript("OnClick", function()
          CB.selectedBotUnit = row.unit
          CB.RefreshGroup()
        end)
        CB.botRows[shown] = row
      end
      row:ClearAllPoints()
      row:SetPoint("TOPLEFT", CB.botPane, "TOPLEFT", 2, -2 - (shown - 1) * 18)
      row.unit = unit
      local r, g, b = ClassColor(cls)
      row.txt:SetText((UnitName(unit) or "?") .. " |cff808080L" .. (UnitLevel(unit) or "?") .. "|r")
      row.txt:SetTextColor(r, g, b)
      local role = CB.db.botRoles and CB.db.botRoles[UnitName(unit)]
      if role and ROLE_ICON[role] then
        row.roleIcon:SetTexture(ROLE_ICON[role]); row.roleIcon:Show()
      else
        row.roleIcon:Hide()
      end
      if CB.selectedBotUnit == unit then row.hl:Show() else row.hl:Hide() end
      row:Show()
    end
  end

  CB.groupHeader:SetText("Managing: " .. table.getn(units) .. " bot" .. (table.getn(units) == 1 and "" or "s"))
  local selName = CB.selectedBotUnit and UnitExists(CB.selectedBotUnit) and UnitName(CB.selectedBotUnit)
  CB.groupSelected:SetText(selName and ("Selected: " .. selName) or "Selected: (none - click a bot)")
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
  -- Left: class filter pane.
  local fp = CreateFrame("Frame", nil, body)
  fp:SetWidth(128); fp:SetHeight(356)
  fp:SetPoint("TOPLEFT", body, "TOPLEFT", 0, 0)
  fp:SetBackdrop({ bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", tile = true, tileSize = 16,
    edgeSize = 12, insets = { left = 3, right = 3, top = 3, bottom = 3 } })
  fp:SetBackdropColor(0, 0, 0, 0.4)
  CB.filterPane = fp
  CB.filterButtons = {}

  -- Middle: bot list pane.
  local bp = CreateFrame("Frame", nil, body)
  bp:SetWidth(158); bp:SetHeight(356)
  bp:SetPoint("TOPLEFT", body, "TOPLEFT", 136, 0)
  bp:SetBackdrop({ bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", tile = true, tileSize = 16,
    edgeSize = 12, insets = { left = 3, right = 3, top = 3, bottom = 3 } })
  bp:SetBackdropColor(0, 0, 0, 0.4)
  CB.botPane = bp
  CB.botRows = {}

  -- Right: controls.
  local rx = 304
  CB.groupHeader = body:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  CB.groupHeader:SetPoint("TOPLEFT", body, "TOPLEFT", rx, -2)
  CB.groupHeader:SetText("Managing: 0 bots")

  CB.groupSelected = body:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  CB.groupSelected:SetPoint("TOPLEFT", body, "TOPLEFT", rx, -22)
  CB.groupSelected:SetText("Selected: (none)")

  local roleLabel = body:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  roleLabel:SetPoint("TOPLEFT", body, "TOPLEFT", rx, -46)
  roleLabel:SetText("Role (selected bot):")

  local drop = CreateFrame("Frame", "CleanBotVRoleDrop", body, "UIDropDownMenuTemplate")
  drop:SetPoint("TOPLEFT", body, "TOPLEFT", rx - 12, -60)
  UIDropDownMenu_Initialize(drop, RoleDropInit)
  UIDropDownMenu_SetWidth(120, drop)
  UIDropDownMenu_SetText("Set Role...", drop)
  CB.roleDrop = drop

  local actLabel = body:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  actLabel:SetPoint("TOPLEFT", body, "TOPLEFT", rx, -100)
  actLabel:SetText("Actions (all party bots):")

  local i
  for i = 1, table.getn(ACTIONS) do
    local spec = ACTIONS[i]
    local btn = CreateFrame("Button", nil, body, "UIPanelButtonTemplate")
    btn:SetWidth(120); btn:SetHeight(22)
    local col = math.mod and math.mod(i - 1, 2) or ((i - 1) - math.floor((i - 1) / 2) * 2)
    local row = math.floor((i - 1) / 2)
    btn:SetPoint("TOPLEFT", body, "TOPLEFT", rx + col * 126, -118 - row * 26)
    btn:SetText(spec.label)
    btn:SetScript("OnClick", function() DoAction(spec) end)
  end

  local note = body:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  note:SetPoint("BOTTOMLEFT", body, "BOTTOMLEFT", rx, 6)
  note:SetWidth(250); note:SetJustifyH("LEFT")
  note:SetText("This server has no strategy/movement commands, so only the actions above are available.")
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
  w:SetScript("OnEvent", function() CB.RefreshGroup() end)
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
