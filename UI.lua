--[[ UI.lua - main panel, command buttons, and minimap button.
     Phase 1 MVP: a draggable panel of core commands that route through
     CB.SendCommand (Bridge.lua). Vanilla 1.12 / Lua 5.0.
]]--

local CB = CleanBotV

-- Command token -> button label. Tokens verified present in mangosd.exe;
-- confirm exact syntax in-game with a `help` whisper (see PLAN.md TODO).
local COMMAND_ORDER = { "follow", "stay", "attack", "flee", "guard", "summon", "reset" }
local COMMAND_LABEL = {
  follow = "Follow",
  stay   = "Stay",
  attack = "Attack",
  flee   = "Flee",
  guard  = "Guard",
  summon = "Summon",
  reset  = "Reset AI",
}

function CB.SetStatus(text)
  if CB.statusText then CB.statusText:SetText(text or "") end
end

function CB.ToggleUI()
  if not CB.mainFrame then return end
  if CB.mainFrame:IsShown() then
    CB.mainFrame:Hide()
    CB.db.shown = false
  else
    CB.mainFrame:Show()
    CB.db.shown = true
  end
end

local function BuildMinimapButton()
  if CB.minimapButton then return end

  local b = CreateFrame("Button", "CleanBotVMinimapButton", Minimap)
  b:SetWidth(31); b:SetHeight(31)
  b:SetFrameStrata("MEDIUM")
  b:SetFrameLevel(8)

  local icon = b:CreateTexture(nil, "BACKGROUND")
  icon:SetWidth(20); icon:SetHeight(20)
  icon:SetTexture("Interface\\Icons\\INV_Misc_GroupLooking")
  icon:SetPoint("TOPLEFT", b, "TOPLEFT", 6, -6)

  local border = b:CreateTexture(nil, "OVERLAY")
  border:SetWidth(53); border:SetHeight(53)
  border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
  border:SetPoint("TOPLEFT", b, "TOPLEFT", 0, 0)

  -- Park it on the minimap ring at the saved angle.
  local angle = math.rad(CB.db.minimapAngle or 200)
  b:SetPoint("CENTER", Minimap, "CENTER", 80 * math.cos(angle), 80 * math.sin(angle))

  b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  b:SetScript("OnClick", function() CB.ToggleUI() end)
  b:SetScript("OnEnter", function()
    GameTooltip:SetOwner(this, "ANCHOR_LEFT")
    GameTooltip:AddLine("CleanBot Vanilla")
    GameTooltip:AddLine("Click to toggle the panel.", 1, 1, 1)
    GameTooltip:Show()
  end)
  b:SetScript("OnLeave", function() GameTooltip:Hide() end)

  CB.minimapButton = b
end

function CB.BuildUI()
  if CB.mainFrame then return end

  local f = CreateFrame("Frame", "CleanBotVFrame", UIParent)
  f:SetWidth(200); f:SetHeight(246)
  f:SetBackdrop({
    bgFile   = "Interface\\DialogFrame\\UI-DialogBox-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true, tileSize = 16, edgeSize = 16,
    insets = { left = 4, right = 4, top = 4, bottom = 4 },
  })
  f:ClearAllPoints()
  f:SetPoint(CB.db.point, UIParent, CB.db.point, CB.db.x, CB.db.y)

  f:SetMovable(true)
  f:EnableMouse(true)
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
  title:SetText("CleanBot Vanilla")

  local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
  close:SetPoint("TOPRIGHT", f, "TOPRIGHT", -2, -2)
  close:SetScript("OnClick", function() CB.ToggleUI() end)

  -- Command buttons.
  local i
  for i = 1, table.getn(COMMAND_ORDER) do
    local cmd = COMMAND_ORDER[i]
    local btn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    btn:SetWidth(170); btn:SetHeight(22)
    btn:SetPoint("TOP", f, "TOP", 0, -30 - (i - 1) * 25)
    btn:SetText(COMMAND_LABEL[cmd] or cmd)
    btn.cmd = cmd
    btn:SetScript("OnClick", function() CB.SendCommand(this.cmd) end)
  end

  local status = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  status:SetPoint("BOTTOM", f, "BOTTOM", 0, 10)
  status:SetWidth(184)
  status:SetText("target a bot, or join a party")
  CB.statusText = status

  CB.mainFrame = f
  BuildMinimapButton()
end
