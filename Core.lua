--[[ Core.lua - CleanBot Vanilla
     Bootstrap: namespace, saved variables, event dispatch, slash command.
     Vanilla 1.12 / Lua 5.0 - see PLAN.md for compatibility rules.
]]--

CleanBotV = CleanBotV or {}
local CB = CleanBotV

CB.version = "0.1"

-- Default saved settings (merged into CleanBotVDB on load).
local defaults = {
  point = "CENTER",
  x = 0,
  y = 0,
  shown = true,
  minimapAngle = 200,
}

function CB.Print(msg)
  DEFAULT_CHAT_FRAME:AddMessage("|cff66ccffCleanBotV:|r " .. tostring(msg))
end

local function ApplyDefaults()
  if type(CleanBotVDB) ~= "table" then CleanBotVDB = {} end
  local k, v
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
    CB.BuildUI()  -- defined in UI.lua
    if CB.db.shown then CB.mainFrame:Show() else CB.mainFrame:Hide() end
    CB.Print("loaded (v" .. CB.version .. "). Type /cbv to toggle the panel.")
  end
end)

-- Slash command: /cbv toggles, /cbv reset re-centers the panel.
SLASH_CLEANBOTV1 = "/cbv"
SlashCmdList["CLEANBOTV"] = function(msg)
  msg = string.lower(msg or "")
  if msg == "reset" then
    CB.db.point, CB.db.x, CB.db.y = "CENTER", 0, 0
    if CB.mainFrame then
      CB.mainFrame:ClearAllPoints()
      CB.mainFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    end
    CB.Print("panel position reset.")
  else
    CB.ToggleUI()
  end
end
