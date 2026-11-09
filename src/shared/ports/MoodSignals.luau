--!strict
--[[
    Port: what the game observes, as named on/off signals, for the music mood resolver
    (ADR 0050). Client side. The game adapter reads its own state (an attribute, a replicated
    value, a controller) and answers `isOn("signal_name")`; the resolver never learns where a
    signal comes from, and the mold never names a game word.
]]

export type MoodSignals = {
    -- True while the named condition holds. An unknown name answers false.
    isOn: (self: MoodSignals, signal: string) -> boolean,
}

return {}
