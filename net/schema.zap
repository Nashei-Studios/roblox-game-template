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
