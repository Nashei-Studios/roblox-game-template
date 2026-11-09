--!strict
--[[
    Runtime-neutral test runner: no Lune API, so it loads under both Lune and the Luau CLI
    (ADR 0017). Add each new test file to `suites` (explicit list keeps it strictly typed).
    Entry points: `scripts/test.luau` (Lune, `lune run scripts/test`) and
    `scripts/test_luau.luau` (`luau --coverage scripts/test_luau.luau`, see scripts/coverage.ps1).
]]

local harness = require("../tests/harness")

local suites: { { name: string, register: (suite: harness.Harness) -> () } } = {
    { name = "Config", register = require("../tests/Config.test") },
    { name = "Result", register = require("../tests/Result.test") },
    { name = "KitManifest", register = require("../tests/assets/KitManifest.test") },
    { name = "Analytics", register = require("../tests/features/analytics/Analytics.test") },
    {
        name = "AnalyticsTracker",
        register = require("../tests/features/analytics/AnalyticsTracker.test"),
    },
    { name = "Flags", register = require("../tests/features/flags/Flags.test") },
    { name = "AutoFeel", register = require("../tests/features/autofeel/AutoFeel.test") },
    { name = "Locomotion", register = require("../tests/features/locomotion/Locomotion.test") },
    { name = "Hub", register = require("../tests/features/hub/Hub.test") },
    {
        name = "MomentDirector",
        register = require("../tests/features/clipmoment/MomentDirector.test"),
    },
    {
        name = "MomentSettings",
        register = require("../tests/features/clipmoment/MomentSettings.test"),
    },
    { name = "Music", register = require("../tests/features/music/Music.test") },
    { name = "Presence", register = require("../tests/features/presence/Presence.test") },
    { name = "Podium", register = require("../tests/features/podium/Podium.test") },
    {
        name = "TierModelSet",
        register = require("../tests/features/tiermodels/TierModelSet.test"),
    },
    {
        name = "TierSurface",
        register = require("../tests/features/tiermodels/TierSurface.test"),
    },
    { name = "MoodResolver", register = require("../tests/features/music/MoodResolver.test") },
    {
        name = "SharedObjective",
        register = require("../tests/features/sharedobjective/SharedObjective.test"),
    },
    {
        name = "WinCondition",
        register = require("../tests/features/wincondition/WinCondition.test"),
    },
    {
        name = "ReceiptDelivery",
        register = require("../tests/features/monetization/ReceiptDelivery.test"),
    },
    {
        name = "ProductGrants",
        register = require("../tests/features/monetization/ProductGrants.test"),
    },
    {
        name = "PlayerDataMigrations",
        register = require("../tests/features/playerdata/PlayerDataMigrations.test"),
    },
    {
        name = "Monetization",
        register = require("../tests/features/monetization/Monetization.test"),
    },
    {
        name = "InMemoryProfileRepository (port contract)",
        register = require("../tests/features/playerdata/InMemoryProfileRepository.test"),
    },
    {
        name = "PlayerDataService",
        register = require("../tests/features/playerdata/PlayerDataService.test"),
    },
    {
        name = "AnalyticsServiceSink (adapter)",
        register = require("../tests/adapters/AnalyticsServiceSink.test"),
    },
    {
        name = "ConfigServiceFlags (adapter)",
        register = require("../tests/adapters/ConfigServiceFlags.test"),
    },
    {
        name = "ProfileStoreRepository (adapter)",
        register = require("../tests/adapters/ProfileStoreRepository.test"),
    },
    { name = "Validation", register = require("../tests/net/Validation.test") },
    { name = "RateLimiter", register = require("../tests/net/RateLimiter.test") },
    {
        name = "EnumOrder (generate-remotes)",
        register = require("../tests/scripts/EnumOrder.test"),
    },
    { name = "AnalyticsQuery", register = require("../tests/ops/AnalyticsQuery.test") },
    {
        name = "PurchaseRequests",
        register = require("../tests/features/monetization/PurchaseRequests.test"),
    },
    {
        name = "BenefitReconciler",
        register = require("../tests/features/subscriptions/BenefitReconciler.test"),
    },
    {
        name = "RobloxMarketplaceSubscriptions (adapter)",
        register = require("../tests/adapters/RobloxMarketplaceSubscriptions.test"),
    },
    {
        name = "ConfigMonetization",
        register = require("../tests/ConfigMonetization.test"),
    },
    {
        name = "RewardedAds",
        register = require("../tests/features/rewardedads/RewardedAds.test"),
    },
    {
        name = "PrivateServer",
        register = require("../tests/features/privateserver/PrivateServer.test"),
    },
    {
        name = "PlusPrompt",
        register = require("../tests/features/plus/PlusPrompt.test"),
    },
    {
        name = "RobuxTransfers",
        register = require("../tests/features/robuxtransfers/RobuxTransfers.test"),
    },
    {
        name = "PriceLabel",
        register = require("../tests/features/pricing/PriceLabel.test"),
    },
    {
        name = "RobloxAdService (adapter)",
        register = require("../tests/adapters/RobloxAdService.test"),
    },
    {
        name = "Announcer (adapter and presenter)",
        register = require("../tests/adapters/Announcer.test"),
    },
    {
        name = "RobloxServerContext (adapter)",
        register = require("../tests/adapters/RobloxServerContext.test"),
    },
    {
        name = "RobloxPlusSubscription (adapter)",
        register = require("../tests/adapters/RobloxPlusSubscription.test"),
    },
    {
        name = "RobloxRobuxTransfers (adapter)",
        register = require("../tests/adapters/RobloxRobuxTransfers.test"),
    },
    {
        name = "RobloxPriceLookup (adapter)",
        register = require("../tests/adapters/RobloxPriceLookup.test"),
    },
    { name = "RemoteBudget", register = require("../tests/perf/RemoteBudget.test") },
    { name = "ProbeEvaluator", register = require("../tests/perf/ProbeEvaluator.test") },
    { name = "CodesConfig", register = require("../tests/features/codes/CodesConfig.test") },
    { name = "Codes", register = require("../tests/features/codes/Codes.test") },
    { name = "CodeRequests", register = require("../tests/features/codes/CodeRequests.test") },
    { name = "StreakClock", register = require("../tests/features/timerewards/StreakClock.test") },
    {
        name = "SessionGifts",
        register = require("../tests/features/timerewards/SessionGifts.test"),
    },
    { name = "TimeRewards", register = require("../tests/features/timerewards/TimeRewards.test") },
    {
        name = "TimeRewardRequests",
        register = require("../tests/features/timerewards/TimeRewardRequests.test"),
    },
    {
        name = "TimeRewardsConfig",
        register = require("../tests/features/timerewards/TimeRewardsConfig.test"),
    },
    { name = "ToastQueue", register = require("../tests/features/notifications/ToastQueue.test") },
    {
        name = "ToastController",
        register = require("../tests/features/notifications/ToastController.test"),
    },
    {
        name = "NotificationsConfig",
        register = require("../tests/features/notifications/NotificationsConfig.test"),
    },
    { name = "Mixer", register = require("../tests/features/sound/Mixer.test") },
    { name = "SoundManager", register = require("../tests/features/sound/SoundManager.test") },
    { name = "SoundSettings", register = require("../tests/features/sound/SoundSettings.test") },
    { name = "SoundConfig", register = require("../tests/features/sound/SoundConfig.test") },
    {
        name = "RemoteNotifier and RemoteSoundPush (adapters)",
        register = require("../tests/adapters/RemoteNotifier.test"),
    },
    { name = "Ui", register = require("../tests/features/ui/Ui.test") },
    { name = "UiAudit", register = require("../tests/features/ui/UiAudit.test") },
    { name = "UiSystem", register = require("../tests/features/uisystem/UiSystem.test") },
    {
        name = "Leaderboards",
        register = require("../tests/features/leaderboards/Leaderboards.test"),
    },
    {
        name = "CommunityReward",
        register = require("../tests/features/community-reward/CommunityReward.test"),
    },
    {
        name = "CommunityPerk",
        register = require("../tests/features/community-reward/CommunityPerk.test"),
    },
    {
        name = "Leaderboards and Group adapters",
        register = require("../tests/adapters/Leaderboards.adapters.test"),
    },
    {
        name = "RobloxGroupMembership (adapter)",
        register = require("../tests/adapters/RobloxGroupMembership.test"),
    },
    {
        name = "JoinCoordinator",
        register = require("../tests/features/join/JoinCoordinator.test"),
    },
    {
        name = "JoinPolicy",
        register = require("../tests/features/join/JoinPolicy.test"),
    },
    {
        name = "FriendBoost",
        register = require("../tests/features/social/FriendBoost.test"),
    },
    {
        name = "FriendBoostLabel",
        register = require("../tests/features/social/FriendBoostLabel.test"),
    },
    {
        name = "Invite (reward, referral, ledger)",
        register = require("../tests/features/social/Invite.test"),
    },
    {
        name = "SocialRuntime",
        register = require("../tests/features/social/SocialRuntime.test"),
    },
    {
        name = "JoinProbe",
        register = require("../tests/features/joinprobe/JoinProbe.test"),
    },
    {
        name = "JoinProbeSink",
        register = require("../tests/features/joinprobe/JoinProbeSink.test"),
    },
    {
        name = "ProfileStoreName",
        register = require("../tests/features/playerdata/ProfileStoreName.test"),
    },
    { name = "Progress", register = require("../tests/features/progress/Progress.test") },
    { name = "LiveOps", register = require("../tests/features/liveops/LiveOps.test") },
    { name = "Offers", register = require("../tests/features/offers/Offers.test") },
    { name = "Quests", register = require("../tests/features/quests/Quests.test") },
    { name = "HitFx", register = require("../tests/features/hitfx/HitFx.test") },
    { name = "CardGrid", register = require("../tests/features/ui/CardGrid.test") },
    {
        name = "CollectionIndex",
        register = require("../tests/features/collectionindex/CollectionIndex.test"),
    },
    { name = "UiEco", register = require("../tests/features/ui/UiEco.test") },
    { name = "ItemIcon", register = require("../tests/features/ui/ItemIcon.test") },
    { name = "ItemSlots", register = require("../tests/features/itemslots/ItemSlots.test") },
    { name = "InspectView", register = require("../tests/features/inspect/InspectView.test") },
    { name = "Rarity", register = require("../tests/features/rarity/Rarity.test") },
    { name = "RevealMoment", register = require("../tests/features/reveal/RevealMoment.test") },
    { name = "UiAudit", register = require("../tests/features/ui/UiAudit.test") },
    {
        name = "TapInput (router and filter)",
        register = require("../tests/features/input/TapInput.test"),
    },
    {
        name = "StudioLockPolicy (hook)",
        register = require("../tests/claude/StudioLockPolicy.test"),
    },
}

local Suites = {}

--- Runs every suite, printing results. Returns (passed, failed).
function Suites.run(): (number, number)
    local totalPassed, totalFailed = 0, 0
    for _, entry in suites do
        print(entry.name)
        local suite = harness.new()
        entry.register(suite)
        local passed, failed = suite:run()
        totalPassed += passed
        totalFailed += failed
    end
    print(`\n{totalPassed} passed, {totalFailed} failed`)
    return totalPassed, totalFailed
end

return Suites
