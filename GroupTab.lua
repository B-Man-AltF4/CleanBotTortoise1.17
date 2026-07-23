--[[ GroupTab.lua - party/raid bot roster with per-bot role controls.
     Roster is read from the client party/raid API (no server command needed).
     Role buttons target the bot and send `.bot setrole <role>`.
     Vanilla 1.12 / Lua 5.0.
]]--

local CB = CleanBotV

-- setrole arguments - VERIFY in-game with `.bot setrole` and adjust if needed.
local ROLES = {
  { key = "tank",   short = "T", name = "Tank" },
  { key = "healer", short = "H", name = "Healer" },
  { key = "dps",    short = "D", name = "DPS" },
}

local ROW_H = 22
local MAX_ROWS = 20

-- All party/raid members except the player (treated as bots on a solo+bots setup).
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

local function ClassColor(unit)
  local _, class = UnitClass(unit)
  local c = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
  if c then return c.r, c.g, c.b end
  return 1, 1, 1
end

local function OnRoleClick()
  local unit = this.unit
  if not unit or not UnitExists(unit) then return end
  TargetUnit(unit)
  SendChatMessage(".bot setrole " .. this.role, "SAY")
  TargetLastTarget()
  if CB.SetStatus then CB.SetStatus("setrole " .. this.role .. " -> " .. (UnitName(unit) or "?")) end
end

local function OnRoleEnter()
  GameTooltip:SetOwner(this, "ANCHOR_RIGHT")
  GameTooltip:SetText("Set role: " .. this.roleName)
  GameTooltip:Show()
end
local function OnRoleLeave() GameTooltip:Hide() end

local function CreateRow(parent, index)
  local row = CreateFrame("Frame", nil, parent)
  row:SetWidth(228); row:SetHeight(ROW_H)
  row:SetPoint("TOPLEFT", parent, "TOPLEFT", 8, -28 - (index - 1) * ROW_H)

  row.name = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  row.name:SetPoint("LEFT", row, "LEFT", 2, 0)
  row.name:SetWidth(116); row.name:SetJustifyH("LEFT")

  row.hp = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  row.hp:SetPoint("LEFT", row, "LEFT", 120, 0)
  row.hp:SetWidth(34); row.hp:SetJustifyH("RIGHT")

  row.roleButtons = {}
  local j
  for j = 1, table.getn(ROLES) do
    local rb = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
    rb:SetWidth(20); rb:SetHeight(18)
    rb:SetPoint("LEFT", row, "LEFT", 162 + (j - 1) * 22, 0)
    rb:SetText(ROLES[j].short)
    rb.role = ROLES[j].key
    rb.roleName = ROLES[j].name
    rb:SetScript("OnClick", OnRoleClick)
    rb:SetScript("OnEnter", OnRoleEnter)
    rb:SetScript("OnLeave", OnRoleLeave)
    row.roleButtons[j] = rb
  end
  return row
end

function CB.UpdateGroup()
  if not CB.group or not CB.group:IsShown() then return end
  local units = BotUnits()
  local count = table.getn(units)

  local i
  for i = 1, MAX_ROWS do
    local row = CB.groupRows[i]
    if i <= count then
      if not row then row = CreateRow(CB.group, i); CB.groupRows[i] = row end
      local unit = units[i]
      row.unit = unit
      local r, g, b = ClassColor(unit)
      row.name:SetText((UnitName(unit) or "?") .. "  |cff808080L" .. (UnitLevel(unit) or "?") .. "|r")
      row.name:SetTextColor(r, g, b)
      local hp, hpmax = UnitHealth(unit), UnitHealthMax(unit)
      local pct = (hpmax and hpmax > 0) and math.floor(hp / hpmax * 100) or 0
      row.hp:SetText(pct .. "%")
      local j
      for j = 1, table.getn(row.roleButtons) do row.roleButtons[j].unit = unit end
      row:Show()
    elseif row then
      row:Hide()
    end
  end

  CB.groupEmpty:SetText(count == 0 and "No party bots in your group." or "")
  CB.group:SetHeight(34 + (count > 0 and count or 1) * ROW_H + 8)
end

function CB.ToggleGroup()
  if not CB.group then CB.BuildGroup() end
  if CB.group:IsShown() then
    CB.group:Hide()
  else
    CB.group:Show()
    CB.UpdateGroup()
  end
end

function CB.BuildGroup()
  if CB.group then return end

  local f = CreateFrame("Frame", "CleanBotVGroup", UIParent)
  f:SetWidth(244); f:SetHeight(80)
  f:SetBackdrop({
    bgFile   = "Interface\\DialogFrame\\UI-DialogBox-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true, tileSize = 16, edgeSize = 16,
    insets = { left = 4, right = 4, top = 4, bottom = 4 },
  })
  f:ClearAllPoints()
  f:SetPoint(CB.db.groupPoint, UIParent, CB.db.groupPoint, CB.db.groupX, CB.db.groupY)
  f:SetMovable(true); f:EnableMouse(true)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", function() this:StartMoving() end)
  f:SetScript("OnDragStop", function()
    this:StopMovingOrSizing()
    local p, _, _, x, y = this:GetPoint()
    CB.db.groupPoint, CB.db.groupX, CB.db.groupY = p, x, y
  end)
  f:Hide()

  local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  title:SetPoint("TOP", f, "TOP", 0, -10)
  title:SetText("Party Bot Roster")

  local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
  close:SetPoint("TOPRIGHT", f, "TOPRIGHT", -2, -2)
  close:SetScript("OnClick", function() f:Hide() end)

  local empty = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  empty:SetPoint("TOP", f, "TOP", 0, -34)
  empty:SetText("No party bots in your group.")
  CB.groupEmpty = empty

  CB.groupRows = {}

  -- Refresh on roster changes; throttle health updates while shown.
  f:RegisterEvent("PARTY_MEMBERS_CHANGED")
  f:RegisterEvent("RAID_ROSTER_UPDATE")
  f:SetScript("OnEvent", function() CB.UpdateGroup() end)
  f.elapsed = 0
  f:SetScript("OnUpdate", function()
    f.elapsed = f.elapsed + arg1
    if f.elapsed >= 0.5 then f.elapsed = 0; CB.UpdateGroup() end
  end)

  CB.group = f
end
