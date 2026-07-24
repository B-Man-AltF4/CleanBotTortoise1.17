--[[ Settings.lua - right-click-minimap settings: bar orientation, show/hide,
     and in-addon keybinding (backed by Bindings.xml + SetBinding).
     Vanilla 1.12 / Lua 5.0.
]]--

local CB = CleanBotTortus

-- Friendly names for the Blizzard Key Bindings menu (built from CB.BAR).
BINDING_HEADER_CLEANBOTTORTUS = "CleanBotTortoise"
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

-- Opens the main window and switches it to the Settings tab (the settings
-- controls live inline there now; see CB.BuildSettings below).
function CB.ToggleSettings()
  if not CB.win then CB.BuildGroup() end
  CB.win:Show()
  CB.db.shown = true
  CB.SelectTab("Settings")
end

-- Builds the settings controls (orientation, show toggles, keybinds) directly
-- into `parent`, which is the Settings tab body created in GroupTab.lua.
function CB.BuildSettings(parent)
  if CB.settingsBuilt then return end
  CB.settingsBuilt = true

  local f = parent

  -- Orientation toggle.
  local orient = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
  orient:SetWidth(200); orient:SetHeight(22)
  orient:SetPoint("TOP", f, "TOP", 0, -6)
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

  MakeCheck(-36, "Show Action Bar",
    function() return CB.db.barShown end,
    function(v) if v then CB.bar:Show() else CB.bar:Hide() end; CB.db.barShown = v end)

  MakeCheck(-60, "Show Command Panel",
    function() return CB.db.shown end,
    function(v)
      if CB.mainFrame then if v then CB.mainFrame:Show() else CB.mainFrame:Hide() end end
      CB.db.shown = v
    end)

  -- Keybind section.
  local kbTitle = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  kbTitle:SetPoint("TOPLEFT", f, "TOPLEFT", 16, -88)
  kbTitle:SetText("Keybinds  (right-click Set to clear)")

  CB.keyRows = {}
  local n = table.getn(CB.BAR)
  local i
  for i = 1, n do
    local spec = CB.BAR[i]
    local y = -106 - (i - 1) * 20

    local label = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    label:SetPoint("TOPLEFT", f, "TOPLEFT", 18, y)
    label:SetWidth(110); label:SetJustifyH("LEFT")
    label:SetText(spec.tip)

    local keyText = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    keyText:SetPoint("TOPLEFT", f, "TOPLEFT", 130, y)
    keyText:SetWidth(90); keyText:SetJustifyH("LEFT")

    local set = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    set:SetWidth(48); set:SetHeight(16)
    set:SetPoint("TOPLEFT", f, "TOPLEFT", 228, y + 2)
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
  local cap = CreateFrame("Frame", "CleanBotTortusKeyCapture", UIParent)
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

  CB.RefreshKeybinds()
end
