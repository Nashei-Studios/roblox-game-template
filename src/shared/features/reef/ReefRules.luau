--!strict
--[[
    Numeric rules of the Reef fishing loop (ADR 0021). Pure data: loads under Lune.
    Every number here is a chosen, unplayed balance value, not a measured one. Change it
    after a playtest, not by feel.
]]

local ReefRules = {}

-- Seconds the first cast of a player with no catches takes to bite (design: bites within 5 s).
ReefRules.TUTORIAL_BITE_SECONDS = 3
-- Seconds after the bite during which a reel lands the fish. Generous on purpose: it must cover latency.
ReefRules.REEL_WINDOW_SECONDS = 1.5
-- Bait multiplies the bite delay by this factor. It never changes fish weights (no paid random).
ReefRules.BAIT_BITE_FACTOR = 0.5
-- Fish a bucket holds without the BiggerBucket pass, and what the pass adds.
ReefRules.BASE_BUCKET = 10
ReefRules.BUCKET_PASS_EXTRA = 20
-- Largest bait stock a player holds; a bait grant beyond it is clamped, not failed (ADR 0016).
ReefRules.MAX_BAIT = 500
-- Metres within which the sell stand accepts a sale (checked by the engine adapter).
ReefRules.STAND_RANGE = 12

ReefRules.BIGGER_BUCKET_PASS = "BiggerBucket"
ReefRules.SELL_ANYWHERE_PASS = "SellAnywhere"

return ReefRules
