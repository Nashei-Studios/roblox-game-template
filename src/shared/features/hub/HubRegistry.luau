--!strict
--[[
    Hub registry: who stands on which slot of the plaza. Pure: loads under Lune; the engine
    presenter (server/adapters/HubSpawner) feeds it PlayerAdded / PlayerRemoving.

    - Join order decides the slot: the lowest free slot, so a player who leaves frees a slot the
      next joiner takes (the plaza fills from the inside out and never fragments).
    - Joining twice is idempotent (a respawn does not move the player).
    - The cap is the hub serverCap; set the experience max players to the same number.
      A player over the cap is not placed (`join` returns nil) and the game decides what to do.
]]

local HubLayout = require("./HubLayout")

export type Hooks = {
    onArrive: ((playerId: number, slot: number) -> ())?,
    onDepart: ((playerId: number, slot: number) -> ())?,
}

export type Deps = {
    config: HubLayout.HubConfig,
    hooks: Hooks?,
}

export type Registry = {
    join: (self: Registry, playerId: number) -> HubLayout.SpawnPoint?,
    leave: (self: Registry, playerId: number) -> (),
    slotOf: (self: Registry, playerId: number) -> number?,
    spawnFor: (self: Registry, playerId: number) -> HubLayout.SpawnPoint?,
    occupancy: (self: Registry) -> number,
    isFull: (self: Registry) -> boolean,
    -- Player ids ordered by slot (the order avatars were seated in).
    seated: (self: Registry) -> { number },
}

local HubRegistry = {}

function HubRegistry.new(deps: Deps): Registry
    local config = deps.config
    local hooks: Hooks = deps.hooks or {}
    local slotByPlayer: { [number]: number } = {}
    local playerBySlot: { [number]: number } = {}
    local count = 0

    local registry: Registry = {
        join = function(_self: Registry, playerId: number): HubLayout.SpawnPoint?
            local existing = slotByPlayer[playerId]
            if existing ~= nil then
                return HubLayout.spawnPoint(config.spawn, existing)
            end
            if count >= config.serverCap then
                return nil
            end
            local slot = 1
            while playerBySlot[slot] ~= nil do
                slot += 1
            end
            slotByPlayer[playerId] = slot
            playerBySlot[slot] = playerId
            count += 1
            local arrive = hooks.onArrive
            if arrive ~= nil then
                arrive(playerId, slot)
            end
            return HubLayout.spawnPoint(config.spawn, slot)
        end,
        leave = function(_self: Registry, playerId: number)
            local slot = slotByPlayer[playerId]
            if slot == nil then
                return
            end
            slotByPlayer[playerId] = nil
            playerBySlot[slot] = nil
            count -= 1
            local depart = hooks.onDepart
            if depart ~= nil then
                depart(playerId, slot)
            end
        end,
        slotOf = function(_self: Registry, playerId: number): number?
            return slotByPlayer[playerId]
        end,
        spawnFor = function(_self: Registry, playerId: number): HubLayout.SpawnPoint?
            local slot = slotByPlayer[playerId]
            if slot == nil then
                return nil
            end
            return HubLayout.spawnPoint(config.spawn, slot)
        end,
        occupancy = function(_self: Registry): number
            return count
        end,
        isFull = function(_self: Registry): boolean
            return count >= config.serverCap
        end,
        seated = function(_self: Registry): { number }
            local slots: { number } = {}
            for slot in playerBySlot do
                table.insert(slots, slot)
            end
            table.sort(slots)
            local ids: { number } = {}
            for _, slot in slots do
                table.insert(ids, playerBySlot[slot])
            end
            return ids
        end,
    }
    return registry
end

return HubRegistry
