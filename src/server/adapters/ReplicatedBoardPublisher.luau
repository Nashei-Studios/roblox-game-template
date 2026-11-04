--!strict
--[[
    Adapter: the leaderboards BoardPublisher over one replicated string value per board. The
    engine piece is injected (ADR 0009): `write(boardId, text)` sets the value that clients read.
    Replication of an instance is server to client by construction, so the budgeted remotes are
    untouched and a client cannot write the board. The text is `BoardKey.encode(entries)` followed
    by "|" and the update time.
]]

local BoardKey = require("../../shared/features/leaderboards/BoardKey")

-- Structurally identical to ports/Leaderboards.luau BoardPublisher (local; see the port).
type Entry = BoardKey.Entry
type BoardPublisher = {
    publish: (self: BoardPublisher, boardId: string, entries: { Entry }, updatedAt: number) -> (),
}

export type Deps = {
    write: (boardId: string, text: string) -> (),
}

local ReplicatedBoardPublisher = {}

function ReplicatedBoardPublisher.new(deps: Deps): BoardPublisher
    local publisher: BoardPublisher = {
        publish = function(
            _self: BoardPublisher,
            boardId: string,
            entries: { Entry },
            updatedAt: number
        )
            deps.write(boardId, `{BoardKey.encode(entries)}|{math.floor(updatedAt)}`)
        end,
    }
    return publisher
end

return ReplicatedBoardPublisher
