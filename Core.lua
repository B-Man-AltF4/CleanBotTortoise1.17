--[[ Core.lua - CleanBot Vanilla
     Bootstrap: namespace, saved variables, event dispatch, slash command.
     Vanilla 1.12 / Lua 5.0 - see PLAN.md for compatibility rules.
]]--

CleanBotV = CleanBotV or {}
local CB = CleanBotV

CB.version = "0.8"

-- Default saved settings (merged into CleanBotVDB on load).
local defaults = {
  point = "CENTER",
  x = 0,
  y = 0,
  shown = false,
  minimapAngle = 200,
  barPoint = "CENTER",
  barX = 0,
  barY = -160,
  barShown = true,
  barOrient = "HORIZONTAL",
  groupPoint = "CENTER",
  groupX = 250,
  groupY = 0,
}

function CB.Print(msg)
  DEFAULT_CHAT_FRAME:AddMessage("|cff66ccffCleanBotV:|r " .. tostring(msg))
end

local function ApplyDefaults()
  if type(CleanBotVDB) ~= "table" then CleanBotVDB = {} end
  for k, v in pairs(defaults) do
    if CleanBotVDB[k] == nil then CleanBotVDB[k] = v end
  end
  CB.db = CleanBotVDB
end

-- Event dispatch. In 1.12 the handler reads the globals `event` / `arg1` / `this`.
local ef = CreateFrame("Frame", "CleanBotVEventFrame")
ef:RegisterEvent("VARIABLES_LOADED")
ef:RegisterEvent("PLAYER_LOGIN")
ef:SetScript("OnEvent", function()
  if event == "VARIABLES_LOADED" then
    ApplyDefaults()
  elseif event == "PLAYER_LOGIN" then
    if not CB.db then ApplyDefaults() end
    CB.BuildUI()        -- defined in UI.lua
    CB.BuildActionBar() -- defined in ActionBar.lua
    CB.BuildGroup()     -- defined in GroupTab.lua
    if CB.db.shown then CB.mainFrame:Show() else CB.mainFrame:Hide() end
    CB.Print("loaded (v" .. CB.version .. "). Click the minimap button for the menu.")
  end
end)

-- Slash command: /cbv toggles, /cbv reset re-centers the panel.
SLASH_CLEANBOTV1 = "/cbv"
SlashCmdList["CLEANBOTV"] = function(msg)
  msg = string.lower(msg or "")
  if msg == "reset" then
    CB.db.point, CB.db.x, CB.db.y = "CENTER", 0, 0
    CB.db.barPoint, CB.db.barX, CB.db.barY = "CENTER", 0, -160
    if CB.mainFrame then
      CB.mainFrame:ClearAllPoints()
      CB.mainFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    end
    if CB.bar then
      CB.bar:ClearAllPoints()
      CB.bar:SetPoint("CENTER", UIParent, "CENTER", 0, -160)
    end
    CB.Print("panel + bar positions reset.")
  elseif msg == "bar" then
    CB.ToggleActionBar()
  elseif msg == "panel" then
    CB.ToggleUI()
  elseif msg == "settings" or msg == "config" then
    CB.ToggleSettings()
  elseif msg == "group" or msg == "roster" then
    CB.ToggleGroup()
  else
    CB.ToggleActionBar()
  end
end
