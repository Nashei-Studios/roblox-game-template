--!strict
--[[
    Pure mixer and fade maths (issue #30). Percent in, gain out; no engine.
]]

local Mixer = {}

--- 0..100 percent to a 0..1 gain; out-of-range and NaN are clamped (NaN becomes 0).
function Mixer.gain(percent: number): number
    if percent ~= percent then
        return 0
    end
    return math.clamp(percent, 0, 100) / 100
end

--- Final gain of a sound: its base volume times the player's group volume.
function Mixer.mix(baseVolume: number, groupPercent: number): number
    return math.clamp(baseVolume, 0, 1) * Mixer.gain(groupPercent)
end

--- Linear fade: the value after `elapsed` of `duration` seconds. A zero duration jumps to `to`.
function Mixer.fade(from: number, to: number, elapsed: number, duration: number): number
    if duration <= 0 then
        return to
    end
    local progress = math.clamp(elapsed / duration, 0, 1)
    return from + (to - from) * progress
end

return Mixer
