--!strict
--[[
    Port: facts about the server a player is in, for the private servers module (ADR 0022).
    A pack adapter can implement this type later without changing callers.
]]

export type TeleportFailure = {
    userId: number,
    -- Name of the Enum.TeleportResult item (for example "Flooded").
    result: string,
    message: string,
    -- Repeats the failed teleport with the same destination and options.
    retry: () -> (),
}

export type ServerContext = {
    -- "" on a public server, the private server id otherwise.
    privateServerId: (self: ServerContext) -> string,
    -- User id of the owner of a VIP private server; 0 when there is none.
    ownerId: (self: ServerContext) -> number,
    -- Registers a TeleportInitFailed listener; returns a function that disconnects it.
    onTeleportFailed: (self: ServerContext, listener: (failure: TeleportFailure) -> ()) -> () -> (),
}

return {}
