--[[ ActionBar.lua - compact, movable icon bar of the most-used .bot commands.
     Horizontal or vertical (Settings). The command list CB.BAR is shared with
     Settings.lua (keybind rows) and Bindings.xml (named bindings).
     Vanilla 1.12 / Lua 5.0.
]]--

local CB = CleanBotTortus

local SIZE, GAP, PAD, GRIP = 28, 2, 5, 12

-- Single source of truth for the command set (bar icons + keybind rows).
CB.BAR = {
  { cmd = "cometome",    tip = "Come to Me",     tex = "Interface\\Icons\\Spell_Nature_Swiftness",     bind = "CLEANBOTTORTUS_COMETOME" },
  { cmd = "attackstart", tip = "Attack target",  tex = "Interface\\Icons\\Ability_Warrior_Charge",     bind = "CLEANBOTTORTUS_ATTACK" },
  { cmd = "attackstop",  tip = "Stop attacking", tex = "Interface\\Icons\\Ability_Warrior_ShieldWall", bind = "CLEANBOTTORTUS_STOP" },
  { cmd = "pull",        tip = "Pull target",    tex = "Interface\\Icons\\Ability_Marksmanship",       bind = "CLEANBOTTORTUS_PULL" },
  { cmd = "aoe",         tip = "AoE",            tex = "Interface\\Icons\\Spell_Nature_StarFall",      bind = "CLEANBOTTORTUS_AOE" },
  { cmd = "focusmark", mark = 8, tip = "Focus (Skull)", tex = "Interface\\Icons\\Ability_Hunter_AimedShot", bind = "CLEANBOTTORTUS_FOCUS" },
  { cmd = "ccmark",    mark = 7, tip = "CC (Cross)",    tex = "Interface\\Icons\\Spell_Nature_Polymorph",   bind = "CLEANBOTTORTUS_CC" },
  { clear = true,      tip = "Clear Marks",     tex = "Interface\\Buttons\\UI-GroupLoot-Pass-Up",     bind = "CLEANBOTTORTUS_CLEARMARKS" },
  { cmd = "pause",       tip = "Pause",          tex = "Interface\\Icons\\INV_Misc_PocketWatch_01",    bind = "CLEANBOTTORTUS_PAUSE" },
  { cmd = "unpause",     tip = "Unpause",        tex = "Interface\\Icons\\Spell_Holy_Renew",           bind = "CLEANBOTTORTUS_UNPAUSE" },
  { cmd = "usegobject",  tip = "Use Object",     tex = "Interface\\Icons\\INV_Misc_Gear_01",           bind = "CLEANBOTTORTUS_USEOBJECT" },
}

local function OnBarClick()
  if this.mark then
    CB.BotMark(this.mark, this.barcmd)
  elseif this.clear then
    CB.BotClearMarks()
  else
    CB.Bot(this.barcmd)
  end
end

local function OnBarEnter()
  GameTooltip:SetOwner(this, "ANCHOR_RIGHT")
  GameTooltip:SetText(this.tip or "")
  if this.bind then
    local key = GetBindingKey(this.bind)
    if key then GameTooltip:AddLine("Key: " .. key, 0.6, 0.8, 1) end
  end
  GameTooltip:Show()
end

local function OnBarLeave()
  GameTooltip:Hide()
end

-- Position the grip + buttons and size the frame for the current orientation.
function CB.LayoutBar()
  local bar = CB.bar
  if not bar then return end
  local vertical = (CB.db.barOrient == "VERTICAL")
  local n = table.getn(CB.barButtons)
  local span = PAD + GRIP + n * (SIZE + GAP) + PAD

  CB.barGrip:ClearAllPoints()
  if vertical then
    bar:SetWidth(SIZE + PAD * 2)
    bar:SetHeight(span)
    CB.barGrip:SetWidth(SIZE); CB.barGrip:SetHeight(GRIP)
    CB.barGrip:SetPoint("TOP", bar, "TOP", 0, -PAD)
    for i = 1, n do
      CB.barButtons[i]:ClearAllPoints()
      CB.barButtons[i]:SetPoint("TOP", bar, "TOP", 0, -(PAD + GRIP + (i - 1) * (SIZE + GAP)))
    end
  else
    bar:SetWidth(span)
    bar:SetHeight(SIZE + PAD * 2)
    CB.barGrip:SetWidth(GRIP); CB.barGrip:SetHeight(SIZE)
    CB.barGrip:SetPoint("LEFT", bar, "LEFT", PAD, 0)
    for i = 1, n do
      CB.barButtons[i]:ClearAllPoints()
      CB.barButtons[i]:SetPoint("LEFT", bar, "LEFT", PAD + GRIP + (i - 1) * (SIZE + GAP), 0)
    end
  end
end

function CB.SetBarOrientation(orient)
  CB.db.barOrient = orient
  CB.LayoutBar()
end

function CB.ToggleActionBar()
  if not CB.bar then return end
  if CB.bar:IsShown() then
    CB.bar:Hide(); CB.db.barShown = false
  else
    CB.bar:Show(); CB.db.barShown = true
  end
end

function CB.BuildActionBar()
  if CB.bar then return end

  local bar = CreateFrame("Frame", "CleanBotTortusBar", UIParent)
  bar:SetBackdrop({
    bgFile   = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true, tileSize = 16, edgeSize = 12,
    insets = { left = 3, right = 3, top = 3, bottom = 3 },
  })
  bar:SetBackdropColor(0, 0, 0, 0.6)
  bar:ClearAllPoints()
  bar:SetPoint(CB.db.barPoint, UIParent, CB.db.barPoint, CB.db.barX, CB.db.barY)
  bar:SetMovable(true); bar:EnableMouse(true)

  local grip = CreateFrame("Button", nil, bar)
  local gt = grip:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  gt:SetPoint("CENTER", grip, "CENTER", 0, 0)
  gt:SetText("|cff999999::|r")
  grip:RegisterForDrag("LeftButton")
  grip:SetScript("OnDragStart", function() bar:StartMoving() end)
  grip:SetScript("OnDragStop", function()
    bar:StopMovingOrSizing()
    local p, _, _, x, y = bar:GetPoint()
    CB.db.barPoint, CB.db.barX, CB.db.barY = p, x, y
  end)
  CB.barGrip = grip

  CB.barButtons = {}
  for i = 1, table.getn(CB.BAR) do
    local spec = CB.BAR[i]
    local btn = CreateFrame("Button", "CleanBotTortusBarButton" .. i, bar)
    btn:SetWidth(SIZE); btn:SetHeight(SIZE)
    btn:SetNormalTexture(spec.tex)
    btn:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    btn.barcmd = spec.cmd
    btn.mark = spec.mark
    btn.clear = spec.clear
    btn.tip = spec.tip
    btn.bind = spec.bind
    btn:SetScript("OnClick", OnBarClick)
    btn:SetScript("OnEnter", OnBarEnter)
    btn:SetScript("OnLeave", OnBarLeave)
    CB.barButtons[i] = btn
  end

  CB.bar = bar
  CB.LayoutBar()
  if CB.db.barShown then bar:Show() else bar:Hide() end
end
