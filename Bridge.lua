--[[ Bridge.lua - the ONLY place that talks to bots.
     Vanilla 1.12 has no SendAddonMessage and the mangos playerbots obey
     whisper / party / raid chat, so every command goes out as chat.
     (The WotLK MBOT addon-message bridge is not available here - see
     docs/bridge-protocol.md "whisper fallback" and PLAN.md.)
]]--

local CB = CleanBotV

-- Decide who receives a command.
--   friendly player targeted (not you) -> whisper that one bot
--   else in a raid                      -> RAID chat (all bots)
--   else in a party                     -> PARTY chat (all bots)
-- Returns: mode, targetName, label   (mode is nil when there's nobody to talk to)
local function ResolveTarget()
  if UnitExists("target") and UnitIsPlayer("target")
     and UnitIsFriend("player", "target")
     and not UnitIsUnit("target", "player") then
    return "whisper", UnitName("target"), "-> " .. UnitName("target")
  elseif GetNumRaidMembers() > 0 then
    return "raid", nil, "-> raid"
  elseif GetNumPartyMembers() > 0 then
    return "party", nil, "-> party"
  end
  return nil, nil, nil
end

-- Send a raw command string to the resolved recipient(s).
function CB.SendCommand(cmd)
  local mode, name, label = ResolveTarget()
  if not mode then
    CB.Print("|cffff5555No bot targeted and not in a group.|r Target a bot, or join a party/raid.")
    if CB.SetStatus then CB.SetStatus("no target / no group") end
    return false
  end

  if mode == "whisper" then
    SendChatMessage(cmd, "WHISPER", nil, name)
  elseif mode == "raid" then
    SendChatMessage(cmd, "RAID")
  elseif mode == "party" then
    SendChatMessage(cmd, "PARTY")
  end

  if CB.SetStatus then CB.SetStatus('sent "' .. cmd .. '"  ' .. label) end
  return true
end
