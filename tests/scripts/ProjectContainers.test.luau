--!strict
local ProjectContainers = require("../../scripts/ProjectContainers")
local harness = require("../harness")

local function joined(paths: { { string } }): string
    local parts: { string } = {}
    for _, path in paths do
        table.insert(parts, table.concat(path, "."))
    end
    return table.concat(parts, " | ")
end

return function(suite: harness.Harness)
    suite:test("every node with $path is a container, in a stable order", function()
        local ok, result = ProjectContainers.from({
            ["$className"] = "DataModel",
            ServerScriptService = {
                ["$className"] = "ServerScriptService",
                Server = { ["$path"] = "src/server" },
                Vendor = {
                    ["$className"] = "Folder",
                    ProfileStore = { ["$path"] = "vendor/ProfileStore.luau" },
                },
            },
            ReplicatedStorage = { Shared = { ["$path"] = "src/shared" } },
            StarterPlayer = { StarterPlayerScripts = { Client = { ["$path"] = "src/client" } } },
        })
        harness.equal(ok, true, "ok")
        harness.equal(
            joined(result :: { { string } }),
            "ReplicatedStorage.Shared | ServerScriptService.Server | ServerScriptService.Vendor.ProfileStore | StarterPlayer.StarterPlayerScripts.Client",
            "containers"
        )
    end)

    suite:test("a whole service mapped with $path is refused with the fix", function()
        local ok, result =
            ProjectContainers.from({ ReplicatedStorage = { ["$path"] = "src/shared" } })
        harness.equal(ok, false, "refused")
        harness.equal(
            string.find(result :: string, "map a child", 1, true) ~= nil,
            true,
            "says how to fix it"
        )
    end)

    suite:test("a project without code is refused", function()
        local ok = ProjectContainers.from({ Workspace = { ["$className"] = "Workspace" } })
        harness.equal(ok, false, "refused")
    end)

    suite:test("a missing tree is refused", function()
        local ok = ProjectContainers.from((nil :: any) :: { [string]: any })
        harness.equal(ok, false, "refused")
    end)
end
