--!strict
--[[
    Tunable numbers of the Key sprint loop. Pure data: loads under Lune. Every value here is a
    game-design choice made for the first build, not a measured result; change them after a
    playtest. Server code reads them; the client only displays what the server sends.
]]

local KeySprintRules = {}

-- Multiplier cap of a new player, the step of each upgrade and the hard maximum.
KeySprintRules.BASE_CAP = 5
KeySprintRules.CAP_STEP = 5
KeySprintRules.MAX_CAP = 30

-- Stages in the game. A test keeps this equal to the number of StageSpecs.
KeySprintRules.STAGE_COUNT = 3

-- Key the HUD asks for and the client listens to (an Enum.KeyCode name).
KeySprintRules.PRESS_KEY_NAME = "E"

-- Roblox default humanoid walk speed (studs per second) at multiplier 1.
KeySprintRules.BASE_WALK_SPEED = 16

-- Charge model. multiplier = min(cap, 1 + charge). One accepted press adds CHARGE_PER_PRESS
-- (times FASTER_CHARGE_FACTOR with the pass). Charge decays by DECAY_PER_SECOND while idle.
KeySprintRules.CHARGE_PER_PRESS = 0.1
KeySprintRules.FASTER_CHARGE_FACTOR = 1.5
KeySprintRules.DECAY_PER_SECOND = 0.25

-- Press intake. A batch carries 1..MAX_PRESSES_PER_BATCH presses. The press limiter spends one
-- token per press: a burst of PRESS_BURST and a sustained MAX_PRESSES_PER_SECOND.
KeySprintRules.MAX_PRESSES_PER_BATCH = 12
KeySprintRules.PRESS_BURST = 16
KeySprintRules.MAX_PRESSES_PER_SECOND = 10

-- A Finish is accepted no sooner than pathLength / (BASE_WALK_SPEED x cap) x this factor.
KeySprintRules.PLAUSIBLE_TIME_FACTOR = 0.9

-- Coins per stage cleared (index = stage) and the price of the NEXT cap, keyed by current cap.
KeySprintRules.STAGE_REWARDS = { 10, 25, 60 } :: { number }
KeySprintRules.CAP_PRICES = {
    [5] = 50,
    [10] = 150,
    [15] = 400,
    [20] = 1000,
    [25] = 2500,
} :: { [number]: number }

return KeySprintRules
