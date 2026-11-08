--!strict
--[[
    Pure filter of "tap anywhere" (ADR 0033): which inputs count as a tap. Takes the name of
    the UserInputType so it loads under Lune without the engine enum.
    - A press starts a tap only when no GUI took it, it is a touch or the left mouse button, and no
      menu is open (nothing is triggered under a menu).
    - A touch counts when it ENDS: short and without travel, so a camera drag never taps. The
      mouse taps on press because it can be held.
    Keyboard and gamepad act through their own bound action, guarded by `allowsAction`.
]]

local TapFilter = {}

-- A touch that moves farther than this many pixels is a drag, not a tap.
TapFilter.MAX_TRAVEL = 10
-- A touch held longer than this many seconds is a hold, not a tap.
TapFilter.MAX_DURATION = 0.3

local TAP_INPUTS: { [string]: boolean } = {
    Touch = true,
    MouseButton1 = true,
}

--- True when a press may start a tap (GUI did not take it, no menu is open).
function TapFilter.beginsTap(
    userInputTypeName: string,
    gameProcessed: boolean,
    menuOpen: boolean
): boolean
    return not gameProcessed and not menuOpen and TAP_INPUTS[userInputTypeName] == true
end

--- True when a touch that has just ended was a tap: little travel, short duration.
function TapFilter.completesTap(travelPixels: number, durationSeconds: number): boolean
    return travelPixels < TapFilter.MAX_TRAVEL and durationSeconds < TapFilter.MAX_DURATION
end

--- The keyboard and gamepad bind actions unless a menu is open.
function TapFilter.allowsAction(menuOpen: boolean): boolean
    return not menuOpen
end

return TapFilter
