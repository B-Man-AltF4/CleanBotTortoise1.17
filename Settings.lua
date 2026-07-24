--[[ Settings.lua - right-click-minimap settings: bar orientation, show/hide,
     and in-addon keybinding (backed by Bindings.xml + SetBinding).
     Vanilla 1.12 / Lua 5.0.
]]--

local CB = CleanBotV

-- Friendly names for the Blizzard Key Bindings menu (built from CB.BAR).
BINDING_HEADER_CLEANBOTV = "CleanBot Turtle"
do
  local i
  for i = 1, table.getn(CB.BAR) do
    local s = CB.BAR[i]
    setglobal("BINDING_NAME_" .. s.bind, s.tip)
  end
end

local MODIFIER_KEYS = {
  LSHIFT = true, RSHIFT = true, LCTRL = true, RCTRL = true,
  LALT = true, RALT = true, UNKNOWN = true,
}

local function BuildCombo(key)
  local pre = ""
  if IsAltKeyDown() then pre = pre .. "ALT-" end
  if IsControlKeyDown() then pre = pre .. "CTRL-" end
  if IsShiftKeyDown() then pre = pre .. "SHIFT-" end
  return pre .. key
end

-- Update the per-row "current key" labels.
function CB.RefreshKeybinds()
  if not CB.keyRows then return end
  local i
  for i = 1, table.getn(CB.keyRows) do
    local row = CB.keyRows[i]
    local key = GetBindingKey(row.bind)
    row.keyText:SetText(key or "|cff808080unbound|r")
  end
end

local function ClearBinding(bind)
  local key = GetBindingKey(bind)
  while key do
    SetBinding(key)  -- one arg unbinds that key
    key = GetBindingKey(bind)
  end
  SaveBindings(GetCurrentBindingSet())
end

function CB.ToggleSettings()
  if not CB.settings then CB.BuildSettings() end
  if CB.settings:IsShown() then
    CB.settings:Hide()
  else
    CB.RefreshKeybinds()
    CB.settings:Show()
  end
end

function CB.BuildSettings()
  if CB.settings then return end

  local f = CreateFrame("Frame", "CleanBotVSettings", UIParent)
  f:SetWidth(300); f:SetHeight(380)
  f:SetBackdrop({
    bgFile   = "Interface\\DialogFrame\\UI-DialogBox-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true, tileSize = 16, edgeSize = 16,
    insets = { left = 4, right = 4, top = 4, bottom = 4 },
  })
  f:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
  f:SetMovable(true); f:EnableMouse(true)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", function() this:StartMoving() end)
  f:SetScript("OnDragStop", function() this:StopMovingOrSizing() end)
  f:SetFrameStrata("DIALOG")
  f:Hide()

  local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  title:SetPoint("TOP", f, "TOP", 0, -12)
  title:SetText("CleanBot Turtle Settings")

  local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
  close:SetPoint("TOPRIGHT", f, "TOPRIGHT", -3, -3)
  close:SetScript("OnClick", function() f:Hide() end)

  -- Orientation toggle.
  local orient = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
  orient:SetWidth(200); orient:SetHeight(22)
  orient:SetPoint("TOP", f, "TOP", 0, -34)
  local function UpdateOrient()
    local o = (CB.db.barOrient == "VERTICAL") and "Vertical" or "Horizontal"
    orient:SetText("Bar Orientation: " .. o)
  end
  orient:SetScript("OnClick", function()
    CB.SetBarOrientation((CB.db.barOrient == "VERTICAL") and "HORIZONTAL" or "VERTICAL")
    UpdateOrient()
  end)
  UpdateOrient()

  -- Show Action Bar / Show Panel checkboxes.
  local function MakeCheck(y, label, getf, setf)
    local c = CreateFrame("CheckButton", nil, f, "UICheckButtonTemplate")
    c:SetWidth(22); c:SetHeight(22)
    c:SetPoint("TOPLEFT", f, "TOPLEFT", 16, y)
    c:SetChecked(getf())
    c:SetScript("OnClick", function() setf(this:GetChecked()) end)
    local t = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    t:SetPoint("LEFT", c, "RIGHT", 2, 0)
    t:SetText(label)
    return c
  end

  MakeCheck(-64, "Show Action Bar",
    function() return CB.db.barShown end,
    function(v) if v then CB.bar:Show() else CB.bar:Hide() end; CB.db.barShown = v end)

  MakeCheck(-88, "Show Command Panel",
    function() return CB.db.shown end,
    function(v)
      if CB.mainFrame then if v then CB.mainFrame:Show() else CB.mainFrame:Hide() end end
      CB.db.shown = v
    end)

  -- Keybind section.
  local kbTitle = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  kbTitle:SetPoint("TOPLEFT", f, "TOPLEFT", 16, -116)
  kbTitle:SetText("Keybinds  (right-click Set to clear)")

  CB.keyRows = {}
  local n = table.getn(CB.BAR)
  local i
  for i = 1, n do
    local spec = CB.BAR[i]
    local y = -134 - (i - 1) * 20

    local label = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    label:SetPoint("TOPLEFT", f, "TOPLEFT", 18, y)
    label:SetWidth(110); label:SetJustifyH("LEFT")
    label:SetText(spec.tip)

    local keyText = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    keyText:SetPoint("TOPLEFT", f, "TOPLEFT", 130, y)
    keyText:SetWidth(90); keyText:SetJustifyH("LEFT")

    local set = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    set:SetWidth(48); set:SetHeight(16)
    set:SetPoint("TOPRIGHT", f, "TOPRIGHT", -14, y + 2)
    set:SetText("Set")
    set.bind = spec.bind
    set.label = spec.tip
    set:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    set:SetScript("OnClick", function()
      if arg1 == "RightButton" then
        ClearBinding(this.bind)
        CB.RefreshKeybinds()
      else
        CB.keyCapture.bind = this.bind
        CB.keyPrompt:SetText("Press a key for:\n" .. this.label .. "\n\n(Esc to cancel)")
        CB.keyCapture:Show()
      end
    end)

    CB.keyRows[i] = { bind = spec.bind, keyText = keyText }
  end

  -- Fullscreen key-capture overlay.
  local cap = CreateFrame("Frame", "CleanBotVKeyCapture", UIParent)
  cap:SetAllPoints(UIParent)
  cap:SetFrameStrata("FULLSCREEN_DIALOG")
  cap:EnableKeyboard(true); cap:EnableMouse(true)
  cap:Hide()
  local bg = cap:CreateTexture(nil, "BACKGROUND")
  bg:SetAllPoints(cap); bg:SetTexture(0, 0, 0, 0.5)
  local prompt = cap:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  prompt:SetPoint("CENTER", cap, "CENTER", 0, 0)
  cap:SetScript("OnKeyDown", function()
    local key = arg1
    if key == "ESCAPE" then cap:Hide(); return end
    if MODIFIER_KEYS[key] then return end
    SetBinding(BuildCombo(key), cap.bind)
    SaveBindings(GetCurrentBindingSet())
    cap:Hide()
    CB.RefreshKeybinds()
  end)
  CB.keyCapture = cap
  CB.keyPrompt = prompt

  CB.settings = f
  CB.RefreshKeybinds()
end
