--!strict
--[[
    Server authority over locomotion and the tool in hand. Pure: the clock, the ownership check
    and the swing handler are injected. A client request carries intent only (ADR 0012): sprint
    began or ended, equip or unequip a tool id, swing. The server decides, and the engine
    presenter applies `speedOf` to the Humanoid.

    - Equip: the tool id must be owned (`owns`), cooldown applies, and the equipped tool is
      remembered per player so it comes back after a respawn (`onRespawn`). Persisting it across
      sessions is the game save, not this module.
    - Swing: only with a tool in hand, past the swing cooldown. The game implements the effect
      through `SwingHandler`; this module never grants anything itself.
]]

local LocomotionConfig = require("./LocomotionConfig")
local LocomotionMachine = require("./LocomotionMachine")

export type SwingHandler = {
    -- Called once per accepted swing. The game grants value here (damage, a hit, a mine tick).
    swing: (playerId: number, toolId: string) -> (),
}

export type Verdict = { accepted: boolean, reason: string? }

export type Deps = {
    config: LocomotionConfig.LocomotionConfig,
    -- Server clock, seconds.
    now: () -> number,
    -- True when the player may hold this tool id (inventory, pass, rank): game specific.
    owns: (playerId: number, toolId: string) -> boolean,
    handler: SwingHandler,
}

export type Server = {
    join: (self: Server, playerId: number) -> (),
    leave: (self: Server, playerId: number) -> (),
    setMoving: (self: Server, playerId: number, moving: boolean) -> (),
    sprint: (self: Server, playerId: number, began: boolean) -> Verdict,
    equip: (self: Server, playerId: number, toolId: string, want: boolean) -> Verdict,
    swing: (self: Server, playerId: number) -> Verdict,
    -- The tool to put back in hand after a respawn, or nil.
    onRespawn: (self: Server, playerId: number) -> string?,
    equippedOf: (self: Server, playerId: number) -> string?,
    speedOf: (self: Server, playerId: number) -> number?,
    snapshotOf: (self: Server, playerId: number) -> LocomotionMachine.Snapshot?,
}

type Entry = {
    machine: LocomotionMachine.Machine,
    tool: string?,
    lastEquipAt: number?,
    lastSwingAt: number?,
}

local LocomotionServer = {}

local function refuse(reason: string): Verdict
    return { accepted = false, reason = reason }
end

function LocomotionServer.new(deps: Deps): Server
    local config = deps.config
    local entries: { [number]: Entry } = {}

    local server: Server
    server = {
        join = function(_self: Server, playerId: number)
            if entries[playerId] == nil then
                entries[playerId] = { machine = LocomotionMachine.new(config) }
            end
        end,
        leave = function(_self: Server, playerId: number)
            entries[playerId] = nil
        end,
        setMoving = function(_self: Server, playerId: number, moving: boolean)
            local entry = entries[playerId]
            if entry ~= nil then
                entry.machine:setMoving(moving)
            end
        end,
        sprint = function(_self: Server, playerId: number, began: boolean): Verdict
            local entry = entries[playerId]
            if entry == nil then
                return refuse("unknown_player")
            end
            entry.machine:sprintInput(began)
            return { accepted = true, reason = nil }
        end,
        equip = function(_self: Server, playerId: number, toolId: string, want: boolean): Verdict
            local entry = entries[playerId]
            if entry == nil then
                return refuse("unknown_player")
            end
            local now = deps.now()
            local last = entry.lastEquipAt
            if last ~= nil and now - last < config.equipCooldownSeconds then
                return refuse("cooldown")
            end
            if want then
                if not deps.owns(playerId, toolId) then
                    return refuse("not_owned")
                end
                entry.tool = toolId
            else
                if entry.tool ~= toolId then
                    return refuse("not_equipped")
                end
                entry.tool = nil
            end
            entry.lastEquipAt = now
            entry.machine:setEquipped(want)
            return { accepted = true, reason = nil }
        end,
        swing = function(_self: Server, playerId: number): Verdict
            local entry = entries[playerId]
            if entry == nil then
                return refuse("unknown_player")
            end
            local tool = entry.tool
            if tool == nil then
                return refuse("nothing_equipped")
            end
            local now = deps.now()
            local last = entry.lastSwingAt
            if last ~= nil and now - last < config.swingCooldownSeconds then
                return refuse("cooldown")
            end
            entry.lastSwingAt = now
            deps.handler.swing(playerId, tool)
            return { accepted = true, reason = nil }
        end,
        onRespawn = function(_self: Server, playerId: number): string?
            local entry = entries[playerId]
            if entry == nil then
                return nil
            end
            -- A new character starts still and with empty hands; the remembered tool returns.
            entry.machine:setMoving(false)
            return entry.tool
        end,
        equippedOf = function(_self: Server, playerId: number): string?
            local entry = entries[playerId]
            return if entry ~= nil then entry.tool else nil
        end,
        speedOf = function(_self: Server, playerId: number): number?
            local entry = entries[playerId]
            return if entry ~= nil then entry.machine:speed() else nil
        end,
        snapshotOf = function(_self: Server, playerId: number): LocomotionMachine.Snapshot?
            local entry = entries[playerId]
            return if entry ~= nil then entry.machine:snapshot() else nil
        end,
    }
    return server
end

return LocomotionServer
