--!strict
local InMemoryProfileRepository =
    require("../../../src/shared/features/playerdata/InMemoryProfileRepository")
local contract = require("./ProfileRepository.contract")
local harness = require("../../harness")

type Data = { coins: number }

local function makeRepository(): contract.Repository
    return InMemoryProfileRepository.new({
        default = function(): Data
            return { coins = 0 }
        end,
        clone = function(data: Data): Data
            return { coins = data.coins }
        end,
        failSaves = nil,
    })
end

return function(suite: harness.Harness)
    contract.run(suite, makeRepository)

    suite:test("failing saves never reach storage, so confirmSaved times out", function()
        local failing = true
        local repository = InMemoryProfileRepository.new({
            default = function(): Data
                return { coins = 0 }
            end,
            clone = function(data: Data): Data
                return { coins = data.coins }
            end,
            failSaves = function(): boolean
                return failing
            end,
        })
        local loaded = repository:load("p1")
        if not loaded.ok then
            error("load failed")
        end
        loaded.value.data.coins = 5
        local function isFive(saved: Data): boolean
            return saved.coins == 5
        end
        local first = loaded.value:confirmSaved(isFive, 1)
        harness.isFalse(first.ok, "outage: not confirmed")
        failing = false
        harness.isTrue(loaded.value:confirmSaved(isFive, 1).ok, "recovered: confirmed")
    end)
end
