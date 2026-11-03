--!strict
--[[
    Port: the server clock that measures growth (ADR 0020). Seconds since the Unix epoch, the
    same scale on every server and on `workspace:GetServerTimeNow()`. Tests inject a fake;
    production uses the adapter src/server/adapters/ServerClock.luau.
]]

export type Clock = {
    now: (self: Clock) -> number,
}

return {}
