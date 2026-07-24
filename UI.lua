--[[ UI.lua - party-bot command center panel + minimap button.
     A 2-column grid of `.bot` command buttons. Vanilla 1.12 / Lua 5.0.
     Every button routes through Bridge.lua (CB.Bot / CB.BotMark / CB.BotClearMarks).
]]--

local CB = CleanBotTortus

-- Button grid (first 10 fill two columns; #11 spans full width).
--   kind "cmd"        -> CB.Bot(arg)
--   kind "mark"       -> CB.BotMark(icon, arg)
--   kind "clearmarks" -> CB.BotClearMarks()
local BUTTONS = {
  { label = "Come to Me",  kind = "cmd",  arg = "cometome" },
  { label = "Use Object",  kind = "cmd",  arg = "usegobject" },
  { label = "Attack",      kind = "cmd",  arg = "attackstart" },
  { label = "Stop",        kind = "cmd",  arg = "attackstop" },
  { label = "Pull",        kind = "cmd",  arg = "pull" },
  { label = "AoE",         kind = "cmd",  arg = "aoe" },
  { label = "Pause",       kind = "cmd",  arg = "pause" },
  { label = "Unpause",     kind = "cmd",  arg = "unpause" },
  { label = "Focus",       kind = "mark", arg = "focusmark", icon = 8 }, -- Skull
  { label = "CC",          kind = "mark", arg = "ccmark",    icon = 7 }, -- Cross
  { label = "Clear Marks", kind = "clearmarks" },
}

function CB.SetStatus(text)
  if CB.statusText then CB.statusText:SetText(text or "") end
end

function CB.ToggleUI()
  if not CB.mainFrame then return end
  if CB.mainFrame:IsShown() then
    CB.mainFrame:Hide(); CB.db.shown = false
  else
    CB.mainFrame:Show(); CB.db.shown = true
  end
end

-- Shared click handler (reads fields off the button; avoids closure capture).
local function OnButtonClick()
  if this.kind == "mark" then
    CB.BotMark(this.icon, this.arg)
  elseif this.kind == "clearmarks" then
    CB.BotClearMarks()
  else
    CB.Bot(this.arg)
  end
end

-- Minimap dropdown menu (rebuilt each open, so checks reflect current state).
local function CleanBotTortusMenuInit()
  local info

  info = {}
  info.text = "CleanBotTortoise"; info.isTitle = 1; info.notCheckable = 1
  UIDropDownMenu_AddButton(info)

  info = {}
  info.text = "Show Action Bar"
  info.checked = CB.db.barShown
  info.func = function() CB.ToggleActionBar() end
  UIDropDownMenu_AddButton(info)

  info = {}
  info.text = "Show Command Panel"
  info.checked = CB.db.shown
  info.func = function() CB.ToggleUI() end
  UIDropDownMenu_AddButton(info)

  info = {}
  info.text = "Party Bot Roster"; info.notCheckable = 1
  info.func = function() CloseDropDownMenus(); CB.ToggleGroup() end
  UIDropDownMenu_AddButton(info)

  info = {}
  info.text = "Settings..."; info.notCheckable = 1
  info.func = function() CloseDropDownMenus(); CB.ToggleSettings() end
  UIDropDownMenu_AddButton(info)
end

local function BuildMinimapButton()
  if CB.minimapButton then return end

  local b = CreateFrame("Button", "CleanBotTortusMinimapButton", Minimap)
  b:SetWidth(31); b:SetHeight(31)
  b:SetFrameStrata("MEDIUM"); b:SetFrameLevel(8)

  local icon = b:CreateTexture(nil, "BACKGROUND")
  icon:SetWidth(20); icon:SetHeight(20)
  icon:SetTexture("Interface\\Icons\\INV_Misc_GroupLooking")
  icon:SetPoint("TOPLEFT", b, "TOPLEFT", 6, -6)

  local border = b:CreateTexture(nil, "OVERLAY")
  border:SetWidth(53); border:SetHeight(53)
  border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
  border:SetPoint("TOPLEFT", b, "TOPLEFT", 0, 0)

  local angle = math.rad(CB.db.minimapAngle or 200)
  b:SetPoint("CENTER", Minimap, "CENTER", 80 * math.cos(angle), 80 * math.sin(angle))

  if not CleanBotTortusMenu then
    local menu = CreateFrame("Frame", "CleanBotTortusMenu", UIParent, "UIDropDownMenuTemplate")
    UIDropDownMenu_Initialize(menu, CleanBotTortusMenuInit, "MENU")
  end

  b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  b:SetScript("OnClick", function()
    ToggleDropDownMenu(1, nil, CleanBotTortusMenu, "cursor", 0, 0)
  end)
  b:SetScript("OnEnter", function()
    GameTooltip:SetOwner(this, "ANCHOR_LEFT")
    GameTooltip:AddLine("CleanBotTortoise - Party Bots")
    GameTooltip:AddLine("Click for menu", 1, 1, 1)
    GameTooltip:Show()
  end)
  b:SetScript("OnLeave", function() GameTooltip:Hide() end)

  CB.minimapButton = b
end

function CB.BuildUI()
  if CB.mainFrame then return end

  local BW, BH, GAP, TOP = 102, 22, 6, -30
  local ROW = BH + GAP

  local f = CreateFrame("Frame", "CleanBotTortusFrame", UIParent)
  f:SetWidth(236); f:SetHeight(238)
  f:SetBackdrop({
    bgFile   = "Interface\\DialogFrame\\UI-DialogBox-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true, tileSize = 16, edgeSize = 16,
    insets = { left = 4, right = 4, top = 4, bottom = 4 },
  })
  f:ClearAllPoints()
  f:SetPoint(CB.db.point, UIParent, CB.db.point, CB.db.x, CB.db.y)
  f:SetMovable(true); f:EnableMouse(true)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", function() this:StartMoving() end)
  f:SetScript("OnDragStop", function()
    this:StopMovingOrSizing()
    local point, _, _, x, y = this:GetPoint()
    CB.db.point, CB.db.x, CB.db.y = point, x, y
  end)
  f:Hide()

  local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  title:SetPoint("TOP", f, "TOP", 0, -10)
  title:SetText("CleanBotTortoise - Party Bots")

  local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
  close:SetPoint("TOPRIGHT", f, "TOPRIGHT", -2, -2)
  close:SetScript("OnClick", function() CB.ToggleUI() end)

  -- First 10 buttons: two columns.
  for i = 1, 10 do
    local spec = BUTTONS[i]
    local btn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    btn:SetWidth(BW); btn:SetHeight(BH)
    local row = math.floor((i - 1) / 2)
    local odd = (math.floor(i / 2) * 2 ~= i)  -- i is odd -> left column
    if odd then
      btn:SetPoint("TOPLEFT", f, "TOPLEFT", 10, TOP - row * ROW)
    else
      btn:SetPoint("TOPRIGHT", f, "TOPRIGHT", -10, TOP - row * ROW)
    end
    btn:SetText(spec.label)
    btn.kind, btn.arg, btn.icon = spec.kind, spec.arg, spec.icon
    btn:SetScript("OnClick", OnButtonClick)
  end

  -- Clear Marks: full width, row 5.
  local cm = BUTTONS[11]
  local wide = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
  wide:SetWidth(BW * 2 + 6); wide:SetHeight(BH)
  wide:SetPoint("TOP", f, "TOP", 0, TOP - 5 * ROW)
  wide:SetText(cm.label)
  wide.kind = cm.kind
  wide:SetScript("OnClick", OnButtonClick)

  local status = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  status:SetPoint("BOTTOM", f, "BOTTOM", 0, 8)
  status:SetWidth(220)
  status:SetText("target an enemy, then command your bots")
  CB.statusText = status

  CB.mainFrame = f
  BuildMinimapButton()
end
