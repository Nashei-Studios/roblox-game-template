--!strict
local LocomotionConfig = require("../../../src/shared/features/locomotion/LocomotionConfig")
local LocomotionMachine = require("../../../src/shared/features/locomotion/LocomotionMachine")
local LocomotionServer = require("../../../src/shared/features/locomotion/LocomotionServer")
local harness = require("../../harness")

local function has(problems: { string }, needle: string): boolean
    return string.find(table.concat(problems, "|"), needle, 1, true) ~= nil
end

type Rig = {
    server: LocomotionServer.Server,
    clock: { now: number },
    swings: { string },
    owned: { [string]: boolean },
}

local function rig(config: LocomotionConfig.LocomotionConfig?): Rig
    local clock = { now = 0 }
    local swings: { string } = {}
    local owned: { [string]: boolean } = { pick = true }
    local server = LocomotionServer.new({
        config = config or LocomotionConfig.default(),
        now = function()
            return clock.now
        end,
        owns = function(_playerId: number, toolId: string): boolean
            return owned[toolId] == true
        end,
        handler = {
            swing = function(playerId: number, toolId: string)
                table.insert(swings, `{playerId}:{toolId}`)
            end,
        },
    })
    server:join(1)
    return { server = server, clock = clock, swings = swings, owned = owned }
end

return function(suite: harness.Harness)
    suite:test("the default config is valid and every animation falls back to Roblox", function()
        local config = LocomotionConfig.default()
        harness.equal(#LocomotionConfig.validate(config), 0)
        harness.equal(#LocomotionConfig.defaultedAnimations(config), 6)
        config.animations.run = 123
        harness.equal(#LocomotionConfig.defaultedAnimations(config), 5)
    end)

    suite:test("validate reports speeds, mode, keys, multiplier, ids and cooldowns", function()
        local bad = LocomotionConfig.default()
        bad.walkSpeed = 0
        bad.runSpeed = 500
        bad.sprintMode = "dash"
        bad.equippedSpeedMultiplier = 5
        bad.keys = { sprint = {}, equip = { "Q" } }
        bad.animations.walk = -4
        bad.equipCooldownSeconds = -1
        bad.swingCooldownSeconds = -1
        local problems = LocomotionConfig.validate(bad)
        for _, needle in
            {
                "walkSpeed",
                "runSpeed",
                "sprintMode",
                "Multiplier",
                "keys",
                "animations.walk",
                "equipCooldown",
                "swingCooldown",
            }
        do
            harness.isTrue(has(problems, needle), needle)
        end
        local slow = LocomotionConfig.default()
        slow.runSpeed = slow.walkSpeed
        harness.isTrue(has(LocomotionConfig.validate(slow), "runSpeed"))
    end)

    suite:test("hold mode: running only while moving and the key is down", function()
        local machine = LocomotionMachine.new(LocomotionConfig.default())
        harness.equal(machine:state(), "idle")
        machine:sprintInput(true)
        harness.equal(machine:state(), "idle", "sprint without movement stays idle")
        machine:setMoving(true)
        harness.equal(machine:state(), "running")
        harness.equal(machine:speed(), 25)
        machine:sprintInput(false)
        harness.equal(machine:state(), "walking")
        harness.equal(machine:speed(), 16)
    end)

    suite:test("toggle mode flips on press, ignores release, clears on stop", function()
        local config = LocomotionConfig.default()
        config.sprintMode = "toggle"
        local machine = LocomotionMachine.new(config)
        machine:setMoving(true)
        machine:sprintInput(true)
        machine:sprintInput(false)
        harness.equal(machine:state(), "running")
        machine:sprintInput(true)
        harness.equal(machine:state(), "walking")
        machine:sprintInput(true)
        machine:setMoving(false)
        machine:setMoving(true)
        harness.equal(machine:state(), "walking", "stopping cleared the sprint")
        config.cancelSprintOnStop = false
        local keep = LocomotionMachine.new(config)
        keep:setMoving(true)
        keep:sprintInput(true)
        keep:setMoving(false)
        keep:setMoving(true)
        harness.equal(keep:state(), "running")
    end)

    suite:test("the equipped multiplier scales the speed and the snapshot reports it", function()
        local config = LocomotionConfig.default()
        config.equippedSpeedMultiplier = 0.5
        local machine = LocomotionMachine.new(config)
        machine:setMoving(true)
        machine:setEquipped(true)
        local snapshot = machine:snapshot()
        harness.equal(snapshot.speed, 8)
        harness.isTrue(snapshot.equipped)
        harness.isFalse(snapshot.sprinting)
    end)

    suite:test(
        "equip needs ownership, honors the cooldown and unequip needs the same tool",
        function()
            local r = rig()
            harness.equal(r.server:equip(1, "ghost", true).reason, "not_owned")
            harness.isTrue(r.server:equip(1, "pick", true).accepted)
            harness.equal(r.server:equippedOf(1), "pick")
            harness.equal(r.server:equip(1, "pick", false).reason, "cooldown")
            r.clock.now = 1
            harness.equal(r.server:equip(1, "other", false).reason, "not_equipped")
            harness.isTrue(r.server:equip(1, "pick", false).accepted)
            harness.equal(r.server:equippedOf(1), nil)
            harness.equal(r.server:equip(99, "pick", true).reason, "unknown_player")
        end
    )

    suite:test(
        "swing needs a tool in hand and respects its cooldown, then calls the handler",
        function()
            local r = rig()
            harness.equal(r.server:swing(1).reason, "nothing_equipped")
            harness.isTrue(r.server:equip(1, "pick", true).accepted)
            harness.isTrue(r.server:swing(1).accepted)
            harness.equal(r.server:swing(1).reason, "cooldown")
            r.clock.now = 1
            harness.isTrue(r.server:swing(1).accepted)
            harness.equal(table.concat(r.swings, ","), "1:pick,1:pick")
            harness.equal(r.server:swing(99).reason, "unknown_player")
        end
    )

    suite:test(
        "server speed follows movement, sprint and the tool; unknown players are inert",
        function()
            local r = rig()
            r.server:setMoving(1, true)
            harness.equal(r.server:speedOf(1), 16)
            harness.isTrue(r.server:sprint(1, true).accepted)
            harness.equal(r.server:speedOf(1), 25)
            local running = r.server:snapshotOf(1)
            harness.equal(if running ~= nil then running.state else "", "running")
            harness.equal(r.server:sprint(7, true).reason, "unknown_player")
            r.server:setMoving(7, true)
            harness.equal(r.server:speedOf(7), nil)
            harness.equal(r.server:snapshotOf(7), nil)
        end
    )

    suite:test("the equipped tool returns after a respawn and is forgotten on leave", function()
        local r = rig()
        harness.equal(r.server:onRespawn(1), nil)
        harness.isTrue(r.server:equip(1, "pick", true).accepted)
        r.server:setMoving(1, true)
        harness.equal(r.server:onRespawn(1), "pick")
        local still = r.server:snapshotOf(1)
        harness.equal(
            if still ~= nil then still.state else "",
            "idle",
            "a new character starts still"
        )
        r.server:leave(1)
        harness.equal(r.server:onRespawn(1), nil)
        harness.equal(r.server:equippedOf(1), nil)
        r.server:join(1)
        r.server:join(1)
        harness.equal(r.server:equippedOf(1), nil)
    end)
end
