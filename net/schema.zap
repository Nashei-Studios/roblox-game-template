opt server_output = "../src/shared/net/generated/server.luau"
opt client_output = "../src/shared/net/generated/client.luau"
opt types_output = "../src/shared/net/generated/types.luau"
opt casing = "camelCase"
opt write_checks = true

-- Product names mirror Config.default.developerProducts. Keep both in sync (see docs/architecture.md).
type ProductName = enum { "Coins100" }

-- Client -> server. Carries intent only (ADR 0012): the server re-derives price, id and grant.
event RequestPurchase = {
	from: Client,
	type: Reliable,
	call: SingleSync,
	data: (product: ProductName),
}

-- Server -> client. The balance after a grant, clamped to u32 by the sender.
event CoinsChanged = {
	from: Server,
	type: Reliable,
	call: SingleSync,
	data: (coins: u32),
}

-- Engagement modules (ADR 0025): codes, time rewards, notifications, sound.
-- Kinds mirror NotificationsConfig.REQUIRED_KINDS; keep both in sync (see docs/architecture.md).
type NotificationKind = enum {
	"code_redeemed",
	"code_invalid",
	"code_expired",
	"code_used",
	"code_cooldown",
	"daily_claimed",
	"daily_unavailable",
	"session_gift_claimed",
	"session_gift_unavailable",
	"community_reward_claimed",
	"community_not_member",
}

type VolumeGroup = enum { "music", "sfx" }

-- Client -> server. Intent only: the text typed. The server normalizes, rate-limits and decides.
event RedeemCode = {
	from: Client,
	type: Reliable,
	call: SingleSync,
	data: (code: string.binary(1..32)),
}

-- Client -> server. Intent only: "claim my daily reward". The server reads its own clock.
event ClaimDailyReward = {
	from: Client,
	type: Reliable,
	call: SingleSync,
	data: (),
}

-- Client -> server. Intent only: the id of a session gift declared in Config.
event ClaimSessionGift = {
	from: Client,
	type: Reliable,
	call: SingleSync,
	data: (giftId: string.binary(1..24)),
}

-- Client -> server. Intent only: a volume choice in percent; the server validates 0..100.
event SetVolume = {
	from: Client,
	type: Reliable,
	call: SingleSync,
	data: (group: VolumeGroup, percent: u8),
}

-- Server -> client. A toast: its kind (text and style come from Config) and a number for {amount}.
event Notify = {
	from: Server,
	type: Reliable,
	call: SingleSync,
	data: (kind: NotificationKind, amount: u32),
}

-- Server -> client. The saved volumes (percent), sent after the data loads and after each change.
event SoundSettings = {
	from: Server,
	type: Reliable,
	call: SingleSync,
	data: (music: u8, sfx: u8),
}

-- Rewarded video ad (opt-in button). Names mirror Config.default.rewardedAds.placements.
type AdPlacementName = enum { "Default" }

-- Client -> server. Intent only: the server picks the reward, checks the cap and plays the ad.
event RequestRewardedAd = {
	from: Client,
	type: Reliable,
	call: SingleSync,
	data: (placement: AdPlacementName),
}

-- Roblox Plus sign-up prompt. Names mirror Config.default.plusPrompt.placements.
type PlusPlacementName = enum { "menu" }

-- Client -> server. Intent only: the player pressed the Plus button at this spot.
event RequestPlusPrompt = {
	from: Client,
	type: Reliable,
	call: SingleSync,
	data: (placement: PlusPlacementName),
}

-- Client -> server. Intent only: who and how much. The platform runs the prompt and the checks.
event RequestRobuxTransfer = {
	from: Client,
	type: Reliable,
	call: SingleSync,
	data: (receiverUserId: f64, amount: u16),
}

-- Private server owner settings. Names mirror Config.default.privateServers.settings.
type PrivateServerSettingName = enum { "maxPlayers" }

-- Client -> server. Intent only: the server checks the owner, the name and the Config bounds.
event RequestPrivateServerSetting = {
	from: Client,
	type: Reliable,
	call: SingleSync,
	data: (setting: PrivateServerSettingName, value: u16),
}

-- Client -> server. Intent only: "check my community membership again". The server decides.
event RequestCommunityCheck = {
	from: Client,
	type: Reliable,
	call: SingleSync,
	data: (),
}
