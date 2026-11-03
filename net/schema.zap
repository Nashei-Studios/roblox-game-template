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
