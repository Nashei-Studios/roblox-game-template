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
    })
end

return function(suite: harness.Harness)
    contract.run(suite, makeRepository)
end
