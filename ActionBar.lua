--[[ ActionBar.lua - compact, movable icon bar of the most-used .bot commands.
     Complements the full panel (UI.lua); both route through Bridge.lua.
     Vanilla 1.12 / Lua 5.0. Toggle with `/cbv bar`.
]]--

local CB = CleanBotV

local SIZE, GAP, PAD, GRIP = 28, 2, 5, 12

-- Icons are vanilla-safe paths; an unknown one just renders the default icon.
local BAR = {
  { cmd = "cometome",    tip = "Come to Me",     tex = "Interface\\Icons\\Spell_Nature_Swiftness" },
  { cmd = "attackstart", tip = "Attack target",  tex = "Interface\\Icons\\Ability_Warrior_Charge" },
  { cmd = "attackstop",  tip = "Stop attacking", tex = "Interface\\Icons\\Ability_Warrior_ShieldWall" },
  { cmd = "pull",        tip = "Pull target",    tex = "Interface\\Icons\\Ability_Marksmanship" },
  { cmd = "aoe",         tip = "AoE",            tex = "Interface\\Icons\\Spell_Nature_StarFall" },
  { cmd = "focusmark", mark = 8, tip = "Focus (Skull)", tex = "Interface\\Icons\\Ability_Hunter_AimedShot" },
  { cmd = "ccmark",    mark = 7, tip = "CC (Cross)",    tex = "Interface\\Icons\\Spell_Nature_Polymorph" },
  { clear = true,      tip = "Clear Marks",      tex = "Interface\\Buttons\\UI-GroupLoot-Pass-Up" },
  { cmd = "pause",       tip = "Pause",          tex = "Interface\\Icons\\INV_Misc_PocketWatch_01" },
  { cmd = "unpause",     tip = "Unpause",        tex = "Interface\\Icons\\Spell_Holy_Renew" },
  { cmd = "usegobject",  tip = "Use Object",     tex = "Interface\\Icons\\INV_Misc_Gear_01" },
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
  GameTooltip:SetOwner(this, "ANCHOR_TOP")
  GameTooltip:SetText(this.tip or "")
  GameTooltip:Show()
end

local function OnBarLeave()
  GameTooltip:Hide()
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
  local n = table.getn(BAR)
  local width = PAD + GRIP + n * (SIZE + GAP) + PAD
  local height = SIZE + PAD * 2

  local bar = CreateFrame("Frame", "CleanBotVBar", UIParent)
  bar:SetWidth(width); bar:SetHeight(height)
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

  -- Drag grip on the left edge.
  local grip = CreateFrame("Button", nil, bar)
  grip:SetWidth(GRIP); grip:SetHeight(SIZE)
  grip:SetPoint("LEFT", bar, "LEFT", PAD, 0)
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

  -- Icon buttons.
  local i
  for i = 1, n do
    local spec = BAR[i]
    local btn = CreateFrame("Button", nil, bar)
    btn:SetWidth(SIZE); btn:SetHeight(SIZE)
    btn:SetPoint("LEFT", bar, "LEFT", PAD + GRIP + (i - 1) * (SIZE + GAP), 0)
    btn:SetNormalTexture(spec.tex)
    btn:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    btn.barcmd = spec.cmd
    btn.mark = spec.mark
    btn.clear = spec.clear
    btn.tip = spec.tip
    btn:SetScript("OnClick", OnBarClick)
    btn:SetScript("OnEnter", OnBarEnter)
    btn:SetScript("OnLeave", OnBarLeave)
  end

  CB.bar = bar
  if CB.db.barShown then bar:Show() else bar:Hide() end
end
