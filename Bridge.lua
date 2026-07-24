--[[ Bridge.lua - the ONLY place that sends bot commands.

     Party bots (vmangos PartyBotAI, Turtle's `.bot` fork) are driven by the
     `.bot` dot-command. Dot-commands are sent over SAY: the server intercepts
     the leading '.' and runs the command (it is NOT broadcast as speech), then
     replies "All party bots are ...". Most subs act on ALL party bots and/or
     your current target; ccmark/focusmark act on the raid-marked target.

     There is no data-out from bots on this server, so there is nothing to parse.
]]--

local CB = CleanBotTortoise

-- Fire a bare `.bot <sub>` command (no argument).
function CB.Bot(sub)
  SendChatMessage(".bot " .. sub, "SAY")
  if CB.SetStatus then CB.SetStatus(".bot " .. sub) end
end

-- Mark the current target with a raid icon (1=Star .. 8=Skull), then fire a
-- mark-based command so the bots act on that exact target.
function CB.BotMark(icon, sub)
  if not UnitExists("target") then
    CB.Print("|cffff5555No target to mark.|r Target an enemy first.")
    if CB.SetStatus then CB.SetStatus("no target to mark") end
    return
  end
  SetRaidTarget("target", icon)
  SendChatMessage(".bot " .. sub, "SAY")
  if CB.SetStatus then CB.SetStatus("marked target + .bot " .. sub) end
end

-- Clear our raid mark on the current target (if any) and clear the bots' marks.
function CB.BotClearMarks()
  if UnitExists("target") then SetRaidTarget("target", 0) end
  SendChatMessage(".bot clearmarks", "SAY")
  if CB.SetStatus then CB.SetStatus(".bot clearmarks") end
end
